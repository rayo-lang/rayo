import LLVM

/// The functions of the program runtime that a program calls, declared in the program's module.
struct RuntimeFunctions {
    let printInt: Function
    let printBool: Function
    let panic: Function
}
