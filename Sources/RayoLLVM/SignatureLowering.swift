import LLVM
import RayoSema

/// Decides how a function's parameters and result are passed, and the LLVM signature that follows, for its calling
/// convention. The rest of the emitter asks it, at a function's declaration and at each call alike.
struct SignatureLowering {
    /// The most scalars a small value splits into. A small value passes directly, split into its scalars, and moves
    /// between places whole; a larger one passes through a pointer, and moves between places with `memcpy`.
    static let smallValueScalarLimit = 2

    let types: LLVMTypes

    /// How a function of `signature` passes each parameter and its result, and its LLVM type, made in `context`.
    func lower(_ signature: FunctionSignature, in context: borrowing Context) -> LoweredSignature {
        let parameters = signature.parameters.map { passMode(of: $0, in: signature.convention) }
        let result = resultMode(of: signature.result, in: signature.convention)
        let returnedStruct = returnedStruct(for: result, in: context)
        let type = functionType(passing: parameters, returning: result, as: returnedStruct, in: context)
        return LoweredSignature(
            signature, parameters: parameters, result: result, type: type, returnedStruct: returnedStruct,
        )
    }

    /// Whether a value of `type` is small: whether it splits into at most `smallValueScalarLimit` scalars.
    func isSmall(_ type: RayoType) -> Bool {
        types.scalars(of: type).count <= Self.smallValueScalarLimit
    }

    /// How `parameter` is passed in `convention`.
    private func passMode(of parameter: FunctionSignature.Parameter, in convention: CallingConvention) -> PassMode {
        switch convention {
        case .rayo: rayoPassMode(of: parameter)
        }
    }

    /// How a result of `type` comes back in `convention`.
    private func resultMode(of type: RayoType, in convention: CallingConvention) -> PassMode {
        switch convention {
        case .rayo: rayoResultMode(of: type)
        }
    }

    /// How Rayo's convention passes `parameter`.
    private func rayoPassMode(of parameter: FunctionSignature.Parameter) -> PassMode {
        let type = parameter.type
        // A mutable argument is changed in the caller's place, whatever its size.
        if parameter.convention == .mutable { return .callerPlace(pointerAttributes(to: type, readOnly: false)) }
        // A small value is passed in its scalars, whatever the parameter's convention.
        if isSmall(type) { return .direct(types.scalars(of: type)) }

        switch parameter.convention {
        // A large borrowed argument is read in the caller's place, which nothing changes while the call runs.
        case .borrowed: return .callerPlace(pointerAttributes(to: type, readOnly: true))
        // A large owned argument is copied to a slot that the callee owns. Passing the place it moves from wants the
        // call's arguments checked against each other first, since one place could be lent to one and moved into
        // another.
        case .owned: return .filledSlot(pointerAttributes(to: type, readOnly: false))
        case .mutable: preconditionFailure("a mutable argument is passed in the caller's place above")
        }
    }

    /// How Rayo's convention returns a result of `type`.
    private func rayoResultMode(of type: RayoType) -> PassMode {
        // Void and a small value are returned in their scalars, which LLVM returns in registers.
        if type == .void || isSmall(type) { return .direct(types.scalars(of: type)) }

        // A large one is written to a slot the caller passes.
        let layout = types.layout(of: type)
        return .resultSlot([.structReturn(types.llvmType(type)), .noAlias, .writable, .deadOnUnwind,
                            .align(layout.alignment)])
    }

    /// The attributes of a pointer, passed as an argument, to a value of `type` that only the callee reaches while
    /// the call runs, and that it never writes where `readOnly`.
    private func pointerAttributes(to type: RayoType, readOnly: Bool) -> [Attribute] {
        let layout = types.layout(of: type)
        // LLVM takes no `dereferenceable` of no bytes, which a value that takes no memory would give.
        let dereferenceable: [Attribute] = layout.size > 0 ? [.dereferenceable(layout.size)] : []
        let access: [Attribute] = readOnly ? [.noAlias, .readOnly] : [.noAlias]
        return access + [.capturesNone, .noUndef, .nonNull] + dereferenceable + [.align(layout.alignment)]
    }

    /// The struct of no name that a result passed in `mode` returns its scalars in, where it has more than one.
    private func returnedStruct(for mode: PassMode, in context: borrowing Context) -> LLVM.StructType? {
        guard case .direct(let scalars) = mode, scalars.count > 1 else { return nil }
        return context.structType(of: scalars.map { types.llvmType($0.type) })
    }

    /// The LLVM type of a function that takes `parameters` and returns a result in `result`, its scalars in
    /// `returnedStruct` where it has one.
    private func functionType(
        passing parameters: [PassMode], returning result: PassMode, as returnedStruct: LLVM.StructType?,
        in context: borrowing Context,
    ) -> FunctionType {
        // A result slot's pointer comes first, then each parameter's scalars, or its pointer.
        var llvmParameters: [AnyType] = []
        if case .resultSlot = result { llvmParameters.append(context.pointerType) }
        for mode in parameters {
            llvmParameters += llvmTypes(passing: mode, in: context)
        }

        let llvmResult = llvmType(returning: result, as: returnedStruct, in: context)
        return context.functionType(returning: llvmResult, taking: llvmParameters)
    }

    /// The LLVM type a function returns where its result is passed in `mode`, its scalars in `returnedStruct` where it
    /// has one.
    private func llvmType(
        returning mode: PassMode, as returnedStruct: LLVM.StructType?, in context: borrowing Context,
    ) -> AnyType {
        // A result of more than one scalar returns the struct of them.
        if let returnedStruct { return returnedStruct.anyType }
        // One of one scalar returns it.
        if case .direct(let scalars) = mode, scalars.count == 1 { return types.llvmType(scalars[0].type) }
        // One of none, or one written to a slot, returns nothing.
        return context.voidType
    }

    /// The types of the LLVM parameters a parameter passed in `mode` takes.
    private func llvmTypes(passing mode: PassMode, in context: borrowing Context) -> [AnyType] {
        switch mode {
        case .direct(let scalars): scalars.map { types.llvmType($0.type) }
        case .callerPlace, .filledSlot, .resultSlot: [context.pointerType]
        }
    }
}
