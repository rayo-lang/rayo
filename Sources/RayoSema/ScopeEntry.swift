/// What a name that a block or a function's parameter list declares stands for.
enum ScopeEntry {
    case local(LocalID)
    /// A name whose declaration failed, which was reported there, so its uses report nothing more.
    case failed
}
