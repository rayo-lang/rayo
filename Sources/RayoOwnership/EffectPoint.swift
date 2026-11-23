import RayoIR

/// The point just before an effect of a block: the effect at `ordinal` of the block's effects, its statements' then its
/// terminator's, counted in order across them all.
struct EffectPoint: Hashable {
    var block: BlockID
    var ordinal: Int
}
