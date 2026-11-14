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

    /// How a value of `type`, which isn't Void, lies in memory. Checking reports a type whose size doesn't fit in an
    /// Int, so the type must have a layout.
    public func layout(of type: RayoType) -> Layout {
        guard let layout = layout(of: type, inside: []) else {
            preconditionFailure("\(type) is too large to lay out")
        }
        return layout
    }

    /// How the fields of `type`, which must be a struct whose size fits in an Int, lie in its memory.
    public func structLayout(of type: RayoType) -> StructLayout {
        guard let layout = structLayout(of: type, inside: []) else {
            preconditionFailure("\(type) is too large to lay out")
        }
        return layout
    }

    /// Whether the size of a value of `type`, which isn't Void, fits in an Int, so that the value can lie in memory.
    func fitsInMemory(_ type: RayoType) -> Bool {
        layout(of: type, inside: []) != nil
    }

    /// The structs laid out so far.
    var laidOut: Set<RayoType> {
        layouts.cache.withLock { Set($0.keys) }
    }

    /// Whether `left` and `right` declare the same structs, which decide every layout.
    public static func == (left: TypeTable, right: TypeTable) -> Bool {
        left.entries == right.entries
    }

    /// The layout of `type`, which lies inside each struct of `enclosing`, or nil where its size doesn't fit in an
    /// Int.
    private func layout(of type: RayoType, inside enclosing: [RayoType]) -> Layout? {
        switch type {
        case .int: .int
        case .uint: .uint
        case .bool: .bool
        case .structure: structLayout(of: type, inside: enclosing)?.layout
        case .array(let count, let element): layout(of: element, inside: enclosing)?.array(of: count)
        case .void: preconditionFailure("no value of type Void lies in memory")
        }
    }

    /// The layout of the struct `type`, which lies inside each struct of `enclosing`, or nil where its size doesn't
    /// fit in an Int.
    private func structLayout(of type: RayoType, inside enclosing: [RayoType]) -> StructLayout? {
        // A struct laid out already keeps its layout.
        if let known = layouts.cache.withLock({ $0[type] }) { return known }

        // Lay out the fields first, since a field's layout is its type's. Checking reports a struct that contains
        // itself, so none reaches a layout. A field too large to lay out makes the struct too large.
        precondition(!enclosing.contains(type), "a struct that contains itself has no layout")
        var fields: [Layout] = []
        for field in self.fields(of: type) {
            guard let layout = layout(of: field.type, inside: enclosing + [type]) else { return nil }
            fields.append(layout)
        }
        guard let layout = StructLayout(fields: fields) else { return nil }

        // Two threads that lay out one struct at once work out the same layout, so either may keep it.
        layouts.cache.withLock { $0[type] = layout }
        return layout
    }
}

/// The struct layouts a `TypeTable` has worked out, shared by the threads that ask it.
private final class StructLayouts: Sendable {
    let cache = Mutex<[RayoType: StructLayout]>([:])
}
