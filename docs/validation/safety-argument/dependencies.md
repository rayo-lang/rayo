# Dependencies

[Safety argument](../safety-argument.md)

**The checker sees names, not memory, so it knows which places a view reaches only through dependency sets** ([02](../../spec/02-views-and-dependencies.md#dependencies)). A view reads memory that something else owns. The ownership and borrow checks protect that memory only if the view's set names a place that holds or owns it ([Ownership, borrows and exclusivity](ownership-and-borrows.md)). Covered states that, and each dependency rule keeps it.

## Covered

**A value is covered when its dependency set accounts for all the memory it can reach, along a path safe code can follow, beyond its own storage and what it owns.** For all such memory, one of these holds:

- its dependency set holds a place whose storage holds or owns that memory, and the dependency is exclusive when the value can write it;
- its dependency set holds a dynamic access that guards that memory;
- the memory is static storage.

**Covered is what lets the checks keep Live and Exclusive for memory a value views:**

- **Live for memory an owner releases.** The release is a mutable access to a place in the set of every live value that reaches the memory ([Borrows and exclusivity](ownership-and-borrows.md#borrows-and-exclusivity)), so it conflicts.
- **Exclusive through views.** Two live values that reach one place both name it, so an exclusive one conflicts with any other use.
- **Live for memory a reset or an unregistration releases.** A value that reaches it without owning it depends on the open that lent it. That open counts as a use of the allocator until that value's last use, so the reset or unregistration panics first. A value that owns the memory is checked at each open ([Memory and allocators](runtime-and-concurrency.md#memory-and-allocators)).

**The rules keep Covered for each value they make, given that the values they start from are covered.** So the argument goes rule by rule: each section below shows that a rule's results are covered when its inputs are.

## Rules 1 and 2

**Rules 1 and 2 cover a view taken from a place, and a value derived from another** ([02](../../spec/02-views-and-dependencies/dependency-projection-and-results.md#rule-1-projection)):

- **Projection.** A view taken from a place reaches only that place's storage and what it owns, so it depends on the place.
- **Sub-views of a shared view**, declared `where return outlives self` or `where yield outlives self`, depend only on what the view carries. Verification checks the two facts that make this safe ([02](../../spec/02-views-and-dependencies/dependency-lifetimes.md#staying-valid-after-a-parameter-moves-on-outlives)):
    - nothing the view carries can be changed through it, since its type holds no mutable view;
    - nothing it carries ends with it, since destroying it is no use.

  Without the first, an iterator over a `MutableSpan` could hand out a view and then replace the data under it. Without the second, dropping a read guard would release the lock under what it lent. A view of data the type holds inline still depends on `self`.
- **Access-bound projections** may yield a temporary in the accessor's frame. A view of one depends on the access, which keeps the accessor suspended, so its frame and the places it was lent stay as they were until the view's last use ([02](../../spec/02-views-and-dependencies/projections-and-accessors.md#access-bound-projections)). The access began in this function, so rule 5 keeps such a view inside it.
- **Transitivity.** A derived value reaches nothing its source can't. A struct's or tuple's per-field sets only split that reach by stored field ([02](../../spec/02-views-and-dependencies/dependency-lifetimes.md#naming-a-field)).

## Rule 3

**Rule 3 gives a scoped result everything the call was given** ([02](../../spec/02-views-and-dependencies/dependency-projection-and-results.md#rule-3-call-results)), and drops a place only where the result can't reach it.

**A callee returns or throws only what rule 5 lets it, and rule 3 gives the result all of that**, so the result is covered. Rule 5 lets a callee return these:

- its borrowed and `mutable` parameters;
- what they carry;
- what its scoped `owned` parameters carried in;
- static storage.

**A shallow argument gives a sealed result only what it carries.** A shallow value is copyable and holds no inline array, so it owns no memory. The only safe ways to view its own bytes are these:

- an `any P` made from it;
- a closure capturing it by reference;
- an interpolated literal borrowing it.

**A sealed type can hold none of them, so a sealed result can't reach the argument's place** ([02](../../spec/02-views-and-dependencies/dependency-projection-and-results.md#shallow-values)). `unsafe` code that views those bytes with `ptr(to:)` promises not to put the view in a sealed type.

**A closure's storage reaches a result only through the function value.** No call of a closure returns a view of its own storage (rule 5 for closure bodies), so only a value holding the function value can reach that storage, and a sealed type can't hold one.

**A place a closure captures exclusively ties the result to the closure.** Besides the result, only the closure reaches that place, and its next call may change or free it. So the result depends on the closure exclusively, and the next call conflicts while it lives ([02](../../spec/02-views-and-dependencies/dependency-projection-and-results.md#closure-calls)):

```swift
var grow = { () -> Span<Int> in buf.append(0); return buf.span }   // captures 'buf' exclusively
let a = grow()                   // 'a' views buf's elements, and depends on 'grow' exclusively
grow()                           // error: 'grow' is borrowed by 'a' (used below); this call may move buf's elements
use(a)                           // 'a' is still live here
```

**Where the caller can't see the body, any `mutating` function value may hold such a capture**, so every call of one is tied.

**A temporary lives to the end of its full statement**, and a value depending on its place can't be used past that. Where the dependency on its place drops, by the shallow rule or an `outlives` clause, nothing reaches it. A `for` loop's sequence and a closure literal kept for a local live in hidden locals instead.

## Rule 4

**Rule 4, absorption, covers what a call stores.** After a call, a scoped `mutable` argument takes on what the call's other arguments borrow ([02](../../spec/02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)), since the callee may have stored views of them in it:

- **A callee stores into a `mutable` parameter only what rule 5 lets it**, and absorption adds all of that to the argument's set. Another `mutable` argument contributes what it carries, not its place, since rule 5 rejects storing a view of another `mutable` parameter's place unless a `where` item names it, and then absorption adds it.
- **A store through an exclusive view lands in memory the view's exclusive dependencies own.** Those places can now reach what was stored, so it joins their sets, transitively ([02](../../spec/02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)). An `owned` mutable view, such as a `MutableSpan`, a `mutating` closure or a `mutable any P`, can be stored through too, so it absorbs as a `mutable` argument does. A generic value whose type may be an owned mutable view absorbs the same way, unless its constraints include `Copyable` or `~Scoped`.
- **A borrowed argument absorbs nothing**, because nothing is stored through a shared path into a place that can hold a view. What safe code can write through a shared path holds only unscoped values: an object's value, a thread-local and the contents of a `Synchronized` value must all be unscoped, `~Scoped` ([02](../../spec/02-views-and-dependencies/scoped-values.md#generic-code-and-scoped)).
- **Creating a closure is a call with its captures as arguments**, so the closure absorbs what they carry. Calling it lets its `mutable` arguments absorb its set, and the closure itself absorbs only what its `keep` arguments carry ([05](../../spec/05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-keep)).
- **Assigning a whole value replaces a set only where the place is known.** The old value is destroyed, so nothing it reached is reachable through the place. Through a binding that may name either of several places, the assignment adds to each, since the others may still hold their old views. A write through an exclusive view adds too, since the view may cover only part of what it depends on.
- **A `mutable` argument's fields may trade what they carry**, so after the call each field has the union of all of them, unless a `where` item proves otherwise ([02](../../spec/02-views-and-dependencies/dependency-lifetimes.md#naming-a-field)).

## Rule 5

**Rule 5 checks each body against what its signature tells callers, so a caller's sets are covered without seeing the body** ([02](../../spec/02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)). What it rejects is what rules 3 and 4 couldn't report:

- a view of what the function owns or began, each released or ended when the call returns: its locals, the storage its `owned` parameters own, a thread-local, and a dynamic or projection access begun inside it. The non-`mutable` parameters of a C entry count as owned, since C passes them by value ([08](../../spec/08-c-interop/calling-rayo-from-c.md#calling-rayo-from-c));
- a store into a `mutable` parameter `p` that depends on a place overlapping `p`, since the caller's set for `p` would have to name `p` itself;
- a store through a parameter's exclusive dependencies that depends on the parameter's own storage, which absorption never reports.

**Static storage is always allowed**, since it is never moved or destroyed ([07](../../spec/07-concurrency/global-state.md#shutdown)). The views a `Synchronized` global lends stay valid by its contract: a guard by its lock, and `Once.get()` by data never written again, which the global never frees ([07](../../spec/07-concurrency/synchronization.md#the-synchronized-contract)).

**What a C entry hands back to C may depend only on its parameters, `const`s and places in a global `let`'s own storage** ([08](../../spec/08-c-interop/calling-rayo-from-c.md#what-a-c-entry-hands-back-to-c)). Once it returns, nothing in Rayo holds what it borrowed: a lock guard is released, and an open no longer counts as a use of its allocator. So a reset or an unregistration could free an owning value's storage while C still holds a view of it.

**A scoped `mutable` parameter counts as used at every exit**, so no path out, an error's included, frees what the callee just stored a view of.

## Rule 6

**A dynamic access is a dependency, and its mark is held until the last use of every value that depends on it**, so the run-time check covers each view for its whole life ([02](../../spec/02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). A mark released earlier would let a conflicting access, or the object's destruction, through while a view still reads the value.

**A set names an access by the site that began it, so a site in a loop holds one access at a time.** Each time the site begins an access, no value that depends on the access it began the last time may be used from then on:

```swift
for w in nodes { names.append(w.value!.name.view) }   // error: the second pass's append uses 'names', which depends on the first pass's access
```

## Mutable views

**A value that can write what it views carries an exclusive dependency on it** ([02](../../spec/02-views-and-dependencies/dependency-projection-and-results.md#mutable-views)). Otherwise a function could turn a shared borrow into a `MutableSpan`, which would write what another shared borrow still reads, against Exclusive. The two exceptions are exclusive by other means: a dynamic exclusive access, checked at run time, and a guard, whose lock grants no conflicting view ([07](../../spec/07-concurrency/synchronization.md#the-synchronized-contract)). `unsafe` code that builds a mutable view promises the same of what it builds.

**An iterator that hands out mutable views lends them one at a time** ([04](../../spec/04-types/collections.md#iteration)). Each depends on the iterator exclusively until the next `next()`, so two are never live at once. A `zip` with an `&` argument iterates only by consuming, so no second iterator over it exists to hand out its views again.

## Destruction as a use

**Destroying some values runs code that may use what they borrow, as a lock guard unlocks its mutex** ([02](../../spec/02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)):

- **A `deinit` may read and write what its value borrows**, so the borrows of a value with one last until its destruction. A generic value may have one, so it counts unless constrained `Copyable` or `TrivialFree`: a copyable type has no `deinit`, and a `TrivialFree` type's destruction only frees memory.
- **A destruction can't use a part of the value itself**, since the `deinit` holds all of `self` owned and may change one part before it reads another.
- **`PlainDeinit` uses only what its elements' destruction uses**, since its `deinit` only destroys what it owns alone and frees its buffers.
- **Nothing relies on a `deinit` running, so skipping one can only leak.** A stale value's elements' `deinit`s are skipped ([06](../../spec/06-memory-and-allocators/arena-safety.md#stale-values-and-the-deinits-a-reset-runs)), and `unsafe` code allows for that ([10](../../spec/10-errors-and-safety/unsafe-code.md#aliasing-and-skipped-deinits)).

## Precise dependencies

**A `where` clause narrows a set only where the callee proves it** ([02](../../spec/02-views-and-dependencies/dependency-lifetimes.md#precise-dependencies-opt-in)). Verification is rule 5 restricted to what the items name, and a witness must satisfy its requirement's clause. So generic code relying on a clause stays covered.

**A value moved out of `p`'s own storage carries only what `p` carried.** A value `p` owns can view `p`'s own storage only through a dependency of `p` on a part of itself. Then `&p` conflicts, so the call that moves it out can't happen ([02](../../spec/02-views-and-dependencies/dependency-lifetimes.md#staying-valid-after-a-parameter-moves-on-outlives)).

## `rebind`

**`rebind` moves a name, such as a cursor walking down a tree, to another place** ([02](../../spec/02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind)). These rules keep the name's set covered at each step:

- **`rebind` changes which place a name stands for**, and the name's set follows the place: one reached through the name keeps the name's set, and any other starts a new borrow. A binding that owns its value first hands it to a hidden local, so views already taken still reach a live value.
- **Through objects, the cursor holds only the new object's mark.** The new place lies in that object's value, which the mark guards. An alias that destroys the object panics, since the mark is live ([03](../../spec/03-handles-and-objects.md#destroying-an-object)), and an alias that reaches it conflicts.
- **No step targets an access-bound projection**, since each step would nest another suspended accessor.

## Projections and accessors

**A projection yields a place instead of returning a value** ([02](../../spec/02-views-and-dependencies/projections-and-accessors.md#projections-read-and-modify-accessors)). These rules keep a view of what it yields covered, during the access and after it:

- **A storage projection's yield is verified to be storage of what its `where` item names** ([02](../../spec/02-views-and-dependencies/projections-and-accessors.md#storage-projections)), so a view of it depends on that, as a view of a stored field does. `unsafe` code that yields through a raw pointer promises the same.
- **After a `yield`, the accessor treats the yielded place as borrowed**, since a view of it may outlive the access: it never changes it, and after a `modify` never reads it.
- **An accessor yields exactly once on every normal path**, so the caller always gets one place.
- **An optional projection or a tuple of places exists only in its parts.** No `T?` or tuple of them lies in memory, so nothing writes, lends or views one whole.
- **A change through `get` and `set`** lends the `get`'s result and passes it to `set`, which changes `self`. So it is rejected when that result may depend on `self` or on a `mutable` argument of the access, which `set` would change while its `newValue` still views it ([02](../../spec/02-views-and-dependencies/projections-and-accessors.md#get-and-set-accessors)). A move-only `owned` argument can't move into both calls.
