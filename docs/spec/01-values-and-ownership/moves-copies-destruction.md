# Moving, copying and destroying values

[01 · Values and ownership](../01-values-and-ownership.md)

## Moves

```swift
var cmds = CommandList()
cmds.draw(mesh)
submit(cmds)                      // submit keeps the list: it moves out of 'cmds'
print(cmds.count)                 // error: 'cmds' was moved
cmds = CommandList()              // fine: a new value makes 'cmds' usable again
```

**Assigning a value, declaring a `let` or `var` with it, returning it or passing it to a function that keeps it moves it.** The new owner takes it over, and the place it came from can't be used until it gets a new value, so the value's bytes stand for it in one place only.

**Only a place the code owns can be moved from.** Moving out of a value the code only borrows is a compile error, since the caller, an alias or a later `deinit` that reaches that place must still find a value in it ([What can be moved from](moving-values-out.md#what-can-be-moved-from)).

**A move changes the owner and nothing else.** It runs none of the program's code, allocates nothing, and copies at most the value's bytes, into the place that takes it.

[Moving values out](moving-values-out.md#moving-values-out) lists every construct that moves a value, and every place that can be moved from.

## Copies

```swift
var spawn = copy e.pos               // Vec3 is copyable: copy duplicates its bytes
spawn.y += 2                         // e.pos is unchanged
var loadout = player.items.clone()   // List owns heap memory: clone allocates a new buffer
var a = copy player.items            // error: 'List<Item>' is not copyable
```

**Copies are written out.** Code asks for a copy in one of two forms:

- **`copy x`** duplicates the bytes of a copyable value, as `memcpy` does. It never allocates.
- **`x.clone()`** copies a move-only value together with what it owns, such as a `List` and its buffer. It allocates, and is always written as a named call.

Taking a copyable `const` also makes a new value ([Constants](moving-values-out.md#constants)), and so do the few operations defined to copy their operands ([below](#operations-that-copy)).

### Copyable types

**A type is copyable only when a copy of its bytes is a second, independent value.** That needs the bytes to be all there is to the value: it owns nothing outside them, and nothing has to run when it is destroyed. A type is **copyable** when:

- all its fields and payloads are copyable;
- it declares no `deinit`, since each copy would run it, and two copies would release one resource twice;
- it doesn't opt out with `~Copyable`;
- it isn't one of the types that are always move-only ([below](#types-that-are-always-move-only)).

So a copyable type owns no heap memory, and `copy` never allocates. Every other type is **move-only**, including every type that owns memory, such as `List`, `String`, `Box` or `Pool`, and copying one of those takes `clone()`.

The compiler derives the marker protocol **`Copyable`** for each copyable type. A type may list it, to have the compiler confirm it, or list **`~Copyable`** to opt out even though its fields could be copied:

```swift
struct Handle<T>(…): Copyable                         // the compiler confirms that Handle is copyable
struct MutableSpan<Element>(…): Scoped, ~Copyable     // two copies could change one element at once
```

Generic code treats an unconstrained type parameter as possibly move-only, so copying a `T` requires `T: Copyable`.

### Types that are always move-only

**Some types are move-only whatever their fields, since a second copy would break what the type promises:**

- **Exclusive views.** A `mutable any P` lends one place for change, and an exclusive `SoA` row lends one place in each column. Two copies would be two ways to change the same place at once ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch), [04](../04-types/data-layout.md#struct-of-arrays-soat)).
- **`Synchronized` types.** A `Synchronized` type, such as `Mutex` or `Atomic<Int>`, exists once, so every thread that shares it synchronizes on the same memory ([07](../07-concurrency/synchronization.md#the-synchronized-contract)).
- **Lock guards.** A `@guard` type, such as `MutexGuard`, holds a lock for as long as it lives, and a copy would release the lock a second time ([02](../02-views-and-dependencies/dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them)).
- **`mutating` and `consuming` function values.** Calling a `mutating` one changes the closure itself, and a `consuming` one runs at most once ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds)).
- **Closure literals that hold a capture of their own, or run once.** A literal's type is move-only when it captures a place exclusively or owns a move-only capture, since a copy would be a second way to change that place or a second owner of that value. It is also move-only when it is `consuming`, since it is called at most once ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closures-by-concrete-type-some-f)).
- **`Closure<F>`**, which owns every capture, so a copy would be a second owner of them ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)).
- **A task's state**, which holds the task's parameters and the locals live across an `await`, so a copy would be a second owner of them ([07](../07-concurrency/tasks.md#semantics)).

### Operations that copy

**Besides `copy`, `clone()` and taking a copyable `const`, these operations copy their copyable operands**, as part of what they are defined to do:

- **Ranges.** A range operator borrows its operands and copies them in, so `0..<count` leaves `count` usable ([05](../05-protocols-generics-and-closures/operators.md#operators)).
- **Vectors.** A `Simd` initializer copies the lanes it borrows, and a lane read copies the lane, since no lane is ever viewed ([04](../04-types/numbers-and-math.md#simd-and-math)).
- **Inline arrays.** An inline array's `.init(repeating:)` copies the value it repeats ([04](../04-types/collections.md#tuples-ranges-and-arrays)).
- **The current allocator.** `using allocator = a` reads the id in `a` once, on entry, and holds no borrow of `a`, so the block may contain an `await` ([06](../06-memory-and-allocators/allocator-basics.md#the-current-allocator)).
- **Widening.** A widening conversion reads its operand and makes a new value ([Conversions](bindings.md#conversions)).
- **`as` patterns.** An `as` pattern on a place copies it, since the conversion makes a new value ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)).
- **`get` and `set`.** A change through a `get` and `set` pair copies a copyable `owned` subscript argument for the `get`, since one value can't move into both calls ([02](../02-views-and-dependencies/projections-and-accessors.md#get-and-set-accessors)).

**One copy is deferred.** A `String` made from a literal uses the literal's bytes until its first write or growth, and copies them then, so making it allocates nothing ([04](../04-types/collections.md#literals)).

## Destruction

**A value is destroyed when its owner's scope ends or when it is overwritten**, and its type's `deinit` runs then. Destruction runs in reverse order:

- a scope's locals, last declared first;
- a statement's temporaries, last made first;
- a value's parts: its own `deinit` runs first, then its fields are destroyed, last declared first. An enum payload's parts, an inline array's elements and a tuple's elements are destroyed last first.

Some values that the code doesn't declare still count as locals, and take their place in that order:

- **Parameters.** A function's `owned` parameters and a `consuming` method's `self` count as locals of its body declared before the others: `self` first, then the parameters in order.
- **Hidden locals.** A **hidden local** is one the language declares to keep a value that a statement can't name, such as a `when` subject ([Conditions and patterns](bindings.md#conditions-and-patterns)) or a loop's sequence ([04](../04-types/collections.md#iteration)). Where each counts as declared depends on what made it:
    - a closure literal's counts as declared just before the local it was made for, in the order the literals are made, so the local that holds a view of the literal is destroyed first ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values));
    - a `rebind`'s counts as the binding whose value it took ([02](../02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind));
    - those of a `guard`, a `when` arm, an `if case`, a `while case` and a `for` loop count as declared where the statement stands: a loop's sequence temporaries in evaluation order, then its iterator ([04](../04-types/collections.md#iteration)).
- **`defer`.** A `defer` block runs as a value declared where it stands would be destroyed ([10](../10-errors-and-safety/typed-errors.md#cleanup)).

**What a destruction uses is checked in this order.** Where destroying a value uses what it borrows ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)), that use is checked in this order, against what is still alive at that point. So a lock guard declared after its mutex is released before the mutex is destroyed.
