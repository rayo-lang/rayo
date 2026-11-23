import RayoCheckedProgram
import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks a call: which function or initializer of a type its callee reaches, and its arguments against that
/// function's parameters.
struct CallChecker {
    /// A function that a call reaches, and the call's arguments, checked against its parameters.
    private typealias Match = (signature: Signature, arguments: [CheckedExpr])

    /// An argument's label and the type of its value, which choose among overloads.
    private typealias TypedArgument = (label: String?, type: RayoType)

    let expressions: ExpressionChecker

    private var errors: ErrorList { expressions.file.errors }
    private var declarations: Declarations { expressions.file.declarations }

    /// Checks `callee(arguments)`. Every argument is checked, whether or not the call reaches a function or a type.
    /// A call of an implicit member waits for its position to give the type whose member it calls.
    func call(_ callee: Expr, _ arguments: [Argument], in range: SourceRange) -> CheckedValue? {
        switch callee.kind {
        // A name calls the functions it names, or the initializers of the type it names.
        case .name(let name):
            call(named: name, at: callee.range, arguments, in: range).map { .typed($0) }

        // A member call calls a method of its base's type, and checking rejects every declaration in a struct's body,
        // so no type has one.
        case .member(let base, let name, let nameRange):
            memberCall(named: name, at: nameRange, of: base, calledAt: callee.range, passing: arguments)

        // An implicit member names a member of the type the call's position expects.
        case .implicitMember(let name):
            implicitMemberCall(named: name, at: callee.range, passing: arguments, in: range)

        // The parser calls nothing else.
        default:
            preconditionFailure("only a name, a member or an implicit member is called")
        }
    }

    /// Checks `name(arguments)`, where the source writes `name` at `nameRange`.
    private func call(named name: String, at nameRange: SourceRange, _ arguments: [Argument],
                      in range: SourceRange) -> CheckedExpr? {
        switch expressions.names.lookUp(name, for: .call) {
        // A type's name calls one of the type's initializers.
        case .type(let type):
            typeCall(of: type, named: name, at: nameRange, passing: arguments, in: range)

        // The name's functions are the call's candidates.
        case .functions(let functions):
            call(among: functions, named: name, passing: arguments, in: range)

        // A local or a field of `self` can't be called.
        case .inScope(.local), .instanceField:
            reachingNothing(reporting: .notAFunction(name: name), at: nameRange, passing: arguments)

        // A local, a function or a struct whose declaration failed was reported there.
        case .inScope(.failed), .failed:
            reachingNothing(reporting: nil, at: nameRange, passing: arguments)

        // Nothing has the name.
        case nil:
            reachingNothing(reporting: .notDeclared(name: name), at: nameRange, passing: arguments)
        }
    }

    /// Checks `name(arguments)`, where `name`, which the source writes at `nameRange`, names `type`, as a call of one
    /// of the type's initializers.
    private func typeCall(of type: RayoType, named name: String, at nameRange: SourceRange,
                          passing arguments: [Argument], in range: SourceRange) -> CheckedExpr? {
        // A type without initializers makes no value by a call.
        let initializerName = Member.initializerName
        guard case .initializers(let initializers)? = declarations.member(named: initializerName, of: type) else {
            let code = ErrorCode.noSuchMember(type: expressions.typeName(of: type), name: initializerName)
            return reachingNothing(reporting: code, at: nameRange, passing: arguments)
        }

        // A prelude type's initializer called with one unlabeled literal makes the literal a value of the type, so
        // `UInt(-1)` is an error, as `let u: UInt = -1` is, where a conversion would only fail as the program runs.
        if case .overloads(let candidates) = initializers, candidates.allSatisfy(\.isBuiltin),
           let literal = soleLiteral(of: arguments) {
            return self.literal(literal, as: type, in: range)
        }
        return call(initializers, named: name, passing: arguments, in: range)
    }

    /// Checks a call of one of `initializers`, which the source names as `name`, that passes `arguments`.
    func call(_ initializers: Member.Initializers, named name: String, passing arguments: [some CallArgument],
              in range: SourceRange) -> CheckedExpr? {
        switch initializers {
        // A struct's primary initializer is made from its fields' values.
        case .primary(let id):
            InitializerChecker(expressions: expressions).checkCall(making: id, passing: arguments, in: range)

        // Any other initializers are the call's candidates.
        case .overloads(let candidates):
            call(among: candidates, named: name, passing: arguments, in: range)
        }
    }

