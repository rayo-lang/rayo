#include <windows.h>
#include <stdio.h>

__declspec(noinline) long long deeper(long long n) { return deeper(n + 1) + 1; }

int main(void) {
#ifdef GUARANTEE
    ULONG g = GUARANTEE;
    SetThreadStackGuarantee(&g);
#endif
    printf("%lld\n", deeper(0));
    return 0;
}
