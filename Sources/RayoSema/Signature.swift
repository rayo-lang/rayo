/// A function's name, its parameters' labels and types, and its result type: everything a call is checked against,
/// apart from the function's body. Each function the file declares has one, and so does each struct's primary
/// initializer and each of the prelude's built-ins.
struct Signature: CustomStringConvertible {
    var name: String
    var callee: Callee
    var parameters: [Parameter]
    var result: DeclaredResult

    /// The name and the parameters, such as `f(_: Int, by: Bool)`, which tell the function apart from every other.
    var description: String {
        let parameterList = parameters.map { "\($0.label ?? "_"): \($0.spelledType)" }.joined(separator: ", ")
        return "\(name)(\(parameterList))"
    }

    /// Whether the declaration failed: a parameter's type or the written result type isn't known, which was reported
    /// there.
    var hasFailed: Bool {
        parameters.contains { $0.type == nil } || result.hasFailed
    }

    /// Whether the other signature takes arguments with the same labels and types, so no call could tell the two
    /// apart. A type that isn't known matches none, since its error was already reported where it is written.
    func takesArguments(like other: Signature) -> Bool {
        parameters.count == other.parameters.count && zip(parameters, other.parameters).allSatisfy { mine, theirs in
            mine.label == theirs.label && mine.type != nil && mine.type == theirs.type
        }
    }

    /// Whether the function is one of the prelude's built-ins.
    var isBuiltin: Bool {
        if case .builtin = callee { true } else { false }
    }

    /// Whether the parameters have exactly `types`, in order.
    func takes(_ types: [RayoType]) -> Bool {
        parameters.map(\.type) == types
    }

    /// Whether a call may pass arguments with these labels, in this order.
    func takesLabels(_ labels: [String?]) -> Bool {
        parameters.count == labels.count && zip(parameters, labels).allSatisfy { $0.label == $1 }
    }

    /// Whether each argument the filter picks has the type of its parameter, taken in order. A parameter whose type
    /// isn't known takes any argument, so a mistake in the declaration gives no further error at each call.
    func takes(_ arguments: [CheckedValue], where isConsidered: (CheckedValue) -> Bool) -> Bool {
        parameters.count == arguments.count && zip(parameters, arguments).allSatisfy { parameter, argument in
            guard isConsidered(argument), let type = parameter.type else { return true }
            return argument.fits(type)
        }
    }
}

extension Signature {
    /// The signature of a built-in function, under the name a call writes to reach it.
    init(of builtin: Builtin) {
        let parameters = builtin.parameters.map { Parameter(label: $0.label, type: $0.type, spelledType: "\($0.type)") }
        self.init(name: builtin.name.spelling, callee: .builtin(builtin), parameters: parameters,
                  result: .type(builtin.result))
    }
}
