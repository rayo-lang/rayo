package import CLLVM

/// An LLVM context, which owns the types and constants made in it and makes the modules and builders that use them.
/// Every handle made in it is valid while it lives, and its modules and builders keep it alive.
public struct Context: ~Copyable {
    let handle: ContextHandle

    public init() {
        handle = ContextHandle()
    }

    package var ref: LLVMContextRef { handle.ref }

    /// The errors LLVM has reported in the context, in order.
    public var reportedErrors: [String] { handle.errors }

    public func makeModule(named name: String) -> Module {
        Module(LLVMModuleCreateWithNameInContext(name, ref), in: handle)
    }

    public func makeBuilder() -> Builder {
        Builder(LLVMCreateBuilderInContext(ref), in: handle)
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

        // Parse the buffer, which LLVM leaves to its caller to dispose of.
        var parsed: LLVMModuleRef?
        var message: UnsafeMutablePointer<CChar>?
        let failed = LLVMParseIRInContext2(ref, buffer, &parsed, &message) != 0
        let report = takeMessage(message)
        // Text LLVM can't parse fails with LLVM's report of it.
        guard !failed, let parsed else { throw LLVMError(message: "LLVM couldn't parse \(name):\n\(report)") }
        return Module(parsed, in: handle)
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

    /// Makes a struct type named `name`, which has no fields until it is given them.
    public func makeStructType(named name: String) -> StructType {
        StructType(LLVMStructCreateNamed(ref, name))
    }

    /// The type of an array of `count` values of `element`.
    public func arrayType(of element: some TypeHandle, count: Int) -> AnyType {
        AnyType(LLVMArrayType2(element.anyType.ref, UInt64(count)))
    }

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
