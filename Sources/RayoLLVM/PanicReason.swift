/// Why a program panics, as its panic message says.
enum PanicReason: String {
    case overflow = "integer overflow"
    case divisionByZero = "division by zero"
    case remainderByZero = "remainder by zero"
    case indexOutOfRange = "index out of range"
}
