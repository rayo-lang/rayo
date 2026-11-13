package import CLLVM

/// An LLVM context, which owns the types and constants made in it and makes the modules and builders that use them.
/// The types and constants made in it are valid while it lives, and its modules and builders keep it alive.
public struct Context: ~Copyable {
    let owned: OwnedContext

    public init() {
        owned = OwnedContext()
    }

    package var ref: LLVMContextRef { owned.ref }

    /// The errors LLVM has reported in the context, in order.
    public var reportedErrors: [String] { owned.errors }

    public func makeModule(named name: String) -> Module {
        Module(LLVMModuleCreateWithNameInContext(name, ref), in: owned)
    }

    public func makeBuilder() -> Builder {
        Builder(LLVMCreateBuilderInContext(ref), in: owned)
    }

    /// Parses `llvmIR`, the text of a module named `name`, into a module of this context.
    public func parseModule(_ llvmIR: [UInt8], named name: String) throws(LLVMError) -> Module {
        // Copy the text into a buffer that ends in a NUL, which LLVM's lexer reads as the end of the text.
        let buffer = llvmIR.withUnsafeBufferPointer { bytes in
            bytes.withMemoryRebound(to: CChar.self) { text in
                LLVMCreateMemoryBufferWithMemoryRangeCopy(text.baseAddress, text.count, name)
            }
        }
        defer { LLVMDisposeMemoryBuffer(buffer) }

        // Parse the buffer into a module, which the `Module` returned disposes of.
        var parsed: LLVMModuleRef?
        var message: UnsafeMutablePointer<CChar>?
        let failed = LLVMParseIRInContext2(ref, buffer, &parsed, &message) != 0
        let report = takeMessage(message)
        // Text LLVM can't parse fails with LLVM's report of it.
        guard !failed, let parsed else { throw LLVMError(message: "LLVM couldn't parse \(name):\n\(report)") }
        return Module(parsed, in: owned)
    }

    /// Appends a block named `name` to the end of `function`'s body.
    public func appendBlock(named name: String, to function: Function) -> BasicBlock {
        BasicBlock(LLVMAppendBasicBlockInContext(ref, function.ref, name))
    }

    // MARK: Types

    public func integerType<Width: IntegerWidth>(_ width: Width.Type) -> IntegerType<Width> {
        IntegerType(LLVMIntTypeInContext(ref, Width.bitWidth))
    }

    /// The type of a function's result when it returns nothing.
    public var voidType: AnyType { AnyType(LLVMVoidTypeInContext(ref)) }

    /// A maker of types in this context, which keeps it alive while the maker is held.
    public var typeMaker: TypeMaker { TypeMaker(owned) }

    /// The struct type of no name that holds `fields`, in order, each padded to its alignment as the target pads it.
    public func structType(of fields: [any TypeHandle]) -> StructType {
        var fields = fields.map { Optional($0.anyType.ref) }
        return StructType(LLVMStructTypeInContext(ref, &fields, UInt32(fields.count), 0))
    }

    /// The type of every pointer, whatever it points to.
    public var pointerType: AnyType { AnyType(LLVMPointerTypeInContext(ref, 0)) }

    public func functionType(returning result: some TypeHandle, taking parameters: [any TypeHandle]) -> FunctionType {
        var parameters = parameters.map { Optional($0.anyType.ref) }
        return FunctionType(LLVMFunctionType(result.anyType.ref, &parameters, UInt32(parameters.count), 0))
    }

    // MARK: Constants

    /// The constant array of `bytes`, with no NUL after them.
    public func constant(bytes: [UInt8]) -> AnyValue {
        bytes.withUnsafeBufferPointer { buffer in
            buffer.withMemoryRebound(to: CChar.self) { text in
                AnyValue(LLVMConstStringInContext2(ref, text.baseAddress, text.count, 1))
            }
        }
    }
}
