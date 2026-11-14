import RayoSource
import RayoSyntax

/// A checked place, and the type of the value it holds.
typealias TypedPlace = (place: CheckedPlace, type: RayoType)

/// What a position asks of a place the source names there, such as one an expression reads or one an assignment
/// changes: which roots it may start from, and which fields and elements it may step into.
protocol PlaceRules {
    /// Checks the expression a place starts from, such as the local `e` in `e.stats.hp`. The flag says whether the
    /// place goes on into a field of it. Returns the start as a place, or nil once it has reported why it can't be one.
    func root(_ expr: Expr, holdsFields: Bool) -> TypedPlace?

    /// Whether a place may go into a field, reporting why where it may not.
    func admits(_ field: DeclaredField, at nameRange: SourceRange) -> Bool

    /// Whether a place may go into an array's element, which the source names at `range`, reporting why where it may
    /// not.
    func admitsElement(at range: SourceRange) -> Bool
}
