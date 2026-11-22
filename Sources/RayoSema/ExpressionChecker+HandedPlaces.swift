import RayoCheckedProgram
import RayoDiagnostics

extension ExpressionChecker {
    /// Reports each place rooted in a local that `value` hands its position to, with the error `code` gives for the
    /// place's name. A position that takes its value but can't borrow it, such as a `var`'s declaration or an
    /// assignment, has its places reported so, since nothing written says whether to copy the value or move it.
    func reportHandedPlaces(of value: CheckedExpr, as code: (String) -> ErrorCode) {
        for handed in value.handedPlaces {
            file.errors.report(code(sourceName(of: handed)), at: handed.place.range)
        }
    }

    /// The name of `place` as the source writes it, such as `e.stats.hp` or `g[i][0]`, for an error to name it by.
    /// An index the source writes as anything but an integer literal or a local's bare name is written `…`, since the
    /// checked program keeps no text for it.
    private func sourceName(of place: HandedPlace) -> String {
        var name = names[place.local].name
        var type = names[place.local].type
        for step in place.place.steps {
            let part = written(step, from: type)
            name += part.text
            type = part.type
        }
        return name
    }

    /// `step` as the source writes it after the value of `type` it steps from, such as `.hp` or `[i]`, and the type
    /// of the part it leads to.
    private func written(_ step: CheckedPlaceStep, from type: RayoType) -> (text: String, type: RayoType) {
        switch (step, type) {
        // A field takes its name from the struct that holds it.
        case (.field(let index, _), .named(.structure(let id))):
            file.declarations.types.fields(of: id)[index].writtenStep
        // An element takes its index, where the source writes one that has a name.
        case (.element(let index, _, _), .array(_, let element)):
            ("[\(indexName(of: index))]", element)
        // Checking steps into a field only of a struct, and into an element only of an array.
        default:
            preconditionFailure("a place steps into a part that its value doesn't have")
        }
    }

    /// The index of an element as an error writes it: an integer literal's value, a local's bare name, or `…`.
    private func indexName(of index: CheckedExpr) -> String {
        switch index.kind {
        case .integerLiteral(let value, _): "\(value)"
        case .place(let place) where place.steps.isEmpty:
            if case .local(let local, _) = place.root { names[local].name } else { "…" }
        default: "…"
        }
    }
}

private extension Field {
    /// The step into the field as the source writes it after the struct that holds it, such as `.hp`, and the
    /// field's type.
    var writtenStep: (text: String, type: RayoType) {
        ("." + name, type)
    }
}
