/// What a call passes for one of its function's parameters, as the parameter's convention takes it.
public enum CheckedArgument: Sendable {
    /// A value the function reads, which the caller keeps.
    case borrowed(CheckedExpr)
    /// A value the function takes, which the caller gives up.
    case owned(CheckedExpr)
    /// A place the function may change, which the caller reads again after the call.
    case mutable(CheckedPlace)

    /// The argument that passes `value` to a parameter of `convention`.
    package init(passing value: CheckedExpr, as convention: ParameterConvention) {
        self = switch convention {
        case .borrowed: .borrowed(value)
        case .owned: .owned(value)
        case .mutable: .mutable(Self.place(passedAs: value))
        }
    }

    /// The place that `value`, passed to a mutable parameter, names. Checking must report a call that passes a mutable
    /// parameter anything but a place, `copy x` among them, before it makes the call's arguments.
    private static func place(passedAs value: CheckedExpr) -> CheckedPlace {
        // Checking rejects a `mutable &` parameter that the source writes, and declares it as one that borrows, and no
        // built-in or initializer has one, so no checked call reaches a mutable parameter.
        guard case .place(let place) = value.kind else {
            preconditionFailure("only a place is passed to a mutable parameter")
        }
        return place
    }
}
