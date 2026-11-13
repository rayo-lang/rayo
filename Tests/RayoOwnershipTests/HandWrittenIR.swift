import RayoIR
import RayoSema
import RayoSource

/// The locals of the function each test checks: `x` and `y` are `var`s, `k` is a `let`, `t` is a temporary, `h` is a
/// `var` that holds a `Hit`, and `s` is a `var` that holds a `Shot`.
let x = 0, y = 1, k = 2, t = 3, h = 4, s = 5

/// The structs each program declares: a `Shot` of an Int `range` and a `hit`, and a `Hit` of an Int `damage`.
let shotAndHit = TypeTable(structs: [
    StructType(name: "Shot", fields: [Field(name: "range", type: .int), Field(name: "hit", type: .structure(hit))]),
    StructType(name: "Hit", fields: [Field(name: "damage", type: .int)]),
])

let shot = StructID(index: 0, name: "Shot")
let hit = StructID(index: 1, name: "Hit")

/// The paths of fields to a `Shot`'s `range`, its `hit`, and the `damage` of its `hit`.
let shotRange = [0], shotHit = [1], shotDamage = [1, 0]

/// A function a test writes by hand: its declaration and its body.
typealias HandWrittenFunction = (declaration: FunctionDeclaration, body: IRBody)

/// A program of `functions`, the first of them its `main`, which declares `Shot` and `Hit`.
func program(of functions: [HandWrittenFunction]) -> IRProgram {
    // Declare each function, with its body under its ID.
    var table = FunctionTable()
    var bodies: [FunctionID: IRBody] = [:]
    for function in functions {
        bodies[table.declare(function.declaration)] = function.body
    }

    return IRProgram(types: shotAndHit, functions: table, bodies: bodies, main: FunctionID(index: 0))
}

/// A function made of `blocks`, whose locals are `x`, `y`, `k`, `t`, `h` and `s`, the first `parameterCount` of them
/// its parameters.
func function(_ blocks: [BasicBlock], parameterCount: Int = 0) -> HandWrittenFunction {
    let locals = [
        IRLocal.source(name: "x", kind: .var, type: .int), .source(name: "y", kind: .var, type: .int),
        .source(name: "k", kind: .let, type: .int), .temporary(.int),
        .source(name: "h", kind: .var, type: .structure(hit)), .source(name: "s", kind: .var, type: .structure(shot)),
    ]
    let parameters = locals.prefix(parameterCount).map(\.type)
    let declaration = FunctionDeclaration(name: "f()", parameters: parameters, result: .void, kind: .written)
    return (declaration, IRBody(locals: locals, blocks: blocks))
}

/// Stores a new `Hit` in `h`, then a new `Shot` that takes it in `s`, which the source names at `offset`.
func storeShot(at offset: Int = 0) -> [Statement] {
    [
        store(.structure(hit, fields: [.constant(.int(7))]), in: h),
        store(.structure(shot, fields: [.constant(.int(4)), move(h, at: offset)]), in: s, at: offset),
    ]
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

/// The field that `fields` lead to inside `local`, outermost first, or the whole local where there are none.
func place(_ local: Int, fields: [Int]) -> Place {
    Place(root: LocalID(index: local), steps: fields.map(PlaceStep.field))
}

/// Reads the field that `fields` lead to inside `local`, or the whole local where there are none, which the source
/// names at `offset`.
func read(_ local: Int, fields: [Int] = [], at offset: Int) -> Operand {
    .read(place(local, fields: fields), at: at(offset))
}

/// Moves the field that `fields` lead to inside `local`, or the whole local where there are none, which the source
/// names at `offset`.
func move(_ local: Int, fields: [Int] = [], at offset: Int) -> Operand {
    .move(place(local, fields: fields), at: at(offset))
}

/// Stores what `value` computes in the field that `fields` lead to inside `local`, or in the whole local where there
/// are none, which the source names at `offset`.
func store(_ value: Rvalue, in local: Int, fields: [Int] = [], at offset: Int = 0) -> Statement {
    let destination = Destination(place(local, fields: fields), at: at(offset))
    return .compute(destination: destination, value: value, range: at(0))
}

func store(_ operand: Operand, in local: Int, fields: [Int] = [], at offset: Int = 0) -> Statement {
    store(.use(operand), in: local, fields: fields, at: offset)
}

func store(_ value: Int64, in local: Int, fields: [Int] = [], at offset: Int = 0) -> Statement {
    store(.constant(.int(value)), in: local, fields: fields, at: offset)
}

/// Computes `operand`'s value and drops it, as `_ = value` does.
func dropping(_ operand: Operand) -> Statement {
    .compute(destination: nil, value: .use(operand), range: at(0))
}

func declare(_ local: Int) -> Statement {
    .declare(LocalID(index: local))
}

func printing(_ operand: Operand) -> Statement {
    .compute(destination: nil, value: .call(.printInt, arguments: [operand]), range: at(0))
}
