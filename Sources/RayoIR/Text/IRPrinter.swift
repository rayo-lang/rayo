import RayoSema
import RayoSource

/// Writes Rayo IR as text, which `IRParser` reads back into the same program.
///
/// The text gives the program's structs, then the function it starts at, then each function, in the order of their
/// IDs:
///
/// ```
/// struct Pair {
///   count: Int
///   flag: Bool
/// }
///
/// main "main()"
///
/// func "main()"() -> Void {
///   var %0 x: Int
///   temp %1: Bool
/// bb0:
///   declare %0
///   %0 @2:9-2:10 = use 1 @2:13-2:14
///   %1 @3:4-3:9 = less read %0 @3:4-3:5, 3 @3:4-3:9
///   branch read %1 @3:4-3:9, bb1, bb2
/// ...
/// }
/// ```
///
/// Each local is numbered by its ID and each block by its own, and a source range is written `line:column-line:column`
/// after an `@`. A statement's own range comes last on its line, after its destination's and its operands'.
public enum IRPrinter {
    /// `program` as text.
    public static func text(of program: IRProgram) -> String {
        // Structs and the function a run starts at come before the functions, which name them.
        var sections = program.types.structs.map(text(of:))
        if let main = program.main { sections.append("main \(quoted(program.functions[main].name))\n") }

        // Each function, in the order of its ID.
        for id in program.functions.ids {
            sections.append(text(of: program.functions[id], body: program.bodies[id], in: program))
        }
        return sections.joined(separator: "\n")
    }

    /// A struct's declaration, a line for each field.
    private static func text(of type: StructType) -> String {
        let fields = type.fields.map { "  \($0.name): \($0.type)\n" }.joined()
        return "struct \(type.name) {\n\(fields)}\n"
    }

    /// A function's declaration, followed, where it has a body, by its locals and its blocks.
    private static func text(of function: FunctionDeclaration, body: IRBody?, in program: IRProgram) -> String {
        let parameters = function.parameters.map(\.description).joined(separator: ", ")
        let header = "func \(quoted(function.name))(\(parameters)) -> \(function.result)"
        guard let body else { return header + "\n" }

        // Each local on a line, then each block under its label.
        let locals = body.locals.enumerated().map { "  \(text(of: $1, id: $0))\n" }.joined()
        let blocks = body.blocks.enumerated().map { index, block in
            let statements = block.statements.map { "  \(text(of: $0, in: program))\n" }.joined()
            return "bb\(index):\n\(statements)  \(text(of: block.terminator))\n"
        }
        return "\(header) {\n\(locals)\(blocks.joined())}\n"
    }

    private static func text(of local: IRLocal, id: Int) -> String {
        switch local {
        case .source(let name, let kind, let type): "\(keyword(of: kind)) %\(id) \(name): \(type)"
        case .temporary(let type): "temp %\(id): \(type)"
        }
    }

    /// The word a local's declaration starts with, for the kind the source declares it with.
    static func keyword(of kind: LocalKind) -> String {
        switch kind {
        case .let: "let"
        case .var: "var"
        case .parameter: "param"
        }
    }

    private static func text(of statement: Statement, in program: IRProgram) -> String {
        switch statement {
        case .declare(let local):
            "declare %\(local.index)"
        case .compute(let destination, let value, let range):
            "\(text(of: destination)) = \(text(of: value, in: program)) \(text(of: range))"
        }
    }

    /// The place a computation stores its value in and where the source names it, or `_` where it drops the value.
    private static func text(of destination: Destination?) -> String {
        guard let destination else { return "_" }
        return "\(text(of: destination.place)) \(text(of: destination.range))"
    }

    private static func text(of value: Rvalue, in program: IRProgram) -> String {
        switch value {
        case .use(let operand):
            "use \(text(of: operand))"
        case .unary(let op, let operand):
            "\(name(of: op)) \(text(of: operand))"
        case .binary(let op, let left, let right):
            "\(name(of: op)) \(text(of: left)), \(text(of: right))"
        case .call(let callee, let arguments):
            "call \(text(of: callee, in: program))(\(list(arguments)))"
        case .structure(let id, let fields):
            "struct \(id.name)(\(list(fields)))"
        }
    }

    /// What a call calls: `builtin` and a built-in's name, or a function's name, quoted.
    private static func text(of callee: Callee, in program: IRProgram) -> String {
        switch callee {
        case .builtin: "builtin \(quoted(callee.name(in: program.functions)))"
        case .function: quoted(callee.name(in: program.functions))
        }
    }

    private static func text(of terminator: Terminator) -> String {
        switch terminator {
        case .goto(let target): "goto bb\(target.index)"
        case .branch(let condition, let then, let otherwise):
            "branch \(text(of: condition)), bb\(then.index), bb\(otherwise.index)"
        case .return(let result?): "return \(text(of: result))"
        case .return(nil): "return"
        case .unreachable: "unreachable"
        }
    }

    private static func text(of operand: Operand) -> String {
        switch operand {
        case .constant(.int(let value)): "\(value)"
        case .constant(.bool(let value)): "\(value)"
        case .read(let place, let range): "read \(text(of: place)) \(text(of: range))"
        case .move(let place, let range): "move \(text(of: place)) \(text(of: range))"
        }
    }

    /// A place as its local's number and the field each step leads into, such as `%2.1.0`.
    private static func text(of place: Place) -> String {
        let steps = place.steps.map { step in
            switch step {
            case .field(let index): ".\(index)"
            }
        }
        return "%\(place.root.index)\(steps.joined())"
    }

    private static func text(of range: SourceRange) -> String {
        "@\(range.start.line):\(range.start.column)-\(range.end.line):\(range.end.column)"
    }

    private static func list(_ operands: [Operand]) -> String {
        operands.map(text(of:)).joined(separator: ", ")
    }

    private static func quoted(_ name: String) -> String {
        "\"\(name)\""
    }

    /// The name of a unary operator, with its overflow mode where it has one, such as `negate checked`.
    static func name(of op: IRUnaryOperator) -> String {
        switch op {
        case .negate(let mode): "negate \(name(of: mode))"
        case .not: "not"
        }
    }

    /// The name of a binary operator, with its overflow mode where it has one, such as `add wrapping`.
    static func name(of op: IRBinaryOperator) -> String {
        switch op {
        case .add(let mode): "add \(name(of: mode))"
        case .subtract(let mode): "subtract \(name(of: mode))"
        case .multiply(let mode): "multiply \(name(of: mode))"
        case .divide(let mode): "divide \(name(of: mode))"
        case .remainder: "remainder"
        case .equal: "equal"
        case .notEqual: "notEqual"
        case .less: "less"
        case .lessEqual: "lessEqual"
        case .greater: "greater"
        case .greaterEqual: "greaterEqual"
        }
    }

    private static func name(of mode: OverflowMode) -> String {
        switch mode {
        case .checked: "checked"
        case .wrapping: "wrapping"
        }
    }
}
