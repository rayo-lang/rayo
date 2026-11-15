import LLVM
@testable import RayoLLVM
import RayoLLVMTestSupport

/// A module run in this process, with a call to the runtime's `rayo.panic` ending the call that reached it instead of
/// the process, and each call to one of the runtime's print functions adding to the call's output instead of printing.
struct InProcessJIT: ~Copyable {
    /// What a call came to: the value it returned, or the message of the panic that ended it.
    enum Call {
        case returned(Int64)
        case panicked(String)
    }

    /// What a run of a program came to: the text it printed, and the message of the panic that ended it, if one did.
    struct Run: Equatable {
        var printed: String
        var panic: String?
    }

    private let jit: JIT

    /// Takes `module`, which leaves the runtime's functions undefined.
    init(running module: consuming Module) throws(LLVMError) {
        // Run `module` in a JIT where `rayo.panic` is the stand-in that ends a call with its message, and each print
        // function is the stand-in that adds to the call's output.
        let jit = try JIT()
        try jit.define(RuntimeFunction.panic.symbol, at: rayo_test_panic_address())
        try jit.define(RuntimeFunction.print(.int).symbol, at: rayo_test_print_int_address())
        try jit.define(RuntimeFunction.print(.uint).symbol, at: rayo_test_print_uint_address())
        try jit.define(RuntimeFunction.print(.bool).symbol, at: rayo_test_print_bool_address())
        try jit.add(module)
        self.jit = jit
    }

    /// Runs the function `name`, of type `(i64, i64) -> i64`, on `left` and `right`.
    func call(_ name: String, _ left: Int64, _ right: Int64) throws(LLVMError) -> Call {
        // Compile the function, and call it where a panic ends the call.
        let function = unsafeBitCast(try jit.address(of: name), to: (@convention(c) (Int64, Int64) -> Int64).self)
        let outcome = rayo_call_catching_panic(function, left, right)

        // A call that returned comes to its value.
        guard outcome.panicked else { return .returned(outcome.value) }
        return .panicked(Self.message(of: outcome))
    }

    /// Runs the program's entry function, `rayo.main`, which takes and returns nothing.
    func runMain() throws(LLVMError) -> Run {
        // Compile the entry function, and call it where a panic ends the call.
        let outcome = rayo_run_catching_panic(try mainFunction())
        return Self.run(from: outcome)
    }

    /// Runs the program's entry function as `runMain()` does, on a thread of its own, and gives the bytes of that
    /// thread's stack the run used, or 0 where it panicked.
    func runMainMeasuringStack() throws(LLVMError) -> (run: Run, stackBytes: Int) {
        var stackBytes = 0
        let outcome = rayo_run_measuring_stack(try mainFunction(), &stackBytes)
        return (Self.run(from: outcome), stackBytes)
    }

    /// The program's entry function, `rayo.main`, compiled.
    private func mainFunction() throws(LLVMError) -> @convention(c) () -> Void {
        unsafeBitCast(try jit.address(of: RuntimeFunction.main.symbol), to: (@convention(c) () -> Void).self)
    }

    /// What the run of a program's entry function that `outcome` records came to.
    private static func run(from outcome: RayoCaughtCall) -> Run {
        // The output is a fixed buffer, of which the run filled only the start.
        let printed = withUnsafeBytes(of: outcome.output) { output in
            String(decoding: output.prefix(Int(outcome.outputLength)), as: UTF8.self)
        }
        return Run(printed: printed, panic: outcome.panicked ? message(of: outcome) : nil)
    }

    /// The message of the panic that ended the call `outcome` records.
    private static func message(of outcome: RayoCaughtCall) -> String {
        // A panic's message lives in the JIT's memory, so it is copied out while the JIT still holds it.
        let message = UnsafeRawBufferPointer(start: outcome.message, count: Int(outcome.length))
        return String(decoding: message, as: UTF8.self)
    }
}
