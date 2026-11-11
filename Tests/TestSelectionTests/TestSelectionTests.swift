import Foundation
import Testing
import TestSelection

/// A package laid out as `swift package dump-package` describes one: a chain of source targets, test targets that
/// depend on links of it, and a target at a path of its own.
private let package = try! JSONDecoder().decode(PackageTargets.self, from: Data("""
    {"targets": [
        {"name": "Source", "type": "regular", "dependencies": []},
        {"name": "Syntax", "type": "regular", "dependencies": [{"byName": ["Source", null]}]},
        {"name": "Sema", "type": "regular", "dependencies": [{"target": ["Syntax", null]}]},
        {"name": "Tool", "type": "executable", "path": "Tests/tool", "dependencies": []},
        {"name": "SyntaxTests", "type": "test", "dependencies": [{"byName": ["Syntax", null]}]},
        {"name": "SemaTests", "type": "test",
         "dependencies": [{"byName": ["Sema", null]}, {"product": ["Parser", "other-package", null, null]}]},
        {"name": "ToolTests", "type": "test", "dependencies": [{"byName": ["Tool", null]}]},
        {"name": "Unused", "type": "regular", "dependencies": []}
    ]}
    """.utf8))

struct TestSelectionTests {
    @Test("a change to a test target selects that test target")
    func testTarget() {
        #expect(TestSelection(changedPaths: ["Tests/SyntaxTests/LexerTests.swift"], in: package) ==
            .targets(["SyntaxTests"]))
    }

    @Test("a change to a source target selects each test target that depends on it directly")
    func directDependency() {
        #expect(TestSelection(changedPaths: ["Sources/Sema/Checker.swift"], in: package) == .targets(["SemaTests"]))
    }

    @Test("a change to a source target selects each test target that depends on it through other targets")
    func indirectDependency() {
        #expect(TestSelection(changedPaths: ["Sources/Source/File.swift"], in: package) ==
            .targets(["SemaTests", "SyntaxTests"]))
    }

    @Test("a target at a path of its own is changed by a change under that path")
    func ownPath() {
        #expect(TestSelection(changedPaths: ["Tests/tool/main.swift"], in: package) == .targets(["ToolTests"]))
    }

    @Test("the changes to several targets select the test targets each selects")
    func severalTargets() {
        let changed = ["Tests/tool/main.swift", "Sources/Sema/Checker.swift"]
        #expect(TestSelection(changedPaths: changed, in: package) == .targets(["SemaTests", "ToolTests"]))
    }

    @Test("a change outside every target, such as to the manifest or to CI, selects every test target",
          arguments: ["Package.swift", ".github/workflows/ci.yml", "Tests/Shared.swift", "Sources/SyntaxExtra/A.swift"])
    func outsideTargets(path: String) {
        #expect(TestSelection(changedPaths: ["Sources/Sema/Checker.swift", path], in: package) == .all)
    }

    @Test("a dependency on a platform's condition, or on a product under module aliases, is a dependency all the same")
    func conditionalDependencies() throws {
        let package = try JSONDecoder().decode(PackageTargets.self, from: Data("""
            {"targets": [
                {"name": "Source", "type": "regular", "dependencies": []},
                {"name": "Syntax", "type": "regular", "dependencies": [
                    {"target": ["Source", {"platformNames": ["linux"]}]},
                    {"product": ["Parser", "other-package", {"Parser": "OtherParser"}, {"platformNames": ["macos"]}]}
                ]},
                {"name": "SyntaxTests", "type": "test",
                 "dependencies": [{"byName": ["Syntax", {"platformNames": ["windows"]}]}]}
            ]}
            """.utf8))
        #expect(TestSelection(changedPaths: ["Sources/Source/File.swift"], in: package) == .targets(["SyntaxTests"]))
    }

    @Test("a change that no test target depends on selects none")
    func noTestTarget() {
        #expect(TestSelection(changedPaths: ["Sources/Unused/File.swift"], in: package) == .none)
    }

    @Test("a selection is written as 'all', 'none', or the filter that runs only its test targets' tests",
          arguments: [
              (TestSelection.all, "all"),
              (.none, "none"),
              (.targets(["SemaTests", "SyntaxTests"]), "^(SemaTests|SyntaxTests)\\."),
          ])
    func written(selection: TestSelection, text: String) {
        #expect(selection.description == text)
    }
}
