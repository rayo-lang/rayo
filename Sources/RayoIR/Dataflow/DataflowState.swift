/// The state of a dataflow analysis at a point of a function: what the analysis knows there, such as what each local
/// holds. The state says which way a walk through the function's control-flow graph carries it, and what each effect
/// of a statement or terminator does to it, and `DataflowSolver` carries it through the blocks.
package protocol DataflowState: Equatable {
    /// What the state needs to know of the function it is carried through to take it across an effect, such as the
    /// types of the function's places; `Void` where it needs nothing.
    associatedtype Function

    var direction: DataflowDirection { get }

    /// The state where a path on which `self` holds meets one on which `other` does. A merge only grows a state: what
    /// it returns holds all that each of the two holds, so merging either of them into it again changes nothing. A
    /// state can grow only so far, which is what brings the solver to a stop.
    func merged(with other: Self) -> Self

    /// Takes the state across `effect`, an effect in `function`, in its direction: from just before the effect to just
    /// after it going forward, and from just after it to just before it going backward.
    mutating func apply(_ effect: Effect, in function: Function)

    /// Takes the state across all of `block` in `function`, whose statements and terminator have `effects`, in its
    /// direction. A state may work out once what a whole block does to it, and apply that here.
    mutating func apply(acrossBlock block: BlockID, effects: [[Effect]], in function: Function)
}

extension DataflowState {
    /// Takes the state across `effects`, the effects of one statement or terminator in `function`, in its direction:
    /// in their order going forward, and in reverse going backward.
    package mutating func apply(_ effects: [Effect], in function: Function) {
        switch direction {
        case .forward:
            for effect in effects { apply(effect, in: function) }
        case .backward:
            for effect in effects.reversed() { apply(effect, in: function) }
        }
    }

    /// Takes the state across each statement and the terminator in turn.
    package mutating func apply(acrossBlock block: BlockID, effects: [[Effect]], in function: Function) {
        let ordered = direction == .forward ? effects : effects.reversed()
        for crossing in ordered {
            apply(crossing, in: function)
        }
    }
}
