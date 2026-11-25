/// The effects of every statement and terminator of a function's body, built once into one array that the dataflow
/// analyses of the body share. Each block's effects are a view into that array, so reading them copies none.
package struct BodyEffects {
    /// The effects of each block's statements and then its terminator, block after block.
    private let effects: [Effect]
    /// Where the effects of each statement and terminator begin in `effects`, in the same order, and then where the
    /// last of them ends.
    private let crossingStarts: [Int]
    /// Where each block's statements and terminator begin in `crossingStarts`, indexed by `BlockID`, and then where
    /// the last block's end.
    private let blockStarts: [Int]

    /// The effects of `body`.
    package init(_ body: IRBody) {
        var effects: [Effect] = []
        var crossingStarts: [Int] = []
        var blockStarts: [Int] = []
        for block in body.blocks {
            blockStarts.append(crossingStarts.count)
            for statement in block.statements {
                crossingStarts.append(effects.count)
                statement.forEachEffect { effects.append($0) }
            }
            crossingStarts.append(effects.count)
            block.terminator.forEachEffect { effects.append($0) }
        }

        // The end of the last crossing closes the last block, as the start of the next one closes each other block.
        blockStarts.append(crossingStarts.count)
        crossingStarts.append(effects.count)

        self.effects = effects
        self.crossingStarts = crossingStarts
        self.blockStarts = blockStarts
    }

    /// How many blocks the body has.
    package var blockCount: Int { blockStarts.count - 1 }

    /// The effects of `block`'s statements and terminator.
    package subscript(block: BlockID) -> BlockEffects {
        let crossings = blockStarts[block.index]...blockStarts[block.index + 1]
        return BlockEffects(effects, startingAt: crossingStarts[crossings])
    }
}
