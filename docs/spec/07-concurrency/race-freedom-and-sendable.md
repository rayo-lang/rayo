# Race freedom and Sendable values

[07 · Concurrency](../07-concurrency.md)

Code on different threads can reach the same memory only through routes that order or separate their accesses. Rayo uses borrowing rules for work lent to a thread, and `Sendable` to limit which values can move between threads. The rules below explain why those routes keep safe code free of data races.

## Why safe code can't race

**Only `Sendable` values reach another thread** ([below](#what-may-cross-threads-sendable)). Everything else stays on its own thread, where exclusivity and the dynamic tier check all its aliases ([01](../01-values-and-ownership.md#tiers-of-checking)).

**Safe code on two threads can reach the same memory only through four routes, each of which orders its writes:**

1. **borrows**, which a library lends to another thread only for the length of a call, where exclusivity governs them statically ([Lending work to other threads](thread-work.md#lending-work-to-other-threads));
2. **`Synchronized` types and channel ends**, which synchronize themselves ([Atomics and locks](synchronization.md#atomics-and-locks), [Queues and channels](synchronization.md#queues-and-channels));
3. **`Shared<T>`**, whose value is `Frozen`, so never written, or `Synchronized`, so written only through its own synchronization ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners));
4. **`const`s, global `let`s and immortal data**, which every thread reads through shared borrows ([Global state](global-state.md#global-state)). Immortal data, such as what a `StaticSpan` or `StaticString` views, is never written once a value names it ([09](../09-compile-time/attributes-and-runtime-data.md#staticspan-views-of-immortal-data)).

**Every other global that safe code can use is thread-local**, with a copy for each thread ([Thread-locals](global-state.md#thread-locals)).

**Reading a value from many threads at once needs nothing special**, as a parallel loop shows:

```swift
let palette = buildPalette()                  // a local, read below by every thread at once
particles.forEachInParallel { p in            // may run on many threads at once
    p.color = palette.color(for: p.kind)      // fine: nothing writes 'palette'
}
```

## What may cross threads: `Sendable`

```swift
import c "audio.h"                                       // declarations land in module 'audio'

struct Enemy(var pos: Vec3, var hp: Float)               // Sendable: every field is
struct Hud(var root: WeakPointer<Widget>)                // not Sendable: holds a thread-bound weak pointer
struct GLTexture(let id: UInt32): ~Sendable              // opts out: must stay on the GL thread
struct AudioDevice(unsafe let device: *audio.AudioDev): unsafe Sendable   // a promise: the C audio API is thread-safe

Thread.start { [move enemies] in simulate(enemies) }     // fine: List<Enemy> is Sendable
Thread.start { [move hud] in draw(hud) }                 // error: 'Hud' isn't Sendable
```

**A value of a `Sendable` type may be used from another thread**: moved there, or borrowed there until the lending call returns. The compiler derives this marker protocol from what a type holds, as it derives `Copyable`, so a value's type says whether it reaches anything bound to one thread:

- **Structs, enums, tuples, unions and arrays.** One is `Sendable` when every stored field, payload and element is. For a generic type, the fields are checked with its type arguments substituted. So `Pair<Enemy>` of two `Enemy` fields is, and no `Tagged<T>` that also holds a `WeakPointer<Widget>` is, whatever `T` is.
- **Closures.** A closure is `Sendable` when every capture's type is, whether captured by reference or owned. A value of a `@sendable` function type, or a `Closure` of one, is `Sendable` ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)). A C function pointer is `Sendable` too.
- **Existentials.** An `any P` or a `mutable any P` hides its value's type. So it is `Sendable` only when `P` refines `Sendable`, or when it is written with `& Sendable`, which accepts only `Sendable` types ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)).
- **Raw pointers.** A raw pointer, and anything that holds one, isn't `Sendable`, unless its type declares `unsafe Sendable` or `unsafe Synchronized` ([The `Synchronized` contract](synchronization.md#the-synchronized-contract)).
- **Object pointers and lock guards.** `UniquePointer` and `WeakPointer` ([03](../03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)), lock guards ([02](../02-views-and-dependencies/dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them)), and anything that holds one of them never are: their marks and locks belong to one thread. An object's access marks never synchronize with another thread, and many platform mutexes must be unlocked on the thread that locked them. So declaring `unsafe Sendable` or `unsafe Synchronized` on such a type breaks its promise ([10](../10-errors-and-safety/unsafe-code.md#unverified-promises)).
- **Shared values, channel ends and pins.** `Shared<T>`, `WeakShared<T>`, `Sender<T>`, `Receiver<T>` and `Pin<T>` are `Sendable` when `T` is. A `LocalShared<T>` or a `LocalPin<T>` never is, so a `LocalShared`'s count needs no atomic operation, and a `LocalPin` drops on its object's home thread ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners), [03](../03-handles-and-objects.md#pinning-for-c)).
- **`Synchronized` types.** Every one, `Future<T>` among them, is `Sendable`, since the contract allows its contents to be only `Sendable` values or raw pointers ([The `Synchronized` contract](synchronization.md#the-synchronized-contract)).

**A type may also opt out, or promise what the compiler can't derive:**

- **`~Sendable`** in a conformance list opts out a type that must stay on one thread although its fields could move, such as the id of an OpenGL texture or a window.
- **`unsafe Sendable`** promises, unchecked, that values of a type whose fields aren't all `Sendable` may be moved to other threads and shared with them ([10](../10-errors-and-safety/unsafe-code.md#unverified-promises)). Examples are a wrapper over a raw pointer into a thread-safe C library, and a handle to heap state that synchronizes itself, as a channel end is. It can't cover an object pointer or lock guard the type holds (above).
- **std's owning containers** (`List`, `String`, `Map`, `Set`, `TrailingArray`, `Pool`, `StablePool`, `Box` and `Blob`), **the builtin `SoA`, and the views** `Span`, `MutableSpan`, `StringView`, `StaticSpan`, `StaticString`, `Borrow` and `MutableRef` each hold a raw pointer, so none derives `Sendable`. Each declares `unsafe Sendable` when every type it holds is `Sendable`: a `TrailingArray`'s header and elements, a `Map`'s keys and values, and each other container's or view's elements. The pointer in each names memory the value owns alone, immortal literal bytes, or memory it views under the borrow rules, so moving or lending the value moves or lends exactly what it holds. So `List<Enemy>` is `Sendable`, and `List<WeakPointer<Enemy>>` isn't.

**`Sendable` is required of everything that code on one thread can reach from another:**

- a thread body's captures ([What a thread can share](thread-work.md#what-a-thread-can-share));
- what a job system lends to its threads and hands back ([The library's promise](thread-work.md#the-librarys-promise));
- the contents of a `Synchronized` value, such as a queue's items or a `Future`'s result, except the raw pointers its `unsafe` code answers for ([The `Synchronized` contract](synchronization.md#the-synchronized-contract));
- the value of a `Shared` whose owners or weak links cross threads ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners));
- every global that safe code reaches ([Global state](global-state.md#global-state)).

**A `Channel`'s items needn't be `Sendable`.** The ends of one whose items aren't `Sendable` aren't either, so both stay on one thread.
