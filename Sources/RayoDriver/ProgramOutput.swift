extension Driver {
    /// Where `rayoc run` sends what the program writes.
    public enum ProgramOutput: Sendable {
        /// Into the result, once the program ends.
        case captured
        /// To `rayoc`'s own standard output and error, as the program writes it.
        case inherited
    }
}
