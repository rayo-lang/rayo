import RayoSema

/// Checks that one function's body keeps the IR's types.
struct FunctionVerifier {
    private let body: IRBody
    private let declaration: FunctionDeclaration
    private let types: TypeTable
    private let functions: FunctionTable

    init(body: IRBody, of declaration: FunctionDeclaration, in program: IRProgram) {
        self.body = body
        self.declaration = declaration
        types = program.types
        functions = program.functions
    }

    /// Throws the first violation in the body, in the order of its blocks, and in each of its statements and then its
    /// terminator.
    func verify() throws(IRViolation) {
        for block in body.blocks {
            for statement in block.statements { try verify(statement) }
            try verify(block.terminator)
        }
    }

    private func verify(_ statement: Statement) throws(IRViolation) {
        switch statement {
        // A computation's value must fit its destination, where it has one.
        case .compute(let destination, let value, _):
            try verify(value, storedIn: destination?.place)

        // A declaration only starts a local's life.
        case .declare:
            break
        }
    }

    /// Throws where `value` breaks the IR's types, or isn't of the type of `destination`, where there is one.
    private func verify(_ value: Rvalue, storedIn destination: Place?) throws(IRViolation) {
        let valueType = try type(of: value)

        // A value that no place takes is dropped, whatever its type.
        guard let destination else { return }
        // A value that a place takes must be of the place's type.
        let placeType = try type(of: destination)
        guard valueType == placeType else {
            throw violation("the IR stores a value of type \(valueType) in a place of type \(placeType)")
        }
    }

    private func verify(_ terminator: Terminator) throws(IRViolation) {
        switch terminator {
        // A branch tests a Bool.
        case .branch(let condition, _, _):
            let conditionType = try type(of: condition)
            guard conditionType == .bool else {
                throw violation("the IR branches on a value of type \(conditionType), where it takes Bool")
            }

        // A `return` gives what the function returns.
        case .return(let result):
            try verifyReturn(of: result)

        // A jump, or a block no path reaches, holds no value.
        case .goto, .unreachable:
            break
        }
    }

    /// Throws where `result`, or nothing where it is nil, isn't what the function returns.
    private func verifyReturn(of result: Operand?) throws(IRViolation) {
        let returns = "from a function that returns \(declaration.result)"

        // Nothing is what a Void function returns.
        guard let result else {
            guard declaration.result == .void else { throw violation("the IR returns nothing \(returns)") }
            return
        }

        // A value is what any other function returns, of its result's type.
        let resultType = try type(of: result)
        guard declaration.result != .void, resultType == declaration.result else {
            throw violation("the IR returns a value of type \(resultType) \(returns)")
        }
    }

    /// The type of the value `rvalue` makes. Throws where its operands aren't of the types it takes.
    private func type(of rvalue: Rvalue) throws(IRViolation) -> RayoType {
        switch rvalue {
        case .use(let operand): try type(of: operand)
        case .unary(let op, let operand): op.resultType(on: try operandType(of: op, operand))
        case .binary(let op, let left, let right): op.resultType(on: try operandType(of: op, left, right))
        case .call(let callee, let arguments): try resultType(of: callee, passing: arguments)
        case .structure(let id, let fields): try structureType(of: id, from: fields)
        }
    }

    /// The type of `operand`, which `op` must take.
    private func operandType(of op: IRUnaryOperator, _ operand: Operand) throws(IRViolation) -> RayoType {
        let operandType = try type(of: operand)
        let taken = op.operandTypes
        guard taken.contains(operandType) else { throw unfit(op, given: operandType, taking: taken) }
        return operandType
    }

    /// The type of `left` and `right`, which must be of one type that `op` takes.
    private func operandType(of op: IRBinaryOperator, _ left: Operand, _ right: Operand) throws(IRViolation)
        -> RayoType {
        // The left operand must be of a type `op` takes.
        let leftType = try type(of: left)
        let taken = op.operandTypes
        guard taken.contains(leftType) else { throw unfit(op, given: leftType, taking: taken) }

        // The right one must be of the same type.
        let rightType = try type(of: right)
        guard rightType == leftType else { throw unfit(op, given: rightType, taking: [leftType]) }
        return leftType
    }

    /// The violation of an operator `op` given an operand of `given`, where it takes one of `taken`.
    private func unfit(_ op: some CustomStringConvertible, given: RayoType, taking taken: [RayoType]) -> IRViolation {
        let takes = taken.map(\.description).joined(separator: " or ")
        return violation("the IR gives '\(op)' an operand of type \(given), where it takes \(takes)")
    }

    /// The type of what a call of `callee` with `arguments` gives. Throws where the arguments aren't as many as its
    /// parameters, or of their types.
    private func resultType(of callee: Callee, passing arguments: [Operand]) throws(IRViolation) -> RayoType {
        let name = callee.name(in: functions)
        let parameters = callee.parameters(in: functions)

        // A call passes as many arguments as the function has parameters.
        guard arguments.count == parameters.count else {
            let counts = "\(arguments.count) \(arguments.count == 1 ? "argument" : "arguments")"
            throw violation("the IR passes '\(name)' \(counts), where it takes \(parameters.count)")
        }

        // Each argument is of its parameter's type.
        for (argument, parameter) in zip(arguments, parameters) {
            let argumentType = try type(of: argument)
            guard argumentType == parameter else {
                let passed = "an argument of type \(argumentType)"
                throw violation("the IR passes '\(name)' \(passed), where it takes \(parameter)")
            }
        }
        return callee.result(in: functions)
    }

    /// The type of the struct `id`, made of `fields`. Throws where they aren't as many as its fields, or of their
    /// types.
    private func structureType(of id: StructID, from fields: [Operand]) throws(IRViolation) -> RayoType {
        let declared = types[id].fields

        // A struct is made of a value for each of its fields.
        guard fields.count == declared.count else {
            throw violation("the IR makes '\(id.name)' of \(fields.count) fields, where it has \(declared.count)")
        }

        // Each value is of its field's type.
        for (index, (field, declaredField)) in zip(fields, declared).enumerated() {
            let fieldType = try type(of: field)
            guard fieldType == declaredField.type else {
                let given = "field \(index) of '\(id.name)' a value of type \(fieldType)"
                throw violation("the IR gives \(given), where it takes \(declaredField.type)")
            }
        }
        return .structure(id)
    }

    /// The type of `operand`'s value, whose root, where it names a place, must be one of the body's locals. Throws
    /// where a step of the place leads into a field that the value it steps from doesn't have.
    private func type(of operand: Operand) throws(IRViolation) -> RayoType {
        switch operand {
        case .constant(let constant): constant.type
        case .read(let place, _), .move(let place, _): try type(of: place)
        }
    }

    /// The type of the value at `place`, whose root must be one of the body's locals. Throws where a step leads into a
    /// field that the value it steps from doesn't have.
    private func type(of place: Place) throws(IRViolation) -> RayoType {
        do {
            return try place.type(in: body, types: types)
        } catch {
            throw violation("the IR names \(error.step.name) of a value of type \(error.holder)")
        }
    }

    /// The violation that `message` says, in this function.
    private func violation(_ message: String) -> IRViolation {
        IRViolation(function: declaration.name, message: message)
    }
}

private extension PlaceStep {
    /// The step as an error names it, such as `field 0`.
    var name: String {
        switch self {
        case .field(let index): "field \(index)"
        }
    }
}
