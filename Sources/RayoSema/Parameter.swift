/// What a call needs to know about one parameter of the function it calls.
struct Parameter {
    /// The label an argument for it is written with, or nil when it is written with none.
    var label: String?
    /// The type, or nil when the declaration names no type or names Void, which was reported there.
    var type: RayoType?
    /// The type as the declaration writes it.
    var spelledType: String
}
