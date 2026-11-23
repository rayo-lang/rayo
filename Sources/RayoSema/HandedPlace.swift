import RayoCheckedProgram

/// A place rooted in a local that a value hands its position to, and that local. The local is the one the place's
/// root names, kept apart so that the code that uses it needn't find it in a root that could be a temporary.
struct HandedPlace {
    var local: LocalID
    var place: CheckedPlace
}
