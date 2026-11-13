/// The rules a function and its callers agree on for how its arguments and its result are passed.
enum CallingConvention {
    /// Rayo's own, which nothing outside the program sees, and which may change from one compiler to the next.
    case rayo
}
