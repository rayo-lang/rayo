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
    case literalExceeds64Bits

    // MARK: Parsing

    @Code(101, error: "unexpected character '{character}'")
    case unexpectedCharacter(character: String)

    // 102 is unused, and stays so.

    @Code(103, error: "unmatched '}'")
    case unmatchedBrace

    @Code(104, error: "expected 'func' to begin a declaration, found {found}")
    case missingFunc(found: FoundToken)

    @Code(105, error: "expected a newline or ';' after the declaration, found {found}")
    case unendedDeclaration(found: FoundToken)

    @Code(106, error: "expected the function's name, found {found}")
    case missingFunctionName(found: FoundToken)

    @Code(107, error: "expected '(' after the function's name, found {found}")
    case missingParameterList(found: FoundToken)

    @Code(108, error: "expected ')' after '(', found {found}")
    case unclosedEmptyParentheses(found: FoundToken)

    @Code(109, error: "expected a type, found {found}")
    case missingType(found: FoundToken)

    @Code(110, error: "expected '{' to begin a block, found {found}")
    case missingBlock(found: FoundToken)

    @Code(111, error: "expected '}' to close the block, found {found}")
    case unclosedBlock(found: FoundToken)

    @Code(112, error: "expected a newline or ';' after the statement, found {found}")
    case unendedStatement(found: FoundToken)

    @Code(113, error: "expected a name to bind, found {found}")
    case missingBindingName(found: FoundToken)

    @Code(114, error: "expected '=' and a value, found {found}")
    case missingBindingValue(found: FoundToken)

    @Code(115, error: "expected an expression, found {found}")
    case missingExpression(found: FoundToken)

    @Code(116, error: "expected a name after 'copy', found {found}")
    case missingCopiedName(found: FoundToken)

    @Code(117, error: "expected ')' to close the arguments, found {found}")
    case unclosedArguments(found: FoundToken)

    @Code(118, error: "expected ')' to close the parenthesized expression, found {found}")
    case unclosedParenthesizedExpression(found: FoundToken)

    // MARK: Checking

    @Code(201, error: "the program has no 'main' function")
    case noMain

    @Code(202, error: "'main' is declared more than once")
    case mainDeclaredTwice

    @Code(203, error: "a program's only function is 'main'")
    case functionNotMain

    @Code(204, error: "'main' returns Void")
    case mainReturnsNonVoid

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
    case literalExceedsInt

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
    /// The number as an error message shows it, such as `E0113`.
    public var identifier: String {
        let digits = String(number)
        return "E" + String(repeating: "0", count: max(0, 4 - digits.count)) + digits
    }
}

/// What the parser found where it expected something else.
public enum FoundToken: Sendable, Hashable, CustomStringConvertible {
    /// A token, as the source spells it.
    case token(String)
    case newline
    case endOfFile

    public var description: String {
        switch self {
        case .token(let spelling): return "'\(spelling)'"
        case .newline: return "a newline"
        case .endOfFile: return "the end of the file"
        }
    }
}

/// How many arguments a function takes, as an error names it: `1 argument`, `2 arguments`.
public struct ArgumentCount: Sendable, Hashable, ExpressibleByIntegerLiteral, CustomStringConvertible {
    public var count: Int

    public init(_ count: Int) { self.count = count }
    public init(integerLiteral count: Int) { self.count = count }

    public var description: String { count == 1 ? "1 argument" : "\(count) arguments" }
}
