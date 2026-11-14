import RayoDiagnostics
import RayoIR
import RayoSource

/// The conflicts in one function under the law of exclusivity: two accesses live at once over overlapping places,
/// where either changes its place. A move out of a place, and an assignment to it, change it at that point, and a
/// read of an operand reads it there.
struct AccessConflicts {
    /// What a use does with the place it reaches, which decides the live accesses it conflicts with, and the error.
    private enum Reach {
        case read
        case change
        case move

        /// The access the use makes of its place: a read reads it, and a change or a move changes it.
        var kind: AccessKind {
            self == .read ? .read : .modify
        }
    }

    let places: PlaceTypes
    /// The access that each statement of the body that begins one begins, by its ID.
    let accesses: [AccessID: Access]
    /// The errors found so far.
    private(set) var errors: [Diagnostic] = []

    init(places: PlaceTypes, accesses: [AccessID: Access]) {
        self.places = places
        self.accesses = accesses
    }

    /// Finds the conflicts at each statement of `block`, and at its terminator, where `live` holds the accesses live
    /// at each point of the block, as `AccessExtents.live(in:)` gives them.
    mutating func check(_ block: BlockID, live: [Set<AccessID>]) {
        let basicBlock = places.body.blocks[block.index]
        for (index, statement) in basicBlock.statements.enumerated() {
            check(statement, liveBefore: live[index], liveAfter: live[index + 1])
        }

        // A terminator's operand is read or moved where the terminator runs.
        guard let operand = basicBlock.terminator.operand else { return }
        check(operand, against: live[basicBlock.statements.count])
    }

    /// Finds the conflicts of `statement`, where `liveBefore` are the accesses live just before it and `liveAfter`
    /// those live just after it.
    private mutating func check(_ statement: Statement, liveBefore: Set<AccessID>, liveAfter: Set<AccessID>) {
        switch statement {
        // An access conflicts with each other access that is live once it has begun.
        case .begin(let id, let access):
            let reach: Reach = access.kind == .read ? .read : .change
            check(reach, of: access.place, at: access.range, against: liveAfter.subtracting([id]))

        // A computation reads and moves its operands, then changes its destination, where it has one, once it has
        // computed its value. So an access that the computation passes, and that ends with it, may reach the
        // destination.
        case .compute(let destination, let value, _):
            for operand in value.operands {
                check(operand, against: liveBefore)
            }
            guard let destination else { return }
            check(.change, of: destination.place, at: destination.range, against: liveAfter)

        // A declaration, the end of an access and a dependence reach no place.
        case .declare, .end, .depend:
            break
        }
    }

    /// Finds the conflicts of `operand` with the accesses in `live`: a read conflicts with a live modify access, and
    /// a move, which changes its place, with any live access.
    private mutating func check(_ operand: Operand, against live: Set<AccessID>) {
        switch operand {
        case .constant: break
        case .read(let place, let range): check(.read, of: place, at: range, against: live)
        case .move(let place, let range): check(.move, of: place, at: range, against: live)
        }
    }

    /// Reports each access in `live` that conflicts with a use that `reach`es `place`, which the source names at
    /// `range`: each that overlaps `place`, where it or the use may change its place.
    private mutating func check(_ reach: Reach, of place: Place, at range: SourceRange, against live: Set<AccessID>) {
        for id in live.sorted() {
            guard let held = accesses[id] else { preconditionFailure("a\(id.index) is live, but nothing begins it") }
            guard held.place.overlaps(place), reach.kind == .modify || held.kind == .modify else { continue }

            // A live modify access forbids any other access, and a live read access forbids a change or a move.
            let (name, borrowed) = (name(of: place), name(of: held.place))
            let code: ErrorCode = switch (held.kind, reach) {
            case (.modify, _): .usedWhileMutablyBorrowed(name: name, borrowed: borrowed)
            case (.read, .move): .movedWhileBorrowed(name: name, borrowed: borrowed)
            case (.read, _): .changedWhileBorrowed(name: name, borrowed: borrowed)
            }
            errors.append(Diagnostic(code, at: range, labeling: [.init(.borrowed, at: held.range)]))
        }
    }

    /// The name of `place` as the source writes it.
    private func name(of place: Place) -> String {
        guard let name = places.sourceName(of: place) else {
            preconditionFailure("lowering accesses each temporary once, so no access to one conflicts")
        }
        return name
    }
}
