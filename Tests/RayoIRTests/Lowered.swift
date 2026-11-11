import RayoDiagnostics
import RayoIR
import RayoSema
import RayoSource
import RayoSyntax

/// The diagnostics of a test's source that the parser or the checker rejected.
struct RejectedSource: Error {
    let diagnostics: [Diagnostic]
}

/// Parses, checks and lowers `source`, throwing a `RejectedSource` where the parser or the checker rejects it.
func loweredWithRanges(_ source: String) throws(RejectedSource) -> IRProgram {
    let (file, syntaxErrors) = Parser.parse(Array(source.utf8))
    guard syntaxErrors.isEmpty else { throw RejectedSource(diagnostics: syntaxErrors) }

    let (program, checkErrors) = Checker.check(file)
    guard let program else { throw RejectedSource(diagnostics: checkErrors) }

    return Lowering.lower(program)
}

/// Parses, checks and lowers `source`, and sets every source range in the IR to `nowhere`, as the expected IR has them.
/// Throws a `RejectedSource` where the parser or the checker rejects the source.
func lowered(_ source: String) throws(RejectedSource) -> IRProgram {
    var program = try loweredWithRanges(source)
    program.functions = program.functions.map(\.erasingRanges)
    return program
}

/// Parses, checks and lowers a `main` whose body is `body`, and gives its IR with every source range in it `nowhere`.
/// Throws a `RejectedSource` where the parser or the checker rejects the source.
func loweredMain(_ body: String) throws(RejectedSource) -> IRFunction {
    let program = try lowered("func main() {\n\(body)\n}")
    // The source declares `main`, so the program has one.
    return program.functions[program.main!.index]
}

private extension IRFunction {
    var erasingRanges: IRFunction {
        let blocks = blocks.map { block in
            BasicBlock(statements: block.statements.map(\.erasingRanges), terminator: block.terminator.erasingRanges)
        }
        return IRFunction(name: name, parameterCount: parameterCount, result: result, locals: locals, blocks: blocks)
    }
}

private extension Statement {
    var erasingRanges: Statement {
        switch self {
        case .compute(let destination, let value, _):
            .compute(destination: destination?.erasingRange, value: value.erasingRanges, range: nowhere)
        case .declare: self
        }
    }
}

private extension Rvalue {
    var erasingRanges: Rvalue {
        switch self {
        case .use(let operand): .use(operand.erasingRange)
        case .unary(let op, let operand): .unary(op, operand.erasingRange)
        case .binary(let op, let left, let right): .binary(op, left.erasingRange, right.erasingRange)
        case .call(let callee, let arguments): .call(callee, arguments: arguments.map(\.erasingRange))
        }
    }
}

private extension Terminator {
    var erasingRanges: Terminator {
        switch self {
        case .branch(let condition, let then, let otherwise):
            .branch(condition.erasingRange, then: then, otherwise: otherwise)
        case .return(let result): .return(result?.erasingRange)
        case .goto, .unreachable: self
        }
    }
}

private extension Operand {
    var erasingRange: Operand {
        switch self {
        case .read(let place): .read(place.erasingRange)
        case .move(let place): .move(place.erasingRange)
        case .constant: self
        }
    }
}

private extension Place {
    var erasingRange: Place {
        Place(local: local, range: nowhere)
    }
}
