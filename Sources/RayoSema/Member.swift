/// What a name finds among the members of a type: a property of a value of the type, or the type's initializers.
enum Member {
    /// The name of a type's initializers among its members, which a call of the type's name reaches too.
    static let initializerName = "init"

    /// The type's initializers, which a call of the type's name or of its `init` reaches.
    enum Initializers {
        /// A struct's primary initializer, which takes each field's value labeled by its name, in the struct's order.
        case primary(StructID)
        /// Initializers among which a call chooses by its arguments' labels and types.
        case overloads([Signature])
    }

    /// A struct's field, a place property: it names a part of the place that holds the struct. It is the field at
    /// `index` in the struct's declaration.
    case field(index: Int, DeclaredField)
    /// An array's count, a value property: a UInt that the array's type fixes, which names no place.
    case count(Int)
    /// The type's initializers, under the member name `init`.
    case initializers(Initializers)
}
