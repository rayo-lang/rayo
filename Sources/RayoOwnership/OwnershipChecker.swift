import RayoCheckedProgram
import RayoDiagnostics
import RayoIR
import RayoStageThread

/// Checks what each function of a lowered program does with its places: its moves, the values its locals hold at each
/// use, its accesses, and the values it leaves unread. It writes the end of each access and the retirement of each
/// local into the program, which the emitter then receives.
public enum OwnershipChecker {
    /// The program with the end of each access and the retirement of each local written into the body of each function
    /// that passes every check, and without the body of each function that fails one, and the errors the checks find,
    /// under the ID of each function that has any, in source order.
    package static func check(
        _ program: IRProgram, on thread: borrowing StageThread,
    ) -> (program: IRProgram, errors: [FunctionID: [Diagnostic]]) {
        var checked = program
        var errors: [FunctionID: [Diagnostic]] = [:]
        for (id, body) in program.definedFunctions {
            let places = PlaceTypes(body: body, types: program.types)
            let (ended, found) = check(places)
            checked.bodies[id] = ended
            // The sort is stable, so errors at one place keep the order the check gives them, such as a compound
            // assignment's use of a local before its store to it.
            if !found.isEmpty { errors[id] = found.inSourceOrder }
        }
        return (checked, errors)
    }

    /// Runs the checks in turn on the body whose places `places` gives the types of. It stops at the first check that
    /// finds errors, so that no later check reports the same mistake again, and gives those errors, without the body.
    /// Every diagnostic these checks report is an error, so any of them fails the function. A body that passes every
    /// check comes back with the end of each access and the retirement of each local written in.
    private static func check(_ places: PlaceTypes) -> (body: IRBody?, errors: [Diagnostic]) {
        // A use of a place after a move out of a borrowed parameter or element isn't reported again as a use after a
        // move.
        let moves = MoveChecker.errors(in: places)
        guard moves.isEmpty else { return (nil, moves) }

        // A misused local, such as a `let` assigned twice, isn't reported again for the accesses it is in, or for the
        // values it leaves unread.
        let missing = InitializationChecker.errors(in: places)
        guard missing.isEmpty else { return (nil, missing) }

        // What code after each point uses is solved once, and serves both where accesses end and which values no
        // code reads.
        let uses = DataflowSolver.solve(from: AccessUseState(), through: places.body, knowing: places)
        let (ended, conflicts) = ExclusivityChecker.check(places, uses: uses)
        guard conflicts.isEmpty else { return (nil, conflicts) }

        let unread = UnusedValueChecker.errors(in: places, uses: uses)
        guard unread.isEmpty else { return (nil, unread) }

        // The retirements are written into the body that already has the ends of its accesses, because an access's end
        // uses the local it reaches. If they were written in before the ends, a local could retire while an access
        // still reaches it.
        return (LocalRetirements.written(into: ended), [])
    }
}
