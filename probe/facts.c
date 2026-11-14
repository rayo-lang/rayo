#include <windows.h>
#include <stdio.h>

int main(void) {
    char name[256] = {0};
    DWORD size = sizeof name;
    RegGetValueA(HKEY_LOCAL_MACHINE, "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0", "ProcessorNameString",
                 RRF_RT_REG_SZ, NULL, name, &size);
    DWORD64 features = GetEnabledXStateFeatures();
    DWORD length = 0;
    InitializeContext2(NULL, CONTEXT_ALL | CONTEXT_XSTATE, NULL, &length, features);
    SYSTEM_INFO info;
    GetNativeSystemInfo(&info);
    printf("cpu=%s\nprocessors=%lu\navx512f=%d\nxstate=0x%llx\ncontext_length=%lu\nerror_mode=0x%x\n", name,
           info.dwNumberOfProcessors, IsProcessorFeaturePresent(41), (unsigned long long)features, length,
           GetErrorMode());
    return 0;
}
