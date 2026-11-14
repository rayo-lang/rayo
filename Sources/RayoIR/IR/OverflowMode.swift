/// What an integer operation does with a result that its type can't hold.
public enum OverflowMode: Hashable, Sendable, CaseIterable {
    /// Panics where the build checks overflow, and wraps where it doesn't.
    case checked
    /// Wraps in every build.
    case wrapping

    /// The name of the operator spelled `symbol` in this mode, as an error names it, such as `wrapping +`.
    func naming(_ symbol: String) -> String {
        switch self {
        case .checked: symbol
        case .wrapping: "wrapping \(symbol)"
        }
    }
}
