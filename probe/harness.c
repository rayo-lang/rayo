// harness <exe> <runs> <parallel> <nogpfault 0|1>: runs exe that many times, at most `parallel` at once, and
// prints a tally of exit codes.
#include <windows.h>
#include <stdio.h>
#include <stdlib.h>

static DWORD codes[64];
static int counts[64];
static int kinds;

static void tally(DWORD code) {
    for (int i = 0; i < kinds; i++) if (codes[i] == code) { counts[i]++; return; }
    codes[kinds] = code; counts[kinds++] = 1;
}

int main(int argc, char **argv) {
    const char *exe = argv[1];
    int runs = atoi(argv[2]), parallel = atoi(argv[3]);
    if (atoi(argv[4])) SetErrorMode(GetErrorMode() | SEM_NOGPFAULTERRORBOX);
    HANDLE live[64];
    int running = 0, started = 0;
    DWORD begin = GetTickCount();
    while (started < runs || running > 0) {
        while (started < runs && running < parallel) {
            STARTUPINFOA si = {sizeof si};
            PROCESS_INFORMATION pi;
            char line[1024];
            snprintf(line, sizeof line, "\"%s\"", exe);
            si.dwFlags = STARTF_USESTDHANDLES;
            si.hStdOutput = si.hStdError = si.hStdInput = NULL;
            if (!CreateProcessA(exe, line, NULL, NULL, FALSE, 0, NULL, NULL, &si, &pi)) {
                printf("CreateProcess failed %lu\n", GetLastError());
                return 1;
            }
            CloseHandle(pi.hThread);
            live[running++] = pi.hProcess;
            started++;
        }
        DWORD which = WaitForMultipleObjects(running, live, FALSE, INFINITE) - WAIT_OBJECT_0;
        DWORD code;
        GetExitCodeProcess(live[which], &code);
        tally(code);
        CloseHandle(live[which]);
        live[which] = live[--running];
    }
    printf("%s runs=%d parallel=%d nogpfault=%d seconds=%lu:", exe, runs, parallel, atoi(argv[4]),
           (GetTickCount() - begin) / 1000);
    for (int i = 0; i < kinds; i++) printf(" 0x%08lX x%d", codes[i], counts[i]);
    printf("\n");
    return 0;
}
