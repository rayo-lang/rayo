import LLVM
import RayoIR
import RayoLLVM
import RayoSema
import Testing

/// IR that the checker would never pass, and what the emitter says is wrong with it.
struct IllTypedIR: CustomTestStringConvertible, Sendable {
    let testDescription: String
    let executable: IRExecutable
    let error: String
}

@Suite("IR the checker would never pass")
struct IllTypedIRTests {
    @Test(arguments: Build.allCases, illTypedIR)
    func `is an internal error that says what is wrong, before LLVM sees it`(build: Build, ir: IllTypedIR) {
        #expect(throws: LLVMError(message: ir.error)) {
            try compile(ir.executable, for: build)
        }
    }
}

private let illTypedIR = [
    IllTypedIR(
        testDescription: "an operator given an operand of a type it doesn't take",
        executable: computing(.binary(.add, read(0), read(1)), on: [.bool, .int], into: .int),
        error: "the IR gives '+' an operand of type i1, where it takes i64",
    ),
    IllTypedIR(
        testDescription: "a division by a Bool",
        executable: computing(.binary(.divide, read(0), read(1)), on: [.int, .bool], into: .int),
        error: "the IR gives '/' an operand of type i1, where it takes i64",
    ),
    IllTypedIR(
        testDescription: "a remainder of a Bool",
        executable: computing(.binary(.remainder, read(0), read(1)), on: [.bool, .int], into: .int),
        error: "the IR gives '%' an operand of type i1, where it takes i64",
    ),
    IllTypedIR(
        testDescription: "negation of a Bool",
        executable: computing(.unary(.negate, read(0)), on: [.bool], into: .int),
        error: "the IR gives '-' an operand of type i1, where it takes i64",
    ),
    IllTypedIR(
        testDescription: "'!' of an Int",
        executable: computing(.unary(.not, read(0)), on: [.int], into: .bool),
        error: "the IR gives '!' an operand of type i64, where it takes i1",
    ),
    IllTypedIR(
        testDescription: "a comparison of a Bool with an Int",
        executable: computing(.binary(.equal, read(0), read(1)), on: [.bool, .int], into: .bool),
        error: "the IR gives '==' an operand of type i64, where it takes i1",
    ),
    IllTypedIR(
        testDescription: "a comparison of an Int with a Bool",
        executable: computing(.binary(.less, read(0), read(1)), on: [.int, .bool], into: .bool),
        error: "the IR gives '<' an operand of type i1, where it takes i64",
    ),
    IllTypedIR(
        testDescription: "a comparison of two structs",
        executable: program(of: [mainFunction(locals: [pairType, pairType, .bool], [
            BasicBlock(
                statements: [statement(storingIn: 2, .binary(.equal, read(0), read(1)))],
                terminator: .return(nil),
            ),
        ])], types: pairTable),
        error: "the IR gives '==' an operand of type %Pair = type <{ i64 }>, where it takes i1 or i64",
    ),
    IllTypedIR(
        testDescription: "a branch on an Int",
        executable: program(locals: [.int], [
            BasicBlock(
                statements: [],
                terminator: .branch(read(0), then: BlockID(index: 1), otherwise: BlockID(index: 1)),
            ),
            BasicBlock(statements: [], terminator: .return(nil)),
        ]),
        error: "the IR branches on a value of type i64, where it takes i1",
    ),
    IllTypedIR(
        testDescription: "a store of an Int in a Bool",
        executable: computing(.use(read(0)), on: [.int], into: .bool),
        error: "the IR stores a value of type i64 in a place of type i1",
    ),
    IllTypedIR(
        testDescription: "a store of a Bool in an Int field",
        executable: computing(.use(read(0)), on: [.bool], intoFieldOf: pairType),
        error: "the IR stores a value of type i1 in a place of type i64",
    ),
    IllTypedIR(
        testDescription: "a store in a field of an Int",
        executable: computing(.use(read(0)), on: [.int], intoFieldOf: .int),
        error: "the IR names field 0 of a value of type i64",
    ),
    IllTypedIR(
        testDescription: "a call given an argument of a type its function doesn't take",
        executable: program(locals: [.bool], [
            BasicBlock(statements: [statement(printing: read(0))], terminator: .return(nil)),
        ]),
        error: "the IR passes 'rayo.print_int' an argument of type i1, where it takes i64",
    ),
    IllTypedIR(
        testDescription: "a call of the Bool print given an Int",
        executable: callingPrint(.printBool, with: [.constant(.int(1))]),
        error: "the IR passes 'rayo.print_bool' an argument of type i64, where it takes i1",
    ),
    IllTypedIR(
        testDescription: "a call given too few arguments",
        executable: callingPrint(.printInt, with: []),
        error: "the IR passes 'rayo.print_int' 0 arguments, where it takes 1",
    ),
    IllTypedIR(
        testDescription: "a call given too many arguments",
        executable: callingPrint(.printInt, with: [.constant(.int(1)), .constant(.int(2))]),
        error: "the IR passes 'rayo.print_int' 2 arguments, where it takes 1",
    ),
    IllTypedIR(
        testDescription: "a call given one argument too few",
        executable: calling("f(_:_:)", taking: 2, with: [.constant(.int(1))]),
        error: "the IR passes 'f(_:_:)' 1 argument, where it takes 2",
    ),
    IllTypedIR(
        testDescription: "a store of what a call that returns nothing gives",
        executable: calling("f()", taking: 0, with: [], storingIn: .int),
        error: "the IR stores the result of 'f()', which returns nothing, in a place of type i64",
    ),
    IllTypedIR(
        testDescription: "a return of a Bool from a function that returns an Int",
        executable: returning(.return(read(0)), of: .bool, from: .int),
        error: "the IR returns a value of type i1 from a function that returns i64",
    ),
    IllTypedIR(
        testDescription: "a return of nothing from a function that returns an Int",
        executable: returning(.return(nil), of: .bool, from: .int),
        error: "the IR returns nothing from a function that returns i64",
    ),
    IllTypedIR(
        testDescription: "a return of a value from a function that returns Void",
        executable: returning(.return(read(0)), of: .bool, from: .void),
        error: "the IR returns a value of type i1 from a function that returns void",
    ),
    IllTypedIR(
        testDescription: "a struct made of fewer values than it has fields",
        executable: computing(.structure(pairID, fields: []), on: [], into: pairType),
        error: "the IR makes 'Pair' of 0 fields, where it has 1",
    ),
    IllTypedIR(
        testDescription: "a struct's field given a value of another type",
        executable: computing(.structure(pairID, fields: [.constant(.bool(true))]), on: [], into: pairType),
        error: "the IR gives field 0 of 'Pair' a value of type i1, where it takes i64",
    ),
    IllTypedIR(
        testDescription: "a read of a field of an Int",
        executable: computing(.use(read(0, field: 0)), on: [.int], into: .int),
        error: "the IR names field 0 of a value of type i64",
    ),
    IllTypedIR(
        testDescription: "a read of a field that a struct doesn't have",
        executable: computing(.use(read(0, field: 1)), on: [pairType], into: .int),
        error: "the IR names field 1 of a value of type %Pair = type <{ i64 }>",
    ),
]

