import RayoSema
import RayoSource

/// Builds one IR body's blocks and locals.
struct FunctionBuilder: ~Copyable {
    /// A block as lowering builds it, which has no terminator until lowering leaves it.
    private struct PendingBlock {
        var statements: [Statement] = []
        var terminator: Terminator?
    }

    private var locals: [IRLocal]
    private var blocks = [PendingBlock()]
    private var current = BlockID(index: 0)

    init(locals: [IRLocal]) {
        self.locals = locals
    }

    /// Makes the IR body of the blocks and locals built so far, every block of which has ended.
    consuming func body() -> IRBody {
        // Each pending block becomes the block it was built as, with its terminator.
        let blocks = blocks.map { block in
            guard let terminator = block.terminator else { preconditionFailure("a block was left unterminated") }
            return BasicBlock(statements: block.statements, terminator: terminator)
        }
        return IRBody(locals: locals, blocks: blocks)
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

    mutating func emit(_ value: Rvalue, into destination: Destination?, range: SourceRange) {
        emit(.compute(destination: destination, value: value, range: range))
    }

    mutating func emit(_ statement: Statement) {
        blocks[current.index].statements.append(statement)
    }

    /// Adds a temporary of `type` to the function, and returns its place.
    mutating func newTemporary(_ type: RayoType) -> Place {
        locals.append(.temporary(type))
        return Place(root: LocalID(index: locals.count - 1))
    }
}
