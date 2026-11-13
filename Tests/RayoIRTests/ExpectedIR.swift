import RayoIR
import RayoSema
import RayoSource

/// The range of every place and computation in the IR a test expects.
let nowhere = SourceRange(SourceLocation(line: 1, column: 1, offset: 0), SourceLocation(line: 1, column: 1, offset: 0))

/// The place of the field that `fields` lead to, outermost first, inside the local at `index`, or of the whole local
/// where there are none.
func place(_ index: Int, fields: [Int] = []) -> Place {
    Place(root: LocalID(index: index), steps: fields.map(PlaceStep.field))
}

/// An operand that reads the local at `index`, which keeps its value.
func read(_ index: Int) -> Operand {
    .read(place(index), at: nowhere)
}

/// An operand that reads the field that `fields` lead to, outermost first, inside the local at `index`.
func read(_ index: Int, fields: Int...) -> Operand {
    .read(place(index, fields: fields), at: nowhere)
}

/// An operand that takes the value of the local at `index`.
func move(_ index: Int) -> Operand {
    .move(place(index), at: nowhere)
}

/// An operand that takes the value of the field that `fields` lead to, outermost first, inside the local at `index`.
func move(_ index: Int, fields: Int...) -> Operand {
    .move(place(index, fields: fields), at: nowhere)
}

func int(_ value: Int64) -> Operand {
    .constant(.int(value))
}

func bool(_ value: Bool) -> Operand {
    .constant(.bool(value))
}

/// Computes `value` into the local at `destination`, or computes it and drops it where `destination` is nil.
func compute(_ destination: Int?, _ value: Rvalue) -> Statement {
    .compute(destination: destination.map { Destination(place($0), at: nowhere) }, value: value, range: nowhere)
}

/// Computes `value` into the field that `fields` lead to, outermost first, inside the local at `index`.
func compute(_ index: Int, fields: Int..., value: Rvalue) -> Statement {
    .compute(destination: Destination(place(index, fields: fields), at: nowhere), value: value, range: nowhere)
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

/// The body of `main`, with `locals` and `blocks`.
func mainFunction(locals: [IRLocal] = [], _ blocks: BasicBlock...) -> IRBody {
    IRBody(locals: locals, blocks: blocks)
}

func letLocal(_ name: String, _ type: RayoType) -> IRLocal {
    .source(name: name, kind: .let, type: type)
}

func varLocal(_ name: String, _ type: RayoType) -> IRLocal {
    .source(name: name, kind: .var, type: type)
}

func parameter(_ name: String, _ type: RayoType) -> IRLocal {
    .source(name: name, kind: .parameter, type: type)
}
