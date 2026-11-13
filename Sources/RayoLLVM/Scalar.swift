import RayoSema

/// One of the Ints and Bools a value splits into: where it lies inside the value, and its type.
struct Scalar: Equatable {
    /// The fields that lead from the value to the scalar, outermost first, each by its place in its struct's
    /// declaration; none where the scalar is the whole value.
    var fields: [Int]
    var type: RayoType
}
