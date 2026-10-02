# 13 · Soundness

```swift
var lines = List<StringView>()
splitLines(source.view, into: &lines)   // rule 4: 'lines' takes on what source.view carries: 'source', shared
source.append("x")                      // error: changes 'source' while 'lines', used below, borrows it
print(lines[0])
```

`append` may move the text to a larger buffer and free the old one, which `lines` still views. The compiler finds the conflict because `lines`' dependency set names `source`, which is the property [Covered](#covered) below. **Safe code has no undefined behavior** ([01](01-values-and-ownership.md#tiers-of-checking)), and each rule of the spec keeps one or more of the five invariants below, which together make that so.

## The invariants

The undefined behavior of [10](10-errors-and-safety.md#unsafe-code) is an access outside a live allocation, a misaligned access, a read of an invalid value, a data race, a write to memory Rayo treats as immutable, and the failure of a check that `unchecked` removed. Safe code has no `unchecked` block, and its memory-safety checks are on in every build ([10](10-errors-and-safety.md#check-levels)), so the last never happens. These rule out the rest:

- **Live.** Safe code accesses memory only inside an allocation, while the allocation is live ([10](10-errors-and-safety.md#unsafe-code)), so nothing it reads or writes has been freed or reused.
- **Valid.** A place that safe code reads, lends or destroys holds a valid value of its type, at an address aligned for it.
- **Exclusive.** While a mutable access to a place is live, nothing reaches an overlapping place except through it. While a shared access is live, nothing writes the place, except a `Synchronized` value through its own synchronization. Static data, a frozen `const` and a `Frozen` value behind a `Shared` or a `LocalShared` are shared for good.
- **Owned.** A value has one owner, except a reference-counted value, which its owners share. It is destroyed at most once, and used neither after its destruction nor after it moves out.
- **Race-free.** Two accesses to the same bytes on different threads, at least one a write, are ordered by happens-before ([07](07-concurrency.md#atomics-and-locks)), unless both are atomic accesses of the same size at the same address.

These are what [10](10-errors-and-safety.md#unsafe-code) asks of `unsafe` code, stated for all code. The sections below show that safe code keeps them, given that `unsafe` code and C keep them too and keep the promises the spec lets them make ([The unsafe boundary](#the-unsafe-boundary)).

## Ownership

This section keeps **Owned** and **Valid**.

- **A move copies bytes and ends the source** ([01](01-values-and-ownership.md#moves)). Only a place the code owns can be moved from, and it can't be used again until it is given a new value, so the bytes stand for the value in one place only.
- **A copy duplicates nothing owned.** `copy`, a copyable `const`, and the operations [01](01-values-and-ownership.md) lists as copying apply only to copyable types, which have no `deinit` and own no heap memory, so a copy is never a second owner of anything. Everything that owns memory is move-only, and `clone()` allocates its own.
- **A type that its kind makes move-only would alias if copied.** Two copies of a mutable view, a `mutable any P` or an exclusive `SoA` row would be two mutable aliases; of a guard, two unlocks; of a `Synchronized` value, two places with one identity; of a `mutating` or `consuming` function value, a `Closure` or a task's state, two owners of the same captures or locals ([01](01-values-and-ownership.md#copies)).
- **A place the code doesn't own always holds a value.** Nothing is consumed from a global, a borrowed or `mutable` parameter, an element, or a place reached through a weak pointer or an accessor, and `replace`, `swap` and `take()` leave a value behind ([01](01-values-and-ownership.md#what-can-be-moved-from)). So a caller, an alias or a later `deinit` that reaches such a place finds a value there, across a `throw`, an early return and an `await` too.
- **Initialization is tracked per path and per field.** A place without a value, maybe without one or partly moved is used only where every path has given it one, and destroyed exactly when it holds one ([01](01-values-and-ownership.md#places-that-hold-no-value)). A closure that gives a captured place its value carries whether the place holds one, and leaves it maybe-initialized after its last use.
- **A field moves out only where no `deinit` needs it.** A `deinit` takes all of `self`, so a field moves out only when no type on the path declares one, or in that type's own code: its `deinit`, or a `consuming` method that ends `self` with `discard self`, which runs no `deinit` and destroys the fields left one by one ([01](01-values-and-ownership.md#what-can-be-moved-from)). `discard self` is allowed only in the type's own module, whose code the `deinit` protects. A `when` whose path has a `deinit` keeps its subject whole in a hidden local for the same reason ([01](01-values-and-ownership.md#conditions-and-patterns)).
- **A `deinit` is part of the type everywhere.** It is declared in the type's module, unconditionally ([04](04-types.md#initializers)), so code that checked a type as copyable, or its destruction as no use, never meets an instance that has one.
- **Destruction runs once, in one order** ([01](01-values-and-ownership.md#destruction)): reverse declaration order, hidden locals and temporaries included, so what a value's destruction uses is checked against what is still alive at that point.

## Borrows and exclusivity

This section keeps **Exclusive**, and, with [Covered](#covered), **Live** for memory an owner releases.

- **Moving, assigning and destroying are mutable accesses** ([01](01-values-and-ownership.md#the-law-of-exclusivity)). So an owner can't release or replace what a live borrow reaches.
- **Borrows never leave the function that makes them** except as the dependencies its signature states (rules 3 to 5). So one body holds every borrow the checker must see, and the checking is static.
- **Places overlap by path** ([01](01-values-and-ownership.md#which-places-overlap)). Distinct stored fields occupy distinct bytes, so they are disjoint. The places counted as one share bytes or are written together: a union's members, a `Simd` vector's lanes, whose store may rewrite the vector, an enum's payload, whose tag may be a niche inside it, and the bitfields of one C memory location. Inline array elements are disjoint only at indices known to differ where the borrows are checked, which a body checked once for every value parameter can't know. A user accessor is an access to all of `self`, since its body may reach any of it; a bitfield's generated accessors touch only their memory location, and an `SoA` column is a buffer of its own, disjoint from the others as a stored field is.
- **Two elements of one collection at once** come from an API that checks at run time that they differ ([01](01-values-and-ownership.md#two-elements-of-one-collection)).
- **A call's borrows begin together, after its places are worked out** ([01](01-values-and-ownership.md#evaluation-order-and-when-a-calls-borrows-begin)). So every borrow and take of one call is checked against the others, as `f(&x, x)` is, and a value read for an argument is done before the call lends or takes its place. An optional chain or `!` reads the optional, so its borrow begins there. An assignment through an optional chain works out the rest of its place after its right side, whose accesses have then ended.
- **A borrowed argument may be a copy of its bits** ([01](01-values-and-ownership.md#borrowed-arguments)), since nothing changes it during the call. The arguments that are always the caller's place are exactly those whose address matters: a `Synchronized` value, whose identity is its address and which changes through a shared borrow; `ptr(to:)`'s; and one that a result, an error, a yield or an absorbing argument may still view after the call, which would otherwise view the callee's copy. This follows from the signature alone, and conversions keep conventions, so a call through a function value passes its arguments as a direct call does.
- **A `mutable` argument's changes reach the caller's place**, through a written-back temporary too ([01](01-values-and-ownership.md#parameters)).
- **Only a changeable place is written** ([01](01-values-and-ownership.md#changeable-places)), so a shared borrow never becomes a write. Each exception brings its own exclusivity: the dynamic marks of a thread-local and an object's value, a `Synchronized` value's synchronization, and the promise of `unsafe` code.
- **A `when` holds its subject still while arms are tested** ([04](04-types.md#matching-with-when-and-choosing-with-if)), so a guard sees the value its arm then binds, and an `owned` part moves only once its arm is chosen.

## Dependencies

The checker sees names, not memory, so it knows which places a view reaches only through dependency sets ([02](02-views-and-dependencies.md#dependencies)).

### Covered

**Whatever memory a value can reach beyond its own storage and what it owns, along any path safe code can follow, its dependency set holds a place whose storage holds or owns that memory, exclusively when the value can write it, or a dynamic access that guards it; or the memory is static storage.**

Covered gives:

- **Live** for memory an owner releases: the release is a mutable access to a place in the set of every live value that reaches the memory, so it conflicts.
- **Exclusive** through views: two live values that reach one place both name it, so an exclusive one conflicts with any other use.
- **Live** for memory a reset or an unregistration releases: a value that reaches it without owning it depends on the open that lent it, which counts as a use of the allocator until that value's last use, so the reset or unregistration panics first, and one that owns it checks at each open ([below](#memory-and-allocators)).

The rules keep Covered for each value they make, given that the values they start from are covered.

### Rules 1 and 2

- **Projection.** A view taken from a place reaches only that place's storage and what it owns, so it depends on the place.
- **Sub-views of a shared view** (`where return outlives self`, `where yield outlives self`) depend only on what the view carries. Verification checks the two facts that make this safe: nothing the view carries can be changed through it, since its type holds no mutable view, or end with it, since destroying it is no use ([02](02-views-and-dependencies.md#staying-valid-after-a-parameter-moves-on-outlives)). A view of data the type holds inline still depends on `self`.
- **Access-bound projections** may yield a temporary in the accessor's frame. A view of one depends on the access, which keeps the accessor suspended, so its frame and the places it was lent stay as they were until the view's last use ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)). The access began in this function, so rule 5 keeps such a view inside it.
- **Transitivity.** A derived value reaches nothing its source can't. A struct's or tuple's per-field sets only split that reach by stored field ([02](02-views-and-dependencies.md#naming-a-field)).

### Rule 3

- **A callee returns or throws only what rule 5 lets it**: its borrowed and `mutable` parameters, what they carry, what its scoped `owned` parameters carried in, and static storage. Rule 3 gives the result all of that, so the result is covered.
- **A shallow argument gives a sealed result only what it carries.** A shallow value is copyable and holds no inline array, so it owns no memory, and the only safe ways to view its own bytes are an `any P` made from it, a closure capturing it by reference and an interpolated literal borrowing it. A sealed type can hold none of them, so a sealed result can't reach the argument's place ([02](02-views-and-dependencies.md#dependencies)). `unsafe` code that views those bytes with `ptr(to:)` promises not to put the view in a sealed type.
- **A closure's storage reaches a result only through the function value.** No call of a closure returns a view of its own storage (rule 5 for closure bodies), so only a value holding the function value can reach that storage, and a sealed type can't hold one.
- **A place a closure captures exclusively ties the result to the closure.** Besides the result, only the closure reaches that place, and its next call may change or free it, so the result depends on the closure exclusively and the next call conflicts while it lives. Where the caller can't see the body, any `mutating` function value may hold such a capture, so every call of one is tied ([02](02-views-and-dependencies.md#dependencies)).
- **A temporary lives to the end of its full statement**, and a value depending on its place can't be used past that. Where the dependency on its place drops, by the shallow rule or `outlives`, nothing reaches it; a `for` loop's sequence and a closure literal kept for a local live in hidden locals instead.

### Rule 4

- **A callee stores into a `mutable` parameter only what rule 5 lets it**, and absorption adds all of that to the argument's set. Another `mutable` argument contributes what it carries, not its place, since rule 5 rejects storing a view of another `mutable` parameter's place unless a `where` item names it, and then absorption adds it.
- **A store through an exclusive view lands in memory the view's exclusive dependencies own.** Those places can now reach what was stored, so it joins their sets, transitively ([02](02-views-and-dependencies.md#dependencies)). An `owned` mutable view, such as a `MutableSpan`, a `mutating` closure or a `mutable any P`, can be stored through too, so it absorbs as a `mutable` argument does, and so does a generic value that may be one, unless its constraints include `Copyable` or `~Scoped`.
- **A borrowed argument absorbs nothing**, because nothing is stored through a shared path into a place that can hold a view. What safe code can write through a shared path holds only unscoped values: an object's value, a thread-local and the contents of a `Synchronized` value are all `~Scoped` ([02](02-views-and-dependencies.md#generic-code-and-scoped)).
- **Creating a closure is a call with its captures as arguments**, so the closure absorbs what they carry; calling it lets its `mutable` arguments absorb its set; it absorbs only what its `keep` arguments carry ([05](05-protocols-generics-and-closures.md#what-a-closure-may-keep-keep)).
- **Assigning a whole value replaces a set only where the place is known.** The old value is destroyed, so nothing it reached is reachable through the place. Through a binding that may name either of several places, the assignment adds to each, since the others may still hold their old views; a write through an exclusive view adds, since the view may cover only part of what it depends on.
- **A `mutable` argument's fields may trade what they carry**, so after the call each field has the union of all of them, unless a `where` item proves otherwise ([02](02-views-and-dependencies.md#naming-a-field)).

### Rule 5

Rule 5 checks each body against what its signature tells callers, so a caller's sets are covered without seeing the body. What it rejects is what rules 3 and 4 couldn't report:

- **a view of what the function owns or began**: its locals, the storage its `owned` parameters own, a thread-local, and a dynamic or projection access begun inside it, each released or ended when the call returns. The non-`mutable` parameters of a C entry count as owned, since C passes them by value ([08](08-c-interop.md#calling-rayo-from-c));
- **a store into a `mutable` parameter `p` that depends on a place overlapping `p`**, since the caller's set for `p` would have to name `p` itself;
- **a store through a parameter's exclusive dependencies that depends on the parameter's own storage**, which absorption never reports.

**Static storage is always allowed**, since it is never moved or destroyed ([07](07-concurrency.md#shutdown)). The views a `Synchronized` global lends are kept by its contract: a guard by its lock, and `Once.get()` by data never written again, which the global never frees ([07](07-concurrency.md#the-synchronized-contract)). What a C entry hands back to C may depend only on its parameters, `const`s and places in a global `let`'s own storage, since nothing in Rayo holds what it borrowed once it returns ([08](08-c-interop.md#c-representations)).

**A scoped `mutable` parameter counts as used at every exit**, so no path out, an error's included, frees what the callee just stored a view of.

### Rule 6

**A dynamic access is a dependency, and its mark is held until the last use of every value that depends on it**, so the run-time check covers each view for its whole life ([02](02-views-and-dependencies.md#dependencies)). A set names an access by the site that began it, so a site in a loop holds one access at a time.

### Mutable views

**A value that can write what it views carries an exclusive dependency on it** ([02](02-views-and-dependencies.md#dependencies)). Otherwise a function could turn a shared borrow into a `MutableSpan`, which would write what another shared borrow still reads. The two exceptions are exclusive by other means: a dynamic exclusive access, checked at run time, and a guard, whose lock grants no conflicting view ([07](07-concurrency.md#the-synchronized-contract)). `unsafe` code that builds a mutable view promises the same of what it builds.

**An iterator that hands out mutable views lends them one at a time** ([04](04-types.md#iteration)): each depends on the iterator exclusively until the next `next()`, so two are never live at once, and a `zip` with an `&` argument iterates only by consuming, so no second iterator over it exists.

### Destruction as a use

- **A `deinit` may read and write what its value borrows**, so the borrows of a value with one last until its destruction ([02](02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it)). A generic value may have one, so it counts unless constrained `Copyable` or `TrivialFree`.
- **A destruction can't use a part of the value itself**, since the `deinit` holds all of `self` owned and may change one part before it reads another.
- **`PlainDeinit` uses only what its elements' destruction uses**, since its `deinit` only destroys what it owns alone and frees its buffers.
- **Nothing relies on a `deinit` running.** A stale value's elements' `deinit`s are skipped ([06](06-memory-and-allocators.md#stale-values-and-the-deinits-a-reset-runs)), so skipping one can only leak, and `unsafe` code allows for that ([10](10-errors-and-safety.md#unsafe-code)).

### Precise dependencies

- **A `where` clause narrows a set only where the callee proves it**: verification is rule 5 restricted to what the items name, and a witness must satisfy its requirement's clause, so generic code relying on a clause stays covered ([02](02-views-and-dependencies.md#precise-dependencies-opt-in)).
- **A value moved out of `p`'s own storage carries only what `p` carried.** A value `p` owns can view `p`'s own storage only through a dependency of `p` on a part of itself, and then `&p` conflicts, so the call that moves it out can't happen ([02](02-views-and-dependencies.md#staying-valid-after-a-parameter-moves-on-outlives)).

### `rebind`

- **`rebind` changes which place a name stands for**, and the name's set follows the place: one reached through the name keeps the name's set, and any other starts a new borrow ([02](02-views-and-dependencies.md#pointing-a-name-at-another-place-rebind)). A binding that owns its value first hands it to a hidden local, so views already taken still reach a live value.
- **Through objects, the cursor holds only the new object's mark.** The new place lies in that object's value, which the mark guards. An alias that destroys the object panics, since the mark is live ([03](03-handles-and-objects.md#destroying-an-object)), and an alias that reaches it conflicts.
- **No step targets an access-bound projection**, since each step would nest another suspended accessor.

### Projections and accessors

- **A storage projection's yield is verified to be storage of what its `where` item names** ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)), so a view of it depends on that, as a view of a stored field does. `unsafe` code that yields through a raw pointer promises the same.
- **After a `yield`, the accessor treats the yielded place as borrowed**, since a view of it may outlive the access: it never changes it, and after a `modify` never reads it.
- **An accessor yields exactly once on every normal path**, so the caller always gets one place.
- **An optional projection or a tuple of places exists only in its parts.** No `T?` or tuple of them lies in memory, so nothing writes, lends or views one whole.
- **A change through `get` and `set`** lends the `get`'s result and passes it to `set`, which changes `self`, so it is rejected when that result may depend on `self` or on a `mutable` argument of the access ([02](02-views-and-dependencies.md#get-and-set-accessors)). A move-only `owned` argument can't move into both calls.

## Closures and function values

This section keeps **Covered**, **Exclusive** and **Race-free**.

- **A function value is a view of its closure's storage** ([05](05-protocols-generics-and-closures.md#function-typed-values)), so it is scoped and depends on that storage, which lives in a hidden local of the scope or as a temporary of the statement.
- **A closure body is checked as a method whose `self` is the closure** ([02](02-views-and-dependencies.md#dependencies)). Owned captures are an owned parameter's storage, since a call through a `consuming` type destroys them, so nothing it returns views them. A store into a capture can't depend on a place captured exclusively, since the next call may change or free it, unless the closure is `consuming` and runs once.
- **Parameters are call-scoped unless `keep`** ([05](05-protocols-generics-and-closures.md#what-a-closure-may-keep-keep)), so a closure lent data for one call, such as a lock's, can't keep a view of it. A `keep` argument's set joins everything the closure depends on exclusively, and the calling function's rule 5 must allow that store. A borrowed `keep` parameter's own storage belongs to the call, so only what it carries flows.
- **The kind says how a closure may be called** ([05](05-protocols-generics-and-closures.md#closure-kinds)). A non-`mutating` closure only reads its captures, so any number of threads may call it at once and a comparator can't write what it reads. A `mutating` one is move-only and lent exclusively. A `consuming` one is called at most once, which is what lets it move out of its captures. A conversion only strengthens the kind and never adds ownership.
- **No conversion applies through `mutable`** ([05](05-protocols-generics-and-closures.md#implicit-conversions)), since the callee could store a value of the wider type into a variable the caller still sees as the narrower one, such as a `mutating` closure into one a job system calls on many threads. The exceptions make new views, each lending its place until the view's last use.
- **A closure captures places as precisely as overlap keeps them apart** ([05](05-protocols-generics-and-closures.md#functions-and-closures)), stopping before accessors, optional chains, payloads and object accesses, which the body evaluates on each call. A captured binding of a place brings its set and its dynamic accesses, held while the closure lives.
- **`Closure<F>` owns and lists its captures**, so it borrows nothing ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref)). Its out-of-line context is checked at each call as any open is. It counts as holding a `Synchronized` value, since its captures may, so it is always the caller's place and never packed.
- **Calls of `unsafe` and C functions stay visible.** No function value hides an `unsafe` call, and C converts only to `@c` types, which carry the stack need its calls check ([05](05-protocols-generics-and-closures.md#c-function-pointers)).

## Generic code and existentials

- **Generic code is checked once, at the safe bound** ([05](05-protocols-generics-and-closures.md#protocols-and-generics)). An unconstrained type parameter may be move-only, scoped, a mutable view, not `Sendable`, and have a `deinit` whose destruction is a use, so a body that checks under those assumptions is sound for every instantiation. Each constraint, such as `Copyable`, `~Scoped`, `TrivialFree` or `Sendable`, relaxes one assumption, and every instantiation meets it. Members a `static if` or `static for` generates are taken at the same bound ([09](09-compile-time.md#generated-members-are-checked-per-instantiation)).
- **A witness keeps its requirement's promises**: conventions, `where` clauses, storage or access-bound projections, and `@noalloc`. So generic code relies only on the requirement.
- **Markers are unconditional** ([05](05-protocols-generics-and-closures.md#conformances)). Generic code derives copyability, sendability and scope from fields, type arguments and these declarations for every type argument at once, so no instantiation can differ from what it checked.
- **`any P` is a view** ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)): made from a shared borrow, or from `&x` as a `mutable any P`, so the rules above apply to it. An unscoped existential, such as `Box<any P>`, forgets its value's type and what that type carries, so the type must be `~Scoped`. An existential is `Sendable`, `Frozen` or `TrivialFree` only when its protocols say so, since it hides a type that may not be.

## The dynamic tier

Each mechanism checks at each use what the static tier can't see, and a failure panics or reads `nil` before it touches memory.

- **Handles** ([03](03-handles-and-objects.md#pools-and-handles)). A pool's subscript checks the slot's generation, and a slot whose generation would wrap is abandoned, so a stale handle reads `nil` for good. A forged one reaches `nil` or some live element of that pool: **Live** and **Valid**, if not the element meant. The subscript is a storage projection of the pool, so removing an element conflicts statically with every live view of one.
- **Object liveness** ([03](03-handles-and-objects.md#destroying-an-object)). A weak pointer names its object by a generation that no other object of the run gets, so it never reaches a later object. An owner whose object a reset or an unregistration destroyed is stale, and an access through it panics.
- **Object marks** ([03](03-handles-and-objects.md#dynamic-exclusivity)). Weak pointers are aliases the checker can't see, so each access takes a mark, held as rule 6 says, and a conflicting one panics before it touches the value: **Exclusive**. The counts can't wrap.
- **Destruction never frees under an access.** Destroying an object while an access to it is live panics, and a pin leaves the `deinit` and the release to the last pin's drop, so the `deinit` runs once, when no access is live and no pin holds the value, and the memory is freed after it ([03](03-handles-and-objects.md#destroying-an-object)).
- **Thread-bound objects stay home.** Their marks aren't atomic, so owners, weak pointers and `LocalPin`s aren't `Sendable`, `WeakPointer(bits:)` and `adopt` check the home thread, a home thread's identity is never reused, the `deinit` runs on that thread, since a reset or an unregistration on another panics instead, and a thread's objects end in its teardown, on it ([03](03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)): **Race-free**.
- **Reference counting** ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners)). A `Shared`'s count is atomic, and a `LocalShared`'s never leaves its thread, so the value is destroyed once, by the drop that takes the count to zero, after every other owner's drop in happens-before order: **Owned** and **Live**. A weak link names its value by a generation that no other `Shared` value of the run gets, and `upgrade()` adds an owner only while the count is above zero, in one atomic step, so it never reaches a destroyed or a later value. A `Waker` reaches its target through such an upgrade.
- **Pins** ([03](03-handles-and-objects.md#pinning-for-c)). A pin keeps its memory from being freed or reused: a destruction leaves the `deinit` and the release to the last pin's drop, which happens on a thread the value may be destroyed on, and a reset or an unregistration panics while a pin into its memory lives. Each drop happens before the release that waited for it. A pin doesn't make the value immutable: Rayo code still writes it through its owner, under the rules above.
- **`Slice`** ([06](06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers)). It reaches its buffer only through a scoped span per use, so it may be stored anywhere. Each `read()` or `lock()` upgrades its weak link and checks the storage's word, and for a locked buffer takes the lock and checks the current length, alignment or count under it. The span then holds the owner and the lock. `T` is `Pod` over initialized bytes, so every element read is **Valid**, and a `MutableSpan` also needs `T` padding-free, so a store leaves no uninitialized byte another slice reads.
- **Thread-locals** ([07](07-concurrency.md#global-state)). Each access to a thread's copy takes a mark, as an object's does. The copy is initialized before any other code of its thread runs and marked dead before it is destroyed, so a later `deinit` that reaches it panics.
- **Locks** ([07](07-concurrency.md#locks-mutex-and-rwlock)). Taking a lock that the thread holds in a conflicting way panics, lent work the lending thread runs included, so no thread gets a second exclusive view.

## Memory and allocators

This section keeps **Live** for memory released out of band, by a reset or an unregistration.

- **Every release happens at a point the code shows** ([06](06-memory-and-allocators.md)): an owner's release, the last of a reference-counted value's owners included, is a mutable access, checked statically, and a reset or an unregistration first checks that nothing uses the memory (below).
- **An open checks the storage's word, and counts as a use while what it lends lives** ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)). A reset can't find the values it invalidates, so every access that reaches their storage checks first, and it can't find their views, so each open counts itself until the last use of what depends on it, as rule 6 holds a dynamic access. A reset or an unregistration makes the storage stale before it reads the counts, so an open racing it either fails or is counted. A container's words cover all of its storage.
- **Uses are counted on every thread.** Lent work's views depend on the lender's opens, which count until the lending call returns, and its own opens count on the thread that makes them ([07](07-concurrency.md#the-librarys-promise)). A parked thread keeps its counts.
- **A word is never issued twice** ([06](06-memory-and-allocators.md#how-values-record-their-allocator)): the limits on registrations and resets panic, so a stale word never passes again, outside the `deinit`s that may open what they own.
- **A reset frees its blocks only once nothing uses them** ([06](06-memory-and-allocators.md#what-a-reset-does)). The runtime, not the arena, decides what is stale, by stamps it issues in order and never twice. It panics while a counted open, a pin, an accessed object or another thread's object still uses the memory, or while another reset or unregistration that reaches it runs, and frees the blocks only after the `deinit`s it runs have returned. Unregistering checks, and waits for its `deinit`s, the same way ([06](06-memory-and-allocators.md#unregistering-an-allocator)).
- **Destroying a stale value never touches its memory** ([06](06-memory-and-allocators.md#stale-values-and-the-deinits-a-reset-runs)), so its elements' `deinit`s are skipped and what they owned leaks.
- **An object's `deinit` that a reset or an unregistration runs may open what that reset or unregistration made stale.** The memory is freed only after the `deinit` returns, and a value an earlier reset made stale still fails, since its memory may already be reused.
- **Backing chains are fixed and acyclic** ([06](06-memory-and-allocators.md#allocators-over-other-allocators)), so a reset or an unregistration reaches everything built on it, and no arena or heap draws from an arena, whose reset would reuse memory under it.
- **`AllocatorImpl` is a promise** ([06](06-memory-and-allocators.md#what-conforming-promises)): disjoint allocations, no reuse after handing a block over, and truthful reports. It is `Synchronized`, since any thread allocates ([06](06-memory-and-allocators.md#allocators-and-threads)).
- **A `Shared<T>` holds a `Frozen` or `Synchronized` value, and a `LocalShared<T>` a `Frozen` one** ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners)), so what many owners reach is never written, or written only through its own synchronization, apart from the count, which no reader observes. `Frozen` is derived only for types with no interior mutability, and nothing holding a `Synchronized` value is `Frozen` ([06](06-memory-and-allocators.md#frozen-types-with-no-interior-mutability)).
- **`release` forgets only a `TrivialFree` value** ([06](06-memory-and-allocators.md#releasing-a-value-without-destroying-it-trivialfree)), whose destruction would only free memory, which the reset then frees.
- **A failed allocation panics or throws** ([06](06-memory-and-allocators.md#allocation-failure)), so no operation goes on with memory it didn't get.

## Threads

This section keeps **Race-free**. Only `Sendable` values reach another thread, and safe code on two threads reaches the same memory only through four routes, each of which orders its writes ([07](07-concurrency.md#why-safe-code-cant-race)).

- **`Sendable` is derived from what a type holds** ([07](07-concurrency.md#what-may-cross-threads-sendable)), so a value's type says whether it reaches anything bound to a thread. Object pointers, `LocalPin`s and guards never are, since their marks and locks belong to one thread, and raw pointers are only by promise.
- **Borrows lent for a call.** The library promises to move only `Sendable` values, to call each closure as its kind allows, to hand values over in happens-before order, and to have every thread done with a value before the borrows it carries end ([07](07-concurrency.md#the-librarys-promise)). The closures it is lent are borrows of the call's arguments, so exclusivity holds across them statically, and a value it keeps past the call is kept in a scoped, unsealed type, which absorbs what the value borrows.
- **`Shared` values**, which don't change except through their own synchronization ([above](#memory-and-allocators)).
- **`Synchronized` values and channel ends.** The contract ([07](07-concurrency.md#the-synchronized-contract)) is a list of what Race-free and Exclusive need of shared mutable state:
    - move-only, so every thread synchronizes on the same memory;
    - no niche, since reading a tag is a plain load of bytes other threads write;
    - unscoped, `Sendable` contents, since they reach other threads and absorption can't follow them through a shared `self`;
    - every field its synchronization writes is `unsafe` or `Synchronized`, so safe code never reads one with a plain load, and the type is never `Frozen` or `Pod`;
    - values taken in and handed out owned, in happens-before order;
    - no view granted while a conflicting one is live, on any thread, which a re-entrant lock can't meet;
    - guards declared `@guard`, so each is released on the thread that took it, pointing only into the lock, which keeps what they view allocated;
    - views of its interior only under a lock, or of data never written again except through its own synchronization and never freed before the value is destroyed;
    - bitwise-movable whenever unborrowed, since the language moves only unborrowed values.
- **A channel's ends** are `mutating` on each side, so exclusivity makes one consumer and one producer at a time, statically ([07](07-concurrency.md#queues-and-channels)).
- **`Shared<T>`**, which is never written ([above](#memory-and-allocators)).
- **`const`s, global `let`s and immortal data**, read through shared borrows and changed only through their own synchronization ([07](07-concurrency.md#global-state)).
- **No other global is reachable from safe code.** A bare global `var` needs `unsafe`, and a `@threadlocal var` gives each thread its own copy. A static stored member is never declared where one declaration stands for many instances.
- **Startup is single-threaded** ([07](07-concurrency.md#initialization-at-startup)), its end happens before every later entry into Rayo code on another thread, and a global read before its initializer has run is caught, statically where the calls are visible and at run time otherwise.
- **Atomics follow the C++20 memory model** ([07](07-concurrency.md#atomics-and-locks)), and the creation of a `Shared` value, an allocator or a `Name` happens before every use of it, however the value naming it arrived.
- **A task holds no borrow across an `await`** ([07](07-concurrency.md#semantics)). Its owner may move or destroy its state between steps. Its own locals are worked out again on resuming, since only its body reaches them, and its resume parameter is lent anew at each step. Its parameters are owned and unscoped, a `defer` live across an `await` uses only its state, and a finished task panics when polled.

## Types and layout

This section keeps **Valid**.

- **`Pod` means every bit pattern is valid and nothing is owned** ([04](04-types.md#plain-data-pod-and-bit-casts)). Its fields are visible and not `unsafe`, so bytes can't forge a value whose invariant a `private init` or an `unsafe` field guards, and `@pod` is a promise.
- **Padding is uninitialized.** A bit cast needs a padding-free source, a shared span cast a padding-free source type, and a mutable one both types padding-free, so no uninitialized byte is read as data.
- **Union reads** ([04](04-types.md#untagged-unions)). Writing a whole member is safe. Reading needs every member `Pod`, none `unsafe`, and the union padding-free, so whatever a write left is a valid value of the member read. Members are copyable, so nothing needs to know which one to destroy.
- **Niches** ([04](04-types.md#optionals)) are bit patterns a type never uses. None lies in a `Synchronized` value, whose bytes other threads write while a tag is read with a plain load, or in a bitfield, whose width may leave no room.
- **Under-aligned places are used only by value** ([04](04-types.md#packed-structs-and-under-aligned-places)), through aligned temporaries, so no view of one exists. Generic code takes the safe bound, and a packed struct holds no `Synchronized` value, which needs its alignment.
- **A whole store may write padding**, so a `TrailingArray`'s header, whose tail padding may hold elements, is written field by field, and a `Synchronized` value never shares bytes with either side ([04](04-types.md#variable-sized-structs-trailingarray)).
- **Text is UTF-8.** String ranges are checked on scalar boundaries ([04](04-types.md#strings)).
- **Arithmetic** ([04](04-types.md#integer-overflow-division-and-shifts)). An overflow that wraps gives a wrong value, never an invalid one, and the next bounds check still catches a wrong index. Division by zero and converting NaN or an out-of-range float are memory-safety checks.
- **Imports keep C's meaning** ([08](08-c-interop.md#structs-unions-and-enums)). A struct Rayo can't lay out exactly imports as `@opaque`, a zeroing `init()` exists only where all-zero bytes are valid, and an enum is closed only where its header says so, holding any value of its underlying type otherwise.

## Compile time and reflection

- **Evaluation checks what run time trusts** ([09](09-compile-time.md#running-code-at-compile-time-const)): every raw access and every memory-safety check an `unchecked` block removes, on one thread.
- **A frozen value is never written or destroyed** ([09](09-compile-time.md#consts-that-reach-run-time)), since it lies in read-only data. So it is `Frozen` with no bookkeeping, `TrivialFree`, holds nothing that exists only at run time, such as a weak pointer or an allocator id, holds no stale owning value, points only at memory freezing copies or at immortal data, and views only static data. It is `Sendable`, since every thread may read it.
- **Reflection grants nothing a name doesn't** ([09](09-compile-time.md#reflection-and-access-control)): the same visibility, `unsafe` fields, union reads and moves out, and `T.construct` calls the primary initializer. A reflective projection is a storage or access-bound projection exactly as the field is ([09](09-compile-time.md#what-reflection-can-read)).
- **Generated declarations are checked as written ones** ([09](09-compile-time.md#generated-members-are-checked-per-instantiation)), and generic code takes them at the safe bound ([above](#generic-code-and-existentials)).

## Checks and panics

- **Memory-safety checks are on in every build** ([10](10-errors-and-safety.md#check-levels)), and only `unchecked` code, which isn't safe code, removes them. Each fails before the access it guards.
- **A diagnostic check guards nothing memory depends on**: with it off, a wrong value still meets every memory-safety check.
- **A panic never returns and never unwinds** ([10](10-errors-and-safety.md#what-a-panic-does)), so no frame's borrows end early, no `deinit` runs on a half-changed value, and work lent from the panicking thread still finds its memory. Other threads may run briefly, which `unsafe` code allows for by leaving shared state valid wherever it can panic.
- **No frame is written past its stack's end** ([10](10-errors-and-safety.md#what-panics)): every function checks its stack on entry, and every call into C checks the need its target declares.

## The unsafe boundary

The argument above assumes that `unsafe` code and C keep the invariants for their own accesses ([10](10-errors-and-safety.md#unsafe-code), [08](08-c-interop.md#what-c-must-uphold)). It also rests on these promises, each of which some step relies on:

| Promise | What relies on it |
| --- | --- |
| A view made from a raw pointer reaches live, aligned, valid places, with the dependencies its signature states ([02](02-views-and-dependencies.md#precise-dependencies-opt-in), [10](10-errors-and-safety.md#unsafe-code)) | [Covered](#covered) |
| A mutable view built from a raw pointer changes only what its exclusive inputs own or carry ([02](02-views-and-dependencies.md#dependencies)) | [Mutable views](#mutable-views) |
| A value kept through a raw pointer is held in a type that says what it holds, and what is handed out of that storage borrows only what the call gives ([02](02-views-and-dependencies.md#dependencies)) | [Rules 3 and 4](#rule-3) |
| A shallow value's bytes viewed with `ptr(to:)` never reach a sealed type ([02](02-views-and-dependencies.md#dependencies)) | The shallow rule ([Rule 3](#rule-3)) |
| A storage projection's yield through a raw pointer lies in storage the named parameter owns or views ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)) | [Projections](#projections-and-accessors) |
| `unsafe Sendable` ([07](07-concurrency.md#what-may-cross-threads-sendable)) | [Threads](#threads) |
| `unsafe Synchronized` ([07](07-concurrency.md#the-synchronized-contract)) | [Threads](#threads), Exclusive |
| `unsafe Frozen` ([06](06-memory-and-allocators.md#frozen-types-with-no-interior-mutability)) | `Shared`, `LocalShared`, freezing |
| `PlainDeinit` ([02](02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it)) | [Destruction as a use](#destruction-as-a-use) |
| `AllocatorImpl` ([06](06-memory-and-allocators.md#what-conforming-promises)) | [Memory and allocators](#memory-and-allocators) |
| `@pod` ([04](04-types.md#plain-data-pod-and-bit-casts)) | `Pod` |
| The library's lending promise ([07](07-concurrency.md#the-librarys-promise)) | Borrows lent for a call ([Threads](#threads)) |
| `Box.adopt` takes back a leaked `Box<T>` once ([06](06-memory-and-allocators.md#owning-boxes)) | Owned |
| `@export`, `extern c func` and the rules of an `import c` config block, each an assertion about C ([10](10-errors-and-safety.md#safe-modules)) | Valid, the stack check |

**What `unsafe` code allows for** is part of the same boundary ([10](10-errors-and-safety.md#unsafe-code)): memory has no declared type, and a `deinit` may never run. **No `unsafe` call is hidden**, so every promise is made at a visible `unsafe` site, and a `@safe` module, which makes none ([10](10-errors-and-safety.md#safe-modules)), is sound given the modules it calls.
