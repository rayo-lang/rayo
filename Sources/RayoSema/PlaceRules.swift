import RayoSource
import RayoSyntax

/// A checked place, and the type of the value it holds.
typealias TypedPlace = (place: CheckedPlace, type: RayoType)

/// What a position asks of a place the source names there, such as one an expression reads or one an assignment
/// changes: which roots it may start from, which fields it may step into, and whether it may name an array's count.
/// Every position may step into an array's element.
protocol PlaceRules {
    /// Checks the expression a place starts from, such as the local `e` in `e.stats.hp`. The flag says whether the
    /// place goes on into a field or an element of it. Returns the start as a place, or nil once it has reported why it
    /// can't be one.
    func root(_ expr: Expr, holdsParts: Bool) -> TypedPlace?

    /// Whether a place may go into a field, reporting why where it may not.
    func admits(_ field: DeclaredField, at nameRange: SourceRange) -> Bool

    /// Whether a place may name an array's count, whose name the source writes at `nameRange`, reporting why where it
    /// may not.
    func admitsCount(at nameRange: SourceRange) -> Bool
}
