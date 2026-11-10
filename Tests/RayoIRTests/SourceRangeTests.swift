import RayoIR
import RayoSource
import Testing

@Suite("Lowering keeps source ranges")
struct SourceRangeTests {
    @Test("an operation and its temporary keep the range of the expression, and an operand the range of its local")
    func operationRanges() throws(RejectedSource) {
        let source = "func main() {\n    let a = 7\n    print(a / 0)\n}"
        let main = try loweredWithRanges(source).functions[0]

        // The division is the third statement, after the declaration and its value, and computes into a temporary.
        guard case .compute(let temporary?, .binary(.divide, .read(let dividend), _), let range)
            = main.blocks[0].statements[2]
        else {
            Issue.record("the division isn't the third statement of \(main.blocks[0])")
            return
        }
        #expect(text(of: range, in: source) == "a / 0")
        #expect(text(of: temporary.range, in: source) == "a / 0")
        #expect(text(of: dividend.range, in: source) == "a")
    }

    @Test func `a declaration and an assignment keep the range of their value`() throws(RejectedSource) {
        let source = "func main() {\n    var x = 1 + 2\n    x = 3\n}"
        let main = try loweredWithRanges(source).functions[0]

        // The declaration's value follows its `declare`, and the assignment follows that.
        guard case .compute(let declared?, .binary(.add, _, _), let declarationRange) = main.blocks[0].statements[1],
              case .compute(let assigned?, .use, let assignmentRange) = main.blocks[0].statements[2]
        else {
            Issue.record("the declaration and the assignment aren't statements 2 and 3 of \(main.blocks[0])")
            return
        }
        #expect(text(of: declarationRange, in: source) == "1 + 2")
        #expect(text(of: declared.range, in: source) == "x")
        #expect(text(of: assignmentRange, in: source) == "3")
        #expect(text(of: assigned.range, in: source) == "x")
    }

    @Test func `a compound assignment keeps the range of its local's name`() throws(RejectedSource) {
        let source = "func main() {\n    var x = 0\n    x += 1\n}"
        let main = try loweredWithRanges(source).functions[0]

        // The compound assignment is the third statement, after the declaration and its value.
        guard case .compute(let destination?, .binary(.add, .read(let operand), _), let range)
            = main.blocks[0].statements[2]
        else {
            Issue.record("the compound assignment isn't the third statement of \(main.blocks[0])")
            return
        }
        #expect(text(of: range, in: source) == "x")
        #expect(text(of: destination.range, in: source) == "x")
        #expect(text(of: operand.range, in: source) == "x")
    }

    @Test func `a '&&' and its temporary keep the range of the whole '&&'`() throws(RejectedSource) {
        let source = "func main() {\n    let a = true\n    let b = a && false\n}"
        let main = try loweredWithRanges(source).functions[0]

        // The `&&` computes `a` into its temporary after the two declarations and `a`'s value, and its right operand
        // into the same temporary, first in the block that evaluates it.
        guard case .compute(let temporary?, .use, let leftRange) = main.blocks[0].statements[3],
              case .compute(_, .use, let rightRange) = main.blocks[1].statements[0]
        else {
            Issue.record("the '&&' doesn't compute its operands where it should in \(main)")
            return
        }
        #expect(text(of: temporary.range, in: source) == "a && false")
        #expect(text(of: leftRange, in: source) == "a && false")
        #expect(text(of: rightRange, in: source) == "a && false")
    }

    @Test(
        "a branch tests an operand with the range of its condition, whether a temporary or a local holds it",
        arguments: [
            (body: "let a = 1\n    if a == 0 {}", condition: "a == 0"),
            (body: "let c = true\n    if c {}", condition: "c"),
        ],
    )
    func branchConditionRange(body: String, condition: String) throws(RejectedSource) {
        let source = "func main() {\n    \(body)\n}"
        let main = try loweredWithRanges(source).functions[0]

        // The first block branches on the condition, which it reads from a temporary or from the local itself.
        guard case .branch(.read(let place), _, _) = main.blocks[0].terminator else {
            Issue.record("the first block of \(main) doesn't branch on a local")
            return
        }
        #expect(text(of: place.range, in: source) == condition)
    }

    @Test(
        "a 'return' leaves with an operand with the range of its value, whether a temporary or a local holds it",
        arguments: [
            (body: "return n * 2", value: "n * 2"),
            (body: "let x = copy n\n    return x", value: "x"),
        ],
    )
    func returnedValueRange(body: String, value: String) throws(RejectedSource) {
        let source = "func main() {}\nfunc result(_ n: Int) -> Int {\n    \(body)\n}"
        let result = try loweredWithRanges(source).functions[1]

        // The first block returns the value, which it reads from a temporary or moves out of the local.
        guard case .return(let operand?) = result.blocks[0].terminator, let place = operand.place else {
            Issue.record("the first block of \(result) doesn't return a local")
            return
        }
        #expect(text(of: place.range, in: source) == value)
    }
}

/// The text of `source` that `range` covers.
private func text(of range: SourceRange, in source: String) -> String {
    let bytes = Array(source.utf8)[range.start.offset..<range.end.offset]
    return String(decoding: bytes, as: UTF8.self)
}

private extension Operand {
    /// The place of the local the operand reads or moves, or nil for a constant.
    var place: Place? {
        switch self {
        case .read(let place), .move(let place): place
        case .constant: nil
        }
    }
}
