internal import CLLVM
import RayoSema

/// The LLVM types that hold a program's values, laid out as the program's type table says. LLVM aligns these
/// structs to a byte, so each slot, load and store of one takes its alignment from `alignment(of:)`.
struct LLVMTypes {
    private let table: TypeTable
    private let module: ModuleBuilder
    /// Each struct's LLVM type, indexed by `StructID`.
    private let structs: [LLVMTypeRef]
    /// For each struct, indexed by `StructID`, the LLVM element that holds each field, indexed by the field's place in
    /// the declaration.
    private let elements: [[UInt32]]

    init(_ table: TypeTable, in module: ModuleBuilder) {
        // Keep the table, and the LLVM element that holds each field of each struct.
        self.table = table
        self.module = module
        elements = table.ids.map { Self.elements(of: table.layout(of: $0)) }

        // Name every struct before any gets its fields, so that a field may hold any struct.
        structs = table.ids.map { LLVMStructCreateNamed(module.context, $0.name) }
        for id in table.ids { defineBody(of: id) }
    }

    /// The LLVM type that holds a value of `type`, or that a function returns when it returns nothing.
    func llvmType(_ type: RayoType) -> LLVMTypeRef {
        switch type {
        case .int: return module.int64
        case .bool: return module.bool
        case .void: return module.void
        case .structure(let id): return structs[id.index]
        }
    }

    /// The alignment, in bytes, that a value of `type` in memory has.
    func alignment(of type: RayoType) -> UInt32 {
        UInt32(table.layout(of: type).alignment)
    }

    /// The element of the LLVM struct that holds the struct `id`'s field at `field` in its declaration.
    func element(holding field: Int, of id: StructID) -> UInt32 {
        elements[id.index][field]
    }

    /// Gives the LLVM type of the struct `id` its fields in the order they lie in memory, then the bytes that pad
    /// its end, if any.
    private func defineBody(of id: StructID) {
        let layout = table.layout(of: id)
        let fields = table[id].fields
        var body: [LLVMTypeRef?] = layout.fieldOrder.map { llvmType(fields[$0].type) }
        // The bytes that pad the end, if there are any, hold nothing.
        if layout.endPadding > 0 { body.append(LLVMArrayType2(module.int8, UInt64(layout.endPadding))) }
        // A packed struct has no padding of LLVM's between its fields, so each lies at the table's offset.
        LLVMStructSetBody(structs[id.index], &body, UInt32(body.count), 1)
    }

    /// The element that holds each field, indexed by the field's place in the declaration, of a struct laid out as
    /// `layout` says.
    private static func elements(of layout: StructLayout) -> [UInt32] {
        var elements = Array(repeating: UInt32(0), count: layout.fieldOrder.count)
        for (element, field) in layout.fieldOrder.enumerated() {
            elements[field] = UInt32(element)
        }
        return elements
    }
}
