import RayoSource
import RayoSyntax

/// Declares the names of a file's types, of every kind, before anything resolves a type, so that a type may name any
/// type of the file. Types of every kind share one namespace.
struct TypeNameChecker {
    let errors: ErrorList

    /// Declares the name of each of `file`'s types in `declarations`, and returns the IDs it gives them. A type whose
    /// name is `_` or another type's is reported, and gets no ID. A type whose name belongs to the file's functions
    /// is reported, and still declared.
    func declare(_ file: SourceFile, in declarations: inout Declarations) -> TypeIDs {
        TypeIDs(structs: declareStructs(file.structs, in: &declarations))
    }

    /// Declares the name of each of `structs`, numbering them in source order, and returns their IDs, nil for each
    /// that takes no name.
    private func declareStructs(_ structs: [StructDecl], in declarations: inout Declarations) -> [StructID?] {
        var ids: [StructID?] = []
        var nextIndex = 0
        for declaration in structs {
            // A struct that takes no name is skipped in the numbering, so each struct lies at its ID's index.
            let id = StructID(index: nextIndex, name: declaration.name)
            guard declare(.structure(id), at: declaration.nameRange, in: &declarations) else {
                ids.append(nil)
                continue
            }
            ids.append(id)
            nextIndex += 1
        }
        return ids
    }

    /// Declares `type`, whose name is written at `range`, and returns whether it did. Reports a name that is `_` or
    /// another type's, which `type` doesn't take, and one that belongs to the file's functions, which it still does.
    private func declare(_ type: DeclaredType, at range: SourceRange, in declarations: inout Declarations) -> Bool {
        // A type named `_` names nothing.
        guard type.name != "_" else {
            errors.report(.underscoreDeclared, at: range)
            return false
        }
        // A type before it holds the name already, whatever its kind.
        guard declarations.type(named: type.name) == nil else {
            errors.report(.alreadyDeclared(name: type.name), at: range)
            return false
        }

        // Declare the type even when its name belongs to functions: a type is looked up apart from a function, so
        // the type's uses still find it, and raise no error of their own.
        if declarations.kind(of: type.name) == .functions {
            errors.report(.alreadyDeclared(name: type.name), at: range)
        }
        declarations.declare(type)
        return true
    }
}
