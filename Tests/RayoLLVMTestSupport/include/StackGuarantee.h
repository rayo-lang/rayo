#ifndef RAYO_LLVM_TEST_SUPPORT_STACK_GUARANTEE_H
#define RAYO_LLVM_TEST_SUPPORT_STACK_GUARANTEE_H

#ifdef _WIN32
/// Runs `start` on a thread of its own, and returns the size in bytes of the stack that thread keeps for handling a
/// stack overflow once `start` returns.
unsigned long rayo_stack_guarantee_after(void (*start)(void));
#endif

#endif
