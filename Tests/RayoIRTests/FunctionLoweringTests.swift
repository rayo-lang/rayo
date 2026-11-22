import RayoCheckedProgram
import RayoIR
import RayoSema
import RayoSyntax
import SnapshotTesting
import Testing

@Suite("Lowering functions")
struct FunctionLoweringTests {
    @Test func `a call names the function it calls, and passes a constant argument as it is`() throws {
        let source = "func main() {\nlet x = double(3)\n}\nfunc double(_ n: Int) -> Int { n * 2 }"
        try expectLowering(of: source, toMatch: "call")
    }

    @Test func `a borrowed argument is a read access, begun as the call begins, which lowering never ends`() throws {
        // Both arguments are computed before either access begins, and the accesses begin in their order.
        let source = """
            func main() {
                let x = 1
                add(&x, x + 1, 2)
            }
            func add(_ a: &Int, _ b: &Int, _ c: &Int) {}
            """
        try expectLowering(of: source, toMatch: "borrowed-arguments")
    }

    @Test func `a mutable argument is a modify access to the place it names, begun as the call begins`() throws {
        // Checking rejects a `mutable &` parameter that the source writes, so the test makes `bump`'s parameter
        // mutable in the checked program, and passes `x` to it as a mutable place.
        let source = "func main() {\n    var x = 1\n    bump(&x)\n    print(x)\n}\nfunc bump(_ n: &Int) {}"
        let (file, _) = Parser.parse(source)
        var checked = Checker.check(file).program
        let bump = FunctionID(index: 1)
        checked.functions = checked.functions.changingFirstParameter(of: bump, to: .mutable)
        checked.bodies[bump]?.locals[0].kind = .parameter(.mutable)
        let main = try #require(checked.bodies[FunctionID(index: 0)])
        checked.bodies[FunctionID(index: 0)]?.statements[1] = try passingMutablePlace(main.statements[1])

        let program = Lowering.lower(checked)
        Snapshot("mutable-argument.ir").expect(IRPrinter.text(of: program))
        #expect(IRVerifier.verify(program, from: .lowering) == nil)
    }

    @Test func `a copied argument is made in a temporary where the source writes it, and the call borrows that`()
        throws {
        // The copied local is read once, for the copy, and the call borrows only the local it lends.
        let source = """
            func main() {
                let x = 1
                add(copy x, &x)
            }
            func add(_ a: &Int, _ b: &Int) {}
            """
        try expectLowering(of: source, toMatch: "copied-argument")
    }

    @Test func `a copy is made before a later operand or argument changes the place it copies`() throws {
        // Each `if` assigns the copied place, after the copy, so the copy holds the value from before; the value
        // assigned to `x` is never read.
        let source = """
            func main() {
                var x = 1
                let y = (copy x) + if true { x = 10; 1 } else { 2 }
                print(y)
                var p = P(hp: 1)
                show(copy p, if true { p.hp = 7; 0 } else { 0 })
                print(p.hp)
            }
            func show(_ a: &P, _ b: Int) {}
            struct P(var hp: Int)
            """
        try expectLowering(of: source, toMatch: "copy-before-change")
    }

    @Test func `a call's arguments are computed left to right, each into its temporary, before the call`() throws {
        let source = """
            func main() { pair(shown(1), shown(2)) }
            func pair(_ a: Int, _ b: Int) {}
            func shown(_ n: Int) -> Int { copy n }
            """
        try expectLowering(of: source, toMatch: "computed-arguments")
    }

    @Test func `the program's table declares each function, by its ID in source order`() throws {
        try expectLowering(of: "func main() {}\nfunc double(_ n: Int, by: Bool) -> Int { n * 2 }", toMatch: "functions")
    }

    @Test func `a function without a body keeps its ID, and leaves no gap among the bodies`() throws {
        // Declare a function that has no body, and a `main` after it that has one.
        var functions = FunctionTable()
        let declaration = FunctionDeclaration(name: "f()", parameters: [], result: .void, kind: .written)
        let bodiless = functions.declare(declaration)
        let main = functions.declare(FunctionDeclaration(name: "main()", parameters: [], result: .void, kind: .written))
        let checked = CheckedProgram(types: .empty, functions: functions,
                                     bodies: [main: CheckedBody(locals: [], statements: [])], main: main)

        // Lowering keeps both declarations and their IDs, and lowers the one body there is.
        let program = Lowering.lower(checked)
        #expect([bodiless, main] == [FunctionID(index: 0), FunctionID(index: 1)])
        #expect(program == (try IRParser.program(from: """
            main "main()"
            func "f()"() -> Void
            func "main()"() -> Void {
            bb0:
              return
            }
            """)))
        #expect(program.definedFunctions.map(\.id) == [main])
    }

    @Test func `a function's parameters are its first locals, ahead of its temporaries`() throws {
        try expectLowering(of: "func main() {}\nfunc double(_ n: Int) -> Int { n * 2 }", toMatch: "parameters")
    }

    @Test func `a function returns a Bool result as it returns an Int one`() throws {
        try expectLowering(of: "func main() {}\nfunc isZero(_ n: Int) -> Bool { n == 0 }", toMatch: "bool-result")
    }

    @Test func `a 'return' of a local moves its value out as the result`() throws {
        let source = """
            func main() {}
            func made() -> Stats {
                let s = Stats(hp: 7)
                return s
            }
            struct Stats(let hp: Int)
            """
        try expectLowering(of: source, toMatch: "return-local")
    }

    @Test func `a body's one expression, and a 'return' of a field, move their place out as the result`() throws {
        let source = """
            func main() {}
            func given(_ s: &Stats) -> Stats { s }
            func stats(_ e: &Enemy) -> Stats {
                let f = copy e
                return f.stats
            }
            struct Stats(let hp: Int)
            struct Enemy(let stats: Stats)
            """
        try expectLowering(of: source, toMatch: "returned-places")
    }

    @Test func `a 'return' of a Void value computes it, and returns nothing`() throws {
        try expectLowering(ofMain: "return print(1)", toMatch: "return-void-value")
    }
}

/// `statement`, an expression statement that calls a function with one argument, a place passed borrowed, with the
/// place passed as a mutable one instead.
private func passingMutablePlace(_ statement: CheckedStmt) throws -> CheckedStmt {
    guard case .expression(var call) = statement, case .call(let callee, let arguments) = call.kind,
          case .borrowed(let value) = try #require(arguments.first), case .place(let place) = value.kind
    else { throw ChangeFailure() }
    call.kind = .call(callee, arguments: [.mutable(place)])
    return .expression(call)
}

/// What a test throws where the checked program isn't shaped as it expects.
private struct ChangeFailure: Error {}

private extension FunctionTable {
    /// The table with the first parameter of the function `id` taking its argument as `convention`.
    func changingFirstParameter(of id: FunctionID, to convention: ParameterConvention) -> FunctionTable {
        var changed = FunctionTable()
        for declared in ids {
            var declaration = self[declared]
            if declared == id { declaration.parameters[0].convention = convention }
            _ = changed.declare(declaration)
        }
        return changed
    }
}