    /// Checks `base.name(arguments)`, where the source writes `name` at `nameRange` and `base.name` at `calleeRange`.
    /// No type has a method, so the call reaches nothing: it reports a property of the base's type as no function,
    /// and any other member as a call that isn't supported, with the errors of `base` and of each argument.
    private func memberCall(named name: String, at nameRange: SourceRange, of base: Expr,
                            calledAt calleeRange: SourceRange, passing arguments: [Argument]) -> CheckedValue? {
        // A base that failed was reported, and gives no type to find the member in.
        let member = expressions.check(base).flatMap { declarations.member(named: name, of: $0.type) }

        let (code, range): (ErrorCode, SourceRange) = switch member {
        // A property gives a value, which can't be called.
        case .field?, .count?: (.notAFunction(name: name), nameRange)
        // A type's initializers aren't called through a value of the type, and any other member would be a method.
        case .initializers?, nil: (.unsupportedMemberCall, calleeRange)
        }
        return reachingNothing(reporting: code, at: range, passing: arguments).map { .typed($0) }
    }

    /// Checks `.name(arguments)`, where the source writes `.name` at `nameRange`, with each argument checked on its
    /// own, since the member that takes them is known only once the call's position gives its type.
    private func implicitMemberCall(named name: String, at nameRange: SourceRange, passing arguments: [Argument],
                                    in range: SourceRange) -> CheckedValue? {
        // Every argument is checked, so each one's errors are reported, before any failure fails the call.
        let values = arguments.map { expressions.value(of: $0.value) }
        let checked = values.compactMap { $0 }
        // An argument that failed was reported, and the others' literals are settled for their own errors.
        guard checked.count == values.count else {
            expressions.reportSettlingErrors(of: values)
            return nil
        }

        let memberArguments = zip(arguments, checked).map {
            ImplicitMember.Argument(label: $0.label, value: $1, range: $0.range)
        }
        let member = ImplicitMember(name: name, nameRange: nameRange, arguments: memberArguments, range: range)
        return .waiting(member)
    }

    /// Checks a call that reaches no function or struct: reports `error`, where there is one, at `range`, and the
    /// errors of each of `arguments`, and returns nil.
    private func reachingNothing(
        reporting error: ErrorCode?, at range: SourceRange, passing arguments: [some CallArgument],
    ) -> CheckedExpr? {
        // A name whose declaration failed comes with no error, since its error was reported there.
        if let error { errors.report(error, at: range) }

        // The arguments' values are still checked, with no parameter to take them.
        checkValues(of: arguments)
        return nil
    }

    /// Checks a call of one of `candidates`, which the source names as `name`, that passes `arguments`.
    private func call(among candidates: [Signature], named name: String, passing arguments: [some CallArgument],
                      in range: SourceRange) -> CheckedExpr? {
        // A call whose arguments fit no candidate was reported.
        guard let match = match(arguments, among: candidates, named: name, in: range) else { return nil }

        // A result type that isn't known was reported in the function that gives it, or here as a cycle.
        guard let result = expressions.file.result(of: match.signature, calledAt: range) else { return nil }
        let call = match.signature.target.call(passing: match.arguments, to: match.signature.parameters)
        return CheckedExpr(kind: call, type: result, range: range)
    }

    /// The value of `arguments` where they are one unlabeled integer literal, or nil where they are anything else.
    private func soleLiteral(of arguments: [Argument]) -> Expr? {
        guard arguments.count == 1, arguments[0].label == nil else { return nil }
        return switch arguments[0].value.kind {
        case .intLiteral, .negativeIntLiteral: arguments[0].value
        default: nil
        }
    }

    /// Checks `literal` as a value of `type`, which the call at `range` makes it.
    private func literal(_ literal: Expr, as type: RayoType, in range: SourceRange) -> CheckedExpr? {
        // A literal that the type can't hold was reported.
        guard let value = expressions.check(literal, expecting: Expectation(type)) else { return nil }
        return CheckedExpr(kind: value.kind, type: type, range: range)
    }

    /// The one of `candidates`, which the source names as `name`, that `arguments` fit, with the arguments checked
    /// against its parameters.
    private func match(_ arguments: [some CallArgument], among candidates: [Signature], named name: String,
                       in range: SourceRange) -> Match? {
        switch candidates.count {
        // Without a candidate, the arguments are checked for their own errors.
        case 0:
            checkValues(of: arguments)
            return nil

        // One candidate is the call's, if the arguments fit its parameters.
        case 1:
            return check(arguments, against: candidates[0], named: name, in: range).map { (candidates[0], $0) }

        // Among overloads, the arguments' labels and types pick one.
        default:
            return pick(among: candidates, named: name, for: arguments, in: range)
        }
    }

