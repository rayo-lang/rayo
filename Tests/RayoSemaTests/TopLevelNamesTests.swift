@testable import RayoSema
import RayoSyntax
import Testing

struct TopLevelNamesTests {
    @Test(arguments: [
        ("struct S", TopLevelNames.Holder.structure),
        ("func S() {}", .functions),
        ("struct S\nfunc S() {}", .structure),
        ("func S() {}\nstruct S", .functions),
        ("func S() {}\nstruct S\nfunc S(_ x: Int) {}", .functions),
        ("struct S\nfunc S() {}\nstruct S", .structure),
    ])
    func `a name belongs to the kind, struct or function, that declares it first`(
        source: String, holder: TopLevelNames.Holder,
    ) {
        #expect(TopLevelNames(of: Parser.parse(source).file).holder(of: "S") == holder)
    }

    @Test func `a name that no struct or function declares belongs to neither`() {
        #expect(TopLevelNames(of: Parser.parse("func f() {}\nstruct T").file).holder(of: "S") == nil)
    }
}
