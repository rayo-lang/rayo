import RayoSema

/// One of the integers and Bools a value splits into: where it lies inside the value, and its type.
struct Scalar: Equatable {
    /// A step from a value to a part of it that holds the scalar. A scalar may lie in an array's element at an index
    /// the type fixes, which no place of the IR steps into, so its steps are its own.
    enum Step: Equatable {
        /// Into a struct's field, by its place in its struct's declaration.
        case field(Int)
        /// Into an array's element, by its index.
        case element(Int)
    }

    /// The steps from the value to the scalar, outermost first; none where the scalar is the whole value.
    var steps: [Step]
    var type: RayoType
}
