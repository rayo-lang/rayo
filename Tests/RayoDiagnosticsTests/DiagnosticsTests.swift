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
}

struct DiagnosticsTests {
    @Test("a code's message fills its placeholders with the code's values", arguments: [
        (SampleCode.noMain, "the program has no 'main' function"),
        (.notDeclared(name: "x"), "'x' isn't declared"),
        (.typeMismatch(expected: "Int", found: "Bool"), "expected Int, found Bool"),
        (.arity(name: "f", count: 1, passed: 2), "'f' takes 1 argument, but the call passes 2: 'f' can't take 2"),
    ])
    func messages(code: SampleCode, message: String) {
        #expect(code.message == message)
    }

    @Test("a code for what isn't supported yet says so")
    func notSupported() {
        #expect(SampleCode.moveOutOfLocal(name: "a").message == "moving a value out of 'a' isn't supported yet")
    }

    @Test("each code has its number", arguments: [
        (SampleCode.noMain, 1), (.notDeclared(name: "x"), 2), (.moveOutOfLocal(name: "a"), 40),
    ])
    func numbers(code: SampleCode, number: Int) {
        #expect(code.number == number)
    }
}
