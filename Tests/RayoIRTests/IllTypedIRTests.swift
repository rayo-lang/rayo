import RayoIR
import RayoSema
import Testing

/// IR that no lowering of a checked program makes, and what the verifier says is wrong with it.
struct IllTypedIR: CustomTestStringConvertible, Sendable {
    let testDescription: String
    let program: IRProgram
    /// The name of the function the violation is in.
    let function: String
    let message: String
}

@Suite("IR that breaks its types")
struct IllTypedIRTests {
    @Test(arguments: illTypedIR)
    func `is a violation that names its function and says what is wrong`(ir: IllTypedIR) {
        #expect(IRVerifier.verify(ir.program) == IRViolation(function: ir.function, message: ir.message))
    }

    @Test func `IR that keeps its types has no violation`() throws {
        let program = try lowered("""
            struct Pair(var count: Int, var flag: Bool)
            func twice(_ n: Int) -> Int { n * 2 }
            func main() {
                var pair = Pair(count: -twice(3) % 4, flag: !(1 < 2))
                pair.count += 1
                if pair.flag == false && pair.count != 0 { print(pair.count / 2) }
                while pair.count >= 0 { pair.count -= 1 }
                print(pair.flag)
            }
            """)
        #expect(IRVerifier.verify(program) == nil)
    }

    @Test func `a wrapping operator is named as one`() {
        let ir = computing(.binary(.add(.wrapping), read(0), read(1)), on: [.bool, .int], into: .int)
        let message = "the IR gives 'wrapping +' an operand of type Bool, where it takes Int"
        #expect(IRVerifier.verify(ir) == IRViolation(function: "main()", message: message))
    }
}

