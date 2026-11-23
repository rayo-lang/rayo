import RayoCheckedProgram
import RayoDiagnostics
import RayoIR

/// Checks that some code reads each value a program assigns to a local, or to a field inside one, and each value the
/// function's entry stores in a parameter.
enum UnusedValueChecker {
    /// Reports each parameter whose value the entry stores and no code reads, where the source declares it, and each
    /// place that assigns a local, or a field inside one, a value that no code reads, in the body whose places
    /// `places` gives the types of, where `uses` says what code after each of its points uses.
    static func errors(in places: PlaceTypes, uses: DataflowResults<AccessUseState>) -> [Diagnostic] {
        unreadParameters(of: places.body, uses: uses)
            + places.body.blocks.indices.flatMap { errors(in: BlockID(index: $0), of: places, uses: uses) }
    }

    /// The parameters whose values the function's entry stores and no code reads, each reported where the source
    /// declares it, where `uses` says what code reads after each point of `body`.
    private static func unreadParameters(
        of body: IRBody, uses: DataflowResults<AccessUseState>,
    ) -> [Diagnostic] {
        // What code reads from the entry on, which every path through the function starts at, is the state at the
        // first point of the first block.
        var unread: [Diagnostic] = []
        uses.walk(BlockID(index: 0)) { point, state in
            guard point == 0 else { return }
            unread = body.locals.indices.compactMap { index in
                guard case .source(let name, .parameter(let convention), _, let range) = body.locals[index],
                      convention.isStoredAtEntry, !state.values.reads(Place(root: LocalID(index: index)))
                else { return nil }
                return Diagnostic(.unreadParameter(name: name), at: range)
            }
        }
        return unread
    }

    /// The stores in `block` of a value that no code reads, where `uses` says what code reads after each of them. A
    /// block that no path reaches has no state, and nothing in it is checked.
    private static func errors(
        in block: BlockID, of places: PlaceTypes, uses: DataflowResults<AccessUseState>,
    ) -> [Diagnostic] {
        let statements = places.body.blocks[block.index].statements
        var errors: [Diagnostic] = []
        uses.walk(block) { point, state in
            // The state after a statement is the one at the point after it; the first point follows none.
            guard point > 0, point <= statements.count else { return }
            if let error = error(at: statements[point - 1], followedBy: state, in: places) { errors.append(error) }
        }
        return errors
    }

    /// The error at `statement` where it stores a value that no code reads, where the code after it uses what `uses`
    /// holds, or nil where it doesn't.
    private static func error(
        at statement: Statement, followedBy uses: AccessUseState, in places: PlaceTypes,
    ) -> Diagnostic? {
        // A statement that stores a value does so last, so the code after the statement is the code after the store.
        guard case .store(let destination)? = statement.effects.last else { return nil }
        // A store that some code reads leaves nothing to report.
        guard !uses.values.reads(destination.place) else { return nil }
        // Lowering reads each temporary it writes, so only a local of the source leaves a value unread.
        guard let name = places.sourceName(of: destination.place) else { return nil }
        return Diagnostic(.unreadValue(name: name), at: destination.range)
    }
}
