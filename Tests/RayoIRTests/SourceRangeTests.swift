import RayoIR
import RayoSource
import Testing

@Suite("Lowering keeps source ranges")
struct SourceRangeTests {
    @Test("an operation and its temporary keep the range of the expression, and an operand the range of its local")
    func operationRanges() throws(RejectedSource) {
        let source = "func main() {\n    let a = 7\n    print(a / 0)\n}"
        let main = try lowered(source).body(at: 0)

        // The division is the third statement, after the declaration and its value, and computes into a temporary.
        guard case .compute(let temporary?, .binary(.divide(.checked), .read(_, let dividend), _), let range)
            = main.blocks[0].statements[2]
        else {
            Issue.record("the division isn't the third statement of \(main.blocks[0])")
            return
        }
        #expect(text(of: range, in: source) == "a / 0")
        #expect(text(of: temporary.range, in: source) == "a / 0")
        #expect(text(of: dividend, in: source) == "a")
    }

    @Test func `a declaration and an assignment keep the range of their value`() throws(RejectedSource) {
        let source = "func main() {\n    var x = 1 + 2\n    x = 3\n}"
        let main = try lowered(source).body(at: 0)

        // The declaration's value follows its `declare`, and the assignment follows that.
        let statements = main.blocks[0].statements
        guard case .compute(let declared?, .binary(.add(.checked), _, _), let declarationRange) = statements[1],
              case .compute(let assigned?, .use, let assignmentRange) = statements[2]
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
        let main = try lowered(source).body(at: 0)

        // The compound assignment is the third statement, after the declaration and its value.
        guard case .compute(let destination?, .binary(.add(.checked), .read(_, let operand), _), let range)
            = main.blocks[0].statements[2]
        else {
            Issue.record("the compound assignment isn't the third statement of \(main.blocks[0])")
            return
        }
        #expect(text(of: range, in: source) == "x")
        #expect(text(of: destination.range, in: source) == "x")
        #expect(text(of: operand, in: source) == "x")
    }

    @Test func `a '&&' and its temporary keep the range of the whole '&&'`() throws(RejectedSource) {
        let source = "func main() {\n    let a = true\n    let b = a && false\n}"
        let main = try lowered(source).body(at: 0)

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

    @Test func `two uses of one place name one place, each at the range of its own use`() throws(RejectedSource) {
        let source = """
            func main() {
                let e = Enemy(hp: 1)
                print(e.hp)
                print(e.hp)
            }
            struct Enemy(let hp: Int)
            """
        let main = try lowered(source).body(at: 0)

        // The two prints follow the declaration and its value, and each reads `e.hp` where it lies.
        guard case .compute(nil, .call(_, let firstArguments), _) = main.blocks[0].statements[2],
              case .compute(nil, .call(_, let secondArguments), _) = main.blocks[0].statements[3],
              case .read(let first, let firstRange) = firstArguments.first,
              case .read(let second, let secondRange) = secondArguments.first
        else {
            Issue.record("the two prints don't read a place as statements 3 and 4 of \(main.blocks[0])")
            return
        }
        #expect(first == second)
        #expect(Set([first, second]).count == 1)
        #expect(text(of: firstRange, in: source) == "e.hp")
        #expect(firstRange != secondRange)
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
        let main = try lowered(source).body(at: 0)

        // The first block branches on the condition, which it reads from a temporary or from the local itself.
        guard case .branch(.read(_, let range), _, _) = main.blocks[0].terminator else {
            Issue.record("the first block of \(main) doesn't branch on a local")
            return
        }
        #expect(text(of: range, in: source) == condition)
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
        let result = try lowered(source).body(at: 1)

        // The first block returns the value, which it reads from a temporary or moves out of the local.
        guard case .return(let operand?) = result.blocks[0].terminator, let range = operand.range else {
            Issue.record("the first block of \(result) doesn't return a local")
            return
        }
        #expect(text(of: range, in: source) == value)
    }
}

/// The text of `source` that `range` covers.
private func text(of range: SourceRange, in source: String) -> String {
    let bytes = Array(source.utf8)[range.start.offset..<range.end.offset]
    return String(decoding: bytes, as: UTF8.self)
}

private extension Operand {
    /// Where the source names the place the operand reads or moves, or nil for a constant.
    var range: SourceRange? {
        switch self {
        case .read(_, let range), .move(_, let range): range
        case .constant: nil
        }
    }
}
