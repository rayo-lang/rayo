import RayoCheckedProgram
import RayoIR
import Testing

struct DataflowTests {
    @Test func `going forward, a block's entry holds what every path into it brings`() throws {
        let results = try solve(EvaluatedOperands(direction: .forward), diamond, result: "Int")
        let join = try #require(states(of: results, in: 3))
        #expect(join[0] == [1, 2, 3])
        #expect(join[1] == [1, 2, 3, 4])
        #expect(join[2] == [1, 2, 3, 4, 5])
    }

    @Test func `going backward, a block's exit holds what every path out of it brings`() throws {
        let results = try solve(EvaluatedOperands(direction: .backward), diamond, result: "Int")
        let branch = try #require(states(of: results, in: 0))
        #expect(branch[2] == [2, 3, 4, 5])
        #expect(branch[0] == [1, 2, 3, 4, 5])
        #expect(states(of: results, in: 3)?[0] == [4, 5])
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
              \(reading(1))
              goto bb1
            bb1:
              \(reading(2))
              branch true, bb2, bb3
            bb2:
              \(reading(3))
              goto bb1
            bb3:
              \(reading(4))
              return
            """
        let results = try solve(EvaluatedOperands(direction: direction), blocks)
        #expect(states(of: results, in: 1)?[statement] == expected)
    }

    @Test func `going backward, a loop that no path leaves starts from the start state`() throws {
        let blocks = """
            bb0:
              \(reading(1))
              goto bb1
            bb1:
              \(reading(2))
              goto bb1
            """
        let results = try solve(EvaluatedOperands(direction: .backward), blocks)
        #expect(states(of: results, in: 1)?[0] == [2])
        #expect(states(of: results, in: 0)?[0] == [1, 2])
    }

    @Test(arguments: [
        DataflowDirection.forward, .backward,
    ])
    func `a block that no path from the entry reaches has no state, in either direction`(
        direction: DataflowDirection,
    ) throws {
        let blocks = """
            bb0:
              \(reading(1))
              return
            bb1:
              \(reading(2))
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
              \(reading(1))
              \(reading(2))
              return read %0 @2:3-2:3
            """
        let results = try solve(EvaluatedOperands(direction: direction), blocks, result: "Int")
        var visited: [(point: Int, columns: Set<Int>)] = []
        results.walk(BlockID(index: 0)) { visited.append(($0, $1.columns)) }
        #expect(visited.map(\.point) == points)
        #expect(visited.map(\.columns) == expected)
    }

    @Test(arguments: [
        (DataflowDirection.forward, [1, 2, 3], [Set(), Set([1]), Set([1, 2])]),
        (DataflowDirection.backward, [3, 2, 1], [Set(), Set([3]), Set([2, 3])]),
    ])
    func `a walk of effects lends each effect once, with the state just before it in the analysis's direction`(
        direction: DataflowDirection, columns: [Int], expected: [Set<Int>],
    ) throws {
        let blocks = """
            bb0:
              \(reading(1))
              \(reading(2))
              return read %0 @2:3-2:3
            """
        let results = try solve(EvaluatedOperands(direction: direction), blocks, result: "Int")
        var visited: [(column: Int, columns: Set<Int>)] = []
        results.walkEffects(of: BlockID(index: 0)) { effect, state in
            guard case .read(_, let range) = effect else { return }
            visited.append((range.start.column, state.columns))
        }
        #expect(visited.map(\.column) == columns)
        #expect(visited.map(\.columns) == expected)
    }

    // Each statement reads, and the return reads and then leaves the function, so the block has four effects.
    @Test(arguments: [
        (DataflowDirection.forward, [0, 1, 2, 3, 4], [[], [1], [1, 2], [1, 2, 3], [1, 2, 3]]),
        (DataflowDirection.backward, [4, 3, 2, 1, 0], [[], [], [3], [2, 3], [1, 2, 3]]),
    ] as [(DataflowDirection, [Int], [Set<Int>])])
    func `a walk between effects lends the state before a block's first effect, and after each of its effects`(
        direction: DataflowDirection, counts: [Int], expected: [Set<Int>],
    ) throws {
        let blocks = """
            bb0:
              \(reading(1))
              \(reading(2))
              return read %0 @2:3-2:3
            """
        let results = try solve(EvaluatedOperands(direction: direction), blocks, result: "Int")
        var visited: [(effectsBefore: Int, columns: Set<Int>)] = []
        results.walkBetweenEffects(of: BlockID(index: 0)) { visited.append(($0, $1.columns)) }
        #expect(visited.map(\.effectsBefore) == counts)
        #expect(visited.map(\.columns) == expected)
    }

    // Going forward, the block after the last loop holds every loop's reads; going backward, the entry block does.
    @Test(arguments: [
        (DataflowDirection.forward, 7), (.backward, 0),
    ])
    func `loops in a row hand on what every pass of each brings, in either direction`(
        direction: DataflowDirection, block: Int,
    ) throws {
        let results = try solve(EvaluatedOperands(direction: direction), loopsInARow(3))
        #expect(states(of: results, in: block)?.first == Set(1...6))
    }

    // The solver checks its merges only in a debug build, which is how the tests run.
    @Test func `in a debug build, a merge that shrinks a block's state stops the solver`() async {
        await #expect(processExitsWith: .failure) {
            let blocks = """
                bb0:
                  \(reading(1))
                  goto bb1
                bb1:
                  branch true, bb2, bb3
                bb2:
                  \(reading(2))
                  goto bb1
                bb3:
                  return
                """
            _ = try solve(EvaluatedOperands(direction: .forward, merge: .keepingLatest), blocks)
        }
    }
}

/// Blocks that branch from the first to the second or the third, both of which go on to the fourth, which returns `x`.
/// Block N reads `x` at column N of line 2, and the return at column 5.
private let diamond = """
    bb0:
      \(reading(1))
      branch true, bb1, bb2
    bb1:
      \(reading(2))
      goto bb3
    bb2:
      \(reading(3))
      goto bb3
    bb3:
      \(reading(4))
      return read %0 @2:5-2:5
    """

/// Reads `x` at `column` of line 2, and drops its value.
private func reading(_ column: Int) -> String {
    "_ = operand read %0 @2:\(column)-2:\(column) @1:1-1:1"
}

/// The source columns of the operands that a function may evaluate before a point going forward, or after it going
/// backward.
private struct EvaluatedOperands: DataflowState {
    /// How a state merges with another where two paths meet.
    enum Merge {
        /// Keeps the columns of both, which only grows the state.
        case union
        /// Keeps only the later state's, which can shrink it.
        case keepingLatest
    }

    let direction: DataflowDirection
    var merge = Merge.union
    var columns: Set<Int> = []

    func merged(with other: EvaluatedOperands) -> EvaluatedOperands {
        switch merge {
        case .union: EvaluatedOperands(direction: direction, merge: merge, columns: columns.union(other.columns))
        case .keepingLatest: other
        }
    }

    mutating func apply(_ effect: Effect, in function: Void) {
        // Only a read or a move evaluates an operand.
        switch effect {
        case .read(_, let range), .move(_, let range): columns.insert(range.start.column)
        case .store, .begin, .use, .end, .depend, .declare, .retire, .exit: break
        }
    }
}

/// Blocks that run `count` loops one after another, each a header and a body. Each reads `x` at a column of its own,
/// so each pass of a body adds to its header's state.
private func loopsInARow(_ count: Int) -> String {
    let loops = (0..<count).map { loop in
        let (header, body) = (2 * loop + 1, 2 * loop + 2)
        return """
            bb\(header):
              \(reading(header))
              branch true, bb\(body), bb\(header + 2)
            bb\(body):
              \(reading(body))
              goto bb\(header)
            """
    }
    return "bb0:\n  goto bb1\n" + loops.joined(separator: "\n") + "\nbb\(2 * count + 1):\n  return"
}

/// Solves the walk from `start` through a function that returns `result` and is made of `blocks`.
private func solve(
    _ start: EvaluatedOperands, _ blocks: String, result: String = "Void",
) throws -> DataflowResults<EvaluatedOperands> {
    DataflowSolver.solve(from: start, through: try body(of: blocks, result: result), knowing: ())
}

/// The body of a function made of `blocks`, whose one local is the Int `x` (`%0`), and which returns `result`.
private func body(of blocks: String, result: String = "Void") throws -> IRBody {
    let program = try IRParser.program(from: """
        main "f()"
        func "f()"() -> \(result) {
          var %0 x: Int @1:1-1:1
        \(blocks)
        }
        """)
    #expect(try verify(program, from: .lowering) == nil)
    // The program's one function has a body.
    return try #require(program.bodies[FunctionID(index: 0)])
}

/// The columns at each point of the block at `index`, which `results` settle on, in the order of the points; nil where
/// no state reaches the block.
private func states(of results: DataflowResults<EvaluatedOperands>, in index: Int) -> [Set<Int>]? {
    var states: [Int: Set<Int>] = [:]
    guard results.walk(BlockID(index: index), visit: { states[$0] = $1.columns }) else { return nil }
    return states.sorted { $0.key < $1.key }.map(\.value)
}
