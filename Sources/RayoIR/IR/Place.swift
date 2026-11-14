import RayoSema

/// A local, or a part of one that steps from the local lead to. Two places are equal where they take the same steps
/// from the same local, wherever the source names each.
public struct Place: Hashable, Sendable {
    public var root: LocalID
    /// The steps from the root to the place, outermost first; none where the place is the whole local.
    public var steps: [PlaceStep]

    public init(root: LocalID, steps: [PlaceStep] = []) {
        self.root = root
        self.steps = steps
    }

    /// The place that `step` leads to from this one.
    public func appending(_ step: PlaceStep) -> Place {
        Place(root: root, steps: steps + [step])
    }

    /// The place that the first `count` steps lead to, which holds this one.
    public func prefix(_ count: Int) -> Place {
        Place(root: root, steps: Array(steps.prefix(count)))
    }

    /// The locals that hold the indices of the elements the place steps into, in the order of its steps. Finding the
    /// place reads each of them.
    public var indexLocals: [LocalID] {
        steps.compactMap { step in
            guard case .elementAt(let local) = step else { return nil }
            return local
        }
    }

    /// The type of the value at the place in `body`, a body of a program whose structs `types` holds, and which holds
    /// the place's root. Throws the first step that leads into a part the value it steps from doesn't have.
    public func type(in body: IRBody, types: TypeTable) throws(UnfitStep) -> RayoType {
        var type = body.locals[root.index].type
        for step in steps {
            // A step must lead into a part of the value it steps from.
            guard let part = step.type(from: type, in: body, types: types) else { throw UnfitStep(step, from: type) }
            type = part
        }
        return type
    }

    /// Whether `other` is this place or lies inside it, by the same steps. So an element at an index a local holds
    /// contains only the places that step through it by the same local.
    public func contains(_ other: Place) -> Bool {
        root == other.root && other.steps.starts(with: steps)
    }

    /// Whether this place and `other` may overlap: whether one may lie inside the other. Two fields of one value lie
    /// apart, and so do two elements of one array at different indices the IR writes, and the places inside each.
    /// An element at an index a local holds may be any element of its array.
    public func overlaps(_ other: Place) -> Bool {
        root == other.root && zip(steps, other.steps).allSatisfy { $0.mayLeadToSamePart(as: $1) }
    }
}
