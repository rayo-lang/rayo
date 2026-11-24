import RayoCheckedProgram

/// One parameter of a signature, as a call is checked against it.
struct Parameter {
    /// The label an argument for it is written with, or nil when it is written with none.
    var label: String?
    var convention: ParameterConvention
    /// The type, or nil when the declaration names no type or names Void, which was reported there.
    var type: RayoType?
    /// The type as the declaration writes it, with any `&`.
    var spelledType: String
    /// Whether a bare value that no local holds may be lent to the parameter as a temporary.
    var borrowsTemporaries: Bool
    /// What the parameter, where it owns its argument, does with a bare place of a type that isn't implicitly copyable.
    var barePlaceUse: BarePlaceUse
}

extension Parameter {
    /// The parameter that the checked program declares as `parameter`.
    init(_ parameter: FunctionParameter, borrowsTemporaries: Bool, barePlaceUse: BarePlaceUse) {
        self.init(label: parameter.label, convention: parameter.convention, type: parameter.type,
                  spelledType: parameter.convention.spelling(of: parameter.type),
                  borrowsTemporaries: borrowsTemporaries, barePlaceUse: barePlaceUse)
    }

    /// The parameter as the checked program declares it, or nil where its type isn't known.
    var declared: FunctionParameter? {
        type.map { FunctionParameter(label: label, convention: convention, type: $0) }
    }

    /// What a call that writes `callee` for what it calls expects of the parameter's argument, or nil where the
    /// parameter's type isn't known. The flag says whether a function of the callee's name that the call's arguments
    /// fit borrows the argument.
    func expectation(calledAs callee: String, isBorrowedByOverload: Bool) -> Expectation? {
        let parameter = ArgumentParameter(callee: callee, convention: convention,
                                          borrowsTemporaries: borrowsTemporaries, barePlaceUse: barePlaceUse,
                                          isBorrowedByOverload: isBorrowedByOverload)
        return type.map { Expectation($0, recipient: .parameter(parameter)) }
    }
}
