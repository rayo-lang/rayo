import RayoSema

/// A local, or a part of one that steps from the local lead to. Two places are equal where they name the same part of
/// the same local, wherever the source names each.
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

    /// The type of the value at the place in `body`, a body of a program whose structs `types` holds. Each step must
    /// lead into a field that the value it steps from has.
    public func type(in body: IRBody, types: TypeTable) -> RayoType {
        var type = body.locals[root.index].type
        for step in steps {
            // A step that leads nowhere breaks the precondition.
            guard let field = step.field(of: type, in: types) else {
                preconditionFailure("\(step) leads into no field of a value of type \(type)")
            }
            type = field.type
        }
        return type
    }

    /// Whether `other` is this place or lies inside it.
    public func contains(_ other: Place) -> Bool {
        root == other.root && other.steps.starts(with: steps)
    }
}
