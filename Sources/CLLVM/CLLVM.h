#include <llvm-c/Analysis.h>
#include <llvm-c/Core.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>
#include <llvm-c/Transforms/PassBuilder.h>

// The directory of the tools of the LLVM install that the package manifest found.
static const char *const RayoLLVMToolDirectory = RAYO_LLVM_TOOL_DIRECTORY;
