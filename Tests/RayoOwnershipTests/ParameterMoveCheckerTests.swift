import Testing
import RayoDiagnostics
import RayoIR
import RayoOwnership
import RayoSema

struct ParameterMoveCheckerTests {
    @Test func `a move out of a borrowed parameter is reported at the move`() {
        let blocks = [BasicBlock(statements: [dropping(move(n, at: 1))], terminator: .return(nil))]
        #expect(errors(in: blocks) == [Diagnostic(.moveFromParameter(name: "n"), at: at(1))])
    }

    @Test("a move of a field out of a borrowed parameter is reported with the field's name", arguments: [
        ([1], "p.hit"),
        ([1, 0], "p.hit.damage"),
    ])
    func fieldMove(fields: [Int], name: String) {
        let blocks = [BasicBlock(statements: [dropping(move(p, fields: fields, at: 1))], terminator: .return(nil))]
        #expect(errors(in: blocks) == [Diagnostic(.moveFieldFromParameter(field: name, parameter: "p"), at: at(1))])
    }

    @Test func `a read of a borrowed parameter, and a move out of a local it was copied into, are allowed`() {
        let blocks = [
            BasicBlock(statements: [
                store(read(n, at: 1), in: v), dropping(move(v, at: 2)), printing(read(p, fields: [0], at: 3)),
            ], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [])
    }

    @Test func `a move out of a parameter in a block that no path reaches is reported too`() {
        let blocks = [
            BasicBlock(statements: [], terminator: .return(nil)),
            BasicBlock(statements: [dropping(move(n, at: 1))], terminator: .return(nil)),
        ]
        #expect(errors(in: blocks) == [Diagnostic(.moveFromParameter(name: "n"), at: at(1))])
    }

    @Test func `moves out of parameters are reported in source order, a terminator's among them`() {
        let blocks = [
            BasicBlock(statements: [dropping(move(n, at: 2))], terminator: .return(move(p, at: 1))),
        ]
        let reported = errors(in: blocks)
        #expect(reported.map(\.range.start.offset) == [1, 2])
    }
}

/// The locals of the function each test checks: `n` is a borrowed Int parameter, `p` a borrowed `Shot` parameter,
/// and `v` a `var` that holds an Int.
private let n = 0, p = 1, v = 2

/// The errors the checker reports in a program of one function, made of `blocks`, whose locals are `n`, `p` and `v`.
private func errors(in blocks: [BasicBlock]) -> [Diagnostic] {
    let locals = [
        IRLocal.source(name: "n", kind: .parameter, type: .int),
        .source(name: "p", kind: .parameter, type: .structure(shot)),
        .source(name: "v", kind: .var, type: .int),
    ]
    let function = IRFunction(name: "f()", parameterCount: 2, result: .void, locals: locals, blocks: blocks)
    return ParameterMoveChecker.check(program(of: [function]))
}
