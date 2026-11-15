import RayoSource

/// An `if` used for its value, checked on its own: its condition, and each branch's statements and how the branch
/// ends. The values the branches end in wait for the `if`'s position, which the branch that runs stands in.
struct IfValue {
    /// A branch: the statements it runs, and how it ends.
    struct Branch {
        /// How a branch ends.
        enum End {
            /// In an expression, whose value the branch gives.
            case value(CheckedValue)
            /// In another statement, or in none, at the given place, so the branch gives Void.
            case void(at: SourceRange)
            /// Nowhere: no run reaches the branch's end, so it gives no value, and fits any type.
            case leaves
        }

        var statements: [CheckedStmt]
        var end: End

        /// The value the branch ends in, where it ends in one.
        var value: CheckedValue? {
            if case .value(let value) = end { value } else { nil }
        }

        /// The type the branch's end fixes: its value's, or Void.
        var type: RayoType? {
            switch end {
            case .value(let value): value.type
            case .void: .void
            case .leaves: nil
            }
        }

        /// Whether a run reaches the branch's end.
        var runsToEnd: Bool {
            if case .leaves = end { false } else { true }
        }

        /// The type the branch's end fixes, or its value's default type.
        var typeOrDefault: RayoType? {
            if case .value(let value) = end { value.typeOrDefault } else { type }
        }

        /// Whether the branch's end can stand where a position expects `type`. One that no run reaches fits any type.
        func fits(_ type: RayoType, in declarations: Declarations) -> Bool {
            switch end {
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

    var branches: [Branch] { [then, otherwise] }
}

extension IfValue: WaitingValue {
    /// The type the first branch that fixes one does, so a branch that waits takes the typed branches' type.
    var type: RayoType? {
        branches.lazy.compactMap(\.type).first
    }

    /// The one type the branches agree on.
    var defaultType: RayoType? {
        CheckedValue.agreedType(of: branches.map { ($0.type, $0.typeOrDefault) })
    }

    /// Whether every branch that runs to its end gives a value that fits `type`. An `if` that every branch leaves
    /// gives no value, so it fits no type here, and its position reports it where it expects none.
    func fits(_ type: RayoType, in declarations: Declarations) -> Bool {
        let completing = branches.filter(\.runsToEnd)
        return !completing.isEmpty && completing.allSatisfy { $0.fits(type, in: declarations) }
    }

    func settled(toward type: RayoType?, by expressions: ExpressionChecker) -> CheckedExpr? {
        IfChecker(expressions: expressions).settled(self, toward: type)
    }

    func settled(expecting expected: Expectation, by expressions: ExpressionChecker) -> CheckedExpr? {
        IfChecker(expressions: expressions).settled(self, expecting: expected)
    }

    /// Reports the errors that settling the `if` where its position gives no type reports.
    func reportErrors(by expressions: ExpressionChecker) {
        _ = settled(toward: nil, by: expressions)
    }
}
