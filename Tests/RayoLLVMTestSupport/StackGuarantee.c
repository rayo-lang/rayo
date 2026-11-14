#include "StackGuarantee.h"

#ifdef _WIN32
#include <process.h>
#include <stdio.h>
#include <stdlib.h>
#include <windows.h>

// A function a thread runs, and the stack guarantee the thread has once it returns.
typedef struct {
    void (*start)(void);
    ULONG guarantee;
} ThreadRun;

// Runs the function at `run`, then reads this thread's guarantee, which a size of 0 asks for without changing it.
static unsigned __stdcall runOnThread(void *run) {
    ThreadRun *threadRun = run;
    threadRun->start();
    threadRun->guarantee = 0;
    SetThreadStackGuarantee(&threadRun->guarantee);
    return 0;
}

unsigned long rayo_stack_guarantee_after(void (*start)(void)) {
    ThreadRun run = {.start = start, .guarantee = 0};
    HANDLE thread = (HANDLE)_beginthreadex(NULL, 0, runOnThread, &run, 0, NULL);
    // A thread that can't start runs nothing whose guarantee could be read.
    if (thread == NULL) {
        fputs("rayo_stack_guarantee_after: can't start a thread\n", stderr);
        abort();
    }
    WaitForSingleObject(thread, INFINITE);
    CloseHandle(thread);
    return run.guarantee;
}
#endif
