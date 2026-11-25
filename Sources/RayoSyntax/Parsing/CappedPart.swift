/// A kind of part whose nesting is counted on its own, apart from expressions and blocks, against a cap of its own.
package enum CappedPart {
    /// A struct's body, each struct body inside another a level.
    case structBody
    /// An array type, each array type that is another's element a level: one the source writes, which the parser
    /// counts, or one the checker gives an array literal from its elements.
    case arrayType

    /// How many levels deep a part of this kind may nest. Real code writes these a few levels deep. The cap bounds how
    /// deep the parser and the checker recurse through them, and the checker's work of laying out each level of an
    /// array type anew.
    package var limit: Int { 64 }
}
