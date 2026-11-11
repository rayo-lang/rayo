/// The test targets that a run after a change needs.
public enum TestSelection: Equatable, Sendable {
    case all
    case none
    /// The named test targets, in order of name, of which there is at least one.
    case targets([String])

    /// Selects the test targets that the change to `changedPaths`, paths relative to the package's root, reaches in
    /// `package`.
    public init(changedPaths: [String], in package: PackageTargets) {
        // Find the target that each path belongs to.
        var changed: Set<String> = []
        for path in changedPaths {
            // A path in no target's directory, such as the manifest or CI's, can change what any test target does.
            guard let target = package.target(holding: path) else {
                self = .all
                return
            }
            changed.insert(target)
        }

        // A test target is needed where it, or a target it depends on, changed.
        let selected = package.testTargets(reaching: changed)
        self = selected.isEmpty ? .none : .targets(selected)
    }
}

extension TestSelection: CustomStringConvertible {
    /// `all`, `none`, or the regular expression that `swift test --filter` takes to run only the selected test
    /// targets' tests.
    public var description: String {
        switch self {
        case .all: "all"
        case .none: "none"
        case .targets(let names): "^(" + names.joined(separator: "|") + ")\\."
        }
    }
}
