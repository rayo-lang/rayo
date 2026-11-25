internal import RayoDiagnostics
internal import RayoSource

/// Counts how many levels deep the parts being parsed nest: expressions and blocks together, and struct bodies and
/// array types each on their own. A part that nests past its limit is reported.
extension Parser {
    /// Parses, with `parse`, a part one level deeper than the part being parsed, such as an operand or a block.
    mutating func parseNested<Part>(
        _ parse: (inout Parser) throws(ParseFailure) -> Part,
    ) throws(ParseFailure) -> Part {
        // A part that would start past the limit is reported before the parser recurses into it, which bounds the
        // parser's own stack.
        guard depth < Self.nestingLevelLimit else { throw failTooDeep(past: Self.nestingLevelLimit, at: current.range) }
        depth += 1
        defer { depth -= 1 }
        deepestLevel = max(deepestLevel, depth)
        return try parse(&self)
    }

    /// Parses a block that lies a level deeper than the part being parsed, as the blocks of an `if` and a loop's
    /// body do.
    mutating func parseNestedBlock() throws(ParseFailure) -> Block {
        try parseNested { parser throws(ParseFailure) in try parser.parseBlock() }
    }

    /// `expression`, which the parser has just built, once it is known to nest no deeper than the limit, counted
    /// from the function body or the declaration around it.
    mutating func checkedDepth(_ expression: Expr) throws(ParseFailure) -> Expr {
        let level = depth + expression.levels
        guard level <= Self.nestingLevelLimit else {
            throw failTooDeep(past: Self.nestingLevelLimit, at: expression.range)
        }
        deepestLevel = max(deepestLevel, level)
        return expression
    }

    /// Parses, with `parse`, a struct's body at its `{`, one level deeper than the struct body it lies in, if any.
    mutating func parseNestedStructBody<Body>(
        _ parse: (inout Parser) throws(ParseFailure) -> Body,
    ) throws(ParseFailure) -> Body {
        // A body past the limit is reported at its `{`, which stays current, so the body is skipped whole.
        guard structBodyDepth < Self.structBodyLevelLimit else {
            throw failTooDeep(past: Self.structBodyLevelLimit, at: current.range)
        }
        structBodyDepth += 1
        defer { structBodyDepth -= 1 }
        return try parse(&self)
    }

    /// Parses, with `parse`, an array type at its `[`, one level deeper than the array type whose element it is, if
    /// any.
    mutating func parseNestedArrayType(
        _ parse: (inout Parser) throws(ParseFailure) -> TypeExpr,
    ) throws(ParseFailure) -> TypeExpr {
        // An array type past the limit is reported at its `[`, which stays current, so the type is skipped whole.
        guard arrayTypeDepth < Self.arrayTypeLevelLimit else {
            throw failTooDeep(past: Self.arrayTypeLevelLimit, at: current.range)
        }
        arrayTypeDepth += 1
        defer { arrayTypeDepth -= 1 }
        return try parse(&self)
    }

    /// Reports a part at `range` that nests past `limit`, and returns the failure to throw.
    private mutating func failTooDeep(past limit: Int, at range: SourceRange) -> ParseFailure {
        report(.nestingTooDeep(limit: limit), at: range)
        return ParseFailure()
    }
}
