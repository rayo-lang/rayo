@testable import RayoSema
import RayoSyntax
import Testing

struct BuiltinTests {
    @Test(arguments: Builtin.allCases)
    func `the prelude declares each built-in under the name a call writes`(builtin: Builtin) {
        var declarations = Declarations(names: TopLevelNames(of: Parser.parse("").file))
        declarations.declarePrelude()

        let callees = declarations.functions(named: builtin.name.spelling).map(\.callee)
        #expect(callees.contains(.builtin(builtin)))
    }

    @Test func `a prelude function is called by its own name`() {
        #expect(BuiltinName.function("print").spelling == "print")
    }

    @Test func `an initializer of a prelude type is declared under the type's name`() {
        var declarations = Declarations(names: TopLevelNames(of: Parser.parse("").file))
        declarations.declarePrelude()

        #expect(declarations.functions(named: "Int").map(\.description) == ["Int(_: UInt)"])
        #expect(declarations.functions(named: "UInt").map(\.description) == ["UInt(_: Int)"])
    }

    @Test(arguments: ["func Int() {}", "struct Int"])
    func `a struct or a function of the file shadows an initializer of a prelude type`(source: String) {
        var declarations = Declarations(names: TopLevelNames(of: Parser.parse(source).file))
        declarations.declarePrelude()

        #expect(declarations.functions(named: "Int").isEmpty)
    }
}
