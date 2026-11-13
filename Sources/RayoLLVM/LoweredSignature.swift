import LLVM

/// A function's signature as LLVM sees it: how each parameter and the result are passed, and the LLVM function type
/// and parameter attributes that follow.
struct LoweredSignature {
    /// The signature lowered.
    let source: FunctionSignature
    /// How each parameter of `source` is passed, in order.
    let parameters: [ParameterPassing]
    let result: ResultPassing
    let type: FunctionType
    /// The attributes of each LLVM parameter, in order.
    let parameterAttributes: [[Attribute]]
    /// The struct of no name that the result's scalars return in, where the result splits into more than one.
    let returnedStruct: LLVM.StructType?
    /// The index of the first LLVM parameter that passes each parameter of `source`, then the index past the last.
    private let firstParameters: [Int]

    init(
        _ source: FunctionSignature, parameters: [ParameterPassing], result: ResultPassing, type: FunctionType,
        returnedStruct: LLVM.StructType?,
    ) {
        // A result's slot is passed ahead of the parameters, and each parameter in as many LLVM parameters as its
        // passing takes.
        var attributes: [[Attribute]] = if case .slot(let slotAttributes) = result { [slotAttributes] } else { [] }
        var firstParameters: [Int] = []
        for parameter in parameters {
            firstParameters.append(attributes.count)
            attributes += parameter.llvmParameterAttributes
        }
        firstParameters.append(attributes.count)

        self.source = source
        self.parameters = parameters
        self.result = result
        self.type = type
        self.parameterAttributes = attributes
        self.returnedStruct = returnedStruct
        self.firstParameters = firstParameters
    }

    /// The indices of the LLVM parameters that pass the parameter at `index` of `source`.
    func llvmParameters(of index: Int) -> Range<Int> {
        firstParameters[index]..<firstParameters[index + 1]
    }
}
