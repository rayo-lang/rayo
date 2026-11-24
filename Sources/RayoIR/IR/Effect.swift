import RayoCheckedProgram
import RayoSource

/// One thing a statement or terminator does to a place, an access or a local's life. A statement or terminator has its
/// effects in order, and each analysis of a function's places works out what it needs from them alone.
public enum Effect: Equatable, Sendable {
    /// Reads the value at the place, which keeps it. The range is where the source names the place; for a local read
    /// for the index it holds, it is where the source names the place that the index finds an element of.
    case read(Place, at: SourceRange)
    /// Moves the value out of the place, which then holds no value until a store gives it one. The range is where the
    /// source names the place.
    case move(Place, at: SourceRange)
    /// Stores a value in the destination's place, replacing whatever the place held.
    case store(Destination)
    /// Begins the access, which reaches the value its place holds from here until it ends.
    case begin(AccessID, Access)
    /// Reaches a place through the access, as a call does that passes the access to a parameter.
    case use(AccessID)
    /// Ends the access, after which nothing reaches its place through it.
    case end(AccessID)
    /// Makes the value at the place depend on the access, which stays live from here for as long as code uses the
    /// value. The value stays where it is, and nothing reads it.
    case depend(Place, on: AccessID)
    /// Starts the life of the local, which holds no value until a store gives it one.
    case declare(LocalID)
    /// Ends the life of the local, which holds no value from here until a declaration starts its life again.
    case retire(LocalID)
    /// Leaves the function, after which its caller reads what each parameter it passed by access holds.
    case exit

    /// The place the effect names: the one it reads, moves, stores to, begins an access to or makes depend on one.
    /// Nil for an effect that names only an access or a local, or none.
    var place: Place? {
        switch self {
        case .read(let place, _), .move(let place, _), .depend(let place, _): place
        case .store(let destination): destination.place
        case .begin(_, let access): access.place
        case .use, .end, .declare, .retire, .exit: nil
        }
    }
}
