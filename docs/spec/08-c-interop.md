# 08 · C interop

A Rayo program imports a C header and calls its functions directly:

```swift
import c "platform.h"          // the header's declarations become Rayo declarations, in module 'platform'

// platform.h declares:  void platform_upload(const float* data, size_t count);
// Rayo sees it as an unsafe func taking (*Float?, UInt)

func upload(_ samples: Span<Float>) {          // a safe wrapper: a span always knows how many elements it has
    unsafe { platform_upload(samples.baseAddress, UInt(samples.count)) }
}
```

**A call to C is a direct call through the platform's C ABI.**

**Interop runs both ways.** Rayo reaches C through the headers it imports ([Importing headers](08-c-interop/imports-and-inline-c.md#importing-headers)), and through `extern c` blocks and declarations ([Inline C](08-c-interop/imports-and-inline-c.md#inline-c)). C reaches Rayo through exported functions ([Calling Rayo from C](08-c-interop/calling-rayo-from-c.md#calling-rayo-from-c)) and callbacks ([Callbacks](08-c-interop/calling-rayo-from-c.md#callbacks)). Either way, C has the obligations that `unsafe` Rayo code would have in its place ([What C must uphold](08-c-interop/c-contract-and-embedding.md#what-c-must-uphold)).

## Subchapters

- [Imports and inline C](08-c-interop/imports-and-inline-c.md)
- [Calling Rayo from C](08-c-interop/calling-rayo-from-c.md)
- [C's contract and embedding](08-c-interop/c-contract-and-embedding.md)
