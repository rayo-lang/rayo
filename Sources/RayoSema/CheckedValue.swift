import RayoCheckedProgram

/// What checking an expression gives before its position is known: a typed value, or one that waits for its position
/// to settle its type.
enum CheckedValue {
    case typed(CheckedExpr)
    case waiting(any WaitingValue)

    /// The value's type, where it has one or a part of it fixes one; nil where its position settles it.
    var type: RayoType? {
        switch self {
        case .typed(let value): value.type
        case .waiting(let value): value.type
        }
    }

    /// The value's type, or the type it settles to where its position gives none. Nil for a value that can't settle
    /// then, such as `[]`, or an implicit member, which names a member of no type until its position gives one.
    var typeOrDefault: RayoType? {
        switch self {
        case .typed(let value): value.type
        case .waiting(let value): value.defaultType
        }
    }

    /// How many levels of array types, each the element of the one around it, any type the value settles to nests at
    /// the least.
    var arrayLevels: Int {
        switch self {
        case .typed(let value): value.type.arrayLevels
        case .waiting(let value): value.arrayLevels
        }
    }

    /// Whether the value fits `type`, as a call asks when it picks among overloads, where `declarations` gives the
    /// members an implicit member names. An integer literal's value counts, so it fits only a type that holds it.
    func fits(_ type: RayoType, in declarations: Declarations) -> Bool {
        switch self {
        case .typed(let value): TypeFit.fits(value.type, type)
        case .waiting(let value): value.fits(type, in: declarations)
        }
    }

    /// Whether a position that expects `type` takes the value, though a literal in it may be one `type` can't hold.
    func canSettle(to type: RayoType, in declarations: Declarations) -> Bool {
        switch self {
        case .typed(let value): TypeFit.fits(value.type, type)
        case .waiting(let value): value.canSettle(to: type, in: declarations)
        }
    }

    /// Whether the source writes the value as a `&` of a place.
    var lendsPlace: Bool {
        switch self {
        case .typed: false
        case .waiting(let value): value.lendsPlace
        }
    }

    /// Whether the value, or any branch of it that runs to its end, is written as a `&` of a place.
    var mayLendPlace: Bool {
        switch self {
        case .typed: false
        case .waiting(let value): value.mayLendPlace
        }
    }

    /// Whether the source writes the value as a `mutable` of a place.
    var lendsForChange: Bool {
        switch self {
        case .typed: false
        case .waiting(let value): value.lendsForChange
        }
    }

    /// The one type that values standing side by side, such as an array literal's elements or an `if`'s branches,
    /// settle to where their position gives none, from each value's own type and its type or default. The first type
    /// a value fixes wins, so an untyped value takes the typed values' type; where none fixes one, the first default
    /// among them does. Nil where no value gives a type.
    static func agreedType(of values: [(type: RayoType?, typeOrDefault: RayoType?)]) -> RayoType? {
        values.lazy.compactMap(\.type).first ?? values.lazy.compactMap(\.typeOrDefault).first
    }
}
