internal import RayoDiagnostics
internal import RayoSource

/// Counts how many levels deep the expressions and blocks being parsed nest, and reports a part that nests past the
/// limit.
extension Parser {
    /// Parses, with `parse`, a part one level deeper than the part being parsed, such as an operand or a block.
    mutating func parseNested<Part>(
        _ parse: (inout Parser) throws(ParseFailure) -> Part,
    ) throws(ParseFailure) -> Part {
        // A part that would start past the limit is reported before the parser recurses into it, which bounds the
        // parser's own stack.
        guard depth < Self.nestingLevelLimit else { throw failTooDeep(at: current.range) }
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
    /// from the body or the declaration around it.
    mutating func checkedDepth(_ expression: Expr) throws(ParseFailure) -> Expr {
        let level = depth + expression.levels
        guard level <= Self.nestingLevelLimit else { throw failTooDeep(at: expression.range) }
        deepestLevel = max(deepestLevel, level)
        return expression
    }

    /// Reports a part at `range` that nests past the limit, and returns the failure to throw.
    private mutating func failTooDeep(at range: SourceRange) -> ParseFailure {
        report(.nestingTooDeep(limit: Self.nestingLevelLimit), at: range)
        return ParseFailure()
    }
}
