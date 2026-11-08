/// An error the compiler reports in a program. A code's number never changes and is never reused, so an
/// error can be looked up by its number.
@Diagnostics
public enum ErrorCode: Sendable, Hashable {
    // MARK: Lexing

    @Code(1, error: "the file isn't valid UTF-8")
    case notUTF8

    @Code(2, error: "unterminated block comment")
    case unterminatedBlockComment

    @Code(3, error: "invalid digit in integer literal")
    case invalidDigit

    @Code(4, error: "expected digits after the radix prefix")
    case missingDigits

    @Code(5, error: "integer literal doesn't fit in 64 bits")
    case integerLiteralTooLarge

    // MARK: Parsing

    @Code(101, error: "unexpected character '{character}'")
    case unexpectedCharacter(character: String)

    @Code(102, error: "expected {what}, found {found}")
    case expected(what: Expectation, found: String)

    @Code(103, error: "unmatched '}'")
    case unmatchedBrace

    // MARK: Checking

    @Code(201, error: "the program has no 'main' function")
    case noMain

    @Code(202, error: "'main' is declared more than once")
    case mainDeclaredTwice

    @Code(203, error: "a program's only function is 'main'")
    case functionNotMain

    @Code(204, error: "'main' returns Void")
    case mainResult

    @Code(205, error: "'{name}' isn't a type")
    case notAType(name: String)

    @Code(206, error: "'{name}' isn't declared")
    case notDeclared(name: String)

    @Code(207, error: "'{name}' is already declared")
    case alreadyDeclared(name: String)

    @Code(208, error: "'{name}' isn't a function")
    case notAFunction(name: String)

    @Code(209, error: "'{name}' can't be called")
    case notCallable(name: String)

    @Code(210, error: "'{name}' takes {takes}, but the call passes {passes}")
    case argumentCount(name: String, takes: ArgumentCount, passes: Int)

    @Code(211, error: "'{name}' is a function, not a value")
    case functionAsValue(name: String)

    @Code(212, error: "'_' names no value")
    case underscoreValue

    @Code(213, error: "expected {expected}, found {found}")
    case typeMismatch(expected: String, found: String)

    @Code(214, error: "'{op}' needs operands of one type, found {left} and {right}")
    case operandsDiffer(op: String, left: String, right: String)

    @Code(215, error: "'{op}' needs {needs} operands, found {left} and {right}")
    case operandTypes(op: String, needs: String, left: String, right: String)

    @Code(216, error: "'{op}' can't compare Void values")
    case voidComparison(op: String)

    @Code(217, error: "the literal doesn't fit in an Int")
    case literalTooLarge

    @Code(218, error: "'_' can't be declared")
    case underscoreDeclared

    @Code(219, error: "a local can't have type Void")
    case voidLocal

    @Code(220, error: "a local's value is taken with 'copy {name}'")
    case takenWithoutCopy(name: String)

    @Code(221, error: "'{name}' is a 'let', so it can't change")
    case assignToLet(name: String)

    @Code(222, error: "'{name}' is a function, so it can't change")
    case assignToFunction(name: String)

    @Code(223, error: "only a local can be assigned")
    case assignToNonLocal

    @Code(224, error: "'{keyword}' is only allowed inside a loop")
    case outsideLoop(keyword: String)
}

extension ErrorCode {
    /// The number as an error message shows it, such as `E0102`.
    public var identifier: String {
        let digits = String(number)
        return "E" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }
}

/// What the parser expected to read next.
public enum Expectation: String, Sendable, Hashable, CustomStringConvertible {
    case declaration = "'func' to begin a declaration"
    case declarationEnd = "a newline or ';' after the declaration"
    case functionName = "the function's name"
    case parametersOpen = "'(' after the function's name"
    case parenthesisPair = "')' after '('"
    case type = "a type"
    case blockOpen = "'{' to begin a block"
    case blockClose = "'}' to close the block"
    case statementEnd = "a newline or ';' after the statement"
    case bindingName = "a name to bind"
    case bindingValue = "'=' and a value"
    case expression = "an expression"
    case copiedName = "a name after 'copy'"
    case argumentsClose = "')' to close the arguments"
    case parenthesizedClose = "')' to close the parenthesized expression"

    public var description: String { rawValue }
}

/// How many arguments a function takes, as an error names it: `1 argument`, `2 arguments`.
public struct ArgumentCount: Sendable, Hashable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    public var count: Int

    public init(_ count: Int) { self.count = count }
    public init(integerLiteral count: Int) { self.count = count }

    public var description: String { count == 1 ? "1 argument" : "\(count) arguments" }
}
