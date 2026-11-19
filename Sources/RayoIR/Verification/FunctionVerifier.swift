import RayoCheckedProgram

/// Checks that one function's body keeps the IR's types.
struct FunctionVerifier {
    private let body: IRBody
    private let declaration: FunctionDeclaration
    private let types: TypeTable
    private let functions: FunctionTable
    /// The access each statement of the body that begins one begins, by its ID.
    private let accesses: [AccessID: Access]

    init(body: IRBody, of declaration: FunctionDeclaration, in program: IRProgram) {
        self.body = body
        accesses = body.begunAccesses
        self.declaration = declaration
        types = program.types
        functions = program.functions
    }

    /// Throws the first violation in the body, in the order of its blocks, and in each of its statements and then its
    /// terminator.
    func verify() throws(IRViolation) {
        try verifyParameterLocals()
        for block in body.blocks {
            for statement in block.statements { try verify(statement) }
            try verify(block.terminator)
        }
    }

    /// Throws where the body's first locals aren't its function's parameters, in order, each of its parameter's
    /// convention and type, or where a later local is a parameter. The ownership stage reads a parameter's convention
    /// from its local, and the emitter from the declaration, so the two must agree.
    private func verifyParameterLocals() throws(IRViolation) {
        // Each side is a parameter's convention and type, without the label, which no local holds, or nil where it is
        // no parameter.
        let parameters = declaration.parameters.map { parameter in
            FunctionParameter(label: nil, convention: parameter.convention, type: parameter.type)
        }
        let locals = body.locals.map { local in
            local.parameterConvention.map { FunctionParameter(label: nil, convention: $0, type: local.type) }
        }
        for index in 0..<max(locals.count, parameters.count) {
            let local = index < locals.count ? locals[index] : nil
            let parameter = index < parameters.count ? parameters[index] : nil
            guard local != parameter else { continue }
            throw violation("the IR declares %\(index) as \(Self.text(of: local)), where its function declares "
                + Self.text(of: parameter))
        }
    }

    /// `parameter` as a violation of a body's parameters names it, such as `a parameter of owned Int`, or `no
    /// parameter` where it is nil.
    private static func text(of parameter: FunctionParameter?) -> String {
        parameter.map { "a parameter of \($0.convention.spelling(of: $0.type))" } ?? "no parameter"
    }

    private func verify(_ statement: Statement) throws(IRViolation) {
        switch statement {
        // A computation's value must fit its destination, where it has one.
        case .compute(let destination, let value, _):
            try verify(value, storedIn: destination?.place)

        // A declaration starts the life of a local the body declares, and a retirement ends it. A parameter's life
        // starts with the call, which passes its value, and ends once the call returns, so no statement declares or
        // retires it.
        case .declare(let local):
            guard body.locals[local.index].parameterConvention == nil else {
                throw violation("the IR declares the parameter %\(local.index) in its function's body")
            }
        case .retire(let local):
            guard body.locals[local.index].parameterConvention == nil else {
                throw violation("the IR retires the parameter %\(local.index) in its function's body")
            }

        // An access reaches a place of the body, and an end names an access that the body begins.
        case .begin(_, let access):
            _ = try type(of: access.place)
        case .end(let id):
            _ = try access(id)
        }
    }

