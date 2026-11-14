internal import Synchronization

/// A program's structs, and how a value of each of its types lies in memory. A struct whose declaration failed keeps
/// its ID, with no type under it, and no body of the program reaches it.
///
/// A type's layout is worked out the first time it's asked for, and kept for every later ask, so the stages from
/// checking on lay out only the types they use.
public struct TypeTable: Equatable, Sendable {
    /// The structs, indexed by `StructID`, nil for a struct whose declaration failed.
    private let entries: [StructType?]
    /// The layout of each struct laid out so far, which every copy of the table shares.
    private let layouts = StructLayouts()

    /// The table of `structs`, each of which checked, indexed by `StructID`.
    public init(structs: [StructType]) {
        entries = structs
    }

    /// The table of `entries`, indexed by `StructID`, nil for each struct whose declaration failed.
    init(entries: [StructType?]) {
        self.entries = entries
    }

    /// The structs whose declarations checked, in the order of their IDs.
    public var structs: [StructType] {
        entries.compactMap(\.self)
    }

    /// The table of a program that declares no struct.
    public static let empty = TypeTable(structs: [])

    /// The struct `id`, which must have checked.
    public subscript(id: StructID) -> StructType {
        // A body that reaches a failed declaration is tainted, and no stage after checking sees it.
        guard let structure = entries[id.index] else {
            preconditionFailure("'\(id.name)' failed to declare, so no checked program reaches it")
        }
        return structure
    }

    /// The fields of `type`, which must be a struct, in the order it declares them.
    public func fields(of type: RayoType) -> [Field] {
        guard case .structure(let id) = type else { preconditionFailure("only a struct holds fields") }
        return self[id].fields
    }

    /// How a value of `type`, which isn't Void, lies in memory.
    public func layout(of type: RayoType) -> Layout {
        layout(of: type, inside: [])
    }

    /// How the fields of `type`, which must be a struct, lie in its memory.
    public func structLayout(of type: RayoType) -> StructLayout {
        structLayout(of: type, inside: [])
    }

    /// The structs laid out so far.
    var laidOut: Set<RayoType> {
        layouts.cache.withLock { Set($0.keys) }
    }

    /// Whether `left` and `right` declare the same structs, which decide every layout.
    public static func == (left: TypeTable, right: TypeTable) -> Bool {
        left.entries == right.entries
    }

    /// The layout of `type`, which lies inside each struct of `enclosing`.
    private func layout(of type: RayoType, inside enclosing: [RayoType]) -> Layout {
        switch type {
        case .int: .int
        case .uint: .uint
        case .bool: .bool
        case .structure: structLayout(of: type, inside: enclosing).layout
        case .array(let count, let element): arrayLayout(of: count, layout(of: element, inside: enclosing))
        case .void: preconditionFailure("no value of type Void lies in memory")
        }
    }

    /// The layout of an array of `count` elements, each laid out as `element`. The elements lie end to end, each
    /// at its index times the element's size, which is a multiple of its alignment, so each element is aligned.
    private func arrayLayout(of count: Int, _ element: Layout) -> Layout {
        Layout(size: count * element.size, alignment: element.alignment)
    }

    /// The layout of the struct `type`, which lies inside each struct of `enclosing`.
    private func structLayout(of type: RayoType, inside enclosing: [RayoType]) -> StructLayout {
        // A struct laid out already keeps its layout.
        if let known = layouts.cache.withLock({ $0[type] }) { return known }

        // Lay out the fields first, since a field's layout is its type's. Checking reports a struct that contains
        // itself, so none reaches a layout.
        precondition(!enclosing.contains(type), "a struct that contains itself has no layout")
        let fields = fields(of: type).map { layout(of: $0.type, inside: enclosing + [type]) }

        // Two threads that lay out one struct at once work out the same layout, so either may keep it.
        let layout = StructLayout(fields: fields)
        layouts.cache.withLock { $0[type] = layout }
        return layout
    }
}

/// The struct layouts a `TypeTable` has worked out, shared by the threads that ask it.
private final class StructLayouts: Sendable {
    let cache = Mutex<[RayoType: StructLayout]>([:])
}
