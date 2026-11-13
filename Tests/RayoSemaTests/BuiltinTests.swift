@testable import RayoSema
import RayoSyntax
import Testing

struct BuiltinTests {
    @Test func `a prelude function is called by its own name`() {
        #expect(BuiltinName.function("print").spelling == "print")
    }

    @Test func `an initializer of a prelude type is called by the type's name`() {
        #expect(BuiltinName.initializer(of: .int).spelling == "Int")
    }

    @Test(arguments: Builtin.allCases)
    func `the prelude declares each built-in under the name a call writes`(builtin: Builtin) {
        var declarations = Declarations(names: TopLevelNames(of: SourceFile(functions: [], structs: [])))
        declarations.declarePrelude()

        let callees = declarations.functions(named: builtin.name.spelling).map(\.callee)
        #expect(callees.contains(.builtin(builtin)))
    }
}
