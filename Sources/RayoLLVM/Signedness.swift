import LLVM

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
