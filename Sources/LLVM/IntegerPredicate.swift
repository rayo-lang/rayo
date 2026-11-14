internal import CLLVM

/// What a comparison of two integers tests.
public enum IntegerPredicate: Equatable, Sendable {
    case equal
    case notEqual
    case signedLess
    case signedLessEqual
    case signedGreater
    case signedGreaterEqual
    case unsignedLess
    case unsignedLessEqual
    case unsignedGreater
    case unsignedGreaterEqual

    var llvmPredicate: LLVMIntPredicate {
        switch self {
        case .equal: LLVMIntEQ
        case .notEqual: LLVMIntNE
        case .signedLess: LLVMIntSLT
        case .signedLessEqual: LLVMIntSLE
        case .signedGreater: LLVMIntSGT
        case .signedGreaterEqual: LLVMIntSGE
        case .unsignedLess: LLVMIntULT
        case .unsignedLessEqual: LLVMIntULE
        case .unsignedGreater: LLVMIntUGT
        case .unsignedGreaterEqual: LLVMIntUGE
        }
    }
}
