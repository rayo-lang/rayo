/// Checks that one function's body holds no end of an access and no retirement of a local, as the IR lowering gives
/// must: the ownership stage writes each of them, once it has found where each access and each local's life ends.
struct LoweredStatementVerifier {
    private let body: IRBody
    /// The name of the function whose body this is, which a violation names.
    private let function: String

    init(body: IRBody, of function: String) {
        self.body = body
        self.function = function
    }

    /// Throws for the first end or retirement found, in the order of the blocks and then of their statements. Every
    /// block is checked, whether or not a path reaches it, since lowering writes neither statement in any of them.
    func verify() throws(IRViolation) {
        for (index, block) in body.blocks.enumerated() {
            for statement in block.statements {
                let message: String? = switch statement {
                case .end(let id):
                    "the IR ends a\(id.index) at bb\(index), though only the ownership stage ends an access"
                case .retire(let local):
                    "the IR retires %\(local.index) at bb\(index), though only the ownership stage retires a local"
                case .compute, .declare, .begin: nil
                }
                if let message { throw IRViolation(function: function, message: message) }
            }
        }
    }
}
