# Ownership, borrows and exclusivity

[13 · Soundness](../13-soundness.md)

## Ownership

**This section keeps Owned and Valid.** Its rules decide which place holds each value, and when the value is destroyed. A value's bytes stand for it in one place only, it is destroyed once, and every place that other code may still reach holds a value.

- **A move copies bytes and ends the source** ([01](../01-values-and-ownership/moves-copies-destruction.md#moves)). Only a place the code owns can be moved from. Once moved from, it can't be used until it is given a new value, so the bytes stand for the value in one place only. Otherwise both places would be used and destroyed as one value, which Owned forbids.
- **A copy duplicates nothing owned.** `copy`, a copyable `const`, and the operations that 01 lists as copying apply only to copyable types ([01](../01-values-and-ownership/moves-copies-destruction.md#operations-that-copy)). Copyable types have no `deinit` and own no heap memory ([01](../01-values-and-ownership/moves-copies-destruction.md#copyable-types)), so a copy is never a second owner of anything. Everything that owns memory is move-only, and `clone()` allocates its own.
- **Some types are move-only whatever their fields, since a copy would alias** ([01](../01-values-and-ownership/moves-copies-destruction.md#types-that-are-always-move-only)):
    - **Mutable views.** A copy of a mutable view, a `mutable any P` or an exclusive `SoA` row would be a second mutable alias, which Exclusive forbids.
    - **Guards.** A copy of a guard would unlock its lock a second time.
    - **`Synchronized` values.** A copy would be a second place with the value's identity, so threads would no longer all synchronize on the same memory ([Threads](runtime-and-concurrency.md#threads)).
    - **Function values, `Closure`s and task states.** A copy of a `mutating` or `consuming` function value, a `Closure` or a task's state would be a second owner of the same captures or locals, which Owned forbids.
- **A place the code doesn't own always holds a value**, since a caller, an alias or a later `deinit` may still reach it, across a `throw`, an early return and an `await` too. Valid needs a value there for whoever reads or destroys it next. So nothing is consumed from these places ([01](../01-values-and-ownership/moving-values-out.md#what-can-be-moved-from)):
    - a global;
    - a borrowed or `mutable` parameter;
    - an element;
    - a place reached through a weak pointer or an accessor.

  `replace`, `swap` and `take()` take a value out of such a place by leaving another behind.
- **Initialization is tracked per path and per field** ([01](../01-values-and-ownership/moving-values-out.md#places-that-hold-no-value)). A place without a value, maybe without one, or partly moved is used only where every path has given it one, and destroyed exactly when it holds one. So every use and every destruction finds a value there, as Valid needs, and no value is destroyed twice, as Owned needs. A closure that gives a captured place its value carries whether the place holds one. It leaves the place maybe-initialized after its last use, since it may never have been called.
- **A narrowed place holds a payload wherever it is used as one** ([04](../04-types/enums.md#narrowing)), as Valid needs. Only a place whose every change the checking body sees narrows: a local, a parameter or a stored field of one. The narrowing ends at each event in that body that could make the place `nil`: a write, a lend for change, a move, an exclusive capture, a `rebind`, or an `await` for a place reached through the resume parameter. Elements, globals and places reached through objects, weak pointers or thread-locals don't narrow, since changes to them may come from elsewhere.
- **A field moves out only where no `deinit` needs it.** A `deinit` takes all of `self`, so a field moved out from under it would leave it a place with no value. So a field moves out only when no type on the path declares one, or in that type's own code: its `deinit`, or a `consuming` method that ends `self` with `discard self` ([01](../01-values-and-ownership/moving-values-out.md#what-can-be-moved-from)). `discard self` runs no `deinit`, and destroys the fields left one by one. It is allowed only in the type's own module, whose code the `deinit` protects. A `when` whose path has a `deinit` keeps its subject whole in a hidden local, for the same reason ([01](../01-values-and-ownership/bindings.md#conditions-and-patterns)).
- **A `deinit` is part of the type everywhere.** It is declared in the type's module, unconditionally ([04](../04-types/structs.md#initializers)). A `deinit` makes the type move-only, and makes its destruction a use unless the type is `PlainDeinit`. Either effect changes how every use is checked. So code that checked a type as copyable, or its destruction as no use, never meets an instance that has one.
- **Destruction runs once, in one order** ([01](../01-values-and-ownership/moves-copies-destruction.md#destruction)): reverse declaration order, hidden locals and temporaries included. So what a value's destruction uses is checked against what is still alive at that point, as when a lock guard declared after its mutex is released before the mutex is destroyed.

## Borrows and exclusivity

**This section keeps Exclusive.** With Covered ([Covered](dependencies.md#covered)), it also keeps Live for memory an owner releases. The compiler checks the law of exclusivity statically, one function body at a time ([01](../01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)). The rules below make sure that check sees every access that matters, and knows which places overlap.

**Moving, assigning and destroying are mutable accesses** ([01](../01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)). So an owner can't release or replace what a live borrow reaches, which keeps Live once Covered puts the place that holds or owns some memory in the set of every view that reaches it.

**Borrows never leave the function that makes them**, except as the dependencies its signature states (rules 3 to 5). So one body holds every borrow the checker must see, and the checking is static.

**Places overlap by path** ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)). The checker sees paths, not bytes, so it treats two paths as disjoint only where writing one can't change the other:

- **Stored fields** are disjoint, since distinct stored fields occupy distinct bytes. An `SoA` column is a buffer of its own, disjoint from the others as a stored field is.
- **A union's members** count as one place, since they share bytes.
- **A `Simd` vector's lanes** count as one, since storing one lane may rewrite the vector.
- **An enum's payload** counts as one, since its tag may be a niche inside it.
- **The bitfields of one C memory location** count as one, since they are written together.
- **Inline array elements** are disjoint only at indices known to differ where the borrows are checked, which a body checked once for every value parameter can't know.
- **A user accessor** is an access to all of `self`, since its body may reach any of it. A bitfield's generated accessors touch only their memory location.

**Two elements of one collection at once** come from an API that checks at run time that they differ ([01](../01-values-and-ownership/exclusivity.md#two-elements-of-one-collection)). Statically they always overlap, since each is reached through the collection's subscript, an accessor, which is an access to all of the collection.

**A call's borrows begin together, after its places are worked out** ([01](../01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin)). So every borrow and take of one call is checked against the others, and a value read for an argument is done before the call lends or takes its place:

```swift
items.append(items.count)     // fine: items.count is read, and done, before append borrows items
f(&x, x)                      // error: two borrows of x overlap for the whole call
```

**An optional chain or `!` reads the optional, so its borrow begins there.** An assignment through an optional chain works out the rest of its place after its right side, whose accesses have then ended.

**A borrowed argument may be a copy of its bits** ([01](../01-values-and-ownership/parameters.md#borrowed-arguments)), since nothing changes it during the call. The arguments that are always the caller's place are exactly those whose address matters:

- a `Synchronized` value, whose identity is its address, and which changes through a shared borrow;
- the argument of `ptr(to:)`, whose result is its address;
- one that a result, an error, a yield or an absorbing argument may still view after the call, which would otherwise view the callee's copy.

**Which arguments these are follows from the signature alone, and conversions keep conventions.** So a call through a function value passes its arguments as a direct call does.

**A `mutable` argument's changes reach the caller's place**, through a written-back temporary too ([01](../01-values-and-ownership/parameters.md#parameters)).

**Only a changeable place is written** ([01](../01-values-and-ownership/bindings.md#changeable-places)), so a shared borrow never becomes a write. Each exception brings its own exclusivity:

- the dynamic marks of a thread-local and an object's value;
- a `Synchronized` value's synchronization;
- the promise of `unsafe` code.

**A `when` holds its subject still while arms are tested** ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)), so a guard sees the value its arm then binds, and an `owned` part moves only once its arm is chosen.
