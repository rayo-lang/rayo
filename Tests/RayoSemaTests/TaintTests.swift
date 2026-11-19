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

    @Test func `a statement left out of a body that isn't tainted stops the compiler`() async throws {
        let exit = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            // Outside the check of any function's body, the error a `break` outside a loop reports taints no body, so
            // the checker leaves the statement out of a body that isn't tainted.
            let file = Parser.parse("func main() {\n    break\n}").file
            guard case .function(let main) = file.declarations.first else { return }
            let body = BodyChecker(file: FileChecker(file), parameters: [], declaredAs: [], result: .void)
            _ = body.check(main.body)
        }
        let message = String(decoding: try #require(exit).standardErrorContent, as: UTF8.self)
        #expect(message.contains("a statement whose check fails is left out only of a tainted body"))
    }
}
