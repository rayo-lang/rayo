import RayoDiagnostics
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
    /// laid out. A struct can't take the name of one of `functions` that comes before it.
    func declare(_ structs: [StructDecl], besides functions: [FuncDecl],
                 in declarations: inout Declarations) -> TypeTable? {
        let ids = declareNames(of: structs, besides: functions, in: &declarations)
        // A field may name any struct, so every name is declared before a field is checked.
        let declared = checkFields(of: structs, declaredAs: ids, in: declarations)
        guard !reportContainment(among: declared) else { return nil }
        return types(of: declared)
    }

    /// Declares the name of each of `structs`, numbering them in source order, and returns their IDs, nil for each
    /// whose name was taken.
    private func declareNames(of structs: [StructDecl], besides functions: [FuncDecl],
                              in declarations: inout Declarations) -> [StructID?] {
        var ids: [StructID?] = []
        var nextIndex = 0
        for declaration in structs {
            // A struct whose name is taken is reported, and gets no ID.
            guard hasFreeName(declaration, besides: functions, in: declarations) else {
                ids.append(nil)
                continue
            }
            let id = StructID(index: nextIndex, name: declaration.name)
            declarations.declare(id)
            ids.append(id)
            nextIndex += 1
        }
        return ids
    }

    /// Whether `declaration` may take its name, reporting it when the name is `_`, another struct's, or that of one
    /// of `functions` that comes before it.
    private func hasFreeName(_ declaration: StructDecl, besides functions: [FuncDecl],
                             in declarations: Declarations) -> Bool {
        // `_` names nothing.
        guard declaration.name != "_" else {
            errors.report(.underscoreDeclared, at: declaration.nameRange)
            return false
        }
        let isAnotherStructsName = declarations.structure(named: declaration.name) != nil
        // A struct or a function before it holds the name already.
        guard !isAnotherStructsName, !isNameOfEarlierFunction(declaration, among: functions) else {
            errors.report(.alreadyDeclared(name: declaration.name), at: declaration.nameRange)
            return false
        }
        return true
    }

    /// Whether one of `functions` that comes before `declaration` has its name.
    private func isNameOfEarlierFunction(_ declaration: StructDecl, among functions: [FuncDecl]) -> Bool {
        functions.contains { $0.name == declaration.name && $0.nameRange.start < declaration.nameRange.start }
    }

    /// Checks the fields of each of `structs`, and returns those that `ids`, which follows their order, gives an ID,
    /// with their fields' types.
    private func checkFields(of structs: [StructDecl], declaredAs ids: [StructID?],
                             in declarations: Declarations) -> [DeclaredStruct] {
        var declared: [DeclaredStruct] = []
        for (declaration, id) in zip(structs, ids) {
            let fieldTypes = checkFields(of: declaration, in: declarations)
            // A struct whose name was taken has its fields checked, and is declared no further.
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
            types.append(type(of: field, in: declarations))
        }
        return types
    }

    /// Checks that `field`'s name is neither `_` nor one of `names`, the names of the fields before it, reporting
    /// it when it is, and adds the name to `names`.
    private func checkName(of field: FieldDecl, besides names: inout Set<String>) {
        // `_` names nothing.
        if field.name == "_" {
            errors.report(.underscoreDeclared, at: field.nameRange)
        } else if !names.insert(field.name).inserted {
            // A field before it has the name already.
            errors.report(.alreadyDeclared(name: field.name), at: field.nameRange)
        }
    }

    /// The type of `field`, reporting it when the field has none, or one that holds no value.
    private func type(of field: FieldDecl, in declarations: Declarations) -> RayoType? {
        // A field must write its type.
        guard let written = field.type else {
            errors.report(.missingFieldType(name: field.name), at: field.nameRange)
            return nil
        }
        let type = declarations.resolve(written, reporting: errors)
        // A field of type Void would hold no value.
        guard type != .void else {
            errors.report(.voidField, at: written.range)
            return nil
        }
        return type
    }

    /// Reports each of `structs`, which are indexed by `StructID`, that contains itself through its fields at any
    /// depth, and returns whether any does.
    private func reportContainment(among structs: [DeclaredStruct]) -> Bool {
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
