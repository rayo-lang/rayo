/// A type whose value is one number or truth value, which no part of a program splits: one of the prelude's integer
/// types, or Bool. It holds the type's name and what its values are, which give everything else about it.
public struct ScalarType: Hashable, Sendable, CustomStringConvertible {
    /// What a scalar type's values are.
    public enum Kind: Hashable, Sendable {
        /// Integers of `width` bits, in two's complement where they are signed.
        case integer(width: Int, isSigned: Bool)
        /// `true` and `false`.
        case bool
    }

    /// The name the prelude declares the type under. Two types may have values of one kind, as `Int` and `Int64`
    /// do, and still be distinct, so the name tells them apart.
    public let name: String
    public let kind: Kind

    private init(name: String, kind: Kind) {
        self.name = name
        self.kind = kind
    }

    /// `Int`, the default integer type, which is 64 bits on every target.
    public static let int = ScalarType(name: "Int", kind: .integer(width: 64, isSigned: true))
    /// `UInt`, which is 64 bits on every target.
    public static let uint = ScalarType(name: "UInt", kind: .integer(width: 64, isSigned: false))
    public static let bool = ScalarType(name: "Bool", kind: .bool)

    /// The scalar types the prelude declares, in the order it declares their built-ins.
    public static let prelude: [ScalarType] = [.int, .uint, .bool]

    public var description: String { name }

    /// Whether the type is an integer type, which arithmetic and orderings take.
    public var isInteger: Bool {
        if case .integer = kind { true } else { false }
    }

    /// Whether an integer of the type reads its top bit as a sign. Bool has no sign.
    public var isSigned: Bool {
        if case .integer(_, let isSigned) = kind { isSigned } else { false }
    }

    /// The bits a value of the type holds: an integer's width, and one bit for a Bool.
    public var bitWidth: Int {
        switch kind {
        case .integer(let width, _): width
        case .bool: 1
        }
    }

    /// How a value of the type lies in memory: an integer in as many bytes as its width fills, aligned to that many,
    /// and a Bool in one byte.
    public var layout: Layout {
        switch kind {
        case .integer(let width, _): Layout(size: width / 8, alignment: width / 8)
        case .bool: Layout(size: 1, alignment: 1)
        }
    }

    /// The values an integer literal of the type can have, or nil where the type takes no integer literal.
    public var literalRange: ClosedRange<Int128>? {
        guard case .integer(let width, let isSigned) = kind else { return nil }
        let top = Int128(1) << (isSigned ? width - 1 : width)
        return isSigned ? -top...(top - 1) : 0...(top - 1)
    }

    /// Whether `T(_: U)`, with `T` this type and `U` `source`, converts a value of `source` to this type. Each
    /// integer type converts from every integer type, its own among them, and Bool from none.
    public func converts(from source: ScalarType) -> Bool {
        isInteger && source.isInteger
    }
}
