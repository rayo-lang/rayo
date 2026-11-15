import RayoSema

/// Checks that one function's body finds each element at an index a local holds only where an `index` operation
/// checked that index against the array's count. The emitter loads such an index and finds the element with no check
/// of its own, so that operation's check is the only one the program makes.
struct ElementIndexVerifier {
    /// How a statement changes a local: by storing an index that an `index` operation checked against a count, or in
    /// any other way.
    private enum Change: Equatable {
        case checked(below: Int)
        case unchecked
    }

    private let body: IRBody
    private let types: TypeTable
    /// The name of the function whose body this is, which a violation names.
    private let function: String
    /// How each statement that changes a local changes it, for each local that some statement changes.
    private let changes: [LocalID: [Change]]

    /// A verifier of `body`, the body of `function` in a program whose structs `types` holds. The body's types must
    /// already have passed their own check.
    init(body: IRBody, of function: String, types: TypeTable) {
        self.body = body
        self.types = types
        self.function = function
        changes = Self.changes(in: body)
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

    /// Throws where `local` isn't a temporary, no statement stores it, or a statement changes it without checking the
    /// value it stores is below `count`.
    private func verifyIndex(_ local: LocalID, below count: Int) throws(IRViolation) {
        let indexing = "the IR indexes an array of \(count) elements at %\(local.index)"
        guard case .temporary = body.locals[local.index] else {
            throw violation("\(indexing), which isn't a temporary")
        }
        // A temporary that nothing stores holds no index at all.
        guard let changes = changes[local] else { throw violation("\(indexing), which no statement stores") }
        guard changes.allSatisfy({ $0 == .checked(below: count) }) else {
            throw violation("\(indexing), which it changes without checking it is below \(count)")
        }
    }

    /// How each statement of `body` that changes a local changes it, for each local that some statement changes.
    private static func changes(in body: IRBody) -> [LocalID: [Change]] {
        var changes: [LocalID: [Change]] = [:]
        for block in body.blocks {
            for statement in block.statements {
                switch statement {
                case .compute(let destination?, let value, _):
                    changes[destination.place.root, default: []].append(change(storing: value))

                // A modify access lets a call store any value there.
                case .begin(_, let access) where access.kind == .modify:
                    changes[access.place.root, default: []].append(.unchecked)

                default:
                    break
                }
            }
        }
        return changes
    }

    /// How a store of `value` changes the local it stores to: a store of an index checks its value, and any other
    /// store doesn't.
    private static func change(storing value: Rvalue) -> Change {
        guard case .index(_, let count) = value else { return .unchecked }
        return .checked(below: count)
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

    /// The violation that `message` says, in this function.
    private func violation(_ message: String) -> IRViolation {
        IRViolation(function: function, message: message)
    }
}
