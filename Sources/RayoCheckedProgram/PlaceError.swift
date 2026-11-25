import RayoDiagnostics

/// An error that a position reports at a place the source writes there bare.
package struct PlaceError: Equatable {
    package var code: ErrorCode
    /// Whether the body keeps its meaning all the same, so the later stages still compile it.
    package var keepsMeaning: Bool

    package init(_ code: ErrorCode, keepsMeaning: Bool = false) {
        self.code = code
        self.keepsMeaning = keepsMeaning
    }
}
