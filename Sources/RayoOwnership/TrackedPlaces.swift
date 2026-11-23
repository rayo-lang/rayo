import RayoCheckedProgram
import RayoIR

/// The places of one body that the initialization check follows, each with a number: every local, numbered by its
/// `LocalID`, then each part of a local that the body moves out of.
struct TrackedPlaces {
    /// Indexed by number.
    private var places: [Place]
    /// The number of each tracked part.
    private var partNumbers: [Place: Int] = [:]
    /// The numbers of the tracked parts of each local, indexed by `LocalID`.
    private var partsByLocal: [[Int]]

    init(_ body: IRBody) {
        places = body.locals.indices.map { Place(root: LocalID(index: $0)) }
        partsByLocal = Array(repeating: [], count: body.locals.count)
        for effect in body.blocks.flatMap(\.effects).joined() {
            guard case .move(let place, _) = effect, !place.steps.isEmpty, partNumbers[place] == nil else { continue }
            partNumbers[place] = places.count
            partsByLocal[place.root.index].append(places.count)
            places.append(place)
        }
    }

    var count: Int { places.count }

    subscript(number: Int) -> Place {
        places[number]
    }

    /// The number of `place`, or nil where it is a part that the body never moves out of.
    func number(of place: Place) -> Int? {
        place.steps.isEmpty ? place.root.index : partNumbers[place]
    }

    /// The numbers of the tracked parts of `local`, the local itself left out.
    func parts(of local: LocalID) -> [Int] {
        partsByLocal[local.index]
    }
}
