import RayoCheckedProgram
import RayoSource

/// An array literal's elements, each checked on its own, and where the source writes the literal.
struct ArrayLiteral {
    var elements: [CheckedValue]
    var range: SourceRange

    /// The type the elements settle to where the literal's position gives none: the one type they agree on.
    var defaultElementType: RayoType? {
        CheckedValue.agreedType(of: elements.map { ($0.type, $0.typeOrDefault) })
    }

    /// The array of as many elements as the literal of `element`, or nil where `element` is.
    private func array(of element: RayoType?) -> RayoType? {
        element.map { .array(count: elements.count, element: $0) }
    }
}

extension ArrayLiteral: TypeWaitingValue {
    /// The array of the type an element fixes, where one does.
    var type: RayoType? {
        array(of: elements.lazy.compactMap(\.type).first)
    }

    /// The array of the type the elements agree on.
    var defaultType: RayoType? {
        array(of: defaultElementType)
    }

    /// Whether `type` is an array of as many elements as the literal, each of which fits its element type.
    func fits(_ type: RayoType, in declarations: Declarations) -> Bool {
        guard case .array(let count, let element) = type, count == elements.count else { return false }
        return elements.allSatisfy { $0.fits(element, in: declarations) }
    }

    /// Whether `type` is an array of as many elements as the literal, each of which can settle to its element type.
    func canSettle(to type: RayoType, in declarations: Declarations) -> Bool {
        guard case .array(let count, let element) = type, count == elements.count else { return false }
        return elements.allSatisfy { $0.canSettle(to: element, in: declarations) }
    }

    func settled(toward type: RayoType?, by expressions: ExpressionChecker) -> CheckedExpr? {
        ArrayLiteralChecker(expressions: expressions).settled(self, toward: type)
    }

    /// Reports the elements' errors, and not the literal's own, whose type the failed expression would have given.
    func reportErrors(by expressions: ExpressionChecker) {
        expressions.reportSettlingErrors(of: elements)
    }
}
