import RayoIR

/// The backward data flow of which locals of a function, and which fields inside them, hold a value that some code
/// reads later, through the function's control-flow graph.
struct LivenessAnalysis {
    /// The state at the exit of each block, indexed by `BlockID`; nil for a block that no path from the function's
    /// entry reaches.
    private(set) var exitStates: [LivenessState?]

    /// The analysis of the function whose places `places` gives the types of.
    init(of places: PlaceTypes) {
        let exitStates = Self.exitStates(in: places)
        let reached = Self.reachedBlocks(of: places.body)
        self.exitStates = exitStates.indices.map { reached.contains($0) ? exitStates[$0] : nil }
    }

    /// Solves the state at the exit of each block of the function whose places `places` gives the types of, indexed
    /// by `BlockID`.
    private static func exitStates(in places: PlaceTypes) -> [LivenessState] {
        let body = places.body

        // No block starts out reading any local, and the passes below add each read they find.
        var entryStates = Array(repeating: LivenessState(), count: body.blocks.count)
        var exitStates = entryStates

        // Each pass gives every block the reads its successors make, until a pass adds none. A block's successors
        // mostly come after it, so a pass from the last block to the first settles most of them.
        var previousEntryStates: [LivenessState]
        repeat {
            previousEntryStates = entryStates
            for (index, block) in body.blocks.enumerated().reversed() {
                exitStates[index] = block.terminator.successors.reduce(LivenessState()) {
                    $0.union(entryStates[$1.index])
                }
                entryStates[index] = exitStates[index]
                entryStates[index].apply(backwardsThrough: block, in: places)
            }
        } while entryStates != previousEntryStates
        return exitStates
    }

    /// Walks the blocks of `body` that some path from its entry reaches, and returns their indices.
    private static func reachedBlocks(of body: IRBody) -> Set<Int> {
        var reached: Set<Int> = [0]
        var pending = [BlockID(index: 0)]
        while let block = pending.popLast() {
            // Each successor not reached before is reached through `block`, and so are its own successors.
            for successor in body.blocks[block.index].terminator.successors
            where reached.insert(successor.index).inserted {
                pending.append(successor)
            }
        }
        return reached
    }
}
