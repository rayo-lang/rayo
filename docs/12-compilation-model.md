# 12 · Compilation model

## Modules and names

```swift
// in the module 'gameplay'
import engine.math                                        // its public declarations are visible here
public func armor(_ e: Enemy) -> Float { e.hp * 0.5 }    // visible to every module that imports 'gameplay'
```

- **Modules.** A module is a set of source files checked and built together. A declaration is visible throughout its module, and `public` also exports it; `private` says explicitly that it isn't `public`. A public declaration's signature names only public types. Every module also sees std's **prelude** without an import, and for startup order and the initialization checks, the prelude's modules, and every module they import, count as imports of every module outside that set ([07](07-concurrency.md#initialization-at-startup)).
- **Import names.** An import names the module in the file by the name `as` gives it, as in `import engine.math as m`, where `m.dot` names that module's `dot`; otherwise by its path's last identifier, `math` above, or, for `import c`, by the header's file name without its extension, `platform` for `"platform.h"` ([09](09-c-interop.md#importing-headers)). A header whose file name isn't an identifier needs `as`. The file's own module's declarations shadow imported ones, and a name that two imports declare must be qualified where it is used. Two imports that give their modules one name are a compile error.
- **No import cycles.** A module that imports itself, directly or through others, is a compile error. So a program's modules have an import order, which generation follows ([10](10-compile-time.md#generation-runs-in-dependency-order)), and so does startup, with the build's list ordering modules that the imports leave unordered ([07](07-concurrency.md#initialization-at-startup)).
- **The prelude.** The prelude must hold what the compiler itself relies on: the language's own types, such as the numbers, `Never`, `Simd`, `Array`, `Span` and `UniquePointer`; the std types the language names, such as `Allocator` for `using`; the literal protocols ([04](04-types.md#literals)); the C type aliases ([09](09-c-interop.md)); the protocols the compiler derives or checks; and the functions it gives meaning to, such as `precondition` and `typeInfo`. A declaration of the module's own, or an imported one, shadows a prelude name, as it does `target` ([10](10-compile-time.md)). The syntax and rules the language gives meaning to, such as `T?`, `nil`, a literal or a `for` loop, always mean the prelude's declarations, whatever shadows their names in a module; a name written in the source, such as `Copyable` in a conformance list, means what it names there.

## Type checking is local

```swift
let dt: Float = 0.016
let step = dt * 2        // '2' is a Float, taken from the other operand in one step
let count = 60           // nothing gives this literal a type, so it is an Int
```

**Type checking needs no search.** Outside what [05](05-protocols-generics-and-closures.md#protocols-and-generics) lists as checked at instantiation, each module is checked against the interfaces of the modules it imports alone: their public declarations, and what their public types' fields decide, such as whether a type is copyable, `Sendable`, `Frozen`, `Pod`, shallow or sealed, its niche and its layout. Those checks at instantiation need the bodies they instantiate or run. That rules out some convenience features:

| Rule | Rules out |
| --- | --- |
| Inference is local: an expression's type comes from its operands and the expected type, and no later use changes it | Constraint solving across an expression |
| A literal gets its type in one local step: from the expected type, the other operand, or a generic parameter the other arguments bind ([05](05-protocols-generics-and-closures.md#operators)), else its default, such as `Int` or `Double` ([04](04-types.md#literals)) | Literal-overload search |
| Operator candidates come only from the two operand types ([05](05-protocols-generics-and-closures.md#operators)) | Global operator overload sets |
| Implicit conversions are a fixed set, each decided by the expected type alone: widening along a fixed order, and the few non-numeric ones [05](05-protocols-generics-and-closures.md#implicit-conversions) lists | User-defined implicit conversions, except an error type's `@converts` initializers under `try` and `throw` ([11](11-errors-and-safety.md#propagating-errors-with-try)) |
| A public function's return type is written, or `Void` when omitted, never inferred; conformances are declared | Whole-program inference |
| Generics are checked once, at definition, except what [05](05-protocols-generics-and-closures.md#protocols-and-generics) lists as checked per instantiation | Checking each instantiation of a generic body |
| Overloads on argument labels are free; type-only overloads are allowed, and resolved per call without backtracking ([05](05-protocols-generics-and-closures.md#functions-and-closures)) | Overload resolution that cascades across an expression |

## Runtime costs

```swift
for e in enemies.span {             // a plain loop over memory, in every build
    total += e.hp
}
let step = vec.normalized * speed   // vector arithmetic, never a hidden call
```

**No build of a program does work at run time that its source doesn't show, beyond the calls the language makes for it ([05](05-protocols-generics-and-closures.md#functions-and-closures))**: no reference counting, no copy-on-write uniqueness checks, no implicit boxing beyond a `Closure`'s context ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref)), and no call through a witness table outside `any P`, since generics are monomorphized ([05](05-protocols-generics-and-closures.md#protocols-and-generics)). Its run-time checks are the ones [11](11-errors-and-safety.md#the-checks) lists: those the operations themselves make, such as bounds and stack space, and those a type or declaration announces, such as the object pointers' and thread-locals' exclusivity ([03](03-handles-and-objects.md), [07](07-concurrency.md#global-state)), an owning value's allocator word, checked at each open ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)), and a global's initialization where the compiler can't prove it ([07](07-concurrency.md#initialization-at-startup)). The runtime's own work happens at section entries, at a thread's teardown ([07](07-concurrency.md#global-state)) and at exit ([08](08-grace-periods-and-checkpoints.md#at-exit-reclaim-then-close-entry)): an entry from C attaches its thread the first time ([09](09-c-interop.md#threads-and-sections)), and an outermost entry, the one after a checkpoint included, runs the `deinit`s queued to the thread ([08](08-grace-periods-and-checkpoints.md#deinits-queued-to-a-thread)).

### Functions that are never calls: `@inline`

```swift
@inline func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

speed = lerp(speed, topSpeed, 0.1)  // the arithmetic runs in place, in every build
```

**A direct call to an `@inline` function is never a call at run time, in any build: its body runs in place**, except the one call that would close a cycle an instantiation makes (below). The same holds for an `@inline` initializer, and for the accessors of an `@inline` computed property or subscript, which are functions too.

- **Only direct calls.** A call through `any P`, a closure, a function value or a `@c` pointer is an ordinary call, and a function value made from an `@inline` function is an ordinary function. So is a call from C to an `@inline` function that is `@export`. A call to a protocol requirement in generic code is direct: each instantiation calls its type argument's witness, so an `@inline` witness runs in place.
- **No cycles.** An `@inline` function that reaches itself through direct calls to `@inline` functions is a compile error. An `@inline` cycle that only an instantiation makes, through a requirement call, isn't an error: in that instantiation, the call that would run an `@inline` function in place inside its own expansion is an ordinary call.
- **Its body is part of what it exports.** A module that calls it needs its body to build, though not to type-check.

## What the spec defines

**The spec defines the language, the run-time behavior programs can rely on, such as what panics and the order of startup, thread teardown and exit, and the contracts libraries implement. How a toolchain or runtime implements them, and everything built on the language, is outside it.**

- **Contracts** are the protocols the language calls or derives, such as `Sequence`, the literal protocols, `Equatable`, `Awaitable` and `Attribute`; every `unsafe protocol`, such as `Synchronized` and `AllocatorImpl`; and the promise of code that lends a scoped value to another thread ([07](07-concurrency.md#the-librarys-promise), [11](11-errors-and-safety.md#safe-modules)).
- **std types** appear where a rule or an example uses one, such as `List` and `String` for literals and the locks and queues for concurrency, and the spec then states what that type checks ([11](11-errors-and-safety.md#the-checks)). The rest of std's catalog, and runtime policy ([below](#what-the-language-leaves-open)), are left to libraries and implementations.

## What a target must provide

Everything the language defines can be implemented in portable C, so a platform whose only toolchain is its vendor's C compiler can run Rayo when that compiler and its C ABI meet these requirements:

**A target's C ABI represents integers in two's complement, and `float` and `double` as IEEE 754 binary32 and binary64. Its `char` is 8 bits, it has the exact-width integer types, and its `bool` is one byte holding 0 or 1. It has 64-bit data and function pointers, whose null is all zero bits, and 64-bit `size_t`, `ptrdiff_t`, `intptr_t` and `uintptr_t`, and lays out structs as Rayo does: each integer, floating-point value, `bool` and pointer aligned to its size, and every struct by the rule of [04](04-types.md#structs). Its C compiler evaluates each `float` and `double` operation in its own type and rounds it once (`FLT_EVAL_METHOD` 0, no contraction), keeps subnormals, and provides thread-local storage and C11's atomic operations and fences, with the guarantees of the C++20 memory model ([07](07-concurrency.md#atomics-and-locks)), lock-free for every size `Atomic<T>` accepts ([07](07-concurrency.md#atomics-and-locks)), and reports a bound on the stack each function it compiles uses, as GCC's and Clang's `-fstack-usage` do, which the stack check on entry to each function needs ([11](11-errors-and-safety.md#what-panics)).**

## What the language leaves open

Evaluation order ([01](01-values-and-ownership.md#evaluation-order-and-when-a-calls-borrows-begin)), every integer result, and every float result IEEE 754 defines exactly ([04](04-types.md)) are fixed, and safe code has no undefined behavior. **So two implementations, or two builds of one program with the same build declarations ([10](10-compile-time.md#what-a-build-declares)), can disagree about a safe program only in these:**

- thread timing;
- the bits of a NaN result, which only reading its bytes as another type observes: a bit cast, a union read, a span cast or an atomic compare-and-swap;
- where values and code live: the address in a raw pointer, and an address's alignment beyond what its type guarantees, which `reinterpret` observes when it checks a span of storage whose type guarantees less than the target type needs ([04](04-types.md#plain-data-pod-and-bit-casts)). Safe code never sees where a function's code lives;
- what a library leaves open, such as the last bits of a math function like `sin`, `Hasher`'s output and so any order that depends on it, the layout of its types, such as std's `Pin<T>`, `LocalPin<T>` or `FieldInfo`, and the bits of handles ([03](03-handles-and-objects.md#pools-and-handles));
- the bits of weak pointers and weak links, which `w.bits` shows ([03](03-handles-and-objects.md#weak-pointers-as-bits-and-handing-objects-to-c), [06](06-memory-and-allocators.md#sharedt-data-with-many-owners));
- the values of ids and hashes that the language defines only by what they identify, `T.id`, `T.layoutId` and a `Name`'s hash, which one implementation keeps from build to build ([10](10-compile-time.md#what-reflection-can-read)), and so the order of an error union's members ([11](11-errors-and-safety.md#error-unions));
- whether two such ids or hashes collide, which fails the build, or, for a `Name` interned at run time, panics, or makes `Name(interning:)` return `nil` ([04](04-types.md#collections-and-strings));
- the layout of a task's state and an interpolated literal's value, which the compiler builds ([07](07-concurrency.md#semantics), [04](04-types.md#strings)), of the builtin `SoA<T>` ([04](04-types.md#struct-of-arrays-soat)), the iteration views `Borrow<T>` and `MutableRef<T>` ([04](04-types.md#iteration)), `Slice<T>` ([06](06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers)), the existential views `any P` and `mutable any P` and function-typed values ([05](05-protocols-generics-and-closures.md)), and of the runtime's `BlockHeader` and `BlockList` ([06](06-memory-and-allocators.md#writing-an-allocator-allocatorimpl)), which only `T.size`, `T.alignment`, `T.isPaddingFree` and `T.layoutId` observe, and which no `Closure` stores inline ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref));
- resource limits: how much memory an allocator can supply, how many allocators may be registered at once and over the run, and how many times one may be reset ([06](06-memory-and-allocators.md#how-values-record-their-allocator)), how many objects may be created over the run ([03](03-handles-and-objects.md#destroying-an-object)), how many threads the platform can start ([07](07-concurrency.md#starting-a-thread-runtimestartthread)), how much stack a thread has and the default reserve for a call into C, which `target.cStackReserve` reports ([10](10-compile-time.md#static-if-and-conditional-compilation)), and how far each count kept for safety goes ([11](11-errors-and-safety.md#what-panics)), so where an allocation, a registration, an object's creation, a thread start, a deep recursion or a count fails ([11](11-errors-and-safety.md#what-panics), [07](07-concurrency.md#starting-a-thread-runtimestartthread));
- what a build reports: the call sites it passes to allocators, or 0 ([06](06-memory-and-allocators.md#writing-an-allocator-allocatorimpl)), and what a panic report contains ([11](11-errors-and-safety.md#what-a-panic-does));
- runtime policy, within what [08](08-grace-periods-and-checkpoints.md) guarantees: when retired memory is reclaimed, so which thread runs, before exit, a retired value's `deinit` that [08](08-grace-periods-and-checkpoints.md#who-reclaims-and-when) gives to the reclaimer, the order in which a thread runs several retired or queued `deinit`s ([08](08-grace-periods-and-checkpoints.md#deinits-queued-to-a-thread)), and what the time limit at exit cuts short;
- whether a `const` evaluation, or a chain of generic instantiations, finishes within the toolchain's limits ([10](10-compile-time.md#running-code-at-compile-time-const), [05](05-protocols-generics-and-closures.md#protocols-and-generics)), which decides only whether the program builds, and whether a global `let`'s does, which decides only whether it is initialized at startup or placed in static data ([07](07-concurrency.md#initialization-at-startup)).
