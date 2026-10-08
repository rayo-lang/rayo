# Imports and inline C

[08 · C interop](../08-c-interop.md)

## Importing headers

```swift
import c "platform.h"                                    // declarations land in module 'platform'
import c "SDL3/SDL.h" as sdl                             // explicit name
import c "vendor/fmod.h" as fmod where prefix: "FMOD_"   // strips the prefix: FMOD_System_Create → fmod.System_Create
```

**`import c` makes a header's declarations available in a Rayo module**, each as the Rayo declaration that the mapping gives it ([below](#what-imports-as-what)). An import may also take a prefix to strip and a config block:

- **`prefix:`** strips a case-sensitive match from the start of each imported function, type, enumerator, macro and variable name. A name keeps its prefix when stripping it would leave text that doesn't start an identifier, as `FMOD_3D` would, or a name that collides with another.
- **Config blocks.** An import may end with a **config block**, `unsafe { … }`, of rules about the header's C. The compiler takes each rule on trust, so the block is spelled `unsafe` ([10](../10-errors-and-safety/unsafe-code.md#unverified-promises)). It holds three kinds of rule:
    - `stack(n)`, which states the stack a function needs ([below](#the-stack-a-c-call-needs));
    - `noalloc`, which states that a function allocates nothing ([below](#c-calls-in-noalloc-code-noalloc));
    - `struct`, `union` or `enum S in "h"`, which names the header to take the type `S` from ([below](#the-identity-of-an-imported-type)).

  Its rules name declarations by their C names, before `prefix:` is stripped.

**Each `import c` reads its header with only the preprocessor definitions the build declares for that import** ([09](../09-compile-time/attributes-and-runtime-data.md#what-a-build-declares)), so no other import's macros reach it. Two imports of one header may therefore read it differently, each with its own definitions.

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

**As a value, an imported function converts only to `@c` function pointer types**, whose calls are `unsafe` too ([05](../05-protocols-generics-and-closures/functions-and-closures.md#c-function-pointers)). Only a `@c` type carries the function's stack need, which a call through any other function type wouldn't check ([below](#the-stack-a-c-call-needs)).

**A `@safe` module can `import c` a header, to name its types and constants, but it can't call its functions or use its variables**, since both need `unsafe`, which such a module rejects ([10](../10-errors-and-safety/unsafe-code.md#safe-modules)).

#### The stack a C call needs

```swift
import c "physics.h" unsafe { stack(256 * 1024) physics_step }   // in the import
extern c stack(512 * 1024) func solve(_ d: CInt) -> CInt         // on an extern c func declaration
typealias Visitor = @c stack(1 << 20) (CInt) -> Void             // in a C function pointer's type
```

**A call into C first checks that the stack its target needs is left, and panics otherwise**, so running out of stack is caught before anything is written past the stack's end ([10](../10-errors-and-safety/panics.md#what-panics)).

**The need is the one declared where the call's target is**, in one of the three places above, each `n` a `const` `Int` expression. When nothing is declared there, the need is `target.cStackReserve` bytes ([09](../09-compile-time/constants-and-conditions.md#static-if-and-conditional-compilation)).

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
| `__m128`, `float32x4_t`, `__m128i`, `int32x4_t` | `Simd<Float, 4>` / `Simd<Int32, 4>` ([04](../04-types/numbers-and-math.md#simd-and-math)), passed by value in vector registers under the platform ABI |
| `struct S { ... }` | `@c struct S` with the same layout, fields and bitfields ([below](#structs-unions-and-enums)) |
| anonymous `union`/`struct` members | Their fields are accessible directly on the enclosing struct, as in C |
| flexible array member `T data[]` | The struct without the member, as a `TrailingArray` header (below) |
| `__attribute__((packed))` / `#pragma pack(n)` / `__attribute__((aligned(n)))` | `@packed` / `@packed(n)` / `@align(n)`, with identical layout ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)) |
| incomplete `struct S;` that the reading doesn't define, and that no header its import names for it defines ([above](#the-identity-of-an-imported-type)) | `@opaque struct S`: only usable as `*S` |
| a struct or union whose layout Rayo can't reproduce, or whose members don't all map (below) | `@opaque` too |
| `typedef T N;` | `typealias N = T`, with the exceptions below |
| `union U` | `@c union U` |
| `enum E { A, B }` | `@c enum E: R`, a form only imports make, with `.A`, `.B`, **open** by default |
| anonymous `enum { A = 1 };` | a `const` of its underlying type per enumerator, and a field or variable of that enum has its underlying type |
| function | `unsafe func` with the same signature, unless it declares a calling convention other than the platform's default, such as `__vectorcall`, `ms_abi` or `pcs`, which isn't imported |
| `static const` variable of an integer, floating-point or `bool` type with a constant initializer | a `const`, as a literal macro is |
| any other variable, `extern T v;` or defined in the header | a global of type `T`, accessed only inside `unsafe`, as a bare global `var` is ([07](../07-concurrency/global-state.md#global-state)). An `_Atomic`, `_Thread_local` or `volatile` variable isn't imported |
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

  Its caller promises what 10 asks of a span made from a raw pointer ([10](../10-errors-and-safety/unsafe-code.md#what-unsafe-code-upholds)):
    - `n` valid elements there, aligned for `T`;
    - nothing else reaching them for as long as the span lives, a whole-struct write at `p` included, since they may share its tail padding.

  Rayo-allocated instances use `TrailingArray<S, T>` when the member's offset is a multiple of `T`'s alignment, since only then can the elements be both where C reads them and aligned ([04](../04-types/data-layout.md#variable-sized-structs-trailingarray)).
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

**Structs.** An imported struct's primary initializer takes the fields that reflection lists for it ([09](../09-compile-time/reflection.md#what-reflection-can-read)), in order, each labeled by its name and an anonymous union or struct member unlabeled, so `T.construct` builds one too. It also gets a zero-initializing `init()` when all-zero bytes are a valid value of every field, and an `unsafe` one otherwise, as when a field is a `_Nonnull` pointer.

**Bitfields keep the layout the target ABI gives them: each holds a run of bits in a storage unit.** So a bitfield differs from other fields in these ways:

- **Type.** A bitfield has its declared type, except an enum-typed one whose enumerators don't all survive the round trip through the field's width and the target ABI's signedness, which has the enum's raw integer type.
- **Access.** Generated accessors read and write a bitfield through a temporary, so they are access-bound projections ([02](../02-views-and-dependencies/projections-and-accessors.md#access-bound-projections)). A read or a write touches only the bytes that hold its memory location's bits, since another thread may write a neighboring field or memory location at the same time ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)). A write of a value that doesn't fit the width panics where overflow checks are on, and keeps its low bits where they are off, as an unlabeled integer conversion does ([04](../04-types/numbers-and-math.md#conversions)). A read of a signed bitfield sign-extends.
- **Places.** A **memory location** is a maximal run of adjacent nonzero-width bitfields, even across storage units, and a non-bitfield member or a zero-width bitfield ends one. The bitfields of one memory location are **one place** for exclusivity, since writing one can change another ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)). So `buttons` and `trigger` above are one place.
- **Padding.** The bits of a storage unit that no named member covers, and an unnamed bitfield's bits, are padding, which C leaves indeterminate even after initialization ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)). So `Pad`, whose second storage unit has 8 bits no bitfield covers, isn't padding-free. A bitfield member of a union fills only its own bits, so a union such as `Reg` isn't padding-free either:

    ```c
    union Reg { uint32_t en : 1; uint32_t raw; };   // 'en' fills one bit of 32: not padding-free
    ```

- **No niche.** A bitfield never gives an optional its niche, since its width may leave no room for the `nil` value ([04](../04-types/enums.md#optionals)).
- **Plain data.** A bitfield counts as its type for `Pod`, except a one-bit `bool`, which has no invalid value although `Bool` isn't `Pod` ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)).

**Unions.** An imported union, named or an anonymous member whose members the enclosing struct shows directly, follows [04](../04-types/enums.md#untagged-unions).

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
        .STICK_LEFT  { moveCamera() }
        .STICK_RIGHT { aim() }
        else         {}              // required: 'stick' may hold any value of its underlying type
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

**A `noalloc` rule for a function `f` states that `f`, and everything it calls, allocates no memory**, from C's allocator or a Rayo one, so a `@noalloc` function may call it ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)). Any other C function may allocate.

**The rule is asserted, not checked**, so the config block that holds it is spelled `unsafe { … }` ([10](../10-errors-and-safety/unsafe-code.md#unverified-promises)). An `extern c func` declares it with `noalloc` before `func`, as above.

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

- **Headers.** The block sees the headers it includes, read with the preprocessor definitions the build declares for it ([09](../09-compile-time/attributes-and-runtime-data.md#what-a-build-declares)). Every type it sees that an import also gives Rayo must read there as the import reads it, or the build fails, since both name one type ([above](#the-identity-of-an-imported-type)).
- **Unsafe code.** The block is arbitrary C, so it counts as `unsafe` code.
- **Declarations.** An `extern c func` declaration is an unverified promise ([10](../10-errors-and-safety/unsafe-code.md#unverified-promises)) of these:
    - its module's `extern c` code, or a library the build links, defines a C function of that signature;
    - that function needs at most the stack its calls check for ([above](#the-stack-a-c-call-needs));
    - when the declaration says `noalloc`, the function allocates nothing ([above](#c-calls-in-noalloc-code-noalloc)).

  Its parameter and result types have C representations, and pass as an `@export` function's do ([Calling Rayo from C](calling-rayo-from-c.md#calling-rayo-from-c)). Calling it is `unsafe`, as every call to C is.
