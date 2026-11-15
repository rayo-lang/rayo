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
    // The output the call printed is in its outcome already, so only its value is set.
    call->outcome.value = call->function(call->left, call->right);
}

#ifdef _WIN32
// Runs the call at `call` on the thread made for it.
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

// Ends the call on this thread, which goes on where the call was made.
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

    // A panic inside a call ends that call with its message, after the output it printed.
    current->outcome.panicked = true;
    current->outcome.message = message;
    current->outcome.length = length;
    endCall();
}

const void *rayo_test_panic_address(void) {
    return (const void *)(uintptr_t)&panic;
}

// Calls the entry function at `main`, which comes as an integer so that the call has the shape of every call under
// test.
static int64_t callMain(int64_t main, int64_t unused) {
    (void)unused;
    ((void (*)(void))(uintptr_t)main)();
    return 0;
}

RayoCaughtCall rayo_run_catching_panic(void (*main)(void)) {
    return rayo_call_catching_panic(callMain, (int64_t)(uintptr_t)main, 0);
}

// Adds the `length` bytes at `text` to the output of the call this thread runs.
static void print(const char *text, int length) {
    // Only code under test prints, inside a call, and an output past its capacity has nowhere to go.
    if (current == NULL || length < 0 || current->outcome.outputLength + length > RAYO_TEST_OUTPUT_CAPACITY) {
        fputs("rayo_call_catching_panic: a print outside a call, or past the output's capacity\n", stderr);
        abort();
    }
    for (int index = 0; index < length; index++) {
        current->outcome.output[current->outcome.outputLength + index] = text[index];
    }
    current->outcome.outputLength += length;
}

// Each stand-in below prints its value as the runtime's print function does, on a line of its own.

static void printInt(int64_t value) {
    char line[32];
    print(line, snprintf(line, sizeof line, "%lld\n", (long long)value));
}

static void printUInt(uint64_t value) {
    char line[32];
    print(line, snprintf(line, sizeof line, "%llu\n", (unsigned long long)value));
}

// The Bool comes as an `i1`, whose caller may leave the bits above the lowest as they were.
static void printBool(uint32_t value) {
    if (value & 1) {
        print("true\n", 5);
    } else {
        print("false\n", 6);
    }
}

const void *rayo_test_print_int_address(void) {
    return (const void *)(uintptr_t)&printInt;
}

const void *rayo_test_print_uint_address(void) {
    return (const void *)(uintptr_t)&printUInt;
}

const void *rayo_test_print_bool_address(void) {
    return (const void *)(uintptr_t)&printBool;
}
