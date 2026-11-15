import LLVM
import RayoSema

/// How LLVM holds the values of a scalar type: as integers of the type's width, whose bits its operations read as
/// signed or not. A Bool is a one-bit integer, which reads as unsigned.
struct NumberFormat: Equatable {
    /// The LLVM type that holds a value.
    let type: AnyIntegerType
    let signedness: Signedness

    /// The format of `scalar`'s values, whose LLVM type `maker` makes.
    init(of scalar: ScalarType, with maker: TypeMaker) {
        type = maker.integerType(bitWidth: scalar.bitWidth)
        signedness = scalar.isSigned ? .signed : .unsigned
    }

    /// The constant that holds `value`, which the format's type holds.
    func constant(_ value: Int128) -> AnyIntValue {
        // A value the type holds lies in its low bits, which a type of 64 bits or fewer takes all of.
        type.constant(Int64(truncatingIfNeeded: value))
    }

    /// `value`, which must be a value of this format, as LLVM holds one.
    func value(_ value: AnyValue) -> AnyIntValue {
        // The verifier passes no IR that gives an operation a value of another type.
        guard let integer = AnyIntValue(value), integer.bitWidth == type.bitWidth else {
            preconditionFailure("a value of this format is held as an i\(type.bitWidth)")
        }
        return integer
    }
}

/// How an integer type's operations read its bits: as a two's complement value, which may be negative, or as one
/// that can't be.
enum Signedness {
    case signed
    case unsigned

    /// The predicates that order two integers of this signedness as `<`, `<=`, `>` and `>=` do.
    var less: IntegerPredicate { self == .signed ? .signedLess : .unsignedLess }
    var lessEqual: IntegerPredicate { self == .signed ? .signedLessEqual : .unsignedLessEqual }
    var greater: IntegerPredicate { self == .signed ? .signedGreater : .unsignedGreater }
    var greaterEqual: IntegerPredicate { self == .signed ? .signedGreaterEqual : .unsignedGreaterEqual }
}
