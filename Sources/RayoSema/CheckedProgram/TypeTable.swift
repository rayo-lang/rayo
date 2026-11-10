/// A program's structs, and how a value of each of its types lies in memory, which code generation follows.
public struct TypeTable: Sendable {
    /// The structs, indexed by `StructID`.
    public let structs: [StructType]
    /// The layout of each struct, indexed by `StructID`.
    private let layouts: [StructLayout]

    /// The table of `structs`, none of which contains itself through its fields, at any depth.
    public init(structs: [StructType]) {
        self.structs = structs
        var laidOut: [StructLayout?] = Array(repeating: nil, count: structs.count)
        for index in structs.indices {
            _ = Self.layout(ofStruct: index, in: structs, laidOut: &laidOut)
        }
        layouts = laidOut.map { $0! }
    }

    /// The ID of each struct, in the order of `structs`.
    public var ids: [StructID] {
        structs.indices.map { StructID(index: $0, name: structs[$0].name) }
    }

    public subscript(id: StructID) -> StructType {
        structs[id.index]
    }

    public func layout(of id: StructID) -> StructLayout {
        layouts[id.index]
    }

    public func layout(of type: RayoType) -> Layout {
        Self.layout(of: type) { layouts[$0.index].layout }
    }

    /// The layout of `type`, given that of each struct.
    private static func layout(of type: RayoType, structLayout: (StructID) -> Layout) -> Layout {
        switch type {
        case .int: return .int
        case .bool: return .bool
        case .structure(let id): return structLayout(id)
        case .void: preconditionFailure("no value of type Void lies in memory")
        }
    }

    /// The layout of the struct at `index` in `structs`. `laidOut` keeps it, with the layout of each struct it holds.
    private static func layout(ofStruct index: Int, in structs: [StructType],
                               laidOut: inout [StructLayout?]) -> StructLayout {
        // A struct laid out already keeps its layout.
        if let layout = laidOut[index] { return layout }

        // Lay out the structs the fields hold first, since a field's layout is its struct's.
        let fields = structs[index].fields.map { field in
            layout(of: field.type) { layout(ofStruct: $0.index, in: structs, laidOut: &laidOut).layout }
        }
        let layout = StructLayout(fields: fields)
        laidOut[index] = layout
        return layout
    }
}

/// A struct that a program declares: its name, and its stored fields in the order the declaration gives them.
public struct StructType: Sendable {
    public var name: String
    public var fields: [Field]

    public init(name: String, fields: [Field]) {
        self.name = name
        self.fields = fields
    }
}

/// A stored field of a struct.
public struct Field: Sendable {
    public var name: String
    public var type: RayoType

    public init(name: String, type: RayoType) {
        self.name = name
        self.type = type
    }
}

/// How a struct's fields lie in its memory: each at a multiple of its alignment, with no padding but at the end.
public struct StructLayout: Hashable, Sendable {
    public var layout: Layout
    /// The fields, by their places in the declaration, in the order they lie in memory.
    public var fieldOrder: [Int]
    /// Each field's offset from the start of the struct, in bytes, indexed by its place in the declaration.
    public var fieldOffsets: [Int]
    /// The bytes after the last field, which pad the struct's size to a multiple of its alignment.
    public var endPadding: Int

    /// Lays out the fields of a struct, whose layouts `fields` gives in declaration order.
    init(fields: [Layout]) {
        // Order the fields by decreasing alignment, and those of one alignment as the declaration does.
        fieldOrder = fields.indices.sorted { first, second in
            let (firstAlignment, secondAlignment) = (fields[first].alignment, fields[second].alignment)
            return firstAlignment != secondAlignment ? firstAlignment > secondAlignment : first < second
        }

        // Lay the fields end to end in that order.
        var offsets = Array(repeating: 0, count: fields.count)
        var end = 0
        for field in fieldOrder {
            offsets[field] = end
            end += fields[field].size
        }
        fieldOffsets = offsets

        // Align the struct to its most-aligned field, and pad its end to that. An empty struct takes no memory, and
        // lies at any address.
        let alignment = fields.map(\.alignment).max() ?? 1
        layout = Layout(size: (end + alignment - 1) / alignment * alignment, alignment: alignment)
        endPadding = layout.size - end
    }
}

/// How a value lies in memory: the bytes it takes, and the alignment its address is a multiple of. The size is a
/// multiple of the alignment, so values of the type lie one after another in an array.
public struct Layout: Hashable, Sendable {
    public var size: Int
    public var alignment: Int

    public init(size: Int, alignment: Int) {
        self.size = size
        self.alignment = alignment
    }

    public static let int = Layout(size: 8, alignment: 8)
    public static let bool = Layout(size: 1, alignment: 1)
}
