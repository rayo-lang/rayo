import RayoDiagnostics

/// A place that the source writes bare in a position, as the position needs it to decide what it does with the place:
/// the type of the value it holds, where it lies, and how an error names it.
package struct GivenPlace {
    package var type: RayoType
    /// Where the place lies, which decides whether code may move the value out of it. Its local is nil where the place
    /// lies in a temporary, a value that no local holds.
    package var source: MoveSource
    /// The place as the source writes it, such as `boss` or `e.stats`, for an error that names it.
    package var spelling: () -> String
    /// The place's type as an error names it.
    package var typeName: () -> TypeName

    package init(type: RayoType, source: MoveSource, spelling: @escaping () -> String,
                 typeName: @escaping () -> TypeName) {
        self.type = type
        self.source = source
        self.spelling = spelling
        self.typeName = typeName
    }

    /// What a statement writes before the place to drop its value: `_ =` alone where that copies the value, and
    /// otherwise `_ = consume` where code may move the value out of the place, and `_ = copy` where it can't.
    package var dropMark: DropMark {
        guard Position.drop.taking(self).error != nil else { return .bare }
        return source.allowsMove ? .consume : .copy
    }
}
