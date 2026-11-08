# Calling Rayo from C

[08 · C interop](../08-c-interop.md)

A C or C++ program uses a library written in Rayo:

```swift
@export(c) func nav_load(_ desc: NavDesc) -> WeakShared<NavMesh> { ... }   // Shared.leak: the C caller owns the mesh
@export(c, name: "nav_path") func findPath(_ mesh: WeakShared<NavMesh>, _ out: owned MutableSpan<Int32>) -> Int32 { ... }

@export(c) @c struct NavDesc(
    var width: Int32,
    var height: Int32,
    var dataPath: *CChar,
)
```

**`@export(c)` functions get C linkage and no mangling, and their parameters and results must have a C representation** ([below](#c-representations)).

- **The name is a promise.** An exported name shares one namespace with every C symbol the program links or loads. So `@export` on a function is an unverified promise ([10](../10-errors-and-safety/unsafe-code.md#unverified-promises)): nothing else in the program defines that name, and every C caller of it calls this signature. The build fails when two objects it links define one name.
- **Parameters pass by value.** Each passes in its C representation, whatever its Rayo convention (borrowed or `owned`), except a `mutable` one, which passes as a pointer. The same holds for `@c func`, the form a callback takes ([below](#callbacks)).
- **No throwing.** Neither kind of function can throw, since C has no form for it.
- **Panics stay in Rayo.** A panic in the body is reported as any panic is ([10](../10-errors-and-safety/panics.md#panics)), and Rayo never unwinds.
- **Not generic.** An `@export` function has no type parameters and no `some P` parameter, since C calls one symbol.

**The build writes a C header for each module.** It holds these, each in its C representation ([below](#c-representations)):

- every exported function;
- every `@export(c)` type;
- every type that the signature of one of the module's exported functions, `@c func`s or `extern c func`s uses;
- every type that one of the module's `@c` types uses.

**For each `List`, `String` and `TrailingArray` type among them, the header declares a free function**: an `@export` function that takes the value `owned` and destroys it. So a call of the free function enters Rayo as any call from C does ([below](#c-entries-and-threads)).

## C representations

**A type's C representation is the C type its values cross to C as.** It has the Rayo type's size and alignment, and these rules give it:

- **Imported types.** Each Rayo type that a C type imports as ([What imports as what](imports-and-inline-c.md#what-imports-as-what)), such as `Int32`, `Bool`, a raw pointer, `Simd<Float, 4>` or an imported `@c union`, crosses as that C type. When several import as it, it crosses as the first one the import table lists that the target has: `Int` as `ptrdiff_t`, `UInt` as `size_t` and `*T?` as `T*`.
- **C aliases.** A type written with one of the C aliases, such as `CChar` or `CLong`, crosses as the C type it stands for, so `*CChar` is a `char*` in a generated header.
- **The table below.** The types in it cross as it gives, provided every type they are built from, such as a struct's fields or a `List<T>`'s `T`, has a C representation too. The `T` of a `Handle` or of a weak pointer to a concrete type needn't have one, since only the bits cross.
- **No size 0.** Since a C representation has its type's size and C has no type of size 0, a struct with no stored fields or a `[0 of T]` has none.

| Rayo | C representation |
| --- | --- |
| `Span<T>` | `struct { const T* ptr; int64_t count; }` |
| `StringView` | `struct { const char* ptr; int64_t count; }` |
| `MutableSpan<T>` | `struct { T* ptr; int64_t count; }` |
| `mutable T` parameter | `T*` |
| `Void` or `Never` as a result | `void`, and `_Noreturn` for `Never` |
| `StaticSpan<T>`, `StaticString` | `struct { const T* ptr; int64_t count; }`, with `char` as a `StaticString`'s `T`: immortal data, which C may keep. A `StaticString`'s bytes are followed by a NUL, so its `cString` passes to C as a `const char*` |
| struct | the C struct that declares its fields in layout order ([04](../04-types/structs.md#structs)), each in its representation |
| `[N of T]` field | a `T name[N]` field, each element in its representation |
| tuple | a C struct whose member `_i` is element `i`, declared in layout order ([04](../04-types/collections.md#tuples-ranges-and-arrays)), each in its representation |
| `Simd<T, N>` over a number type, other than the vector types the table above imports | `struct { _Alignas(A) T lanes[N]; }`, where `A` is the vector's alignment, so a 3-lane vector's fourth slot is padding ([04](../04-types/numbers-and-math.md#simd-and-math)) |
| union | the C union its layout gives ([04](../04-types/enums.md#untagged-unions)), each member in its representation |
| enum without payloads | its stored integer type, the raw type if it has one ([04](../04-types/enums.md#enums)), with a constant per case holding its stored value |
| enum with payloads | `struct { tag; union { … } }`, its tag as an enum without payloads stores it |
| `T?` with a niche | same layout as `T`, with one value meaning `nil` (below) |
| other `T?` | `struct { T value; bool has; }` |
| `Handle<T>`, `WeakPointer<T>`, `WeakShared<T>` | `uint64_t`: the bits (`h.bits`, `w.bits`), which only Rayo resolves |
| `List<T>`, `String` | `struct { T* ptr; int64_t count; int64_t cap; uint64_t alloc; }` (below) |
| `RawAllocation` | `struct { void* address; int64_t size; int64_t align; uint64_t alloc; }` ([10](../10-errors-and-safety/unsafe-code.md#raw-allocations)) |
| `TrailingArray<H, E>` | `struct { H* ptr; int64_t count; uint64_t alloc; }`, where `ptr` points at the header and the `count` elements start at the offset 04 gives ([04](../04-types/data-layout.md#variable-sized-structs-trailingarray)), which the generated header names |

- **The `nil` value of a niche** is the one 04 gives ([04](../04-types/enums.md#optionals)), and the generated header names it.
- **A `String` that still uses a literal's immortal bytes** ([04](../04-types/collections.md#literals)) has `cap` 0 and a non-null `ptr`.

**Every other type has no C representation**, and can't appear in an exported signature or a `@c` type. That includes:

- function-typed values other than `@c` pointers;
- weak pointers and weak links to `any P`;
- `Name`;
- any type whose layout the language or a library leaves open ([11](../11-compilation-model.md#what-the-language-leaves-open)), such as a task's state, `Borrow`, `MutableRef`, `Slice`, `Pin` and `LocalPin`;
- any type that is or holds a `Synchronized` value, which synchronizes itself and whose identity is its address ([07](../07-concurrency/synchronization.md#atomics-and-locks)).

## What a C entry hands back to C

**A `Span<T>` or `StringView` handed back to C views what it depends on** ([02](../02-views-and-dependencies.md#dependencies)), and C uses it only while that memory lives. What a C entry ([below](#c-entries-and-threads)) hands back to C is its scoped result, and whatever it stores into a `mutable` parameter or through a view a parameter carries.

**Once a C entry returns, nothing in Rayo holds what it borrowed**: a lock guard is released, and an open no longer counts as a use of its allocator ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)).

**So what a C entry hands back to C may depend only on these:**

- its parameters;
- `const`s;
- places in a global `let`'s own storage, reached through stored fields, inline array elements and enum payloads only, since no global is destroyed ([07](../07-concurrency/global-state.md#shutdown)).

**What it hands back never depends on a lock guard, `Once.get()` or an owning value's storage**, such as a global `List`'s elements. A reset or an unregistration could free those while C still holds what was handed back.

## Ownership that crosses to C

**Ownership crosses to C in these ways:**

- as a `List`, `String` or `TrailingArray` that a C entry returns to C or stores through a `mutable` parameter C lent, or that Rayo passes to an `owned` parameter of an `extern c func` or a `@c` pointer ([above](#c-representations));
- as a weak pointer from `UniquePointer.leak`, which comes back through `adopt` ([03](../03-handles-and-objects.md#weak-pointers-as-bits-and-handing-objects-to-c));
- as a weak link from `Shared.leak`, which comes back through `adopt` ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners));
- as a `RawAllocation` through `Box.leak` and the `unsafe` `Box.adopt` ([06](../06-memory-and-allocators/owning-values.md#owning-boxes)).

**An object or a `Shared` value reached through a protocol crosses as its weak pointer's or weak link's bits.** Rayo rebuilds the existential with `WeakPointer<any P>(bits:)` or `WeakShared<any P>(bits:)`.

# Callbacks

A `@c func` is a Rayo function that C can call through a function pointer:

```swift
let audioEvents = MpscQueue<AudioEvent>(capacity: 256)       // global let: Synchronized, safe from any thread

@c func onAudioEvent(_ user: *Void?, _ event: CInt) {        // runs on the audio library's thread
    audioEvents.push(AudioEvent(raw: copy event))
}

unsafe { platform_set_audio_callback(onAudioEvent, nil) }
// the program drains audioEvents with pop() wherever it processes input
```

**A function pointer type imported from a C header has borrowed parameters**, so a `@c func` with an `owned` parameter doesn't convert to it ([05](../05-protocols-generics-and-closures/functions-and-closures.md#c-function-pointers)): C calling through it never gives up what it passes.

## C entries and threads

**C may call a C entry from any thread.** A **C entry** is a `@c func`, an `@export` function or a closure literal converted to a `@c` pointer, all of which have the C calling convention.

**A call from C attaches the calling thread on first entry**, if Rayo didn't create it and C hasn't attached it ([Embedding Rayo in a C program](c-contract-and-embedding.md#embedding-rayo-in-a-c-program)). Attaching initializes the thread's thread-locals and gives the runtime its stack's bounds ([What the runtime needs from the platform](c-contract-and-embedding.md#what-the-runtime-needs-from-the-platform)), which Rayo code needs before it runs there.
