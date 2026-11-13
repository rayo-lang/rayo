import RayoSource
import RayoSyntax

/// A checked place, and the type of the value it holds.
typealias TypedPlace = (place: CheckedPlace, type: RayoType)

/// What a position asks of a place the source names there, such as one an expression reads or one an assignment
/// changes: which roots it may start from, and which fields it may step into.
protocol PlaceRules {
    /// Checks `expr` as the root of a place, which holds the fields the source steps into when `holdsFields` is true.
    /// Returns the root as a place, or nil where it can't be one, which was reported.
    func root(_ expr: Expr, holdsFields: Bool) -> TypedPlace?

    /// Whether a place may step into `field`, which the source names at `nameRange`, reporting it where it can't.
    func admits(_ field: DeclaredField, at nameRange: SourceRange) -> Bool
}
