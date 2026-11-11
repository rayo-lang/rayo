internal import CLLVM
import RayoSema

/// The LLVM types of a program's values, and of a function's result, laid out as the program's type table says.
struct LLVMTypes {
    private let table: TypeTable
    private let module: ModuleBuilder
    /// Each struct's LLVM type, indexed by `StructID`.
    private let structs: [LLVMTypeRef]

    init(_ table: TypeTable, in module: ModuleBuilder) {
        // Keep the table that the types follow, and the module that makes them.
        self.table = table
        self.module = module

        // Name every struct before any gets its fields, so that a field may hold any struct.
        structs = table.ids.map { LLVMStructCreateNamed(module.context, $0.name) }
        for id in table.ids { defineBody(of: id) }
    }

    /// The LLVM type that holds a value of `type`, or that a function returns when it returns nothing.
    func llvmType(_ type: RayoType) -> LLVMTypeRef {
        switch type {
        case .int: module.int64
        case .bool: module.bool
        case .void: module.void
        case .structure(let id): structs[id.index]
        }
    }

    /// The alignment, in bytes, that a value of `type` in memory has.
    func alignment(of type: RayoType) -> UInt32 {
        UInt32(table.layout(of: type).alignment)
    }

    /// Gives the LLVM type of the struct `id` its fields in the order they lie in memory, then the bytes that pad
    /// its end, if any.
    private func defineBody(of id: StructID) {
        // Lay the fields out in the order the table puts them in memory.
        let layout = table.structLayout(of: id)
        let fields = table[id].fields
        var body: [LLVMTypeRef?] = layout.layoutOrder.map { llvmType(fields[$0].type) }

        // The bytes that pad the end, if there are any, hold nothing.
        if layout.endPadding > 0 { body.append(LLVMArrayType2(module.int8, UInt64(layout.endPadding))) }

        // A packed struct has no padding of LLVM's between its fields, so each lies at the table's offset.
        LLVMStructSetBody(structs[id.index], &body, UInt32(body.count), 1)
    }
}
