/// Where `rayo` sends what `rayoc` and the program write.
public enum ProcessOutput: Sendable {
    /// Into the result, once each ends.
    case captured
    /// To `rayo`'s own standard output and error, as each writes it.
    case inherited
}
