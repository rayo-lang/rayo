import RayoCheckedProgram
import RayoSource

/// An implicit member, such as `.init(repeating: 0)`: its name, and the arguments of the call where it is called, each
/// checked on its own.
struct ImplicitMember {
    /// An argument of the call: its label, its value checked on its own, and where the source writes both.
    struct Argument: CallArgument {
        var label: String?
        var value: CheckedValue
        var range: SourceRange

        func checked(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr? {
            expressions.settled(value, expecting: expected)
        }

        /// The value, which was checked on its own already, as the member's arguments are.
        func uncheckedValue(by _: ExpressionChecker) -> CheckedValue? {
            value
        }

        func reportErrors(by expressions: ExpressionChecker) {
            expressions.reportSettlingErrors(of: [value])
        }
    }

    var name: String
    /// Where the source writes the `.` and the name.
    var nameRange: SourceRange
    /// The call's arguments, or nil where the member isn't called.
    var arguments: [Argument]?
    /// Where the source writes the member, with the call's arguments where it is called.
    var range: SourceRange

    /// The values of the call's arguments; none where the member isn't called.
    var argumentValues: [CheckedValue] {
        arguments?.map(\.value) ?? []
    }

    /// Whether a position that expects `type` takes an implicit member, which only an array's does: of the
    /// language's implicit members, rayoc builds only an array's `.init(repeating:)`, so another type's are reported
    /// as unsupported rather than looked up.
    static func isSupported(in type: RayoType) -> Bool {
        if case .array = type { true } else { false }
    }
}

extension ImplicitMember: TypeWaitingValue {
    /// None: the member names a member of no type until its position gives one.
    var type: RayoType? { nil }

    /// None, for the same reason.
    var defaultType: RayoType? { nil }

    /// Whether the member makes a value of `type`, among whose members `declarations` finds it: a call of one of the
    /// type's initializers whose labels and parameter types the call's arguments fit.
    func fits(_ type: RayoType, in declarations: Declarations) -> Bool {
        guard Self.isSupported(in: type), let arguments,
              case .initializers(.overloads(let candidates))? = declarations.member(named: name, of: type)
        else { return false }
        let labels = arguments.map(\.label)
        return candidates.contains {
            $0.takesLabels(labels) && $0.takes(argumentValues, in: declarations, where: { _ in true })
        }
    }

    func settled(toward type: RayoType?, by expressions: ExpressionChecker) -> CheckedExpr? {
        ImplicitMemberChecker(expressions: expressions).settled(self, toward: type)
    }

    /// Reports the arguments' errors, and not the member's own, whose type the failed expression would have given.
    func reportErrors(by expressions: ExpressionChecker) {
        expressions.reportSettlingErrors(of: argumentValues)
    }
}
