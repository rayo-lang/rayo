import RayoSource

/// Writes a checked program as text, for a reader to see what checking made of the source.
///
/// The text gives the program's structs, then the function a run starts at, then each function, in the order of
/// their IDs, with its locals and then its statements. A struct's primary initializer is declared with `init`, and has
/// no body. Each statement and expression starts a line, and the expressions and places it holds follow, indented
/// under it. An expression's line ends in its type and its source range, written `line:column-line:column` after an
/// `@`:
///
/// ```
/// func "main()"() -> Void {
///   let %0 x: Int
///   bind %0 @2:9-2:10
///     binary add: Int @2:13-2:18
///       int 1: Int @2:13-2:14
///       int 2: Int @2:17-2:18
/// }
/// ```
public struct CheckedPrinter: ~Copyable {
    private let program: CheckedProgram
    private var lines: [String] = []

    private init(_ program: CheckedProgram) {
        self.program = program
    }

    /// `program` as text.
    public static func text(of program: CheckedProgram) -> String {
        var printer = CheckedPrinter(program)
        printer.writeProgram()
        return printer.lines.map { $0 + "\n" }.joined()
    }

    /// Writes the structs, the function a run starts at, and each function, a blank line between each two.
    private mutating func writeProgram() {
        for type in program.types.structs {
            lines.append("struct \(type.name) {")
            lines += type.fields.map { "  \($0.name): \($0.type)" }
            lines += ["}", ""]
        }
        if let main = program.main {
            lines += ["main \(quoted(program.functions[main].name))", ""]
        }
        for id in program.functions.ids {
            writeFunction(id)
        }

        // The last item ends the text without a blank line after it.
        if lines.last == "" { lines.removeLast() }
    }

    /// Writes a function's declaration, then its locals and its statements where it has a body.
    private mutating func writeFunction(_ id: FunctionID) {
        let function = program.functions[id]
        let parameters = function.parameters.map(\.description).joined(separator: ", ")
        let header = "\(function.kind.keyword) \(quoted(function.name))(\(parameters)) -> \(function.result)"
        guard let body = program.bodies[id] else {
            lines += [header, ""]
            return
        }

        lines.append(header + " {")
        for (index, local) in body.locals.enumerated() {
            lines.append("  \(keyword(of: local.kind)) %\(index) \(local.name): \(local.type)")
        }
        write(body.statements, depth: 1)
        lines += ["}", ""]
    }

    private mutating func write(_ statements: [CheckedStmt], depth: Int) {
        for statement in statements {
            write(statement, depth: depth)
        }
    }

    /// Writes a line that names what `statement` does, and the expressions and places it holds under it.
    private mutating func write(_ statement: CheckedStmt, depth: Int) {
        switch statement {
        case .expression(let value):
            line("expression", depth)
            write(value, depth: depth + 1)
        case .binding(let local, let range, let value):
            line("bind %\(local.index) \(text(of: range))", depth)
            if let value { write(value, depth: depth + 1) }
        case .assign(let place, let value):
            line("assign", depth)
            write(place, depth: depth + 1)
            write(value, depth: depth + 1)
        case .compoundAssign(let place, let op, let value):
            line("compound-assign \(op)", depth)
            write(place, depth: depth + 1)
            write(value, depth: depth + 1)
        case .whileStmt(let condition, let body):
            line("while", depth)
            write(condition, depth: depth + 1)
            line("do", depth)
            write(body, depth: depth + 1)
        case .breakStmt:
            line("break", depth)
        case .continueStmt:
            line("continue", depth)
        case .returnStmt(let value):
            line("return", depth)
            if let value { write(value, depth: depth + 1) }
        }
    }

    /// Writes a line that names what `expression` does, with its type and range, and the expressions and places it
    /// holds under it.
    private mutating func write(_ expression: CheckedExpr, depth: Int) {
        line("\(head(of: expression.kind)): \(expression.type) \(text(of: expression.range))", depth)
        switch expression.kind {
        case .intLiteral, .uintLiteral, .boolLiteral:
            break
        case .place(let place), .copy(let place):
            write(place, depth: depth + 1)
        case .unary(_, let operand):
            write(operand, depth: depth + 1)
        case .binary(_, let left, let right):
            write(left, depth: depth + 1)
            write(right, depth: depth + 1)
        case .call(_, let arguments):
            for argument in arguments { write(argument, depth: depth + 1) }
        case .arrayLiteral(let elements):
            for element in elements { write(element, depth: depth + 1) }
        case .if(let condition, let then, let otherwise):
            write(condition, depth: depth + 1)
            line("then", depth)
            write(then, depth: depth + 1)
            line("else", depth)
            write(otherwise, depth: depth + 1)
        }
    }

    /// What an expression of `kind` does, without the expressions it holds, such as `binary add` or `int 3`.
    private func head(of kind: CheckedExprKind) -> String {
        switch kind {
        case .intLiteral(let value): "int \(value)"
        case .uintLiteral(let value): "uint \(value)"
        case .boolLiteral(let value): "bool \(value)"
        case .place: "value"
        case .copy: "copy"
        case .unary(let op, _): "unary \(op)"
        case .binary(let op, _, _): "binary \(op)"
        case .call(let callee, _): "call \(text(of: callee))"
        case .if: "if"
        case .arrayLiteral: "array"
        }
    }

    /// Writes a branch of an `if`: its statements, then `value` and the expression that gives it, where it gives one.
    private mutating func write(_ branch: CheckedBranch, depth: Int) {
        write(branch.statements, depth: depth)
        if let value = branch.value {
            line("value", depth)
            write(value, depth: depth + 1)
        }
    }

    /// Writes a place as its root, then each step and where the source names the place it leads to, such as
    /// `place %0 @3:1-3:2 .1 @3:1-3:7`. A value that no local holds is written under the line.
    private mutating func write(_ place: CheckedPlace, depth: Int) {
        let steps = place.steps.map { step in
            switch step {
            case .field(let index, let range): " .\(index) \(text(of: range))"
            }
        }.joined()
        switch place.root {
        case .local(let local, let range):
            line("place %\(local.index) \(text(of: range))\(steps)", depth)
        case .temporary(let value):
            line("place temporary\(steps)", depth)
            write(value, depth: depth + 1)
        }
    }

    /// Adds `text` as a line, indented two spaces for each level of `depth`.
    private mutating func line(_ text: String, _ depth: Int) {
        lines.append(String(repeating: "  ", count: depth) + text)
    }

    private func keyword(of kind: LocalKind) -> String {
        switch kind {
        case .let: "let"
        case .var: "var"
        case .parameter: "param"
        }
    }

    private func text(of range: SourceRange) -> String {
        "@\(range.start.line):\(range.start.column)-\(range.end.line):\(range.end.column)"
    }

    /// What a call calls: `builtin` and a built-in's name, or a function's name, quoted.
    private func text(of callee: Callee) -> String {
        switch callee {
        case .builtin: "builtin \(quoted(callee.name(in: program.functions)))"
        case .function: quoted(callee.name(in: program.functions))
        }
    }

    private func quoted(_ name: String) -> String {
        "\"\(name)\""
    }
}
