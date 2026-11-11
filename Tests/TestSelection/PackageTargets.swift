/// The targets of a package, as `swift package dump-package` describes them.
public struct PackageTargets: Decodable, Sendable {
    let targets: [Target]

    /// A target: its name, its kind, the directory that holds its sources where it names one, and what it depends on.
    struct Target: Decodable, Sendable {
        let name: String
        let type: String
        let path: String?
        let dependencies: [Dependency]
    }

    /// A target's dependency, on a target of the package or on a product, which `swift package dump-package`
    /// writes as an object with one key, naming the kind, whose value starts with the name.
    struct Dependency: Decodable, Sendable {
        let byName: [String?]?
        let target: [String?]?
        let product: [String?]?

        /// The target of the package depended on, or nil for a product of another package.
        var targetName: String? {
            (byName ?? target)?.first ?? nil
        }
    }

    /// Returns the name of the target whose directory holds `path`, or nil where none does.
    func target(holding path: String) -> String? {
        targets.first { path.hasPrefix(Self.directory(of: $0) + "/") }?.name
    }

    /// Returns the names, in order, of the test targets among `changed`, or that depend on one of them, directly or
    /// through other targets.
    func testTargets(reaching changed: Set<String>) -> [String] {
        let byName = Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0) })
        return targets.filter { $0.type == "test" && Self.reaches($0, changed, in: byName) }.map(\.name).sorted()
    }

    /// Whether `target` is among `changed`, or depends on one of them, directly or through other targets.
    private static func reaches(_ target: Target, _ changed: Set<String>, in byName: [String: Target]) -> Bool {
        // A changed target reaches itself.
        if changed.contains(target.name) { return true }

        // Otherwise it reaches what one of the targets it depends on reaches; SwiftPM allows no cycle among them.
        return target.dependencies.contains { dependency in
            dependency.targetName.flatMap { byName[$0] }.map { reaches($0, changed, in: byName) } ?? false
        }
    }

    /// The directory that holds `target`'s sources: the one it names, or else SwiftPM's default, `Tests/` and its
    /// name for a test target, and `Sources/` and its name for any other.
    private static func directory(of target: Target) -> String {
        target.path ?? (target.type == "test" ? "Tests/" : "Sources/") + target.name
    }
}