/// A program whose `main` holds temporaries of `operands`' types and then of `result`'s, and stores what `rvalue`
/// computes in the last. Its structs are `pairTable`'s.
private func computing(_ rvalue: Rvalue, on operands: [RayoType], into result: RayoType) -> IRExecutable {
    let main = mainFunction(locals: operands + [result], [
        BasicBlock(statements: [statement(storingIn: operands.count, rvalue)], terminator: .return(nil)),
    ])
    return program(of: [main], types: pairTable)
}

/// A program whose `main` holds temporaries of `operands`' types and then of `holder`'s, and stores what `rvalue`
/// computes in the first field of the last. Its structs are `pairTable`'s.
private func computing(_ rvalue: Rvalue, on operands: [RayoType], intoFieldOf holder: RayoType) -> IRExecutable {
    let field = Place(local: LocalID(index: operands.count), fields: [0], range: nowhere)
    let main = mainFunction(locals: operands + [holder], [
        BasicBlock(
            statements: [.compute(destination: field, value: rvalue, range: nowhere)], terminator: .return(nil),
        ),
    ])
    return program(of: [main], types: pairTable)
}

/// An operand that reads the field at `field` of the value of the local `index`.
private func read(_ index: Int, field: Int) -> Operand {
    .read(Place(local: LocalID(index: index), fields: [field], range: nowhere))
}

/// A program whose `main` returns nothing, and whose `f()`, which returns `result`, holds a temporary of `local`'s
/// type and ends in `terminator`.
private func returning(_ terminator: Terminator, of local: RayoType, from result: RayoType) -> IRExecutable {
    let main = mainFunction(locals: [], [BasicBlock(statements: [], terminator: .return(nil))])
    let function = IRFunction(
        name: "f()", parameterCount: 0, result: result, locals: [.temporary(local)],
        blocks: [BasicBlock(statements: [], terminator: terminator)],
    )
    return program(of: [main, function])
}

/// A program whose `main` calls `name`, which takes Ints for `parameterCount` parameters and returns nothing, with
/// `arguments`, and stores what the call gives in a temporary of `local`'s type, or drops it where there is no `local`.
private func calling(
    _ name: String, taking parameterCount: Int, with arguments: [Operand], storingIn local: RayoType? = nil,
) -> IRExecutable {
    // `main` calls the function, storing what it gives where it has a temporary to store it in.
    let call = Rvalue.call(.function(FunctionID(index: 1)), arguments: arguments)
    let main = if let local {
        // A `main` with a temporary stores what the call gives in it.
        mainFunction(locals: [local], [
            BasicBlock(statements: [statement(storingIn: 0, call)], terminator: .return(nil)),
        ])
    } else {
        // A `main` without one drops it.
        mainFunction(locals: [], [
            BasicBlock(
                statements: [.compute(destination: nil, value: call, range: nowhere)], terminator: .return(nil),
            ),
        ])
    }

    // The function returns as soon as it is called.
    let function = IRFunction(
        name: name, parameterCount: parameterCount, result: .void,
        locals: Array(repeating: .temporary(.int), count: parameterCount),
        blocks: [BasicBlock(statements: [], terminator: .return(nil))],
    )
    return program(of: [main, function])
}

/// A program whose `main` passes `arguments` to `print`, one of the prelude's, each of which takes one argument.
private func callingPrint(_ print: Callee, with arguments: [Operand]) -> IRExecutable {
    program(locals: [], [
        BasicBlock(
            statements: [.compute(destination: nil, value: .call(print, arguments: arguments), range: nowhere)],
            terminator: .return(nil),
        ),
    ])
}

/// A struct of one Int.
private let pairTable = TypeTable(structs: [StructType(name: "Pair", fields: [Field(name: "count", type: .int)])])

/// The struct `pairTable` holds.
private let pairID = StructID(index: 0, name: "Pair")

/// The type of the struct `pairTable` holds.
private let pairType = RayoType.structure(pairID)
