import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks a file's structs: that each has a name of its own, that its fields have names of their own and types that
/// hold values, and that none contains itself. It declares each struct's type.
struct StructChecker {
    /// A struct whose declaration took its name, with the types of its fields, nil where one isn't known.
    private struct DeclaredStruct {
        var id: StructID
        var declaration: StructDecl
        var fieldTypes: [RayoType?]
    }

    let errors: ErrorList

    /// Declares the types of `structs` in `declarations`, and returns the types they make, or nil when they can't be
    /// laid out. A struct whose name `names` gives to functions is reported, and still declared.
    func declare(
        _ structs: [StructDecl], among names: TopLevelNames, in declarations: inout Declarations,
    ) -> TypeTable? {
        let ids = declareNames(of: structs, among: names, in: &declarations)

        // A field may name any struct, so every name is declared before a field is checked.
        let declared = checkStructs(structs, withIDs: ids, in: declarations)

        guard !reportSelfContaining(among: declared) else { return nil }

        return types(of: declared)
    }

    /// Declares the name of each of `structs`, numbering them in source order, and returns their IDs, nil for each
    /// whose name is `_` or another struct's. A struct whose name `names` gives to functions is reported, and still
    /// declared.
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
            reportNameOfFunctions(declaration, among: names)
            let id = StructID(index: nextIndex, name: declaration.name)
            declarations.declare(id)
            ids.append(id)
            nextIndex += 1
        }
        return ids
    }

    /// Whether `declaration` may take its name, reporting it when the name is `_` or another struct's.
    private func hasFreeName(_ declaration: StructDecl, in declarations: Declarations) -> Bool {
        // A struct named `_` was reported.
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
    private func reportNameOfFunctions(_ declaration: StructDecl, among names: TopLevelNames) {
        // A function before it holds the name already.
        if names.holder(of: declaration.name) == .functions {
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
            let fieldTypes = checkFields(of: declaration, in: declarations)
            // A struct with no ID has its fields checked, and is declared no further.
            if let id { declared.append(DeclaredStruct(id: id, declaration: declaration, fieldTypes: fieldTypes)) }
        }
        return declared
    }

    /// Checks the fields of `declaration`, and returns their types, nil for each whose type isn't known.
    private func checkFields(of declaration: StructDecl, in declarations: Declarations) -> [RayoType?] {
        var names: Set<String> = []
        var types: [RayoType?] = []
        for field in declaration.fields {
            checkName(of: field, besides: &names)
            types.append(checkType(of: field, in: declarations))
        }
        return types
    }

    /// Checks that `field`'s name is neither `_` nor one of `names`, the names of the fields before it, reporting
    /// it when it is, and adds the name to `names`.
    private func checkName(of field: FieldDecl, besides names: inout Set<String>) {
        // A field named `_` was reported.
        guard isNaming(field.name, at: field.nameRange) else { return }
        // A field before it has the name already.
        if !names.insert(field.name).inserted {
            errors.report(.alreadyDeclared(name: field.name), at: field.nameRange)
        }
    }

    /// Checks `field`'s type and default value, and returns the type, nil where it isn't known. Reports a field with
    /// no type, one whose type holds no value, and a default value, which rayoc doesn't support.
    private func checkType(of field: FieldDecl, in declarations: Declarations) -> RayoType? {
        // A default value is reported, and the field is checked as though it had none.
        if let defaultValue = field.defaultValue { errors.report(.fieldDefault, at: defaultValue.range) }

        // A field that writes no type has none to check.
        guard let written = field.type else {
            // A field with no default value needs its type written; one with a default, reported above, would take
            // its type from the default.
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
