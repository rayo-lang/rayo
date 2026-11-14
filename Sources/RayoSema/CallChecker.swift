import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks a call: which function or struct's initializer its callee reaches, and a function's arguments against its
/// parameters.
struct CallChecker {
    /// A function that a call reaches, and the call's arguments, checked against its parameters.
    private typealias Match = (signature: Signature, arguments: [CheckedExpr])

    /// An argument's label and the type of its value, which choose among overloads.
    private typealias TypedArgument = (label: String?, type: RayoType)

    let expressions: ExpressionChecker

    private var errors: ErrorList { expressions.file.errors }

    /// Checks `callee(arguments)`. Every argument is checked, whether or not the call reaches a function or a struct.
    /// A call of an implicit member waits for its position to give the type whose member it calls.
    func call(_ callee: Expr, _ arguments: [Argument], in range: SourceRange) -> CheckedValue? {
        switch callee.kind {
        // A name calls the functions it names, or the initializers of the type it names.
        case .name(let name):
            call(named: name, at: callee.range, arguments, in: range).map { .typed($0) }

        // A member names a method, which no type has.
        case .member(let base, _, _):
            memberCall(of: base, at: callee.range, passing: arguments).map { .typed($0) }

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
        // A struct's name calls one of the struct's initializers.
        case .structure(let id):
            initializerCall(of: id, passing: arguments, in: range)

        // The name's functions are the call's candidates.
        case .functions(let functions):
            call(among: functions, passing: arguments, in: range)

        // A local can't be called.
        case .inScope(.local):
            reachingNothing(reporting: .notAFunction(name: name), at: nameRange, passing: arguments)

        // A local, a function or a struct whose declaration failed was reported there.
        case .inScope(.failed), .failed:
            reachingNothing(reporting: nil, at: nameRange, passing: arguments)

        // Nothing has the name.
        case nil:
            reachingNothing(reporting: .notDeclared(name: name), at: nameRange, passing: arguments)
        }
    }

    /// Checks a call of one of the initializers of the struct `id`, or, where the struct declares none, of its
    /// primary initializer.
    private func initializerCall(of id: StructID, passing arguments: [Argument],
                                 in range: SourceRange) -> CheckedExpr? {
        let initializers = expressions.file.declarations.initializers(of: id)
        // A struct without initializers is made by its primary initializer, from its fields' values.
        guard !initializers.isEmpty else {
            return InitializerChecker(expressions: expressions).checkCall(making: id, passing: arguments, in: range)
        }
        return call(among: initializers, passing: arguments, in: range)
    }

    /// Checks a call of the member of `base` that the source writes at `range`, which isn't supported: reports it, and
    /// the errors of `base` and of each of `arguments`, and returns nil.
    private func memberCall(of base: Expr, at range: SourceRange, passing arguments: [Argument]) -> CheckedExpr? {
        _ = expressions.check(base)
        return reachingNothing(reporting: .unsupportedMemberCall, at: range, passing: arguments)
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
        return .implicitMember(member)
    }

    /// Checks a call that reaches no function or struct: reports `error`, where there is one, at `range`, and the
    /// errors of each of `arguments`, and returns nil.
    private func reachingNothing(
        reporting error: ErrorCode?, at range: SourceRange, passing arguments: [Argument],
    ) -> CheckedExpr? {
        // A name whose declaration failed comes with no error, since its error was reported there.
        if let error { errors.report(error, at: range) }

        // The arguments' values are still checked, with no parameter to take them.
        checkValues(of: arguments)
        return nil
    }

    /// Checks a call of one of `candidates`, the functions of one name, that passes `arguments`.
    private func call(among candidates: [Signature], passing arguments: [Argument],
                      in range: SourceRange) -> CheckedExpr? {
        // A prelude type's initializer called with one unlabeled literal makes the literal a value of the type, so
        // `UInt(-1)` is an error, as `let u: UInt = -1` is, where a conversion would only fail as the program runs.
        if let type = preludeType(initializedBy: candidates), let literal = soleLiteral(of: arguments) {
            return self.literal(literal, as: type, in: range)
        }

        // A call whose arguments fit no candidate was reported.
        guard let match = match(arguments, among: candidates, in: range) else { return nil }

        // A result type that isn't known was reported in the function that gives it, or here as a cycle.
        guard let result = expressions.file.result(of: match.signature, calledAt: range) else { return nil }
        let kind = CheckedExprKind.call(match.signature.callee, arguments: match.arguments)
        return CheckedExpr(kind: kind, type: result, range: range)
    }

