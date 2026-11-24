import Testing
@testable import RayoDiagnostics
import RayoSource

@Diagnostics
enum SampleCode: Equatable {
    @Code(1, error: "the program has no 'main' function")
    case noMain

    @Code(2, error: "'{name}' isn't declared")
    case notDeclared(name: String)

    @Code(3, error: "expected {expected}, found {found}")
    case typeMismatch(expected: String, found: String)

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

    @Code(1_003, error: "expected a block '{…}'")
    case ellipsis

    @Code(1_004, error: "'{name}' has {name.count} letters, and '{name.}' and '{name.count.x}' are text")
    case letters(name: String)

    @Code(1_005, warning: "'{name}' is never read")
    case unread(name: String)

    @Code(1_006, error: "'{name}' was moved", labels: ["moved": "moved here", "kept": "'{name}' kept here"])
    case moved(name: String)
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
        (.ellipsis, "expected a block '{…}'"),
        (.letters(name: "abc"), "'abc' has 3 letters, and '{name.}' and '{name.count.x}' are text"),
    ])
    func messages(code: SampleCode, message: String) {
        #expect(code.message == message)
    }

    @Test("a brace that doesn't enclose a name, and an escape, are written as they are")
    func literalText() {
        #expect(SampleCode.braces(name: "if").message == "expected '{' after 'if', then '}' A and \"\\\" on\nanother line")
    }

    @Test("each code has its number", arguments: [
        (SampleCode.noMain, 1), (.notDeclared(name: "x"), 2), (.typeMismatch(expected: "", found: ""), 3),
        (.arity(name: "", count: 0, passed: 0), 41), (.keywordLabel(in: ""), 80),
        (.braces(name: ""), 1000), (.qualified, 1001), (.edges(name: "", café: ""), 1002), (.ellipsis, 1003),
        (.letters(name: ""), 1004), (.unread(name: ""), 1005), (.moved(name: ""), 1006),
    ])
    func numbers(code: SampleCode, number: Int) {
        #expect(code.number == number)
    }

    @Test(arguments: [(SampleCode.noMain, Severity.error), (.unread(name: "x"), .warning), (.moved(name: "x"), .error)])
    func `each code is an error or a warning, as its '@Code' says`(code: SampleCode, severity: Severity) {
        #expect(code.severity == severity)
    }

    @Test func `a code's labels give their texts, filled with the code's values`() {
        #expect(SampleCode.moved(name: "x").labels == [.moved: "moved here", .kept: "'x' kept here"])
        #expect(SampleCode.noMain.labels.isEmpty)
    }
}

/// The range from `line`, `column` to the end of that line.
private func range(_ line: Int, _ column: Int) -> SourceRange {
    SourceRange(SourceLocation(line: line, column: column, offset: line * 100 + column),
                SourceLocation(line: line, column: 99, offset: line * 100 + 99))
}

struct DiagnosticTests {
    @Test func `a diagnostic is shown as its position, its severity, its code and its message`() {
        let error = Diagnostic(.usedAfterMove(name: "x"), at: range(3, 5))
        let warning = Diagnostic(.usedAfterMove(name: "x"), severity: .warning, at: range(3, 5))
        #expect(error.description == "3:5: error[E0302]: 'x' was moved")
        #expect(warning.description == "3:5: warning[E0302]: 'x' was moved")
    }

    @Test func `each place a diagnostic labels is shown as a note of its position and its label's text, in order`() {
        let moves = [range(2, 9), range(1, 7)].map { Diagnostic.LabeledRange(.moved, at: $0) }
        let diagnostic = Diagnostic(.usedAfterMove(name: "x"), at: range(3, 5), labeling: moves)
        #expect(diagnostic.notes == ["2:9: note: moved here", "1:7: note: moved here"])
    }
}

struct ErrorCodeTests {
    @Test("an error code is shown as 'E' and four digits", arguments: [
        (ErrorCode.notUTF8, "E0001"), (.unmatchedBrace, "E0103"), (.outsideLoop(keyword: "break"), "E0224"),
    ])
    func identifiers(code: ErrorCode, identifier: String) {
        #expect(code.identifier == identifier)
    }

    @Test(arguments: [ErrorCode.usedAfterMove(name: "x"), .usedAfterMaybeMove(name: "x")])
    func `a use of a moved local labels each move 'moved here'`(code: ErrorCode) {
        #expect(code.labels == [.moved: "moved here"])
    }

