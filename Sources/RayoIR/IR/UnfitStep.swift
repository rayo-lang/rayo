import RayoSema

/// A step of a place that leads into a part that the value it steps from doesn't have, which no lowering of a checked
/// program writes.
public struct UnfitStep: Error {
    public var step: PlaceStep
    /// The type of the value the step steps from.
    public var holder: RayoType

    public init(_ step: PlaceStep, from holder: RayoType) {
        self.step = step
        self.holder = holder
    }
}
