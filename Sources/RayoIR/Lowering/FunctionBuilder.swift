import RayoSema
import RayoSource

/// Builds one IR function: the blocks of its control-flow graph, the block that lowering adds statements to, and
/// the temporaries it adds to the function's locals.
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

    /// The IR function these blocks make of `checked`.
    consuming func function(lowering checked: CheckedFunction) -> IRFunction {
        let blocks = blocks.map { block in
            // Lowering ends every block before it makes the function.
            guard let terminator = block.terminator else { preconditionFailure("a block was left unterminated") }
            return BasicBlock(statements: block.statements, terminator: terminator)
        }
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

    /// Adds a temporary of `type` to the function, and returns its place, whose range is that of the expression it
    /// holds.
    mutating func newTemporary(_ type: RayoType, at range: SourceRange) -> Place {
        locals.append(.temporary(type))
        return Place(local: LocalID(index: locals.count - 1), range: range)
    }
}
