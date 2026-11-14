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

    /// Checks each struct's fields, declares them, and returns the types the structs make. The IDs follow the order
    /// of the structs, with nil for a struct whose name couldn't be declared. A struct that can't be laid out is
    /// declared as such, and makes no type.
    func declare(
        _ structs: [StructDecl], withIDs ids: [StructID?], in declarations: inout Declarations,
    ) -> TypeTable {
        let declared = checkStructs(structs, withIDs: ids, in: declarations)
        declareFields(of: declared, in: &declarations)

        // Only once every struct's fields are known can the structs that fail be told.
        let failed = failedStructs(among: declared)
        for id in failed { declarations.declareUnlaidOut(id) }
        return types(of: declared, besides: failed)
    }

    /// Checks every struct's fields, and returns each struct that has an ID, with what checking its fields found.
    /// The IDs follow the order of the structs.
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

    /// Checks the fields of one struct, and returns what checking each found.
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

    /// Declares each struct's fields, as a function body sees them.
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

    /// The IDs of the structs among `structs`, which are indexed by `StructID`, that can't be laid out: each with a
    /// field whose type isn't known or that has no name of its own, each that contains itself through its fields at
    /// any depth, which is reported, and each that contains one of those.
    private func failedStructs(among structs: [DeclaredStruct]) -> Set<StructID> {
        // A field that failed was reported where it is written.
        let withFailedFields = structs.filter { $0.fields.contains { $0.type == nil || !$0.hasOwnName } }

        // A struct that contains itself is reported at its name.
        let containingItself = structs.filter { contained(in: $0, among: structs).contains($0.id.index) }
        for structure in containingItself {
            errors.report(.containsItself(name: structure.id.name), at: structure.declaration.nameRange)
        }

        // A struct that contains one that failed fails with it, and reports nothing more.
        let failed = Set((withFailedFields + containingItself).map(\.id.index))
        let containingFailed = structs.filter { !contained(in: $0, among: structs).isDisjoint(with: failed) }
        return Set((withFailedFields + containingItself + containingFailed).map(\.id))
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

    /// The types `structs` make, which are indexed by `StructID`, with none for those of `failed`.
    private func types(of structs: [DeclaredStruct], besides failed: Set<StructID>) -> TypeTable {
        TypeTable(entries: structs.map { failed.contains($0.id) ? nil : type(of: $0) })
    }

    /// The type `structure` makes, or nil where the type of one of its fields isn't known.
    private func type(of structure: DeclaredStruct) -> StructType? {
        let fields = zip(structure.declaration.fields, structure.fields).compactMap { field, checked in
            checked.type.map { Field(name: field.name, type: $0) }
        }
        // A field whose type isn't known is left out, so the struct has fewer fields than it declares.
        guard fields.count == structure.fields.count else { return nil }
        return StructType(name: structure.id.name, fields: fields)
    }
}
