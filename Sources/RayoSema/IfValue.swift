import RayoCheckedProgram
import RayoSource

/// An `if` used for its value, checked on its own: its condition, each branch's statements and how the branch ends,
/// and the type its branches agree on. The values the branches end in wait for the `if`'s position, which the branch
/// that runs stands in.
struct IfValue {
    /// A branch: the statements it runs, and how it ends.
    struct Branch {
        var statements: [CheckedStmt]
        var end: End
    }

    /// How a branch ends.
    enum End {
        /// In an expression, whose value the branch gives.
        case value(CheckedValue)
        /// In another statement, or in none, at the given place, so the branch gives Void.
        case void(at: SourceRange)
        /// Nowhere: no run reaches the branch's end, so it gives no value, and fits any type.
        case leaves

        /// The value the branch ends in, where it ends in one.
        var value: CheckedValue? {
            if case .value(let value) = self { value } else { nil }
        }

        /// Whether a run reaches the end.
        var isReached: Bool {
            if case .leaves = self { false } else { true }
        }

        /// The type the end fixes: its value's, or Void.
        var type: RayoType? {
            switch self {
            case .value(let value): value.type
            case .void: .void
            case .leaves: nil
            }
        }

        /// The type the end fixes, or its value's default type.
        var typeOrDefault: RayoType? {
            if case .value(let value) = self { value.typeOrDefault } else { type }
        }

        /// Whether the end can stand where a position expects `type`. One that no run reaches fits any type.
        func fits(_ type: RayoType, in declarations: Declarations) -> Bool {
            switch self {
            case .value(let value): value.fits(type, in: declarations)
            case .void: TypeFit.fits(.void, type)
            case .leaves: true
            }
        }
    }

    var condition: CheckedExpr
    var then: Branch
    var otherwise: Branch
    /// Where the source writes the whole `if`.
    var range: SourceRange
    /// The type the branches agree on that each of them can take, or nil where they agree on none that all take.
    private(set) var agreedType: RayoType?

    /// The `if` of `condition`, `then` and `otherwise` that the source gives at `range`, whose branches agree on a
    /// type only where each can take it, as `declarations` gives the members an implicit member names.
    init(condition: CheckedExpr, then: Branch, otherwise: Branch, range: SourceRange, in declarations: Declarations) {
        self.condition = condition
        self.then = then
        self.otherwise = otherwise
        self.range = range
        agreedType = ruledType.flatMap { type in ends.allSatisfy { $0.fits(type, in: declarations) } ? type : nil }
    }

    var branches: [Branch] { [then, otherwise] }

    /// How each branch ends.
    var ends: [End] { branches.map(\.end) }

    /// The type the one rule for values side by side picks for the branches, whether or not each can take it.
    var ruledType: RayoType? {
        CheckedValue.agreedType(of: ends.map { ($0.type, $0.typeOrDefault) })
    }
}

extension IfValue: WaitingValue {
    /// The type the branches agree on, where one of them fixes it, so a branch that waits takes the typed branches'
    /// type. None where a branch can't take it, since the `if` then fails wherever it stands.
    var type: RayoType? {
        ends.contains { $0.type != nil } ? agreedType : nil
    }

    var defaultType: RayoType? { agreedType }

    /// Whether every branch that runs to its end gives a value that fits `type`. An `if` that every branch leaves
    /// gives no value, so it fits no type here, and its position reports it where it expects none.
    func fits(_ type: RayoType, in declarations: Declarations) -> Bool {
        let reached = ends.filter(\.isReached)
        return !reached.isEmpty && reached.allSatisfy { $0.fits(type, in: declarations) }
    }

    /// Whether every branch that runs to its end ends in a `&` of a place.
    var lendsPlace: Bool {
        let reached = ends.filter(\.isReached)
        return !reached.isEmpty && reached.allSatisfy { $0.value?.lendsPlace ?? false }
    }

    func settled(toward type: RayoType?, by expressions: ExpressionChecker) -> CheckedExpr? {
        IfChecker(expressions: expressions).settled(self, toward: type, takenBy: nil)
    }

    /// Settles the branches as a position that gives no type would, with each branch's value taken by `recipient`,
    /// since the `if` hands its position to the branch that runs.
    func settled(takenBy recipient: Recipient, by expressions: ExpressionChecker) -> CheckedExpr? {
        IfChecker(expressions: expressions).settled(self, toward: nil, takenBy: recipient)
    }

    func settled(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr? {
        IfChecker(expressions: expressions).settled(self, expecting: expected)
    }
}
