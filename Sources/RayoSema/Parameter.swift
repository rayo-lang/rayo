/// One parameter of a signature: the label a call writes before its argument, how the function takes the argument,
/// and the type the argument must have.
struct Parameter {
    /// The label an argument for it is written with, or nil when it is written with none.
    var label: String?
    var convention: ParameterConvention
    /// The type, or nil when the declaration names no type or names Void, which was reported there.
    var type: RayoType?
    /// The type as the declaration writes it.
    var spelledType: String
}

extension Parameter {
    /// The parameter of a function the program declares, which the parameter becomes once its type is known.
    init(_ parameter: FunctionParameter) {
        self.init(label: parameter.label, convention: parameter.convention, type: parameter.type,
                  spelledType: "\(parameter.type)")
    }

    /// The parameter as the checked program declares it, or nil where its type isn't known.
    var declared: FunctionParameter? {
        type.map { FunctionParameter(label: label, convention: convention, type: $0) }
    }
}
