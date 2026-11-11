import LLVM
import RayoSema

/// The LLVM types of a program's values, and of a function's result, laid out as the program's type table says.
struct LLVMTypes {
    private let table: TypeTable
    let int64: IntegerType<I64>
    let bool: IntegerType<I1>
    private let int8: IntegerType<I8>
    private let void: AnyType
    /// Each struct's LLVM type, indexed by `StructID`.
    private let structs: [LLVM.StructType]

    init(_ table: TypeTable, in context: borrowing Context) {
        // Keep the table that the types follow, and make the types of the values that aren't structs.
        self.table = table
        int64 = context.integerType(I64.self)
        bool = context.integerType(I1.self)
        int8 = context.integerType(I8.self)
        void = context.voidType

        // Name every struct before any gets its fields, so that a field may hold any struct.
        structs = table.ids.map { context.makeStructType(named: $0.name) }
        for id in table.ids { defineBody(of: id, in: context) }
    }

    /// The LLVM type that holds a value of `type`, or that a function returns when it returns nothing.
    func llvmType(_ type: RayoType) -> AnyType {
        switch type {
        case .int: int64.anyType
        case .bool: bool.anyType
        case .void: void
        case .structure(let id): structs[id.index].anyType
        }
    }

    /// The alignment, in bytes, that a value of `type`, which isn't Void, has in memory.
    func alignment(of type: RayoType) -> Int {
        table.layout(of: type).alignment
    }

    /// Gives the LLVM type of the struct `id` its fields in the order they lie in memory, then the bytes that pad
    /// its end, if any.
    private func defineBody(of id: StructID, in context: borrowing Context) {
        // Lay the fields out in the order the table puts them in memory.
        let layout = table.structLayout(of: id)
        let fields = table[id].fields
        var body: [any TypeHandle] = layout.layoutOrder.map { llvmType(fields[$0].type) }

        // The bytes that pad the end, if there are any, hold nothing.
        if layout.endPadding > 0 { body.append(context.arrayType(of: int8, count: layout.endPadding)) }

        // A packed struct has no padding of LLVM's between its fields, so each lies at the table's offset.
        structs[id.index].setFields(body, packed: true)
    }
}
