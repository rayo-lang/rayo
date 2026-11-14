import LLVM
import RayoIR
import RayoSema

/// The LLVM types of a program's values, and of a function's result, laid out as the program's type table says.
struct LLVMTypes {
    /// The program's structs, which the types follow.
    let table: TypeTable
    let int64: IntegerType<I64>
    let bool: IntegerType<I1>
    private let int8: IntegerType<I8>
    private let void: AnyType
    /// Makes each struct's LLVM type when it is first needed.
    private let maker: TypeMaker
    /// The LLVM type of each struct made so far, which every copy of these types shares.
    private let structs = StructTypes()

    init(_ table: TypeTable, in context: borrowing Context) {
        self.table = table
        int64 = context.integerType(I64.self)
        bool = context.integerType(I1.self)
        int8 = context.integerType(I8.self)
        void = context.voidType
        maker = context.typeMaker
    }

    /// The LLVM type that holds a value of `type`, or that a function returns when it returns nothing.
    func llvmType(_ type: RayoType) -> AnyType {
        switch type {
        case .int, .uint: int64.anyType
        case .bool: bool.anyType
        case .void: void
        case .structure: llvmStruct(type).anyType
        }
    }

    /// The LLVM type that holds a value of `type`, which must be a struct. The first ask makes it.
    func llvmStruct(_ type: RayoType) -> LLVM.StructType {
        // A struct whose type was made already keeps it.
        if let made = structs.made[type] { return made }

        let made = maker.makeStructType(named: type.description)
        made.setFields(elements(of: type), packed: true)
        structs.made[type] = made
        return made
    }

    /// The alignment, in bytes, that a value of `type`, which isn't Void, has in memory.
    func alignment(of type: RayoType) -> Int {
        table.layout(of: type).alignment
    }

    /// How a value of `type`, which isn't Void, lies in memory.
    func layout(of type: RayoType) -> Layout {
        table.layout(of: type)
    }

    /// The scalars a value of `type` splits into: an integer or a Bool is one, a struct is its fields' scalars in the
    /// order it declares the fields, and Void is none.
    func scalars(of type: RayoType) -> [Scalar] {
        switch type {
        // An integer or a Bool is a scalar of its own.
        case .int, .uint, .bool:
            [Scalar(steps: [], type: type)]

        // Void holds nothing.
        case .void:
            []

        // A struct is the scalars of each field in turn, each lying inside its field.
        case .structure:
            table.fields(of: type).enumerated().flatMap { index, field in
                scalars(of: field.type).map { Scalar(steps: [.field(index)] + $0.steps, type: $0.type) }
            }
        }
    }

    /// The type of each field of `type`, which must be a struct, in the order the struct declares them, and the
    /// index of the element of the struct's LLVM type that holds it.
    func fields(of type: RayoType) -> [(type: RayoType, element: Int)] {
        // The elements hold the fields in the order they lie in memory, so each field's element is its place there.
        let fields = table.fields(of: type)
        var elements = Array(repeating: 0, count: fields.count)
        for (element, field) in table.structLayout(of: type).layoutOrder.enumerated() {
            elements[field] = element
        }
        return zip(fields, elements).map { ($0.type, $1) }
    }

    /// The elements of the LLVM type of `type`, a struct: its fields in the order they lie in memory, then the bytes
    /// that pad its end, if any. The struct is packed, so LLVM puts no padding between them, and each field lies at
    /// the table's offset.
    private func elements(of type: RayoType) -> [any TypeHandle] {
        let layout = table.structLayout(of: type)
        let fields = table.fields(of: type)
        var elements: [any TypeHandle] = layout.layoutOrder.map { llvmType(fields[$0].type) }

        // The bytes that pad the end, if there are any, hold nothing.
        if layout.endPadding > 0 { elements.append(maker.arrayType(of: int8, count: layout.endPadding)) }
        return elements
    }
}

/// The LLVM struct types an `LLVMTypes` has made, shared by its copies so that each struct gets one.
private final class StructTypes {
    var made: [RayoType: LLVM.StructType] = [:]
}
