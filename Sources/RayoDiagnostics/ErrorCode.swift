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

    @Code(104, error: "expected 'func' or 'struct' to begin a declaration, found {found}")
    case missingDeclaration(found: FoundToken)

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

    // 114 is unused, and stays so.

    @Code(115, error: "expected an expression, found {found}")
    case missingExpression(found: FoundToken)

    @Code(116, error: "expected a name after 'copy', found {found}")
    case missingCopiedName(found: FoundToken)

    @Code(117, error: "expected ')' to close the arguments, found {found}")
    case unclosedArguments(found: FoundToken)

    @Code(118, error: "expected ')' to close the parenthesized expression, found {found}")
    case unclosedParenthesizedExpression(found: FoundToken)

    @Code(119, error: "expected ')' to close the parameters, found {found}")
    case unclosedParameters(found: FoundToken)

    @Code(120, error: "expected the parameter's name, found {found}")
    case missingParameterName(found: FoundToken)

    @Code(121, error: "expected ':' and the parameter's type, found {found}")
    case missingParameterType(found: FoundToken)

    @Code(122, error: "expected the struct's name, found {found}")
    case missingStructName(found: FoundToken)

    @Code(123, error: "expected 'var' or 'let' to begin a field, found {found}")
    case missingFieldKind(found: FoundToken)

    @Code(124, error: "expected the field's name, found {found}")
    case missingFieldName(found: FoundToken)

    @Code(125, error: "expected ')' to close the fields, found {found}")
    case unclosedFields(found: FoundToken)

    @Code(126, error: "expected '}' to close the struct's body, found {found}")
    case unclosedStructBody(found: FoundToken)

    @Code(127, error: "expected a member's name after '.', found {found}")
    case missingMemberName(found: FoundToken)

    // MARK: Checking

    @Code(201, error: "a file without a 'main' function is a library, which can't be built into an executable or run")
    case noMain

    @Code(202, error: "'{signature}' is declared more than once")
    case functionDeclaredTwice(signature: String)

    // 203 is unused, and stays so.

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

    // 209 is unused, and stays so.

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

    @Code(216, error: "'{op}' can't compare {type} values")
    case incomparable(op: String, type: String)

    @Code(217, error: "the literal doesn't fit in an Int")
    case literalExceedsInt

    @Code(218, error: "'_' can't be declared")
    case underscoreDeclared

    @Code(219, error: "a local can't have type Void")
    case voidLocal

    // 220 is unused, and stays so.

    // 221 is unused, and stays so.

    @Code(222, error: "'{name}' is a function, so it can't change")
    case assignToFunction(name: String)

    @Code(223, error: "only a local can be assigned")
    case assignToNonLocal

    @Code(224, error: "'{keyword}' is only allowed inside a loop")
    case outsideLoop(keyword: String)

    @Code(225, error: "'return' needs a value of type {type}")
    case missingReturnValue(type: String)

    @Code(226, error: "'{signature}' can reach its end without returning a value")
    case missingReturn(signature: String)

    @Code(227, error: "the result type of '{signature}' depends on itself")
    case resultDependsOnItself(signature: String)

    @Code(228, error: "expected {expected} before the argument, found {found}")
    case argumentLabel(expected: ArgumentLabel, found: ArgumentLabel)

    @Code(229, error: "'main' takes no parameters")
    case mainTakesParameters

    @Code(230, error: "'{name}' is a borrowed parameter, so it can't change")
    case assignToParameter(name: String)

    @Code(231, error: "no '{name}' takes the arguments ({arguments})")
    case noMatchingFunction(name: String, arguments: String)

    @Code(232, error: "'{convention}' parameters aren't supported")
    case unsupportedConvention(convention: String)

    @Code(233, error: "default arguments aren't supported")
    case defaultArgument

    @Code(234, error: "a parameter can't have type Void")
    case voidParameter

    @Code(235, error: "the {type} value isn't used")
    case unusedValue(type: String)

    @Code(236, error: "'{name}' needs a type or a value")
    case missingLocalType(name: String)

    @Code(237, error: "'{name}' needs a type")
    case missingFieldType(name: String)

    @Code(238, error: "a field can't have type Void")
    case voidField

    @Code(239, error: "'{name}' contains itself")
    case containsItself(name: String)

    @Code(240, error: "field defaults aren't supported")
    case fieldDefault

    // 241 is unused, and stays so.

    @Code(242, error: "'{name}' is a type, not a value")
    case typeAsValue(name: String)

    @Code(243, error: "'{name}' is a type, so it can't change")
    case assignToType(name: String)

    @Code(244, error: "{type} has no field '{field}'")
    case noSuchField(type: String, field: String)

    @Code(245, error: "the call leaves out the field '{field}'")
    case fieldLeftOut(field: String)

    @Code(246, error: "the call gives the field '{field}' more than once")
    case fieldGivenTwice(field: String)

    @Code(247, error: "'{field}' must come before '{after}', as the struct declares them")
    case fieldOutOfOrder(field: String, after: String)

    @Code(248, error: "the field '{field}' takes {expected}, found {found}")
    case fieldTypeMismatch(field: String, expected: String, found: String)

    @Code(249, error: "the argument names no field of {type}")
    case argumentNamesNoField(type: String)

    @Code(250, error: "moving a field out of a struct isn't supported")
    case fieldMove

    // MARK: Ownership

    @Code(301, error: "'{name}' is a borrowed parameter, so it can't be moved")
    case moveFromParameter(name: String)

    @Code(302, error: "'{name}' was moved")
    case usedAfterMove(name: String)

    @Code(303, error: "'{name}' may have been moved")
    case usedAfterMaybeMove(name: String)

    @Code(304, error: "'{name}' isn't initialized")
    case usedUninitialized(name: String)

    @Code(305, error: "'{name}' isn't initialized on every path")
    case usedMaybeUninitialized(name: String)

    @Code(306, error: "'{name}' is a 'let', so it can't be assigned again")
    case letAssignedTwice(name: String)

    @Code(307, error: "'{name}' is a 'let', and may have been assigned already")
    case letMaybeAssignedTwice(name: String)
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

/// The label an argument is written with, as an error names it: `'by:'`, or `no label`.
public enum ArgumentLabel: Sendable, Hashable, CustomStringConvertible {
    case label(String)
    case none

    public init(_ label: String?) {
        self = label.map { .label($0) } ?? .none
    }

    public var description: String {
        switch self {
        case .label(let label): return "'\(label):'"
        case .none: return "no label"
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
