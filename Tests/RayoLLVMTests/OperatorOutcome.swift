import LLVM
@testable import RayoLLVM
import RayoIR

/// What an operator came to when its emitted code ran: the value it gave, or the message of the panic it reported.
enum OperatorOutcome: Equatable {
    case int(Int64)
    case uint(UInt64)
    case bool(Bool)
    case panic(String)

    /// The panic that an operator at line 3, column 7 of main.rayo, where `OperatorModule.range` starts,
    /// reports for `reason`.
    static func panics(_ reason: String) -> OperatorOutcome {
        .panic("main.rayo:3:7: panic: \(reason)\n")
    }
}

/// What `left op right` comes to on two Ints, emitted as `build` does, and run in this process.
func outcome(of op: IRBinaryOperator, _ left: Int64, _ right: Int64, in build: Build) throws -> OperatorOutcome {
    try outcome(left, right, on: .ints, in: build) { emit, a, b in try emit(op, a, b) }
}

/// What `left op right` comes to on two Bools, run in this process.
func outcome(of op: IRBinaryOperator, _ left: Bool, _ right: Bool) throws -> OperatorOutcome {
    try outcome(left ? 1 : 0, right ? 1 : 0, on: .bools, in: .debug) { emit, a, b in try emit(op, a, b) }
}

/// What `left op right` comes to on two UInts, emitted as `build` does, and run in this process.
func unsignedOutcome(of op: IRBinaryOperator, _ left: UInt64, _ right: UInt64,
                     in build: Build) throws -> OperatorOutcome {
    try outcome(Int64(bitPattern: left), Int64(bitPattern: right), on: .uints, in: build) { emit, a, b in
        try emit(op, a, b)
    }
}

/// What `op operand` comes to on a UInt, emitted as `build` does, and run in this process.
func unsignedOutcome(of op: IRUnaryOperator, _ operand: UInt64, in build: Build) throws -> OperatorOutcome {
    try outcome(Int64(bitPattern: operand), 0, on: .uints, in: build) { emit, a, _ in try emit(op, a) }
}

/// What converting `value`, an integer of the type `operands` names, to the other integer type comes to, emitted as
/// `build` does, and run in this process. The outcome gives the converted value's bits as the type converted from.
func conversionOutcome(of value: Int64, from operands: OperatorModule.Operands,
                       in build: Build) throws -> OperatorOutcome {
    try outcome(value, 0, on: operands, in: build) { emit, a, _ in try emit.convert(a) }
}

/// What `op operand` comes to on an Int, emitted as `build` does, and run in this process.
func outcome(of op: IRUnaryOperator, _ operand: Int64, in build: Build) throws -> OperatorOutcome {
    try outcome(operand, 0, on: .ints, in: build) { emit, a, _ in try emit(op, a) }
}

/// What `op operand` comes to on a Bool, run in this process.
func outcome(of op: IRUnaryOperator, _ operand: Bool) throws -> OperatorOutcome {
    try outcome(operand ? 1 : 0, 0, on: .bools, in: .debug) { emit, a, _ in try emit(op, a) }
}

/// What `expression` comes to on an Int in a release build: emitted where overflow isn't checked, optimised as a
/// release build is, and run on `operand` in this process.
func releaseOutcome(
    of operand: Int64,
    _ expression: (borrowing OperatorModule, AnyValue) throws -> AnyValue,
) throws -> OperatorOutcome {
    try outcome(operand, 0, on: .ints, in: .release) { emit, a, _ in try expression(emit, a) }
}

/// Emits a function of two operands, as `build` does, whose result is the value `expression` makes of them, and
/// runs it on `left` and `right` in this process.
private func outcome(
    _ left: Int64, _ right: Int64, on operands: OperatorModule.Operands, in build: Build,
    _ expression: (borrowing OperatorModule, AnyValue, AnyValue) throws -> AnyValue,
) throws -> OperatorOutcome {
    // Emit `f`, and ready the module as the build does.
    var module = try OperatorModule(for: build)
    let (_, givesBool) = try module.define("f", on: operands, expression)
    try module.ready(exporting: ["f"])

    // Run `f` in this process, and read what it came to as the type it gave.
    let jit = try InProcessJIT(running: module.takeModule())
    return switch try jit.call("f", left, right) {
    case .returned(let value) where givesBool: .bool(value != 0)
    case .returned(let value) where operands == .uints: .uint(UInt64(bitPattern: value))
    case .returned(let value): .int(value)
    case .panicked(let message): .panic(message)
    }
}
