import RayoCheckedProgram
import RayoSyntax

extension TypeID {
    /// Gives the types a file declares their IDs in source order, numbering each kind apart, so that each type lies
    /// at its ID's index in its kind's table.
    struct Numbering {
        private var structCount = 0

        /// The ID of the type that `declaration` declares, or nil where it declares no type, or failed to parse.
        mutating func id(for declaration: Declaration) -> TypeID? {
            switch declaration {
            case .structure(let structure):
                defer { structCount += 1 }
                return .structure(StructID(index: structCount, name: structure.name))
            case .function, .failed:
                return nil
            }
        }
    }
}
