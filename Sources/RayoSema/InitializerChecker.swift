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

    /// Checks a call that makes a struct, such as `Enemy(hp: 100, armor: 5)`, and returns the checked call, or nil
    /// when it has a mistake, which is reported. Each argument is matched to the field it gives a value for, so that
    /// an error about it names the field. Every argument is checked, even when the call as a whole doesn't fit.
    func checkCall(making id: StructID, with arguments: [Argument], in range: SourceRange) -> CheckedExpr? {
        let fields = expressions.file.declarations.fields(of: id)

        // When a field's own declaration has an error, such as a type that doesn't exist, the call can't be checked
        // against the struct's fields. Each argument is still checked by itself, so mistakes inside it are reported,
        // but the call adds no error of its own: the struct's mistake gives one error, not one more at every call.
        guard let types = knownTypes(of: fields) else {
            for argument in arguments { _ = expressions.check(argument.value) }
            return nil
        }

        // Match each argument to its field, and check its value against the field's type.
        let given = fieldsGiven(by: arguments, among: fields, of: id)
        let values = values(of: arguments, givenTo: given, among: fields, ofTypes: types)
        let hasEveryField = reportLeftOut(of: fields, given: given, in: range)
        let isInOrder = reportOutOfOrder(given, by: arguments, among: fields)

        // A call that fails any of these was reported.
        guard let values, hasEveryField, isInOrder, given.allSatisfy(\.isLabeledRight) else { return nil }
        let initializer = expressions.file.declarations.primaryInitializer(of: id)
        return CheckedExpr(kind: .call(.function(initializer), arguments: values), type: .structure(id), range: range)
    }

    /// The type of each field, in order, or nil when the type of any field isn't known.
    private func knownTypes(of fields: [DeclaredField]) -> [RayoType]? {
        var types: [RayoType] = []
        for field in fields {
            guard let type = field.type else { return nil }
            types.append(type)
        }
        return types
    }

    /// Finds the field each argument gives a value for. An argument whose label names a field gives that field, and
    /// one without such a label gives the field at its own place in the call. Reports an argument that gives no
    /// field, or a field an earlier argument gave already, and an argument whose label isn't its field's name.
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

    /// Reports an argument that gives none of the struct's fields, naming its label where it has one.
    private func reportNoField(for argument: Argument, of id: StructID) {
        let code: ErrorCode = switch argument.label {
        case let label?: .noSuchField(type: expressions.typeName(of: .structure(id)), field: label)
        case nil: .argumentNamesNoField(type: expressions.typeName(of: .structure(id)))
        }
        errors.report(code, at: argument.range)
    }

    /// Checks each argument's value against the type of the field it gives; the struct takes the value as its own.
    /// Returns the checked values, or nil when any value has a mistake or gives no field.
    private func values(
        of arguments: [Argument], givenTo given: [GivenField], among fields: [DeclaredField], ofTypes types: [RayoType],
    ) -> [CheckedExpr]? {
        // Check every argument, so each one's errors are reported, before any failure fails the call.
        var values: [CheckedExpr] = []
        for (argument, given) in zip(arguments, given) {
            let expected = given.field.map { field in
                Expectation(types[field]) { .fieldTypeMismatch(field: fields[field].name, expected: $0, found: $1) }
            }
            let value = expressions.check(argument.value, expecting: expected)
            // A value that failed, that has another type than its field's, or that gives no field, was reported.
            guard let value, given.field != nil else { continue }
            values.append(value)
        }
        return values.count == arguments.count ? values : nil
    }

    /// Reports each field that no argument gives a value for, and returns whether every field has one.
    private func reportLeftOut(of fields: [DeclaredField], given: [GivenField], in range: SourceRange) -> Bool {
        let givenFields = Set(given.compactMap(\.field))
        let leftOut = fields.indices.filter { !givenFields.contains($0) }
        for field in leftOut {
            errors.report(.fieldLeftOut(field: fields[field].name), at: range)
        }
        return leftOut.isEmpty
    }

    /// Reports each argument that gives a field out of the struct's order: one the struct declares before a field
    /// an earlier argument gave. Returns whether the fields come in order.
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
