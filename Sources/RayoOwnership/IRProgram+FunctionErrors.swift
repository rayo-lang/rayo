import RayoDiagnostics
import RayoIR
import RayoSema

extension IRProgram {
    /// The errors that `check` finds in the body of each function that has one, each function's in source order,
    /// under the IDs of the functions it finds any in.
    func errors(foundBy check: (FunctionID, IRBody) -> [Diagnostic]) -> [FunctionID: [Diagnostic]] {
        var errors: [FunctionID: [Diagnostic]] = [:]
        for (id, body) in definedFunctions {
            let found = check(id, body)
            // The sort is stable, so errors at one place keep the order `check` gives them, such as a compound
            // assignment's use of a local before its store to it.
            if !found.isEmpty { errors[id] = found.inSourceOrder }
        }
        return errors
    }
}