    /// The access that `id` names. Throws where no statement of the body begins it.
    private func access(_ id: AccessID) throws(IRViolation) -> Access {
        guard let access = accesses[id] else { throw violation("the IR names a\(id.index), which it never begins") }
        return access
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

    /// The type of the value an operation makes. Throws where its operands don't have the types it takes.
    private func type(of rvalue: Rvalue) throws(IRViolation) -> RayoType {
        switch rvalue {
        case .operand(let operand): try type(of: operand)
        case .unary(let op, let operand): op.resultType(on: try operandType(of: op, operand))
        case .binary(let op, let left, let right): op.resultType(on: try operandType(of: op, left, right))
        case .call(let callee, let arguments): try resultType(of: callee, passing: arguments)
        case .array(let elements, let element): try arrayType(of: elements, eachOf: element)
        case .filledArray(let value, let count): .array(count: count, element: try type(of: value))
        case .index(let operand, _): try indexType(of: operand)
        }
    }

    /// The type of an index, which `operand` must give as a UInt.
    private func indexType(of operand: Operand) throws(IRViolation) -> RayoType {
        let operandType = try type(of: operand)
        guard operandType == .uint else { throw violation("the IR indexes with a value of type \(operandType)") }
        return .uint
    }

    /// The type of an array of `elements`, each of which must be of `element`.
    private func arrayType(of elements: [Operand], eachOf element: RayoType) throws(IRViolation) -> RayoType {
        for operand in elements {
            let elementType = try type(of: operand)
            guard elementType == element else {
                throw violation("the IR makes an array of \(element) from an element of type \(elementType)")
            }
        }
        return .array(count: elements.count, element: element)
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
        // The types are listed as a sentence lists them, such as `Int, UInt or Bool`.
        let names = taken.map(\.description)
        let takes = if names.count > 1, let last = names.last {
            names.dropLast().joined(separator: ", ") + " or " + last
        } else {
            names.joined()
        }
        return violation("the IR gives '\(op)' an operand of type \(given), where it takes \(takes)")
    }

    /// The type of what a call of `callee` with `arguments` gives. Throws where the arguments aren't as many as its
    /// parameters, or of their types.
    private func resultType(of callee: Callee, passing arguments: [CallArgument]) throws(IRViolation) -> RayoType {
        let name = callee.name(in: functions)
        let parameters = callee.parameters(in: functions)

        // A call passes as many arguments as the function has parameters.
        guard arguments.count == parameters.count else {
            let counts = "\(arguments.count) \(arguments.count == 1 ? "argument" : "arguments")"
            throw violation("the IR passes '\(name)' \(counts), where it takes \(parameters.count)")
        }

        // Each argument is of its parameter's type, and passed as its parameter's convention takes it.
        for (argument, parameter) in zip(arguments, parameters) {
            let argumentType = try type(of: argument)
            guard argumentType == parameter.type else {
                let passed = "an argument of type \(argumentType)"
                throw violation("the IR passes '\(name)' \(passed), where it takes \(parameter.type)")
            }
            try verify(argument, passedTo: parameter.convention, of: name)
        }
        return callee.result(in: functions)
    }

    /// Throws where `argument` isn't passed as a parameter of `convention` of the function `name` takes it: a value or
    /// a read access where the parameter borrows, a value where it owns, and a modify access where it is mutable.
    private func verify(
        _ argument: CallArgument, passedTo convention: ParameterConvention, of name: String,
    ) throws(IRViolation) {
        // A value passes through no access.
        let accessKind: AccessKind? = if let id = argument.access { try access(id).kind } else { nil }
        let accepted: [AccessKind?] = switch convention {
        case .borrowed: [nil, .read]
        case .owned: [nil]
        case .mutable: [.modify]
        }
        guard !accepted.contains(accessKind) else { return }

        let takes = accepted.map(Self.passing(through:)).joined(separator: " or ")
        throw violation("the IR passes '\(name)' \(Self.passing(through: accessKind)), where it takes \(takes)")
    }

    /// What an argument passed through an access of `kind` passes, or through none where `kind` is nil, as a
    /// violation names it.
    private static func passing(through kind: AccessKind?) -> String {
        kind.map { "a \($0.rawValue) access" } ?? "a value"
    }

    /// The type of the value `argument` passes: its operand's, or that of the place its access reaches. Throws where
    /// no statement of the body begins its access.
    private func type(of argument: CallArgument) throws(IRViolation) -> RayoType {
        switch argument {
        case .operand(let operand): try type(of: operand)
        case .access(let id): try type(of: try access(id).place)
        }
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
            throw violation("the IR names \(error.step) of a value of type \(error.holder)")
        }
    }

    /// The violation that `message` says, in this function.
    private func violation(_ message: String) -> IRViolation {
        IRViolation(function: declaration.name, message: message)
    }
}
