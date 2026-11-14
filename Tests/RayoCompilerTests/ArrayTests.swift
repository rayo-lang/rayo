import Testing
import RayoDiagnostics

/// A struct, and functions that take and give arrays, which the bodies below use.
private let declarations = """
    struct Hit(var damage: Int)
    func sum(_ a: [2 of Int]) -> Int { 0 }
    func none(_ a: [0 of Bool]) {}
    func pick(_ a: [2 of Int]) {}
    func pick(_ a: [3 of Int]) {}
    """

/// The errors that `body`, as `main`'s body beside `declarations`, reports, each as its position, code and message.
private func errorLines(_ body: String) -> [String] {
    diagnostics("func main() {\n\(body)\n}\n\(declarations)").map(\.description)
}

struct ArrayTypeTests {
    @Test(arguments: [
        "func f(_ a: [2 of Int]) -> [2 of Int] { copy a }",
        "func f(_ a: [0 of Bool]) -> [0 of Bool] { copy a }",
        "func f(_ a: [2 of [3 of S]]) {}\nstruct S(var a: [4 of Bool], let b: [1 of [0 of Int]])",
        "func f() {\n    var a: [2 of S]\n    let b: [1 of Int]\n}\nstruct S",
    ])
    func `an array type may be a local's, a parameter's, a result's, a field's or an element's`(source: String) {
        #expect(errors("func main() {}\n" + source) == [])
    }

    @Test(arguments: [
        ("func f(_ a: [2 of Q]) {}", ErrorCode.notAType(name: "Q"), "Q"),
        ("func f(_ a: [2 of ()]) {}", .voidElement(type: "Void"), "()"),
        ("func f(_ a: [2 of [1 of Void]]) {}", .voidElement(type: "Void"), "Void"),
        ("func f(_ a: [9223372036854775808 of Int]) {}", .arrayCountExceedsInt, "[9223372036854775808 of Int]"),
    ])
    func `an array's element type names a type that isn't Void, and its count fits in an Int`(
        declaration: String, expected: ErrorCode, covered: String,
    ) {
        let source = "func main() {}\n" + declaration

        // The one error is the type's, and it covers what is wrong with it.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test(arguments: [
        ("struct S(var a: [2 of S])", [ErrorCode.containsItself(name: "S")]),
        ("struct S(var a: [0 of S])", [.containsItself(name: "S")]),
        (
            "struct S(var a: [1 of [2 of T]])\nstruct T(var s: S)",
            [.containsItself(name: "S"), .containsItself(name: "T")],
        ),
    ])
    func `a struct that holds itself through an array, at any depth, contains itself`(
        declarations: String, expected: [ErrorCode],
    ) {
        #expect(errors("func main() {}\n" + declarations) == expected)
    }

    @Test(arguments: [
        (
            "let a = [true, false]\nlet b: [2 of Int] = a",
            ErrorCode.typeMismatch(expected: "[2 of Int]", found: "[2 of Bool]"),
        ),
        ("let a = [Hit(damage: 1)]\nlet b: [1 of Int] = a", .typeMismatch(expected: "[1 of Int]", found: "[1 of Hit]")),
        ("let a = [1, 2]\nlet b: [3 of Int] = a", .typeMismatch(expected: "[3 of Int]", found: "[2 of Int]")),
        ("print([1])", .noMatchingFunction(name: "print", arguments: "[1 of Int]")),
        ("let a = [1] == [1]", .incomparable(op: "==", type: "[1 of Int]")),
        ("let a = [1]\nlet b = a.count", .noSuchField(type: "[1 of Int]", field: "count")),
    ])
    func `an array type is its count and its element's type, and has no other type`(body: String, expected: ErrorCode) {
        #expect(errors("func main() {\n\(body)\n}\n\(declarations)") == [expected])
    }
}

struct ArrayLiteralTests {
    @Test(arguments: [
        "let a: [2 of Int] = [1, -2]\n_ = sum(a)",
        "_ = sum([1, 2])",
        "let a: [0 of Bool] = []\nnone(a)\nnone([])",
        "var a = [[1, 2], [3, 4]]\n_ = a\na = [[5, 6], [7, 8]]\n_ = a",
        "let h = Hit(damage: 1)\n_ = [h, Hit(damage: 2)]",
        "let n = 3\n_ = [1, n]",
        "pick([1, 2, 3])",
        "_ = [if true { 1 } else { 2 }, 3]",
    ])
    func `an array literal takes its type from its position, or from its elements`(body: String) {
        #expect(errorLines(body) == [])
    }

    @Test(arguments: [
        ("let a: [3 of Int] = [1, 2]", "2:21: error[E0261]: a [3 of Int] literal needs 3 elements, found 2"),
        ("_ = sum([1, 2, 3])", "2:9: error[E0261]: a [2 of Int] literal needs 2 elements, found 3"),
        ("var a: [1 of Int]\na = []", "3:5: error[E0261]: a [1 of Int] literal needs 1 element, found 0"),
        ("let a: [2 of Int] = [1, true]", "2:25: error[E0213]: expected Int, found Bool"),
        ("let a = [1, true]", "2:10: error[E0263]: the array literal holds Bool in one element and Int in another"),
        (
            "let a = [Hit(damage: 1), 2]",
            "2:26: error[E0263]: the array literal holds Hit in one element and Int in another",
        ),
        ("let a = [[1], [1, 2]]", "2:15: error[E0261]: a [1 of Int] literal needs 1 element, found 2"),
        ("let a = []", "2:9: error[E0262]: an empty array literal needs a type"),
        ("let a: Int = [1]", "2:14: error[E0213]: expected Int, found [1 of Int]"),
        ("pick([1])", "2:1: error[E0231]: no 'pick' takes the arguments ([1 of Int])"),
    ])
    func `an array literal whose count or elements don't fit its type, or that has no type, is an error`(
        body: String, expected: String,
    ) {
        #expect(errorLines(body) == [expected])
    }

    @Test func `a literal returned from a function needs as many elements as the function's result type`() {
        #expect(errors("func main() {}\nfunc made() -> [2 of Int] { return [1] }") == [
            .arrayLiteralCount(type: "[2 of Int]", needs: 2, found: 1),
        ])
    }

    @Test func `each element is checked, so an error in one still reports the others'`() {
        #expect(errorLines("let a = [q, 9223372036854775808]") == [
            "2:10: error[E0206]: 'q' isn't declared", "2:13: error[E0217]: the literal doesn't fit in an Int",
        ])
    }

    @Test func `an element of an array literal is moved into the array, as a struct's field is`() {
        #expect(errors("func main() {\nlet h = Hit(damage: 1)\n_ = [h]\n_ = h\n}\n" + declarations) == [
            .usedAfterMove(name: "h"),
        ])
    }
}