    /// Checks `arguments` against `signature`'s parameters, in order, reporting each mismatch. An error names the
    /// signature as `name`, the way the call writes it.
    private func check(_ arguments: [some CallArgument], against signature: Signature, named name: String,
                       in range: SourceRange) -> [CheckedExpr]? {
        // A call that passes too few or too many arguments fails, though each argument's own errors are reported.
        let parameters = signature.parameters
        guard arguments.count == parameters.count else {
            let takes = ArgumentCount(parameters.count)
            errors.report(.argumentCount(name: name, takes: takes, passes: arguments.count), at: range)
            checkValues(of: arguments)
            return nil
        }

        // Check every argument, so each one's errors are reported, before any failure fails the call.
        let checked = zip(arguments, parameters).map { check($0, against: $1, of: name) }
        let values = checked.compactMap { $0 }
        return values.count == arguments.count ? values : nil
    }

    /// Checks `argument`'s label and value against `parameter`, of the function the call names as `name`.
    private func check(_ argument: some CallArgument, against parameter: Parameter, of name: String) -> CheckedExpr? {
        // A label other than the parameter's is reported, and fails the argument once its value is checked.
        let isLabeledRight = argument.label == parameter.label
        if !isLabeledRight {
            let expected = ArgumentLabel(parameter.label)
            errors.report(.argumentLabel(expected: expected, found: ArgumentLabel(argument.label)), at: argument.range)
        }

        // A parameter whose type isn't known was reported where it is declared; the value is checked on its own.
        guard let expected = parameter.expectation(calledAs: name) else {
            argument.reportErrors(by: expressions)
            return nil
        }
        let value = argument.checked(expecting: expected, by: expressions)
        return isLabeledRight ? value : nil
    }

    /// The one of `candidates`, which the source names as `name`, whose labels and parameter types `arguments` fit,
    /// with the arguments settled to its parameters' types.
    private func pick(among candidates: [Signature], named name: String, for arguments: [some CallArgument],
                      in range: SourceRange) -> Match? {
        // Check each argument on its own, since the candidate that takes it isn't known yet, so an untyped one stays
        // untyped.
        let checked = arguments.map { $0.uncheckedValue(by: expressions) }
        let values = checked.compactMap { $0 }
        // An argument that failed was reported, and without it no candidate can be picked. The other arguments'
        // literals are settled to their default types, for their own errors.
        guard values.count == arguments.count else {
            expressions.reportSettlingErrors(of: checked)
            return nil
        }

        // Pick the one candidate that the arguments' labels and values fit.
        let labels = arguments.map(\.label)
        let (remaining, takeArgumentsAsWritten) = remaining(of: candidates, passing: labels, values)
        // No candidate fits, which is reported with the arguments' types.
        guard !remaining.isEmpty else {
            reportNoMatch(of: name, labels: labels, values: values, in: range)
            return nil
        }
        // Several fit by type, and none takes the arguments as they are written. A candidate that failed was
        // reported where it is declared, and is left to `chosen` to pass over.
        if !takeArgumentsAsWritten, remaining.count > 1, !remaining.contains(where: \.hasFailed) {
            reportMiswritten(values, among: remaining, named: name, labels: labels, in: range)
            return nil
        }
        // Where several fit and none of them is the call's, the arguments' literals are settled for their own errors.
        guard let chosen = chosen(among: remaining, named: name, for: values, in: range) else {
            expressions.reportSettlingErrors(of: values)
            return nil
        }

        // A parameter whose type isn't known was reported where it is declared, and takes any argument, so the
        // arguments report only their own errors, as they do where the call has one candidate.
        let expectations = chosen.parameters.compactMap { $0.expectation(calledAs: name) }
        guard expectations.count == values.count else {
            expressions.reportSettlingErrors(of: values)
            return nil
        }

        // The chosen candidate's parameters settle the untyped arguments, and take each argument as it fits them.
        let settled = zip(values, expectations).compactMap { expressions.settled($0, expecting: $1) }
        // An argument that failed to settle to its parameter's type was reported.
        guard settled.count == values.count else { return nil }
        return (chosen, settled)
    }

