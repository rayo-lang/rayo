import RayoDiagnostics
import RayoIR
import RayoSource

/// The conflicts in one function under the law of exclusivity: two accesses live at once over overlapping places,
/// where either changes its place. A move out of a place, and a store to it, change it at that point, and a read,
/// whether of an operand or of a local that holds an index, reads it there.
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
        for (index, effects) in places.body.blocks[block.index].effects.enumerated() {
            check(effects, liveAfter: live[index + 1])
        }
    }

    /// Finds the conflicts of `effects`, those of one statement or terminator, where `liveAfter` are the accesses live
    /// just after it. Each effect conflicts with the accesses live just after it: so a call's operands meet the
    /// accesses it passes, and its store meets only those that outlive it.
    private mutating func check(_ effects: [Effect], liveAfter: Set<AccessID>) {
        // Walk back from the point after the statement, to find the accesses live just after each effect.
        var live = LiveAccesses(liveAfter)
        var liveAfterEach: [Set<AccessID>] = []
        for effect in effects.reversed() {
            liveAfterEach.append(live.ids)
            live.apply(effect, in: ())
        }

        // Check the effects in their order, so that each statement's errors keep it.
        for (effect, live) in zip(effects, liveAfterEach.reversed()) {
            check(effect, against: live)
        }
    }

    /// Finds the conflicts of `effect` with the accesses in `live`: a read conflicts with a live modify access, and a
    /// move or a store, which changes its place, with any live access.
    private mutating func check(_ effect: Effect, against live: Set<AccessID>) {
        switch effect {
        case .read(let place, let range):
            check(.read, of: place, at: range, against: live)
        case .move(let place, let range):
            check(.move, of: place, at: range, against: live)
        case .store(let destination):
            check(.change, of: destination.place, at: destination.range, against: live)

        // An access conflicts with each other access that is live once it has begun.
        case .begin(let id, let access):
            let reach: Reach = access.kind == .read ? .read : .change
            check(reach, of: access.place, at: access.range, against: live.subtracting([id]))

        // Using or ending an access, starting or ending a local's life, and leaving the function reach no place
        // anew.
        case .use, .end, .declare, .retire, .exit:
            break
        }
    }

    /// Reports each access in `live` that conflicts with a use that `reach`es `place`, which the source names at
    /// `range`: each that overlaps `place`, where it or the use may change its place.
    private mutating func check(_ reach: Reach, of place: Place, at range: SourceRange, against live: Set<AccessID>) {
        for id in live.sorted() {
            guard let held = accesses[id] else { preconditionFailure("a\(id.index) is live, but nothing begins it") }
            guard held.place.mayOverlap(place), reach.kind == .modify || held.kind == .modify else { continue }

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
