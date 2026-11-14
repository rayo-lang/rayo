#include "CLLVMInstall.h"

// The package manifest defines these values for this target alone, so no target that reads them is built against
// LLVM's headers.
const int RayoLLVMMajorVersion = RAYO_LLVM_MAJOR_VERSION;
const char *const RayoLLVMToolDirectory = RAYO_LLVM_TOOL_DIRECTORY;
const char *const RayoLLDDirectory = RAYO_LLD_DIRECTORY;
