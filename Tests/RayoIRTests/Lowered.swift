import RayoDiagnostics
import RayoIR
import RayoSema
import RayoSource
import RayoSyntax

/// The diagnostics of a test's source that the parser or the checker rejected.
struct RejectedSource: Error {
    let diagnostics: [Diagnostic]
}

/// The IR that lowering makes of `source`, which the parser and the checker accept.
func loweredWithRanges(_ source: String) throws -> IRProgram {
    let (file, syntaxErrors) = Parser.parse(Array(source.utf8))
    guard syntaxErrors.isEmpty else { throw RejectedSource(diagnostics: syntaxErrors) }

    let (program, checkErrors) = Checker.check(file)
    guard let program else { throw RejectedSource(diagnostics: checkErrors) }

    return Lowering.lower(program)
}

/// The IR that lowering makes of `source`, with every source range in it `nowhere`, as the expected IR has them.
func lowered(_ source: String) throws -> IRProgram {
    let program = try loweredWithRanges(source)
    return IRProgram(functions: program.functions.map(\.erasingRanges), main: program.main)
}

/// The IR that lowering makes of `main`, given `body` as its body, with every source range in it `nowhere`.
func loweredMain(_ body: String) throws -> IRFunction {
    let program = try lowered("func main() {\n\(body)\n}")
    return program.functions[program.main.index]
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
            return .compute(destination: destination?.erasingRange, value: value.erasingRanges, range: nowhere)
        case .declare: return self
        }
    }
}

private extension Rvalue {
    var erasingRanges: Rvalue {
        switch self {
        case .use(let operand): return .use(operand.erasingRange)
        case .unary(let op, let operand): return .unary(op, operand.erasingRange)
        case .binary(let op, let left, let right): return .binary(op, left.erasingRange, right.erasingRange)
        case .call(let callee, let arguments): return .call(callee, arguments: arguments.map(\.erasingRange))
        }
    }
}

private extension Terminator {
    var erasingRanges: Terminator {
        switch self {
        case .branch(let condition, let then, let otherwise):
            return .branch(condition.erasingRange, then: then, otherwise: otherwise)
        case .return(let result): return .return(result?.erasingRange)
        case .goto, .unreachable: return self
        }
    }
}

private extension Operand {
    var erasingRange: Operand {
        switch self {
        case .read(let place): return .read(place.erasingRange)
        case .move(let place): return .move(place.erasingRange)
        case .constant: return self
        }
    }
}

private extension Place {
    var erasingRange: Place {
        Place(local: local, range: nowhere)
    }
}
