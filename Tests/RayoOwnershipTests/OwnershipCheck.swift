import RayoDiagnostics
import RayoIR
import RayoOwnership
import RayoSema

/// What the ownership stage makes of `function`, checked as the first function of a program beside the `callees` and
/// `others`, as the pipeline runs the stage: its body with the end of each access and the retirement of each local
/// written in, or nil where a check fails, and the errors the checks report in it, in source order.
func checked(
    _ function: (name: String, text: String), beside others: [(name: String, text: String)] = [],
) throws -> (body: IRBody?, errors: [Diagnostic]) {
    let (program, errors) = OwnershipChecker.check(try program(of: [function] + callees + others))
    let first = FunctionID(index: 0)
    return (program.bodies[first], errors[first] ?? [])
}

/// The body of a function of `blocks`, with the locals `function` gives it, once the ownership stage has written the
/// ends of its accesses and the retirements of its locals into it, or nil where a check fails.
func ended(_ blocks: String) throws -> IRBody? {
    try checked(function(blocks)).body
}

/// The body of a function of `blocks`, as the text writes it.
func body(of blocks: String) throws -> IRBody? {
    try program(of: [function(blocks)] + callees).bodies[FunctionID(index: 0)]
}
