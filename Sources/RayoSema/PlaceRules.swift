import RayoCheckedProgram
import RayoDiagnostics
import RayoSource
import RayoSyntax

/// A checked place, and the type of the value it holds.
typealias TypedPlace = (place: CheckedPlace, type: RayoType)

/// What a position asks of a place the source names there, such as one an expression reads or one an assignment
/// changes: which roots it may start from, which fields it may step into, and whether a place may hold the value of
/// a value property, such as an array's count. Every position may step into an array's element. A place that a bare
/// name starts is found the same way in every position, and these rules check each step of it.
protocol PlaceRules {
    /// Checks the expression a place starts from where it is no bare name, such as the call in `make().hp`. The flag
    /// says whether the place goes on into a field or an element of it. Returns the start as a place, or nil once it
    /// has reported why it can't be one.
    func root(_ expr: Expr, holdsParts: Bool) -> TypedPlace?

    /// Whether a place may start from `local`, which the source names at `range`, reporting why where it may not. The
    /// flag says whether the place goes on into a field or an element of the local.
    func admits(_ local: LocalID, at range: SourceRange, holdsParts: Bool) -> Bool

    /// The error to report where a place starts from `name`, a bare name that names no place.
    func error(naming nonPlace: NonPlaceName, _ name: String) -> ErrorCode

    /// Whether a place may go into a field, reporting why where it may not.
    func admits(_ field: Field, at nameRange: SourceRange) -> Bool

    /// The place that holds `property`, the value of a value property whose name the source writes at `nameRange`,
    /// where the source names it as a place or goes on from it, as in `copy a.count`. Returns nil once it has reported
    /// why the position can't name it.
    func place(holding property: CheckedExpr, at nameRange: SourceRange) -> TypedPlace?
}
