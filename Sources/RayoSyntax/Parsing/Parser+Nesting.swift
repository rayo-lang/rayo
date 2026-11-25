internal import RayoDiagnostics
internal import RayoSource

/// Counts how many levels deep the parts being parsed nest: expressions and blocks together, and each kind of capped
/// part on its own. A part that nests past its limit is reported.
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

    /// Parses, with `parse`, a part of the kind `part` at its opening bracket, a level deeper than the parts of that
    /// kind it lies in.
    mutating func parseNested<Parsed>(
        _ part: CappedPart, _ parse: (inout Parser) throws(ParseFailure) -> Parsed,
    ) throws(ParseFailure) -> Parsed {
        // A part past its cap is reported at its opening bracket, which stays current, so the part is skipped whole.
        guard cappedDepths[part.rawValue] < part.limit else { throw failTooDeep(past: part.limit, at: current.range) }
        cappedDepths[part.rawValue] += 1
        defer { cappedDepths[part.rawValue] -= 1 }
        return try parse(&self)
    }

    /// Reports a part at `range` that nests past `limit`, and returns the failure to throw.
    private mutating func failTooDeep(past limit: Int, at range: SourceRange) -> ParseFailure {
        report(.nestingTooDeep(limit: limit), at: range)
        return ParseFailure()
    }
}
