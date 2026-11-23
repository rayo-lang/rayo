import RayoCheckedProgram

/// One parameter of a signature: the label a call writes before its argument, how the function takes the argument,
/// the type the argument must have, and whether a call may lend it a temporary.
struct Parameter {
    /// The label an argument for it is written with, or nil when it is written with none.
    var label: String?
    var convention: ParameterConvention
    /// The type, or nil when the declaration names no type or names Void, which was reported there.
    var type: RayoType?
    /// The type as the declaration writes it, with the `&` of a parameter that borrows, such as `&Enemy`.
    var spelledType: String
    /// Whether a call may lend the parameter, where it borrows its argument, a value that no local holds and the
    /// source writes with no `&`, such as a call's result, as a temporary that lives to the end of the call's
    /// statement.
    var borrowsTemporaries: Bool
}

extension Parameter {
    /// The parameter that the checked program declares as `parameter`, which borrows a temporary where
    /// `borrowsTemporaries` says.
    init(_ parameter: FunctionParameter, borrowsTemporaries: Bool) {
        self.init(label: parameter.label, convention: parameter.convention, type: parameter.type,
                  spelledType: parameter.convention.spelling(of: parameter.type),
                  borrowsTemporaries: borrowsTemporaries)
    }

    /// The parameter as the checked program declares it, or nil where its type isn't known.
    var declared: FunctionParameter? {
        type.map { FunctionParameter(label: label, convention: convention, type: $0) }
    }

    /// What a call that writes `callee` for what it calls expects of the parameter's argument, or nil where the
    /// parameter's type isn't known.
    func expectation(calledAs callee: String) -> Expectation? {
        let parameter = ArgumentParameter(callee: callee, convention: convention,
                                          borrowsTemporaries: borrowsTemporaries)
        return type.map { Expectation($0, recipient: .parameter(parameter)) }
    }
}
