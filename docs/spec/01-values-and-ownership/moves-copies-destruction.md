# Moving, copying and destroying values

[01 · Values and ownership](../01-values-and-ownership.md)

A move can hand a value to a new owner without making a second one. A copy does make a second value, which matters when either value owns resources that must later be released. Rayo keeps those operations distinct and defines when the remaining values are destroyed.

## Moves

```swift
var cmds = CommandList()
cmds.draw(mesh)
submit(cmds)                      // submit keeps the list: it moves out of 'cmds'
print(cmds.count)                 // error: 'cmds' was moved
cmds = CommandList()              // fine: a new value makes 'cmds' usable again
var queued = consume cmds         // 'consume' moves the list out of 'cmds' into 'queued'
cmds = queued                     // error: assigning a place takes 'copy' or 'consume'
```

**`consume x`, returning a local, and passing a place to a function that keeps it move the value.** The new owner takes it over, and the place it came from can't be used until it gets a new value, so the value's bytes stand for it in one place only. A value of an implicitly copyable type, such as an `Int`, is copied instead by each of these but `consume`, and its place stays usable ([Implicit copies](#implicit-copies)).

**An assignment or a declaration takes a place's value only where it writes `consume`.** A `let` or `var` given a place writes `copy` or `consume` before it, or is declared `ref let` to borrow the place read-only, as an argument does ([Bindings](bindings.md#bindings-that-own-a-value)). An assignment given a place writes `copy` or `consume`, and leaving both out is a compile error that names them, since the place it assigns stores a value of its own, which a borrow isn't. These need neither:

- one of an implicitly copyable type, which copies the place ([Implicit copies](#implicit-copies));
- one from a copyable `const`, which gives a new value ([Constants](moving-values-out.md#constants));
- one whose conversion makes a value of its own from the place, such as a view or a numeric widening ([Conversions](bindings.md#conversions));
- a declaration from a place in a temporary's own storage, which the binding owns ([Bindings](bindings.md#bindings-that-own-a-value));
- `_ = x`, which takes what `x` holds and drops it on purpose, as [Moving values out](moving-values-out.md#moving-values-out) lists ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unused-values)).

**Only a place the code owns can be moved from.** Moving out of a value the code only borrows is a compile error, since the caller, an alias or a later `deinit` that reaches that place must still find a value in it ([What can be moved from](moving-values-out.md#what-can-be-moved-from)).

**A move changes the owner and nothing else.** It runs none of the program's code, allocates nothing, and copies at most the value's bytes, into the place that takes it.

[Moving values out](moving-values-out.md#moving-values-out) lists every construct that moves a value, and every place that can be moved from.

## Copies

```swift
var spare = copy enemies[0]                // Enemy is copyable: copy duplicates its bytes
spare.hp = 50                              // enemies[0] is unchanged
var spawn = e.pos                          // Vec3 is implicitly copyable: copied with nothing written
spawn.y += 2                               // e.pos is unchanged
var loadout = alloc player.items.clone()   // List owns heap memory: clone allocates a new buffer
var a = copy player.items                  // error: 'List<Item>' is not copyable
```

**Copies are written out, unless the type declares them cheap.** Code asks for a copy in one of two forms:

- **`copy x`** duplicates the bytes of a copyable value, as `memcpy` does. It never allocates.
- **`alloc x.clone()`** copies a move-only value together with what it owns, such as a `List` and its buffer. It allocates, and is always written as a named call. `clone()` receives the copy's allocator from the `alloc` before it ([06](../06-memory-and-allocators/allocator-basics.md#functions-that-make-a-new-value-alloc-func)).

**A value of an implicitly copyable type, such as `Int` or `Vec3`, is copied with nothing written**, where a place would otherwise be moved or bound ([Implicit copies](#implicit-copies)). Its type promises that the copy is cheap ([Implicitly copyable types](#implicitly-copyable-types)). Taking a copyable `const` also makes a new value ([Constants](moving-values-out.md#constants)), and so do the few operations defined to copy their operands ([below](#operations-that-copy)).

### Copyable types

**A type is copyable only when a copy of its bytes is a second, independent value.** That needs the bytes to be all there is to the value: it owns nothing outside them, and nothing has to run when it is destroyed. A type is **copyable** when:

- all its fields and payloads are copyable;
- it declares no `deinit`, since each copy would run it, and two copies would release one resource twice;
- it doesn't opt out with `~Copyable`;
- it isn't one of the types that are always move-only ([below](#types-that-are-always-move-only));
- it isn't an `@opaque` C type, which has no values to copy and conforms to no protocol ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#type-parameters-with-no-known-size-opaque)).

So a copyable type owns no heap memory, and `copy` never allocates. Every other type is **move-only**, including every type that owns memory, such as `List`, `String`, `Box` or `Pool`, and copying one of those takes `clone()`.

The compiler derives the marker protocol **`Copyable`** for each copyable type. A type may list it, to have the compiler confirm it, or list **`~Copyable`** to opt out even though its fields could be copied:

```swift
struct Handle<T>(…): Copyable                         // the compiler confirms that Handle is copyable
struct MutableSpan<Element>(…): Scoped, ~Copyable     // two copies could change one element at once
```

Generic code treats an unconstrained type parameter as possibly move-only, so copying a `T` requires `T: Copyable`. Copying one with nothing written requires `T: ImplicitlyCopyable` ([below](#implicitly-copyable-types)).

### Types that are always move-only

**Some types are move-only whatever their fields, since a second copy would break what the type promises:**

- **Exclusive views.** A `mutable any P` lends one place for change, and an exclusive `SoA` row lends one place in each column. Two copies would be two ways to change the same place at once ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch), [04](../04-types/data-layout.md#struct-of-arrays-soat)).
- **`Synchronized` types.** A `Synchronized` type, such as `Mutex` or `Atomic<Int>`, exists once, so every thread that shares it synchronizes on the same memory ([07](../07-concurrency/synchronization.md#the-synchronized-contract)).
- **Lock guards.** A `@guard` type, such as `MutexGuard`, holds a lock for as long as it lives, and a copy would release the lock a second time ([02](../02-views-and-dependencies/dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them)).
- **`mutating` and `consuming` function values.** Calling a `mutating` one changes the closure itself, and a `consuming` one runs at most once ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds)).
- **Closure literals that hold a capture of their own, or run once.** A literal's type is move-only when it captures a place exclusively or owns a move-only capture, since a copy would be a second way to change that place or a second owner of that value. It is also move-only when it is `consuming`, since it is called at most once ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closures-by-concrete-type-some-f)).
- **`Closure<F>`**, which owns every capture, so a copy would be a second owner of them ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)).
- **A task's state**, which holds the task's parameters and the locals live across an `await`, so a copy would be a second owner of them ([07](../07-concurrency/tasks.md#semantics)).

### Implicitly copyable types

**A copyable type whose copy is cheap may promise that its copies need no `copy` written.** If every copy were written, even an `Int`'s, the cheapest operation would be the one code writes most. The marker protocol **`ImplicitlyCopyable`** refines `Copyable` and states the promise. Keeping the two apart keeps a large copyable value from ever copying silently: a copy that nothing writes is one its type has declared cheap. A type that conforms is **implicitly copyable**:

- **Number types, `Bool` and raw pointers**, which the language makes conform, since each is one machine value ([04](../04-types/numbers-and-math.md#numbers), [10](../10-errors-and-safety/unsafe-code.md#raw-pointers)). A `Simd` vector of 16 bytes or less conforms too, such as a `Vec4` ([04](../04-types/numbers-and-math.md#simd-and-math)).
- **A struct or enum that lists `ImplicitlyCopyable`.** The compiler confirms that the type is copyable and that every field and payload is implicitly copyable, as it confirms a listed `Copyable`. A `~Copyable` type can't conform.
- **A tuple whose elements all conform**, since a tuple's type spells out each element, so a reader sees each value it copies.

**A struct or enum conforms only by listing the protocol**, never by derivation, since only its author knows whether its copies stay cheap as it changes. A generic type lists it in a constrained extension, for the type arguments that make every field conform. Whether a type conforms is part of its module's interface ([11](../11-compilation-model.md#type-checking-is-local)).

```swift
struct EntityId(let index: UInt32, let generation: UInt32): ImplicitlyCopyable   // fine: both fields conform
struct Enemy(var pos: Vec3, var hp: Float)                    // copyable, but a copy of it is written
struct Tag(var id: EntityId, var name: String): ImplicitlyCopyable   // error: 'String' is not copyable
extension Optional: ImplicitlyCopyable where T: ImplicitlyCopyable {}   // as the prelude declares it
```

**An inline array never conforms**, even a `[4 of Float]`. So a copy of an array is always written, and a `[4096 of UInt8]` never copies silently ([04](../04-types/collections.md#tuples-ranges-and-arrays)).

**Generic code copies a `T` with nothing written only under `T: ImplicitlyCopyable`**, since an unconstrained or merely copyable `T` may be a large value. Under `T: Copyable` alone, it writes `copy x`.

**The standard library declares the protocol on each copyable type that passes one test**: its copy is 16 bytes or less, and a second copy is as good as the first. So `Handle`, `Name`, the ranges of implicitly copyable bounds, `Allocator`, `Stamp`, `std.math`'s `Vec3`, and `T?` where `T` conforms are implicitly copyable. A `Panic` is copyable but larger, so its copy is written. Each chapter that declares a copyable type of the standard library says whether it conforms.

### Implicit copies

**A value of an implicitly copyable type taken from a place is copied, and the place stays usable.** That holds wherever the place would otherwise be moved, or bound by a `let` or `var`:

- a `let` or `var` initializer, including the last expression of an `if` or `when` arm, or of an `unsafe` block, whose position it hands on ([Bindings](bindings.md#if-and-when-as-values));
- the right side of an assignment;
- a `let` or `var` binding in a condition ([Bindings](bindings.md#conditions));
- a `for` or `when` name whose subject isn't lent with `&` ([Bindings](bindings.md#for-and-when-names));
- an argument to an `owned` parameter, an initializer's argument, an element of a tuple or array literal, and an enum case's payload;
- the other constructs that take a value with no `consume` written, such as `return` ([Moving values out](moving-values-out.md#moving-values-out)).

```swift
var hp = 100
var best = hp                      // a copy: Int is implicitly copyable, so 'hp' stays usable
hp -= 10                           // 'best' is still 100
best = hp                          // an assignment copies too
let gone = consume hp              // a move: 'hp' can't be used until it gets a new value
log(hp)                            // error: 'hp' was moved
var lead = enemies[0]              // error: write 'copy' or 'consume' before 'enemies[0]', or declare 'ref let'
```

**What code writes keeps its meaning, whatever the type:**

- **`copy p`** stays valid, and means the same.
- **`consume p`** still moves `p`, which can't be used until it gets a new value. So does a `[move p]` capture ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)).
- **A `ref let` or `ref var`** still refers to the place.
- **A borrowed argument** still borrows, so a call copies nothing that its parameter doesn't keep.

### Operations that copy

**Besides `copy`, `clone()`, an implicit copy and taking a copyable `const`, these operations copy their copyable operands**, as part of what they are defined to do:

- **Ranges.** A range operator borrows its operands and copies them in, so `0..<count` leaves `count` usable ([05](../05-protocols-generics-and-closures/operators.md#operators)).
- **Vectors.** A `Simd` initializer, a load included, copies the lanes it borrows, a store copies its lanes into the span, and a lane read, a swizzle or a shuffle copies the lanes it reads, since no lane is ever viewed ([04](../04-types/numbers-and-math.md#simd-and-math)).
- **Inline arrays.** An inline array's `.init(repeating:)` copies the value it is given into every element ([04](../04-types/collections.md#tuples-ranges-and-arrays)).
- **Allocations.** `a.alloc` reads the id in `a` once, and holds no borrow of `a`, and the value it makes keeps a copy of the id ([06](../06-memory-and-allocators/allocator-basics.md#allocating-with-alloc)).
- **Widening.** A widening conversion reads its operand and makes a new value ([Conversions](bindings.md#conversions)).
- **Static values.** Converting a copyable value to or from its [static type](../02-views-and-dependencies/scoped-values.md#converting-to-and-from-a-static-type) reads its operand and makes a new value that views the same data ([Conversions](bindings.md#conversions)).
- **`as` patterns.** An `as` pattern on a place copies it, since the conversion makes a new value ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)).
- **`get` and `set`.** A change through a value property with a `get` and a `set` copies a copyable `owned` subscript argument for the `get`, since one value can't move into both calls ([02](../02-views-and-dependencies/place-and-value-properties.md#value-properties-get-and-set)).

**One copy is deferred.** A `String` made from a plain literal or a `static StringView`, as `alloc "jump"` is, uses the view's bytes, which live as long as the program, until its first write or growth, and copies them then, so making it allocates nothing ([04](../04-types/collections.md#strings)).

## Destruction

**A value is destroyed when its owner's scope ends or when it is overwritten**, and its type's `deinit` runs then. Destruction runs in reverse order:

- a scope's locals, last declared first;
- a statement's temporaries, last made first;
- a value's parts: its own `deinit` runs first, then its fields are destroyed, last declared first. An enum payload's parts, an inline array's elements and a tuple's elements are destroyed last first.

Some values that the code doesn't declare still count as locals, and take their place in that order:

- **Parameters.** A function's `owned` parameters and a `consuming` method's `self` count as locals of its body declared before the others: `self` first, then the parameters in order.
- **Hidden locals.** A **hidden local** is one the language declares to keep a value that a statement can't name, such as a `when` subject ([`for` and `when` names](bindings.md#for-and-when-names)) or a loop's sequence ([04](../04-types/collections.md#iteration)). Where each counts as declared depends on what made it:
    - a closure literal's counts as declared just before the local it was made for, in the order the literals are made, so the local that holds a view of the literal is destroyed first ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values));
    - a `rebind`'s counts as the binding whose value it took ([02](../02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind));
    - those of a `guard`, a `when` arm and a `for` loop count as declared where the statement stands: a loop's sequence temporaries in evaluation order, then its iterator ([04](../04-types/collections.md#iteration)).
- **`defer`.** A `defer` block runs as a value declared where it stands would be destroyed ([10](../10-errors-and-safety/typed-errors.md#cleanup)).

**What a destruction uses is checked in this order.** Where destroying a value uses what it borrows ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)), that use is checked in this order, against what is still alive at that point. So a lock guard declared after its mutex is released before the mutex is destroyed.

**An assignment stores the new value before it destroys the old one.** It moves the old value out to a temporary, moves the new value in, then destroys the temporary. So when the old value's `deinit` panics, the place already holds the new value, and nothing that reaches the place after the panic finds a destroyed value there ([10](../10-errors-and-safety/panics.md#unwinding)).

### Destruction by unwinding

**A panic that unwinds through a scope ends it as a `throw` would** ([10](../10-errors-and-safety/panics.md#unwinding)). The scopes end innermost first, and each destroys what it holds in this order:

1. the temporaries that the statement the panic interrupted has made so far, last made first;
2. its live locals, hidden locals and `owned` parameters, last declared first, each `defer` block running where it stands. A value that a field was moved out of loses only the fields it still holds, last declared first.

**So a value is destroyed once, and only while it holds one, whichever way its scope ends.** A place that holds a value on only some paths is destroyed exactly when it holds one, as at any scope's end ([Places that hold no value](moving-values-out.md#places-that-hold-no-value)). A value still being built, such as the arguments of a primary initializer or the elements of an array literal, is only the temporaries made so far. The unwind destroys those, and no half-built value ([04](../04-types/structs.md#initializers)).
