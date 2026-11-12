import RayoDiagnostics
import RayoSource
import RayoSyntax

/// Checks a call of a struct's primary initializer, whose arguments give each of the struct's fields once, labeled by
/// its name, in the order the struct declares them, and take their values owned.
struct InitializerChecker {
    /// The field an argument gives a value for.
    private enum GivenField {
        /// The field at this place in the struct's declaration, under its own label.
        case field(Int)
        /// The field at this place in the struct's declaration, under a label that isn't its own, which was reported.
        case mislabeled(Int)
        /// No field, which was reported.
        case noField

        /// The field's place in the struct's declaration, where the argument gives one.
        var field: Int? {
            switch self {
            case .field(let field), .mislabeled(let field): field
            case .noField: nil
            }
        }

        /// Whether the argument gives a field under the field's own label.
        var isLabeledRight: Bool {
            switch self {
            case .field: true
            case .mislabeled, .noField: false
            }
        }
    }

    let expressions: ExpressionChecker

    private var errors: ErrorList { expressions.file.errors }

    /// Checks `id(arguments)`, which makes a value of the struct `id`. Every argument is checked, whether or not the
    /// call fits the struct's fields.
    func make(_ id: StructID, from arguments: [Argument], in range: SourceRange) -> CheckedExpr? {
        // Find the struct's fields, and the types of those whose declarations are known.
        let fields = expressions.file.declarations.fields(of: id)
        let types = fields.compactMap(\.type)

        // A struct with a field whose declaration failed, which was reported there, takes its arguments' values on
        // their own, so the failure doesn't spread to its calls.
        guard types.count == fields.count else {
            for argument in arguments { _ = expressions.checkTaken(argument.value) }
            return nil
        }

        // Match each argument to its field, and check its value against the field's type.
        let given = fieldsGiven(by: arguments, among: fields, of: id)
        let values = values(of: arguments, givenTo: given, among: fields, ofTypes: types)
        let hasEveryField = reportLeftOut(of: fields, given: given, in: range)
        let isInOrder = reportOutOfOrder(given, by: arguments, among: fields)

        // A call that fails any of these was reported.
        guard let values, hasEveryField, isInOrder, given.allSatisfy(\.isLabeledRight) else { return nil }
        return CheckedExpr(kind: .structure(id, fields: values), type: .structure(id), range: range)
    }

    /// The field that each of `arguments` gives a value for, among `fields`, those of the struct `id`. Reports each
    /// argument that gives no field, or one that an argument before it gave, and each label that isn't its field's.
    private func fieldsGiven(by arguments: [Argument], among fields: [DeclaredField], of id: StructID) -> [GivenField] {
        // Give each argument whose label names a field that field, unless an argument before it gave the field.
        var given: [GivenField?] = Array(repeating: nil, count: arguments.count)
        var taken: Set<Int> = []
        for (index, argument) in arguments.enumerated() {
            // An argument without a label, or with one that names no field, is matched below.
            guard let label = argument.label, let field = fields.firstIndex(where: { $0.name == label }) else {
                continue
            }
            // A field that an argument before gave is reported, and this argument gives none.
            guard taken.insert(field).inserted else {
                errors.report(.fieldGivenTwice(field: label), at: argument.range)
                given[index] = GivenField.noField
                continue
            }
            given[index] = .field(field)
        }

        // Give each other argument the field at its own place, where no label gave that field: its label, or its lack
        // of one, is the mistake.
        for (index, argument) in arguments.enumerated() where given[index] == nil {
            // An argument with no field left at its place gives none, which is reported.
            guard index < fields.count, taken.insert(index).inserted else {
                reportNoField(for: argument, of: id)
                given[index] = GivenField.noField
                continue
            }
            let expected = ArgumentLabel(fields[index].name)
            errors.report(.argumentLabel(expected: expected, found: ArgumentLabel(argument.label)), at: argument.range)
            given[index] = .mislabeled(index)
        }

        // Every argument has its field now, or none.
        return given.compactMap { $0 }
    }

    /// Reports `argument`, which gives no field of the struct `id`, by its label where it has one.
    private func reportNoField(for argument: Argument, of id: StructID) {
        let code: ErrorCode = switch argument.label {
        case let label?: .noSuchField(type: expressions.typeName(of: .structure(id)), field: label)
        case nil: .argumentNamesNoField(type: expressions.typeName(of: .structure(id)))
        }
        errors.report(code, at: argument.range)
    }

    /// Checks the value of each of `arguments`, which an initializer takes owned, against the type of the field it
    /// gives, among `fields`, whose types are `types`. Returns the values, or nil when any fails or gives no field.
    private func values(
        of arguments: [Argument], givenTo given: [GivenField], among fields: [DeclaredField], ofTypes types: [RayoType],
    ) -> [CheckedExpr]? {
        // Check every argument, so each one's errors are reported, before any failure fails the call.
        var values: [CheckedExpr] = []
        for (argument, given) in zip(arguments, given) {
            let value = expressions.checkTaken(argument.value)
            // A value that failed, or that gives no field, was reported.
            guard let value, let field = given.field else { continue }
            // A value of another type than the field's is reported.
            guard value.type == types[field] else {
                let code = ErrorCode.fieldTypeMismatch(
                    field: fields[field].name,
                    expected: expressions.typeName(of: types[field]),
                    found: expressions.typeName(of: value.type),
                )
                errors.report(code, at: value.range)
                continue
            }
            values.append(value)
        }
        return values.count == arguments.count ? values : nil
    }

    /// Reports each of `fields` that no argument gives a value for, as `given` says, in the call at `range`, and
    /// returns whether every field has one.
    private func reportLeftOut(of fields: [DeclaredField], given: [GivenField], in range: SourceRange) -> Bool {
        let givenFields = Set(given.compactMap(\.field))
        let leftOut = fields.indices.filter { !givenFields.contains($0) }
        for field in leftOut {
            errors.report(.fieldLeftOut(field: fields[field].name), at: range)
        }
        return leftOut.isEmpty
    }

    /// Reports each of `arguments` that gives a field, as `given` says, that `fields` declares before the field of an
    /// argument before it, and returns whether none does.
    private func reportOutOfOrder(_ given: [GivenField], by arguments: [Argument],
                                  among fields: [DeclaredField]) -> Bool {
        var latest: Int?
        var isInOrder = true
        for (argument, given) in zip(arguments, given) {
            // An argument that gives no field has no place in the order.
            guard let field = given.field else { continue }
            // A field declared before the latest one given so far comes too late, which is reported.
            if let latest, field < latest {
                errors.report(.fieldOutOfOrder(field: fields[field].name, after: fields[latest].name),
                              at: argument.range)
                isInOrder = false
            } else {
                // Any other field is the latest one given.
                latest = field
            }
        }
        return isInOrder
    }
}
