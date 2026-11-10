/// How a parameter takes its argument, when it doesn't borrow it.
public enum ParamConvention: String, Sendable {
    case mutable, owned
}
