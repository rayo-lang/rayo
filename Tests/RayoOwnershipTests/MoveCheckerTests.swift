import Testing
import RayoDiagnostics
import RayoIR
import RayoOwnership
import RayoSema
import RayoSource

/// The locals of the function each test checks.
private let x = 0, y = 1

struct MoveCheckerTests {
    @Test("a use of a local after a move reports that it was moved, at the use")
    func useAfterMove() {
        let blocks = [
            BasicBlock(statements: [store(1, in: x), store(move(x, at: 1), in: y), printing(read(x, at: 2))],
                       terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(.usedAfterMove(name: "x"), at: at(2))])
    }

    @Test("a move uses the local as a read does, so moving it again is reported there")
    func moveAfterMove() {
        let blocks = [
            BasicBlock(statements: [store(1, in: x), store(move(x, at: 1), in: y), store(move(x, at: 2), in: y)],
                       terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(.usedAfterMove(name: "x"), at: at(2))])
    }

    @Test("an assignment gives a moved local a value again")
    func reassigned() {
        let blocks = [
            BasicBlock(statements: [
                store(1, in: x), store(move(x, at: 1), in: y), store(2, in: x), printing(read(x, at: 2)),
            ], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [])
    }

    @Test("a parameter holds its argument from the function's entry")
    func parameterHoldsValue() {
        let blocks = [BasicBlock(statements: [printing(read(x, at: 1))], terminator: .return(nil))]
        #expect(errors(in: blocks, parameterCount: 1) == [])
    }

    @Test("a local moved on some of the paths that join may have been moved, and one moved on all of them was moved",
          arguments: [(true, ErrorCode.usedAfterMaybeMove(name: "x")), (false, .usedAfterMove(name: "x"))])
    func join(keptOnOnePath: Bool, expected: ErrorCode) {
        let otherwise = keptOnOnePath ? [] : [store(move(x, at: 2), in: y)]
        let blocks = [
            BasicBlock(statements: [store(1, in: x)], terminator: branch(then: 1, otherwise: 2)),
            BasicBlock(statements: [store(move(x, at: 1), in: y)], terminator: goto(3)),
            BasicBlock(statements: otherwise, terminator: goto(3)),
            BasicBlock(statements: [printing(read(x, at: 3))], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(expected, at: at(3))])
    }

    @Test("a move in a loop's body leaves the local without a value on the next pass, unless the body assigns it again",
          arguments: [(false, [Diagnostic(.usedAfterMaybeMove(name: "x"), at: at(1))]), (true, [])])
    func loop(assignsAgain: Bool, expected: [Diagnostic]) {
        let body = [store(move(x, at: 1), in: y)] + (assignsAgain ? [store(2, in: x)] : [])
        let blocks = [
            BasicBlock(statements: [store(1, in: x)], terminator: goto(1)),
            BasicBlock(statements: [], terminator: branch(then: 2, otherwise: 3)),
            BasicBlock(statements: body, terminator: goto(1)),
            BasicBlock(statements: [], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == expected)
    }

    @Test("a branch's condition and a return's result are uses, and a return's result may be a move")
    func terminators() {
        let blocks = [
            BasicBlock(statements: [store(1, in: x), store(move(x, at: 1), in: y)],
                       terminator: .branch(read(x, at: 2), then: BlockID(index: 1), otherwise: BlockID(index: 1))),
            BasicBlock(statements: [], terminator: .return(move(x, at: 3))),
        ]
        #expect(errors(in: blocks) == [
            Diagnostic(.usedAfterMove(name: "x"), at: at(2)), Diagnostic(.usedAfterMove(name: "x"), at: at(3)),
        ])
    }

    @Test("a block that no path reaches reports nothing")
    func unreachable() {
        let blocks = [
            BasicBlock(statements: [store(1, in: x)], terminator: .return(move(x, at: 1))),
            BasicBlock(statements: [printing(read(x, at: 2))], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [])
    }

    @Test("every use without a value is reported, in source order across the program's functions")
    func sourceOrder() {
        let movesTwice = function([
            BasicBlock(statements: [store(1, in: x), store(move(x, at: 1), in: y), printing(read(x, at: 6)),
                                    printing(read(x, at: 4))], terminator: .return(nil)),
        ])
        let movesOnce = function([
            BasicBlock(statements: [store(1, in: x), store(move(x, at: 2), in: y), printing(read(x, at: 5))],
                       terminator: .return(nil)),
        ])
        let program = IRProgram(functions: [movesTwice, movesOnce], main: FunctionID(index: 0))
        #expect(MoveChecker.check(program).map(\.range.start.offset) == [4, 5, 6])
    }
}

/// The errors the move checker reports in a function made of `blocks`, whose locals are named `x` and `y`, the
/// first `parameterCount` of them its parameters.
private func errors(in blocks: [BasicBlock], parameterCount: Int = 0) -> [Diagnostic] {
    MoveChecker.check(IRProgram(functions: [function(blocks, parameterCount: parameterCount)],
                                main: FunctionID(index: 0)))
}

/// A function made of `blocks`, whose locals are named `x` and `y`, the first `parameterCount` of them its
/// parameters.
private func function(_ blocks: [BasicBlock], parameterCount: Int = 0) -> IRFunction {
    let locals = ["x", "y"].map { IRLocal(type: .int, name: $0) }
    return IRFunction(name: "f()", parameterCount: parameterCount, result: .void, locals: locals, blocks: blocks)
}

private func goto(_ block: Int) -> Terminator {
    .goto(BlockID(index: block))
}

/// A branch on a condition that the move checker can't tell the value of.
private func branch(then: Int, otherwise: Int) -> Terminator {
    .branch(.constant(.bool(true)), then: BlockID(index: then), otherwise: BlockID(index: otherwise))
}

/// A range that starts and ends at `offset` in a file of one line, so each use a test writes has a range of its
/// own.
private func at(_ offset: Int) -> SourceRange {
    let location = SourceLocation(line: 1, column: offset + 1, offset: offset)
    return SourceRange(location, location)
}

private func read(_ local: Int, at offset: Int) -> Operand {
    .read(Place(local: LocalID(index: local), range: at(offset)))
}

private func move(_ local: Int, at offset: Int) -> Operand {
    .move(Place(local: LocalID(index: local), range: at(offset)))
}

private func store(_ operand: Operand, in local: Int) -> Statement {
    Statement(destination: LocalID(index: local), value: .use(operand), range: at(0))
}

private func store(_ value: Int64, in local: Int) -> Statement {
    store(.constant(.int(value)), in: local)
}

private func printing(_ operand: Operand) -> Statement {
    Statement(destination: nil, value: .call(.printInt, arguments: [operand]), range: at(0))
}
