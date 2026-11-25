import RayoDiagnostics

/// What a position does with a value that no local holds, such as a call's result or a part of one, which a temporary
/// holds until its statement ends.
package enum ValueTaking: Equatable {
    /// Takes the value, reporting the error at it where there is one: a position that refers to a place, or borrows
    /// one, finds none, and checking goes on with the value all the same.
    case takes(reporting: ErrorCode?)
    /// Refuses the value, reporting the error at the temporary that holds it, which the position would change.
    case refused(ErrorCode)
}
