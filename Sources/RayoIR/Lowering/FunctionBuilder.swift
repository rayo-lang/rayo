import RayoSema
import RayoSource

/// Builds one IR function's blocks and locals, and keeps the loops around the block it is building.
struct FunctionBuilder: ~Copyable {
    /// A block as lowering builds it, which has no terminator until lowering leaves it.
    private struct PendingBlock {
        var statements: [Statement] = []
        var terminator: Terminator?
    }

    /// The blocks that a `continue` and a `break` in a loop's body go to.
    struct Loop {
        var header: BlockID
        var exit: BlockID
    }

    private var locals: [IRLocal]
    private var blocks = [PendingBlock()]
    private var current = BlockID(index: 0)
    /// The loops around the current block, innermost last.
    private var loops: [Loop] = []

    init(locals: [IRLocal]) {
        self.locals = locals
    }

    /// Makes the IR function of `checked` from the blocks and locals built so far, every block of which has ended.
    consuming func function(of checked: CheckedFunction) -> IRFunction {
        // Each pending block becomes the block it was built as, with its terminator.
        let blocks = blocks.map { block in
            guard let terminator = block.terminator else { preconditionFailure("a block was left unterminated") }
            return BasicBlock(statements: block.statements, terminator: terminator)
        }

        // Put those blocks and the locals under `checked`'s header.
        return IRFunction(
            name: checked.name, parameterCount: checked.parameterCount, result: checked.result,
            locals: locals, blocks: blocks,
        )
    }

    mutating func newBlock() -> BlockID {
        blocks.append(PendingBlock())
        return BlockID(index: blocks.count - 1)
    }

    /// Ends the current block with `terminator`.
    mutating func end(with terminator: Terminator) {
        blocks[current.index].terminator = terminator
    }

    /// Ends the current block with `terminator`, and continues in `next`.
    mutating func end(with terminator: Terminator, continuingIn next: BlockID) {
        end(with: terminator)
        current = next
    }

    mutating func emit(_ value: Rvalue, into destination: Place?, range: SourceRange) {
        emit(.compute(destination: destination, value: value, range: range))
    }

    mutating func emit(_ statement: Statement) {
        blocks[current.index].statements.append(statement)
    }

    /// The loop that a `break` or a `continue` belongs to, which the checker allows only inside one.
    var innermostLoop: Loop {
        loops[loops.count - 1]
    }

    /// Starts the body of `loop`, which is the innermost loop until `leaveLoop()`.
    mutating func enterLoop(_ loop: Loop) {
        loops.append(loop)
    }

    mutating func leaveLoop() {
        loops.removeLast()
    }

    /// Adds a temporary of `type` to the function, and returns its place at `range`.
    mutating func newTemporary(_ type: RayoType, at range: SourceRange) -> Place {
        locals.append(.temporary(type))
        return Place(local: LocalID(index: locals.count - 1), range: range)
    }
}
