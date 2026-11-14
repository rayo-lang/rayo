import RayoIR
import RayoSema

/// The accesses that the value each local holds depends on at a point, and those that each access depends on through
/// the place it reaches. A local or an access left out depends on none.
struct DependencyState: DataflowState {
    /// The accesses each local's value depends on, by the local's ID, wherever in the local the value lies; a local
    /// whose value depends on none is left out.
    private(set) var dependentLocals: [LocalID: Set<AccessID>] = [:]
    /// The accesses each access depends on, by its ID: those its place's value depended on as it began.
    private var accesses: [AccessID: Set<AccessID>] = [:]

    /// The state on entry to a function, where no value depends on an access, since none has begun.
    init() {}

    func merged(with other: DependencyState) -> DependencyState {
        var merged = self
        merged.dependentLocals.merge(other.dependentLocals) { $0.union($1) }
        merged.accesses.merge(other.accesses) { $0.union($1) }
        return merged
    }

    /// The accesses that `access` depends on.
    func dependencies(of access: AccessID) -> Set<AccessID> {
        accesses[access] ?? []
    }

    /// Applies what `statement` does to the dependencies.
    mutating func apply(_ statement: Statement) {
        switch statement {
        // A computation's destination takes on what its value depends on.
        case .compute(let destination?, let value, _):
            store(dependencies(of: value), in: destination.place)

        // A declaration starts a local's life without a value, so it depends on nothing.
        case .declare(let local):
            dependentLocals[local] = nil

        // An access depends on what its place's value depends on, since the code reaches that value through it.
        case .begin(let id, let access):
            accesses[id] = dependentLocals[access.place.root] ?? []

        // The value at the place now depends on the access too, and on what the access depends on.
        case .depend(let place, let id):
            dependentLocals[place.root, default: []].formUnion(dependencies(of: id).union([id]))

        // A computation that drops its value, or the end of an access, changes no value's dependencies.
        case .compute(nil, _, _), .end:
            break
        }
    }

    /// The accesses that the value `value` makes depends on. A copy of a value, or a move of one, carries what the
    /// value depends on. So does a call's result, of what the values the call is passed as they are depend on, since
    /// it may hold them, as a struct that its primary initializer makes does. An operator's result is an Int or a
    /// Bool, which depends on nothing.
    private func dependencies(of value: Rvalue) -> Set<AccessID> {
        switch value {
        case .operand, .call:
            value.operands.reduce(into: []) { dependencies, operand in
                if let place = operand.place { dependencies.formUnion(dependentLocals[place.root] ?? []) }
            }
        case .unary, .binary:
            []
        }
    }

    /// Stores a value that depends on `dependencies` in `place`. A value stored in a whole local replaces the old
    /// one and what it depended on; one stored in a part of it adds to what the local's value depends on.
    private mutating func store(_ dependencies: Set<AccessID>, in place: Place) {
        if place.steps.isEmpty {
            dependentLocals[place.root] = dependencies.isEmpty ? nil : dependencies
        } else if !dependencies.isEmpty {
            dependentLocals[place.root, default: []].formUnion(dependencies)
        }
    }
}
