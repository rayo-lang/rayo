internal import CLLVM
import RayoSema

/// The LLVM types of a program's values, and of a function's result.
struct LLVMTypes {
    private let module: ModuleBuilder

    init(in module: ModuleBuilder) {
        self.module = module
    }

    /// The LLVM type that holds a value of `type`, or that a function returns when it returns nothing.
    func llvmType(_ type: RayoType) -> LLVMTypeRef {
        switch type {
        case .int: module.int64
        case .bool: module.bool
        case .void: module.void
        }
    }
}
