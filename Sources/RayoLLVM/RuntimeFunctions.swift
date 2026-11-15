import LLVM
import RayoSema

/// The type of each runtime function, made once for a program. A program's module declares a runtime function with
/// that type the first time its code calls it.
struct RuntimeFunctions {
    /// The signature of the print of each of the prelude's scalar types, which a call passes its argument by.
    private let printSignatures: [ScalarType: LoweredSignature]
    /// The type of the program's `main`, which takes nothing and returns nothing.
    private let mainType: FunctionType
    /// The type of the panic, which takes a pointer to its message's bytes and their count as an Int. No Rayo type
    /// is a pointer, so no Rayo signature lowers to it.
    private let panicType: FunctionType

    /// Lowers the signature of each runtime function with `lowering`, in `context`.
    init(lowering: SignatureLowering, in context: borrowing Context) {
        let prints = ScalarType.prelude.map { scalar in
            (scalar, lowering.lower(FunctionSignature(of: .print(scalar)), in: context))
        }
        printSignatures = Dictionary(uniqueKeysWithValues: prints)
        mainType = lowering.lower(FunctionSignature(parameters: [], result: .void), in: context).type
        let length = lowering.types.format(of: .int).type
        panicType = context.functionType(returning: context.voidType, taking: [context.pointerType, length])
    }

    /// The LLVM type the program declares `function` with.
    func type(of function: RuntimeFunction) -> FunctionType {
        switch function {
        case .main: mainType
        case .print(let scalar): printSignature(of: scalar).type
        case .panic: panicType
        }
    }

    /// The print of `scalar`, declared in `module`, with the signature a call passes its argument by.
    func print(_ scalar: ScalarType, in module: borrowing Module) -> DeclaredFunction {
        DeclaredFunction(function: declare(.print(scalar), in: module), signature: printSignature(of: scalar))
    }

    /// The panic, declared in `module`.
    func panic(in module: borrowing Module) -> Function {
        declare(.panic, in: module)
    }

    /// The signature of the print of `scalar`, one of the prelude's scalar types.
    private func printSignature(of scalar: ScalarType) -> LoweredSignature {
        guard let signature = printSignatures[scalar] else {
            preconditionFailure("the runtime prints no \(scalar)")
        }
        return signature
    }

    /// Declares `function` in `module`, unless the module declares it already, and returns it.
    private func declare(_ function: RuntimeFunction, in module: borrowing Module) -> Function {
        if let declared = module.function(named: function.symbol) { return declared }
        return module.addFunction(named: function.symbol, type: type(of: function))
    }
}
