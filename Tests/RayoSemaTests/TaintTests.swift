import Testing
import RayoSema
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

    @Test func `a function whose declaration fails to check keeps its ID, with no declaration`() {
        let program = Checker.check(Parser.parse("func a(_ n: Nope) {}\nfunc b() {}").file).program
        #expect(program.functions.ids.map(\.index) == [1])
        #expect(program.bodies.keys.map(\.index) == [1])
    }
}
