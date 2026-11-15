import RayoSyntax

extension TypeID {
    /// The ID of the type that `declaration` declares, as the program's named type at `index`, or nil where it
    /// declares no type, or failed to parse.
    init?(declaredBy declaration: Declaration, at index: Int) {
        switch declaration {
        case .structure(let structure): self = .structure(StructID(index: index, name: structure.name))
        case .function, .failed: return nil
        }
    }
}
