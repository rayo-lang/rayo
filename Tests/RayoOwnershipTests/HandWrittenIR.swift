import RayoIR
import RayoSema
import RayoSource

/// The locals of the function each test checks: `x` and `y` are `var`s, `k` is a `let`, and `t` is a temporary.
let x = 0, y = 1, k = 2, t = 3

/// A program of `functions`, the first of them its `main`, which declares no structs.
func program(of functions: [IRFunction]) -> IRProgram {
    IRProgram(types: .empty, functions: functions, main: FunctionID(index: 0))
}

/// A function made of `blocks`, whose locals are `x`, `y`, `k` and `t`, the first `parameterCount` of them its
/// parameters.
func function(_ blocks: [BasicBlock], parameterCount: Int = 0) -> IRFunction {
    let locals = [
        IRLocal.source(name: "x", kind: .var, type: .int), .source(name: "y", kind: .var, type: .int),
        .source(name: "k", kind: .let, type: .int), .temporary(.int),
    ]
    return IRFunction(name: "f()", parameterCount: parameterCount, result: .void, locals: locals, blocks: blocks)
}

func goto(_ block: Int) -> Terminator {
    .goto(BlockID(index: block))
}

/// A branch on a condition that the checker can't tell the value of.
func branch(then: Int, otherwise: Int) -> Terminator {
    .branch(.constant(.bool(true)), then: BlockID(index: then), otherwise: BlockID(index: otherwise))
}

/// A range that starts and ends at `offset` in a file of one line, so each use a test writes has a range of its
/// own.
func at(_ offset: Int) -> SourceRange {
    let location = SourceLocation(line: 1, column: offset + 1, offset: offset)
    return SourceRange(location, location)
}

func read(_ local: Int, at offset: Int) -> Operand {
    .read(Place(local: LocalID(index: local), range: at(offset)))
}

func move(_ local: Int, at offset: Int) -> Operand {
    .move(Place(local: LocalID(index: local), range: at(offset)))
}

/// Stores what `value` computes in `local`, which the source names at `offset`.
func store(_ value: Rvalue, in local: Int, at offset: Int = 0) -> Statement {
    .compute(destination: Place(local: LocalID(index: local), range: at(offset)), value: value, range: at(0))
}

func store(_ operand: Operand, in local: Int, at offset: Int = 0) -> Statement {
    store(.use(operand), in: local, at: offset)
}

func store(_ value: Int64, in local: Int, at offset: Int = 0) -> Statement {
    store(.constant(.int(value)), in: local, at: offset)
}

func declare(_ local: Int) -> Statement {
    .declare(LocalID(index: local))
}

func printing(_ operand: Operand) -> Statement {
    .compute(destination: nil, value: .call(.printInt, arguments: [operand]), range: at(0))
}
