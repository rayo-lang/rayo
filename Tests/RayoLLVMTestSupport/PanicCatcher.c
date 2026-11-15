#include "PanicCatcher.h"

#include <stdio.h>
#include <stdlib.h>

#ifdef _WIN32
#include <process.h>
#include <windows.h>
#else
#include <pthread.h>
#include <setjmp.h>
#include <string.h>
#include <sys/mman.h>
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
// A call that runs on a thread of its own, and, where it measures them, the bytes of that thread's stack it used.
typedef struct {
    Call call;
    bool measures;
    size_t stackBytes;
} ThreadCall;

// The bytes of this thread's stack that are committed, from its top down to the deepest page code has reached.
static size_t committedStackBytes(void) {
    ULONG_PTR low, high;
    GetCurrentThreadStackLimits(&low, &high);

    // Windows commits a stack's pages from the top down, as code first reaches each through the guard page below
    // those committed. So the lowest committed page that isn't a guard page is the deepest the thread has reached.
    MEMORY_BASIC_INFORMATION region;
    for (ULONG_PTR address = low; address < high; address += region.RegionSize) {
        VirtualQuery((void *)address, &region, sizeof region);
        if (region.State == MEM_COMMIT && !(region.Protect & PAGE_GUARD)) return high - address;
    }
    return 0;
}

// Runs the call at `threadCall` on the thread made for it, and measures the thread's stack once the call returns.
static unsigned __stdcall runOnThread(void *threadCall) {
    ThreadCall *running = threadCall;
    run(&running->call);
    // A panic ends the thread before this, and so measures nothing.
    if (running->measures) running->stackBytes = committedStackBytes();
    return 0;
}

// Runs the call at `threadCall` on a new thread whose stack reserves `stackBytes`, or the process's default where
// that is 0, and waits for the thread to end.
static void runOnNewThread(ThreadCall *threadCall, unsigned stackBytes) {
    unsigned flags = stackBytes == 0 ? 0 : STACK_SIZE_PARAM_IS_A_RESERVATION;
    HANDLE thread = (HANDLE)_beginthreadex(NULL, stackBytes, runOnThread, threadCall, flags, NULL);
    // A thread that can't start leaves no call to run.
    if (thread == NULL) {
        fputs("rayo_call_catching_panic: can't start a thread for the call\n", stderr);
        abort();
    }
    WaitForSingleObject(thread, INFINITE);
    CloseHandle(thread);
}

RayoCaughtCall rayo_call_catching_panic(int64_t (*function)(int64_t, int64_t), int64_t left, int64_t right) {
    // Windows' longjmp unwinds each frame it leaves by the frame's unwind tables, and LLVM's JIT registers none for
    // the code it compiles. So the call runs on a thread of its own, which a panic ends where it stands.
    ThreadCall threadCall = {.call = {.function = function, .left = left, .right = right}};
    runOnNewThread(&threadCall, 0);
    return threadCall.call.outcome;
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

#ifdef _WIN32
RayoCaughtCall rayo_run_measuring_stack(void (*main)(void), size_t *stackBytes) {
    ThreadCall threadCall = {.call = {.function = callMain, .left = (int64_t)(uintptr_t)main}, .measures = true};
    runOnNewThread(&threadCall, RAYO_TEST_MEASURED_STACK_BYTES);
    *stackBytes = threadCall.stackBytes;
    return threadCall.call.outcome;
}
#else
// The byte a measured stack is filled with before the run, which the run overwrites wherever it reaches.
static const unsigned char unreachedStackByte = 0xA5;

// A run of a program's entry function on a thread of its own, and what it came to.
typedef struct {
    void (*main)(void);
    RayoCaughtCall outcome;
} MainRun;

// Runs the entry function of the run at `mainRun`, and records what it came to.
static void *runMain(void *mainRun) {
    MainRun *running = mainRun;
    running->outcome = rayo_run_catching_panic(running->main);
    return NULL;
}

RayoCaughtCall rayo_run_measuring_stack(void (*main)(void), size_t *stackBytes) {
    // Fill the stack before the run, so that the deepest byte the run changed shows how far down it reached.
    size_t size = RAYO_TEST_MEASURED_STACK_BYTES;
    unsigned char *stack = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (stack == MAP_FAILED) {
        fputs("rayo_run_measuring_stack: can't map a stack for the run\n", stderr);
        abort();
    }
    memset(stack, unreachedStackByte, size);

    // Run the entry function on a thread that has that stack.
    MainRun run = {.main = main};
    pthread_attr_t attributes;
    pthread_t thread;
    pthread_attr_init(&attributes);
    pthread_attr_setstack(&attributes, stack, size);
    if (pthread_create(&thread, &attributes, runMain, &run) != 0) {
        fputs("rayo_run_measuring_stack: can't start a thread for the run\n", stderr);
        abort();
    }
    pthread_join(thread, NULL);
    pthread_attr_destroy(&attributes);

    // The stack grows down from its end, so the bytes below the deepest the run reached are still as they were filled.
    size_t unreached = 0;
    while (unreached < size && stack[unreached] == unreachedStackByte) unreached++;
    *stackBytes = run.outcome.panicked ? 0 : size - unreached;
    munmap(stack, size);
    return run.outcome;
}
#endif

// Adds the `length` bytes at `text` to the output of the call this thread runs.
static void print(const char *text, int length) {
    // Only code under test prints, inside a call.
    if (current == NULL) {
        fputs("rayo_call_catching_panic: a print outside a call\n", stderr);
        abort();
    }
    // An output past its capacity has nowhere to go.
    if (length < 0 || current->outcome.outputLength + length > RAYO_TEST_OUTPUT_CAPACITY) {
        fputs("rayo_call_catching_panic: a call printed more than its output holds\n", stderr);
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
