# Unsafe code

[10 · Errors and safety](../10-errors-and-safety.md)

```swift
unsafe {
    let p: *Particle = ptr(to: &particles[0])
    p[3].pos = .zero
    memcpy(dst, src, n)
}
let now = unsafe plat.time_seconds()                                // one expression

unsafe func blit(_ dst: *UInt8, _ src: *UInt8, _ n: Int) { ... }   // callers need unsafe too
```

**An `unsafe` block marks code whose correctness the compiler takes on trust.** Checks stay as they are inside it, and `unchecked { }` turns them off ([`unchecked` blocks](checks-and-build-modes.md#unchecked-blocks)).

**An `unsafe` block covers all the code written inside it, including the bodies of closure literals there.** `unsafe` before an expression is an `unsafe` block around its operand, as the precedence table of 12 binds it ([12](../12-grammar/constructs.md#expressions)):

```swift
let sum = unsafe a.pointee + b.pointee      // error: 'unsafe' covers only a.pointee, and b.pointee needs it too
let total = unsafe (a.pointee + b.pointee)  // covers both reads
```

**The body of an `unsafe func` isn't an `unsafe` block.** It writes `unsafe` where it needs it, as any function does.

## What needs `unsafe`

**These operations need `unsafe`, since the compiler takes their correctness on trust:**

- dereferencing or offsetting a raw pointer, and converting an integer to a pointer ([below](#raw-pointers));
- taking an address with `ptr(to:)` ([below](#taking-an-address));
- the raw-memory operations ([below](#raw-memory)), and resizing or freeing a raw allocation ([below](#raw-allocations));
- calls into C, since a header can't say that a pointer outlives the call, or that a buffer holds `n` elements ([08](../08-c-interop/imports-and-inline-c.md#calling-imported-functions));
- calls through `@c` pointers, since the type can't tell a Rayo function from a C one ([05](../05-protocols-generics-and-closures/functions-and-closures.md#c-function-pointers)), and calls to `unsafe` functions;
- using a field declared `unsafe`, which `unsafe` code trusts, such as `Span`'s `baseAddress` ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)), whether by name, through reflection or as a `SoA` column;
- accessing a bare global `var` ([07](../07-concurrency/global-state.md#global-state)) or an imported C variable ([08](../08-c-interop/imports-and-inline-c.md#what-imports-as-what)), since every thread can reach it;
- converting a function to a `@c` type by C representations alone, or a `@c` value to a `@c noalloc` one ([05](../05-protocols-generics-and-closures/functions-and-closures.md#c-function-pointers));
- reading a union member where 04 requires it, since what another member's write left there may not be a valid value of it ([04](../04-types/enums.md#untagged-unions)).

**No `unsafe` call is hidden**, so every promise that `unsafe` code makes is made at a visible `unsafe` site ([13](../13-soundness/types-and-boundaries.md#the-unsafe-boundary)).

- **An `unsafe` declaration** is used only inside `unsafe`, or through an `unsafe` function type, an `unsafe` requirement or a `: unsafe P` conformance. That holds for an `unsafe` declaration of any kind: a function, an initializer, an operator, a subscript or an accessor.
- **An imported or `extern c` function** is used only inside `unsafe`, or through a `@c` pointer, whose calls need `unsafe` ([05](../05-protocols-generics-and-closures/functions-and-closures.md#c-function-pointers)).

So a call the language makes on the code's behalf is allowed only where the call written out would be. Examples are a `@converts` initializer under `try` ([Propagating errors with `try`](typed-errors.md#propagating-errors-with-try)), and the `==` of an expression pattern ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)).

## Raw pointers

**`*T` is a non-null raw pointer.** `*T?` is nullable, with the same size and ABI as a C pointer, since its `nil` is the null pointer ([04](../04-types/enums.md#optionals)).

- **Untyped pointers.** `*Void` points at memory of no stated type, and `p.cast(to: U.self)` converts between pointer types.
- **Integers.** Converting a pointer to an integer (`UInt(bitPattern: p)`) is safe. Converting an integer to a pointer is `unsafe`.
- **Reading and offsetting.** `p.pointee` is the `T` at `p`, `p + n` is `n` times `T`'s size further on, and `p[i]` is `(p + i).pointee`. They need a `T` whose size is known and nonzero. So `*Void` and a pointer to an `@opaque` type have none of them, and byte offsets go through `p.cast(to: UInt8.self)`.
- **Alignment.** Every type's size is a multiple of its alignment, so consecutive values stay aligned.

## What `unsafe` code upholds

**`unsafe` code keeps the rules of this section.** They are the invariants that make safe code free of undefined behavior, stated for `unsafe` code. Safe code keeps them by the rules of the other chapters, and its soundness assumes that `unsafe` code and C keep them too ([13](../13-soundness.md#the-invariants)).

The rules say what an allocation is, what each access through a raw pointer must satisfy, and what the values and views that `unsafe` code leaves behind promise to the code that uses them.

### Allocations

**Bounds and liveness are judged per allocation.** An **allocation** is one block of storage, which accesses stay inside and which is live or freed as a whole. It is one of these:

- storage that Rayo gave out from an allocator;
- the storage of a local, a temporary or a global, each one allocation;
- memory that C, the platform or a device provides, for as long as its provider keeps it.

**When an allocation is live:**

- **One from an allocator** is live until it is freed, by its owner or by a reset or an unregistration ([06](../06-memory-and-allocators/arena-safety.md#what-a-reset-does)).
- **A local's or a temporary's** keeps one address, whatever moves into or out of it. It is live from the declaration or the creation to the end of its scope or full statement ([02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#temporaries)).
- **A `Closure`'s inline captures and a task's locals**, which its state holds across an `await` ([07](../07-concurrency/tasks.md#semantics)), are the exception to keeping one address. They move with the value that holds them, so a pointer into them reaches what it pointed at only until that value next moves.

### Raw accesses

**An access through a raw pointer must satisfy each of these, and breaking any of them is undefined behavior.** Together they say where the access may land, what it must find there, how much it may write, and how it is ordered against other threads:

- **In bounds.** `p + n` stays inside the allocation `p` was derived from, or one past its end. An access lies wholly inside that allocation while it is live, so nothing it reads or writes has been freed or reused ([13](../13-soundness.md#the-invariants)).
- **Aligned.** The address is a multiple of `T`'s alignment, since a misaligned load or store faults on some targets ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)).
- **Valid.** A read as `T` finds a valid `T` there. What is valid depends on the type:
    - for a padding-free `Pod` type ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)), any initialized bytes;
    - for any other type, a bit pattern that is one of its values, such as a write of a `T` leaves;
    - for a type whose primary initializer or a field is `unsafe` or `private`, only the values its initializers could produce ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)). Such a type may guard an invariant, such as a `Handle`'s generation that is never 0, and bytes must not forge a value that breaks it ([03](../03-handles-and-objects.md#pools-and-handles)). So a `String`, `StringView` or `StaticString` holds whole UTF-8 sequences ([04](../04-types/collections.md#strings)).
- **Whole.** Storing a whole `T` may write every byte of it, padding included. So may any write to a `T` lent as a `mutable` argument, bound with `&` or reached through a `MutableSpan<T>`. A struct whose tail padding holds other data is never stored whole or lent in those ways, since such a write could overwrite the data in its padding. Its fields are written one by one, each through its own place, such as `p.pointee.len`. A `TrailingArray`'s header can be such a struct, and so can an imported struct whose flexible array member's elements share its tail padding ([04](../04-types/data-layout.md#variable-sized-structs-trailingarray)).
- **Race-free.** Two accesses to the same bytes on different threads, at least one of them a write, are ordered by synchronization ([07](../07-concurrency/synchronization.md#atomics-and-locks)). This doesn't apply when both are atomic accesses of the same size at the same address. Atomic accesses that overlap in any other way count as non-atomic here.
- **Exposed.** A pointer converted from an integer reaches only memory whose address was exposed:
    - an allocation whose address an earlier pointer-to-integer conversion exposed;
    - memory that Rayo didn't allocate, such as a device register at a fixed address, or a buffer whose address C passes as an integer.

**Raw accesses respect borrows and views.** `unsafe` code reads a place only where Rayo code could. It writes a place, moves its value out, as `p.move()` does, or destroys the value in it, only where Rayo code with exclusive access could. These rules apply the law of exclusivity ([01](../01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)) to raw accesses:

- **Under a mutable access.** While a `mutable` access, an `&` binding or a mutable view is live, nothing touches the places it reaches except through it. So two `MutableSpan`s made from one pointer never overlap while both are live, since one could write what the other still reads ([02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#mutable-views)).
- **Under a borrow.** While a borrow, a borrowing binding or a shared view is live, nothing writes, moves out of or destroys the places it reads. The exception is the places inside a `Synchronized` value, which its own operations may write, move out of or destroy. Any other write could free what the borrow still reads, as appending to a `String` may move its text and free the buffer a view of it reads ([13](../13-soundness.md)).
- **Under narrowing.** While a place is narrowed, nothing makes it `nil` except the code that narrowed it, through one of the events that end the narrowing ([04](../04-types/enums.md#narrowing)). That code uses the payload without checking again.
- **Immutable memory.** Nothing writes memory that Rayo treats as immutable: read-only data, which holds every `const`'s frozen data, and a `Frozen` value behind a `Shared` or a `LocalShared`. Rayo reads such memory without a mark ([08](../08-c-interop/c-contract-and-embedding.md#what-c-must-uphold)). Nothing writes memory that its provider made read-only either, such as a C object defined `const`, a string literal's bytes or a page mapped read-only.

**A live parameter counts as a borrow or `mutable` access of its argument's place.** The compiler may assume that neither kind is aliased. It may also pass a borrowed argument as a copy of its bits, so the callee may see a copy rather than the caller's place ([01](../01-values-and-ownership/parameters.md#borrowed-arguments)).

**The views `unsafe` code makes keep the promises that 02 states for dependencies** ([02](../02-views-and-dependencies/dependency-rules.md#dependencies)). The compiler sees names, not memory, so a view's dependency set is all it knows of which places the view reaches ([13](../13-soundness/dependencies.md#dependencies)).

### Values, views and threads

**These rules cover the values, views and threads that `unsafe` code hands on to other code:**

- **Places hold valid values.** Whenever Rayo code may next read, lend or destroy a place as `T`, it holds a valid `T`. So a write through a pointer of another type leaves one there. A place that `p.move()` or `p.deinitialize()` emptied is initialized again before its owner uses or destroys it. Otherwise the owner would use or destroy a value that has moved out or been destroyed already ([13](../13-soundness.md#the-invariants)).
- **Views reach live, aligned, valid places.** This holds for a span, `Borrow` or `MutableRef` that `unsafe` code makes from a raw pointer, and for a borrowed or `mutable` argument that it passes through one. For as long as such a view or argument lives, its places lie inside one live allocation, and each is aligned for its type and holds a valid value. Such a mutable view's places, and such a `mutable` argument's, are also writable. A span reaches its `count` consecutive places. Safe code reads and writes them with aligned accesses.
- **A move-only value has one owner.** Its bytes stand for one value. After they are copied to a second place, only one of the two is used or destroyed as that type again, as `p.move()` leaves only the destination. Two places standing for it would be two owners of what it holds, two mutable aliases, or a guard that unlocks twice ([13](../13-soundness/ownership-and-borrows.md#ownership)).
- **A panic leaves shared state valid.** Wherever `unsafe` code can panic, what other threads can reach through it is valid, as if the code had stopped there, since other threads may run briefly after a panic ([What a panic does](panics.md#what-a-panic-does)). A queue's links and a lock's word are such state.
- **Values that aren't `Sendable` stay on their thread.** Such a value is used, lent and destroyed only on the thread whose code made it, or, for a thread-bound object, on its home thread ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)). That holds whatever `unsafe` code or C passes it through, since only on that thread do exclusivity and the dynamic tier check all of its aliases ([07](../07-concurrency/race-freedom-and-sendable.md#why-safe-code-cant-race)). A value that only the raw pointers it holds keep from being `Sendable` may cross, and each access through those pointers follows the rules on raw accesses ([above](#raw-accesses)).

## Aliasing and skipped `deinit`s

Two more facts are part of the boundary between `unsafe` and safe code ([13](../13-soundness/types-and-boundaries.md#the-unsafe-boundary)):

**Memory has no declared type.** A raw pointer of any type may alias memory also reached as another type, and `unsafe` code may rely on that.

**A `deinit` may never run, and `unsafe` code allows for that.** Destroying a stale value skips its elements' `deinit`s ([06](../06-memory-and-allocators/arena-safety.md#stale-values-and-the-deinits-a-reset-runs)). So `unsafe` code stays sound when a value it hands out, a guard included, is never destroyed. A guard left in a stale container, for one, keeps its lock held, and moving or destroying that lock stays sound ([07](../07-concurrency/synchronization.md#the-synchronized-contract)).

## Taking an address

**`ptr(to:)` returns the address of a place**, in two forms: one for a place lent to it with `&`, and a shared form for a place it borrows.

```swift
unsafe func ptr<T>(to place: mutable T) -> *T     // the form for a place lent with '&'
let p = unsafe ptr(to: &particles[0])             // the address of particles[0], lent for change
let q = unsafe ptr(to: particles[0])              // the shared form: the address of a place it borrows
```

- **Builtin.** It is builtin, and the call's `&` chooses the form, as for a method's forms ([04](../04-types/collections.md#shared-mutable-and-consuming-forms-of-one-method)).
- **Never a function value.** It converts to no function type or `Closure` and binds no `some F`, so every call of it is direct.
- **The caller's place.** Its argument, borrowed or not, is always the caller's place, never a copy, since its result is that place's address ([01](../01-values-and-ownership/parameters.md#borrowed-arguments)).
- **A short access.** The access ends with the call, since a raw pointer is unscoped.

**The place must be storage that a view could outlive:** a variable, a stored field or element, or a storage projection ([02](../02-views-and-dependencies/projections-and-accessors.md#storage-projections)). Passing an access-bound projection or an under-aligned place ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)) is a compile error, since either reaches the call only as a temporary the call would outlive. An under-aligned field's address is its enclosing place's plus `field.offset` ([09](../09-compile-time/reflection.md#what-reflection-can-read)).

**An object's value or a thread-local qualifies, but no mark guards later uses of its address.** The dynamic access the call takes ends with the call. Later uses of the address keep the rules on raw accesses ([above](#raw-accesses)). They stay in bounds only while the object, or the thread's copy, lives.

## Raw memory

**The raw-memory operations put a value in, take it out, or destroy it in place:**

- `p.initialize(to: v)` moves `v` into uninitialized memory without running a `deinit` on what was there.
- `p.move()` moves the value out and leaves the memory uninitialized.
- `p.deinitialize()` destroys the value in place, running its `deinit` and its fields'. `p.deinitialize(count: n)` does so for `n` values.

Plain assignment through `p.pointee` assumes initialized memory and destroys the old value first, as for any place.

## Raw allocations

**`allocator.allocateRaw(bytes:align:)` returns a `RawAllocation`, or `nil` when the allocator can't make it.** A `RawAllocation` is a copyable record of these:

- the address, an `unsafe` field, so safe code never sees it;
- the size and the alignment;
- the allocator word ([06](../06-memory-and-allocators/allocator-implementations.md#how-values-record-their-allocator)).

**Resizing and freeing:**

- `reallocateRaw(_:bytes:)` resizes one, keeping its first bytes up to the smaller size, and returns the updated record. It returns `nil` when the allocator can't make the new size, which leaves the old allocation live and unchanged.
- `freeRaw(_:)` gives one back.

**`reallocateRaw` and `freeRaw` are `unsafe`, and reach the allocator through the record's word.** Their caller promises that the word names the allocator they are called on, and that the allocation is still live. After `freeRaw`, the caller uses nothing at the old address. After a `reallocateRaw` that succeeds, it uses the allocation only through the record that call returned.

**An `unsafe` core, an owning container that user `unsafe` code builds on raw allocations, checks the word before it touches the storage.** It stores the word next to its pointer. It checks the word at every open, each access that reaches the storage ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)), before it reads, writes or frees there. The check is made at the open, since a reset can't find the values it invalidates, which may be anywhere. `word.isLive` makes that check without panicking, so the core can refuse a stale buffer instead of reading reused memory.

## Hardware access

**These operations serve hardware access and code that interrupts a thread:**

- `volatileLoad(p)` and `volatileStore(p, v)`, for a `T` of 1, 2, 4 or 8 bytes, are each performed exactly once, at `T`'s width, and in program order with the thread's other volatile accesses. They are never merged, split or removed.
- `fence(_:)`, given `.acquire`, `.release`, `.acqRel` or `.seqCst`, is a memory fence of that ordering ([07](../07-concurrency/synchronization.md#atomics-and-locks)).
- `compilerFence(_:)` orders the thread's accesses only against code interrupting that same thread, such as a signal handler.

## `@safe` modules

**A module the build declares `@safe` ([09](../09-compile-time/attributes-and-runtime-data.md#what-a-build-declares)) is restricted to the safe subset.** Every construct whose correctness the compiler takes on trust is an error anywhere in it. It can still call safe wrappers that other modules built with `unsafe`. So it makes no promise of its own, and is sound given the modules it calls ([13](../13-soundness/types-and-boundaries.md#the-unsafe-boundary)).

**A `@safe` module rejects:**

- `unsafe` blocks, expressions and functions;
- the unverified promises ([below](#unverified-promises)): `unsafe` conformances, `@pod`, `@export` functions, `import c` config blocks and `extern c func` declarations;
- `unchecked` blocks ([`unchecked` blocks](checks-and-build-modes.md#unchecked-blocks));
- `extern c` blocks of C code ([08](../08-c-interop/imports-and-inline-c.md#inline-c)).

### Unverified promises

**The unverified promises are these, each taken on trust:**

- **`@pod`** states that every bit pattern of a struct or union is valid ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)). It waives the visibility and `unsafe` conditions, which keep bytes from forging a value whose invariant a type guards.
- **`@export` on a function** is a promise about its C name and callers ([08](../08-c-interop/calling-rayo-from-c.md#calling-rayo-from-c)).
- **A conformance to an `unsafe protocol`** is a contract the compiler can't check ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#conformances)). An **unsafe protocol** is one declared with `unsafe protocol`. A conformance the compiler derives itself, such as `Frozen` for a type with no interior mutability, or `Sendable` for a type whose fields are all `Sendable`, is no promise. The language's own unsafe protocols are these:
    - `Sendable` and `Synchronized` ([07](../07-concurrency.md));
    - `Frozen` and `AllocatorImpl` ([06](../06-memory-and-allocators.md));
    - `PlainDeinit` ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)).
- **A conformance written `: unsafe P` for one of these reasons** is a promise too, since generic code reaches a witness with no `unsafe` in sight ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#conformances)):
    - a witness is an `unsafe` field, or a union member that isn't safe to read;
    - a witness is a static stored `var` that isn't `@threadlocal`, which also promises that its accesses never race;
    - a witness is an `unsafe` declaration meeting a safe requirement;
    - its derived `==` or `hash(into:)` reads such a field or member ([05](../05-protocols-generics-and-closures/operators.md#equality-and-ordering)).
- **A rule in an `import c` config block** is an assertion about the header's C. The rules are `noalloc` ([08](../08-c-interop/imports-and-inline-c.md#c-calls-in-noalloc-code-noalloc)), `stack` ([08](../08-c-interop/imports-and-inline-c.md#the-stack-a-c-call-needs)), and `struct`, `union` or `enum S in "h"` ([08](../08-c-interop/imports-and-inline-c.md#the-identity-of-an-imported-type)). A `stack` in a `@c` function pointer type is no promise, since a function converts to the type only when the type declares at least the function's need.
- **An `extern c func` declaration** is an assertion about its module's `extern c` code or a linked library ([08](../08-c-interop/imports-and-inline-c.md#inline-c)).
