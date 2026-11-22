import Testing
import RayoSyntax

/// The kind of `declaration` and the name it reached, as `struct S`, `func f` or `failed func`.
private func summary(of declaration: Declaration) -> String {
    let name = declaration.name.map { " \($0)" } ?? ""
    return switch declaration {
    case .function: "func" + name
    case .structure: "struct" + name
    case .failed(let failed): (failed.kind == .function ? "failed func" : "failed struct") + name
    }
}

struct DeclarationTests {
    @Test func `a file keeps its declarations in source order, the failed ones among them`() {
        let file = Parser.parse("struct A\nfunc f() {}\nstruct B(var 1)\nfunc h(x) {}\nfunc g() {}\nstruct C").file
        #expect(file.declarations.map(summary(of:)) == [
            "struct A", "func f", "failed struct B", "failed func h", "func g", "struct C",
        ])
    }

    @Test func `a struct's body holds its members in source order, the failed ones among them`() throws {
        let file = Parser.parse("struct S {\n    func f() {}\n    struct T\n    func g(x) {}\n}").file
        guard case .structure(let structure)? = file.declarations.first else {
            Issue.record("expected a struct, found \(file.declarations)")
            return
        }
        #expect(structure.members.map(summary(of:)) == ["func f", "struct T", "failed func g"])
    }

    @Test func `a parameter's type says whether it borrows its argument, borrows it for change, or owns it`() throws {
        let file = Parser.parse("func f(_ a: &Int, b: mutable &[2 of Int], c: Bool) {}").file
        guard case .function(let function)? = file.declarations.first else {
            Issue.record("expected a function, found \(file.declarations)")
            return
        }
        #expect(function.parameters.map(\.convention) == [.borrowed, .mutable, nil])
        #expect(function.parameters.map(\.type.spelling) == ["Int", "[2 of Int]", "Bool"])
        #expect(function.parameters.map(\.spelledType) == ["&Int", "mutable &[2 of Int]", "Bool"])
    }

    @Test(arguments: [
        ("struct S", true), ("struct S(var x)", true), ("struct", true), ("func f() {}", false), ("func (", false),
    ])
    func `a struct declares a type, and a function doesn't, whether or not it parsed`(
        source: String, declaresType: Bool,
    ) throws {
        let declaration = try #require(Parser.parse(source).file.declarations.first)
        #expect(declaration.declaresType == declaresType)
    }
}
