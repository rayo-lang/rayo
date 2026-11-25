@testable import RayoSema
import RayoSyntax
import Testing

struct TopLevelNamesTests {
    @Test(arguments: [
        ("struct S", TopLevelNames.Kind.type),
        ("func S() {}", .functions),
        ("struct S\nfunc S() {}", .type),
        ("func S() {}\nstruct S", .functions),
        ("func S() {}\nstruct S\nfunc S(_ x: Int) {}", .functions),
        ("struct S\nfunc S() {}\nstruct S", .type),
    ])
    func `a name belongs to the kind, type or function, that declares it first`(
        source: String, kind: TopLevelNames.Kind,
    ) throws {
        #expect(TopLevelNames(of: try parsed(source).file).kind(of: "S") == kind)
    }

    @Test func `a name that no type or function declares belongs to neither`() throws {
        #expect(TopLevelNames(of: try parsed("func f() {}\nstruct T").file).kind(of: "S") == nil)
    }
}
