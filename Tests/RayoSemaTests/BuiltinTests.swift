@testable import RayoSema
import RayoCheckedProgram
import RayoSyntax
import Testing

struct BuiltinTests {
    @Test(arguments: Builtin.allCases)
    func `the prelude gives each built-in where a call finds it, a function by its name and an initializer in its type`(
        builtin: Builtin,
    ) {
        var declarations = Declarations(names: TopLevelNames(of: Parser.parse("").file))
        declarations.declarePrelude()

        let found = if let type = builtin.initializedType {
            initializers(of: type, in: declarations)
        } else {
            declarations.functions(named: builtin.name.spelling)
        }
        let isEachBuiltin = found.allSatisfy(\.isBuiltin)
        #expect(isEachBuiltin)
        #expect(found.map(\.description).contains(Signature(of: builtin).description))
    }

    @Test func `a prelude function is called by its own name`() {
        #expect(BuiltinName.function("print").spelling == "print")
    }

    @Test func `an initializer of a prelude type is a member of the type, and no function`() {
        var declarations = Declarations(names: TopLevelNames(of: Parser.parse("").file))
        declarations.declarePrelude()

        #expect(initializers(of: .int, in: declarations).map(\.description) == ["Int(_: Int)", "Int(_: UInt)"])
        #expect(initializers(of: .uint, in: declarations).map(\.description) == ["UInt(_: Int)", "UInt(_: UInt)"])
        #expect(initializers(of: .bool, in: declarations).isEmpty)
        #expect(declarations.functions(named: "Int").isEmpty)
    }

    @Test func `'print' takes each scalar type`() {
        var declarations = Declarations(names: TopLevelNames(of: Parser.parse("").file))
        declarations.declarePrelude()

        let prints = declarations.functions(named: "print").map(\.description)
        #expect(prints == ["print(_: Int)", "print(_: UInt)", "print(_: Bool)"])
    }

    @Test(arguments: ["func Int() {}", "struct Int"])
    func `a struct or a function of the file shadows a prelude type`(source: String) {
        let declarations = Declarations(names: TopLevelNames(of: Parser.parse(source).file))

        #expect(declarations.preludeType(named: "Int") == nil)
        #expect(declarations.preludeType(named: "UInt") == .uint)
    }
}

/// The initializers that `declarations` gives the prelude type `type` as its members, none where it has none.
private func initializers(of type: RayoType, in declarations: Declarations) -> [Signature] {
    guard case .initializers(.overloads(let initializers))? = declarations.member(named: "init", of: type) else {
        return []
    }
    return initializers
}
