import Testing
import RayoDiagnostics
import RayoIR
import RayoOwnership

struct UnusedValueCheckerTests {
    @Test func `a value stored in a local that no code reads is reported at the store`() {
        let blocks = [BasicBlock(statements: [declare(k), store(1, in: k, at: 1)], terminator: .return(nil))]
        #expect(errors(in: blocks) == [Diagnostic(.unreadValue(name: "k"), at: at(1))])
    }

    @Test("a value that an assignment overwrites before any code reads it is reported, and the new one isn't")
    func overwritten() {
        let blocks = [
            BasicBlock(statements: [store(1, in: x, at: 1), store(2, in: x, at: 2), printing(read(x, at: 3))],
                       terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(.unreadValue(name: "x"), at: at(1))])
    }

    @Test func `a value read on one of the paths from its store is used, though another path overwrites it`() {
        let blocks = [
            BasicBlock(statements: [store(1, in: x, at: 1)], terminator: branch(then: 1, otherwise: 2)),
            BasicBlock(statements: [printing(read(x, at: 2))], terminator: goto(2)),
            BasicBlock(statements: [store(2, in: x, at: 3), printing(move(x, at: 4))], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [])
    }

    @Test("a value stored in a loop's body is used when the next pass reads it", arguments: [
        (true, [Diagnostic]()),
        (false, [Diagnostic(.unreadValue(name: "x"), at: at(1)), Diagnostic(.unreadValue(name: "x"), at: at(2))]),
    ])
    func loop(bodyReads: Bool, expected: [Diagnostic]) {
        let value: Rvalue = bodyReads ? .binary(.add, read(x, at: 3), .constant(.int(1))) : .use(.constant(.int(1)))
        let blocks = [
            BasicBlock(statements: [store(0, in: x, at: 1)], terminator: goto(1)),
            BasicBlock(statements: [], terminator: branch(then: 2, otherwise: 3)),
            BasicBlock(statements: [store(value, in: x, at: 2)], terminator: goto(1)),
            BasicBlock(statements: [], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == expected)
    }

    @Test func `a branch's condition and a return's result read the locals they name`() {
        let toNext = Terminator.branch(read(x, at: 1), then: BlockID(index: 1), otherwise: BlockID(index: 1))
        let blocks = [
            BasicBlock(statements: [store(1, in: x)], terminator: toNext),
            BasicBlock(statements: [store(2, in: y)], terminator: .return(move(y, at: 2))),
        ]
        #expect(errors(in: blocks) == [])
    }

    @Test func `a declaration starts its local's life, so a read after it reads no value stored before it`() {
        let blocks = [
            BasicBlock(statements: [store(1, in: x, at: 1), declare(x), printing(read(x, at: 2))],
                       terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(.unreadValue(name: "x"), at: at(1))])
    }

    @Test func `a temporary that no code reads reports nothing, since lowering made it`() {
        let blocks = [BasicBlock(statements: [store(1, in: t)], terminator: .return(nil))]
        #expect(errors(in: blocks) == [])
    }

    @Test func `a block that no path reaches reports nothing`() {
        let blocks = [
            BasicBlock(statements: [], terminator: .return(nil)),
            BasicBlock(statements: [store(1, in: x, at: 1)], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [])
    }

    @Test(arguments: [
        (read(s, at: 3), [Diagnostic]()),
        (read(s, fields: shotHit, at: 3), []),
        (read(s, fields: shotDamage, at: 3), []),
        (read(s, fields: shotRange, at: 3), [Diagnostic(.unreadValue(name: "s.hit.damage"), at: at(2))]),
    ])
    func `a value stored in a field is read by a later read of the field, or of a struct that holds it`(
        later: Operand, expected: [Diagnostic],
    ) {
        // The last read, of `range`, reads the Shot that `s` is given, so only the store to `damage` may go unread.
        let blocks = [
            BasicBlock(statements: storeShot(at: 1) + [
                store(9, in: s, fields: shotDamage, at: 2), printing(later),
                printing(read(s, fields: shotRange, at: 4)),
            ], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == expected)
    }

    @Test func `a store to a field leaves the struct's other fields as they were, which a later read still reads`() {
        let blocks = [
            BasicBlock(statements: storeShot(at: 1) + [
                store(9, in: s, fields: shotRange, at: 2), printing(read(s, fields: shotDamage, at: 3)),
                printing(read(s, fields: shotRange, at: 4)),
            ], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [])
    }

    @Test(arguments: [
        (shotRange, Rvalue.use(.constant(.int(9))), "s.range"),
        (shotDamage, .use(.constant(.int(9))), "s.hit.damage"),
        (shotHit, .structure(hit, fields: [.constant(.int(9))]), "s.hit"),
    ])
    func `a later read of the whole struct doesn't read a field's value that a store replaced before it`(
        field: [Int], value: Rvalue, path: String,
    ) {
        // The struct's other fields keep the values the first store to `s` gave them, which the move reads.
        let blocks = [
            BasicBlock(statements: storeShot(at: 1) + [
                store(value, in: s, fields: field, at: 2), store(value, in: s, fields: field, at: 3),
                dropping(move(s, at: 4)),
            ], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(.unreadValue(name: path), at: at(2))])
    }

    @Test func `a struct's value is never read when each of its fields that code reads is replaced first`() {
        let blocks = [
            BasicBlock(statements: storeShot(at: 1) + [
                store(9, in: s, fields: shotRange, at: 2), printing(read(s, fields: shotRange, at: 3)),
            ], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(.unreadValue(name: "s"), at: at(1))])
    }

    @Test func `the errors come in source order across the program's functions`() {
        // The first function's error comes after the second's in the source.
        let late = function([BasicBlock(statements: [store(1, in: x, at: 6)], terminator: .return(nil))])
        let early = function([BasicBlock(statements: [store(1, in: x, at: 5)], terminator: .return(nil))])

        // The checker reports the second function's error first, as the source has it.
        let reported = UnusedValueChecker.check(program(of: [late, early]))
        #expect(reported.map(\.range.start.offset) == [5, 6])
    }
}

/// The errors the checker reports in a program of one function made of `blocks`.
private func errors(in blocks: [BasicBlock]) -> [Diagnostic] {
    UnusedValueChecker.check(program(of: [function(blocks)]))
}
