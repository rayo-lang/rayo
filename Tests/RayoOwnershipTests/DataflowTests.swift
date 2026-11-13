@testable import RayoOwnership
import RayoIR
import RayoSource
import Testing

struct DataflowTests {
    @Test func `going forward, a block's entry holds what every path into it brings`() {
        let blocks = [
            BasicBlock(statements: [printing(read(x, at: 1))], terminator: branch(then: 1, otherwise: 2)),
            BasicBlock(statements: [printing(read(x, at: 2))], terminator: goto(3)),
            BasicBlock(statements: [printing(read(x, at: 3))], terminator: goto(3)),
            BasicBlock(statements: [printing(read(x, at: 4))], terminator: .return(read(x, at: 5))),
        ]
        var results = solve(EvaluatedOperands(direction: .forward), blocks)
        #expect(results.state(before: 0, in: BlockID(index: 3)) == EvaluatedOperands.State([1, 2, 3]))
        #expect(results.state(after: 0, in: BlockID(index: 3)) == EvaluatedOperands.State([1, 2, 3, 4]))
        #expect(results.state(after: 1, in: BlockID(index: 3)) == EvaluatedOperands.State([1, 2, 3, 4, 5]))
    }

    @Test func `going backward, a block's exit holds what every path out of it brings`() {
        let blocks = [
            BasicBlock(statements: [printing(read(x, at: 1))], terminator: branch(then: 1, otherwise: 2)),
            BasicBlock(statements: [printing(read(x, at: 2))], terminator: goto(3)),
            BasicBlock(statements: [printing(read(x, at: 3))], terminator: goto(3)),
            BasicBlock(statements: [printing(read(x, at: 4))], terminator: .return(read(x, at: 5))),
        ]
        var results = solve(EvaluatedOperands(direction: .backward), blocks)
        #expect(results.state(after: 1, in: BlockID(index: 0)) == EvaluatedOperands.State([2, 3, 4, 5]))
        #expect(results.state(before: 0, in: BlockID(index: 0)) == EvaluatedOperands.State([1, 2, 3, 4, 5]))
        #expect(results.state(before: 0, in: BlockID(index: 3)) == EvaluatedOperands.State([4, 5]))
    }

    @Test("a loop's header holds what each pass of its body brings, in either direction", arguments: [
        (DataflowDirection.forward, 0, Set([1, 2, 3])),
        (DataflowDirection.backward, 1, Set([2, 3, 4])),
    ])
    func loop(direction: DataflowDirection, statement: Int, expected: Set<Int>) {
        let blocks = [
            BasicBlock(statements: [printing(read(x, at: 1))], terminator: goto(1)),
            BasicBlock(statements: [printing(read(x, at: 2))], terminator: branch(then: 2, otherwise: 3)),
            BasicBlock(statements: [printing(read(x, at: 3))], terminator: goto(1)),
            BasicBlock(statements: [printing(read(x, at: 4))], terminator: .return(nil)),
        ]
        var results = solve(EvaluatedOperands(direction: direction), blocks)
        #expect(results.state(before: statement, in: BlockID(index: 1)) == EvaluatedOperands.State(expected))
    }

    @Test func `going backward, a loop that no path leaves starts from the start state`() {
        let blocks = [
            BasicBlock(statements: [printing(read(x, at: 1))], terminator: goto(1)),
            BasicBlock(statements: [printing(read(x, at: 2))], terminator: goto(1)),
        ]
        var results = solve(EvaluatedOperands(direction: .backward), blocks)
        #expect(results.state(before: 0, in: BlockID(index: 1)) == EvaluatedOperands.State([2]))
        #expect(results.state(before: 0, in: BlockID(index: 0)) == EvaluatedOperands.State([1, 2]))
    }

    @Test("a block that no path from the entry reaches has no state, in either direction", arguments: [
        DataflowDirection.forward, .backward,
    ])
    func unreached(direction: DataflowDirection) {
        let blocks = [
            BasicBlock(statements: [printing(read(x, at: 1))], terminator: .return(nil)),
            BasicBlock(statements: [printing(read(x, at: 2))], terminator: goto(0)),
        ]
        var results = solve(EvaluatedOperands(direction: direction), blocks)
        #expect(results.state(before: 0, in: BlockID(index: 1)) == nil)
    }

    @Test("the states asked about a block in any order are those of its points, in either direction", arguments: [
        (DataflowDirection.forward, [Set([1, 2]), Set([1]), Set([1])]),
        (DataflowDirection.backward, [Set([3]), Set([2, 3]), Set([2, 3])]),
    ])
    func anyOrder(direction: DataflowDirection, expected: [Set<Int>]) {
        let blocks = [
            BasicBlock(
                statements: [printing(read(x, at: 1)), printing(read(x, at: 2))],
                terminator: .return(read(x, at: 3)),
            ),
        ]
        var results = solve(EvaluatedOperands(direction: direction), blocks)
        let states = [
            results.state(after: 1, in: BlockID(index: 0)), results.state(before: 1, in: BlockID(index: 0)),
            results.state(after: 0, in: BlockID(index: 0)),
        ]
        #expect(states == expected.map { EvaluatedOperands.State($0) })
    }

    // The solver checks its merges only in a debug build, which is how the tests run.
    @Test func `in a debug build, a merge that shrinks a block's state stops the solver`() async {
        await #expect(processExitsWith: .failure) {
            let blocks = [
                BasicBlock(statements: [printing(read(x, at: 1))], terminator: goto(1)),
                BasicBlock(statements: [], terminator: branch(then: 2, otherwise: 3)),
                BasicBlock(statements: [printing(read(x, at: 2))], terminator: goto(1)),
                BasicBlock(statements: [], terminator: .return(nil)),
            ]
            _ = solve(EvaluatedOperands(direction: .forward, merge: .keepingLatest), blocks)
        }
    }
}

/// The source offsets of the operands that a function may evaluate before a point going forward, or after it going
/// backward.
private struct EvaluatedOperands: DataflowAnalysis {
    /// How a state merges with another where two paths meet.
    enum Merge {
        /// Keeps the offsets of both, which only grows the state.
        case union
        /// Keeps only the later state's, which can shrink it.
        case keepingLatest
    }

    struct State: DataflowState {
        var offsets: Set<Int>
        var merge: Merge

        init(_ offsets: Set<Int>, merge: Merge = .union) {
            self.offsets = offsets
            self.merge = merge
        }

        func merged(with other: State) -> State {
            switch merge {
            case .union: State(offsets.union(other.offsets), merge: merge)
            case .keepingLatest: other
            }
        }
    }

    let direction: DataflowDirection
    var merge = Merge.union

    var startState: State {
        State([], merge: merge)
    }

    func apply(_ statement: Statement, to state: inout State) {
        // A declaration evaluates no operand.
        guard case .compute(_, let value, _) = statement else { return }
        state.offsets.formUnion(value.operands.compactMap(Self.offset))
    }

    func apply(_ terminator: Terminator, to state: inout State) {
        if let operand = terminator.operand, let offset = Self.offset(of: operand) {
            state.offsets.insert(offset)
        }
    }

    /// The offset that the source names the place an operand reads at, or nil for a constant.
    private static func offset(of operand: Operand) -> Int? {
        switch operand {
        case .constant: nil
        case .read(_, let range), .move(_, let range): range.start.offset
        }
    }
}

/// Solves `analysis` through a function made of `blocks`.
private func solve(_ analysis: EvaluatedOperands, _ blocks: [BasicBlock]) -> DataflowResults<EvaluatedOperands> {
    DataflowSolver.solve(analysis, in: function(blocks).body)
}
