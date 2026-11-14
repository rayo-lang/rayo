import RayoDiagnostics
import RayoSyntax

/// Checks a file's structs, whose names are declared already: that their fields have names of their own and types
/// that hold values, and that none contains itself. It declares each struct's fields and lays out its type.
struct StructChecker {
    /// A struct whose declaration took its name, with what checking each of its fields found, in declaration order.
    private struct DeclaredStruct {
        var id: StructID
        var declaration: StructDecl
        var fields: [CheckedField]
    }

    /// What checking a field's declaration found.
    private struct CheckedField {
        /// The type, or nil where it isn't known.
        var type: RayoType?
        /// Whether the name is neither `_` nor another field's.
        var hasOwnName: Bool
    }

    let errors: ErrorList

    /// Declares the fields of `structs`, whose IDs are `ids`, in `declarations`, and returns the types they make, or
    /// nil when they can't be laid out. `ids` follows the order of `structs`, nil for each struct whose name wasn't
    /// declared.
    func declare(
        _ structs: [StructDecl], withIDs ids: [StructID?], in declarations: inout Declarations,
    ) -> TypeTable? {
        let declared = checkStructs(structs, withIDs: ids, in: declarations)
        declareFields(of: declared, in: &declarations)

        guard !reportSelfContaining(among: declared) else { return nil }

        return types(of: declared)
    }

    /// Checks the fields of each of `structs`, and returns those that `ids`, which follows their order, gives an ID,
    /// with their fields' types.
    private func checkStructs(
        _ structs: [StructDecl], withIDs ids: [StructID?], in declarations: Declarations,
    ) -> [DeclaredStruct] {
        var declared: [DeclaredStruct] = []
        for (declaration, id) in zip(structs, ids) {
            let fields = checkFields(of: declaration, in: declarations)
            // A struct with no ID has its fields checked, and is declared no further.
            guard let id else { continue }
            // IDs number the structs that have them in order, so each struct lies at its ID's index.
            precondition(id.index == declared.count, "a declared struct lies at its ID's index")
            declared.append(DeclaredStruct(id: id, declaration: declaration, fields: fields))
        }
        return declared
    }

    /// Checks the fields of `declaration`, and returns what checking each found.
    private func checkFields(of declaration: StructDecl, in declarations: Declarations) -> [CheckedField] {
        var names: Set<String> = []
        var fields: [CheckedField] = []
        for field in declaration.fields {
            let hasOwnName = checkName(of: field, besides: &names)
            reportDefault(of: field)
            fields.append(CheckedField(type: checkType(of: field, in: declarations), hasOwnName: hasOwnName))
        }
        return fields
    }

    /// Declares the fields of each of `structs`, as a function body sees them.
    private func declareFields(of structs: [DeclaredStruct], in declarations: inout Declarations) {
        for structure in structs {
            // A body sees no type for a field without a name of its own, so neither a call nor a read can pick it.
            let fields = zip(structure.declaration.fields, structure.fields).map { declaration, checked in
                DeclaredField(
                    name: declaration.name, kind: declaration.kind, type: checked.hasOwnName ? checked.type : nil,
                )
            }
            declarations.declare(fields, of: structure.id)
        }
    }

    /// Reports `field`'s default value, if it has one, since rayoc doesn't support a field's default.
    private func reportDefault(of field: FieldDecl) {
        // A field's default is reported where it is written.
        if let defaultValue = field.defaultValue { errors.report(.fieldDefault, at: defaultValue.range) }
    }

    /// Whether `field`'s name is neither `_` nor one of `names`, the names of the fields before it, reporting it
    /// when it is. Adds the name to `names`.
    private func checkName(of field: FieldDecl, besides names: inout Set<String>) -> Bool {
        // A field named `_` is reported, and its name is checked no further.
        guard errors.isNaming(field.name, at: field.nameRange) else { return false }
        // A field before it has the name already.
        guard names.insert(field.name).inserted else {
            errors.report(.alreadyDeclared(name: field.name), at: field.nameRange)
            return false
        }
        return true
    }

    /// Checks `field`'s type, and returns it, nil where it isn't known. Reports a field with neither a type nor a
    /// default value, and one whose type holds no value.
    private func checkType(of field: FieldDecl, in declarations: Declarations) -> RayoType? {
        // A field that writes no type has none to check.
        guard let written = field.type else {
            // A field with no default value needs its type written; one with a default, which is reported apart,
            // would take its type from the default.
            if field.defaultValue == nil {
                errors.report(.missingFieldType(name: field.name), at: field.nameRange)
            }
            return nil
        }

        // Resolve the written type, which must hold a value.
        let type = declarations.resolve(written, reporting: errors)
        // A field of type Void would hold no value.
        guard type != .void else {
            errors.report(.voidField(type: declarations.typeName(of: .void)), at: written.range)
            return nil
        }
        return type
    }

    /// Reports each of `structs`, which are indexed by `StructID`, that contains itself through its fields at any
    /// depth, and returns whether it reported any.
    private func reportSelfContaining(among structs: [DeclaredStruct]) -> Bool {
        let containing = structs.filter { contained(in: $0, among: structs).contains($0.id.index) }
        for structure in containing {
            errors.report(.containsItself(name: structure.id.name), at: structure.declaration.nameRange)
        }
        return !containing.isEmpty
    }

    /// The indices of the structs that `structure`'s fields hold, at any depth, among `structs`, which are indexed
    /// by `StructID`.
    private func contained(in structure: DeclaredStruct, among structs: [DeclaredStruct]) -> Set<Int> {
        var found: Set<Int> = []
        var unvisited = [structure]
        while let next = unvisited.popLast() {
            for case .structure(let id)? in next.fields.map(\.type) {
                // A struct found for the first time has its own fields searched in turn.
                if found.insert(id.index).inserted { unvisited.append(structs[id.index]) }
            }
        }
        return found
    }

    /// The types `structs` make, or nil when a field's type isn't known.
    private func types(of structs: [DeclaredStruct]) -> TypeTable? {
        var types: [StructType] = []
        for structure in structs {
            var fields: [Field] = []
            for (field, checked) in zip(structure.declaration.fields, structure.fields) {
                // A field whose type isn't known was reported.
                guard let type = checked.type else { return nil }
                fields.append(Field(name: field.name, type: type))
            }
            types.append(StructType(name: structure.id.name, fields: fields))
        }
        return TypeTable(structs: types)
    }
}
