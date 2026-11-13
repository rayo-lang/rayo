import LLVM

/// A function's signature as LLVM sees it: how each parameter and the result are passed, and the LLVM function type
/// and parameter attributes that follow.
struct LoweredSignature {
    /// The signature lowered.
    let source: FunctionSignature
    /// How each parameter of `source` is passed, in order.
    let parameters: [PassMode]
    let result: PassMode
    let type: FunctionType
    /// The attributes of each LLVM parameter, in order.
    let parameterAttributes: [[Attribute]]
    /// The struct of no name that the result's scalars return in, where the result splits into more than one.
    let returnedStruct: LLVM.StructType?
    /// The index of the first LLVM parameter that passes each parameter of `source`, then the index past the last.
    private let firstParameters: [Int]

    init(
        _ source: FunctionSignature, parameters: [PassMode], result: PassMode, type: FunctionType,
        returnedStruct: LLVM.StructType?,
    ) {
        // A result slot is passed ahead of the parameters, and each parameter is passed in as many LLVM parameters
        // as it has scalars where it is passed directly, and in one pointer otherwise.
        var attributes = result.passesSlot ? [result.attributes] : []
        var firstParameters: [Int] = []
        for mode in parameters {
            firstParameters.append(attributes.count)
            attributes += mode.llvmParameterAttributes
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

private extension PassMode {
    /// Whether the mode passes a result in a slot, whose pointer comes ahead of the parameters.
    var passesSlot: Bool {
        if case .resultSlot = self { true } else { false }
    }

    /// The attributes of each LLVM parameter that a parameter passed in this mode takes.
    var llvmParameterAttributes: [[Attribute]] {
        switch self {
        case .direct(let scalars): Array(repeating: [], count: scalars.count)
        case .callerPlace(let attributes), .filledSlot(let attributes), .resultSlot(let attributes): [attributes]
        }
    }
}
