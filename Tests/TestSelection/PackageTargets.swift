/// The targets of a package, as `swift package dump-package` describes them.
public struct PackageTargets: Decodable, Sendable {
    let targets: [Target]

    /// A target, as much of it as decides which targets a change reaches.
    struct Target: Decodable, Sendable {
        let name: String
        let type: String
        /// The directory that holds the target's sources, where the manifest names one.
        let path: String?
        let dependencies: [Dependency]

        var isTest: Bool { type == "test" }
    }

    /// A target's dependency, on a target of the package or on a product, which `swift package dump-package`
    /// writes as an object with one key, naming the kind, whose value is an array that starts with the name.
    struct Dependency: Decodable, Sendable {
        /// The name of the target of the package depended on, or nil for a product.
        let targetName: String?

        init(from decoder: any Decoder) throws {
            // A product is another package's, so it names no target of this one.
            let container = try decoder.container(keyedBy: Kind.self)
            guard let kind = [Kind.byName, .target].first(where: container.contains) else {
                targetName = nil
                return
            }

            // The name comes first; a condition on the platform may follow it, which still depends on the target.
            var values = try container.nestedUnkeyedContainer(forKey: kind)
            targetName = try values.decode(String.self)
        }

        /// The kinds of dependency that name a target of the package by name.
        private enum Kind: String, CodingKey {
            case byName
            case target
        }
    }

    /// Returns the names of the targets whose directories hold `paths`, or nil where a path is in none.
    func targets(holding paths: [String]) -> Set<String>? {
        var names: Set<String> = []
        for path in paths {
            // A path in no target's directory has no target to name.
            guard let target = targets.first(where: { path.hasPrefix(Self.directory(of: $0) + "/") }) else {
                return nil
            }
            names.insert(target.name)
        }
        return names
    }

    /// Returns the names, in order, of the test targets that reach one of `changed`.
    func testTargets(reaching changed: Set<String>) -> [String] {
        let targetsByName = Dictionary(uniqueKeysWithValues: targets.map { ($0.name, $0) })
        return targets.filter { $0.isTest && Self.reaches($0, changed, in: targetsByName) }.map(\.name).sorted()
    }

    /// Whether `target` is one of `changed`, or depends on one of them by name, directly or through other targets.
    private static func reaches(_ target: Target, _ changed: Set<String>, in targetsByName: [String: Target]) -> Bool {
        // A changed target reaches itself.
        if changed.contains(target.name) { return true }

        // Otherwise it reaches what one of the targets it depends on reaches; SwiftPM allows no cycle among them.
        return target.dependencies.contains { dependency in
            // A product, or a name that is no target's, is another package's, which no change here reaches.
            guard let name = dependency.targetName, let dependee = targetsByName[name] else { return false }
            return reaches(dependee, changed, in: targetsByName)
        }
    }

    /// The directory that holds `target`'s sources: the one it names, or else SwiftPM's default, `Tests/` and its
    /// name for a test target, and `Sources/` and its name for any other.
    private static func directory(of target: Target) -> String {
        target.path ?? (target.isTest ? "Tests/" : "Sources/") + target.name
    }
}
