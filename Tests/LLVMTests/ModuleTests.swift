import LLVM
import Testing

struct ModuleTests {
    @Test func `a module that fails to verify throws LLVM's report of what is wrong with it`() {
        let bench = Workbench()
        // An entry block with no terminator.
        _ = bench.function(named: "f", returning: bench.context.voidType)

        #expect(throws: LLVMError(message: """
            LLVM rejected the module it was given:
            Basic Block in function 'f' does not have terminator!
            label %entry

            """)) {
            try bench.module.verify()
        }
    }

    @Test func `a parsed module links into another, which then defines its functions`() throws {
        let bench = Workbench()
        let parsed = try bench.context.parseModule(Array("define i64 @answer() {\n  ret i64 42\n}\n".utf8),
                                                   named: "answer.ll")
        try bench.module.link(parsed)

        let found = bench.module.function(named: "answer")
        let answer = try #require(found)
        #expect(!answer.isDeclaration)
        #expect(bench.module.functions.map(\.name) == ["answer"])
    }

    @Test func `text that isn't LLVM IR throws LLVM's report of it, naming the text`() {
        let bench = Workbench()
        #expect {
            _ = try bench.context.parseModule(Array("define".utf8), named: "broken.ll")
        } throws: { error in
            (error as? LLVMError)?.message.hasPrefix("LLVM couldn't parse broken.ll:\n") == true
        }
    }

    @Test func `modules that both define a function fail to link, with the error LLVM reports`() throws {
        let bench = Workbench()
        _ = bench.function(named: "twice", returning: bench.context.voidType)
        bench.builder.returnVoid()
        let other = try bench.context.parseModule(Array("define void @twice() {\n  ret void\n}\n".utf8),
                                                  named: "other.ll")

        // The link consumes `other`, which a closure of `#expect(throws:)` can't.
        var thrown: LLVMError?
        do { try bench.module.link(other) } catch { thrown = error }
        #expect(thrown == LLVMError(message: """
            LLVM couldn't link other.ll into workbench:
            Linking globals named 'twice': symbol multiply defined!
            """))
        #expect(bench.context.reportedErrors == ["Linking globals named 'twice': symbol multiply defined!"])
    }

    @Test func `a global holds its initializer, made constant, unnamed and linked as it is told`() throws {
        let bench = Workbench()
        let bytes = bench.context.constant(bytes: Array("hi".utf8))
        let message = bench.module.addGlobal(named: "message", initializer: bytes)
        message.isConstant = true
        message.hasUnnamedAddress = true
        message.setLinkage(.private)

        try bench.module.verify()
        #expect(bench.module.globals.map(\.name) == ["message"])
        #expect(bench.module.text.contains("@message = private unnamed_addr constant [2 x i8] c\"hi\"\n"))
    }

    @Test func `a function's linkage decides which code sees its name`() throws {
        let bench = Workbench()
        let function = bench.function(named: "helper", returning: bench.context.voidType)
        bench.builder.returnVoid()
        function.setLinkage(.internal)

        try bench.module.verify()
        #expect(function.text.hasPrefix("define internal void @helper() {"))
    }

    @Test func `a module's target and data layout are those it is given`() {
        let bench = Workbench()
        bench.module.target = "x86_64-unknown-linux-gnu"
        bench.module.dataLayout = "e-m:e-i64:64-n8:16:32:64-S128"

        #expect(bench.module.target == "x86_64-unknown-linux-gnu")
        #expect(bench.module.dataLayout == "e-m:e-i64:64-n8:16:32:64-S128")
        #expect(bench.module.name == "workbench")
    }

    @Test func `a module keeps its context alive after the context goes`() throws {
        /// A module whose context this function made, and no longer holds.
        func orphanedModule() -> Module {
            let context = Context()
            let module = context.makeModule(named: "orphan")
            let int64 = context.integerType(I64.self)
            let function = module.addFunction(named: "one", type: context.functionType(returning: int64, taking: []))
            let builder = context.makeBuilder()
            builder.position(atEndOf: context.appendBlock(named: "entry", to: function))
            builder.return(int64.constant(1))
            return module
        }

        let module = orphanedModule()
        try module.verify()
        #expect(module.text.contains("ret i64 1"))
    }
}
