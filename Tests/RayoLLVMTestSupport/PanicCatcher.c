#include "PanicCatcher.h"

#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
#include <process.h>
#include <windows.h>
#else
#include <setjmp.h>
#endif

// A call of a function under test, and what it came to.
typedef struct {
    int64_t (*function)(int64_t, int64_t);
    int64_t left;
    int64_t right;
    RayoCaughtCall outcome;
} Call;

// The call that this thread runs, or none outside one; each thread runs its own.
static _Thread_local Call *current;

// Runs `call` on this thread, and records its value once it returns.
static void run(Call *call) {
    current = call;
    int64_t value = call->function(call->left, call->right);
    call->outcome = (RayoCaughtCall){.panicked = false, .value = value};
}

#ifdef _WIN32
static unsigned __stdcall runOnThread(void *call) {
    run(call);
    return 0;
}

RayoCaughtCall rayo_call_catching_panic(int64_t (*function)(int64_t, int64_t), int64_t left, int64_t right) {
    // Windows' longjmp unwinds each frame it leaves by the frame's unwind tables, and LLVM's JIT registers none for
    // the code it compiles. So the call runs on a thread of its own, which a panic ends where it stands.
    Call call = {.function = function, .left = left, .right = right};
    HANDLE thread = (HANDLE)_beginthreadex(NULL, 0, runOnThread, &call, 0, NULL);
    // A thread that can't start leaves no call to run.
    if (thread == NULL) {
        fputs("rayo_call_catching_panic: can't start a thread for the call\n", stderr);
        abort();
    }
    WaitForSingleObject(thread, INFINITE);
    CloseHandle(thread);
    return call.outcome;
}

// Ends the call on this thread, which ends the thread, leaving the frames of the code under test as they stand.
static _Noreturn void endCall(void) {
    _endthreadex(0);
    __builtin_unreachable();
}
#else
// Where this thread's call goes on when a panic ends it.
static _Thread_local jmp_buf caller;

RayoCaughtCall rayo_call_catching_panic(int64_t (*function)(int64_t, int64_t), int64_t left, int64_t right) {
    // The call lives outside this frame, since a jump back to the frame leaves what changed in it undefined.
    static _Thread_local Call call;
    call = (Call){.function = function, .left = left, .right = right};

    // A panic jumps back here, with the panic recorded as what the call came to; this longjmp leaves the frames
    // between without unwinding them.
    if (setjmp(caller) == 0) run(&call);
    current = NULL;
    return call.outcome;
}

static _Noreturn void endCall(void) {
    longjmp(caller, 1);
}
#endif

static _Noreturn void panic(const char *message, int64_t length) {
    // A panic outside a call has no call to end, so it ends the process, as the runtime's does.
    if (current == NULL) {
        fwrite(message, 1, (size_t)length, stderr);
        abort();
    }

    // A panic inside a call ends that call with its message.
    current->outcome = (RayoCaughtCall){.panicked = true, .message = message, .length = length};
    endCall();
}

uint64_t rayo_test_panic_address(void) {
    return (uint64_t)(uintptr_t)&panic;
}
