import LLVM
import RayoSource

/// Emits a function's panics: each a branch, on a condition, to a block that calls the runtime's panic with a message
/// naming the reason and the place in the source.
struct PanicEmitter {
    /// The function that a panic's blocks are appended to.
    private let llvmFunction: Function
    private let runtimeDeclarations: RuntimeDeclarations
    private let types: LLVMTypes

    init(into llvmFunction: Function, runtimeDeclarations: RuntimeDeclarations, types: LLVMTypes) {
        self.llvmFunction = llvmFunction
        self.runtimeDeclarations = runtimeDeclarations
        self.types = types
    }

    /// Branches to a panic for `reason` at `range` where `condition` holds, and leaves the builder in a new block
    /// where it doesn't.
    func panic(
        if condition: IntValue<I1>, _ reason: PanicReason, at range: SourceRange, in program: borrowing ProgramEmitter,
    ) {
        // Split on the condition into two blocks appended at the function's end.
        let panicBlock = program.context.appendBlock(named: "panic", to: llvmFunction)
        let continueBlock = program.context.appendBlock(named: "continue", to: llvmFunction)
        program.builder.branch(if: condition, then: panicBlock, else: continueBlock)

        // The panic block reports the reason and the place, and never returns.
        program.builder.position(atEndOf: panicBlock)
        let message = Array("\(program.sourcePath):\(range.start): panic: \(reason.rawValue)\n".utf8)
        let bytes = program.context.constant(bytes: message)
        // A name with a dot is none that the runtime or the C library defines.
        let text = program.module.addGlobal(named: "panic.message", initializer: bytes)
        text.setConstant()
        text.setUnnamedAddress()
        let length = types.format(of: .int).constant(Int128(message.count))
        program.builder.call(runtimeDeclarations.panic(in: program.module), [text.pointer, length])
        program.builder.unreachable()

        program.builder.position(atEndOf: continueBlock)
    }
}
