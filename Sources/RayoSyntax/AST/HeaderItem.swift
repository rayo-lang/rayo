/// A parameter or a field in a declaration's header: one that parsed, or one that failed, whose syntax error was
/// reported.
public enum HeaderItem<Item: Sendable>: Sendable {
    case parsed(Item)
    case failed
}
