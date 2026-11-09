#include <llvm-c/Analysis.h>
#include <llvm-c/Core.h>
#include <llvm-c/IRReader.h>
#include <llvm-c/Linker.h>
#include <llvm-c/Target.h>
#include <llvm-c/TargetMachine.h>
#include <llvm-c/Transforms/PassBuilder.h>

// The directories of the tools that link a program, in the LLVM install that the package manifest found.
static const char *const RayoLLVMToolDirectory = RAYO_LLVM_TOOL_DIRECTORY;
static const char *const RayoLLDDirectory = RAYO_LLD_DIRECTORY;
