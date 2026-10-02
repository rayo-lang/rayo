# 01 · Values and ownership

```swift
struct Enemy(var pos: Vec3, var hp: Float)

var a = Enemy(pos: .zero, hp: 100)
owned var b = a                    // a move: 'b' takes over the enemy, and 'a' can't be used any more
var c = copy b                     // a copy, written out: Enemy is copyable, so this is a memcpy
c.hp = 50                          // 'b' is unchanged

func heal(_ e: mutable Enemy) { e.hp = 100 }
heal(&b)                           // lends 'b' to heal, which changes it in place: no copy
```

A **place** is storage that holds a value: a local, a global, a parameter or a temporary, or a part of one, such as `enemy.hp` or `list[i]`.

**Every value has one owner**, which decides when the value is destroyed. The exception is reference counting: `Shared<T>` lets several owners share one value, and the last owner to let go destroys it ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners)). Code that uses a value without owning it **borrows** it.

**A second value exists only where the code asks for one**: with `copy` or `clone()`, by taking a copyable `const` ([below](#constants)), or through an operation that copies its operands ([below](#operations-that-copy)).

## Tiers of checking

Rayo checks each pattern of memory use at one of three levels, its **tiers**: statically, by the compiler; dynamically, by a check at each use; or not at all, in `unsafe` code, `unchecked` blocks and C.

**Each pattern is checked in the cheapest tier that can check it.** A pattern the static checker can't prove is checked at run time, in the dynamic tier. It is never forbidden for that reason, and never forced into `unsafe`.

| Tier | Mechanisms | Checked | Cost |
| --- | --- | --- | --- |
| **Static** | Values, moves, borrows (bindings and parameters), scoped values, dependencies, `rebind` | By the compiler, inside one function body | Zero |
| **Dynamic** | `Handle<T>` into pools; `UniquePointer<T>` + `WeakPointer<T>` for objects; `WeakShared<T>` links to reference-counted values; `Slice<T>` of a buffer; thread-local `var`s; the locks of `Synchronized` types ([07](07-concurrency.md#atomics-and-locks)); an owning value's allocator word ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)) | At each use: a stale link reads `nil` or panics instead of dangling, and conflicting uses panic or wait instead of racing | A check per use, visible in the type, or for a thread-local in its `@threadlocal` declaration |
| **Unsafe** | `*T` raw pointers and raw memory, calls into C, `unchecked`, and the other operations that 10 lists ([10](10-errors-and-safety.md#what-needs-unsafe)) | Not checked | Zero |

**Safe code** is the code of the first two tiers: everything outside `unsafe` code, `unchecked` blocks and C. It has no undefined behavior ([11](11-compilation-model.md#what-the-language-leaves-open)).

## Moves

```swift
var cmds = CommandList()
cmds.draw(mesh)
submit(cmds)                      // submit keeps the list: it moves out of 'cmds'
print(cmds.count)                 // error: 'cmds' was moved
cmds = CommandList()              // fine: a new value makes 'cmds' usable again
```

**Assigning a value, returning it or passing it to a function that keeps it moves it.** The new owner takes it over, and the place it came from can't be used until it gets a new value, so the value's bytes stand for it in one place only.

**Only a place the code owns can be moved from.** Moving out of a value the code only borrows is a compile error, since the caller, an alias or a later `deinit` that reaches that place must still find a value in it ([below](#what-can-be-moved-from)).

**A move changes the owner and nothing else.** It runs none of the program's code, allocates nothing, and copies at most the value's bytes, into the place that takes it.

[Moving values out](#moving-values-out) lists every construct that moves a value, and every place that can be moved from.

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

Taking a copyable `const` also makes a new value ([below](#constants)), and so do the few operations defined to copy their operands ([below](#operations-that-copy)).

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

- **Exclusive views.** A `mutable any P` lends one place for change, and an exclusive `SoA` row lends one place in each column. Two copies would be two ways to change the same place at once ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch), [04](04-types.md#struct-of-arrays-soat)).
- **`Synchronized` types.** A `Synchronized` type, such as `Mutex` or `Atomic<Int>`, exists once, so every thread that shares it synchronizes on the same memory ([07](07-concurrency.md#the-synchronized-contract)).
- **Lock guards.** A `@guard` type, such as `MutexGuard`, holds a lock for as long as it lives, and a copy would release the lock a second time ([02](02-views-and-dependencies.md#lock-guards-are-released-on-the-thread-that-took-them)).
- **`mutating` and `consuming` function values.** Calling a `mutating` one changes the closure itself, and a `consuming` one runs at most once ([05](05-protocols-generics-and-closures.md#closure-kinds)).
- **Closure literals that hold a capture of their own, or run once.** A literal's type is move-only when it captures a place exclusively or owns a move-only capture, since a copy would be a second way to change that place or a second owner of that value. It is also move-only when it is `consuming`, since it is called at most once ([05](05-protocols-generics-and-closures.md#closures-by-concrete-type-some-f)).
- **`Closure<F>`**, which owns every capture, so a copy would be a second owner of them ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref)).
- **A task's state**, which holds the task's parameters and the locals live across an `await`, so a copy would be a second owner of them ([07](07-concurrency.md#semantics)).

### Operations that copy

**Besides `copy`, `clone()` and taking a copyable `const`, these operations copy their copyable operands**, as part of what they are defined to do:

- **Ranges.** A range operator borrows its operands and copies them in, so `0..<count` leaves `count` usable ([05](05-protocols-generics-and-closures.md#operators)).
- **Vectors.** A `Simd` initializer copies the lanes it borrows, and a lane read copies the lane, since no lane is ever viewed ([04](04-types.md#simd-and-math)).
- **Inline arrays.** An inline array's `.init(repeating:)` copies the value it repeats ([04](04-types.md#tuples-ranges-and-arrays)).
- **The current allocator.** `using allocator = a` reads the id in `a` once, on entry, and holds no borrow of `a`, so the block may contain an `await` ([06](06-memory-and-allocators.md#the-current-allocator)).
- **Widening.** A widening conversion reads its operand and makes a new value ([below](#conversions)).
- **`as` patterns.** An `as` pattern on a place copies it, since the conversion makes a new value ([04](04-types.md#matching-with-when-and-choosing-with-if)).
- **`get` and `set`.** A change through a `get` and `set` pair copies a copyable `owned` subscript argument for the `get`, since one value can't move into both calls ([02](02-views-and-dependencies.md#get-and-set-accessors)).

**One copy is deferred.** A `String` made from a literal uses the literal's bytes until its first write or growth, and copies them then, so making it allocates nothing ([04](04-types.md#literals)).

## Destruction

**A value is destroyed when its owner's scope ends or when it is overwritten**, and its type's `deinit` runs then. Destruction runs in reverse order:

- a scope's locals, last declared first;
- a statement's temporaries, last made first;
- a value's parts: its own `deinit` runs first, then its fields are destroyed, last declared first. An enum payload's parts, an inline array's elements and a tuple's elements are destroyed last first.

Some values that the code doesn't declare still count as locals, and take their place in that order:

- **Parameters.** A function's `owned` parameters and a `consuming` method's `self` count as locals of its body declared before the others: `self` first, then the parameters in order.
- **Hidden locals.** A **hidden local** is one the language declares to keep a value that a statement can't name, such as a `when` subject ([below](#conditions-and-patterns)) or a loop's sequence ([04](04-types.md#iteration)). Where each counts as declared depends on what made it:
    - a closure literal's counts as declared just before the local it was made for, in the order the literals are made, so the local that holds a view of the literal is destroyed first ([05](05-protocols-generics-and-closures.md#function-typed-values));
    - a `rebind`'s counts as the binding whose value it took ([02](02-views-and-dependencies.md#pointing-a-name-at-another-place-rebind));
    - those of a `guard`, a `when` arm, an `if case`, a `while case` and a `for` loop count as declared where the statement stands: a loop's sequence temporaries in evaluation order, then its iterator ([04](04-types.md#iteration)).
- **`defer`.** A `defer` block runs as a value declared where it stands would be destroyed ([10](10-errors-and-safety.md#cleanup)).

**What a destruction uses is checked in this order.** Where destroying a value uses what it borrows ([02](02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it)), that use is checked in this order, against what is still alive at that point. So a lock guard declared after its mutex is released before the mutex is destroyed.

## Parameters

**A parameter's convention says what the function does with its argument**: looks at it (the default), changes it in place, or keeps it.

```swift
func length(_ v: Vec3) -> Float { ... }                 // borrows v: reads it, can't change it
func damage(_ e: mutable Enemy, by amount: Float) { ... } // borrows e mutably: changes the caller's enemy
func adopt(_ items: owned List<Item>) { ... }       // takes ownership: keeps the list
func remember(_ pos: owned Vec3) { ... }            // takes ownership: keeps the position

damage(&boss, by: 10)                                   // '&' marks the mutable borrow; 'boss' must be a changeable place
adopt(loot)                                             // 'loot' is moved in and can't be used after
adopt(backpack.items.clone())                           // a clone is a new value, so nothing moves
remember(copy e.pos)                                    // a copy moves in, and e.pos stays as it was
```

| Convention | Declared as | Call site | Callee receives |
| --- | --- | --- | --- |
| borrowed (default) | `_ x: T` | `f(x)` | A shared borrow ([below](#borrowed-arguments)) |
| mutable | `_ x: mutable T` | `f(&x)` | A mutable borrow of a [changeable place](#changeable-places) |
| owned | `_ x: owned T` | `f(x)` | The value: a place moves in, whatever its type, and `f(copy x)` passes a copy |

- **The callee owns an `owned` argument as a `var` owns its value.** It may change or consume it. It is destroyed when the call ends, unless the callee moves it on. A `consuming` method's `self` is held the same way.
- **Methods use the same conventions for `self`.** A plain `func` borrows it, a `mutating func` takes it `mutable`, and a `consuming func` takes it `owned`. A struct's primary initializer takes its fields `owned`, since the value owns its fields ([04](04-types.md#initializers)). So `World(enemies: enemies)` moves `enemies` in.
- **Conventions line up across an indirection.** A protocol witness, a function converted to a function type, and a function type converted to another declare each parameter, and `self`, with the convention of what they stand for ([05](05-protocols-generics-and-closures.md#implicit-conversions)). So a call through any of them passes its arguments as a direct call would ([below](#borrowed-arguments)).
- **A `mutable` argument's changes always reach the caller's place**, even when it is lent through a temporary that is written back, as a bitfield or an under-aligned field is ([04](04-types.md#packed-structs-and-under-aligned-places)).

**Some parameters are received `owned` with no `owned` written**, unless they are declared `mutable`. Each is used in a way that a borrowed parameter, which is read-only, can't be ([below](#changeable-places)):

- **Function values that change or consume their captures.** This covers a parameter of a `mutating` or `consuming` function type, and one of a type parameter constrained to one, written `some F` or named. Calling such a value changes or consumes the closure, so a borrowed one could never be called ([05](05-protocols-generics-and-closures.md#closure-kinds)).
- **`mutable any P`.** It is a view of its own, and calling a `mutating` requirement through it needs the view in a changeable place ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)).

### Default arguments

**A default value makes an argument optional:**

```swift
func spawn(_ kind: Kind, at pos: Vec3 = .zero) { ... }
spawn(kind)                                             // leaves out 'at:', so 'pos' is .zero
```

- **The default is checked where it is declared**, as the body of a function with no parameters that returns the parameter's type and doesn't throw. So it names no other parameter and no `self`, and a view it returns views only static storage ([02](02-views-and-dependencies.md#rule-5-the-callee-side)).
- **A call that leaves the argument out calls that function** in the argument's position, as part of the call's own statement ([below](#evaluation-order-and-when-a-calls-borrows-begin)).
- **A `mutable` parameter has no default**, since it stands for a place of the caller's.
- **A field's default works the same way** in the primary initializer ([04](04-types.md#initializers)).

### Borrowed arguments

**Safe code in the callee can't change, keep or take the address of a borrowed argument, and nothing else changes it before the call returns** ([below](#the-law-of-exclusivity)). The exception is a `Synchronized` value the argument holds, which changes through its own synchronization ([07](07-concurrency.md#the-synchronized-contract)).

**So the callee may see a copy of the argument's bits or the caller's place, and the compiler chooses.** The callee can't tell them apart. These borrowed arguments are always the caller's place, since their address matters:

- **A `Synchronized` value.** An argument that is or holds one at any depth, since such a value's identity is its address, and it changes through a shared borrow. A `Closure<F>` counts, since its captures may hold one ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref)).
- **The argument of `ptr(to:)`**, whose result is its address ([10](10-errors-and-safety.md#taking-an-address)).
- **An argument still viewed after the call.** The result, a thrown error, a storage projection's yield ([02](02-views-and-dependencies.md#storage-projections)) or an absorbing argument may view the argument's own storage, which in a copy would be the callee's. An absorbing argument is a `mutable` one, or an `owned` mutable view, such as a `MutableSpan` or a `mutating` closure (rule 4 in [02](02-views-and-dependencies.md#rule-4-absorption)).

[Rules 3 and 4](02-views-and-dependencies.md#dependencies), and an accessor's `where yield` clause, tell which arguments may still be viewed: they go by the signature's types, and by which arguments are [shallow](02-views-and-dependencies.md#shallow-values). An `Int` or a `List<Int>` result views nothing.

**Which arguments are the caller's place follows from the signature alone**: the function called, its result and error types, its `where yield` clause, and each parameter's type and convention.

- **Adding `keep` to a parameter changes none of this** ([05](05-protocols-generics-and-closures.md#what-a-closure-may-keep-keep)).
- **A call through a function value passes its arguments as a direct call would**, since every function-type conversion keeps the conventions, and which arguments are places ([05](05-protocols-generics-and-closures.md#implicit-conversions)). `ptr(to:)` is never a function value ([10](10-errors-and-safety.md#taking-an-address)).

### Evaluation order, and when a call's borrows begin

```swift
items.append(items.count)     // fine: items.count is read, and done, before append borrows items
builder.finish(builder.count) // fine: count is read before finish takes builder
f(&x, x)                      // error: two borrows of x overlap for the whole call
```

**Evaluation is left to right, and a call's borrows begin with the call.** So a value read for an argument is done before the call lends or takes its place, and every borrow and take of one call is checked against the others. The order is fixed, so two implementations never disagree about it ([11](11-compilation-model.md#what-the-language-leaves-open)). A call runs in this order:

1. **It evaluates its callee, then its receiver, then its arguments.** Evaluating a borrowed or `mutable` argument works out which place it names: its base first, then its indices, left to right. An `owned` argument or a `consuming` receiver that names a place is worked out the same way.
2. **Then the call begins.** Every borrow it passes begins, and lasts until the call returns, and every value it takes leaves its place.
3. **As it begins, it runs the accessors those places reach**, in the order the places were worked out, receiver first. These are the `read` and `modify` projections, and the `get` of each `get` and `set` pair that the call lends for change ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)).
4. **When it returns, it ends those accesses in reverse order**, running the code after each `yield` and calling each `set`. An access-bound projection's access that the result still depends on is the exception: it ends at that value's last use ([02](02-views-and-dependencies.md#access-bound-projections)).

**Any other `get` runs as its argument or receiver is evaluated.** It makes a value, whatever the call then does with it: borrows it, changes it as a mutable form's view, takes it, or calls a method on it. Its result keeps what it depends on borrowed (rule 3 in [02](02-views-and-dependencies.md#rule-3-call-results)).

```swift
items.insert(x, at: items.count)   // count's get has returned before insert borrows items
```

**Working out a place never accesses it**, except for an optional chain (`?.`) or a force unwrap (`!`) in a borrowed or `mutable` argument. Unwrapping reads the optional, so the borrow up to that point begins there, and lasts until the call returns:

```swift
damage(&world.enemies[h]!, by: reinforce(&world.enemies))   // error: '!' begins the borrow of world.enemies before reinforce runs
```

**These keep the same left-to-right order:**

- operator operands, the elements of tuple and array literals, and the segments of an interpolated string;
- an assignment, which works out its left place, evaluates its right side, then writes;
- a compound assignment `a ⊕= b`, which works out `a`'s place once, evaluates `b`, then reads the place, applies `⊕` and writes the result back ([05](05-protocols-generics-and-closures.md#operators)).

**Some operands are skipped.** `&&`, `||` and `??` evaluate their right side only when the left doesn't decide. Optional chaining skips the rest of the chain at a `nil`, arguments included.

**An assignment through `?.`, `?` or `!` reads the optional only after evaluating its right side.** When the left side holds one, the assignment works out its left place up to the first of them. Then it evaluates its right side, and only then reads the optional and works out the rest, so the right side's accesses have ended by then. A compound assignment does the same. When the chain stops at a `nil`, the right side's value is dropped.

```swift
pool[h]?.hp = 0                                       // works out pool[h], evaluates 0, then reads the optional
requests[h]? = v                                      // the same through '?': v is evaluated before the optional is read
pool[a]?.hp = copy pool[b]!.hp                        // fine: pool[b] is read before pool[a]'s optional is
world.enemies[h]?.hp -= reinforce(&world.enemies)     // fine: reinforce returns before the optional is read
```

## Bindings

**A local binding says what it does with what it is given, in a parameter's words.** `let` and `var` say only whether the binding may change what it holds. A binding of a place borrows it, and `owned` takes the value out instead.

```swift
var enemies = loadEnemies()

let seen = enemies[0]              // looks: a read-only name for the enemy, nothing copied
var boss = &enemies[0]             // changes it in place: boss.hp = 0 changes enemies[0]
var spare = copy enemies[0]        // a second enemy of its own
let mesh = loadMesh()              // a value, not a place: the binding owns it, with no 'owned' written
var e = enemies[0]                 // error: a bare 'var' of a place
```

| Form | Like the parameter | Meaning | Cost |
| --- | --- | --- | --- |
| `let x = place` | `_ x: T` | A shared **borrow** of `place`, of any type: `place` can't be changed, moved or destroyed while `x` is live | None |
| `var x = &place` | `_ x: mutable T` | A mutable **borrow** of a [changeable place](#changeable-places): `place` is reachable only through `x` while `x` is live | None |
| `owned let x = place`, `owned var x = place` | `_ x: owned T` | A **move** from a place the code owns ([below](#what-can-be-moved-from)): `place` can't be used until it gets a new value | A `memcpy` at most |
| `let x = copy place`, `var x = copy place` | | An independent **copy** of a copyable value; a move-only one is copied with `.clone()` | A `memcpy` |
| `let x = f()`, `var x = f()` | | The binding owns the value, even a move-only scoped value such as a `MutableSpan` or a lock guard ([02](02-views-and-dependencies.md#scoped-values)); `consume x` ends it early | None |
| `var x = place` | | A compile error, except for a `const` of a copyable type, which gives the `var` a new value ([below](#constants)) | |

- **A binding of anything that isn't a place owns it**, as a binding of a call's result does: a literal, an operator's result, `copy place` or `consume place`. On such a binding, `owned` changes nothing. A binding that owns its value can move it on, and a `let` still can't change it.
- **Views taken from a `let` of a place depend on the place itself** ([02](02-views-and-dependencies.md#rule-1-projection)).
- **A place in a temporary's own storage dies with its statement**, such as `makeEnemy().pos`. So a `let` of one owns that value instead, moving it out as [What can be moved from](#what-can-be-moved-from) allows. Where that can't move it, the binding is a compile error unless it is written with `copy` or `.clone()`.
- **A place that a `where yield outlives self` projection yields from a temporary lies outside the temporary**, such as `makeSpan()[0]`. So a `let` of one borrows it, depending on what the temporary carries ([02](02-views-and-dependencies.md#temporaries)).
- **Neither borrowing form may bind an under-aligned place**: that is a compile error, since a load or store of its type at that address may be invalid, and fault on some targets ([04](04-types.md#packed-structs-and-under-aligned-places)).

### What a `let` of a place sees

**Changing a place while a `let` of it is used is a compile error**, since the `let` is a shared borrow ([below](#the-law-of-exclusivity)). For a place reached through an object or a thread-local, it is a panic instead ([below](#how-long-a-borrow-lasts)). A `Synchronized` value still changes through its own synchronization ([07](07-concurrency.md#the-synchronized-contract)).

**Making a field computed, or stored, never silently changes what a `let` of it sees.** What the `let` sees follows from how the field is declared:

- A `let` of a stored field is another name for the field.
- A `let` of a property whose accessor is a `get` owns the value the `get` returns.
- A `let` of a `read` projection borrows what it yields ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)).

Where the stored and the computed forms would differ, the stored form is a compile error:

```swift
extension Enemy { var isDead: Bool { hp <= 0 } }   // computed

func hit(_ e: mutable Enemy, _ d: Float) {
    let before = e.hp
    e.hp -= d                      // error: 'before' still names e.hp
    let dead = e.isDead            // computed: the Bool it returned, which 'dead' owns
    save(dead)                     // fine: save takes an owned parameter
    save(before)                   // error: 'before' names e.hp, which isn't this code's
}
```

### How long a borrow lasts

**A borrow lasts until its last use, not to the end of the scope.** Once `boss` above is last used, `enemies` is free again. Where destroying the value that holds the borrow is a use ([02](02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it)), that destruction is its last use.

**A `let` of a dynamic place holds its access until its last use.** A dynamic place is one reached through a thread-bound object's owner or weak pointer, or a thread-local, and the `let` holds that dynamic access (rule 6 in [02](02-views-and-dependencies.md#rule-6-dynamic-accesses)). So a call in between that changes the object panics.

### Conditions and patterns

**Conditions and patterns bind as bindings do**, and `guard` and `while` work the same way as `if`:

```swift
if let e = world.enemies[h] { ... }        // looks at the enemy in place
if var e = &world.enemies[h] { ... }       // changes it in place
if let v = pool.take(h) { ... }            // owns the value that take moved out
```

**`if let x` is short for `if let x = x`, and `guard let x` for `guard let x = x`.** `while` has no short form, since the unwrapped `x` would shadow the optional for the whole body, which then couldn't change it to end the loop. `var` has none either, since its `&` must be written.

**In a `when`, each part of a pattern binds as a binding does:**

- **A `let` part looks at what it matches, and a `var` part changes it in place.** For a `var` part, the subject is marked `&`, as in the example below.
- **An `owned` part takes what it matches out of a subject the code owns.** It moves as a field is moved out ([below](#what-can-be-moved-from)): only when no type on the path to it declares a `deinit`, except in that type's own `deinit`, since a `deinit` takes the whole value. It also moves only once its arm is chosen, since patterns and guards run under a borrow of the subject until then ([04](04-types.md#matching-with-when-and-choosing-with-if)).
- **When the subject is a value, every part owns what it matches.**
- **A `deinit` on the path keeps a value subject whole.** This holds in an arm where any of its patterns has, on the path to a part, a type that declares a `deinit`, whichever pattern matched. The value stays whole in a hidden local until the arm ends, as a `for` loop's sequence does. The arm's `let` parts look at it, and its `var` parts change it in place, so the `deinit` runs on the changed value, and nothing moves out of it. The subject still takes no `&`, since the hidden local is the arm's own.
- **A subject in a temporary's own storage that can't be moved out is kept whole the same way**, with the whole temporary in that hidden local, as `connect().state` is where `Conn` declares a `deinit`.

```swift
when &shape {
    .circle(var r) -> r *= 2       // a var part: doubles the radius inside 'shape'
    else -> {}
}
```

**`if case`, `guard case` and `while case` bind the same way**, with the value after `=` as the subject. A `guard`'s hidden local lives to the end of the enclosing scope, as the names it binds do.

**`for` patterns bind elements in place**, and own what the iterator hands out as a value of its own, such as a `Range`'s `Int` ([04](04-types.md#iteration)).

### `if` and `when` as values

**An `if` or `when` expression hands its position to the arm that runs.** Whatever the position does with a value, it does with the arm's last expression, as if that expression stood there: borrows it, lends it for change, moves it or returns it. An `unsafe` block used as an expression hands its position to its last expression the same way ([10](10-errors-and-safety.md#unsafe-code)).

```swift
let e = if first { enemies[0] } else { enemies[1] }   // borrows one of the two
var t = if left { &a } else { &b }                    // lends one for change
owned let v = if c { p } else { q }                   // moves from the one chosen
```

What depends on `e` depends on both places ([02](02-views-and-dependencies.md#dependencies)). `v` moves from the one chosen, so each of `p` and `q` is moved only on its own path ([below](#moving-values-out)).

**When some arms name places and others give values, each value is kept in a hidden local:**

```swift
let e = if c { enemies[0] } else { makeEnemy() }      // the new enemy is kept in a hidden local
```

The hidden local is declared where the binding is, and destroyed with it if its arm ran. The binding is then a binding of a place, which can't be consumed. What depends on it depends on every arm's place, and on those hidden locals.

### Conversions

**A converted value is a new value.** When a binding's declared type differs from its initializer's, the conversion says what it does with a place ([05](05-protocols-generics-and-closures.md#implicit-conversions)):

- **A numeric widening reads the place** and makes a new value, which the binding owns.
- **These conversions take the value**, so from a place, each is written as a move, with `owned` or `consume`, or as a copy of a copyable value:
    - wrapping it in an optional or an error union;
    - making a `Box<T>` or an object pointer into one of an existential;
    - moving a closure into a `Closure`.
- **Making an `any P` from a place borrows the place shared**, and the binding, `let` or `var`, owns the view. So a `var` of one may later point at another value. `&place` makes a `mutable any P` instead ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)).

```swift
let total: Int = n                          // 'n' is an Int32: the widened Int is a new value 'total' owns
var spare: Handle<Enemy>? = copy h          // wrapping a copy of the handle
owned var target: Handle<Enemy>? = h        // or wrapping the handle itself, moved out of 'h'
var d: any Drawable = sprite                // borrows 'sprite'; 'd' owns the view, and may later view another value
```

### Changeable places

**Only a changeable place can be changed, or lent with `&`**, so a shared borrow never becomes a write. A place is **changeable** when it is:

- a `var` that owns its value;
- a temporary, which its statement owns ([02](02-views-and-dependencies.md#temporaries));
- the place that a `var` given `&place` names, through that binding;
- a `mutable` or `owned` parameter, or `self` in a `mutating` or `consuming` method, a `deinit` or an initializer;
- an owned capture of a `mutating` or `consuming` closure;
- a `var` field, an element, a `modify` projection ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)), or a property or subscript with a `set` ([02](02-views-and-dependencies.md#get-and-set-accessors)), of a changeable place.

**Everything else is read-only, and so is whatever is reached through it**: a `let`, owning or borrowing, a borrowed parameter, `self` in a plain method, a `let` field, a `const` and a global `let`.

```swift
let x = makeEnemy()
var y = &x                         // error: a let is read-only, even one that owns its value
heal(&x)                           // error: the same
```

**There are four exceptions, each with its own way of keeping exclusivity**, the first two checked at run time:

- **A `@threadlocal var`**, which its own thread changes under a dynamic mark on each access ([07](07-concurrency.md#global-state)).
- **An object's value**, which is changeable whatever holds its owner or weak pointer, since each access takes a dynamic mark ([03](03-handles-and-objects.md#dynamic-exclusivity)).
- **A `Synchronized` value**, whose non-`mutating` methods change it through its own synchronization ([07](07-concurrency.md#the-synchronized-contract)).
- **`unsafe` code**, which may change a bare global `var` or an imported C variable ([07](07-concurrency.md#global-state)), and the memory a raw pointer points at, whatever holds the pointer ([10](10-errors-and-safety.md#raw-accesses)). It promises to keep exclusivity itself ([10](10-errors-and-safety.md#what-unsafe-code-upholds)).

```swift
let r = renderer.weak()
r.value?.submit(mesh)              // fine: an object's value is changeable through a let of a weak pointer
```

### Lending a place for change

**`&` marks every place lent for change, in a binding as in a call.** The receiver of a `mutating` method call is the exception, since the call's form shows it. These places take `&`, each lent to code that may change it:

- a `mutable` argument;
- the right side of a `var`, `if var`, `guard var` or `while var` that binds a place, or of a pattern with a `var` part bound to a place;
- the target of a `rebind` of a `var` ([02](02-views-and-dependencies.md#pointing-a-name-at-another-place-rebind));
- a loop's sequence whose elements the loop changes, which may be a temporary the loop keeps in a hidden local ([04](04-types.md#iteration));
- a `when` subject that is a place, or a `case` condition's value that is one, with a `var` part;
- the last expression of an `if` or `when` arm whose position lends a place for change;
- a place holding a `mutating` closure, a `Closure<mutating …>` or a `mutating` function value, made into a new function value ([05](05-protocols-generics-and-closures.md#implicit-conversions));
- a place that a `modify` projection's `yield` lends ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors));
- a place made into a `mutable any P`, or holding one that lends a new view of its value ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)).

```swift
for (i, var e) in &makeEnemies().enumerated() { ... }   // the loop keeps the new list in a hidden local, and changes it
var t = if left { &a } else { &b }                       // the arm's place is lent for change
var v: mutable any Damageable = &boss                    // a mutable any P made from 'boss'
```

**What follows `&` is a changeable place, or a member of one that has a mutable form.** Leaving `&` out is a compile error, and so is `&` on something that lends nothing for change.

- **`&` picks a mutable form.** Where a method or property has a shared and a mutable form of one name, the operand of `&` picks the mutable one ([04](04-types.md#shared-mutable-and-consuming-forms-of-one-method)). So a binding of `&particles.life` binds an [`SoA`](04-types.md#struct-of-arrays-soat) column as a `MutableSpan<Float>` that it owns, where a binding of `particles.life` gets a `Span<Float>`, as in the example below.
- **A binding of a value lends nothing, so it takes no `&`.** A call result bound to a name is owned by its binding. That includes an **owned exclusive view**: a move-only scoped value ([02](02-views-and-dependencies.md#scoped-values)), such as the guard that `registry.lock()` returns, which changes the registry through it.
- **A call result lent for change takes `&`, as any changeable place does**, when it is a `mutable` argument or a loop's sequence. It is a temporary, which its statement owns, or which the loop owns, for a sequence, as in the example below.
- **A `zip` marks its own arguments**, as in `zip(&vels, forces)`, so a loop over it needs no `&` of its own ([04](04-types.md#iteration)).

```swift
var lives = &particles.life        // the mutable form: a MutableSpan<Float> that 'lives' owns
let ages = particles.life          // the shared form: a Span<Float>
var g = registry.lock()            // no '&': 'g' owns the guard, and changes the registry through it
heal(&makeEnemy())                 // the statement owns the new enemy, and destroys it after the call
```

## Moving values out

**These take a value, and so move it** ([above](#moves)). Each hands the value to a new owner:

- an assignment, `return`, `throw` and `await`;
- an `owned` argument, and a `consuming` method's receiver ([above](#parameters));
- an `owned` binding ([above](#bindings));
- a `[move x]` capture ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref));
- a global's initializer;
- the elements of a tuple or array literal, and an enum case's payload.

A copyable `const` is the exception: taking one makes a new value ([below](#constants)). A `let` of a place, or a `var` of `&place`, borrows the place instead ([above](#bindings)).

**`consume place` writes a move as an expression.** Moving a place's value out, implicitly or this way, is **consuming** the place. `consume` also moves where the code would otherwise borrow: in `f(consume x)` for a borrowed parameter, the moved value is a temporary, destroyed at the end of the statement.

```swift
var loot = List<Item>()
give(loot)                            // fine: 'loot' is a local that owns its list
var spare = List<Item>()
show(consume spare)                   // 'show' only borrows; 'consume' moves 'spare' out, destroyed after the statement
give(player.inventory)                // error if 'player' is a mutable parameter: the caller still owns it
let old = replace(&player.inventory, with: List())    // the way to take it: leave a value behind
```

### What can be moved from

**Only code that owns a place may move from it, implicitly or with `consume`**, and only while no borrow of it is live and no scoped value depends on it, since a move is a mutable access ([below](#the-law-of-exclusivity)). These places can be moved from:

- a local that owns its value: a `let` or `var` bound to a value, including an owned exclusive view such as an `SoA` column bound with `&` ([above](#lending-a-place-for-change)), or one declared `owned`;
- an `owned` parameter, including a function-typed one received owned, and an owned capture inside a `consuming` closure;
- a temporary, such as a call result passed to an `owned` parameter;
- a field of one of those, through stored fields only, named or reached by reflection ([09](09-compile-time.md#what-reflection-can-read)), when no type along the path declares a `deinit`, since a `deinit` takes the whole value;
- a stored field of `self`, or a part of an enum `self`'s payload through an `owned` pattern, in that type's own `deinit`;
- the same, in a `consuming` method declared in the type's own module, when every path that moves one out then reaches `discard self` (below).

**The condition on a field covers a temporary's fields and an enum's payload**, and a pattern takes an enum's payload under the same condition ([above](#conditions-and-patterns)):

```swift
take(makeHolder().items)        // moves 'items' out of the temporary: an error when makeHolder()'s type has a deinit
```

These moves leave the rest of the value to be destroyed:

- **Moving a field out of a temporary**, as above, destroys the other fields at the end of the statement.
- **A `deinit` that consumes some fields and parts leaves the rest to be destroyed after it**, last declared first.
- **`discard self` ends `self` without its `deinit`**, destroying the fields and parts it hasn't consumed, last declared first. So a `consuming` method can end its value without running the `deinit`, as the two below do.

```swift
extension File {
    consuming func close() throws(IoError) { … }   // File's deinit closes it: this closes it, then 'discard self', so it closes once
}
extension Bag {
    consuming func intoItems() -> List<T> { … }    // Bag has a deinit: this moves 'items' out, then 'discard self'
}
```

**After a field is consumed, the whole value can't be used or passed until the field is assigned again.** If the scope ends first, the fields still held are destroyed one by one, last declared first.

**Only a place that holds the rest of its value has a field assigned.** A place that holds no value, or maybe holds one, is given a whole value, made by an initializer, so no value is ever half-built ([04](04-types.md#initializers)).

**Nothing else can be consumed.** So none of these can:

- a global, `const`s included;
- a `let` or `var` bound to a place;
- a borrowed or `mutable` parameter;
- an owned capture outside a `consuming` closure, since only a `consuming` closure runs at most once ([05](05-protocols-generics-and-closures.md#closure-kinds));
- a collection's element;
- a place reached through a weak pointer, an accessor or a subscript.

**The alternatives leave a value in the place:**

- `copy place` and `place.clone()` leave it as it was;
- through an exclusive view, `replace(&place, with: new)`, `swap(&a, &b)` or a type's own `take()`, such as `Optional.take()` and `List.take()`, leave a value behind.

So such a place always holds a value, across a `throw`, an early return and an `await` too. A caller, an alias or a later `deinit` that reaches it finds one there.

### Constants

**A `const` that reaches run time is a place in read-only data that lives as long as the program** ([09](09-compile-time.md#consts-that-reach-run-time)). A view of it is static storage, which any function may return.

**A `const` of a copyable type is taken without `copy`**, as a new value each time. So a `var` bound to one gets a new value. A `let` of one still borrows it. A `const` of a move-only type can only be borrowed or cloned.

```swift
const maxLives = 3

var lives = maxLives               // a new Int, with no 'copy' written
let cap = maxLives                 // borrows the const
```

**A static stored member is a global or a `const` in its type's namespace**, and is taken as either is. So `Vec3.zero`, whether a copyable `static const` or a computed property, is taken with no `copy`, as in `Enemy(pos: .zero, hp: 100)`.

### Places that hold no value

**A binding declared without a value holds none until it is assigned.** A `let` is assigned at most once on each path.

```swift
let lo: Float, hi: Float           // no values yet
lo = 0                             // each let is assigned once
hi = 1
```

**A place that holds a value on only some paths is maybe-initialized where the paths join.** A **maybe-initialized** place can't be used until it is assigned again, which the compiler proves statically.

**At scope end, and when a new value is assigned, the old value is destroyed exactly when there is one.** A partly moved value is tracked per field.

**A closure that captures a place exclusively may give it its value**, when the place holds no value, or maybe holds one, and the closure's body assigns it before any other use on every path.

- **The capture carries whether the place holds a value.** An assignment destroys an old value only if there is one. So a `mutating` closure called twice destroys the first value when it assigns the second.
- **A `let` is given its value this way only by a `consuming` closure**, which runs at most once.
- **After the closure's last use, the place is maybe-initialized** in the enclosing function, since the closure may never have been called.

## The law of exclusivity

```swift
for (h, var e) in &world.enemies.entries {
    if e.hp <= 0 {
        world.enemies.remove(h)            // error: 'world.enemies' is mutably borrowed by the loop
    }
}
```

**While a mutable borrow of a place is live, no other access to an overlapping place may happen. While a shared borrow is live, no mutable access may happen.** Moving from a place, assigning it and destroying it are mutable accesses to it, so an owner can't release or replace what a live borrow reaches.

Without the law, a change could destroy or move what a borrow still uses. In the loop above, `remove` would destroy the enemy that `e` lends, and may move the pool's last enemy into its slot ([03](03-handles-and-objects.md#pools-and-handles)).

The compiler checks this one function at a time, from its body and the signatures of the functions it calls: a borrow never outlives the function that makes it, except as that function's signature says. So one body holds every borrow the check must see, and the check is **static, in every build, at no run-time cost**. Changing another field during the loop is allowed:

```swift
for (h, e) in world.enemies.entries {
    if e.hp <= 0 { world.commands.append(.despawn(h)) }  // a different field: allowed
}
world.apply(world.commands.take())                       // take() moves the contents out, leaving it empty
```

### State that other code can change

**Only these let other code change a value between two of your uses**, and each says so in its type or declaration:

- **Objects.** Code changes an object through its owner or any of its weak pointers, which are aliases the static checker can't see. So each access takes a mark, and a conflicting one panics ([03](03-handles-and-objects.md#dynamic-exclusivity)).
- **Thread-locals.** A thread-local is declared `@threadlocal`, and the static checker can't see a callee touching one, so its accesses are marked the same way ([07](07-concurrency.md#global-state)).
- **`Synchronized` values.** A value such as a `Mutex` changes only through its own synchronization ([07](07-concurrency.md#atomics-and-locks)). A `Slice` into a locked buffer takes the buffer's lock ([06](06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers)).
- **Channel ends.** A channel's two ends share one queue, which each end changes ([07](07-concurrency.md#queues-and-channels)).
- **Pool elements.** A pool's element, named by a `Handle`, reads `nil` once the element is removed ([03](03-handles-and-objects.md#pools-and-handles)).
- **Pinned elements.** C may hold a pinned element's address ([03](03-handles-and-objects.md#pinning-for-c)).
- **Unsafe code.** In `unsafe` code, raw pointers, bare global `var`s and imported C variables let other code change a value, and nothing checks them.

### Which places overlap

The law of exclusivity governs accesses to overlapping places, so which places overlap decides which accesses conflict.

**Places overlap by path**: `world` and `world.enemies` overlap, since one contains the other.

- **Stored fields of one value are disjoint from each other**, since they occupy distinct bytes, and so are reflection projections of distinct stored fields, such as `value[f1]` and `value[f2]` ([09](09-compile-time.md#what-reflection-can-read)). Two projections whose fields may be one overlap where the borrows are checked, as two that `Row.field(ofType:)` picks may in code generic over `Row`. `value[fields: (f1, f2)]` projects both at once, and is checked distinct at instantiation ([09](09-compile-time.md#tuples-field-lists-and-queries)).
- **Inline array elements at indices known to differ where the borrows are checked are disjoint.** Any other two overlap, since `a[i]` and `a[j]` may be the same element. So may `a[I]` and `a[J]`, for value parameters `I` and `J` of a body checked once for all its instantiations ([05](05-protocols-generics-and-closures.md#protocols-and-generics)). A collection's elements are reached through its subscript, which is an accessor (next).
- **A user-declared computed property or subscript accessor is an access to all of `self`**, whatever it yields, since its body may reach any of it. So two `&` bindings of two computed properties of `world` conflict, as in the example below. An imported bitfield's generated accessors are the exception: each accesses only its C memory location (below), as a reflection projection of the bitfield does.

```swift
var p = &world.physics             // when 'physics' and 'render' are computed properties,
var r = &world.render              // error: each is an access to all of 'world', and 'p' is used below
p.step(dt)
```

**These places count as one place, since writing one can change another:**

- **Unions.** The members of one union, declared `union` or `@c union` or anonymous inside a struct ([04](04-types.md#untagged-unions), [08](08-c-interop.md#structs-unions-and-enums)), and the fields nested at any depth inside them. Every rule that relies on disjoint fields treats a union this way, reflection projections and SoA splitting included.
- **Vector lanes.** The lanes of one `Simd` value ([04](04-types.md#simd-and-math)), since storing one lane may rewrite the vector. A swizzle accesses the whole vector. `Vec3`'s `x`, `y` and `z` are ordinary stored fields, which are disjoint, and its swizzles are computed properties, which access all of it (above).
- **Enum payloads.** Reaching into a payload, an optional's included, reads the tag, which may be a niche inside the payload ([04](04-types.md#optionals)). So every path into one enum value's payload overlaps every other, through `?.`, `!`, a pattern or reflection's `value[case:]` ([09](09-compile-time.md#what-reflection-can-read)): `s?.n` and `s?.b` conflict. One pattern that binds several parts reads the tag once, though, so one over an optional tuple gives two disjoint borrows, as in the example below.
- **Bitfields.** Imported bitfields that form one C **memory location** ([08](08-c-interop.md#structs-unions-and-enums)). Bitfields in different memory locations, or a bitfield and a neighboring field, are separate places, which two threads may write at once, as C11 allows.

```swift
g(&e.f, &e.u)                            // error when 'f' and 'u' are members of one union
join({ e.f = 1 }, { use(e.u) })          // error: the same
join({ v.x = x }, { v.y = y })           // error for a Simd 'v': each closure accesses the whole vector
if var (first, second) = &pair { ... }   // fine for an optional tuple 'pair': two disjoint borrows
```

```c
struct { uint32_t a : 20; uint32_t b : 20; };  // 'a' and 'b' are one place, though they lie in two storage units
```

### Two elements of one collection

**Two elements at once need an API that checks at run time that they are distinct:**

```swift
if var (a, b) = &world.enemies[h1, h2] {     // nil if h1 == h2 or either is stale
    swap(&a.hp, &b.hp)
}
if var (a, b) = &verts[i, j] { ... }         // lists too: nil if i == j; out of bounds still panics
list.swapAt(i, j)
var (left, right) = list.split(at: mid)        // two disjoint MutableSpans, both depending on list
```

