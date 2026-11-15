internal import CLLVM

/// An attribute of a whole function, which tells LLVM how to generate the function's machine code.
public enum FunctionAttribute: Equatable {
    /// `uwtable`: the function has an unwind table that is right at every instruction, which a debugger or the
    /// system's unwinder reads to walk the stack through the function.
    case unwindTable
    /// `"probe-stack"="inline-asm"`: as the function makes its frame, it touches each page of the frame in turn from
    /// the top, so a frame larger than the stack faults on the stack's guard page instead of skipping past it.
    case inlineStackProbes

    /// How LLVM spells an attribute: as a kind it knows by name, holding a number, or as a string key, holding a
    /// string.
    private enum Spelling {
        case known(String, UInt64)
        case string(String, String)
    }

    private var spelling: Spelling {
        switch self {
        // `uwtable` holds the kind of table, and one right at every instruction, which LLVM calls asynchronous, is 2.
        case .unwindTable: .known("uwtable", 2)
        case .inlineStackProbes: .string("probe-stack", "inline-asm")
        }
    }

    /// The attribute, made in `context`.
    func ref(in context: LLVMContextRef) -> LLVMAttributeRef {
        switch spelling {
        case .known(let name, let value):
            LLVMCreateEnumAttribute(context, Self.kind(named: name), value)
        case .string(let key, let value):
            LLVMCreateStringAttribute(context, key, UInt32(key.utf8.count), value, UInt32(value.utf8.count))
        }
    }

    /// Whether `function` carries the attribute, holding the same value.
    func isCarried(by function: LLVMValueRef) -> Bool {
        switch spelling {
        case .known(let name, let value):
            let carried = LLVMGetEnumAttributeAtIndex(function, Self.functionIndex, Self.kind(named: name))
            return carried.map { LLVMGetEnumAttributeValue($0) == value } ?? false
        case .string(let key, let value):
            let carried = LLVMGetStringAttributeAtIndex(function, Self.functionIndex, key, UInt32(key.utf8.count))
            return carried.map { Self.stringValue(of: $0) == value } ?? false
        }
    }

    /// The index LLVM gives the whole function among the places that carry attributes: ~0, which C's enum spells -1.
    static let functionIndex = LLVMAttributeIndex(bitPattern: Int32(LLVMAttributeFunctionIndex))

    /// The number LLVM knows the attribute `name` by.
    private static func kind(named name: String) -> UInt32 {
        LLVMGetEnumAttributeKindForName(name, name.utf8.count)
    }

    /// The string a string attribute holds.
    private static func stringValue(of attribute: LLVMAttributeRef) -> String {
        var length: UInt32 = 0
        let bytes = LLVMGetStringAttributeValue(attribute, &length)!
        return String(decoding: UnsafeRawBufferPointer(start: bytes, count: Int(length)), as: UTF8.self)
    }
}
