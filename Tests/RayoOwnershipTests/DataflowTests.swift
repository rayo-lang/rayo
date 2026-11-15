@testable import RayoOwnership
import RayoIR
import RayoSema
import Testing

struct DataflowTests {
    @Test func `going forward, a block's entry holds what every path into it brings`() throws {
        let results = try solve(EvaluatedOperands(direction: .forward), diamond, result: "Int")
        let join = try #require(states(of: results, in: 3))
        #expect(join[0] == EvaluatedOperands.State([1, 2, 3]))
        #expect(join[1] == EvaluatedOperands.State([1, 2, 3, 4]))
        #expect(join[2] == EvaluatedOperands.State([1, 2, 3, 4, 5]))
    }

    @Test func `going backward, a block's exit holds what every path out of it brings`() throws {
        let results = try solve(EvaluatedOperands(direction: .backward), diamond, result: "Int")
        let branch = try #require(states(of: results, in: 0))
        #expect(branch[2] == EvaluatedOperands.State([2, 3, 4, 5]))
        #expect(branch[0] == EvaluatedOperands.State([1, 2, 3, 4, 5]))
        #expect(states(of: results, in: 3)?[0] == EvaluatedOperands.State([4, 5]))
    }

    @Test(arguments: [
        (DataflowDirection.forward, 0, Set([1, 2, 3])),
        (DataflowDirection.backward, 1, Set([2, 3, 4])),
    ])
    func `a loop's header holds what each pass of its body brings, in either direction`(
        direction: DataflowDirection, statement: Int, expected: Set<Int>,
    ) throws {
        let blocks = """
            bb0:
              \(printing(1))
              goto bb1
            bb1:
              \(printing(2))
              branch true, bb2, bb3
            bb2:
              \(printing(3))
              goto bb1
            bb3:
              \(printing(4))
              return
            """
        let results = try solve(EvaluatedOperands(direction: direction), blocks)
        #expect(states(of: results, in: 1)?[statement] == EvaluatedOperands.State(expected))
    }

    @Test func `going backward, a loop that no path leaves starts from the start state`() throws {
        let blocks = """
            bb0:
              \(printing(1))
              goto bb1
            bb1:
              \(printing(2))
              goto bb1
            """
        let results = try solve(EvaluatedOperands(direction: .backward), blocks)
        #expect(states(of: results, in: 1)?[0] == EvaluatedOperands.State([2]))
        #expect(states(of: results, in: 0)?[0] == EvaluatedOperands.State([1, 2]))
    }

    @Test(arguments: [
        DataflowDirection.forward, .backward,
    ])
    func `a block that no path from the entry reaches has no state, in either direction`(
        direction: DataflowDirection,
    ) throws {
        let blocks = """
            bb0:
              \(printing(1))
              return
            bb1:
              \(printing(2))
              goto bb0
            """
        let results = try solve(EvaluatedOperands(direction: direction), blocks)
        #expect(states(of: results, in: 1) == nil)
    }

    @Test(arguments: [
        (DataflowDirection.forward, [0, 1, 2, 3], [Set(), Set([1]), Set([1, 2]), Set([1, 2, 3])]),
        (DataflowDirection.backward, [3, 2, 1, 0], [Set(), Set([3]), Set([2, 3]), Set([1, 2, 3])]),
    ])
    func `a walk lends the state at each point of a block once, in the analysis's direction`(
        direction: DataflowDirection, points: [Int], expected: [Set<Int>],
    ) throws {
        let blocks = """
            bb0:
              \(printing(1))
              \(printing(2))
              return read %0 @2:3-2:3
            """
        let results = try solve(EvaluatedOperands(direction: direction), blocks, result: "Int")
        var visited: [(point: Int, state: EvaluatedOperands.State)] = []
        results.walk(BlockID(index: 0)) { visited.append(($0, $1)) }
        #expect(visited.map(\.point) == points)
        #expect(visited.map(\.state) == expected.map { EvaluatedOperands.State($0) })
    }

    // The solver checks its merges only in a debug build, which is how the tests run.
    @Test func `in a debug build, a merge that shrinks a block's state stops the solver`() async {
        await #expect(processExitsWith: .failure) {
            let blocks = """
                bb0:
                  \(printing(1))
                  goto bb1
                bb1:
                  branch true, bb2, bb3
                bb2:
                  \(printing(2))
                  goto bb1
                bb3:
                  return
                """
            _ = try solve(EvaluatedOperands(direction: .forward, merge: .keepingLatest), blocks)
        }
    }
}

/// Blocks that branch from the first to the second or the third, both of which go on to the fourth, which returns `x`.
/// Each block prints `x`, at the column of line 2 that is its number, and the return reads it at column 5.
private let diamond = """
    bb0:
      \(printing(1))
      branch true, bb1, bb2
    bb1:
      \(printing(2))
      goto bb3
    bb2:
      \(printing(3))
      goto bb3
    bb3:
      \(printing(4))
      return read %0 @2:5-2:5
    """

/// Prints `x`, which the source names at `column` of line 2.
private func printing(_ column: Int) -> String {
    "_ = call builtin \"print(_: Int)\"(read %0 @2:\(column)-2:\(column)) @1:1-1:1"
}

/// The source columns of the operands that a function may evaluate before a point going forward, or after it going
/// backward.
private struct EvaluatedOperands: DataflowAnalysis {
    /// How a state merges with another where two paths meet.
    enum Merge {
        /// Keeps the columns of both, which only grows the state.
        case union
        /// Keeps only the later state's, which can shrink it.
        case keepingLatest
    }

    struct State: DataflowState {
        var columns: Set<Int>
        var merge: Merge

        init(_ columns: Set<Int>, merge: Merge = .union) {
            self.columns = columns
            self.merge = merge
        }

        func merged(with other: State) -> State {
            switch merge {
            case .union: State(columns.union(other.columns), merge: merge)
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
        state.columns.formUnion(value.operands.compactMap(Self.column))
    }

    func apply(_ terminator: Terminator, to state: inout State) {
        if let operand = terminator.operand, let column = Self.column(of: operand) {
            state.columns.insert(column)
        }
    }

    /// The column that the source names the place an operand reads at, or nil for a constant.
    private static func column(of operand: Operand) -> Int? {
        switch operand {
        case .constant: nil
        case .read(_, let range), .move(_, let range): range.start.column
        }
    }
}

/// Solves `analysis` through a function that returns `result` and is made of `blocks`.
private func solve(
    _ analysis: EvaluatedOperands, _ blocks: String, result: String = "Void",
) throws -> DataflowResults<EvaluatedOperands> {
    let program = try program(of: [function(blocks, result: result)])
    // The program's one function has a body.
    let body = try #require(program.bodies[FunctionID(index: 0)])
    return DataflowSolver.solve(analysis, in: body)
}

/// The state at each point of the block at `index`, which `results` settle on, in the order of the points; nil where no
/// state reaches the block.
private func states(of results: DataflowResults<EvaluatedOperands>, in index: Int) -> [EvaluatedOperands.State]? {
    var states: [Int: EvaluatedOperands.State] = [:]
    guard results.walk(BlockID(index: index), visit: { states[$0] = $1 }) else { return nil }
    return states.sorted { $0.key < $1.key }.map(\.value)
}