    @Test(arguments: [
        (ErrorCode.usedPartlyMoved(name: "s", field: "s.hit"),
         "'s.hit' was moved out of 's', so 's' can't be used as a whole"),
        (.usedMaybePartlyMoved(name: "s", field: "s.hit"),
         "'s.hit' may have been moved out of 's', so 's' can't be used as a whole"),
    ])
    func `a use of a place a field was moved out of names the field and the place`(code: ErrorCode, message: String) {
        #expect(code.message == message)
    }

    @Test("an argument count names one argument, or several", arguments: [
        (ArgumentCount(0), "0 arguments"), (1, "1 argument"), (2, "2 arguments"),
    ])
    func argumentCounts(count: ArgumentCount, text: String) {
        #expect(count.description == text)
    }

    @Test("a found token is named by its spelling, or as a newline or the end of the file", arguments: [
        (FoundToken.token("="), "'='"), (.newline, "a newline"), (.endOfFile, "the end of the file"),
    ])
    func foundTokens(found: FoundToken, text: String) {
        #expect(found.description == text)
    }

    @Test(arguments: [(TypeName.named("Int"), "Int"), ("Shot", "Shot"), (.shadowedPrelude("Int"), "the prelude's Int")])
    func `a type is named by its name, or as the prelude's when a declaration of the file shadows it`(
        type: TypeName, text: String,
    ) {
        #expect(type.description == text)
    }

    @Test(arguments: [
        (TypeName.named("Int"), "the Int", "an Int", "type Int"),
        ("UInt", "the UInt", "a UInt", "type UInt"),
        ("Bool", "the Bool", "a Bool", "type Bool"),
        (.shadowedPrelude("Int"), "the prelude's Int", "the prelude's Int", "the prelude's type Int"),
    ])
    func `a type's name takes 'the', 'a' or 'an', or the word 'type', which a shadowed prelude type's fits to its own`(
        type: TypeName, definite: String, withArticle: String, typePhrase: String,
    ) {
        #expect(type.definite == definite)
        #expect(type.withArticle == withArticle)
        #expect(type.typePhrase == typePhrase)
    }

    @Test(arguments: [
        (ErrorCode.unusedValue(type: "Int", drop: .bare),
         "the Int value isn't used; write '_ =' before it to drop it"),
        (.unusedValue(type: .shadowedPrelude("Int"), drop: .bare),
         "the prelude's Int value isn't used; write '_ =' before it to drop it"),
        (.literalDoesntFit(type: "Int"), "the literal doesn't fit in an Int"),
        (.literalDoesntFit(type: .shadowedPrelude("Int")), "the literal doesn't fit in the prelude's Int"),
        (.voidLocal(name: "x", type: "Void"), "the local 'x' can't have type Void"),
        (.voidLocal(name: "x", type: .shadowedPrelude("Void")), "the local 'x' can't have the prelude's type Void"),
        (.voidParameter(name: "v", type: .shadowedPrelude("Void")),
         "the parameter 'v' can't have the prelude's type Void"),
        (.voidField(name: "v", type: .shadowedPrelude("Void")), "the field 'v' can't have the prelude's type Void"),
        (.missingReturnValue(type: "Int"), "'return' needs a value of type Int"),
        (.missingReturnValue(type: .shadowedPrelude("Int")), "'return' needs a value of the prelude's type Int"),
    ])
    func `a message names a type in the form its sentence needs`(code: ErrorCode, message: String) {
        #expect(code.message == message)
    }

    @Test(arguments: [
        (ErrorCode.unusedValue(type: "Enemy", drop: .consume),
         "the Enemy value isn't used; write '_ = consume' before it to drop it"),
        (.unusedValue(type: "Enemy", drop: .copy), "the Enemy value isn't used; write '_ = copy' before it to drop it"),
        (.assignmentBorrowsPlace(marks: PlaceMarks("e", mayMove: true, mayLend: false)),
         "an assignment can't borrow 'e'; write 'consume e' or 'copy e'"),
        (.assignmentBorrowsPlace(marks: PlaceMarks("g[0]", mayMove: false, mayLend: false)),
         "an assignment can't borrow 'g[0]'; write 'copy g[0]'"),
    ])
    func `a message about a place written bare names the marks that fit it`(code: ErrorCode, message: String) {
        #expect(code.message == message)
    }

    @Test(arguments: [
        (DropMark.bare, "the parameter 'n' is never read; write '_ = n' to drop it"),
        (.consume, "the parameter 'n' is never read; write '_ = consume n' to drop it"),
        (.copy, "the parameter 'n' is never read; write '_ = copy n' to drop it"),
    ])
    func `a message about an unread place names the statement that drops it`(mark: DropMark, message: String) {
        #expect(ErrorCode.unreadParameter(drop: DropStatement(mark, dropping: "n")).message == message)
    }
}
