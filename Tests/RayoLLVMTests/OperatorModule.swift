import LLVM
@testable import RayoLLVM
import RayoIR
import RayoSema
import RayoSource

/// A module for the host, into which a debug or a release build's operators are emitted in functions of their own,
/// each operator at `range`. An expression that `define` takes emits its operators by calling the module.
struct OperatorModule: ~Copyable {
    /// The type of the operands of a function's operators.
    enum Operands: Equatable {
        case ints
        /// UInts, which the function takes as the Ints of their bits.
        case uints
        /// Bools, which the function takes as the Ints 0 and 1.
        case bools
    }

    /// The source range, in main.rayo, of every operator the module emits.
    static let range = SourceRange(
        SourceLocation(line: 3, column: 7, offset: 20), SourceLocation(line: 3, column: 12, offset: 25),
    )

    private let programModule: ProgramModule
    private let types: LLVMTypes
    /// The operators of the function that `define` is defining. Only `define` hands the module to an expression, once
    /// it has made them.
    private var operators: OperatorEmitter?
    /// The type of the integers the function that `define` is defining computes on.
    private var integerType = RayoType.int

    init(for build: Build) throws(LLVMError) {
        programModule = try ProgramModule(for: build)
        types = LLVMTypes(TypeTable(structs: []), in: programModule.emitter.context)
    }

    private var program: ProgramEmitter {
        borrow { programModule.emitter }
    }

    /// Ends the module, handing on the LLVM module it emitted into.
    consuming func takeModule() -> Module {
        programModule.takeModule()
    }

    /// Defines `name(i64, i64) -> i64`, which takes its parameters as the type `operands` names and returns what
    /// `expression` makes of them, a Bool as 0 or 1. Returns the function, and whether it returns a Bool, or rethrows
    /// what `expression` throws.
    mutating func define(
        _ name: String, on operands: Operands,
        _ expression: (borrowing OperatorModule, AnyValue, AnyValue) throws -> AnyValue,
    ) rethrows -> (function: Function, givesBool: Bool) {
        // Make the function, and its operators.
        let function = beginFunction(name, taking: [types.int64, types.int64])
        operators = OperatorEmitter(into: function, types: types)
        integerType = operands == .uints ? .uint : .int

        // Emit the operators on the parameters, narrowed to Bools where the operands are. The function takes Ints, so
        // each parameter is one.
        let ints = (0..<2).map { IntValue<I64>(function.parameter(at: $0))! }
        let parameters = ints.map { narrowed($0, to: operands) }
        let value = try expression(self, parameters[0], parameters[1])

        // Return the result, widened to an Int where it is a Bool.
        let boolResult = IntValue<I1>(value)
        let result = if let boolResult { widened(boolResult) } else { value }
        program.builder.return(result)
        return (function, boolResult != nil)
    }

    /// Defines `name() -> i64` to return what `function` returns on `left` and `right`.
    func defineCall(_ name: String, of function: Function, _ left: Int64, _ right: Int64) -> Function {
        let caller = beginFunction(name, taking: [])
        // Every operator gives a value, so the call does too.
        let result = program.builder.call(function, [types.int64.constant(left), types.int64.constant(right)])!
        program.builder.return(result)
        return caller
    }

    /// Readies the module to run as the compiler readies a program's for the build, exporting the functions
    /// `exported` names where the compiler would export only the program's entry point. The runtime is left out, so
    /// that the stand-in for its panic catches a panic.
    func ready(exporting exported: Set<String>) throws {
        try LLVMEmitter.ready(program.module, for: programModule.target, exporting: exported)
    }

    /// Emits `left op right`, on two integers of the function's integer type or two Bools.
    func callAsFunction(_ op: IRBinaryOperator, _ left: AnyValue, _ right: AnyValue) throws(LLVMError) -> AnyValue {
        try operators!.emit(op, left, right, of: type(of: left), at: Self.range, in: program)
    }

    /// Emits `left op right`, where `right` is a constant of the function's integer type, given by its bits.
    func callAsFunction(_ op: IRBinaryOperator, _ left: AnyValue, _ right: Int64) throws(LLVMError) -> AnyValue {
        try self(op, left, types.int64.constant(right).anyValue)
    }

    /// Emits `op operand`, on an integer of the function's integer type or a Bool.
    func callAsFunction(_ op: IRUnaryOperator, _ operand: AnyValue) throws(LLVMError) -> AnyValue {
        try operators!.emit(op, on: operand, of: type(of: operand), at: Self.range, in: program)
    }

    /// Emits the conversion of `value`, an integer of the function's integer type, to the other integer type.
    func convert(_ value: AnyValue) throws(LLVMError) -> AnyValue {
        try operators!.emitConversion(of: value, at: Self.range, in: program)
    }

    /// The Rayo type of `value`, an integer of the function's integer type or a Bool.
    private func type(of value: AnyValue) -> RayoType {
        IntValue<I1>(value) == nil ? integerType : .bool
    }

    /// Adds `name`, returning an Int, and positions the builder at the end of its entry block.
    private func beginFunction(_ name: String, taking parameters: [any TypeHandle]) -> Function {
        let type = program.context.functionType(returning: types.int64, taking: parameters)
        let function = program.module.addFunction(named: name, type: type)
        program.builder.position(atEndOf: program.context.appendBlock(named: "entry", to: function))
        return function
    }

    /// `parameter`, an Int, as the type `operands` names.
    private func narrowed(_ parameter: IntValue<I64>, to operands: Operands) -> AnyValue {
        // A Bool is the Int's low bit.
        guard operands == .bools else { return parameter.anyValue }
        return program.builder.truncate(parameter, to: types.bool).anyValue
    }

    /// `value`, a Bool, as the Int 0 or 1.
    private func widened(_ value: IntValue<I1>) -> AnyValue {
        program.builder.zeroExtend(value, to: types.int64).anyValue
    }
}
