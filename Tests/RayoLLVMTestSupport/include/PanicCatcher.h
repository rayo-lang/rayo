#ifndef RAYO_LLVM_TEST_SUPPORT_PANIC_CATCHER_H
#define RAYO_LLVM_TEST_SUPPORT_PANIC_CATCHER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

/// The most bytes a call under test may print. A call that prints more ends the process.
#define RAYO_TEST_OUTPUT_CAPACITY 4096

/// What a call of a function under test came to: its value, or the message of the panic that ended it, and the text
/// it printed through the stand-ins for the runtime's print functions before it returned or panicked.
typedef struct {
    bool panicked;
    int64_t value;
    const char *message;
    int64_t length;
    char output[RAYO_TEST_OUTPUT_CAPACITY];
    int64_t outputLength;
} RayoCaughtCall;

/// Calls `function` with `left` and `right`, and returns its value, or the panic that ends it through
/// the function at `rayo_test_panic_address()`.
RayoCaughtCall rayo_call_catching_panic(int64_t (*function)(int64_t, int64_t), int64_t left, int64_t right);

/// Calls `main`, a program's entry function, which takes and returns nothing, and returns what it printed and the
/// panic that ended it, if one did, as `rayo_call_catching_panic` does.
RayoCaughtCall rayo_run_catching_panic(void (*main)(void));

/// The bytes of stack the thread that `rayo_run_measuring_stack` makes has. A run that needs more ends the process.
#define RAYO_TEST_MEASURED_STACK_BYTES (16 * 1024 * 1024)

/// Calls `main` as `rayo_run_catching_panic` does, on a thread of its own, and returns what the call came to, with
/// `stackBytes` set to how far down the thread's stack the call reached, in bytes from its top. A call that panicked
/// sets it to 0. On Windows a frame's pages are each touched as it is made, so this is the depth of the deepest frame;
/// elsewhere it is the deepest byte the call wrote, so a slot no code writes doesn't count.
RayoCaughtCall rayo_run_measuring_stack(void (*main)(void), size_t *stackBytes);

/// The address of the function that stands in for the runtime's `rayo.panic`: it ends the call that
/// `rayo_call_catching_panic` made with the panic's message, which lives as long as the code that
/// panicked.
const void *rayo_test_panic_address(void);

/// The addresses of the functions that stand in for the runtime's `rayo.print_int`, `rayo.print_uint` and
/// `rayo.print_bool`: each adds the line the runtime's function would print to the output of the call that
/// `rayo_call_catching_panic` made.
const void *rayo_test_print_int_address(void);
const void *rayo_test_print_uint_address(void);
const void *rayo_test_print_bool_address(void);

#endif
