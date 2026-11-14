import RayoDiagnostics
import RayoSource

/// Settles an implicit member to the member it names of the type its position expects. An array's one member is
/// `.init(all: value)`, which fills it with copies of the value, and no other type has implicit members.
struct ImplicitMemberChecker {
    let expressions: ExpressionChecker

    private var errors: ErrorList { expressions.file.errors }

    /// Settles `member` to the member of `type` it names, reporting it where `type` is nil or has no such member.
    func settled(_ member: ImplicitMember, toward type: RayoType?) -> CheckedExpr? {
        switch type {
        // An array's member makes the array.
        case .array(let count, let element)?:
            arrayMember(member, makingArrayOf: count, element)

        // A position that gives no type gives no type to find the member in.
        case nil:
            failed(member, reporting: .implicitMemberWithoutType(name: member.name), at: member.nameRange)

        // Any other type has no implicit members.
        case let type?:
            failed(member, reporting: .unsupportedImplicitMember(type: expressions.typeName(of: type)),
                   at: member.nameRange)
        }
    }

    /// Checks `member` as a member of the array of `count` values of `element`. The array's one member,
    /// `.init(all: value)`, makes the array with each element a copy of the value.
    private func arrayMember(_ member: ImplicitMember, makingArrayOf count: Int, _ element: RayoType) -> CheckedExpr? {
        let type = RayoType.array(count: count, element: element)

        // An array has no member but its initializer, which makes a value only when it is called.
        guard member.name == "init" else {
            let typeName = expressions.typeName(of: type)
            return failed(member, reporting: .noSuchMember(type: typeName, name: member.name), at: member.nameRange)
        }
        guard let arguments = member.arguments else { return failed(member, reporting: .uncalledInitializer) }

        // The initializer takes one argument.
        guard arguments.count == 1 else {
            let code = ErrorCode.argumentCount(name: ".init", takes: 1, passes: arguments.count)
            return failed(member, reporting: code)
        }
        let argument = arguments[0]
        // `.init(each:)`, which calls a function for each element, isn't supported.
        guard argument.label != "each" else { return failed(member, reporting: .unsupportedEachInitializer) }

        // The argument's label must be `all:`, and its value is an element's, which is checked whatever its label.
        let isLabeledRight = argument.label == "all"
        if !isLabeledRight {
            let found = ArgumentLabel(argument.label)
            errors.report(.argumentLabel(expected: ArgumentLabel("all"), found: found), at: argument.range)
        }
        let value = expressions.settled(argument.value, expecting: Expectation(element))
        guard isLabeledRight, let value else { return nil }
        return CheckedExpr(kind: .filledArray(value), type: type, range: member.range)
    }

    /// Reports `code` at `range`, or at the whole member where there is none, settles `member`'s arguments for their
    /// own errors, and returns nil.
    private func failed(
        _ member: ImplicitMember, reporting code: ErrorCode, at range: SourceRange? = nil,
    ) -> CheckedExpr? {
        errors.report(code, at: range ?? member.range)
        expressions.reportSettlingErrors(of: member.argumentValues)
        return nil
    }
}
