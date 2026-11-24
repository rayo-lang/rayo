/// What decides whether code may move the value out of a place: the local the place lies in, and whether it lies in
/// an array's element.
package struct MoveSource {
    /// The kind of the local the place lies in, or nil where a temporary holds it.
    package var local: LocalKind?
    /// Whether the place is an array's element, or lies inside one.
    package var liesInElement: Bool

    package init(local: LocalKind?, liesInElement: Bool) {
        self.local = local
        self.liesInElement = liesInElement
    }

    /// Whether code may move the value out of the place, which only code that owns the place may do.
    package var allowsMove: Bool {
        // An element is its array's for as long as the array holds a value, wherever the array lies.
        if liesInElement { return false }

        return switch local {
        // A temporary owns what it holds, and so do a `let`, a `var` and a parameter that owns its argument.
        case nil, .let?, .var?, .parameter(.owned)?: true
        // A `ref let` and a borrowing parameter hold a value that another place owns.
        case .refLet?, .parameter(.borrowed)?, .parameter(.mutable)?: false
        }
    }
}
