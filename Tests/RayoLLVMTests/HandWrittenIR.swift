import RayoIR
import RayoSema
import RayoSource

/// A program whose `main` holds temporaries of `locals`' types and is made of `blocks`.
func program(locals: [RayoType], _ blocks: [BasicBlock]) -> IRExecutable {
    program(of: [mainFunction(locals: locals, blocks)])
}

/// A `main` that holds temporaries of `locals`' types and is made of `blocks`.
func mainFunction(locals: [RayoType], _ blocks: [BasicBlock]) -> IRFunction {
    IRFunction(
        name: "main()", parameterCount: 0, result: .void, locals: locals.map(IRLocal.temporary), blocks: blocks,
    )
}

/// A program of `functions`, the first of them its `main`, whose structs `types` holds, none by default.
func program(of functions: [IRFunction], types: TypeTable = .empty) -> IRExecutable {
    // A program with a `main` is always an executable.
    IRExecutable(IRProgram(types: types, functions: functions, main: FunctionID(index: 0)))!
}

/// An operand that reads the local `index`.
func read(_ index: Int) -> Operand {
    .read(Place(root: LocalID(index: index)), at: nowhere)
}

/// An operand that moves the local `index`'s value out of it.
func move(_ index: Int) -> Operand {
    .move(Place(root: LocalID(index: index)), at: nowhere)
}

/// A program that prints what `value` computes.
func printing(_ value: Rvalue) -> IRExecutable {
    program(locals: [.int], [
        BasicBlock(statements: [
            statement(storingIn: 0, value),
            statement(printing: read(0)),
        ], terminator: .return(nil)),
    ])
}

/// A statement that stores what `value` computes in the local `local`.
func statement(storingIn local: Int, _ value: Rvalue) -> Statement {
    .compute(destination: Destination(Place(root: LocalID(index: local)), at: nowhere), value: value, range: nowhere)
}

/// A statement that prints the Int `operand` holds.
func statement(printing operand: Operand) -> Statement {
    .compute(destination: nil, value: .call(.printInt, arguments: [operand]), range: nowhere)
}

/// The range of an operation no source file wrote.
let nowhere = SourceRange(SourceLocation(line: 1, column: 1, offset: 0), SourceLocation(line: 1, column: 1, offset: 0))
