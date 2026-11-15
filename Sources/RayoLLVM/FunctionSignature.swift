import RayoIR
import RayoSema

/// What a call needs to know of a function to pass its arguments and take its result: each parameter's convention and
/// type, and the result's type.
struct FunctionSignature {
    struct Parameter {
        var convention: ParameterConvention
        var type: RayoType
    }

    var parameters: [Parameter]
    var result: RayoType

    /// The signature of the function `declaration` declares, whose parameters are all borrowed, the one convention
    /// the IR has.
    init(of declaration: FunctionDeclaration) {
        parameters = declaration.parameters.map { Parameter(convention: .borrowed, type: $0) }
        result = declaration.result
    }

    /// The signature of the runtime's function that a call of `builtin` goes to, whose parameters are all borrowed.
    init(of builtin: Builtin) {
        parameters = builtin.parameterTypes.map { Parameter(convention: .borrowed, type: $0) }
        result = builtin.result
    }

    init(parameters: [Parameter], result: RayoType) {
        self.parameters = parameters
        self.result = result
    }
}
