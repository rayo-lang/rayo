import Testing
import RayoDiagnostics

/// A struct of 2^31 bytes, one more than a value on the stack may take.
private let big = "struct Big(var a: [268435456 of Int])"

struct StackSizeTests {
    @Test(arguments: [
        (
            "var a: [1000000000000000000 of Int] = .init(repeating: 1)\nprint(a[0])",
            "[1000000000000000000 of Int]" as TypeName, "[1000000000000000000 of Int]",
        ),
        ("var a: [2147483648 of Bool]", "[2147483648 of Bool]", "[2147483648 of Bool]"),
        ("let b = Big(a: .init(repeating: 1))", "Big", "Big(a: .init(repeating: 1))"),
        ("print(Big(a: .init(repeating: 1)).a[0])", "Big", "Big(a: .init(repeating: 1))"),
        ("_ = Big(a: .init(repeating: 1))", "Big", "Big(a: .init(repeating: 1))"),
        ("Big(a: .init(repeating: 1)).a[0] = 2", "Big", "Big(a: .init(repeating: 1))"),
    ])
    func `a local or a temporary too large for the stack is reported once, where its type comes from`(
        body: String, type: TypeName, covered: String,
    ) {
        let source = "\(mainSource(body))\n\(big)"
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.tooLargeForStack(type: type)])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test(arguments: [
        ("func f(_ a: &[2147483648 of Bool]) {}", "[2147483648 of Bool]" as TypeName, "[2147483648 of Bool]"),
        (
            "func f() -> [2147483648 of Bool] { .init(repeating: false) }",
            "[2147483648 of Bool]", "[2147483648 of Bool]",
        ),
        ("func f() { Big(a: .init(repeating: 1)) }", "Big", "Big(a: .init(repeating: 1))"),
    ])
    func `a parameter or a result too large for the stack is reported once, where its type comes from`(
        declaration: String, type: TypeName, covered: String,
    ) {
        let source = "func main() {}\n\(declaration)\n\(big)"
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.tooLargeForStack(type: type)])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test(arguments: [
        "func f(_ a: &[2147483647 of Bool]) -> [2147483647 of Bool] { copy a }",
        "func f() {\n    var a: [2147483647 of Bool] = .init(repeating: false)\n    a[0] = true\n}",
        big,
    ])
    func `a value of up to 2147483647 bytes fits on the stack, and a type may be larger while no value of it is there`(
        source: String,
    ) {
        #expect(errors("func main() {}\n" + source) == [])
    }
}
