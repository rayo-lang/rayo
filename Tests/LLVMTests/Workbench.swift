import LLVM

/// A context, a module in it and a builder, which a test builds functions with.
struct Workbench: ~Copyable {
    let context = Context()
    let module: Module
    let builder: Builder

    init() {
        module = context.makeModule(named: "workbench")
        builder = context.makeBuilder()
    }

    /// Ends the workbench, handing its module on.
    consuming func takeModule() -> Module {
        module
    }

    var int64: IntegerType<I64> { context.integerType(I64.self) }
    var bool: IntegerType<I1> { context.integerType(I1.self) }

    /// Adds a function named `name` that takes `parameters` and returns `result`, and positions the builder at the
    /// end of its entry block.
    func function(
        named name: String, returning result: some TypeHandle, taking parameters: [any TypeHandle] = [],
    ) -> Function {
        let type = context.functionType(returning: result, taking: parameters)
        let function = module.addFunction(named: name, type: type)
        builder.position(atEndOf: context.appendBlock(named: "entry", to: function))
        return function
    }
}

/// The argument `function` takes at `index`, as an integer of `Width`.
func parameter<Width>(_ index: Int, of function: Function, as width: Width.Type) -> IntValue<Width> {
    // The tests declare each integer parameter they read as one of the width they read it as.
    IntValue<Width>(function.parameter(at: index))!
}
