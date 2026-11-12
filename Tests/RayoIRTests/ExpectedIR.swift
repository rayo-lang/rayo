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

/// An operand that reads the field that `fields` lead to, outermost first, inside the local at `index`.
func read(_ index: Int, fields: Int...) -> Operand {
    .read(Place(local: LocalID(index: index), fields: fields, range: nowhere))
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

/// Computes `value` into the field that `fields` lead to, outermost first, inside the local at `index`.
func compute(_ index: Int, fields: Int..., value: Rvalue) -> Statement {
    .compute(destination: Place(local: LocalID(index: index), fields: fields, range: nowhere), value: value,
             range: nowhere)
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

/// `main`, which takes no parameters and gives no result, with `locals` and `blocks`.
func mainFunction(locals: [IRLocal] = [], _ blocks: BasicBlock...) -> IRFunction {
    IRFunction(name: "main()", parameterCount: 0, result: .void, locals: locals, blocks: blocks)
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
