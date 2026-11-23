import RayoIR
import RayoSource

/// Finds the moves that may have taken a place's value at a point, for the error at a use there. It walks back from
/// the point, so the dataflow state carries no moves.
struct ReachingMoves {
    /// The effects of each block, its statements' then its terminator's, indexed by `BlockID`.
    private let effects: [[Effect]]
    /// The reached blocks that lead to each block, indexed by `BlockID`.
    private let predecessors: [[BlockID]]
    /// The moves before which the moved place holds a value on some path; only these take one.
    private let takingMoves: Set<EffectPoint>

    /// The moves in `body`, whose blocks `isReached` says a path from the entry reaches.
    init(_ body: IRBody, isReached: [Bool], takingMoves: Set<EffectPoint>) {
        effects = body.blocks.map { Array($0.effects.joined()) }
        var predecessors: [[BlockID]] = Array(repeating: [], count: body.blocks.count)
        for (index, block) in body.blocks.enumerated() where isReached[index] {
            for successor in block.terminator.successors {
                predecessors[successor.index].append(BlockID(index: index))
            }
        }
        self.predecessors = predecessors
        self.takingMoves = takingMoves
    }

    /// The ranges of the moves of `place` that take its value on some path to `point`, with no assignment after them.
    func moves(of place: Place, reaching point: EffectPoint) -> Set<SourceRange> {
        var found: Set<SourceRange> = []
        var isQueued = Array(repeating: false, count: effects.count)

        // Each block waiting is walked back from the effect before `end`, until an effect gives the place its value.
        var pending = [(block: point.block, end: point.ordinal)]
        while let (block, end) = pending.popLast() {
            guard walkBack(through: block, before: end, for: place, into: &found) else { continue }
            for predecessor in predecessors[block.index] where !isQueued[predecessor.index] {
                isQueued[predecessor.index] = true
                pending.append((predecessor, effects[predecessor.index].count))
            }
        }
        return found
    }

    /// Adds the moves of `place` among the effects of `block` before `end` to `found`, last first, and returns whether
    /// the walk reaches the block's start: whether no effect on the way gives the place a value again.
    private func walkBack(
        through block: BlockID, before end: Int, for place: Place, into found: inout Set<SourceRange>,
    ) -> Bool {
        for ordinal in (0..<end).reversed() {
            let effect = effects[block.index][ordinal]
            if case .move(let moved, let range) = effect, moved == place {
                if takingMoves.contains(EffectPoint(block: block, ordinal: ordinal)) { found.insert(range) }
            } else if effect.replacesValue(of: place) {
                return false
            }
        }
        return true
    }
}

private extension Effect {
    /// Whether the effect leaves `place` holding a value again, or ends its local's life, so that no move before it
    /// takes a value that the place lacks after it.
    func replacesValue(of place: Place) -> Bool {
        switch self {
        case .store(let destination): destination.place.mustContain(place)
        // A move of a place around it stands for the place, which then holds whatever the moved place holds.
        case .move(let moved, _): moved != place && moved.mustContain(place)
        case .declare(let local), .retire(let local): local == place.root
        case .read, .begin, .use, .end, .depend, .exit: false
        }
    }
}
