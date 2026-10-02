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

**Interop runs both ways.** Rayo reaches C through the headers it imports ([below](#importing-headers)), and through `extern c` blocks and declarations ([below](#inline-c)). C reaches Rayo through exported functions ([below](#calling-rayo-from-c)) and callbacks ([below](#callbacks)). Either way, C has the obligations that `unsafe` Rayo code would have in its place ([below](#what-c-must-uphold)).

## Importing headers

```swift
import c "platform.h"                                    // declarations land in module 'platform'
import c "SDL3/SDL.h" as sdl                             // explicit name
import c "vendor/fmod.h" as fmod where prefix: "FMOD_"   // strips the prefix: FMOD_System_Create → fmod.System_Create
```

**`import c` makes a header's declarations available in a Rayo module**, each as the Rayo declaration that the mapping gives it ([below](#what-imports-as-what)). An import may also take a prefix to strip and a config block:

- **`prefix:`** strips a case-sensitive match from the start of each imported function, type, enumerator, macro and variable name. A name keeps its prefix when stripping it would leave text that doesn't start an identifier, as `FMOD_3D` would, or a name that collides with another.
- **Config blocks.** An import may end with a **config block**, `unsafe { … }`, of rules about the header's C. The compiler takes each rule on trust, so the block is spelled `unsafe` ([10](10-errors-and-safety.md#unverified-promises)). It holds three kinds of rule:
    - `stack(n)`, which states the stack a function needs ([below](#the-stack-a-c-call-needs));
    - `noalloc`, which states that a function allocates nothing ([below](#c-calls-in-noalloc-code-noalloc));
    - `struct`, `union` or `enum S in "h"`, which names the header to take the type `S` from ([below](#the-identity-of-an-imported-type)).

  Its rules name declarations by their C names, before `prefix:` is stripped.

**Each `import c` reads its header with only the preprocessor definitions the build declares for that import** ([09](09-compile-time.md#what-a-build-declares)), so no other import's macros reach it. Two imports of one header may therefore read it differently, each with its own definitions.

### The identity of an imported type

**An imported type is one type wherever it is reached from, whatever definitions it is read with.** So `SDL_Window` is one type whether a module imports `SDL3/SDL.h` or `SDL3/SDL_video.h`.

**Its identity is its kind, `struct`, `union` or `enum`, the file that defines it, and its name there:**

- **A tagged type's name** is its tag, before any `prefix:` is stripped.
- **An untagged type's name** is the first typedef that names it, kept distinct from every tag. An untagged type that no typedef names is identified by its position among the untagged types declared directly in the struct or union that holds it, together with that holder's identity. One that nothing holds is identified by its position among its file's untagged types.
- **A tag gives way to a typedef of a different type, a function, a variable or an enumerator that shares its identifier.** The other declaration takes the plain Rayo name, and the tagged type imports as `struct_Shape`, `union_Shape` or `enum_Shape`.

So two untagged types with the same fields are still two types, and a tag can lose its plain name:

```c
typedef struct { float x, y; } Vec2;              // the type named Vec2 in this file
typedef struct { float x, y; } Point;             // a second type, although its fields match
struct Shape { float radius; };                   // imports as struct_Shape: the typedef below takes the name
typedef struct { float w, h; } Shape;             // imports as Shape
struct stat { … };                                // POSIX's <sys/stat.h> defines the struct first
int stat(const char* path, struct stat* buf);     // POSIX: the function is stat, and the struct is struct_stat
```

**A type that a reading only declares is a type of its own**, since two libraries may each keep a private `struct buffer`, and a declaration doesn't say whose it means. It is identified by the first file that declares it in the reading's include order, and imports as `@opaque`:

```c
struct sockaddr;      // declared, not defined in this reading: an @opaque type of its own
```

**An import can name a header whose reading has the type**, with a rule in its config block:

```swift
import c "mylib.h" unsafe { struct sockaddr in "sys/socket.h" }   // take struct sockaddr from sys/socket.h's reading
```

**Naming a header `h` this way asserts, unchecked, that the type is the one of that kind and tag in the reading of `h` with the import's definitions.** The build fails if that reading doesn't declare it. The named reading may only declare it too, as every public header does for a library's handle type that no header defines, such as Wayland's `struct wl_surface`. So imports that name one header for it share one opaque type.

**Two readings of one identity must agree, since they import as one type:** they give it the same kind, layout, fields, cases and attributes, or the build fails. Such a failure comes, for example, when one header defines a macro before including another, or when two imports read the type with definitions that change it. So modules that import `SDL3/SDL.h` with and without `SDL_MAIN_HANDLED` share one `SDL_Window`. An import that names a header for a type its own reading only declares takes that header's reading of the type.

### Calling imported functions

**Every imported C function is `unsafe` to call**, since a header can't say that a pointer outlives a call, or that a buffer holds `n` elements.

**As a value, an imported function converts only to `@c` function pointer types**, whose calls are `unsafe` too ([05](05-protocols-generics-and-closures.md#c-function-pointers)). Only a `@c` type carries the function's stack need, which a call through any other function type wouldn't check ([below](#the-stack-a-c-call-needs)).

**A `@safe` module can `import c` a header, to name its types and constants, but it can't call its functions or use its variables**, since both need `unsafe`, which such a module rejects ([10](10-errors-and-safety.md#safe-modules)).

#### The stack a C call needs

```swift
import c "physics.h" unsafe { stack(256 * 1024) physics_step }   // in the import
extern c stack(512 * 1024) func solve(_ d: CInt) -> CInt         // on an extern c func declaration
typealias Visitor = @c stack(1 << 20) (CInt) -> Void             // in a C function pointer's type
```

**A call into C first checks that the stack its target needs is left, and panics otherwise**, so running out of stack is caught before anything is written past the stack's end ([10](10-errors-and-safety.md#what-panics)).

**The need is the one declared where the call's target is**, in one of the three places above, each `n` a `const` `Int` expression. When nothing is declared there, the need is `target.cStackReserve` bytes ([09](09-compile-time.md#static-if-and-conditional-compilation)).

**A function or pointer converts to a `@c` type that declares at least its need, never less**, so a call through that type checks for at least the stack its target needs. A `@c` type without `stack` declares `target.cStackReserve`.

**A Rayo function, a `@c func`, an `@export` function or a literal needs none**, since it checks its own stack on entry.

**Every call to C is `unsafe`, so the calling code answers for the declared need being enough.**

### What imports as what

**The table gives the Rayo form of each C type and declaration that Rayo imports.**

| C | Rayo |
| --- | --- |
| `int8_t` … `int64_t`, `uint8_t` … `uint64_t` | `Int8` … `Int64`, `UInt8` … `UInt64` |
| `ptrdiff_t`, `intptr_t`, `size_t`, `uintptr_t` | `Int`, `Int`, `UInt`, `UInt` |
| `float`, `double`, `bool` | `Float`, `Double`, `Bool` |
| `void` as a function's result | `Void` |
| `_Float16`, where the target's C compiler has it | `Half` |
| `int`, `long`, `char` and C's other standard integer types | `CInt`, `CLong`, `CChar` and the like (below) |
| `T*` | `*T?` (nullable), or `*T` when annotated `_Nonnull` or inside `NS_ASSUME_NONNULL`-style regions |
| `const T*` | as `T*`, with the `const` dropped: Rayo has no pointer-const |
| `void*` | `*Void?` |
| `T arr[N]`, as a struct field or a variable | `[N of T]`. As a parameter, C adjusts it to `T*`, which imports as above |
| `__m128`, `float32x4_t`, `__m128i`, `int32x4_t` | `Simd<Float, 4>` / `Simd<Int32, 4>` ([04](04-types.md#simd-and-math)), passed by value in vector registers under the platform ABI |
| `struct S { ... }` | `@c struct S` with the same layout, fields and bitfields ([below](#structs-unions-and-enums)) |
| anonymous `union`/`struct` members | Their fields are accessible directly on the enclosing struct, as in C |
| flexible array member `T data[]` | The struct without the member, as a `TrailingArray` header (below) |
| `__attribute__((packed))` / `#pragma pack(n)` / `__attribute__((aligned(n)))` | `@packed` / `@packed(n)` / `@align(n)`, with identical layout ([04](04-types.md#packed-structs-and-under-aligned-places)) |
| incomplete `struct S;` that the reading doesn't define, and that no header its import names for it defines ([above](#the-identity-of-an-imported-type)) | `@opaque struct S`: only usable as `*S` |
| a struct or union whose layout Rayo can't reproduce, or whose members don't all map (below) | `@opaque` too |
| `typedef T N;` | `typealias N = T`, with the exceptions below |
| `union U` | `@c union U` |
| `enum E { A, B }` | `@c enum E: R`, a form only imports make, with `.A`, `.B`, **open** by default |
| anonymous `enum { A = 1 };` | a `const` of its underlying type per enumerator, and a field or variable of that enum has its underlying type |
| function | `unsafe func` with the same signature, unless it declares a calling convention other than the platform's default, such as `__vectorcall`, `ms_abi` or `pcs`, which isn't imported |
| `static const` variable of an integer, floating-point or `bool` type with a constant initializer | a `const`, as a literal macro is |
| any other variable, `extern T v;` or defined in the header | a global of type `T`, accessed only inside `unsafe`, as a bare global `var` is ([07](07-concurrency.md#global-state)). An `_Atomic`, `_Thread_local` or `volatile` variable isn't imported |
| function pointer `R (*)(A)` | `(@c (A) -> R)?`, nullable with null as its niche, or `@c (A) -> R` when annotated `_Nonnull` or inside an `NS_ASSUME_NONNULL`-style region |
| variadic function | callable with the variadic arguments below |
| `#define N 16` (literal) | `const N: CInt = 16` (below) |
| `#define F (1u << 3)` (another integer constant expression) | a `const` of the value and type C gives it, as the alias of that type: here a `CUInt` of 8 |
| `#define` function-like macros, and other macros | Not imported |
| `static inline` functions | Imported and called |

**Several rows of the table have rules of their own:**

- **C's standard integer types.** `CInt`, `CLong`, `CChar` and the like, such as `CUInt` for `unsigned` and `CShort` for `short`, are type aliases. Each is the `IntN` or `UIntN` with its C type's size and signedness on the target. So `CChar` is `Int8` or `UInt8` as the target's `char` is signed or not.
- **Flexible array members.** A struct `S` with a flexible array member `T data[]` imports without the member, as a `TrailingArray` header. Its `unsafe` static function `trailing(at:count:)`, called with a `p: *S` and a count `n`, gives a `MutableSpan<T>` at the member's offset from `p`, without lending the struct:

    ```swift
    // C: struct Packet { uint32_t len; uint8_t data[]; };
    let bytes = unsafe Packet.trailing(at: p, count: n)   // a MutableSpan<UInt8> of n elements at data's offset
    ```

  Its caller promises what 10 asks of a span made from a raw pointer ([10](10-errors-and-safety.md#what-unsafe-code-upholds)):
    - `n` valid elements there, aligned for `T`;
    - nothing else reaching them for as long as the span lives, a whole-struct write at `p` included, since they may share its tail padding.

  Rayo-allocated instances use `TrailingArray<S, T>` when the member's offset is a multiple of `T`'s alignment, since only then can the elements be both where C reads them and aligned ([04](04-types.md#variable-sized-structs-trailingarray)).
- **Structs and unions that import as `@opaque`.** A struct or union imports as `@opaque` when Rayo's layout rules, with `@packed(n)` and `@align(n)`, can't reproduce its members' offsets, size and alignment, as with an `_Alignas`, `aligned` or `packed` member. So does one whose members don't all map, as with an `_Atomic` member. A function that passes such a type by value, or a variable of that type, isn't imported, since an `@opaque` type is usable only behind a pointer.
- **Typedefs.** A typedef of a type `T` imports as a `typealias` of `T`, except for these:
    - a typedef that names a tagged type by its own tag, which adds nothing;
    - the first typedef that names an untagged type, which names the type itself ([above](#the-identity-of-an-imported-type));
    - a typedef whose attribute changes `T`'s size, alignment or representation, such as `aligned`, `packed`, `mode` or `vector_size`, which isn't imported unless it is one of the vector types above.
- **Variadic functions.** A variadic function is callable with variadic arguments that C's default argument promotions leave as they are, each with a C representation:
    - an integer at least as wide as `CInt`, signed or not;
    - a `Double`;
    - a pointer.

  The promotions would change a `Float` or a narrower integer, so the code converts one explicitly first, as in `Double(x)` or `CInt(x)`. A variadic function converts to no function type, and an `extern c func` can't declare one.
- **Literal macros.** A macro defined as a single literal imports as a `const`, usable as an array length or in a `static if` condition. Its value is the C literal's, so an octal literal reads as octal, and a `float` literal's value is rounded to `float`. A negated or parenthesized literal counts as one. Its type follows the type C gives the literal, suffix included. For an integer or character literal, it is the alias of that C type, such as `CInt` or `CUInt`. For a floating-point literal, it is the type that C type imports as, such as `Float` or `Double`, and for a string literal `StaticString`:

    ```c
    #define MAX_PADS 16          // const MAX_PADS: CInt = 16
    #define MODE 0644            // a CInt of 420: 0644 is octal
    #define LOW (-1)             // a CInt: a negated, parenthesized literal counts as one
    #define SLOTS 16u            // a CUInt
    #define MASK 0xFFFFFFFF      // a CUInt
    #define SEP ','              // a CInt, the type C gives a character literal
    #define SCALE 0.1f           // a Float, its value rounded to float
    #define RATE 0.1             // a Double
    #define TITLE "Rayo"         // a StaticString
    ```

**A C type the table doesn't map isn't imported.** Such types include:

- `long double`, `_Complex`, `__int128` and `_BitInt(N)`;
- a vector type other than those above;
- a function pointer type with a calling convention other than the platform's default.

**A function, typedef or variable that uses such a type isn't imported either, except through a data pointer.** A pointer to such a type imports as a pointer to `Void`:

```c
long double lerp(long double a, long double b, long double t);   // not imported
void clear(long double* p);                                       // imported, with a *Void? parameter
```

**An import compiles only the header's `static` definitions that its module reaches**, each with internal linkage:

- the `static` and `static inline` functions its module calls or converts to a `@c` pointer;
- the `static` variables its module uses;
- every such definition that these reach.

**Any other definition in a header, of a function or a variable, imports as a declaration alone.** So an import adds no symbol to the program and runs no C when it loads. A library's code comes from linking the library, or from an `extern c` block ([below](#inline-c)).

### Structs, unions and enums

```swift
// C: struct Pad { uint32_t id; uint32_t buttons : 16; uint32_t trigger : 8; };
var pad = Pad()                                  // safe: all-zero bytes are a valid value of every field
pad.buttons = 0x3                                // a generated accessor writes the bitfield
join({ pad.id = 1 }, { pad.buttons = 2 })        // fine: 'id' isn't a bitfield, so it is a separate place
join({ pad.buttons = 1 }, { pad.trigger = 2 })   // error: adjacent bitfields are one memory location, one place
```

**The rules below say how Rayo code builds and uses an imported struct, union or enum.**

**Structs.** An imported struct's primary initializer takes the fields that reflection lists for it ([09](09-compile-time.md#what-reflection-can-read)), in order, each labeled by its name and an anonymous union or struct member unlabeled, so `T.construct` builds one too. It also gets a zero-initializing `init()` when all-zero bytes are a valid value of every field, and an `unsafe` one otherwise, as when a field is a `_Nonnull` pointer.

**Bitfields keep the layout the target ABI gives them: each holds a run of bits in a storage unit.** So a bitfield differs from other fields in these ways:

- **Type.** A bitfield has its declared type, except an enum-typed one whose enumerators don't all survive the round trip through the field's width and the target ABI's signedness, which has the enum's raw integer type.
- **Access.** Generated accessors read and write a bitfield through a temporary, so they are access-bound projections ([02](02-views-and-dependencies.md#access-bound-projections)). A read or a write touches only the bytes that hold its memory location's bits, since another thread may write a neighboring field or memory location at the same time ([01](01-values-and-ownership.md#which-places-overlap)). A write of a value that doesn't fit the width panics where overflow checks are on, and keeps its low bits where they are off, as an unlabeled integer conversion does ([04](04-types.md#conversions)). A read of a signed bitfield sign-extends.
- **Places.** A **memory location** is a maximal run of adjacent nonzero-width bitfields, even across storage units, and a non-bitfield member or a zero-width bitfield ends one. The bitfields of one memory location are **one place** for exclusivity, since writing one can change another ([01](01-values-and-ownership.md#which-places-overlap)). So `buttons` and `trigger` above are one place.
- **Padding.** The bits of a storage unit that no named member covers, and an unnamed bitfield's bits, are padding, which C leaves indeterminate even after initialization ([04](04-types.md#plain-data-pod-and-bit-casts)). So `Pad`, whose second storage unit has 8 bits no bitfield covers, isn't padding-free. A bitfield member of a union fills only its own bits, so a union such as `Reg` isn't padding-free either:

    ```c
    union Reg { uint32_t en : 1; uint32_t raw; };   // 'en' fills one bit of 32: not padding-free
    ```

- **No niche.** A bitfield never gives an optional its niche, since its width may leave no room for the `nil` value ([04](04-types.md#optionals)).
- **Plain data.** A bitfield counts as its type for `Pod`, except a one-bit `bool`, which has no invalid value although `Bool` isn't `Pod` ([04](04-types.md#plain-data-pod-and-bit-casts)).

**Unions.** An imported union, named or an anonymous member whose members the enclosing struct shows directly, follows [04](04-types.md#untagged-unions).

**Enums.** An imported enum's underlying integer type, the `R` of `@c enum E: R`, is the one the header fixes, as a C23 header can, or else the one the target ABI gives it.

```c
enum Team : uint32_t { TEAM_RED, TEAM_BLUE };    // C23 fixes the underlying type: @c enum Team: UInt32
```

**An enum whose fixed underlying type is `bool` has none**, since `Bool` isn't an integer type, and imports as an anonymous enum does: a `Bool` constant per enumerator, with `E` a `typealias` for `Bool`.

**How an enum imports depends on what its header declares:**

- **An imported enum is open unless its header declares it closed.** C lets an enum object hold any value of its underlying type, so every `R` is a valid `E`, `E(rawValue:)` never fails, and a `when` over it needs an `else` arm:

    ```swift
    // C: enum Stick { STICK_LEFT, STICK_RIGHT };
    when stick {
        .STICK_LEFT  -> moveCamera()
        .STICK_RIGHT -> aim()
        else         -> {}           // required: 'stick' may hold any value of its underlying type
    }
    ```

- **Closed enums.** An enum the header declares closed, with `__attribute__((enum_extensibility(closed)))`, imports as a Rayo enum does: it holds only its cases, so `E(rawValue:)` fails on any other value and a `when` that covers every case needs no `else` arm.
- **Flag enums.** A flag enum (`__attribute__((flag_enum))`) imports as a flag set: a struct holding a `rawValue` of the underlying type, with these members:
    - a static constant per flag;
    - an `init()` of no flags;
    - `==`;
    - the bitwise operators `|`, `&`, `^` and `~` between flag sets;
    - `contains(_:)`.
- **Shared values.** Enumerators that share a value name one value: the first imports as a case, and each later one as a static constant equal to it.

### C calls in `@noalloc` code: `noalloc`

```swift
import c "mixer.h" unsafe { noalloc mix_block, apply_gain }   // in the import's config block
extern c noalloc func soft_clip(_ x: Float) -> Float           // on an extern c func declaration
```

**A `noalloc` rule for a function `f` states that `f`, and everything it calls, allocates no memory**, from C's allocator or a Rayo one, so a `@noalloc` function may call it ([06](06-memory-and-allocators.md#allocation-failure)). Any other C function may allocate.

**The rule is asserted, not checked**, so the config block that holds it is spelled `unsafe { … }` ([10](10-errors-and-safety.md#unverified-promises)). An `extern c func` declares it with `noalloc` before `func`, as above.

## Inline C

An `extern c` block holds C code inside the Rayo module:

```swift
extern c """
    #include <math.h>
    static inline float rsqrt(float x) { return 1.0f / sqrtf(x); }
    """
extern c func rsqrt(_ x: Float) -> Float             // declared for the type checker; unsafe to call
```

**An `extern c` block's C is compiled with its module, and Rayo code calls a function it defines through an `extern c func` declaration.**

- **Headers.** The block sees the headers it includes, read with the preprocessor definitions the build declares for it ([09](09-compile-time.md#what-a-build-declares)). Every type it sees that an import also gives Rayo must read there as the import reads it, or the build fails, since both name one type ([above](#the-identity-of-an-imported-type)).
- **Unsafe code.** The block is arbitrary C, so it counts as `unsafe` code.
- **Declarations.** An `extern c func` declaration is an unverified promise ([10](10-errors-and-safety.md#unverified-promises)) of these:
    - its module's `extern c` code, or a library the build links, defines a C function of that signature;
    - that function needs at most the stack its calls check for ([above](#the-stack-a-c-call-needs));
    - when the declaration says `noalloc`, the function allocates nothing ([above](#c-calls-in-noalloc-code-noalloc)).

  Its parameter and result types have C representations, and pass as an `@export` function's do ([below](#calling-rayo-from-c)). Calling it is `unsafe`, as every call to C is.

## Calling Rayo from C

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

- **The name is a promise.** An exported name shares one namespace with every C symbol the program links or loads. So `@export` on a function is an unverified promise ([10](10-errors-and-safety.md#unverified-promises)): nothing else in the program defines that name, and every C caller of it calls this signature. The build fails when two objects it links define one name.
- **Parameters pass by value.** Each passes in its C representation, whatever its Rayo convention (borrowed or `owned`), except a `mutable` one, which passes as a pointer. The same holds for `@c func`, the form a callback takes ([below](#callbacks)).
- **No throwing.** Neither kind of function can throw, since C has no form for it.
- **Panics stay in Rayo.** A panic in the body is reported as any panic is ([10](10-errors-and-safety.md#panics)), and Rayo never unwinds.
- **Not generic.** An `@export` function has no type parameters and no `some P` parameter, since C calls one symbol.

**The build writes a C header for each module.** It holds these, each in its C representation ([below](#c-representations)):

- every exported function;
- every `@export(c)` type;
- every type that the signature of one of the module's exported functions, `@c func`s or `extern c func`s uses;
- every type that one of the module's `@c` types uses.

**For each `List`, `String` and `TrailingArray` type among them, the header declares a free function**: an `@export` function that takes the value `owned` and destroys it. So a call of the free function enters Rayo as any call from C does ([below](#c-entries-and-threads)).

### C representations

**A type's C representation is the C type its values cross to C as.** It has the Rayo type's size and alignment, and these rules give it:

- **Imported types.** Each Rayo type that a C type imports as ([above](#what-imports-as-what)), such as `Int32`, `Bool`, a raw pointer, `Simd<Float, 4>` or an imported `@c union`, crosses as that C type. When several import as it, it crosses as the first one the import table lists that the target has: `Int` as `ptrdiff_t`, `UInt` as `size_t` and `*T?` as `T*`.
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
| struct | the C struct its layout gives ([04](04-types.md#structs)), each field in its representation |
| `[N of T]` field | a `T name[N]` field, each element in its representation |
| tuple | `struct { T0 _0; T1 _1; … }`, the C struct its layout gives ([04](04-types.md#tuples-ranges-and-arrays)), each element in its representation |
| `Simd<T, N>` over a number type, other than the vector types the table above imports | `struct { _Alignas(A) T lanes[N]; }`, where `A` is the vector's alignment, so a 3-lane vector's fourth slot is padding ([04](04-types.md#simd-and-math)) |
| union | the C union its layout gives ([04](04-types.md#untagged-unions)), each member in its representation |
| enum without payloads | its stored integer type, the raw type if it has one ([04](04-types.md#enums)), with a constant per case holding its stored value |
| enum with payloads | `struct { tag; union { … } }`, its tag as an enum without payloads stores it |
| `T?` with a niche | same layout as `T`, with one value meaning `nil` (below) |
| other `T?` | `struct { T value; bool has; }` |
| `Handle<T>`, `WeakPointer<T>`, `WeakShared<T>` | `uint64_t`: the bits (`h.bits`, `w.bits`), which only Rayo resolves |
| `List<T>`, `String` | `struct { T* ptr; int64_t count; int64_t cap; uint64_t alloc; }` (below) |
| `RawAllocation` | `struct { void* address; int64_t size; int64_t align; uint64_t alloc; }` ([10](10-errors-and-safety.md#raw-allocations)) |
| `TrailingArray<H, E>` | `struct { H* ptr; int64_t count; uint64_t alloc; }`, where `ptr` points at the header and the `count` elements start at the offset 04 gives ([04](04-types.md#variable-sized-structs-trailingarray)), which the generated header names |

- **The `nil` value of a niche** is the one 04 gives ([04](04-types.md#optionals)), and the generated header names it.
- **A `String` that still uses a literal's immortal bytes** ([04](04-types.md#literals)) has `cap` 0 and a non-null `ptr`.

**Every other type has no C representation**, and can't appear in an exported signature or a `@c` type. That includes:

- function-typed values other than `@c` pointers;
- weak pointers and weak links to `any P`;
- `Name`;
- any type whose layout the language or a library leaves open ([11](11-compilation-model.md#what-the-language-leaves-open)), such as a task's state, `Borrow`, `MutableRef`, `Slice`, `Pin` and `LocalPin`;
- any type that is or holds a `Synchronized` value, which synchronizes itself and whose identity is its address ([07](07-concurrency.md#atomics-and-locks)).

### What a C entry hands back to C

**A `Span<T>` or `StringView` handed back to C views what it depends on** ([02](02-views-and-dependencies.md#dependencies)), and C uses it only while that memory lives. What a C entry ([below](#c-entries-and-threads)) hands back to C is its scoped result, and whatever it stores into a `mutable` parameter or through a view a parameter carries.

**Once a C entry returns, nothing in Rayo holds what it borrowed**: a lock guard is released, and an open no longer counts as a use of its allocator ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)).

**So what a C entry hands back to C may depend only on these:**

- its parameters;
- `const`s;
- places in a global `let`'s own storage, reached through stored fields, inline array elements and enum payloads only, since no global is destroyed ([07](07-concurrency.md#shutdown)).

**What it hands back never depends on a lock guard, `Once.get()` or an owning value's storage**, such as a global `List`'s elements. A reset or an unregistration could free those while C still holds what was handed back.

### Ownership that crosses to C

**Ownership crosses to C in these ways:**

- as a `List`, `String` or `TrailingArray` that a C entry returns to C or stores through a `mutable` parameter C lent, or that Rayo passes to an `owned` parameter of an `extern c func` or a `@c` pointer ([above](#c-representations));
- as a weak pointer from `UniquePointer.leak`, which comes back through `adopt` ([03](03-handles-and-objects.md#weak-pointers-as-bits-and-handing-objects-to-c));
- as a weak link from `Shared.leak`, which comes back through `adopt` ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners));
- as a `RawAllocation` through `Box.leak` and the `unsafe` `Box.adopt` ([06](06-memory-and-allocators.md#owning-boxes)).

**An object or a `Shared` value reached through a protocol crosses as its weak pointer's or weak link's bits.** Rayo rebuilds the existential with `WeakPointer<any P>(bits:)` or `WeakShared<any P>(bits:)`.

## Callbacks

A `@c func` is a Rayo function that C can call through a function pointer:

```swift
let audioEvents = MpscQueue<AudioEvent>(capacity: 256)       // global let: Synchronized, safe from any thread

@c func onAudioEvent(_ user: *Void?, _ event: CInt) {        // runs on the audio library's thread
    audioEvents.push(AudioEvent(raw: copy event))
}

unsafe { platform_set_audio_callback(onAudioEvent, nil) }
// the program drains audioEvents with pop() wherever it processes input
```

**A function pointer type imported from a C header has borrowed parameters**, so a `@c func` with an `owned` parameter doesn't convert to it ([05](05-protocols-generics-and-closures.md#c-function-pointers)): C calling through it never gives up what it passes.

### C entries and threads

**C may call a C entry from any thread.** A **C entry** is a `@c func`, an `@export` function or a closure literal converted to a `@c` pointer, all of which have the C calling convention.

**A call from C attaches the calling thread on first entry**, if Rayo didn't create it and C hasn't attached it ([below](#embedding-rayo-in-a-c-program)). Attaching initializes the thread's thread-locals and gives the runtime its stack's bounds ([below](#what-the-runtime-needs-from-the-platform)), which Rayo code needs before it runs there.

## What C must uphold

**C that calls Rayo, that Rayo calls, or that reaches Rayo memory has the obligations that `unsafe` Rayo code would have in its place.** The argument that safe code is sound assumes C keeps them, as it assumes `unsafe` code keeps its own ([13](13-soundness.md#the-unsafe-boundary)). They are these:

- **Valid values.** Every value C passes, returns or writes into Rayo memory is valid for its Rayo type ([10](10-errors-and-safety.md#raw-accesses)):
    - a `Bool` is 0 or 1, and a Rayo enum, or an imported enum declared closed, holds one of its cases;
    - a non-null pointer isn't null, a span's pointer included when its count is 0, since null is a `Span<T>?`'s `nil`;
    - a raw pointer need only be non-null where its type says so, since only `unsafe` code dereferences it;
    - a `String`, `StringView` or `StaticString` holds whole UTF-8 sequences ([04](04-types.md#strings));
    - a weak pointer, a weak link or a `Handle` holds bits that Rayo gave out for that type, stale or not;
    - a `StaticSpan`, a `StaticString` or a `String` with `cap` 0 points at bytes that stay valid and unwritten for the rest of the run, a `StaticString`'s followed by a NUL.
- **One owner per move-only value.** A move-only value's bytes are never copied to stand for a second value ([10](10-errors-and-safety.md#values-views-and-threads)).
- **Values that stay on one thread.** A value whose type isn't `Sendable` reaches Rayo, and is freed through the header, only on its own thread ([10](10-errors-and-safety.md#values-views-and-threads)), unless nothing but the raw pointers it holds keeps its type from being `Sendable`. Its own thread is the one Rayo gave it out on, or, for a thread-bound `WeakPointer`, its object's home thread ([03](03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)).
- **Spans and `mutable` parameters.** Spans, `mutable` parameters and the views C hands Rayo meet these ([10](10-errors-and-safety.md#what-unsafe-code-upholds)):
    - a span, or the pointer that a `mutable` parameter passes, reaches its `count` places, or one. For the whole call, each of those places is live, aligned for its type and holding a valid value, and writable for a `MutableSpan` or `mutable` parameter;
    - a `MutableSpan` or `mutable` parameter is the only access to its memory during the call, by C or by Rayo, and nothing writes the memory a `Span` or `StringView` parameter views;
    - a view, or a value holding one, that C returns to Rayo or writes into Rayo memory, through a `mutable` parameter, a `MutableSpan` or a pointer, addresses live memory for as long as its dependency set says. Rayo gives it that set by rules 3 and 4 ([02](02-views-and-dependencies.md#dependencies)).
- **Known stacks.** Rayo code runs only on a stack whose bounds the runtime knows, so running out of it panics instead of writing past its end ([10](10-errors-and-safety.md#panics)):
    - C that switches a thread between stacks, as a fiber scheduler does, declares the new stack's bounds with `rayo_thread_set_stack` after each switch, back to the thread's own stack included, before Rayo code runs there ([below](#embedding-rayo-in-a-c-program));
    - a Rayo frame that such a switch suspends resumes only on the thread it began on, whose accesses, allocator uses and thread-locals it uses;
    - a fiber abandoned with Rayo frames on it never returns from them. C keeps its stack allocated and unmoved for the rest of the run. What the frames own leaks, and what they borrow stays borrowed, so a reset of an allocator they use panics ([06](06-memory-and-allocators.md#what-a-reset-does)).
- **Stack for C.** C that Rayo calls uses no more stack than the call checks is left ([above](#the-stack-a-c-call-needs)), or runs on a stack of its own.
- **Frames end by returning.** Control leaves a Rayo frame for good only when the frame returns, apart from the stack switches above, and its memory stays allocated until then. C never `longjmp`s over one, unwinds through one, ends its thread beneath one, or frees or reuses a stack that holds one.
- **Unloading.** C never unloads the program's code, or frees memory that its runtime or globals use, unless `rayo_shutdown` has returned `true` ([below](#embedding-rayo-in-a-c-program)), which it does only once nothing can run Rayo code or the runtime's code again.
- **Entering by a call.** C enters Rayo only by an ordinary call, never from a signal handler or an interrupt, which could arrive while its thread is in the middle of Rayo code.
- **Values C hands to Rayo.** A value C hands to Rayo in one of these ways is Rayo's from then on, so C never uses or frees it again:
    - passing it to an `owned` parameter, directly or through a `@c` pointer;
    - returning it from a C function Rayo called;
    - writing it into Rayo memory, such as through a `mutable` parameter Rayo lent C.
- **Borrowed values.** A value passed to a borrowed parameter stays its sender's, so C never frees or keeps one that Rayo passed it borrowed, nor passes it to an `owned` parameter.
- **Owning values Rayo hands C.** C frees a `List`, `String` or `TrailingArray` that Rayo handed it ([above](#ownership-that-crosses-to-c)) at most once, and only through the free function the header declares for its type. It never frees one after passing it to an `owned` parameter, returning it to Rayo or writing it into Rayo memory. It reads its elements only until the allocator its `alloc` word names is reset or unregistered ([06](06-memory-and-allocators.md#what-a-reset-does)).
- **Rayo-owned memory.** C reads Rayo-owned memory only while Rayo keeps it alive and isn't writing it, and writes it only where Rayo code with exclusive access could. It writes a `TrailingArray`'s header, or a struct whose flexible array member's elements share its tail padding, field by field, never as a whole struct, and never passes one to Rayo as a `mutable` parameter or in a `MutableSpan`. A whole store, or a write to a struct lent either way, may write all its bytes, the elements in its tail padding included ([10](10-errors-and-safety.md#raw-accesses)).
- **Immutable and synchronized memory.** C never writes memory Rayo treats as immutable, such as read-only data or a `Frozen` value behind a `Shared`, which Rayo reads without a mark. It writes a `Synchronized` value only through that value's own synchronization.

**Breaking one is undefined behavior**, as a wrong `unsafe` block is. So an entry point that takes a Rayo type relies on C to pass a valid value, while one that takes the raw form accepts anything C passes:

```swift
enum NavMode: Int32 { case walk, fly }

@export(c) func nav_set_mode(_ mesh: WeakShared<NavMesh>, _ mode: NavMode) { ... }   // C must pass a valid case

@export(c) func nav_set_mode_checked(_ bits: UInt64, _ raw: Int32) -> Bool {  // accepts anything C passes
    guard let mesh = WeakShared<NavMesh>(bits: bits) else { return false }   // nil unless the bits name a live NavMesh
    guard let mode = NavMode(rawValue: raw) else { return false }            // nil unless 'raw' is a case's value
    ...
}
```

**An entry point that takes the raw form, as `nav_set_mode_checked` does, converts it with Rayo's checked conversions:**

- a `UInt64` with `WeakShared<T>(bits:)`, with `WeakPointer<T>(bits:)`, which also checks the thread, since an object is used only on its home thread ([03](03-handles-and-objects.md#weak-pointers-as-bits-and-handing-objects-to-c)), or with `Handle<T>(bits:)`;
- a raw integer with `E(rawValue:)`.

## The platform, and embedding Rayo in C

### What the runtime needs from the platform

**The runtime needs these from the platform:**

- memory for `.system`, the platform's general-purpose heap ([06](06-memory-and-allocators.md#allocator-values));
- threads, which `Runtime.startThread` starts ([07](07-concurrency.md#starting-a-thread-runtimestartthread));
- the bounds of each stack Rayo code runs on, so running out of one panics instead of writing past its end: a C thread's when it attaches, and a fiber's when C declares it ([above](#what-c-must-uphold));
- a way to park a thread on an address and wake it, which blocking primitives wait with ([07](07-concurrency.md#parking-and-waking-a-thread));
- a monotonic clock for timeouts, such as a parked thread's;
- a way to report a panic ([10](10-errors-and-safety.md#panics)).

### Embedding Rayo in a C program

**A C program can embed Rayo, and then runs startup and shutdown itself**, with `rayo_init` and `rayo_shutdown`, where a Rayo program runs them around `main` ([07](07-concurrency.md#initialization-at-startup)). It calls Rayo through exported functions and these C exports of the runtime:

| Function | Purpose |
| --- | --- |
| `void rayo_init(void)` | Runs startup, once: the calling thread's thread-locals and the other globals' initializers, in startup order ([07](07-concurrency.md#initialization-at-startup)) |
| `bool rayo_shutdown(void)` | Shuts the runtime down: destroys the calling thread's thread-locals and objects (below), and closes entry ([07](07-concurrency.md#shutdown)), and returns whether the runtime has stopped (below) |
| `void rayo_thread_attach(void)`, `void rayo_thread_detach(void)` | Attach and detach threads Rayo didn't create, such as a middleware library's callback thread. Attaching an attached thread, or detaching one that isn't, does nothing |
| `void rayo_thread_set_stack(void* low, void* high)` | Declares the bounds of the stack the calling thread has just switched to, such as a fiber's, before it runs Rayo code there |

- **`rayo_init`.** Startup is single-threaded ([07](07-concurrency.md#initialization-at-startup)). So an entry from another thread before `rayo_init` has finished panics, and the threads the initializers started with `Runtime.startThread` are queued, and start when it returns. A second call panics too. C that an initializer calls may call back into Rayo on the same thread, and the runtime checks guard each global it reads.
- **`rayo_shutdown`.** Only the calling thread's thread-locals and objects are destroyed, since a thread's teardown runs only on that thread ([07](07-concurrency.md#thread-teardown)). Any other thread still attached, the one that called `rayo_init` included, keeps its copies, which leak. An entry from a C thread afterwards panics, except a nested one, which is let in as before ([07](07-concurrency.md#initialization-at-startup)). It returns `true` only when nothing can run Rayo code or the runtime's code again: every thread `Runtime.startThread` started has ended, and no thread has a Rayo frame on any of its stacks. Only then may C unload the program's code ([above](#what-c-must-uphold)).
- **Attaching threads.** Attaching is also implicit on first entry ([above](#c-entries-and-threads)), and initializes the thread's thread-locals. Detaching destroys them and the thread's objects, on that thread ([07](07-concurrency.md#thread-teardown)). A thread that exits without detaching, or is still attached when another calls `rayo_shutdown`, leaks them instead. Both enter Rayo as a call from C does, with the same checks ([above](#c-entries-and-threads)), so after `rayo_shutdown` either one fails as such an entry does (above).
- **Not from inside Rayo.** `rayo_thread_detach` and `rayo_shutdown` panic, before they do anything, on a thread with a Rayo frame on any of its stacks, a suspended fiber's included. That holds whether the thread is inside a call into Rayo or in a C call that Rayo made, since its Rayo frames may still use what they destroy.
- **Detaching on return.** `Runtime.detachOnReturn()`, called on a thread Rayo didn't create, detaches it when the thread next returns to C with no Rayo frame on any of its stacks, as `rayo_thread_detach` would there. On a thread Rayo started, which tears down when its body returns, it does nothing. So a `@c func` that is the start routine of a thread made through the C API tears its thread down with no C of its own.
