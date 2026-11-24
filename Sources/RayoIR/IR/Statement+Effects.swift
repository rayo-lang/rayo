extension Statement {
    /// What the statement does to places, accesses and locals' lives, in the order it does them.
    public var effects: [Effect] {
        var effects: [Effect] = []
        forEachEffect { effects.append($0) }
        return effects
    }

    /// Lends `visit` each of the statement's effects in turn, and stops where it throws.
    package func forEachEffect<Failure: Error>(_ visit: (Effect) throws(Failure) -> Void) throws(Failure) {
        switch self {
        case .compute(let destination, let value, _):
            try Self.forEachEffect(computing: value, storingIn: destination, visit)
        // An access finds its place where it begins.
        case .begin(let id, let access):
            try access.place.forEachIndexRead(at: access.range, visit)
            try visit(.begin(id, access))
        case .end(let id): try visit(.end(id))
        case .depend(let place, let id): try visit(.depend(place, on: id))
        case .declare(let local): try visit(.declare(local))
        case .retire(let local): try visit(.retire(local))
        }
    }

    /// Lends `visit` what a computation of `value` does, storing it in `destination` where it has one: it finds its
    /// operands' values and runs, holding the accesses a call passes, before it finds its destination and stores the
    /// value there.
    private static func forEachEffect<Failure: Error>(
        computing value: Rvalue, storingIn destination: Destination?, _ visit: (Effect) throws(Failure) -> Void,
    ) throws(Failure) {
        try value.forEachOperand { operand throws(Failure) in try operand.forEachEffect(visit) }
        try value.forEachAccess { access throws(Failure) in try visit(.use(access)) }

        guard let destination else { return }
        try destination.place.forEachIndexRead(at: destination.range, visit)
        try visit(.store(destination))
    }
}
