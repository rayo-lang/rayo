import RayoIR

/// The backward data flow of which locals of a function, and which fields inside them, hold a value that some code
/// reads later, through the function's control-flow graph.
struct LivenessAnalysis {
    /// The state at the exit of each block, indexed by `BlockID`; nil for a block that no path from the function's
    /// entry reaches.
    private(set) var exitStates: [LivenessState?]

    init(_ function: IRFunction) {
        let exitStates = Self.exitStates(of: function)
        let reached = Self.reachedBlocks(of: function)
        self.exitStates = exitStates.indices.map { reached.contains($0) ? exitStates[$0] : nil }
    }

    /// Solves the state at the exit of each block of `function`, indexed by `BlockID`.
    private static func exitStates(of function: IRFunction) -> [LivenessState] {
        // No block starts out reading any local, and the passes below add each read they find.
        var entryStates = Array(repeating: LivenessState(), count: function.blocks.count)
        var exitStates = entryStates

        // Each pass gives every block the reads its successors make, until a pass adds none. A block's successors
        // mostly come after it, so a pass from the last block to the first settles most of them.
        var previousEntryStates: [LivenessState]
        repeat {
            previousEntryStates = entryStates
            for (index, block) in function.blocks.enumerated().reversed() {
                exitStates[index] = block.terminator.successors.reduce(LivenessState()) {
                    $0.union(entryStates[$1.index])
                }
                entryStates[index] = exitStates[index]
                entryStates[index].apply(backwardsThrough: block)
            }
        } while entryStates != previousEntryStates
        return exitStates
    }

    /// Walks the blocks of `function` that some path from its entry reaches, and returns their indices.
    private static func reachedBlocks(of function: IRFunction) -> Set<Int> {
        var reached: Set<Int> = [0]
        var pending = [BlockID(index: 0)]
        while let block = pending.popLast() {
            // Each successor not reached before is reached through `block`, and so are its own successors.
            for successor in function.blocks[block.index].terminator.successors
            where reached.insert(successor.index).inserted {
                pending.append(successor)
            }
        }
        return reached
    }
}
