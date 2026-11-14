import RayoIR
import RayoSema

/// One of the integers and Bools a value splits into: where it lies inside the value, and its type.
struct Scalar: Equatable {
    /// The steps from the value to the scalar, outermost first; none where the scalar is the whole value.
    var steps: [PlaceStep]
    var type: RayoType
}