private let illTypedIR = [
    IllTypedIR(
        testDescription: "an operator given an operand of a type it doesn't take",
        program: computing(.binary(.add(.checked), read(0), read(1)), on: [.bool, .int], into: .int),
        function: "main()",
        message: "the IR gives '+' an operand of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "a division by a Bool",
        program: computing(.binary(.divide(.checked), read(0), read(1)), on: [.int, .bool], into: .int),
        function: "main()",
        message: "the IR gives '/' an operand of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "a remainder of a Bool",
        program: computing(.binary(.remainder, read(0), read(1)), on: [.bool, .int], into: .int),
        function: "main()",
        message: "the IR gives '%' an operand of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "negation of a Bool",
        program: computing(.unary(.negate(.checked), read(0)), on: [.bool], into: .int),
        function: "main()",
        message: "the IR gives '-' an operand of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "'!' of an Int",
        program: computing(.unary(.not, read(0)), on: [.int], into: .bool),
        function: "main()",
        message: "the IR gives '!' an operand of type Int, where it takes Bool",
    ),
    IllTypedIR(
        testDescription: "a comparison of a Bool with an Int",
        program: computing(.binary(.equal, read(0), read(1)), on: [.bool, .int], into: .bool),
        function: "main()",
        message: "the IR gives '==' an operand of type Int, where it takes Bool",
    ),
    IllTypedIR(
        testDescription: "a comparison of an Int with a Bool",
        program: computing(.binary(.less, read(0), read(1)), on: [.int, .bool], into: .bool),
        function: "main()",
        message: "the IR gives '<' an operand of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "an ordering of two Bools",
        program: computing(.binary(.less, read(0), read(1)), on: [.bool, .bool], into: .bool),
        function: "main()",
        message: "the IR gives '<' an operand of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "a comparison of two structs",
        program: computing(.binary(.equal, read(0), read(1)), on: [pairType, pairType], into: .bool),
        function: "main()",
        message: "the IR gives '==' an operand of type Pair, where it takes Int or Bool",
    ),
    IllTypedIR(
        testDescription: "a branch on an Int",
        program: program(of: [main(locals: [.int], [
            block(then: branch(read(0), then: 1, otherwise: 1)),
            block(then: .return(nil)),
        ])]),
        function: "main()",
        message: "the IR branches on a value of type Int, where it takes Bool",
    ),
    IllTypedIR(
        testDescription: "a store of an Int in a Bool",
        program: computing(.use(read(0)), on: [.int], into: .bool),
        function: "main()",
        message: "the IR stores a value of type Int in a place of type Bool",
    ),
    IllTypedIR(
        testDescription: "a store of a Bool in an Int field",
        program: computing(.use(read(0)), on: [.bool], intoFieldOf: pairType),
        function: "main()",
        message: "the IR stores a value of type Bool in a place of type Int",
    ),
    IllTypedIR(
        testDescription: "a store in a field of an Int",
        program: computing(.use(read(0)), on: [.int], intoFieldOf: .int),
        function: "main()",
        message: "the IR names field 0 of a value of type Int",
    ),
    IllTypedIR(
        testDescription: "a call given an argument of a type its function doesn't take",
        program: program(of: [main(locals: [.bool], [
            block(compute(nil, .call(.builtin(.printInt), arguments: [read(0)])), then: .return(nil)),
        ])]),
        function: "main()",
        message: "the IR passes 'print(_: Int)' an argument of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "a call of the Bool print given an Int",
        program: callingPrint(.printBool, with: [int(1)]),
        function: "main()",
        message: "the IR passes 'print(_: Bool)' an argument of type Int, where it takes Bool",
    ),
    IllTypedIR(
        testDescription: "a call given too few arguments",
        program: callingPrint(.printInt, with: []),
        function: "main()",
        message: "the IR passes 'print(_: Int)' 0 arguments, where it takes 1",
    ),
    IllTypedIR(
        testDescription: "a call given too many arguments",
        program: callingPrint(.printInt, with: [int(1), int(2)]),
        function: "main()",
        message: "the IR passes 'print(_: Int)' 2 arguments, where it takes 1",
    ),
    IllTypedIR(
        testDescription: "a call given one argument too few",
        program: calling("f(_:_:)", taking: 2, with: [int(1)]),
        function: "main()",
        message: "the IR passes 'f(_:_:)' 1 argument, where it takes 2",
    ),
    IllTypedIR(
        testDescription: "a store of what a call that returns nothing gives",
        program: calling("f()", taking: 0, with: [], storingIn: .int),
        function: "main()",
        message: "the IR stores a value of type Void in a place of type Int",
    ),
    IllTypedIR(
        testDescription: "a return of a Bool from a function that returns an Int",
        program: returning(.return(read(0)), of: .bool, from: .int),
        function: "f()",
        message: "the IR returns a value of type Bool from a function that returns Int",
    ),
    IllTypedIR(
        testDescription: "a return of nothing from a function that returns an Int",
        program: returning(.return(nil), of: .bool, from: .int),
        function: "f()",
        message: "the IR returns nothing from a function that returns Int",
    ),
    IllTypedIR(
        testDescription: "a return of a value from a function that returns Void",
        program: returning(.return(read(0)), of: .bool, from: .void),
        function: "f()",
        message: "the IR returns a value of type Bool from a function that returns Void",
    ),
    IllTypedIR(
        testDescription: "a struct made of fewer values than it has fields",
        program: computing(.structure(pairID, fields: []), on: [], into: pairType),
        function: "main()",
        message: "the IR makes 'Pair' of 0 fields, where it has 1",
    ),
    IllTypedIR(
        testDescription: "a struct's field given a value of another type",
        program: computing(.structure(pairID, fields: [bool(true)]), on: [], into: pairType),
        function: "main()",
        message: "the IR gives field 0 of 'Pair' a value of type Bool, where it takes Int",
    ),
    IllTypedIR(
        testDescription: "a read of a field of an Int",
        program: computing(.use(read(0, fields: 0)), on: [.int], into: .int),
        function: "main()",
        message: "the IR names field 0 of a value of type Int",
    ),
    IllTypedIR(
        testDescription: "a read of a field that a struct doesn't have",
        program: computing(.use(read(0, fields: 1)), on: [pairType], into: .int),
        function: "main()",
        message: "the IR names field 1 of a value of type Pair",
    ),
]

/// A function a test writes by hand: its declaration and its body.
private typealias HandWrittenFunction = (declaration: FunctionDeclaration, body: IRBody)

