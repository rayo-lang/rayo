import RayoCheckedProgram

extension RayoType {
    /// How many levels of array types the type nests, each the element of the one around it: none for a type that
    /// isn't an array.
    var arrayLevels: Int {
        guard case .array(_, let element) = self else { return 0 }
        return 1 + element.arrayLevels
    }
}
