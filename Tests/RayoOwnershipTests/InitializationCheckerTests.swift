import Testing
import RayoDiagnostics
import RayoIR
import RayoOwnership
import RayoSema
import RayoSource

struct InitializationCheckerTests {
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

    @Test("a move takes a value only where the local holds one, so a move that is an error takes nothing")
    func moveOfNoValue() {
        let blocks = [
            BasicBlock(statements: [
                declare(k), store(move(k, at: 1), in: k, at: 2), printing(read(k, at: 3)),
                store(1, in: x), store(move(x, at: 4), in: y), store(move(x, at: 5), in: y), printing(read(x, at: 6)),
            ], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [
            Diagnostic(.usedUninitialized(name: "k"), at: at(1)), Diagnostic(.usedAfterMove(name: "x"), at: at(5)),
        ])
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
            BasicBlock(statements: [store(1, in: x), store(move(x, at: 3), in: y)],
                       terminator: .return(move(x, at: 4))),
        ]
        #expect(errors(in: blocks) == [
            Diagnostic(.usedAfterMove(name: "x"), at: at(2)), Diagnostic(.usedAfterMove(name: "x"), at: at(4)),
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

    @Test("the uses that the same moves reach are reported once, at the first of them in the source")
    func sameMovesReportedOnce() {
        let readsTwice = store(.binary(.add, read(x, at: 3), read(x, at: 2)), in: y)
        let blocks = [
            BasicBlock(statements: [
                store(1, in: x), store(move(x, at: 1), in: y), readsTwice, printing(read(x, at: 4)),
            ], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(.usedAfterMove(name: "x"), at: at(2))])
    }

    @Test("a use that other moves reach is reported again")
    func otherMovesReportedAgain() {
        let blocks = [
            BasicBlock(statements: [store(1, in: x)], terminator: branch(then: 1, otherwise: 2)),
            BasicBlock(statements: [store(move(x, at: 1), in: y)], terminator: goto(3)),
            BasicBlock(statements: [], terminator: goto(3)),
            BasicBlock(statements: [
                printing(read(x, at: 2)), store(2, in: x), store(move(x, at: 3), in: y), printing(read(x, at: 4)),
                printing(read(x, at: 5)),
            ], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [
            Diagnostic(.usedAfterMaybeMove(name: "x"), at: at(2)), Diagnostic(.usedAfterMove(name: "x"), at: at(4)),
        ])
    }

    @Test("a use of a local that nothing has assigned since its declaration reports that it isn't initialized")
    func useBeforeAssignment() {
        let blocks = [
            BasicBlock(statements: [declare(x), printing(read(x, at: 1)), store(1, in: x), printing(read(x, at: 2))],
                       terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(.usedUninitialized(name: "x"), at: at(1))])
    }

    @Test("a local assigned on some of the paths that join isn't initialized on every path, unlike one assigned on all",
          arguments: [(true, [Diagnostic(.usedMaybeUninitialized(name: "x"), at: at(3))]), (false, [])])
    func joinUnassigned(unassignedOnOnePath: Bool, expected: [Diagnostic]) {
        let otherwise = unassignedOnOnePath ? [] : [store(2, in: x)]
        let blocks = [
            BasicBlock(statements: [declare(x)], terminator: branch(then: 1, otherwise: 2)),
            BasicBlock(statements: [store(1, in: x)], terminator: goto(3)),
            BasicBlock(statements: otherwise, terminator: goto(3)),
            BasicBlock(statements: [printing(read(x, at: 3))], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == expected)
    }

    @Test("a local moved on one path and never assigned on the other may have been moved")
    func joinMovedAndUnassigned() {
        let blocks = [
            BasicBlock(statements: [declare(x)], terminator: branch(then: 1, otherwise: 2)),
            BasicBlock(statements: [store(1, in: x), store(move(x, at: 1), in: y)], terminator: goto(2)),
            BasicBlock(statements: [printing(read(x, at: 2))], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(.usedAfterMaybeMove(name: "x"), at: at(2))])
    }

    @Test("a declaration in a loop's body leaves the local without a value, whatever the last pass assigned")
    func declarationInLoop() {
        let blocks = [
            BasicBlock(statements: [], terminator: goto(1)),
            BasicBlock(statements: [], terminator: branch(then: 2, otherwise: 3)),
            BasicBlock(statements: [declare(k), store(1, in: k, at: 1), declare(x), printing(read(x, at: 2)),
                                    store(1, in: x)], terminator: goto(1)),
            BasicBlock(statements: [], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(.usedUninitialized(name: "x"), at: at(2))])
    }

    @Test("a 'var' may be assigned any number of times, and a 'let' only once on each path")
    func assignedTwice() {
        let blocks = [
            BasicBlock(statements: [declare(x), store(1, in: x), store(2, in: x), declare(k), store(1, in: k, at: 1),
                                    store(2, in: k, at: 2), store(3, in: k, at: 3)], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [
            Diagnostic(.letAssignedTwice(name: "k"), at: at(2)), Diagnostic(.letAssignedTwice(name: "k"), at: at(3)),
        ])
    }

    @Test("a 'let' that a move left without a value was still assigned, so it can't be assigned again")
    func assignedAfterMove() {
        let blocks = [
            BasicBlock(statements: [declare(k), store(1, in: k), store(move(k, at: 1), in: y), store(2, in: k, at: 2)],
                       terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(.letAssignedTwice(name: "k"), at: at(2))])
    }

    @Test("a 'let' assigned on some of the paths that join, or on an earlier pass of a loop, may have been assigned",
          arguments: [true, false])
    func maybeAssignedTwice(inLoop: Bool) {
        let blocks = inLoop ? [
            BasicBlock(statements: [declare(k)], terminator: goto(1)),
            BasicBlock(statements: [], terminator: branch(then: 2, otherwise: 3)),
            BasicBlock(statements: [store(1, in: k, at: 1)], terminator: goto(1)),
            BasicBlock(statements: [], terminator: .return(nil)),
        ] : [
            BasicBlock(statements: [declare(k)], terminator: branch(then: 1, otherwise: 2)),
            BasicBlock(statements: [store(1, in: k)], terminator: goto(2)),
            BasicBlock(statements: [store(2, in: k, at: 1)], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(.letMaybeAssignedTwice(name: "k"), at: at(1))])
    }

    @Test("the uses that no assignment reaches since a declaration are reported once for each local")
    func unassignedReportedOnce() {
        let blocks = [
            BasicBlock(statements: [declare(x), declare(y), printing(read(x, at: 1)), printing(read(x, at: 2)),
                                    printing(read(y, at: 3))], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [
            Diagnostic(.usedUninitialized(name: "x"), at: at(1)), Diagnostic(.usedUninitialized(name: "y"), at: at(3)),
        ])
    }

    @Test(arguments: [
        ([declare(s)], ErrorCode.usedUninitialized(name: "s")),
        (storeShot() + [dropping(move(s, at: 1))], .usedAfterMove(name: "s")),
    ])
    func `a store to a field uses its local, which must hold the rest of its value`(
        before: [Statement], expected: ErrorCode,
    ) {
        let blocks = [
            BasicBlock(statements: before + [store(9, in: s, fields: shotDamage, at: 2), printing(read(s, at: 3))],
                       terminator: .return(nil)),
        ]
        // The read after the store has the same cause as the store, so the store alone is reported.
        #expect(errors(in: blocks) == [Diagnostic(expected, at: at(2))])
    }

    @Test func `a store to a field leaves its local holding its value, which a move may then take`() {
        let blocks = [
            BasicBlock(statements: storeShot() + [
                store(9, in: s, fields: shotRange, at: 1), dropping(move(s, at: 2)), printing(read(s, at: 3)),
            ], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(.usedAfterMove(name: "s"), at: at(3))])
    }

    @Test func `the errors come in source order across the program's functions`() {
        // The first function's error comes after the second's in the source.
        let usesLate = function([
            BasicBlock(
                statements: [store(1, in: x), store(move(x, at: 1), in: y), printing(read(x, at: 6))],
                terminator: .return(nil),
            ),
        ])
        let usesEarly = function([
            BasicBlock(
                statements: [store(1, in: x), store(move(x, at: 2), in: y), printing(read(x, at: 5))],
                terminator: .return(nil),
            ),
        ])

        // The checker reports the second function's error first, as the source has it.
        let reported = InitializationChecker.check(program(of: [usesLate, usesEarly]))
        #expect(reported.map(\.range.start.offset) == [5, 6])
    }
}

/// The errors the checker reports in a program of one function made of `blocks`, whose first `parameterCount` locals
/// are its parameters.
private func errors(in blocks: [BasicBlock], parameterCount: Int = 0) -> [Diagnostic] {
    InitializationChecker.check(program(of: [function(blocks, parameterCount: parameterCount)]))
}
