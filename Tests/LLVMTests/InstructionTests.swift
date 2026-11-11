import LLVM
import Testing

struct InstructionTests {
    @Test func `a function's blocks hold its instructions in order, the last its terminator`() throws {
        let bench = Workbench()
        let function = slotRoundTrip(on: bench)

        let blocks = function.blocks
        #expect(blocks.count == 1)
        #expect(blocks[0].instructions.map(\.opcode) == [.allocate, .store, .load, .return])
        #expect(blocks[0].terminator?.opcode == .return)
    }

    @Test func `a stack slot, a load and a store say how they are aligned, and a slot what it holds`() throws {
        let bench = Workbench()
        let instructions = slotRoundTrip(on: bench).blocks[0].instructions

        #expect(instructions.map(\.alignment) == [8, 8, 4, nil])
        #expect(instructions.map(\.allocatedType) == [bench.int64.anyType, nil, nil, nil])
    }

    @Test func `an instruction's operands are the values it takes`() throws {
        let bench = Workbench()
        let instructions = slotRoundTrip(on: bench).blocks[0].instructions

        // `ret` returns what `load` loads.
        #expect(instructions[3].operand(at: 0) == instructions[2].anyValue)
    }

    @Test func `an integer constant gives its value, and a value that is no constant none`() {
        let bench = Workbench()
        let function = bench.function(named: "f", returning: bench.int64, taking: [bench.int64])

        #expect(bench.int64.constant(-5).constantValue == -5)
        #expect(bench.bool.constant(1).constantValue == -1)
        #expect(parameter(0, of: function, as: I64.self).constantValue == nil)
    }

    @Test func `an undefined value says so, and a constant doesn't`() throws {
        let bench = Workbench()
        let module = try bench.context.parseModule(Array("define i64 @f() {\n  ret i64 undef\n}\n".utf8), named: "m")
        // `#require` can't take a call on the module, which isn't copyable, so it takes the call's result.
        let found = module.function(named: "f")
        let terminator = try #require(found?.blocks.first?.terminator)

        #expect(terminator.operand(at: 0).isUndefined)
        #expect(!bench.int64.constant(0).anyValue.isUndefined)
    }
}

/// Defines `f(i64) -> i64` on `bench`, which stores its parameter in a stack slot aligned to 8, then loads it back
/// aligned to 4 and returns it.
private func slotRoundTrip(on bench: borrowing Workbench) -> Function {
    let function = bench.function(named: "f", returning: bench.int64, taking: [bench.int64])
    let slot = bench.builder.allocate(bench.int64, alignment: 8)
    bench.builder.store(function.parameter(at: 0), to: slot, alignment: 8)
    bench.builder.return(bench.builder.load(bench.int64, from: slot, alignment: 4))
    return function
}
