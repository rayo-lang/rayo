/// Where a `return`, a `break` and a `continue` in the code being checked leave for: the function's result, and the
/// loops around the code.
struct JumpTargets {
    /// The function's result type, or nil when it isn't known.
    let result: RayoType?
    /// How many loops enclose the code.
    private(set) var loops = 0

    init(result: RayoType?) {
        self.result = result
    }

    /// The targets of the code in the body of a loop that this code holds.
    var insideLoop: JumpTargets {
        var inside = self
        inside.loops += 1
        return inside
    }
}
