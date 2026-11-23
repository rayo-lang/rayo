# 08 · C interop

A Rayo program can use a C library without rewriting its interface. Imported headers provide the declarations, and calls use the platform's C ABI. The boundary also makes Rayo state when it relies on C's pointer and memory guarantees. For example, a safe wrapper can take a reference to a run of elements while keeping the direct C call inside `unsafe`:

```rayo
import c "platform.h"          // the header's declarations become Rayo declarations, in module 'platform'

// platform.h declares:  void platform_upload(const float* data, size_t count);
// Rayo sees it as an unsafe func taking (*Float?, CSize)

func upload(_ samples: &[Float]) {             // a safe wrapper: a '&[Float]' always knows how many elements it has
    unsafe { platform_upload(samples.baseAddress, CSize(samples.count)) }
}
```

`samples` names the run its caller lends, as in `upload(levelSamples)`. It hands C the run's `count` and its `baseAddress`, the first element's address, which only `unsafe` code reads ([10](10-errors-and-safety/unsafe-code.md#what-needs-unsafe)).

**Interop runs both ways.** Rayo reaches C through the headers it imports ([Importing headers](08-c-interop/imports-and-inline-c.md#importing-headers)), and through `extern c` blocks and declarations ([Inline C](08-c-interop/imports-and-inline-c.md#inline-c)). C reaches Rayo through exported functions ([Calling Rayo from C](08-c-interop/calling-rayo-from-c.md#calling-rayo-from-c)) and callbacks ([Callbacks](08-c-interop/calling-rayo-from-c.md#callbacks)). Either way, C has the obligations that `unsafe` Rayo code would have in its place ([What C must uphold](08-c-interop/c-contract-and-embedding.md#what-c-must-uphold)).

## Subchapters

- [Imports and inline C](08-c-interop/imports-and-inline-c.md)
- [Calling Rayo from C](08-c-interop/calling-rayo-from-c.md)
- [C's contract and embedding](08-c-interop/c-contract-and-embedding.md)
