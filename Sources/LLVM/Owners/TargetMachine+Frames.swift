internal import CLLVM

extension TargetMachine {
    /// The most bytes LLVM puts in one function's frame for this machine, or nil where it puts any number. Windows on
    /// arm64 tells its unwinder a frame's size in 24 bits of 16-byte units, so LLVM ends the whole process, with no
    /// error to catch, at a frame of 256 MiB or more.
    var largestFrame: Int? {
        let isArm64 = triple.hasPrefix("aarch64") || triple.hasPrefix("arm64")
        return isArm64 && compilesForWindows ? (1 << 28) - 1 : nil
    }

    /// Throws where a function that `module` defines keeps more on its stack than a frame this machine can make
    /// holds, before LLVM would end the process on it.
    func checkFrames(of module: borrowing Module) throws(LLVMError) {
        guard let largestFrame else { return }

        // Beside its stack slots, a frame holds the registers the function saves and the values it spills, which
        // take far less than the mebibyte left for them here.
        let largestSlots = largestFrame - (1 << 20)
        let layout = LLVMGetModuleDataLayout(module.ref)!
        for function in module.functions where !function.isDeclaration {
            let slots = stackSlotBytes(of: function, laidOutBy: layout)
            guard slots <= largestSlots else {
                throw LLVMError(message: """
                    LLVM can't make a frame of 256 MiB or more for Windows on arm64, and '\(function.name)' keeps \
                    \(slots) bytes on its stack
                    """)
            }
        }
    }
}

/// The bytes that the stack slots of `function`'s entry block take, each rounded up to its alignment: the slots that
/// LLVM puts in the function's frame. A slot whose count isn't a constant grows the stack as the function runs, and
/// takes no room in the frame.
private func stackSlotBytes(of function: Function, laidOutBy layout: LLVMTargetDataRef) -> Int {
    var bytes = 0
    for instruction in function.blocks.first?.instructions ?? [] {
        guard let type = instruction.allocatedType,
              let count = LLVMIsAConstantInt(LLVMGetOperand(instruction.ref, 0)) else { continue }
        let alignment = instruction.alignment ?? 1
        let size = Int(LLVMABISizeOfType(layout, type.ref)) * Int(LLVMConstIntGetZExtValue(count))
        bytes += (size + alignment - 1) / alignment * alignment
    }
    return bytes
}
