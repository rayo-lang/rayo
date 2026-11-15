import RayoDiagnostics
import RayoIR
import RayoOwnership
import RayoSema

/// What the ownership stage makes of `function`, checked as the first function of a program beside the `callees`, as
/// the pipeline runs the stage: its body with the end of each access written in, or nil where a check fails, and the
/// errors the checks report in it, in source order.
func checked(_ function: (name: String, text: String)) throws -> (body: IRBody?, errors: [Diagnostic]) {
    let (program, errors) = OwnershipChecker.check(try program(of: [function] + callees))
    let first = FunctionID(index: 0)
    return (program.bodies[first], errors[first] ?? [])
}
