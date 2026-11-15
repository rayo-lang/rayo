import Testing
import RayoDiagnostics

struct InitializationTests {
    @Test("a local declared without a value needs a type, and the error covers its name", arguments: [
        ("let x", [ErrorCode.missingLocalType(name: "x")], ["x"]),
        ("var a = 1, b", [.missingLocalType(name: "b")], ["b"]),
        ("let x\nprint(x)\nx = 1", [.missingLocalType(name: "x")], ["x"]),
        ("let x: Int8", [.notAType(name: "Int8")], ["Int8"]),
        ("var x: ()", [.voidLocal(type: "Void")], ["()"]),
        ("let _: Int", [.underscoreDeclared], ["_"]),
    ])
    func needsType(body: String, expected: [ErrorCode], covered: [String]) {
        #expect(codesAndCoverage(inMain: body) == (expected, covered))
    }

    @Test("each binding of a declaration binds a name, and the type of one that binds '_' is still checked",
          arguments: [
        ("let a = 1, _ = 2", [ErrorCode.underscoreDeclared], ["_"]),
        ("var _: Int, b: Int", [.underscoreDeclared], ["_"]),
        ("let _: Int8", [.underscoreDeclared, .notAType(name: "Int8")], ["_", "Int8"]),
    ])
    func underscoreBinding(body: String, expected: [ErrorCode], covered: [String]) {
        #expect(codesAndCoverage(inMain: body) == (expected, covered))
    }

    @Test("a declaration's bindings are declared in order, so an earlier one can't take a later one's value")
    func severalBindings() {
        #expect(errors("func main() {\nlet a = b, b = 1\n}") == [.notDeclared(name: "b")])
    }
}
