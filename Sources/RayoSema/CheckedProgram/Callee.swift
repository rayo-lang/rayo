/// What a call calls.
public enum Callee: Hashable, Sendable {
    case builtin(Builtin)
    case function(FunctionID)
}
