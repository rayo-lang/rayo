# Moving, copying and destroying values

[01 · Values and ownership](../01-values-and-ownership.md)

A move can hand a value to a new owner without making a second one. A copy does make a second value, which matters when either value owns resources that must later be released. Rayo keeps those operations distinct and defines when the remaining values are destroyed.

## Moves

```swift
var cmds = CommandList()
cmds.draw(&mesh)
submit(consume cmds)              // submit keeps the list: it moves out of 'cmds'
print("\(cmds.count)")            // error: 'cmds' was moved
cmds = CommandList()              // fine: a new value makes 'cmds' usable again
var queued = consume cmds         // 'consume' moves the list out of 'cmds' into 'queued'
cmds = queued                     // error: write 'consume queued'
```

**`consume x` moves the value.** The new owner takes it over, and the place it came from can't be used until it gets a new value, so the value's bytes stand for it in one place only.

**A position takes a place's value only where it writes `consume`.** Every position given a place writes `&`, `mutable &`, `consume` or `copy` before it ([References](references.md#places-given-to-a-position)). So an argument, a declaration, an assignment and a `return` move a place only with `consume`. A place of an implicitly copyable type, such as an `Int`, is copied with nothing written, and stays usable ([Implicit copies](#implicit-copies)).

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

**A value of an implicitly copyable type, such as `Int` or `Vec3`, is copied with nothing written**, wherever a place of it is given with no mark ([Implicit copies](#implicit-copies)). Its type promises that the copy is cheap ([Implicitly copyable types](#implicitly-copyable-types)). Taking a copyable `const` also makes a new value ([Constants](moving-values-out.md#constants)), and so do the few operations defined to copy their operands ([below](#operations-that-copy)).

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
struct Ticket(let seat: UInt32): ~Copyable           // each ticket admits once, so a copy would admit twice
```

Generic code treats an unconstrained type parameter as possibly move-only, so copying a `T` requires `T: Copyable`. Copying one with nothing written requires `T: ImplicitlyCopyable` ([below](#implicitly-copyable-types)).

### Types that are always move-only

**Some types are move-only whatever their fields, since a second copy would break what the type promises:**

- **Exclusive views the language gives.** A mutable reference lends one place for change, and an exclusive `SoA` row lends one place in each column. Two copies would be two ways to change the same place at once ([References](references.md#making-a-reference), [04](../04-types/data-layout.md#struct-of-arrays-soat)).
- **`Synchronized` types.** A `Synchronized` type, such as `Mutex` or `Atomic<Int>`, exists once, so every thread that shares it synchronizes on the same memory ([07](../07-concurrency/synchronization.md#the-synchronized-contract)).
- **Lock guards.** A `@guard` type, such as `MutexGuard`, holds a lock for as long as it lives, and a copy would release the lock a second time ([02](../02-views-and-dependencies/dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them)).
- **`mutating` and `consuming` function values.** Calling a `mutating` one changes the closure itself, and a `consuming` one runs at most once ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds)).
- **Closure literals that hold a capture of their own, or run once.** A literal's type is move-only when it captures a place exclusively or owns a move-only capture, since a copy would be a second way to change that place or a second owner of that value. It is also move-only when it is `consuming`, since it is called at most once ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closures-by-concrete-type-some-f)).
- **`Closure<F>`**, which owns every capture, so a copy would be a second owner of them ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)).
- **A task's state**, which holds the task's parameters and the locals live across an `await`, so a copy would be a second owner of them ([07](../07-concurrency/tasks.md#semantics)).

### Implicitly copyable types

**A copyable type whose copy is cheap may promise that its copies need no `copy` written.** If every copy were written, even an `Int`'s, the cheapest operation would be the one code writes most. The marker protocol **`ImplicitlyCopyable`** refines `Copyable` and states the promise. Keeping the two apart keeps a large copyable value from ever copying silently: a copy that nothing writes is one its type has declared cheap. A type that conforms is **implicitly copyable**:

- **Number types, `Bool` and raw pointers**, which the language makes conform, since each is one machine value ([04](../04-types/numbers-and-math.md#numbers), [10](../10-errors-and-safety/unsafe-code.md#raw-pointers)). A `Simd` vector of 16 bytes or less conforms too, such as a `Vec4` ([04](../04-types/numbers-and-math.md#simd-and-math)).
- **Shared references**, `&T`, which the language makes conform, since a copy is one more shared borrow of the same place ([References](references.md#making-a-reference)).
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

**No other type the language gives conforms**, such as a mutable reference, a function value or a type value, so a copy of one is written.

**The standard library declares the protocol on each copyable type that passes one test**: its copy is 16 bytes or less, and a second copy is as good as the first. So `Handle`, `Name`, `Allocator`, `Stamp` and `std.math`'s `Vec3` are implicitly copyable. A `Panic` is copyable but larger, so its copy is written. Each chapter that declares a copyable type of the standard library says whether it conforms.

**The standard library declares the protocol on each of its generic types that holds only its type arguments and at most a tag, for the arguments that conform.** So a range of `Int`s, `T?` and `Result` conform where their arguments do, as `Optional`'s extension above declares. Such a type's copy costs what copies of its arguments cost, which their own types have declared cheap, so the test applies to them, not to the whole.

### Implicit copies

**A value of an implicitly copyable type taken from a place is copied, and the place stays usable.** Such a copy is an **implicit copy**. It happens wherever the place is given to a position with no mark written ([References](references.md#places-given-to-a-position)). Such positions include an initializer, the right side of an assignment, an argument to a parameter that owns it, a loop's subject and a `return`. A `consuming` method's receiver copies it too ([Moving values out](moving-values-out.md#moving-values-out)).

```swift
var hp = 100
var best = hp                      // a copy: Int is implicitly copyable, so 'hp' stays usable
hp -= 10                           // 'best' is still 100
best = hp                          // an assignment copies too
let gone = consume hp              // a move: 'hp' can't be used until it gets a new value
print("\(hp)")                     // error: 'hp' was moved
var lead = enemies[0]              // error: write 'copy' or '&' before 'enemies[0]'
```

**What code writes means the same for an implicitly copyable type as for any other:**

- **`copy p`** makes a copy.
- **`consume p`** moves `p`, which can't be used until it gets a new value. So does a `[move p]` capture ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)).
- **`&p` and `mutable &p`** make a reference to the place, and a `ref let` or `ref var` given one names it.
- **A `&T` argument** borrows, so a call copies nothing that its parameter doesn't own.

### Operations that copy

**Besides `copy`, `clone()`, an implicit copy and taking a copyable `const`, these operations copy their copyable operands**, as part of what they are defined to do:

- **Ranges.** A range operator borrows its operands and copies them in, so `0..<count` leaves `count` usable ([05](../05-protocols-generics-and-closures/operators.md#operators)).
- **Vectors.** A `Simd` initializer, a load included, copies the lanes it borrows, a store copies its lanes out, and a lane read, a swizzle or a shuffle copies the lanes it reads, since no lane is ever viewed ([04](../04-types/numbers-and-math.md#simd-and-math)).
- **Inline arrays.** An inline array's `.init(repeating:)` copies the value it is given into every element ([04](../04-types/collections.md#tuples-ranges-and-arrays)).
- **Allocations.** `a.alloc` reads the id in `a` once, and holds no borrow of `a`, and the value it makes keeps a copy of the id ([06](../06-memory-and-allocators/allocator-basics.md#allocating-with-alloc)).
- **Widening.** A widening conversion reads its operand and makes a new value ([Conversions](bindings.md#conversions)).
- **Static values.** Converting a copyable value to or from its [static type](../02-views-and-dependencies/scoped-values.md#converting-to-and-from-a-static-type) reads its operand and makes a new value that views the same data ([Conversions](bindings.md#conversions)).
- **`as` patterns.** An `as` pattern on a place copies it, since the conversion makes a new value ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)).
- **`get` and `set`.** A change through a value property with a `get` and a `set` copies a copyable subscript argument that its parameter owns, for the `get`, since one value can't move into both calls ([02](../02-views-and-dependencies/place-and-value-properties.md#value-properties-get-and-set)).

**One copy is deferred.** A `String` made from a plain literal or a `static &Text`, as `alloc "jump"` is, uses the text's bytes, which live as long as the program, until its first write or growth, and copies them then, so making it allocates nothing ([04](../04-types/collections.md#strings)).

## Destruction

**A value is destroyed when its owner's scope ends or when it is overwritten**, and its type's `deinit` runs then. Destruction runs in reverse order:

- a scope's locals, last declared first;
- a statement's temporaries, last made first;
- a value's parts: its own `deinit` runs first, then its fields are destroyed, last declared first. An enum payload's parts, an inline array's elements and a tuple's elements are destroyed last first.

Some values that the code doesn't declare still count as locals, and take their place in that order:

- **Parameters.** A function's parameters that own their arguments and a `consuming` method's `self` count as locals of its body declared before the others: `self` first, then the parameters in order.
- **Hidden locals.** A **hidden local** is one the language declares to keep a value that a statement can't name, such as a `when` subject ([`for` and `when` names](bindings.md#for-and-when-names)) or a loop's sequence ([04](../04-types/collections.md#iteration)). Where each counts as declared depends on what made it:
    - a closure literal's counts as declared just before the local it was made for, in the order the literals are made, so the local that holds a view of the literal is destroyed first ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values));
    - those of a `guard`, a `when` arm and a `for` loop count as declared where the statement stands: a loop's sequence temporaries in evaluation order, then its iterator ([04](../04-types/collections.md#iteration)).
- **`defer`.** A `defer` block runs as a value declared where it stands would be destroyed ([10](../10-errors-and-safety/typed-errors.md#cleanup)).

**What a destruction uses is checked in this order.** Where destroying a value uses what it borrows ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)), that use is checked in this order, against what is still alive at that point. So a lock guard declared after its mutex is released before the mutex is destroyed.

**An assignment stores the new value before it destroys the old one.** It moves the old value out to a temporary, moves the new value in, then destroys the temporary. So when the old value's `deinit` panics, the place already holds the new value, and nothing that reaches the place after the panic finds a destroyed value there ([10](../10-errors-and-safety/panics.md#unwinding)).

### Destruction by unwinding

**A panic that unwinds through a scope ends it as a `throw` would** ([10](../10-errors-and-safety/panics.md#unwinding)). The scopes end innermost first, and each destroys what it holds in this order:

1. the temporaries that the statement the panic interrupted has made so far, last made first;
2. its live locals, hidden locals and the parameters that own their arguments, last declared first, each `defer` block running where it stands. A value that a field was moved out of loses only the fields it still holds, last declared first.

**So a value is destroyed once, and only while it holds one, whichever way its scope ends.** A place that holds a value on only some paths is destroyed exactly when it holds one, as at any scope's end ([Places that hold no value](moving-values-out.md#places-that-hold-no-value)). A value still being built, such as the arguments of a primary initializer or the elements of an array literal, is only the temporaries made so far. The unwind destroys those, and no half-built value ([04](../04-types/structs.md#initializers)).
