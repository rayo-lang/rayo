/// A program's structs, and how a value of each of its types lies in memory.
public struct TypeTable: Equatable, Sendable {
    /// The structs, indexed by `StructID`.
    public let structs: [StructType]
    /// The layout of each struct, indexed by `StructID`.
    private let layouts: [StructLayout]

    /// The table of `structs`, none of which contains itself through its fields, at any depth.
    public init(structs: [StructType]) {
        self.structs = structs

        // Lay out each struct once, those its fields hold before it.
        var laidOut: [StructLayout?] = Array(repeating: nil, count: structs.count)
        layouts = structs.indices.map { Self.layout(ofStruct: $0, in: structs, laidOut: &laidOut) }
    }

    /// The table of a program that declares no struct.
    public static let empty = TypeTable(structs: [])

    /// The ID of each struct, in the order of `structs`.
    public var ids: [StructID] {
        structs.indices.map { StructID(index: $0, name: structs[$0].name) }
    }

    public subscript(id: StructID) -> StructType {
        structs[id.index]
    }

    public func structLayout(of id: StructID) -> StructLayout {
        layouts[id.index]
    }

    public func layout(of type: RayoType) -> Layout {
        Self.layout(of: type) { layouts[$0.index].layout }
    }

    /// The layout of `type`, given that of each struct.
    private static func layout(of type: RayoType, structLayout: (StructID) -> Layout) -> Layout {
        switch type {
        case .int: .int
        case .bool: .bool
        case .structure(let id): structLayout(id)
        case .void: preconditionFailure("no value of type Void lies in memory")
        }
    }

    /// The layout of the struct at `index` in `structs`. `laidOut` keeps it, with the layout of each struct it holds.
    private static func layout(
        ofStruct index: Int, in structs: [StructType], laidOut: inout [StructLayout?],
    ) -> StructLayout {
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
