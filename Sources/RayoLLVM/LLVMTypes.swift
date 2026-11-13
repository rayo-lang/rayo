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

    /// The LLVM type that holds a value of the struct `id`.
    func llvmStruct(_ id: StructID) -> LLVM.StructType {
        structs[id.index]
    }

    /// The alignment, in bytes, that a value of `type`, which isn't Void, has in memory.
    func alignment(of type: RayoType) -> Int {
        table.layout(of: type).alignment
    }

    /// How a value of `type`, which isn't Void, lies in memory.
    func layout(of type: RayoType) -> Layout {
        table.layout(of: type)
    }

    /// The scalars a value of `type` splits into: an Int or a Bool is one, a struct is its fields' scalars in the
    /// order it declares the fields, and Void is none.
    func scalars(of type: RayoType) -> [Scalar] {
        switch type {
        // An Int or a Bool is a scalar of its own.
        case .int, .bool:
            [Scalar(fields: [], type: type)]

        // Void holds nothing.
        case .void:
            []

        // A struct is the scalars of each field in turn, each lying inside its field.
        case .structure(let id):
            table[id].fields.enumerated().flatMap { index, field in
                scalars(of: field.type).map { Scalar(fields: [index] + $0.fields, type: $0.type) }
            }
        }
    }

    /// The type of each field of the struct `id`, in the order the struct declares them, and the index of the element
    /// of the struct's LLVM type that holds it.
    func fields(of id: StructID) -> [(type: RayoType, element: Int)] {
        // The elements hold the fields in the order they lie in memory, so each field's element is its place there.
        var elements = Array(repeating: 0, count: table[id].fields.count)
        for (element, field) in table.structLayout(of: id).layoutOrder.enumerated() {
            elements[field] = element
        }
        return zip(table[id].fields, elements).map { ($0.type, $1) }
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
