/// How a function body uses a name, which decides the matches its lookup skips.
enum NameUse {
    case call
    /// Any use but a call.
    case ordinary
}
