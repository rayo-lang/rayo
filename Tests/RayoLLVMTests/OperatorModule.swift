import CLLVM
@testable import RayoLLVM

/// A module for the host, into which a debug or a release build's operators are emitted in functions of their own.
struct OperatorModule {
    /// How a build emits its operators, and whether it optimises them.
    enum Build: Equatable {
        /// A debug build's: overflow panics, and the module isn't optimised.
        case debug
        /// A release build's: overflow wraps, and the module is optimised as the compiler optimises a program's.
        /// Only the runtime is left out, so that the stand-in for its panic catches a panic.
        case release
    }

    /// The type of the operands of a function's operators.
    enum Operands: Equatable {
        case ints
        /// Bools, which the function takes as the Ints 0 and 1.
        case bools
    }

    private let module: ModuleBuilder
    private let program: ProgramEmitter
    private let target: TargetMachine

    init(for build: Build) throws {
        target = try TargetMachine(optimizes: build == .release)
        module = ModuleBuilder(named: "main.rayo", for: target)
        program = ProgramEmitter(module: module, runtime: try Runtime(in: module), sourcePath: "main.rayo",
                                 checksOverflow: build == .debug)
    }

    /// The text of the module's IR.
    var llvmIR: String {
        takeMessage(LLVMPrintModuleToString(module.module))
    }

    /// Defines `name(i64, i64) -> i64`, which takes its parameters as the type `operands` names and returns what
    /// `expression` makes of them, a Bool as 0 or 1. Returns the function, and whether it returns a Bool.
    func define(_ name: String, on operands: Operands,
                _ expression: (ExpressionEmitter, LLVMValueRef, LLVMValueRef) -> LLVMValueRef)
        -> (function: FunctionValue, givesBool: Bool) {
        // Make the function, and build from its entry block.
        let function = module.addFunction(name, taking: [module.int64, module.int64], returning: module.int64)
        LLVMPositionBuilderAtEnd(module.builder, module.appendBlock(to: function.value, named: "entry"))

        // Emit the operators on the parameters, narrowed to Bools where the operands are.
        let parameters = (0..<2).map { index in
            let parameter = LLVMGetParam(function.value, UInt32(index))!
            return operands == .bools ? LLVMBuildTrunc(module.builder, parameter, module.bool, "")! : parameter
        }
        let operators = OperatorEmitter(program: program, into: function.value)
        let value = expression(ExpressionEmitter(operators: operators), parameters[0], parameters[1])

        // Return the result, widened to an Int where it is a Bool.
        let givesBool = LLVMTypeOf(value) == module.bool
        let result = givesBool ? LLVMBuildZExt(module.builder, value, module.int64, "")! : value
        LLVMBuildRet(module.builder, result)
        return (function, givesBool)
    }

    /// Defines `name() -> i64` to return what `function` returns on `left` and `right`.
    func defineCall(_ name: String, of function: FunctionValue, _ left: Int64, _ right: Int64) -> FunctionValue {
        let caller = module.addFunction(name, taking: [], returning: module.int64)
        LLVMPositionBuilderAtEnd(module.builder, module.appendBlock(to: caller.value, named: "entry"))
        LLVMBuildRet(module.builder, module.call(function, [module.constant(left), module.constant(right)]))
        return caller
    }

    /// Readies the module to run as the compiler readies a program's for the build, exporting the functions
    /// `exported` names where the compiler would export only the program's entry point.
    func ready(exporting exported: Set<String>) throws {
        try target.ready(module, exporting: exported)
    }
}
