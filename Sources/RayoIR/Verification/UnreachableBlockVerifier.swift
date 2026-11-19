/// Checks that no path from the entry of one function's body reaches a block that ends in `unreachable`. The emitter
/// gives such a block LLVM's `unreachable`, so a run that reached it would have undefined behaviour. A path follows
/// every successor of a terminator, including both blocks of a branch on a constant.
struct UnreachableBlockVerifier {
    private let body: IRBody
    /// The name of the function whose body this is, which a violation names.
    private let function: String

    init(body: IRBody, of function: String) {
        self.body = body
        self.function = function
    }

    /// Throws for the first block that ends in `unreachable` on a walk of the blocks a path from the entry reaches,
    /// breadth first.
    func verify() throws(IRViolation) {
        // The blocks reached so far, in the order the walk reaches them, starting at the entry, and whether the walk
        // has reached each block, by its index.
        var reached = [BlockID(index: 0)]
        var isReached = Array(repeating: false, count: body.blocks.count)
        isReached[0] = true
        var next = 0

        // No reached block may end in `unreachable`, and the blocks it goes on to are reached too.
        while next < reached.count {
            let block = reached[next]
            next += 1
            let terminator = body.blocks[block.index].terminator
            guard terminator != .unreachable else {
                let message = "the IR reaches bb\(block.index), which ends in unreachable"
                throw IRViolation(function: function, message: message)
            }
            for successor in terminator.successors where !isReached[successor.index] {
                isReached[successor.index] = true
                reached.append(successor)
            }
        }
    }
}
