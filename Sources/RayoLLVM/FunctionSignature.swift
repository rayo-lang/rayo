import RayoIR
import RayoSema

/// What a call needs to know of a function to pass its arguments and take its result: each parameter's convention and
/// type, the result's type, and the calling convention.
struct FunctionSignature {
    struct Parameter {
        var convention: ParameterConvention
        var type: RayoType
    }

    var parameters: [Parameter]
    var result: RayoType
    var convention: CallingConvention

    /// The signature of the function `declaration` declares, whose parameters are all borrowed, the one convention
    /// the IR has.
    init(of declaration: FunctionDeclaration) {
        parameters = declaration.parameters.map { Parameter(convention: .borrowed, type: $0) }
        result = declaration.result
        convention = .rayo
    }

    /// The signature of a function of the runtime that takes one borrowed argument of `type`, an Int or a Bool, and
    /// returns nothing.
    init(runtimeTaking type: RayoType) {
        parameters = [Parameter(convention: .borrowed, type: type)]
        result = .void
        // The runtime's functions follow C's convention, which passes a lone Int or Bool directly, as Rayo's does.
        convention = .rayo
    }

    init(parameters: [Parameter], result: RayoType, convention: CallingConvention) {
        self.parameters = parameters
        self.result = result
        self.convention = convention
    }
}
