import Testing
import RayoDiagnostics
import RayoIR
import RayoOwnership
import RayoSema

struct MoveCheckerTests {
    @Test func `a move out of a borrowed parameter is reported at the move`() throws {
        let blocks = "bb0:\n  _ = operand move %0 @2:1-2:1 @1:1-1:1\n  return"
        #expect(try errors(in: blocks) == [Diagnostic(.moveFromParameter(name: "n"), at: at(1))])
    }

    @Test(arguments: [
        ("%1.1", "p.hit"),
        ("%1.1.0", "p.hit.damage"),
    ])
    func `a move of a field out of a borrowed parameter is reported with the field's name`(
        field: String, name: String,
    ) throws {
        let blocks = "bb0:\n  _ = operand move \(field) @2:1-2:1 @1:1-1:1\n  return"
        #expect(try errors(in: blocks) == [
            Diagnostic(.moveFieldFromParameter(field: name, parameter: "p"), at: at(1)),
        ])
    }

    @Test func `a read of a borrowed parameter, and a move out of a local it was copied into, are allowed`() throws {
        let blocks = """
            bb0:
              %2 @1:1-1:1 = operand read %0 @2:1-2:1 @1:1-1:1
              _ = operand move %2 @2:2-2:2 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %1.0 @2:3-2:3) @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [])
    }

    @Test func `a move out of a parameter in a block that no path reaches is reported too`() throws {
        let blocks = """
            bb0:
              return
            bb1:
              _ = operand move %0 @2:1-2:1 @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [Diagnostic(.moveFromParameter(name: "n"), at: at(1))])
    }

    @Test func `moves out of parameters are reported in source order, a terminator's among them`() throws {
        let blocks = """
            bb0:
              _ = operand move %0 @2:2-2:2 @1:1-1:1
              return move %1 @2:1-2:1
            """
        let reported = try errors(in: blocks, result: "Shot")
        #expect(reported.map(\.range.start.column) == [1, 2])
    }

    @Test(arguments: ["%3[1]", "%3[%4]", "%3[0].0"])
    func `a move out of an array's element, or out of a part of one, is reported at the move`(place: String) throws {
        let blocks = "bb0:\n  _ = operand move \(place) @2:1-2:1 @1:1-1:1\n  return"
        #expect(try errors(in: blocks) == [Diagnostic(.moveFromElement, at: at(1))])
    }

    @Test func `a read of an element, and a move of the whole array, are allowed`() throws {
        let blocks = """
            bb0:
              _ = call builtin "print(_: Int)"(read %3[0].0 @2:1-2:1) @1:1-1:1
              _ = operand move %3 @2:2-2:2 @1:1-1:1
              return
            """
        #expect(try errors(in: blocks) == [])
    }
}

/// The errors the checker reports in a program of one function, which returns `result` and is made of `blocks`, and
/// whose locals are `n` (`%0`), a borrowed Int parameter, `p` (`%1`), a borrowed `Shot` parameter, `v` (`%2`), a
/// `var` that holds an Int, `a` (`%3`), a `var` that holds two `Hit`s, and a UInt temporary (`%4`).
private func errors(in blocks: String, result: String = "Void") throws -> [Diagnostic] {
    let function = """
        func "f(_: Int, _: Shot)"(Int, Shot) -> \(result) {
          param %0 n: Int
          param %1 p: Shot
          var %2 v: Int
          var %3 a: [2 of Hit]
          temp %4: UInt
        \(blocks)
        }
        """
    return MoveChecker.check(try program(of: [("f(_: Int, _: Shot)", function)]))[FunctionID(index: 0)] ?? []
}
