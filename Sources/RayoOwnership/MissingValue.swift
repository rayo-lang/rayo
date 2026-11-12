/// Why a use of a place may find no value there, with each field named by the fields that lead to it from the
/// place's local, outermost first.
enum MissingValue {
    /// The local, where `fields` is empty, or the field at `fields`, which is the place or holds it, may hold no
    /// value, as `state` says.
    case missing(fields: [Int], state: PlaceState)
    /// The field at `fields`, inside the place, may have been moved out of it, as `state` says, so the place may
    /// hold only part of its value.
    case partlyMoved(fields: [Int], state: PlaceState)

    /// The fields that lead to the local or field that may hold no value.
    var fields: [Int] {
        switch self {
        case .missing(let fields, _), .partlyMoved(let fields, _): fields
        }
    }

    /// What the local or field that may hold no value holds.
    var state: PlaceState {
        switch self {
        case .missing(_, let state), .partlyMoved(_, let state): state
        }
    }
}
