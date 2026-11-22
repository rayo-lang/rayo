import RayoCheckedProgram

/// A place rooted in a local that a value hands its position to, and that local.
struct HandedPlace {
    var local: LocalID
    var place: CheckedPlace
}
