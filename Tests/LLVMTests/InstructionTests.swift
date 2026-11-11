import LLVM
import Testing

struct InstructionTests {
    @Test func `a function's blocks hold its instructions in order, the last its terminator`() throws {
        let bench = Workbench()
        let blocks = slotRoundTrip(on: bench).blocks

        try #require(blocks.count == 1)
        #expect(blocks[0].instructions.map(\.opcode) == [.allocate, .store, .load, .return])
        #expect(blocks[0].terminator?.opcode == .return)
    }

    @Test func `a block that nothing ends yet has no terminator, and a declared function no blocks`() throws {
        let bench = Workbench()
        let function = bench.function(named: "f", returning: bench.int64)
        let declared = bench.module.addFunction(named: "g", type: function.type)

        let entry = try #require(function.blocks.first)
        #expect(entry.terminator == nil)
        #expect(declared.blocks.isEmpty)
    }

    @Test func `a stack slot, a load and a store say how they are aligned, and a slot what it holds`() throws {
        let bench = Workbench()
        let block = try #require(slotRoundTrip(on: bench).blocks.first)

        #expect(block.instructions.map(\.alignment) == [8, 8, 4, nil])
        #expect(block.instructions.map(\.allocatedType) == [bench.int64.anyType, nil, nil, nil])
    }

    @Test func `an instruction's operands are the values it takes`() throws {
        let bench = Workbench()
        let instructions = try #require(slotRoundTrip(on: bench).blocks.first).instructions

        try #require(instructions.count == 4)
        // `ret` returns what `load` loads.
        #expect(instructions[3].operand(at: 0) == instructions[2].anyValue)
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