    /// The prelude type whose initializers `candidates` are, or nil where they are anything else.
    private func preludeType(initializedBy candidates: [Signature]) -> RayoType? {
        guard case .builtin(let builtin)? = candidates.first?.callee else { return nil }
        return builtin.initializedType
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

    /// The one of `candidates` that `arguments` fit, with the arguments checked against its parameters.
    private func match(_ arguments: [Argument], among candidates: [Signature], in range: SourceRange) -> Match? {
        switch candidates.count {
        // Without a candidate, the arguments are checked for their own errors.
        case 0:
            checkValues(of: arguments)
            return nil

        // One candidate is the call's, if the arguments fit its parameters.
        case 1:
            return check(arguments, against: candidates[0], in: range).map { (candidates[0], $0) }

        // Among overloads, the arguments' labels and types pick one.
        default:
            return pick(among: candidates, for: arguments, in: range)
        }
    }

    /// Checks `arguments` against `signature`'s parameters, in order, reporting each mismatch.
    private func check(_ arguments: [Argument], against signature: Signature,
                       in range: SourceRange) -> [CheckedExpr]? {
        // A call that passes too few or too many arguments fails, though each argument's own errors are reported.
        let parameters = signature.parameters
        guard arguments.count == parameters.count else {
            let takes = ArgumentCount(parameters.count)
            errors.report(.argumentCount(name: signature.name, takes: takes, passes: arguments.count), at: range)
            checkValues(of: arguments)
            return nil
        }

        // Check every argument, so each one's errors are reported, before any failure fails the call.
        let checked = zip(arguments, parameters).map { check($0, against: $1) }
        let values = checked.compactMap { $0 }
        return values.count == arguments.count ? values : nil
    }

    /// Checks `argument`'s label and value against `parameter`.
    private func check(_ argument: Argument, against parameter: Parameter) -> CheckedExpr? {
        // A label other than the parameter's is reported, and fails the argument once its value is checked.
        let isLabeledRight = argument.label == parameter.label
        if !isLabeledRight {
            let expected = ArgumentLabel(parameter.label)
            errors.report(.argumentLabel(expected: expected, found: ArgumentLabel(argument.label)), at: argument.range)
        }

        // A parameter whose type isn't known was reported where it is declared; the value is checked on its own.
        guard let type = parameter.type else {
            _ = expressions.check(argument.value)
            return nil
        }
        let value = expressions.check(argument.value, expecting: Expectation(type))
        return isLabeledRight ? value : nil
    }

    /// The one of `candidates` whose labels and parameter types `arguments` fit, with the arguments settled to its
    /// parameters' types.
    private func pick(among candidates: [Signature], for arguments: [Argument], in range: SourceRange) -> Match? {
        // Check each argument on its own, since the candidate that takes it isn't known yet, so an untyped one stays
        // untyped.
        let checked = arguments.map { expressions.value(of: $0.value) }
        let values = checked.compactMap { $0 }
        // An argument that failed was reported, and without it no candidate can be picked. The other arguments'
        // literals are settled to their default types, for their own errors.
        guard values.count == arguments.count else {
            expressions.reportSettlingErrors(of: checked)
            return nil
        }

        // Pick the one candidate that the arguments' labels and values fit.
        let labels = arguments.map(\.label)
        let remaining = remaining(of: candidates, passing: labels, values)
        // No candidate fits, which is reported with the arguments' types.
        guard !remaining.isEmpty else {
            reportNoMatch(of: candidates[0].name, labels: labels, values: values, in: range)
            return nil
        }
        // Where several fit and none of them is the call's, the arguments' literals are settled for their own errors.
        guard let chosen = chosen(among: remaining, for: values, in: range) else {
            expressions.reportSettlingErrors(of: values)
            return nil
        }

        // The chosen candidate's parameters settle the untyped arguments.
        let settled = zip(values, chosen.parameters).compactMap { expressions.settled($0, toward: $1.type) }
        // An argument whose literal its parameter's type can't hold was reported.
        guard settled.count == values.count else { return nil }
        return (chosen, settled)
    }

    /// The one of `remaining`, the candidates that `values` fit, that the call reaches. Reports a call that several
    /// fit, unless one of them failed, which was reported where it is declared.
    private func chosen(among remaining: [Signature], for values: [CheckedValue], in range: SourceRange) -> Signature? {
        // No candidate needs a conversion, so one that alone remains is the call's.
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
        errors.report(.ambiguousCall(name: remaining[0].name), at: range)
        return nil
    }

    /// The candidates that a call passing arguments with `labels` and `values`, in order, can reach.
    private func remaining(of candidates: [Signature], passing labels: [String?],
                           _ values: [CheckedValue]) -> [Signature] {
        // Keep the candidates whose labels the arguments match, in order.
        let labeled = candidates.filter { $0.takesLabels(labels) }
        // Keep those that the typed arguments fit, so that an untyped argument is offered only the parameters of the
        // candidates the typed ones leave.
        let typedFit = labeled.filter { $0.takes(values, where: { $0.type != nil }) }
        // Each untyped argument takes each remaining candidate's parameter type, and a candidate it doesn't fit drops
        // out.
        return typedFit.filter { $0.takes(values, where: { $0.type == nil }) }
    }

    /// Reports a call of `name` whose arguments, with `labels` and `values`, fit none of its functions, unless an
    /// untyped argument fails to settle to its default type, which is reported in its place.
    private func reportNoMatch(of name: String, labels: [String?], values: [CheckedValue], in range: SourceRange) {
        // Each untyped argument takes its default type, which the error names it by.
        let settled = values.compactMap { expressions.settled($0, toward: nil) }
        // A literal its default type can't hold was reported.
        guard settled.count == values.count else { return }
        let typed = zip(labels, settled).map { (label: $0, type: $1.type) }
        errors.report(.noMatchingFunction(name: name, arguments: spelling(of: typed)), at: range)
    }

    /// Checks the values of `arguments` for their own errors, where no function's parameters take them.
    private func checkValues(of arguments: [Argument]) {
        for argument in arguments {
            _ = expressions.check(argument.value)
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
