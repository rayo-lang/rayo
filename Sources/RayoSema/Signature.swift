/// What a call needs to know about the function it calls.
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

    /// Whether `other` takes arguments with the same labels and types, so no call could tell the two apart. A type
    /// that isn't known matches none, since it was reported where it is written.
    func takesArguments(like other: Signature) -> Bool {
        parameters.count == other.parameters.count && zip(parameters, other.parameters).allSatisfy { mine, theirs in
            mine.label == theirs.label && mine.type != nil && mine.type == theirs.type
        }
    }

    /// Whether a call may pass arguments with `labels`, in order.
    func takesLabels(_ labels: [String?]) -> Bool {
        parameters.count == labels.count && zip(parameters, labels).allSatisfy { $0.label == $1 }
    }

    /// Whether each of `arguments`, in order, that `isConsidered` picks fits its parameter. A parameter whose type
    /// isn't known takes any argument, so a declaration's error doesn't spread to its calls.
    func takes(_ arguments: [CheckedValue], where isConsidered: (CheckedValue) -> Bool) -> Bool {
        parameters.count == arguments.count && zip(parameters, arguments).allSatisfy { parameter, argument in
            guard isConsidered(argument), let type = parameter.type else { return true }
            return argument.fits(type)
        }
    }
}

extension Signature {
    /// The signature of `builtin`, under the name a call writes to reach it.
    init(of builtin: Builtin) {
        let parameters = builtin.parameters.map { Parameter(label: $0.label, type: $0.type, spelledType: "\($0.type)") }
        self.init(name: builtin.name.spelling, callee: .builtin(builtin), parameters: parameters,
                  result: .type(builtin.result))
    }
}
