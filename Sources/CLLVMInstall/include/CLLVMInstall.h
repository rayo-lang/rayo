#ifndef RAYO_CLLVM_INSTALL_H
#define RAYO_CLLVM_INSTALL_H

/// The major release of the LLVM install that the package manifest found.
extern const int RayoLLVMMajorVersion;

/// The directory that holds that install's tools, clang among them.
extern const char *const RayoLLVMToolDirectory;

/// The directory that holds the LLD that the package manifest found, which some package managers install apart
/// from LLVM.
extern const char *const RayoLLDDirectory;

#endif
