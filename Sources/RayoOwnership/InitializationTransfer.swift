import RayoIR

/// What the initialization state knows of a body: the places it follows, and what each block does to their facts,
/// worked out once.
struct InitializationTransfer {
    let places: TrackedPlaces
    /// Indexed by `BlockID`.
    let blocks: [GenKill]

    init(_ body: IRBody, tracking places: TrackedPlaces) {
        self.places = places
        blocks = body.blocks.map { block in
            var change = GenKill(count: InitializationState.bitCount(tracking: places))
            for effect in block.effects.joined() {
                for bit in InitializationState.bits(changedBy: effect, among: places) {
                    change.set(bit.index, to: bit.value)
                }
            }
            return change
        }
    }
}
