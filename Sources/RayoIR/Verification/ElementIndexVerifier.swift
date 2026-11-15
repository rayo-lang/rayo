import RayoSema

/// Checks that each step of one function's body into an element at an index a local holds needs no check of its own:
/// the local is a temporary, and every statement that changes it stores an index that an `index` operation checked
/// against the count of the array the step indexes. The emitter loads the index and finds the element with no check,
/// so the `index` operation's check is the only one the program makes.
struct ElementIndexVerifier {
    private let body: IRBody
    private let types: TypeTable
    /// The name of the function whose body this is, which a violation names.
    private let function: String
    /// For each local that some statement changes, the count that each such statement checks the value it stores
    /// against, or nil for one that changes the local without such a check.
    private let checkedCounts: [LocalID: [Int?]]

    /// A verifier of `body`, the body of `function` in a program whose structs `types` holds, and whose types the
    /// verifier of its types has passed.
    init(body: IRBody, of function: String, types: TypeTable) {
        self.body = body
        self.types = types
        self.function = function
        checkedCounts = Self.checkedCounts(in: body)
    }

    /// Throws for the first element step found whose index isn't checked against its array's count.
    func verify() throws(IRViolation) {
        for place in Self.places(in: body) {
            try verifyIndices(in: place)
        }
    }

    /// Throws where a step of `place` into an element at an index a local holds needs a check of its own.
    private func verifyIndices(in place: Place) throws(IRViolation) {
        var type = body.locals[place.root.index].type
        for step in place.steps {
            if case .elementAt(let local) = step, case .array(let count, _) = type {
                try verifyIndex(local, below: count)
            }
            guard let part = step.type(from: type, in: body, types: types) else {
                preconditionFailure("the IR's types are verified before its indices")
            }
            type = part
        }
    }

    /// Throws where `local` isn't a temporary, or a statement changes it without checking the value it stores is
    /// below `count`.
    private func verifyIndex(_ local: LocalID, below count: Int) throws(IRViolation) {
        let indexing = "the IR indexes an array of \(count) elements at %\(local.index)"
        guard case .temporary = body.locals[local.index] else {
            throw IRViolation(function: function, message: "\(indexing), which is no temporary")
        }
        guard checkedCounts[local, default: []].allSatisfy({ $0 == count }) else {
            let message = "\(indexing), which it changes without checking it is below \(count)"
            throw IRViolation(function: function, message: message)
        }
    }

    /// For each local of `body` that a statement changes, the count that each such statement checks the value it
    /// stores against, or nil for one that changes the local without such a check.
    private static func checkedCounts(in body: IRBody) -> [LocalID: [Int?]] {
        var counts: [LocalID: [Int?]] = [:]
        for block in body.blocks {
            for statement in block.statements {
                switch statement {
                // A store of an index checks its value; any other store doesn't.
                case .compute(let destination?, let value, _):
                    let checked: Int? = if case .index(_, let count) = value { count } else { nil }
                    counts[destination.place.root, default: []].append(checked)

                // A modify access lets a call store any value there.
                case .begin(_, let access) where access.kind == .modify:
                    counts[access.place.root, default: []].append(nil)

                default:
                    break
                }
            }
        }
        return counts
    }

    /// The places that `body` names: those its operands read or move, then those its statements store to, begin an
    /// access to, or make depend on an access.
    private static func places(in body: IRBody) -> [Place] {
        let read = body.blocks.flatMap(\.operands).compactMap(\.place)
        let reached = body.blocks.flatMap(\.statements).compactMap { statement -> Place? in
            switch statement {
            case .compute(let destination, _, _): destination?.place
            case .begin(_, let access): access.place
            case .depend(let place, _): place
            case .declare, .end: nil
            }
        }
        return read + reached
    }
}
