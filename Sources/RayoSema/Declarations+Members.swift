extension Declarations {
    /// The member of `type` called `name`, or nil where `type` has none. A type's initializers are its members called
    /// `init`.
    func member(named name: String, of type: RayoType) -> Member? {
        switch type {
        case .named(.structure(let id)): structMember(named: name, of: id)
        case .array(let count, let element): arrayMember(named: name, count: count, element)
        case .scalar, .void: preludeMember(named: name, of: type)
        }
    }

    /// The member of the struct `id` called `name`: one of its fields, or its primary initializer.
    private func structMember(named name: String, of id: StructID) -> Member? {
        if name == Member.initializerName { return .initializers(.primary(id)) }
        let fields = types.fields(of: id)
        return fields.firstIndex { $0.name == name }.map { .field(index: $0, fields[$0]) }
    }

    /// The member called `name` of the array of `count` values of `element`: its count, or its `init(repeating:)`.
    private func arrayMember(named name: String, count: Int, _ element: RayoType) -> Member? {
        switch name {
        case "count": .count(count)
        case Member.initializerName: .initializers(.overloads([Signature(fillingArrayOf: count, element)]))
        default: nil
        }
    }

    /// The member of the prelude type `type` called `name`: the built-ins that initialize it, where it has any.
    private func preludeMember(named name: String, of type: RayoType) -> Member? {
        guard name == Member.initializerName else { return nil }
        let initializers = Builtin.allCases.filter { $0.initializedType == type }.map(Signature.init(of:))
        return initializers.isEmpty ? nil : .initializers(.overloads(initializers))
    }
}
