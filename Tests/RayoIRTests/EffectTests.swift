import RayoCheckedProgram
@testable import RayoIR
import RayoSource
import Testing

/// Statements or a terminator in IR text, and the effects the last of them has, each as `effectText(_:)` writes it.
struct EffectsOfText: CustomTestStringConvertible, Sendable {
    let testDescription: String
    let text: String
    let effects: [String]
}

@Suite("What each statement and terminator does to places")
struct EffectTests {
    @Test(arguments: statementEffects)
    func `a statement's effects are what it does, in the order it does them`(statement: EffectsOfText) throws {
        let body = try mainBody(from: """
            bb0:
            \(statement.text)
              return
            """)
        let last = try #require(body.blocks[0].statements.last)
        #expect(last.effects.map(effectText) == statement.effects)
    }

    @Test(arguments: terminatorEffects)
    func `a terminator's effects are what it does, in the order it does them`(terminator: EffectsOfText) throws {
        let body = try mainBody(from: """
            bb0:
            \(terminator.text)
            bb1:
              return
            """)
        #expect(body.blocks[0].terminator.effects.map(effectText) == terminator.effects)
    }

    @Test func `a block's effects are each statement's, then the terminator's`() throws {
        let body = try mainBody(from: """
            bb0:
              declare %0
              %0 @1:1-1:2 = operand 1 @1:3-1:4
              return
            """)
        let effects = BodyEffects(body)[BlockID(index: 0)]
        #expect(effects.map { $0.map(effectText) } == [["declare %0"], ["store %0 @1:1-1:2"], ["exit"]])
    }

    @Test func `a body's effects give each block its own, including a statement or jump with none`() throws {
        let body = try mainBody(from: """
            bb0:
              declare %0
              goto bb1
            bb1:
              _ = operand 1 @1:1-1:2
              %0 @1:1-1:2 = operand read %0 @1:3-1:4 @1:3-1:4
              goto bb2
            bb2:
              return
            """)
        let effects = BodyEffects(body)
        #expect(effects[BlockID(index: 0)].map { $0.map(effectText) } == [["declare %0"], []])
        #expect(effects[BlockID(index: 1)].map { $0.map(effectText) } == [
            [], ["read %0 @1:3-1:4", "store %0 @1:1-1:2"], [],
        ])
        #expect(effects[BlockID(index: 2)].map { $0.map(effectText) } == [["exit"]])
    }

    @Test func `a body's effects fit it, and not the body with a statement written in`() throws {
        var body = try mainBody(from: """
            bb0:
              declare %0
              return
            """)
        let effects = BodyEffects(body)
        #expect(effects.fit(body))
        body.blocks[0].statements.append(.retire(LocalID(index: 0)))
        #expect(!effects.fit(body))
    }

    @Test func `all of a block's effects are each statement's in turn, then the terminator's`() throws {
        let body = try mainBody(from: """
            bb0:
              goto bb1
            bb1:
              declare %0
              %0 @1:1-1:2 = operand read %0 @1:3-1:4 @1:3-1:4
              return move %0 @2:1-2:2
            """)
        let effects = BodyEffects(body)
        #expect(effects[BlockID(index: 0)].all.isEmpty)
        #expect(effects[BlockID(index: 1)].all.map(effectText) == [
            "declare %0", "read %0 @1:3-1:4", "store %0 @1:1-1:2", "move %0 @2:1-2:2", "exit",
        ])
    }

    @Test func `a walk of a block's effects takes each statement's in turn, then the terminator's`() throws {
        let body = try mainBody(from: """
            bb0:
              %2[%1] @1:1-1:6 = operand read %0 @1:9-1:10 @1:9-1:10
              begin a0 modify %0 @2:1-2:2
              _ = call "bump(_: mutable &Int, _: Int)"(a0, 1) @2:1-2:7
              end a0
              return move %0 @3:1-3:2
            """)
        var walked: [String] = []
        body.blocks[0].forEachEffect { walked.append(effectText($0)) }
        #expect(walked == [
            "read %0 @1:9-1:10", "read %1 @1:1-1:6", "store %2[%1] @1:1-1:6", "begin a0 modify %0", "use a0", "end a0",
            "move %0 @3:1-3:2", "exit",
        ])
    }

    @Test func `a walk of a block's effects stops at the effect its visit throws at`() throws {
        let body = try mainBody(from: """
            bb0:
              declare %0
              %2[%1] @1:1-1:6 = operand read %0 @1:9-1:10 @1:9-1:10
              retire %0
              return
            """)
        var walked: [String] = []
        #expect(throws: StoppedWalk.self) {
            try body.blocks[0].forEachEffect { effect throws(StoppedWalk) in
                walked.append(effectText(effect))
                if case .read = effect { throw StoppedWalk() }
            }
        }
        #expect(walked == ["declare %0", "read %0 @1:9-1:10"])
    }
}

/// What a visit throws to stop a walk of effects.
private struct StoppedWalk: Error {}

