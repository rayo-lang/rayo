import RayoDiagnostics
import RayoSource

/// Settles an implicit member to the member it names of the type its position expects, as the type's members give
/// it. Only an array has implicit members, and the one it has is `.init(repeating: value)`, a call of its initializer.
struct ImplicitMemberChecker {
    let expressions: ExpressionChecker

    private var errors: ErrorList { expressions.file.errors }

    /// Settles `member` to the member of `type` it names, reporting it where `type` is nil or has no such member.
    func settled(_ member: ImplicitMember, toward type: RayoType?) -> CheckedExpr? {
        // A position that gives no type gives no type to find the member in.
        guard let type else {
            return failed(member, reporting: .implicitMemberWithoutType(name: member.name), at: member.nameRange)
        }
        // A type other than an array has no implicit members.
        guard ImplicitMember.isSupported(in: type) else {
            let code = ErrorCode.unsupportedImplicitMember(type: expressions.typeName(of: type))
            return failed(member, reporting: code, at: member.nameRange)
        }

        switch expressions.file.declarations.member(named: member.name, of: type) {
        // The type's initializers make a value of it.
        case .initializers(let initializers)?:
            return initializerCall(member, of: initializers)

        // A property belongs to a value of the type, so it is no implicit member, nor is a name the type lacks.
        case .field?, .count?, nil:
            let code = ErrorCode.noSuchMember(type: expressions.typeName(of: type), name: member.name)
            return failed(member, reporting: code, at: member.nameRange)
        }
    }

    /// Checks `member`, which names `initializers`, as a call of one of them.
    private func initializerCall(_ member: ImplicitMember, of initializers: Member.Initializers) -> CheckedExpr? {
        // An initializer makes a value only when it is called.
        guard let arguments = member.arguments else { return failed(member, reporting: .uncalledInitializer) }
        // An array's `.init(each:)`, which calls a function for each element, is an initializer of the spec that
        // rayoc doesn't build, so it is reported as unsupported rather than as a call that fits no initializer.
        if arguments.count == 1, arguments[0].label == "each" {
            return failed(member, reporting: .unsupportedEachInitializer)
        }
        return CallChecker(expressions: expressions)
            .call(initializers, named: ".\(member.name)", passing: arguments, in: member.range)
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
