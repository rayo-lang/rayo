import LLVM
import Testing

struct UndefinedValueTests {
    @Test(arguments: ["undef", "poison"])
    func `undef and poison say they are undefined`(value: String) throws {
        let bench = Workbench()
        let text = "define i64 @f() {\n  ret i64 \(value)\n}\n"
        let module = try bench.context.parseModule(Array(text.utf8), named: "m")
        let found = module.function(named: "f")
        let terminator = try #require(found?.blocks.first?.terminator)

        #expect(terminator.operand(at: 0).isUndefined)
    }

    @Test func `a constant is no undefined value`() {
        let bench = Workbench()

        #expect(!bench.int64.constant(0).anyValue.isUndefined)
    }
}
