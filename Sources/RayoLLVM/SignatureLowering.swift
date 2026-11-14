import LLVM
import RayoSema

/// Decides how a function's parameters and result are passed, and the LLVM signature that follows, for its calling
/// convention, and which values are small.
struct SignatureLowering {
    /// The most scalars a small value splits into.
    static let smallValueScalarLimit = 2

    let types: LLVMTypes

    /// How a function of `signature` passes each parameter and its result, and its LLVM type, made in `context`.
    func lower(_ signature: FunctionSignature, in context: borrowing Context) -> LoweredSignature {
        let parameters = signature.parameters.map { passing(of: $0, in: signature.convention) }
        let result = passing(ofResult: signature.result, in: signature.convention)
        let returnedStruct = returnedStruct(for: result, in: context)
        let type = functionType(passing: parameters, returning: result, as: returnedStruct, in: context)
        return LoweredSignature(
            signature, parameters: parameters, result: result, type: type, returnedStruct: returnedStruct,
        )
    }

    /// Whether a value of `type` is small: whether it splits into at most `smallValueScalarLimit` scalars. A small
    /// value moves between places whole, and a larger one with `memcpy`.
    func isSmall(_ type: RayoType) -> Bool {
        types.scalarCount(of: type) <= Self.smallValueScalarLimit
    }

    /// How `parameter` is passed in `convention`.
    private func passing(
        of parameter: FunctionSignature.Parameter, in convention: CallingConvention,
    ) -> ParameterPassing {
        switch convention {
        case .rayo: rayoPassing(of: parameter)
        }
    }

    /// How a result of `type` comes back in `convention`.
    private func passing(ofResult type: RayoType, in convention: CallingConvention) -> ResultPassing {
        switch convention {
        case .rayo: rayoPassing(ofResult: type)
        }
    }

    /// How Rayo's convention passes `parameter`.
    private func rayoPassing(of parameter: FunctionSignature.Parameter) -> ParameterPassing {
        let type = parameter.type
        // A mutable argument is changed in the caller's place, whatever its size.
        if parameter.convention == .mutable { return .callerPlace(pointerAttributes(to: type, access: [.noAlias])) }
        // A small value is passed in its scalars, whatever the parameter's convention.
        if isSmall(type) { return .direct(types.scalars(of: type)) }

        return switch parameter.convention {
        // A large borrowed argument is read in the caller's place, which nothing else changes while the call runs,
        // unless the value changes through its own synchronization.
        case .borrowed: .callerPlace(pointerAttributes(to: type, access: borrowedAccess(to: type)))
        // A large owned argument is copied to a slot that the callee owns. Passing the place it moves from wants the
        // call's arguments checked against each other first, since one place could be lent to one and moved into
        // another.
        case .owned: .filledSlot(pointerAttributes(to: type, access: [.noAlias]))
        // A mutable argument is passed in the caller's place above.
        case .mutable: preconditionFailure("a mutable argument is passed in the caller's place above")
        }
    }

    /// What a callee may assume of the memory a borrowed argument of `type` lies in: that nothing else reaches it
    /// while the call runs, and nothing writes it.
    private func borrowedAccess(to type: RayoType) -> [Attribute] {
        // A value that is or holds a `Synchronized` changes through its own synchronization while it is borrowed, so
        // LLVM may assume neither. The program's types hold none.
        let holdsSynchronized = false
        return holdsSynchronized ? [] : [.noAlias, .readOnly]
    }

    /// How Rayo's convention returns a result of `type`.
    private func rayoPassing(ofResult type: RayoType) -> ResultPassing {
        // Void and a small value are returned in their scalars, which LLVM returns in registers.
        if type == .void || isSmall(type) { return .direct(types.scalars(of: type)) }

        // A large one is written to a slot the caller passes.
        let layout = types.layout(of: type)
        return .slot([
            .structReturn(types.llvmType(type)), .noAlias, .writable, .deadOnUnwind, .align(layout.alignment),
        ])
    }

    /// The attributes of a pointer, passed as an argument, to a value of `type` that no copy of the pointer outlives,
    /// with `access`, which says who reaches the value while the call runs and whether the callee writes it.
    private func pointerAttributes(to type: RayoType, access: [Attribute]) -> [Attribute] {
        let layout = types.layout(of: type)
        // LLVM takes no `dereferenceable` of no bytes, which a value that takes no memory would give.
        let dereferenceable: [Attribute] = layout.size > 0 ? [.dereferenceable(layout.size)] : []
        return access + [.capturesNone, .noUndef, .nonNull] + dereferenceable + [.align(layout.alignment)]
    }

    /// The struct of no name that a result passed as `result` returns its scalars in, where it has more than one.
    private func returnedStruct(for result: ResultPassing, in context: borrowing Context) -> LLVM.StructType? {
        guard case .direct(let scalars) = result, scalars.count > 1 else { return nil }
        return context.structType(of: scalars.map { types.llvmType($0.type) })
    }

    /// The LLVM type of a function that takes `parameters` and gives its result back as `result`, its scalars in
    /// `returnedStruct` where it has one.
    private func functionType(
        passing parameters: [ParameterPassing], returning result: ResultPassing, as returnedStruct: LLVM.StructType?,
        in context: borrowing Context,
    ) -> FunctionType {
        // A result slot's pointer comes first, then each parameter's scalars, or its pointer.
        var llvmParameters: [AnyType] = []
        if case .slot = result { llvmParameters.append(context.pointerType) }
        for parameter in parameters {
            llvmParameters += llvmTypes(passing: parameter, in: context)
        }

        let llvmResult = llvmType(returning: result, as: returnedStruct, in: context)
        return context.functionType(returning: llvmResult, taking: llvmParameters)
    }

    /// The LLVM type a function returns where its result is passed as `result`, its scalars in `returnedStruct` where
    /// it has one.
    private func llvmType(
        returning result: ResultPassing, as returnedStruct: LLVM.StructType?, in context: borrowing Context,
    ) -> AnyType {
        // A result of more than one scalar returns the struct of them.
        if let returnedStruct { return returnedStruct.anyType }
        // One of one scalar returns it.
        if case .direct(let scalars) = result, scalars.count == 1 { return types.llvmType(scalars[0].type) }
        // One of none, or one written to a slot, returns nothing.
        return context.voidType
    }

    /// The types of the LLVM parameters that `parameter` passes in.
    private func llvmTypes(passing parameter: ParameterPassing, in context: borrowing Context) -> [AnyType] {
        switch parameter {
        case .direct(let scalars): scalars.map { types.llvmType($0.type) }
        case .callerPlace, .filledSlot: [context.pointerType]
        }
    }
}
