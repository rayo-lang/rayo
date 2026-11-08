# 11 · Compilation model

Modules decide which declarations a source file can name and what a build checks together. This chapter also states which operations may allocate or dispatch at run time, and what a target must provide to run Rayo.

## Modules and names

```swift
// in the module 'gameplay'
import engine.math                                        // its public declarations are visible here
public func armor(_ e: Enemy) -> Float { e.hp * 0.5 }    // visible to every module that imports 'gameplay'
```

**A module is a set of source files checked and built together.** It is what an import names, what `public` exports from, and what the compiler checks against the interfaces of the modules it imports ([below](#type-checking-is-local)).

**A declaration is visible throughout its module, and `public` also exports it** to every module that imports this one. `private` says explicitly that a declaration isn't `public`. A public declaration's signature names only public types.

### Import names

```swift
import engine.math as m      // named 'm', so 'm.dot' is engine.math's 'dot'
import engine.physics        // named 'physics', the path's last identifier
import c "platform.h"        // named 'platform', the header's file name without its extension
```

**An import gives the module it imports a name in the file**, which qualifies that module's declarations, as `m.dot` does:

- **With `as`**, the name is the one `as` gives.
- **Without `as`**, the name is the path's last identifier, or, for `import c`, the header's file name without its extension ([08](08-c-interop/imports-and-inline-c.md#importing-headers)). A header whose file name isn't an identifier needs `as`.

**When names clash, these rules say which declaration a name means:**

- **A name that the file's own module declares** shadows the imported declarations of that name.
- **A name that two imports declare** must be qualified where it is used.
- **Two imports that give their modules one name** are a compile error, since qualifying by that name couldn't tell the two modules apart.

### No import cycles

**A module that imports itself, directly or through others, is a compile error.** So a program's modules have an import order, which these rules rely on:

- **Generation follows it.** A module's generation reads the lists of the modules it imports, which are final by then ([09](09-compile-time/declaration-generation.md#generation-runs-in-dependency-order)).
- **Startup follows it too.** Startup initializes a module's globals only after those of every module it imports. The build's list orders the modules that the imports leave unordered ([07](07-concurrency/global-state.md#initialization-at-startup)).
- **The initialization check depends on it.** A chain of calls that startup's static check follows from an initializer ends in the initializer's own module, at its own global or one declared after it ([07](07-concurrency/global-state.md#initialization-at-startup)).
- **Error conversions depend on it.** A conversion from one error type to another is declared in one of the two types' modules. Only one of the two can see both types, so no two modules give one pair different conversions ([10](10-errors-and-safety/typed-errors.md#propagating-errors-with-try)).

### The prelude

**Every module sees std's prelude without an import.** The **prelude** is the set of std declarations that every module sees this way.

**For startup order and the initialization checks, the prelude's modules, and every module they import, count as imports of every module outside that set.** So startup initializes that set first, though no import names it ([07](07-concurrency/global-state.md#initialization-at-startup)).

```swift
struct Optional<T>(var value: T)      // this module's own Optional shadows the prelude's
let lockedOn: Handle<Enemy>? = nil    // 'T?' still means the prelude's Optional
let boxed = Optional(value: 3)        // a name written in the source means this module's Optional
```

**A module's own declaration, or an imported one, shadows a prelude name**, as a declaration named `target` shadows the prelude's `target` ([09](09-compile-time/constants-and-conditions.md#static-if-and-conditional-compilation)). The syntax and rules the language gives meaning to, such as `T?`, `nil`, a literal or a `for` loop, still mean the prelude's declarations, whatever shadows their names in a module. A name written in the source, such as `Copyable` in a conformance list, means what it names there.

**The prelude must hold what the compiler itself relies on, since the language's syntax and rules mean its declarations:**

- the language's own types, such as the numbers, `Never`, `Simd`, `Array`, `Span` and `UniquePointer`;
- the std types the language names, such as `Allocator` for `using`;
- the literal protocols ([04](04-types/collections.md#literals));
- the C type aliases ([08](08-c-interop.md));
- the protocols the compiler derives or checks;
- the functions it gives meaning to, such as `precondition` and `typeInfo`.

## Type checking is local

```swift
let dt: Float = 0.016
let step = dt * 2        // '2' is a Float, taken from the other operand in one step
let count = 60           // nothing gives this literal a type, so it is an Int
```

**Type checking needs no search.** Each module is checked against the interfaces of the modules it imports alone, never their bodies. The exception is the generic code that 05 lists as checked at each instantiation, such as a `static if` branch, which needs the bodies it instantiates or runs ([05](05-protocols-generics-and-closures/protocols-and-generics.md#checking-generic-code)).

**A module's interface is its public declarations, and what its public types' fields decide**, such as:

- whether a type is copyable, `Sendable`, `Frozen`, `Pod`, shallow or sealed;
- its niche;
- its layout.

**The interface carries those facts because other modules' checks need them, and the fields that decide them may be private.** Whether `copy` applies to an imported value, for one, depends on whether its type is copyable, which depends on all of the type's fields ([01](01-values-and-ownership/moves-copies-destruction.md#copyable-types)).

**Local type checking rules out some convenience features.** Each row gives a rule of local checking, and the feature it rules out:

| Rule | Rules out |
| --- | --- |
| Inference is local: an expression's type comes from its operands and the expected type, and no later use changes it | Constraint solving across an expression |
| A literal gets its type in one local step: from the expected type, the other operand, or a generic parameter the other arguments bind ([05](05-protocols-generics-and-closures/operators.md#operators)), else its default, such as `Int` or `Double` ([04](04-types/collections.md#literals)) | Literal-overload search |
| Operator candidates come only from the two operand types ([05](05-protocols-generics-and-closures/operators.md#operators)) | Global operator overload sets |
| Implicit conversions are a fixed set, each decided by the expected type alone: widening along a fixed order, and the few non-numeric ones that 05 lists ([05](05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)) | User-defined implicit conversions, except an error type's `@converts` initializers under `try` and `throw` ([10](10-errors-and-safety/typed-errors.md#propagating-errors-with-try)) |
| A public function's return type is written, or `Void` when omitted, never inferred; conformances are declared | Whole-program inference |
| Generics are checked once, at definition, except what 05 lists as checked per instantiation ([05](05-protocols-generics-and-closures/protocols-and-generics.md#checking-generic-code)) | Checking each instantiation of a generic body |
| Overloads on argument labels are free; type-only overloads are allowed, and resolved per call without backtracking ([05](05-protocols-generics-and-closures/functions-and-closures.md#functions-and-closures)) | Overload resolution that cascades across an expression |

## Runtime costs

```swift
for e in enemies.span {             // a plain loop over memory, in every build
    total += e.hp
}
let step = vec.normalized * speed   // vector arithmetic, never a hidden call
```

**No build of a program does work at run time that its source doesn't show, beyond the calls the language makes for it**, such as a `deinit` at a scope's end ([05](05-protocols-generics-and-closures/functions-and-closures.md#functions-and-closures)). That means:

- no reference counting;
- no copy-on-write uniqueness checks;
- no implicit boxing beyond a `Closure`'s context ([05](05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref));
- no call through a witness table outside `any P`, since generics are monomorphized ([05](05-protocols-generics-and-closures/protocols-and-generics.md#instantiation)).

**A program's run-time checks are the ones that 10 lists** ([10](10-errors-and-safety/checks-and-build-modes.md#the-checks)). They are of two kinds:

- **Checks the operations themselves make**, such as bounds and stack space.
- **Checks a type or declaration announces.** These include:
    - the exclusivity of object pointers ([03](03-handles-and-objects.md)) and of thread-locals ([07](07-concurrency/global-state.md#thread-locals));
    - an owning value's allocator word, checked at each open, which counts as a use of its allocator while what it lends lives ([06](06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it));
    - a global's initialization where the compiler can't prove it ([07](07-concurrency/global-state.md#initialization-at-startup)).

**The runtime's own work happens in these places:**

- at each entry from C, the first of which on a thread attaches that thread ([08](08-c-interop/calling-rayo-from-c.md#c-entries-and-threads));
- at a thread's teardown ([07](07-concurrency/global-state.md#thread-teardown));
- at shutdown ([07](07-concurrency/global-state.md#shutdown));
- in the operations that call it, such as a reset.

### Functions that are never calls: `@inline`

```swift
@inline func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }

speed = lerp(speed, topSpeed, 0.1)  // the arithmetic runs in place, in every build
```

**`@inline` lets a library function run without a call, as a builtin operation does.** `std.math`'s `Vec3` declares its operations `@inline`, so they never become calls at run time, as `Simd`'s builtin ones never do ([04](04-types/numbers-and-math.md#simd-and-math)).

**A direct call to an `@inline` function is never a call at run time, in any build: its body runs in place.** The same holds for an `@inline` initializer, and for the accessors of an `@inline` computed property or subscript, which are functions too. The one exception is the call that would close a cycle that an instantiation makes (below).

- **Only direct calls run in place.** A call through `any P`, a closure, a function value or a `@c` pointer is an ordinary call. So is a call from C to an `@inline` function that is `@export`. A function value made from an `@inline` function is an ordinary function.
- **A requirement call in generic code is direct.** Generics are monomorphized ([05](05-protocols-generics-and-closures/protocols-and-generics.md#instantiation)), so each instantiation calls its type argument's witness, and an `@inline` witness runs in place.
- **No cycles.** An `@inline` function that reaches itself through direct calls to `@inline` functions is a compile error, since its body would run in place inside its own expansion, without end. An `@inline` cycle that only an instantiation makes, through a requirement call, isn't an error. In that instantiation, the call that would run an `@inline` function in place inside its own expansion is an ordinary call.
- **Its body is part of what it exports.** A module that calls it needs its body to build, since the body runs in place in the caller, though not to type-check.

## What the spec defines

**The spec defines the language, the run-time behavior that programs can rely on, and the contracts that libraries implement.** The run-time behavior includes what panics, and the order of startup, thread teardown and exit. How a toolchain or runtime implements these, and everything built on the language, is outside the spec.

**Contracts** are what a library implements for the language to call or to trust:

- the protocols the language calls or derives, such as `Sequence`, the literal protocols, `Equatable`, `Awaitable` and `Attribute`;
- every `unsafe protocol`, such as `Synchronized` and `AllocatorImpl`, whose conformances the compiler can't check ([10](10-errors-and-safety/unsafe-code.md#unverified-promises));
- the promise of code that lends a scoped value to another thread ([07](07-concurrency/thread-work.md#the-librarys-promise)).

**std types appear where a rule or an example uses one**, such as `List` and `String` for literals, and the locks and queues for concurrency. The spec then states what that type checks ([10](10-errors-and-safety/checks-and-build-modes.md#the-checks)). The rest of std's catalog, and runtime policy ([below](#what-the-language-leaves-open)), are left to libraries and implementations.

## What a target must provide

**Everything the language defines can be implemented in portable C.** So a platform whose only toolchain is its vendor's C compiler can run Rayo when that compiler and its C ABI meet the requirements below. Most of them make C's types and arithmetic match Rayo's own.

**A target's C ABI:**

- represents integers in two's complement, and `float` and `double` as IEEE 754 binary32 and binary64, as Rayo's integers and its `Float` and `Double` are ([04](04-types/numbers-and-math.md#numbers));
- has an 8-bit `char`, the exact-width integer types, and a one-byte `bool` holding 0 or 1, which import as Rayo's sized integers and `Bool` ([08](08-c-interop/imports-and-inline-c.md#what-imports-as-what));
- has 64-bit data and function pointers, whose null is all zero bits;
- has 64-bit `size_t`, `ptrdiff_t`, `intptr_t` and `uintptr_t`, which import as Rayo's 64-bit `Int` and `UInt` ([08](08-c-interop/imports-and-inline-c.md#what-imports-as-what));
- places a struct's members, in the order it declares them, by the rules of 04 ([04](04-types/structs.md#structs)), so a Rayo struct crosses to C as the C struct that declares its fields in layout order ([08](08-c-interop/calling-rayo-from-c.md#c-representations)). Each integer, floating-point value, `bool` and pointer is aligned to its size.

**Its C compiler:**

- evaluates each `float` and `double` operation in its own type and rounds it once (`FLT_EVAL_METHOD` 0, no contraction), as Rayo evaluates each floating-point operation ([04](04-types/numbers-and-math.md#floating-point));
- keeps subnormals, which Rayo never flushes ([04](04-types/numbers-and-math.md#floating-point));
- provides thread-local storage;
- provides C11's atomic operations and fences, with the guarantees of the C++20 memory model that Rayo uses, and lock-free for every size `Atomic<T>` accepts, since none of Rayo's atomic operations blocks ([07](07-concurrency/synchronization.md#atomics-and-locks));
- reports a bound on the stack each function it compiles uses, as GCC's and Clang's `-fstack-usage` do, which the stack check on entry to each function needs ([10](10-errors-and-safety/checks-and-build-modes.md#the-checks)).

## What the language leaves open

**Two implementations, or two builds of one program with the same build declarations ([09](09-compile-time/attributes-and-runtime-data.md#what-a-build-declares)), can disagree about a safe program only in the points below.** Evaluation order is fixed ([01](01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin)), and so are every integer result and every float result that IEEE 754 defines exactly ([04](04-types.md)). Safe code has no undefined behavior.

**What is left is timing and order, some representations, what libraries and builds choose, and limits:**

- **Thread timing.**
- **Destruction order**: the order in which a reset or an unregistration runs the `deinit`s of the objects it destroys ([03](03-handles-and-objects.md#objects-in-arenas-and-other-allocators)), and in which a thread's teardown destroys its objects ([07](07-concurrency/global-state.md#thread-teardown)).
- **The bits of a NaN result**, which only reading its bytes as another type observes: a bit cast, a union read, a span cast or an atomic compare-and-swap.
- **Where values and code live**: the address in a raw pointer, and an address's alignment beyond what its type guarantees. `reinterpret` observes that alignment when it checks a span of storage whose type guarantees less than the target type needs ([04](04-types/data-layout.md#plain-data-pod-and-bit-casts)). Safe code never sees where a function's code lives.
- **The bits of weak pointers and weak links**, which `w.bits` shows ([03](03-handles-and-objects.md#weak-pointers-as-bits-and-handing-objects-to-c), [06](06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)).
- **The values of the ids and hashes that the language defines only by what they identify**: `T.id`, `T.layoutId` and a `Name`'s hash. Each implementation keeps them the same from build to build ([09](09-compile-time/reflection.md#what-reflection-can-read)). The order of an error union's members, which follows its members' `T.id`s, is left open with them ([10](10-errors-and-safety/typed-errors.md#error-unions)).
- **Whether two such ids or hashes collide.** A collision fails the build, or, for a `Name` interned at run time, panics or makes `Name(interning:)` return `nil` ([04](04-types/collections.md#collections-and-strings)).
- **The layouts below**, which only `T.size`, `T.alignment`, `T.isPaddingFree` and `T.layoutId` observe, and whose values no `Closure` stores inline ([05](05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)):
    - a task's state and an interpolated literal's value, which the compiler builds ([07](07-concurrency/tasks.md#semantics), [04](04-types/collections.md#strings));
    - the builtin `SoA<T>` ([04](04-types/data-layout.md#struct-of-arrays-soat));
    - the iteration views `Borrow<T>` and `MutableRef<T>` ([04](04-types/collections.md#iteration));
    - `Slice<T>` ([06](06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers));
    - the existential views `any P` and `mutable any P`, and function-typed values ([05](05-protocols-generics-and-closures.md));
    - the runtime's `BlockHeader` ([06](06-memory-and-allocators/allocator-implementations.md#writing-an-allocator-allocatorimpl)).
- **What a library leaves open**, such as:
    - the last bits of a math function like `sin`;
    - `Hasher`'s output, and so any order that depends on it;
    - the layout of its types, such as std's `Pin<T>`, `LocalPin<T>` or `FieldInfo`;
    - the bits of handles ([03](03-handles-and-objects.md#pools-and-handles)).
- **What a build reports**: the call sites it passes to allocators, or 0 ([06](06-memory-and-allocators/allocator-implementations.md#writing-an-allocator-allocatorimpl)), and what a panic report contains ([10](10-errors-and-safety/panics.md#what-a-panic-does)).
- **Resource limits**, and so where an allocation, a registration, an object's creation, a thread start, a deep recursion or a count fails ([10](10-errors-and-safety/panics.md#what-panics), [07](07-concurrency/thread-work.md#starting-a-thread-runtimestartthread)):
    - how much memory an allocator can supply ([06](06-memory-and-allocators/allocation-lifecycle.md#allocation-failure));
    - how many allocators may be registered, at once and over the run, and how many times one may be reset ([06](06-memory-and-allocators/allocator-implementations.md#how-values-record-their-allocator));
    - how many objects may be created over the run ([03](03-handles-and-objects.md#destroying-an-object));
    - how many threads the platform can start ([07](07-concurrency/thread-work.md#starting-a-thread-runtimestartthread));
    - how much stack a thread has, and the default reserve for a call into C, which `target.cStackReserve` reports ([09](09-compile-time/constants-and-conditions.md#static-if-and-conditional-compilation));
    - how far each count kept for safety goes ([10](10-errors-and-safety/panics.md#what-panics)).
- **Whether a `const` evaluation, or a chain of generic instantiations, finishes within the toolchain's limits** ([09](09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const), [05](05-protocols-generics-and-closures/protocols-and-generics.md#instantiation)). That decides only whether the program builds. Whether a global `let`'s compile-time run finishes within those limits decides only whether the global is initialized at startup or placed in read-only data ([07](07-concurrency/global-state.md#initialization-at-startup)).