/// The function `name`, which returns `result`, holds temporaries of `locals`' types and is made of `blocks`, and
/// whose first `parameterCount` locals are its parameters.
private func function(
    _ name: String, parameterCount: Int = 0, result: RayoType = .void, locals: [RayoType], _ blocks: [BasicBlock],
) -> HandWrittenFunction {
    let parameters = Array(locals.prefix(parameterCount))
    let declaration = FunctionDeclaration(name: name, parameters: parameters, result: result, kind: .written)
    return (declaration, IRBody(locals: locals.map(IRLocal.temporary), blocks: blocks))
}

/// A `main` that holds temporaries of `locals`' types and is made of `blocks`.
private func main(locals: [RayoType], _ blocks: [BasicBlock]) -> HandWrittenFunction {
    function("main()", locals: locals, blocks)
}

/// A program of `functions`, the first of them its `main`, whose structs are `pairTable`'s.
private func program(of functions: [HandWrittenFunction]) -> IRProgram {
    // Declare each function, with its body under its ID.
    var table = FunctionTable()
    var bodies: [FunctionID: IRBody] = [:]
    for function in functions {
        bodies[table.declare(function.declaration)] = function.body
    }
    return IRProgram(types: pairTable, functions: table, bodies: bodies, main: FunctionID(index: 0))
}

/// A program whose `main` holds temporaries of `operands`' types and then of `result`'s, and stores what `rvalue`
/// computes in the last.
private func computing(_ rvalue: Rvalue, on operands: [RayoType], into result: RayoType) -> IRProgram {
    program(of: [main(locals: operands + [result], [block(compute(operands.count, rvalue), then: .return(nil))])])
}

/// A program whose `main` holds temporaries of `operands`' types and then of `holder`'s, and stores what `rvalue`
/// computes in the first field of the last.
private func computing(_ rvalue: Rvalue, on operands: [RayoType], intoFieldOf holder: RayoType) -> IRProgram {
    let store = compute(operands.count, fields: 0, value: rvalue)
    return program(of: [main(locals: operands + [holder], [block(store, then: .return(nil))])])
}

/// A program whose `main` returns nothing, and whose `f()`, which returns `result`, holds a temporary of `local`'s
/// type and ends in `terminator`.
private func returning(_ terminator: Terminator, of local: RayoType, from result: RayoType) -> IRProgram {
    program(of: [
        main(locals: [], [block(then: .return(nil))]),
        function("f()", result: result, locals: [local], [block(then: terminator)]),
    ])
}

/// A program whose `main` calls `name`, which takes Ints for `parameterCount` parameters and returns nothing, with
/// `arguments`, and stores what the call gives in a temporary of `local`'s type, or drops it where there is no `local`.
private func calling(
    _ name: String, taking parameterCount: Int, with arguments: [Operand], storingIn local: RayoType? = nil,
) -> IRProgram {
    // `main` stores what the call gives in its one temporary, where it has one, and drops it otherwise.
    let call = Rvalue.call(.function(FunctionID(index: 1)), arguments: arguments)
    let caller = main(locals: local.map { [$0] } ?? [], [
        block(compute(local == nil ? nil : 0, call), then: .return(nil)),
    ])

    // The function returns as soon as it is called.
    let parameters = Array(repeating: RayoType.int, count: parameterCount)
    let callee = function(name, parameterCount: parameterCount, locals: parameters, [block(then: .return(nil))])
    return program(of: [caller, callee])
}

/// A program whose `main` passes `arguments` to `print`, one of the prelude's, each of which takes one argument.
private func callingPrint(_ print: Builtin, with arguments: [Operand]) -> IRProgram {
    program(of: [main(locals: [], [
        block(compute(nil, .call(.builtin(print), arguments: arguments)), then: .return(nil)),
    ])])
}

/// A struct of one Int.
private let pairTable = TypeTable(structs: [StructType(name: "Pair", fields: [Field(name: "count", type: .int)])])

/// The struct `pairTable` holds.
private let pairID = StructID(index: 0, name: "Pair")

/// The type of the struct `pairTable` holds.
private let pairType = RayoType.structure(pairID)
