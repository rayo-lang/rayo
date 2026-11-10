internal import CLLVM
import RayoSema

/// The LLVM types that hold a program's values.
struct LLVMTypes {
    private let module: ModuleBuilder

    init(in module: ModuleBuilder) {
        self.module = module
    }

    /// The LLVM type that holds a value of `type`, or that a function returns when it returns nothing.
    func llvmType(_ type: RayoType) -> LLVMTypeRef {
        switch type {
        case .int: return module.int64
        case .bool: return module.bool
        case .void: return module.void
        }
    }
}
