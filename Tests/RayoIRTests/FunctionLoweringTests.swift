import RayoIR
import RayoSema
import Testing

@Suite("Lowering functions")
struct FunctionLoweringTests {
    @Test func `a call names the function it calls, and passes a constant argument as it is`() throws {
        let source = "func main() {\nlet x = double(3)\n}\nfunc double(_ n: Int) -> Int { n * 2 }"
        try expectLowering(of: source, toMatch: "call")
    }

    @Test func `a borrowed argument is a read access, begun where it is evaluated, which lowering never ends`() throws {
        // The second argument is computed after the first's access begins, and before its own begins.
        let source = """
            func main() {
                let x = 1
                add(x, x + 1, 2)
            }
            func add(_ a: Int, _ b: Int, _ c: Int) {}
            """
        try expectLowering(of: source, toMatch: "borrowed-arguments")
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
        try expectLowering(of: "func main() {}\nfunc seven() -> Int {\nlet x = 7\nreturn x\n}", toMatch: "return-local")
    }

    @Test func `a 'return' of a Void value computes it, and returns nothing`() throws {
        try expectLowering(ofMain: "return print(1)", toMatch: "return-void-value")
    }
}
