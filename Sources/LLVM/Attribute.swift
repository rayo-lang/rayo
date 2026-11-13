internal import CLLVM

/// An attribute of a function's parameter, or of a call's argument, which tells LLVM what holds of it beyond its type.
public enum Attribute: Equatable {
    /// `noalias`: while the function runs, it reaches the memory the pointer points to through no other pointer.
    case noAlias
    /// `readonly`: the function never writes through the pointer.
    case readOnly
    /// `captures(none)`: the function keeps no copy of the pointer once it returns.
    case capturesNone
    /// `noundef`: the value has defined bits.
    case noUndef
    /// `nonnull`: the pointer is never null.
    case nonNull
    /// `dereferenceable(n)`: the pointer points to at least `n` bytes that may be read.
    case dereferenceable(Int)
    /// `align(n)`: the pointer is a multiple of `n` bytes.
    case align(Int)
    /// `sret(type)`: the pointer is the slot the function writes its result, of `type`, in.
    case structReturn(AnyType)
    /// `writable`: the function may write the memory the pointer points to, whatever it held.
    case writable
    /// `dead_on_unwind`: the memory the pointer points to is never read once the call unwinds.
    case deadOnUnwind

    /// The attribute, made in `context`.
    func ref(in context: LLVMContextRef) -> LLVMAttributeRef {
        switch self {
        case .noAlias: Self.enumAttribute("noalias", in: context)
        case .readOnly: Self.enumAttribute("readonly", in: context)
        // `captures` holds the ways the pointer may be captured, and none is 0.
        case .capturesNone: Self.enumAttribute("captures", in: context)
        case .noUndef: Self.enumAttribute("noundef", in: context)
        case .nonNull: Self.enumAttribute("nonnull", in: context)
        case .dereferenceable(let bytes): Self.enumAttribute("dereferenceable", bytes, in: context)
        case .align(let bytes): Self.enumAttribute("align", bytes, in: context)
        case .structReturn(let type):
            LLVMCreateTypeAttribute(context, Self.kind(named: "sret"), type.ref)
        case .writable: Self.enumAttribute("writable", in: context)
        case .deadOnUnwind: Self.enumAttribute("dead_on_unwind", in: context)
        }
    }

    /// The attribute `name`, holding `value`, made in `context`.
    private static func enumAttribute(_ name: String, _ value: Int = 0, in context: LLVMContextRef)
        -> LLVMAttributeRef {
        LLVMCreateEnumAttribute(context, kind(named: name), UInt64(value))
    }

    /// The number LLVM knows the attribute `name` by.
    private static func kind(named name: String) -> UInt32 {
        LLVMGetEnumAttributeKindForName(name, name.utf8.count)
    }
}

extension [[Attribute]] {
    /// Calls `apply` with each attribute, made in `context`, and the index LLVM gives the parameter it holds of: one
    /// list of attributes for each parameter, in order.
    func forEachAttribute(in context: LLVMContextRef, _ apply: (LLVMAttributeIndex, LLVMAttributeRef) -> Void) {
        for (parameter, attributes) in enumerated() {
            // LLVM numbers the parameters from 1, after the result.
            let index = LLVMAttributeIndex(parameter + 1)
            for attribute in attributes { apply(index, attribute.ref(in: context)) }
        }
    }
}
