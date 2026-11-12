import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks a file's structs: that each has a name of its own, that its fields have names of their own and types that
/// hold values, and that none contains itself. It declares each struct's type and fields.
struct StructChecker {
    /// A struct whose declaration took its name, with the types of its fields, nil where one isn't known.
    private struct DeclaredStruct {
        var id: StructID
        var declaration: StructDecl
        var fieldTypes: [RayoType?]
        /// The fields as a function body sees them, each without a type where its name or its type failed.
        var fields: [DeclaredField]
    }

    let errors: ErrorList

    /// Declares the types and fields of `structs` in `declarations`, and returns the types they make, or nil when
    /// they can't be laid out. A struct whose name `names` gives to functions is reported, and still declared.
    func declare(
        _ structs: [StructDecl], among names: TopLevelNames, in declarations: inout Declarations,
    ) -> TypeTable? {
        let ids = declareNames(of: structs, among: names, in: &declarations)

        // A field may name any struct, so every name is declared before a field is checked.
        let declared = checkStructs(structs, withIDs: ids, in: declarations)
        declareFields(of: declared, in: &declarations)

        guard !reportSelfContaining(among: declared) else { return nil }

        return types(of: declared)
    }

    /// Declares the name of each of `structs`, numbering them in source order, and returns their IDs, nil for each
    /// whose name is `_` or another struct's.
    private func declareNames(
        of structs: [StructDecl], among names: TopLevelNames, in declarations: inout Declarations,
    ) -> [StructID?] {
        var ids: [StructID?] = []
        var nextIndex = 0
        for declaration in structs {
            // A struct whose name is `_` or another struct's is reported, and gets no ID.
            guard hasFreeName(declaration, in: declarations) else {
                ids.append(nil)
                continue
            }

            // Number and declare the struct, even when its name belongs to functions: a type is looked up apart from
            // a function, so the struct's uses still find it, and raise no error of their own.
            reportNameTakenByFunctions(declaration, among: names)
            let id = StructID(index: nextIndex, name: declaration.name)
            declarations.declare(id)
            ids.append(id)
            nextIndex += 1
        }
        return ids
    }

    /// Whether `declaration` may take its name, reporting it when the name is `_` or another struct's.
    private func hasFreeName(_ declaration: StructDecl, in declarations: Declarations) -> Bool {
        // A struct named `_` is reported, and may not take the name.
        guard isNaming(declaration.name, at: declaration.nameRange) else { return false }
        // A struct before it holds the name already.
        guard declarations.structure(named: declaration.name) == nil else {
            errors.report(.alreadyDeclared(name: declaration.name), at: declaration.nameRange)
            return false
        }
        return true
    }

    /// Whether `name`, written at `range`, names a struct or a field, reporting it when it is `_`, which names
    /// nothing.
    private func isNaming(_ name: String, at range: SourceRange) -> Bool {
        // Any name but `_` names one.
        guard name == "_" else { return true }
        errors.report(.underscoreDeclared, at: range)
        return false
    }

    /// Reports `declaration`, the first struct of its name, when `names` gives the name to functions.
    private func reportNameTakenByFunctions(_ declaration: StructDecl, among names: TopLevelNames) {
        // A function before it holds the name already.
        if names.kind(of: declaration.name) == .functions {
            errors.report(.alreadyDeclared(name: declaration.name), at: declaration.nameRange)
        }
    }

    /// Checks the fields of each of `structs`, and returns those that `ids`, which follows their order, gives an ID,
    /// with their fields' types.
    private func checkStructs(
        _ structs: [StructDecl], withIDs ids: [StructID?], in declarations: Declarations,
    ) -> [DeclaredStruct] {
        var declared: [DeclaredStruct] = []
        for (declaration, id) in zip(structs, ids) {
            let (fieldTypes, fields) = checkFields(of: declaration, in: declarations)
            // A struct with no ID has its fields checked, and is declared no further.
            guard let id else { continue }
            // IDs number the structs that have them in order, so each struct lies at its ID's index.
            precondition(id.index == declared.count, "a declared struct lies at its ID's index")
            declared.append(DeclaredStruct(id: id, declaration: declaration, fieldTypes: fieldTypes, fields: fields))
        }
        return declared
    }

    /// Checks the fields of `declaration`, and returns their types, nil for each whose type isn't known, and the
    /// fields as a function body sees them.
    private func checkFields(
        of declaration: StructDecl, in declarations: Declarations,
    ) -> (types: [RayoType?], fields: [DeclaredField]) {
        var names: Set<String> = []
        var types: [RayoType?] = []
        var fields: [DeclaredField] = []
        for field in declaration.fields {
            let hasOwnName = checkName(of: field, besides: &names)
            reportDefault(of: field)
            let type = checkType(of: field, in: declarations)
            types.append(type)
            // A body sees no type for a field without a name of its own, so neither a call nor a read can pick it.
            fields.append(DeclaredField(name: field.name, type: hasOwnName ? type : nil))
        }
        return (types, fields)
    }

    /// Declares the fields of each of `structs`, so that a function body can make the struct and read its fields.
    private func declareFields(of structs: [DeclaredStruct], in declarations: inout Declarations) {
        for structure in structs {
            declarations.declare(structure.fields, of: structure.id)
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
        guard isNaming(field.name, at: field.nameRange) else { return false }
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
            errors.report(.voidField, at: written.range)
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
            for case .structure(let id)? in next.fieldTypes {
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
            for (field, type) in zip(structure.declaration.fields, structure.fieldTypes) {
                // A field whose type isn't known was reported.
                guard let type else { return nil }
                fields.append(Field(name: field.name, type: type))
            }
            types.append(StructType(name: structure.id.name, fields: fields))
        }
        return TypeTable(structs: types)
    }
}
