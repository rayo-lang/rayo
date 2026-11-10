/// How a function body uses a name, which decides whether its lookup prefers a function or a local.
enum NameUse {
    case call
    /// Any use but a call.
    case ordinary
}
