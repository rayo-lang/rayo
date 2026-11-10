import RayoIR
import RayoSema
import RayoSource

/// The range of every place and computation in the IR a test expects.
let nowhere = SourceRange(SourceLocation(line: 1, column: 1, offset: 0), SourceLocation(line: 1, column: 1, offset: 0))

/// The place of the local at `index`.
func local(_ index: Int) -> Place {
    Place(local: LocalID(index: index), range: nowhere)
}

/// An operand that reads the local at `index`, which keeps its value.
func read(_ index: Int) -> Operand {
    .read(local(index))
}

/// An operand that takes the value of the local at `index`.
func move(_ index: Int) -> Operand {
    .move(local(index))
}

func int(_ value: Int64) -> Operand {
    .constant(.int(value))
}

func bool(_ value: Bool) -> Operand {
    .constant(.bool(value))
}

/// Computes `value` into the local at `destination`, or computes it and drops it where `destination` is nil.
func compute(_ destination: Int?, _ value: Rvalue) -> Statement {
    .compute(destination: destination.map(local), value: value, range: nowhere)
}

func declare(_ index: Int) -> Statement {
    .declare(LocalID(index: index))
}

func block(_ statements: Statement..., then terminator: Terminator) -> BasicBlock {
    BasicBlock(statements: statements, terminator: terminator)
}

func goto(_ index: Int) -> Terminator {
    .goto(BlockID(index: index))
}

func branch(_ condition: Operand, then: Int, otherwise: Int) -> Terminator {
    .branch(condition, then: BlockID(index: then), otherwise: BlockID(index: otherwise))
}
