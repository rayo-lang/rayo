import Testing
import RayoDiagnostics

/// A struct, and functions that take and give arrays, which the bodies below use.
private let declarations = """
    struct Hit(var damage: Int)
    func sum(_ a: [2 of Int]) -> Int { 0 }
    func none(_ a: [0 of Bool]) {}
    func pick(_ a: [2 of Int]) {}
    func pick(_ a: [3 of Int]) {}
    func made() -> [2 of Int] { .init(all: 1) }
    func returned() -> [2 of Bool] { return .init(all: true) }
    struct Holder(var hits: [2 of Hit])
    """

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
        ("func f(_ a: [9223372036854775808 of Bool]) {}", .arrayTooLarge, "[9223372036854775808 of Bool]"),
        ("func f(_ a: [1152921504606846976 of Int]) {}", .arrayTooLarge, "[1152921504606846976 of Int]"),
        (
            "func f() {\n    var a: [2 of [576460752303423488 of Int]]\n}",
            .arrayTooLarge, "[2 of [576460752303423488 of Int]]",
        ),
        ("func f(_ a: [2 of S]) {}\nstruct S(var a: [576460752303423488 of Int])", .arrayTooLarge, "[2 of S]"),
        ("struct S(var a: Int, let b: [1152921504606846976 of Int])", .arrayTooLarge, "[1152921504606846976 of Int]"),
    ])
    func `an array's element type names a type that isn't Void, and its size in bytes fits in an Int`(
        declaration: String, expected: ErrorCode, covered: String,
    ) {
        let source = "func main() {}\n" + declaration

        // The one error is the type's, and it covers what is wrong with it.
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [expected])
        #expect(coveredText(reported, in: source) == [covered])
    }

    @Test func `a struct whose fields fit in memory, but not together, is too large, and so is one that holds it`() {
        // `S` takes two fields of 2^62 bytes each, which no Int can count together. `T` holds `S`, and fails with it.
        let source = """
            func main() {}
            struct S(var a: [576460752303423488 of Int], var b: [576460752303423488 of Int])
            struct T(var s: S)
            func f(_ t: T) {}
            """
        let reported = diagnostics(source)
        #expect(reported.map(\.code) == [.structTooLarge(name: "S")])
        #expect(coveredText(reported, in: source) == ["S"])
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
        ("let a = [1]\nlet b = a.first", .noSuchMember(type: "[1 of Int]", name: "first")),
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
        "let a: [2 of UInt] = [1, 2]\n_ = a\nlet b: [1 of [2 of UInt]] = [[3, 4]]\n_ = b",
        "_ = [if true { 1 } else { 2 }, 3]",
    ])
    func `an array literal takes its type from its position, or from its elements`(body: String) {
        #expect(errorLines(inMain: body, beside: declarations) == [])
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
        #expect(errorLines(inMain: body, beside: declarations) == [expected])
    }

    @Test func `a literal returned from a function needs as many elements as the function's result type`() {
        #expect(errors("func main() {}\nfunc made() -> [2 of Int] { return [1] }") == [
            .arrayLiteralCount(type: "[2 of Int]", needs: 2, found: 1),
        ])
    }

    @Test func `each element is checked, so an error in one still reports the others'`() {
        #expect(errorLines(inMain: "let a = [q, 9223372036854775808]", beside: declarations) == [
            "2:10: error[E0206]: 'q' isn't declared", "2:13: error[E0217]: the literal doesn't fit in an Int",
        ])
    }

    @Test func `an element of an array literal is moved into the array, as a struct's field is`() {
        #expect(errors("func main() {\nlet h = Hit(damage: 1)\n_ = [h]\n_ = h\n}\n" + declarations) == [
            .usedAfterMove(name: "h"),
        ])
    }
}

struct ArrayInitializerTests {
    @Test(arguments: [
        "var a: [3 of Int] = .init(all: 0)\n_ = a",
        "let a: [2 of UInt] = .init(all: 7)\n_ = a",
        "_ = sum(.init(all: 1))",
        "none(.init(all: true))",
        "var a: [2 of Int] = [1, 2]\n_ = a\na = .init(all: 3)\n_ = a",
        "_ = Holder(hits: .init(all: Hit(damage: 1)))",
        "let a: [2 of [2 of Int]] = [.init(all: 1), [2, 3]]\n_ = a",
        "let a: [2 of [3 of Bool]] = .init(all: .init(all: true))\n_ = a",
        "let n = 3\nlet a: [2 of Int] = .init(all: n + 1)\n_ = a",
    ])
    func `.init(all:) makes the array its position expects`(body: String) {
        #expect(errorLines(inMain: body, beside: declarations) == [])
    }

    @Test(arguments: [
        ("let a = .init(all: 0)", "2:9: error[E0267]: the implicit member '.init' needs a type"),
        ("let a: Int = .init(all: 0)", "2:14: error[E0257]: implicit members of Int aren't supported"),
        ("let a: Hit = .init(damage: 1)", "2:14: error[E0257]: implicit members of Hit aren't supported"),
        ("let a: [2 of Int] = .init(0)", "2:27: error[E0228]: expected 'all:' before the argument, found no label"),
        ("let a: [2 of Int] = .init(al: 0)", "2:27: error[E0228]: expected 'all:' before the argument, found 'al:'"),
        ("let a: [2 of Int] = .init(each: 0)", "2:21: error[E0268]: '.init(each:)' isn't supported"),
        ("let a: [2 of Int] = .init(all: 0, 1)", "2:21: error[E0210]: '.init' takes 1 argument, but the call passes 2"),
        ("let a: [2 of Int] = .init()", "2:21: error[E0210]: '.init' takes 1 argument, but the call passes 0"),
        ("let a: [2 of Int] = .init", "2:21: error[E0269]: '.init' must be called"),
        ("let a: [2 of Int] = .zero", "2:21: error[E0270]: [2 of Int] has no member 'zero'"),
        ("let a: [2 of Int] = .make(all: 0)", "2:21: error[E0270]: [2 of Int] has no member 'make'"),
        ("let a: [2 of Int] = .init(all: true)", "2:32: error[E0213]: expected Int, found Bool"),
        ("let a: [2 of UInt] = .init(all: -1)", "2:33: error[E0217]: the literal doesn't fit in a UInt"),
        ("pick(.init(all: 1))", "2:1: error[E0260]: the call fits more than one 'pick'"),
        ("print(.init(all: 1))", "2:7: error[E0267]: the implicit member '.init' needs a type"),
    ])
    func `.init(all:) with no array type, or with the wrong member, label or value, is an error`(
        body: String, expected: String,
    ) {
        #expect(errorLines(inMain: body, beside: declarations) == [expected])
    }

    @Test func `the value an array is filled with is copied into it, so it is borrowed and stays usable`() {
        #expect(errors("func main() {\nlet h = Hit(damage: 1)\nlet a: [2 of Hit] = .init(all: h)\n_ = a\n_ = h\n}\n"
            + declarations) == [])
    }

    @Test func `a value that was moved can't fill an array`() {
        #expect(errors("func main() {\nlet h = Hit(damage: 1)\n_ = h\nlet a: [2 of Hit] = .init(all: h)\n_ = a\n}\n"
            + declarations) == [.usedAfterMove(name: "h")])
    }
}
