import RayoCheckedProgram
import Testing
@testable import RayoSema
import RayoSyntax

/// The names of the functions of the program `source` checks to, and the names of those it holds a body for.
private func checked(_ source: String) -> (declared: [String], withBodies: [String]) {
    let program = Checker.check(Parser.parse(source).file).program
    let ids = program.functions.ids
    return (ids.map { program.functions[$0].name }, ids.filter { program.bodies[$0] != nil }.map {
        program.functions[$0].name
    })
}

struct TaintTests {
    @Test func `a file with errors checks to a program that holds a body for each untainted function alone`() {
        let program = checked("""
            func clean() {}
            func parses() {
                let = 1
            }
            func types() {
                let flag: Bool = 1
            }
            func callsBroken() {
                broken()
                print(1)
            }
            func callsTainted() {
                types()
                print(1)
            }
            func broken( {
            }
            """)
        #expect(program.declared == ["clean()", "parses()", "types()", "callsBroken()", "callsTainted()"])
        #expect(program.withBodies == ["clean()", "callsTainted()"])
    }

    @Test func `an error that leaves a body's meaning whole taints nothing, unless what it is in fails`() {
        let program = checked("""
            func unused() -> Int { 1 }
            func unusedValue() {
                unused()
                print(1)
            }
            func literal() {
                let n: Int = 9223372036854775808
                print(n)
            }
            func index() {
                let a = [1, 2]
                print(copy a[2])
            }
            func noMatch() {
                overloaded(9223372036854775808)
                print(1)
            }
            struct Flag(var on: Bool)
            func overloaded(_ b: Bool) {}
            func overloaded(_ f: Flag) {}
            """)
        #expect(program.withBodies == [
            "unused()", "unusedValue()", "literal()", "index()", "overloaded(_: Bool)", "overloaded(_: Flag)",
        ])
    }

    @Test func `a function whose declaration fails to check keeps its ID, with no declaration`() {
        let program = Checker.check(Parser.parse("func a(_ n: Nope) {}\nfunc b() {}").file).program
        #expect(program.functions.ids.map(\.index) == [1])
        #expect(program.bodies.keys.map(\.index) == [1])
    }

    @Test func `a use of a parameter whose type failed taints the body`() {
        let checker = FileChecker(Parser.parse("func f(n: Nope) {\n    print(n)\n    print(1)\n}").file)
        _ = checker.check()
        #expect(checker.errors.taints.functions == [FunctionID(index: 0)])
    }
}

/// The checker's promise that a body missing a statement is tainted. Every check that fails taints the body it is
/// checked in, so these tests check statements outside any function's body, where an error taints none.
struct UntaintedFailureTests {
    @Test func `a statement left out where no body is tainted stops the compiler`() async throws {
        let exit = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            // A `break` outside a loop fails, and is left out.
            let file = Parser.parse("func main() {\n    break\n}").file
            guard case .function(let main) = file.declarations.first else { return }
            let body = BodyChecker(file: FileChecker(file), parameters: [], declaredAs: [], result: .void)
            _ = body.check(main.body)
        }
        #expect(try stoppedForUntaintedFailure(exit))
    }

    @Test func `a single expression left out where no body is tainted stops the compiler`() async throws {
        let exit = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            // A body whose single expression failed returns nothing.
            let body = BodyChecker(file: FileChecker(Parser.parse("").file), parameters: [], declaredAs: [],
                                   result: .int)
            _ = body.statements(returning: nil)
        }
        #expect(try stoppedForUntaintedFailure(exit))
    }

    /// Whether `exit` is that of a process the checker stopped, for a statement it left out of a body that isn't
    /// tainted.
    private func stoppedForUntaintedFailure(_ exit: ExitTest.Result?) throws -> Bool {
        let message = String(decoding: try #require(exit).standardErrorContent, as: UTF8.self)
        return message.contains("a statement whose check fails is left out only of a tainted body")
    }
}

struct TaintedBodiesTests {
    @Test func `the body being checked is tainted once a check taints it, until its check ends`() {
        let taints = TaintedBodies()
        var tainted: [Bool] = []
        taints.checkingBody(of: FunctionID(index: 0)) {
            tainted.append(taints.isCheckingTaintedBody)
            taints.taint()
            tainted.append(taints.isCheckingTaintedBody)
        }
        tainted.append(taints.isCheckingTaintedBody)
        #expect(tainted == [false, true, false])
    }

    @Test func `of a body checked while another is, only the inner one answers whether it is tainted`() {
        let taints = TaintedBodies()
        var tainted: [Bool] = []
        taints.checkingBody(of: FunctionID(index: 0)) {
            taints.taint()
            taints.checkingBody(of: FunctionID(index: 1)) { tainted.append(taints.isCheckingTaintedBody) }
            tainted.append(taints.isCheckingTaintedBody)
        }
        #expect(tainted == [false, true])
    }
}
