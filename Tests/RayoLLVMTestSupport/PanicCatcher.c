#include "PanicCatcher.h"

#include <setjmp.h>
#include <stdio.h>
#include <stdlib.h>

// Each thread runs its own call, so a panic jumps back to the call on its own thread, carrying its message.
static _Thread_local bool calling;
static _Thread_local jmp_buf caller;
static _Thread_local const char *panicMessage;
static _Thread_local int64_t panicLength;

RayoCaughtCall rayo_call_catching_panic(int64_t (*function)(int64_t, int64_t), int64_t left, int64_t right) {
    // A panic jumps back here, and the call comes to its message instead of a value.
    calling = true;
    if (setjmp(caller) != 0) {
        calling = false;
        return (RayoCaughtCall){.panicked = true, .message = panicMessage, .length = panicLength};
    }

    // A call that returns comes to its value.
    int64_t value = function(left, right);
    calling = false;
    return (RayoCaughtCall){.panicked = false, .value = value};
}

static _Noreturn void panic(const char *message, int64_t length) {
    // A panic outside a call has no call to end, so it ends the process, as the runtime's does.
    if (!calling) {
        fwrite(message, 1, (size_t)length, stderr);
        abort();
    }

    // A panic inside a call ends that call with its message.
    panicMessage = message;
    panicLength = length;
    longjmp(caller, 1);
}

uint64_t rayo_test_panic_address(void) {
    return (uint64_t)(uintptr_t)&panic;
}
