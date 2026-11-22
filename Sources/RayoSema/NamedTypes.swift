import RayoCheckedProgram

/// The file's named types, of every kind, which share one namespace: the type each name declares, the types whose
/// declarations failed, and, once the types are checked, the table of those that can be laid out, with their fields.
struct NamedTypes {
    /// The type each name declares.
    private var ids: [String: TypeID] = [:]
    /// The names of the types whose declarations failed to parse, which name no type.
    private var unparsed: Set<String> = []
    /// The types that can't be laid out, whose uses report nothing more.
    private var unlaidOut: Set<TypeID> = []
    /// The types that can be laid out, which lay out every type that holds them; nil until the types are checked,
    /// while their fields' types are resolved.
    private var table: TypeTable?

    /// Declares `name` as the name of the type `id`.
    mutating func declare(_ name: String, as id: TypeID) {
        ids[name] = id
    }

    /// Declares `name` as the name of a type whose declaration failed to parse, which names no type.
    mutating func declareUnparsed(_ name: String) {
        unparsed.insert(name)
    }

    /// Declares the type `id` as one that can't be laid out, whose uses report nothing more.
    mutating func declareUnlaidOut(_ id: TypeID) {
        unlaidOut.insert(id)
    }

    /// Declares `table`, the types that can be laid out, so that each type resolved from here on is checked to fit in
    /// memory.
    mutating func declare(_ table: TypeTable) {
        self.table = table
    }

    /// Whether a type of the file is called `name`, whether or not its declaration parsed.
    func isDeclared(_ name: String) -> Bool {
        ids[name] != nil || unparsed.contains(name)
    }

    /// The type called `name`, or nil where no type has the name, or the declaration of the type that has it failed
    /// to parse.
    func type(named name: String) -> RayoType? {
        ids[name].map(RayoType.named)
    }

    /// Whether the type called `name` failed to parse, or can't be laid out.
    func hasFailed(named name: String) -> Bool {
        guard let id = ids[name] else { return unparsed.contains(name) }
        return unlaidOut.contains(id)
    }

    /// Whether the size of a value of `type`, which isn't Void, fits in an Int. Every type fits until the types are
    /// checked, which reports those that don't.
    func fitsInMemory(_ type: RayoType) -> Bool {
        table?.fitsInMemory(type) ?? true
    }

    /// Whether a value of `type`, which fits in memory, may lie on the stack. Only a body or a function's signature
    /// asks, once the types are laid out.
    func fitsOnStack(_ type: RayoType) -> Bool {
        guard let table else { preconditionFailure("the types aren't laid out yet, so no value lies on the stack") }
        return table.fitsOnStack(type)
    }

    /// The fields of the struct `id`, which must be laid out, in the order it declares them.
    func fields(of id: StructID) -> [Field] {
        // The checker lays out the types before it checks a body, which alone asks for fields.
        guard let table else { preconditionFailure("the types aren't laid out yet, so '\(id.name)' has no fields") }
        return table[id].fields
    }
}
