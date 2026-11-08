import Testing
import RayoDiagnostics

@Diagnostics
enum SampleCode: Equatable {
    @Code(1, error: "the program has no 'main' function")
    case noMain

    @Code(2, error: "'{name}' isn't declared")
    case notDeclared(name: String)

    @Code(3, error: "expected {expected}, found {found}")
    case typeMismatch(expected: String, found: String)

    @Code(40, notSupported: "moving a value out of '{name}'")
    case moveOutOfLocal(name: String)

    @Code(41, error: "'{name}' takes {count} argument, but the call passes {passed}: '{name}' can't take {passed}")
    case arity(name: String, count: Int, passed: Int)

    @Code(0x50, error: "'{in}' is in a loop")
    case keywordLabel(in: String)

    @Code(1_000, error: "expected '{' after '{name}', then '}' \u{41} and \"\\\" on\nanother line")
    case braces(name: String)

    @RayoDiagnostics.Code(1_001, error: "qualified")
    case qualified

    @Code(1_002, error: "a backslash, then '\\u{name}', and '{café}'")
    case edges(name: String, café: String)
}

struct DiagnosticsTests {
    @Test("a code's message fills its placeholders with the code's values", arguments: [
        (SampleCode.noMain, "the program has no 'main' function"),
        (.notDeclared(name: "x"), "'x' isn't declared"),
        (.typeMismatch(expected: "Int", found: "Bool"), "expected Int, found Bool"),
        (.arity(name: "f", count: 1, passed: 2), "'f' takes 1 argument, but the call passes 2: 'f' can't take 2"),
        (.keywordLabel(in: "i"), "'i' is in a loop"),
        (.qualified, "qualified"),
        (.edges(name: "n", café: "c"), "a backslash, then '\\un', and 'c'"),
    ])
    func messages(code: SampleCode, message: String) {
        #expect(code.message == message)
    }

    @Test("a brace that doesn't enclose a name, and an escape, are written as they are")
    func literalText() {
        #expect(SampleCode.braces(name: "if").message == "expected '{' after 'if', then '}' A and \"\\\" on\nanother line")
    }

    @Test("a code for what isn't supported yet says so")
    func notSupported() {
        #expect(SampleCode.moveOutOfLocal(name: "a").message == "moving a value out of 'a' isn't supported yet")
    }

    @Test("each code has its number", arguments: [
        (SampleCode.noMain, 1), (.notDeclared(name: "x"), 2), (.typeMismatch(expected: "", found: ""), 3),
        (.moveOutOfLocal(name: "a"), 40), (.arity(name: "", count: 0, passed: 0), 41), (.keywordLabel(in: ""), 80),
        (.braces(name: ""), 1000), (.qualified, 1001), (.edges(name: "", café: ""), 1002),
    ])
    func numbers(code: SampleCode, number: Int) {
        #expect(code.number == number)
    }
}
