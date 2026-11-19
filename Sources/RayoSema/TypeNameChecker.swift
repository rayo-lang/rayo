import RayoCheckedProgram
import RayoSource
import RayoSyntax

/// Declares the names of a file's types, of every kind, before anything resolves a type, so that a type may name any
/// type of the file. Types of every kind share one namespace.
struct TypeNameChecker {
    let errors: ErrorList

    /// Declares the name of each of `file`'s types in `declarations`, in source order, and returns the ID of the type
    /// each of the file's declarations declares, nil for one that declares no type or gets no ID. A type whose name
    /// is `_` or another type's is reported, and gets no ID. A type whose name belongs to the file's functions is
    /// reported, and still declared. A type whose declaration failed to parse after its name takes the name, so its
    /// uses find it, and gets no ID.
    func declare(_ file: SourceFile, in declarations: inout Declarations) -> [TypeID?] {
        var ids: [TypeID?] = []
        var numbering = TypeID.Numbering()
        for declaration in file.declarations {
            // A function and a type that failed before its name get no ID.
            guard declaration.declaresType, let name = declaration.name, let nameRange = declaration.nameRange else {
                ids.append(nil)
                continue
            }
            // A type that can't take its name gets no ID either.
            guard takesName(name, at: nameRange, in: declarations) else {
                ids.append(nil)
                continue
            }

            // Only a type that takes its name is numbered, so each lies at its ID's index; one that failed to parse
            // takes the name with no ID.
            let id = numbering.id(for: declaration)
            if let id { declarations.types.declare(name, as: id) } else { declarations.types.declareUnparsed(name) }
            ids.append(id)
        }
        return ids
    }

    /// Whether a type may take `name`, which is written at `range`. Reports a name that is `_` or another type's,
    /// which the type can't take, and one that belongs to the file's functions, which it still takes.
    private func takesName(_ name: String, at range: SourceRange, in declarations: Declarations) -> Bool {
        guard errors.isNaming(name, at: range) else { return false }
        // A type before it holds the name already, whatever its kind.
        guard !declarations.types.isDeclared(name) else {
            errors.report(.alreadyDeclared(name: name), at: range)
            return false
        }

        // The type takes the name even when it belongs to functions: a type is looked up apart from a function, so
        // the type's uses still find it, and raise no error of their own.
        if declarations.kind(of: name) == .functions {
            errors.report(.alreadyDeclared(name: name), at: range)
        }
        return true
    }
}