private let statementEffects = [
    EffectsOfText(
        testDescription: "a computation reads and moves its operands in order, then stores its value",
        text: "  %0 @1:1-1:2 = add checked read %0 @1:3-1:4, move %0 @1:5-1:6 @1:1-1:6",
        effects: ["read %0 @1:3-1:4", "move %0 @1:5-1:6", "store %0 @1:1-1:2"],
    ),
    EffectsOfText(
        testDescription: "a computation that drops its value stores nothing",
        text: "  _ = operand read %0 @1:3-1:4 @1:1-1:4",
        effects: ["read %0 @1:3-1:4"],
    ),
    EffectsOfText(
        testDescription: "an operand at an index a local holds reads that local first, where the source names it",
        text: "  _ = operand read %2[%1] @1:3-1:8 @1:1-1:8",
        effects: ["read %1 @1:3-1:8", "read %2[%1] @1:3-1:8"],
    ),
    EffectsOfText(
        testDescription: "a store at an index a local holds reads that local after the operands, then stores",
        text: "  %2[%1] @1:1-1:6 = operand read %0 @1:9-1:10 @1:9-1:10",
        effects: ["read %0 @1:9-1:10", "read %1 @1:1-1:6", "store %2[%1] @1:1-1:6"],
    ),
    EffectsOfText(
        testDescription: "a call uses the accesses it passes after it reads its operands, in any order of arguments",
        text: """
              begin a0 modify %0 @1:1-1:2
              _ = call "bump(_: mutable &Int, _: Int)"(a0, read %0 @1:5-1:6) @1:1-1:7
            """,
        effects: ["read %0 @1:5-1:6", "use a0"],
    ),
    EffectsOfText(
        testDescription: "an access to a place at an index a local holds reads that local, then begins",
        text: "  begin a0 read %2[%1] @1:1-1:6",
        effects: ["read %1 @1:1-1:6", "begin a0 read %2[%1]"],
    ),
    EffectsOfText(
        testDescription: "an access's end ends it",
        text: """
              begin a0 read %0 @1:1-1:2
              end a0
            """,
        effects: ["end a0"],
    ),
    EffectsOfText(
        testDescription: "a dependence makes the value at its place depend on its access, and reads nothing",
        text: """
              begin a0 read %0 @1:1-1:2
              depend %2[%1] on a0
            """,
        effects: ["depend %2[%1] on a0"],
    ),
    EffectsOfText(testDescription: "a declaration declares its local", text: "  declare %0", effects: ["declare %0"]),
    EffectsOfText(testDescription: "a retirement retires its local", text: "  retire %0", effects: ["retire %0"]),
]

private let terminatorEffects = [
    EffectsOfText(testDescription: "a jump does nothing to places", text: "  goto bb1", effects: []),
    EffectsOfText(
        testDescription: "a branch reads its condition",
        text: "  branch read %3 @1:1-1:2, bb1, bb1",
        effects: ["read %3 @1:1-1:2"],
    ),
    EffectsOfText(
        testDescription: "a return reads or moves its result, then leaves the function",
        text: "  return move %0 @1:1-1:2",
        effects: ["move %0 @1:1-1:2", "exit"],
    ),
    EffectsOfText(
        testDescription: "a return without a result leaves the function",
        text: "  return",
        effects: ["exit"],
    ),
    EffectsOfText(testDescription: "a block no path reaches does nothing", text: "  unreachable", effects: []),
]

/// The body of `main` in a program whose `main` has an Int `%0`, a UInt `%1`, an array `%2` of two Ints and a Bool
/// `%3`, and is made of `blocks`, and whose `bump` takes a mutable Int and an owned one.
private func mainBody(from blocks: String) throws -> IRBody {
    let program = try IRParser.program(from: """
        main "main()"

        func "main()"() -> Void {
          temp %0: Int
          temp %1: UInt
          temp %2: [2 of Int]
          temp %3: Bool
        \(blocks)
        }

        func "bump(_: mutable &Int, _: Int)"(_: mutable &Int, _: Int) -> Void {
          param %0 a: mutable &Int @1:1-1:2
          param %1 b: Int @1:3-1:4
        bb0:
          return
        }
        """)
    return try #require(program.bodies[FunctionID(index: 0)])
}

/// `effect` as a test writes it: what it does, then the place, local or access it does it to, and, for a read, a move
/// or a store, where the source names the place, as in `read %2[%1] @1:3-1:8`.
private func effectText(_ effect: Effect) -> String {
    switch effect {
    case .read(let place, let range): "read \(placeText(place)) \(rangeText(range))"
    case .move(let place, let range): "move \(placeText(place)) \(rangeText(range))"
    case .store(let destination): "store \(placeText(destination.place)) \(rangeText(destination.range))"
    case .begin(let id, let access): "begin a\(id.index) \(access.kind.rawValue) \(placeText(access.place))"
    case .use(let id): "use a\(id.index)"
    case .end(let id): "end a\(id.index)"
    case .depend(let place, let id): "depend \(placeText(place)) on a\(id.index)"
    case .declare(let local): "declare %\(local.index)"
    case .retire(let local): "retire %\(local.index)"
    case .exit: "exit"
    }
}

/// `place` as the IR's text writes it, such as `%1.0[%4]`.
private func placeText(_ place: Place) -> String {
    let steps = place.steps.map { step in
        switch step {
        case .field(let index): ".\(index)"
        case .element(let index): "[\(index)]"
        case .elementAt(let local): "[%\(local.index)]"
        }
    }
    return "%\(place.root.index)" + steps.joined()
}

/// `range` as the IR's text writes it, such as `@1:3-1:8`.
private func rangeText(_ range: SourceRange) -> String {
    "@\(range.start.line):\(range.start.column)-\(range.end.line):\(range.end.column)"
}
