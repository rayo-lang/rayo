extension Statement {
    /// What the statement does to places, accesses and locals' lives, in the order it does them.
    public var effects: [Effect] {
        switch self {
        case .compute(let destination, let value, _): Self.effects(computing: value, storingIn: destination)
        // An access finds its place where it begins.
        case .begin(let id, let access): access.place.indexReads(at: access.range) + [.begin(id, access)]
        case .end(let id): [.end(id)]
        case .depend(let place, let id): [.depend(place, on: id)]
        case .declare(let local): [.declare(local)]
        case .retire(let local): [.retire(local)]
        }
    }

    /// What a computation of `value` does, storing it in `destination` where it has one: it finds its operands' values
    /// and runs, holding the accesses a call passes, before it finds its destination and stores the value there.
    private static func effects(computing value: Rvalue, storingIn destination: Destination?) -> [Effect] {
        let running = value.operands.flatMap(\.effects) + value.accesses.map(Effect.use)
        guard let destination else { return running }
        return running + destination.place.indexReads(at: destination.range) + [.store(destination)]
    }
}
