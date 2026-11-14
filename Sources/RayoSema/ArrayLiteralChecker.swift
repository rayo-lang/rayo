import RayoDiagnostics
import RayoSource

/// Settles an array literal to a type: the array type its position expects, or, where it expects none, an array of
/// the one type its elements give.
struct ArrayLiteralChecker {
    let expressions: ExpressionChecker

    private var errors: ErrorList { expressions.file.errors }

    /// Settles `literal` to `type` where it is an array type, and otherwise to the array of its elements' one type.
    func settled(_ literal: ArrayLiteral, toward type: RayoType?) -> CheckedExpr? {
        switch type {
        // An array type gives the literal its count, and its elements their type.
        case .array(let count, let element)?:
            settled(literal, toArrayOf: count, element, mismatch: ErrorCode.typeMismatch)

        // Any other position leaves the literal the type its elements give.
        default:
            settledByElements(literal)
        }
    }

    /// Settles `literal` to an array of as many elements as it has, of the type its elements give: that of its first
    /// typed element, or, where none is typed, the first default type among them. Reports an empty literal, which no
    /// element gives a type, and each element of another type.
    private func settledByElements(_ literal: ArrayLiteral) -> CheckedExpr? {
        // An empty literal has no element to give it a type.
        guard !literal.elements.isEmpty else {
            errors.report(.emptyArrayLiteral, at: literal.range)
            return nil
        }
        // Nor has one whose elements are each an empty literal, or hold only empty literals; each is reported.
        guard let element = literal.defaultElementType else {
            for element in literal.elements { _ = expressions.settled(element, toward: nil) }
            return nil
        }
        return settled(literal, toArrayOf: literal.elements.count, element, mismatch: ErrorCode.elementTypesDiffer)
    }

    /// Settles `literal` to an array of `count` values of `element`. Reports a literal of another count, and each
    /// element that doesn't have the type `element`, with the error `mismatch` gives.
    private func settled(
        _ literal: ArrayLiteral, toArrayOf count: Int, _ element: RayoType,
        mismatch: @escaping (TypeName, TypeName) -> ErrorCode,
    ) -> CheckedExpr? {
        let type = RayoType.array(count: count, element: element)

        // A literal of another count would leave elements without a value, or values with no element to hold them.
        let hasCount = literal.elements.count == count
        if !hasCount {
            let needs = ElementCount(count)
            let code = ErrorCode.arrayLiteralCount(type: expressions.typeName(of: type), needs: needs,
                                                   found: literal.elements.count)
            errors.report(code, at: literal.range)
        }

        // Every element is settled, so each one's errors are reported, before any failure fails the literal.
        let expected = Expectation(element, mismatch: mismatch)
        let settled = literal.elements.map { expressions.settled($0, expecting: expected) }
        let elements = settled.compactMap { $0 }
        guard hasCount, elements.count == settled.count else { return nil }
        return CheckedExpr(kind: .arrayLiteral(elements), type: type, range: literal.range)
    }
}
