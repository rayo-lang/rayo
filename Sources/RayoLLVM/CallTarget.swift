import RayoSema

/// What a call of one of the program's functions reaches in the module.
enum CallTarget {
    /// A function the module declares, which the call calls.
    case function(DeclaredFunction)
    /// The primary initializer of the struct, which the module declares no function for: the call builds the struct
    /// in its destination from its arguments.
    case primaryInitializer(StructID)
}
