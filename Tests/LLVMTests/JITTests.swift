import LLVM
import Testing

struct JITTests {
    @Test func `a function the JIT compiles returns what it computes`() throws {
        let bench = Workbench()
        let add = bench.function(named: "add", returning: bench.int64, taking: [bench.int64, bench.int64])
        let sum = bench.builder.add(parameter(0, of: add, as: I64.self), parameter(1, of: add, as: I64.self))
        bench.builder.return(sum)

        let jit = try JIT()
        try jit.add(bench.takeModule())
        let compiled = unsafeBitCast(try jit.address(of: "add"), to: (@convention(c) (Int64, Int64) -> Int64).self)
        #expect(compiled(40, 2) == 42)
    }

    @Test func `a call of a function the module only declares reaches the definition the JIT is given`() throws {
        // `caller` calls `double`, which the module declares and leaves undefined.
        let bench = Workbench()
        let doubleType = bench.context.functionType(returning: bench.int64, taking: [bench.int64])
        let double = bench.module.addFunction(named: "double", type: doubleType)
        let caller = bench.function(named: "caller", returning: bench.int64, taking: [bench.int64])
        let doubled = bench.builder.call(double, [caller.parameter(at: 0)])
        bench.builder.return(try #require(doubled))

        let jit = try JIT()
        try jit.define("double", at: unsafeBitCast(doubling, to: UnsafeRawPointer.self))
        try jit.add(bench.takeModule())
        let compiled = unsafeBitCast(try jit.address(of: "caller"), to: (@convention(c) (Int64) -> Int64).self)
        #expect(compiled(21) == 42)
    }

    @Test func `a lookup of a name the JIT has no definition of throws, naming it`() throws {
        let jit = try JIT()
        // The expectation can't take the JIT, which isn't copyable, so the lookup's error is caught here.
        do throws(LLVMError) {
            _ = try jit.address(of: "missing")
            Issue.record("the lookup of 'missing' gave an address")
        } catch {
            #expect(error.message.hasPrefix("LLVM couldn't look up 'missing' in the JIT:\n"))
        }
    }
}

/// The definition the JIT is given of a function that doubles an Int.
private let doubling: @convention(c) (Int64) -> Int64 = { $0 * 2 }
