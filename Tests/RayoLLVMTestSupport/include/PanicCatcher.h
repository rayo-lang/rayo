#ifndef RAYO_LLVM_TEST_SUPPORT_PANIC_CATCHER_H
#define RAYO_LLVM_TEST_SUPPORT_PANIC_CATCHER_H

#include <stdbool.h>
#include <stdint.h>

/// What a call of a function under test came to: its value, or the message of the panic that ended it.
typedef struct {
    bool panicked;
    int64_t value;
    const char *message;
    int64_t length;
} RayoCaughtCall;

/// Calls `function` with `left` and `right`, and returns its value, or the panic that ends it through
/// the function at `rayo_test_panic_address()`.
RayoCaughtCall rayo_call_catching_panic(int64_t (*function)(int64_t, int64_t), int64_t left, int64_t right);

/// The address of the function that stands in for the runtime's `rayo.panic`: it ends the call that
/// `rayo_call_catching_panic` made with the panic's message, which lives as long as the code that
/// panicked.
const void *rayo_test_panic_address(void);

#endif
