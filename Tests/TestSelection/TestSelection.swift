/// The test targets that a run after a change needs.
public enum TestSelection: Equatable, Sendable {
    case all
    case none
    /// The named test targets, in order of name, of which there is at least one.
    case targets([String])

    /// Selects the test targets that the change to `changedPaths`, paths relative to the package's root, reaches in
    /// `package`.
    public init(changedPaths: [String], in package: PackageTargets) {
        // A path in no target's directory, such as the manifest or CI's, can change what any test target does.
        guard let changed = package.targets(holding: changedPaths) else {
            self = .all
            return
        }

        // `.targets` holds at least one name, so a change that reaches no test target selects none.
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