    /// The one of `remaining`, the candidates that `values` fit, that the call reaches. Reports a call that several
    /// fit, naming them as `name`, unless one of them failed, which was reported where it is declared.
    private func chosen(among remaining: [Signature], named name: String, for values: [CheckedValue],
                        in range: SourceRange) -> Signature? {
        // A candidate that alone remains is the call's.
        if remaining.count == 1 { return remaining[0] }

        // A parameter whose type failed to resolve fits any argument, so several remain; that failure was reported
        // where the function is declared.
        if remaining.contains(where: \.hasFailed) { return nil }

        // The prelude's built-ins of one name stand in for one generic function, which binds an untyped argument to
        // its default type, so `print(1)` prints an Int.
        // An array literal that no element gives a type has no default, and binds no built-in.
        let defaultTypes = values.compactMap(\.typeOrDefault)
        if defaultTypes.count == values.count, remaining.allSatisfy(\.isBuiltin),
           let chosen = remaining.first(where: { $0.takes(defaultTypes) }) {
            return chosen
        }

        // Otherwise an untyped argument fits more than one of the functions the code declares.
        errors.report(.ambiguousCall(name: name), at: range)
        return nil
    }

    /// The candidates that a call passing arguments with `labels` and `values`, in order, can reach, and whether they
    /// take each argument as it is written.
    private func remaining(of candidates: [Signature], passing labels: [String?],
                           _ values: [CheckedValue]) -> (candidates: [Signature], takeArgumentsAsWritten: Bool) {
        // Keep the candidates whose labels the arguments match, in order.
        let labeled = candidates.filter { $0.takesLabels(labels) }
        // Keep those that the typed arguments fit, so that an untyped argument is offered only the parameters of the
        // candidates the typed ones leave.
        let typedFit = labeled.filter { $0.takes(values, in: declarations, where: { $0.type != nil }) }
        // Each untyped argument takes each remaining candidate's parameter type, and a candidate it doesn't fit drops
        // out.
        let typesFit = typedFit.filter { $0.takes(values, in: declarations, where: { $0.type == nil }) }
        // Where some candidates take each argument as it is written, with or without a `&`, the others drop out.
        // Where none does, those the types fit stay, so the one the call reaches reports how to write its arguments.
        let writtenFit = typesFit.filter { $0.takesWritten(values) }
        return writtenFit.isEmpty ? (typesFit, false) : (writtenFit, true)
    }

    /// Reports `values`, which several of `candidates`, the functions the call names as `name`, fit by type, though
    /// none takes each of them as it is written. Where every candidate takes each argument the same way, each
    /// argument reports what any of them would report of it; otherwise the call fits none of them as written.
    private func reportMiswritten(_ values: [CheckedValue], among candidates: [Signature], named name: String,
                                  labels: [String?], in range: SourceRange) {
        let conventions = candidates[0].parameters.map(\.convention)
        guard candidates.allSatisfy({ $0.parameters.map(\.convention) == conventions }) else {
            reportNoMatch(of: name, labels: labels, values: values, in: range)
            return
        }

        // The candidates differ only in types the arguments fit, so the first stands for them all. The call still
        // fails, so its body is tainted, whatever the arguments report.
        let expectations = candidates[0].parameters.compactMap { $0.expectation(calledAs: name) }
        for (value, expected) in zip(values, expectations) {
            _ = expressions.settled(value, expecting: expected)
        }
        errors.taints.taint()
    }

    /// Reports a call of `name` whose arguments, with `labels` and `values`, fit none of its functions, unless an
    /// untyped argument reports an error as it settles to its default type, which is reported in its place.
    private func reportNoMatch(of name: String, labels: [String?], values: [CheckedValue], in range: SourceRange) {
        // Each untyped argument takes its default type, which the error names it by.
        let reportedBefore = errors.list.count
        let settled = values.compactMap { expressions.settled($0, toward: nil) }

        // An argument that reports an error as it settles, such as a literal its default type can't hold, is the
        // error in place of the mismatch. The call still fails, so its body is tainted.
        guard settled.count == values.count, errors.list.count == reportedBefore else {
            errors.taints.taint()
            return
        }
        let typed = zip(labels, settled).map { (label: $0, type: $1.type) }
        errors.report(.noMatchingFunction(name: name, arguments: spelling(of: typed)), at: range)
    }

    /// Checks the values of `arguments` for their own errors, where no function's parameters take them.
    private func checkValues(of arguments: [some CallArgument]) {
        for argument in arguments {
            argument.reportErrors(by: expressions)
        }
    }

    /// The arguments as an error writes them, such as `Int, by: Bool`.
    private func spelling(of arguments: [TypedArgument]) -> String {
        let written = arguments.map { argument in
            let label = argument.label.map { "\($0): " } ?? ""
            return label + "\(expressions.typeName(of: argument.type))"
        }
        return written.joined(separator: ", ")
    }
}
