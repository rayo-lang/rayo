import CLLVM
import LLVM
@testable import RayoLLVM
import RayoSema
import RayoSource
import RayoSyntax

/// A module for the host, into which a debug or a release build's operators are emitted in functions of their own,
/// each operator at `range`. An expression that `define` takes emits its operators by calling the module.
struct OperatorModule: ~Copyable {
    /// The type of the operands of a function's operators.
    enum Operands: Equatable {
        case ints
        /// Bools, which the function takes as the Ints 0 and 1.
        case bools
    }

    /// The source range, in main.rayo, of every operator the module emits.
    static let range = SourceRange(
        SourceLocation(line: 3, column: 7, offset: 20), SourceLocation(line: 3, column: 12, offset: 25),
    )

    private let programModule: ProgramModule
    private let types: LLVMTypes
    /// The operators of the function that `define` is defining.
    private var operators: OperatorEmitter?

    init(for build: Build) throws(LLVMError) {
        programModule = try ProgramModule(for: build)
        types = LLVMTypes(TypeTable(structs: []), in: programModule.emitter.context)
    }

    private var program: ProgramEmitter {
        borrow { programModule.emitter }
    }

    /// The text of the module's IR.
    var llvmIR: String {
        program.module.text
    }

    /// Defines `name(i64, i64) -> i64`, which takes its parameters as the type `operands` names and returns what
    /// `expression` makes of them, a Bool as 0 or 1. Returns the function, and whether it returns a Bool.
    mutating func define(
        _ name: String, on operands: Operands, _ expression: (borrowing OperatorModule, AnyValue, AnyValue) -> AnyValue,
    ) -> (function: Function, givesBool: Bool) {
        // Make the function, and its operators.
        let function = addFunction(name, taking: [types.int64, types.int64])
        operators = OperatorEmitter(into: function, types: types, panic: programModule.runtime.panic)

        // Emit the operators on the parameters, narrowed to Bools where the operands are.
        let parameters = (0..<2).map { narrowed(function.parameter(at: $0), to: operands) }
        let value = expression(self, parameters[0], parameters[1])

        // Return the result, widened to an Int where it is a Bool.
        let givesBool = IntValue<I1>(value) != nil
        let result = givesBool ? AnyValue(LLVMBuildZExt(program.builder.ref, value.ref, types.int64.ref, "")!) : value
        program.builder.return(result)
        return (function, givesBool)
    }

    /// Defines `name() -> i64` to return what `function` returns on `left` and `right`.
    func defineCall(_ name: String, of function: Function, _ left: Int64, _ right: Int64) -> Function {
        let caller = addFunction(name, taking: [])
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

    /// Emits `left op right`.
    func callAsFunction(_ op: BinaryOperator, _ left: AnyValue, _ right: AnyValue) -> AnyValue {
        // Only `define` hands the module to an expression, once it has made the function's operators.
        operators!.emit(op, left, right, at: Self.range, in: program)
    }

    /// Emits `left op right`, where `right` is an Int constant.
    func callAsFunction(_ op: BinaryOperator, _ left: AnyValue, _ right: Int64) -> AnyValue {
        self(op, left, AnyValue(LLVMConstInt(left.type.ref, UInt64(bitPattern: right), 1)))
    }

    /// Emits `op operand`.
    func callAsFunction(_ op: UnaryOperator, _ operand: AnyValue) -> AnyValue {
        // Only `define` hands the module to an expression, once it has made the function's operators.
        operators!.emit(op, on: operand, at: Self.range, in: program)
    }

    /// Adds `name`, returning an Int, and positions the builder at the end of its entry block.
    private func addFunction(_ name: String, taking parameters: [any TypeHandle]) -> Function {
        let type = program.context.functionType(returning: types.int64, taking: parameters)
        let function = program.module.addFunction(named: name, type: type)
        program.builder.position(atEndOf: program.context.appendBlock(named: "entry", to: function))
        return function
    }

    /// `parameter`, an Int, as the type `operands` names.
    private func narrowed(_ parameter: AnyValue, to operands: Operands) -> AnyValue {
        // A Bool is the Int's low bit.
        guard operands == .bools else { return parameter }
        return AnyValue(LLVMBuildTrunc(program.builder.ref, parameter.ref, types.bool.ref, "")!)
    }
}
