import RayoOwnership
import Testing
import RayoDiagnostics
import RayoIR
import RayoSema

struct MoveCheckerTests {
    @Test func `a move out of a borrowed parameter is reported at the move`() throws {
        let blocks = "bb0:\n  _ = operand move %0 @2:1-2:1 @1:1-1:1\n  return"
        #expect(try checked(withParameters(blocks)).errors == [Diagnostic(.moveFromParameter(name: "n"), at: at(1))])
    }

    @Test(arguments: [
        ("%1.1", "p.hit"),
        ("%1.1.0", "p.hit.damage"),
    ])
    func `a move of a field out of a borrowed parameter is reported with the field's name`(
        field: String, name: String,
    ) throws {
        let blocks = "bb0:\n  _ = operand move \(field) @2:1-2:1 @1:1-1:1\n  return"
        #expect(try checked(withParameters(blocks)).errors == [
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
        #expect(try checked(withParameters(blocks)).errors == [])
    }

    @Test func `a move out of a parameter in a block that no path reaches is reported too`() throws {
        let blocks = """
            bb0:
              return
            bb1:
              _ = operand move %0 @2:1-2:1 @1:1-1:1
              return
            """
        #expect(try checked(withParameters(blocks)).errors == [Diagnostic(.moveFromParameter(name: "n"), at: at(1))])
    }

    @Test func `moves out of parameters are reported in source order, a terminator's among them`() throws {
        let blocks = """
            bb0:
              _ = operand move %0 @2:2-2:2 @1:1-1:1
              return move %1 @2:1-2:1
            """
        let reported = try checked(withParameters(blocks, result: "Shot")).errors
        #expect(reported.map(\.range.start.column) == [1, 2])
    }

    @Test(arguments: ["%3[1]", "%3[%4]", "%3[0].0"])
    func `a move out of an array's element, or out of a part of one, is reported at the move`(place: String) throws {
        let blocks = "bb0:\n  _ = operand move \(place) @2:1-2:1 @1:1-1:1\n  return"
        #expect(try checked(withParameters(blocks)).errors == [Diagnostic(.moveFromElement, at: at(1))])
    }

    @Test func `a read of an element, and a move of the whole array, are allowed`() throws {
        let blocks = """
            bb0:
              %3 @1:1-1:1 = fill 2 of read %1.1 @1:1-1:1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %3[0].0 @2:1-2:1) @1:1-1:1
              _ = operand move %3 @2:2-2:2 @1:1-1:1
              return
            """
        #expect(try checked(withParameters(blocks)).errors == [])
    }
}

/// The function `f(_: Int, _: Shot)`, made of `blocks`, which returns `result`, and whose locals are `n` (`%0`), a
/// borrowed Int parameter, `p` (`%1`), a borrowed `Shot` parameter, `v` (`%2`), a `var` that holds an Int, `a` (`%3`),
/// a `var` that holds two `Hit`s, and a UInt temporary (`%4`).
private func withParameters(_ blocks: String, result: String = "Void") -> (name: String, text: String) {
    let text = """
        func "f(_: Int, _: Shot)"(Int, Shot) -> \(result) {
          param %0 n: Int
          param %1 p: Shot
          var %2 v: Int
          var %3 a: [2 of Hit]
          temp %4: UInt
        \(blocks)
        }
        """
    return ("f(_: Int, _: Shot)", text)
}
