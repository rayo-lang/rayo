import RayoSource
import RayoSyntax

/// Declares the names of a file's types, of every kind, before anything resolves a type, so that a type may name any
/// type of the file. Types of every kind share one namespace.
struct TypeNameChecker {
    let errors: ErrorList

    /// Declares the name of each of `file`'s types in `declarations`, in source order, and returns the IDs it gives
    /// them. A type whose name is `_` or another type's is reported, and gets no ID. A type whose name belongs to the
    /// file's functions is reported, and still declared.
    func declare(_ file: SourceFile, in declarations: inout Declarations) -> TypeIDs {
        var ids = TypeIDs(structs: [])
        var nextStructIndex = 0
        for declaration in TypeDeclaration.all(in: file) {
            switch declaration {
            // Structs are numbered in source order, skipping each that takes no name, so each lies at its ID's index.
            case .structure(let structure):
                let id = StructID(index: nextStructIndex, name: structure.name)
                let isDeclared = declare(.structure(id), at: structure.nameRange, in: &declarations)
                ids.structs.append(isDeclared ? id : nil)
                if isDeclared { nextStructIndex += 1 }

            // A type that failed to parse takes its name, so its uses find it, and gets no ID.
            case .failed(let name, let range):
                _ = declare(.failed(name: name), at: range, in: &declarations)
            }
        }
        return ids
    }

    /// Declares `type`, whose name is written at `range`, and returns whether it did. Reports a name that is `_` or
    /// another type's, which `type` doesn't take, and one that belongs to the file's functions, which it still does.
    private func declare(_ type: DeclaredType, at range: SourceRange, in declarations: inout Declarations) -> Bool {
        guard errors.isNaming(type.name, at: range) else { return false }
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
