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

**A second value exists only where the code asks for one**: with `copy` or `clone()`, by taking a copyable `const` ([below](#moving-values-out)), or through an operation that copies its operands ([below](#operations-that-copy)).

## Tiers of checking

**Each pattern is checked in the cheapest tier that can check it.** A pattern the static checker can't prove is checked at run time, in the dynamic tier. It is never forbidden for that reason, and never forced into `unsafe`.

| Tier | Mechanisms | Checked | Cost |
| --- | --- | --- | --- |
| **Static** | Values, moves, borrows (bindings and parameters), scoped values, dependencies, `rebind` | By the compiler, inside one function body | Zero |
| **Dynamic** | `Handle<T>` into pools; `UniquePointer<T>` + `WeakPointer<T>` for objects; `WeakShared<T>` links to reference-counted values; `Slice<T>` of a buffer; thread-local `var`s; the locks of `Synchronized` types ([07](07-concurrency.md#atomics-and-locks)); an owning value's allocator word ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)) | At each use: a stale link reads `nil` or panics instead of dangling, and conflicting uses panic or wait instead of racing | A check per use, visible in the type, or for a thread-local in its `@threadlocal` declaration |
| **Unsafe** | `*T` raw pointers and raw memory, calls into C, `unchecked`, and the other operations [10](10-errors-and-safety.md#unsafe-code) lists | Not checked | Zero |

**Safe code** is the code of the first two tiers: everything outside `unsafe` code, `unchecked` blocks and C. It has no undefined behavior ([11](11-compilation-model.md#what-the-language-leaves-open)).

## Moves

```swift
var cmds = CommandList()
cmds.draw(mesh)
submit(cmds)                      // submit keeps the list: it moves out of 'cmds'
print(cmds.count)                 // error: 'cmds' was moved
cmds = CommandList()              // fine: a new value makes 'cmds' usable again
```

**Assigning a value, returning it or passing it to a function that keeps it moves it.** The new owner takes it over, and the place it came from can't be used until it gets a new value. Only a place the code owns can be moved from: moving out of a value the code only borrows is a compile error.

**A move changes the owner and nothing else.** It runs none of the program's code, allocates nothing, and copies at most the value's bytes, into the place that takes it.

[Moving values out](#moving-values-out) lists every construct that moves a value, and every place that can be moved from.

## Copies

```swift
var spawn = copy e.pos            // copy: Vec3 is copyable, so this is a memcpy
spawn.y += 2                      // e.pos is unchanged
var loadout = player.items.clone()   // clone: List owns heap memory, so this allocates
var a = copy player.items         // error: 'List<Item>' is not copyable
```

**Copies are written out.** `copy x` is a `memcpy` of a copyable value's bytes, and never allocates. A move-only value is copied with a named call, `x.clone()`, which allocates.

A type is **copyable** when:

- all its fields and enum payloads are copyable;
- it declares no `deinit`;
- it doesn't opt out with `~Copyable`;
- its kind doesn't make it move-only (below).

A copyable type can't own heap memory, which is why `copy` never allocates. Copyable types conform to the derived marker protocol **`Copyable`**. Listing it, as `struct Handle<T>(…): Copyable` does, asks the compiler to confirm it.

Every other type is **move-only**: one that declares a `deinit`, has a move-only field or payload, or lists **`~Copyable`**, as `struct MutableSpan<Element>(…): Scoped, ~Copyable` does. So is a type whose kind makes it move-only:

- a `Synchronized` or `@guard` type ([07](07-concurrency.md#the-synchronized-contract), [02](02-views-and-dependencies.md#lock-guards-are-released-on-the-thread-that-took-them));
- a `mutating` or `consuming` function value ([05](05-protocols-generics-and-closures.md#closure-kinds));
- a `consuming` closure literal's type, or one with an exclusive or move-only capture ([05](05-protocols-generics-and-closures.md#closures-by-concrete-type-some-f));
- a `Closure<F>` ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref));
- a `mutable any P` ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch));
- an exclusive `SoA` row ([04](04-types.md#struct-of-arrays-soat));
- a task's state ([07](07-concurrency.md#semantics)).

Every type that owns memory, such as `List`, `String`, `Box` or `Pool`, is move-only, so copying heap data always takes a named call that allocates: `a.clone()`. Generic code treats an unconstrained type parameter as possibly move-only, so copying a `T` requires `T: Copyable`.

### Operations that copy

Besides `copy`, `clone()` and taking a copyable `const`, these operations copy their copyable operands:

- a range operator ([05](05-protocols-generics-and-closures.md#operators));
- a `Simd` initializer or lane read ([04](04-types.md#simd-and-math));
- an inline array's `.init(repeating:)` ([04](04-types.md#tuples-ranges-and-arrays));
- `using allocator = a`, which reads the id in `a` ([06](06-memory-and-allocators.md#the-current-allocator));
- a widening conversion ([below](#conversions));
- an `as` pattern on a place ([04](04-types.md#matching-with-when-and-choosing-with-if));
- a change through a `get` and `set` pair, which copies a copyable `owned` subscript argument for the `get` ([02](02-views-and-dependencies.md#get-and-set-accessors)).

One copy is deferred: a `String` made from a literal uses the literal's bytes until its first write or growth, and copies them then ([04](04-types.md#literals)).

## Destruction

**A value is destroyed when its owner's scope ends or when it is overwritten**, and its type's `deinit` runs then. Destruction runs in reverse order:

- a scope's locals, last declared first;
- a statement's temporaries, last made first;
- a value's parts: its own `deinit` runs first, then its fields are destroyed, last declared first. An enum payload's parts, an inline array's elements and a tuple's elements are destroyed last first.

Some values that the code doesn't declare still count as locals, and take their place in that order:

- **Parameters.** A function's `owned` parameters and a `consuming` method's `self` count as locals of its body declared before the others: `self` first, then the parameters in order.
- **Hidden locals.** A **hidden local** is one the language declares to keep a value that a statement can't name, such as a `when` subject ([below](#conditions-and-patterns)) or a loop's sequence ([04](04-types.md#iteration)):
    - a closure literal's counts as declared just before the local it was made for, in the order the literals are made ([05](05-protocols-generics-and-closures.md#function-typed-values));
    - a `rebind`'s counts as the binding whose value it took ([02](02-views-and-dependencies.md#pointing-a-name-at-another-place-rebind));
    - those of a `guard`, a `when` arm, an `if case`, a `while case` and a `for` loop count as declared where the statement stands: a loop's sequence temporaries in evaluation order, then its iterator ([04](04-types.md#iteration)).
- **`defer`.** A `defer` block runs as a value declared where it stands would be destroyed ([10](10-errors-and-safety.md#cleanup)).

Where destroying a value uses what it borrows ([02](02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it)), that use is checked in this order. So a lock guard declared after its mutex is released before the mutex is destroyed.

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
- **Methods use the same conventions for `self`.** A plain `func` borrows it, a `mutating func` takes it `mutable`, and a `consuming func` takes it `owned`. A struct's primary initializer takes its fields `owned` ([04](04-types.md#initializers)), so `World(enemies: enemies)` moves `enemies` in.
- **Conventions line up across an indirection.** A protocol witness, a function converted to a function type, and a function type converted to another declare each parameter, and `self`, with the convention of what they stand for ([05](05-protocols-generics-and-closures.md#implicit-conversions)).
- **A `mutable` argument's changes always reach the caller's place**, even when it is lent through a temporary that is written back, as a bitfield or an under-aligned field is ([04](04-types.md#packed-structs-and-under-aligned-places)).

**Some parameters are received `owned` with no `owned` written**, unless they are declared `mutable`:

- a parameter of a `mutating` or `consuming` function type, or of a type parameter constrained to one, written `some F` or named, since a borrowed one could never be called ([05](05-protocols-generics-and-closures.md#closure-kinds));
- a `mutable any P`, which is a view of its own ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)).

### Default arguments

**A default value makes an argument optional.** With `func spawn(_ kind: Kind, at pos: Vec3 = .zero)`, a call may leave out `at:`.

- **The default is checked where it is declared**, as the body of a function with no parameters that returns the parameter's type and doesn't throw. So it names no other parameter and no `self`, and a view it returns views only static storage ([02](02-views-and-dependencies.md#dependencies)).
- **A call that leaves the argument out calls that function** in the argument's position, as part of the call's own statement ([below](#evaluation-order-and-when-a-calls-borrows-begin)).
- **A `mutable` parameter has no default**, since it stands for a place of the caller's.
- **A field's default works the same way** in the primary initializer ([04](04-types.md#initializers)).

### Borrowed arguments

**Safe code in the callee can't change, keep or take the address of a borrowed argument, and nothing else changes it before the call returns** ([below](#the-law-of-exclusivity)). The exception is a `Synchronized` value the argument holds, which changes through its own synchronization ([07](07-concurrency.md#the-synchronized-contract)).

**So the callee may see a copy of the argument's bits or the caller's place, and the compiler chooses.** The callee can't tell them apart. These borrowed arguments are always the caller's place:

- **A `Synchronized` value.** An argument that is or holds one at any depth, since such a value's identity is its address. A `Closure<F>` counts, since its captures may hold one ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref)).
- **The argument of `ptr(to:)`**, whose result is its address ([10](10-errors-and-safety.md#unsafe-code)).
- **An argument still viewed after the call.** The result, a thrown error, a storage projection's yield ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)) or an absorbing argument may view the argument's own storage. An absorbing argument is a `mutable` one, or an `owned` mutable view, such as a `MutableSpan` or a `mutating` closure (rule 4 in [02](02-views-and-dependencies.md#dependencies)).

[Rules 3 and 4](02-views-and-dependencies.md#dependencies), and an accessor's `where yield` clause, tell which arguments may still be viewed: they go by the signature's types, and by which arguments are [shallow](02-views-and-dependencies.md#dependencies). An `Int` or a `List<Int>` result views nothing.

**Which arguments are the caller's place follows from the signature alone**: the function called, its result and error types, its `where yield` clause, and each parameter's type and convention.

- **Adding `keep` to a parameter changes none of this** ([05](05-protocols-generics-and-closures.md#what-a-closure-may-keep-keep)).
- **A call through a function value passes its arguments as a direct call would**, since every function-type conversion keeps the conventions, and which arguments are places ([05](05-protocols-generics-and-closures.md#implicit-conversions)). `ptr(to:)` is never a function value ([10](10-errors-and-safety.md#unsafe-code)).

### Evaluation order, and when a call's borrows begin

```swift
items.append(items.count)     // fine: items.count is read, and done, before append borrows items
f(&x, x)                      // error: two borrows of x overlap for the whole call
```

**Evaluation is left to right, and a call's borrows begin with the call.** A call runs in this order:

1. **It evaluates its callee, then its receiver, then its arguments.** Evaluating a borrowed or `mutable` argument works out which place it names: its base first, then its indices, left to right. An `owned` argument or a `consuming` receiver that names a place is worked out the same way.
2. **Then the call begins.** Every borrow it passes begins, and lasts until the call returns, and every value it takes leaves its place. So `builder.finish(builder.count)` reads `count` before `finish` takes `builder`.
3. **As it begins, it runs the accessors those places reach**, in the order the places were worked out, receiver first. These are the `read` and `modify` projections, and the `get` of each `get` and `set` pair that the call lends for change ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)).
4. **When it returns, it ends those accesses in reverse order**, running the code after each `yield` and calling each `set`. An access-bound projection's access that the result still depends on is the exception: it ends at that value's last use ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)).

**Any other `get` runs as its argument or receiver is evaluated.** It makes a value, whatever the call then does with it: borrows it, changes it as a mutable form's view, takes it, or calls a method on it. Its result keeps what it depends on borrowed (rule 3 in [02](02-views-and-dependencies.md#dependencies)). So in `items.insert(x, at: items.count)`, `count`'s `get` has returned before `insert` borrows `items`.

**Working out a place never accesses it**, except for an optional chain (`?.`) or a force unwrap (`!`) in a borrowed or `mutable` argument. Unwrapping reads the optional, so the borrow up to that point begins there, and lasts until the call returns. So `damage(&world.enemies[h]!, by: reinforce(&world.enemies))` is a conflict.

**These keep the same left-to-right order:**

- operator operands, the elements of tuple and array literals, and the segments of an interpolated string;
- an assignment, which works out its left place, evaluates its right side, then writes;
- a compound assignment `a ⊕= b`, which works out `a`'s place once, evaluates `b`, then reads the place, applies `⊕` and writes the result back ([05](05-protocols-generics-and-closures.md#operators)).

**Some operands are skipped.** `&&`, `||` and `??` evaluate their right side only when the left doesn't decide. Optional chaining skips the rest of the chain at a `nil`, arguments included.

**An assignment through `?.`, `?` or `!` reads the optional only after evaluating its right side.** When the left side holds one, as in `pool[h]?.hp = 0` or `requests[h]? = v`, the assignment works out its left place up to the first of them. Then it evaluates its right side, and only then reads the optional and works out the rest. A compound assignment does the same. So `pool[a]?.hp = copy pool[b]!.hp` and `world.enemies[h]?.hp -= reinforce(&world.enemies)` compile, and when the chain stops at a `nil`, the right side's value is dropped.

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
| `owned let x = place`, `owned var x = place` | `_ x: owned T` | A **move** from a place the code owns ([below](#moving-values-out)): `place` can't be used until it gets a new value | A `memcpy` at most |
| `let x = copy place`, `var x = copy place` | | An independent **copy** of a copyable value; a move-only one is copied with `.clone()` | A `memcpy` |
| `let x = f()`, `var x = f()` | | The binding owns the value, even a move-only scoped value such as a `MutableSpan` or a lock guard ([02](02-views-and-dependencies.md#scoped-values)); `consume x` ends it early | None |
| `var x = place` | | A compile error, except for a `const` of a copyable type, which gives the `var` a new value ([below](#moving-values-out)) | |

- **A binding of anything that isn't a place owns it**, as a binding of a call's result does: a literal, an operator's result, `copy place` or `consume place`. On such a binding, `owned` changes nothing. A binding that owns its value can move it on, and a `let` still can't change it.
- **Views taken from a `let` of a place depend on the place itself** ([02](02-views-and-dependencies.md#dependencies)).
- **A place in a temporary's own storage dies with its statement**, such as `makeEnemy().pos`. So a `let` of one owns that value instead, moving it out as [Moving values out](#moving-values-out) allows. Where that can't move it, the binding is a compile error unless it is written with `copy` or `.clone()`.
- **A place that a `where yield outlives self` projection yields from a temporary lies outside the temporary**, such as `makeSpan()[0]`. So a `let` of one borrows it, depending on what the temporary carries ([02](02-views-and-dependencies.md#dependencies)).
- **Neither borrowing form may bind an under-aligned place**: that is a compile error ([04](04-types.md#packed-structs-and-under-aligned-places)).

### What a `let` of a place sees

**Changing a place while a `let` of it is used is a compile error.** For a place reached through an object or a thread-local, it is a panic instead ([below](#how-long-a-borrow-lasts)). A `Synchronized` value still changes through its own synchronization ([07](07-concurrency.md#the-synchronized-contract)).

**Making a field computed, or stored, never silently changes what a `let` of it sees.**

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

**A `let` of a dynamic place holds its access until its last use.** A dynamic place is one reached through a thread-bound object's owner or weak pointer, or a thread-local, and the `let` holds that dynamic access (rule 6 in [02](02-views-and-dependencies.md#dependencies)). So a call in between that changes the object panics.

### Conditions and patterns

**Conditions and patterns bind as bindings do.** `if let e = world.enemies[h]` looks, `if var e = &world.enemies[h]` changes in place, and `if let v = pool.take(h)` owns the value it moves out. `guard` and `while` work the same way.

**`if let x` is short for `if let x = x`, and `guard let x` for `guard let x = x`.** `while` has no short form, since the unwrapped `x` would shadow the optional for the whole body, which then couldn't change it to end the loop. `var` has none either, since its `&` must be written.

**In a `when`, each part of a pattern binds as a binding does:**

- **A `let` part looks at what it matches, and a `var` part changes it in place.** For a `var` part, the subject is marked `&`: `when &shape { .circle(var r) -> r *= 2; else -> {} }`.
- **An `owned` part takes what it matches out of a subject the code owns.** It moves as a field is moved out ([below](#moving-values-out)): only when no type on the path to it declares a `deinit`, except in that type's own `deinit`, and only once its arm is chosen.
- **When the subject is a value, every part owns what it matches.**
- **A `deinit` on the path keeps a value subject whole.** This holds in an arm where any of its patterns has, on the path to a part, a type that declares a `deinit`, whichever pattern matched. The value stays whole in a hidden local until the arm ends, as a `for` loop's sequence does. The arm's `let` parts look at it, and its `var` parts change it in place, so the `deinit` runs on the changed value, and nothing moves out of it. The subject still takes no `&`, since the hidden local is the arm's own.
- **A subject in a temporary's own storage that can't be moved out is kept whole the same way**, with the whole temporary in that hidden local, as `connect().state` is where `Conn` declares a `deinit`.

**`if case`, `guard case` and `while case` bind the same way**, with the value after `=` as the subject. A `guard`'s hidden local lives to the end of the enclosing scope, as the names it binds do.

**`for` patterns bind elements in place**, and own what the iterator hands out as a value of its own, such as a `Range`'s `Int` ([04](04-types.md#iteration)).

### `if` and `when` as values

**An `if` or `when` expression hands its position to the arm that runs.** Whatever the position does with a value, it does with the arm's last expression, as if that expression stood there: borrows it, lends it for change, moves it or returns it. An `unsafe` block used as an expression hands its position to its last expression the same way ([10](10-errors-and-safety.md#unsafe-code)).

- `let e = if first { enemies[0] } else { enemies[1] }` borrows one of the two, and what depends on `e` depends on both ([02](02-views-and-dependencies.md#dependencies)).
- `var t = if left { &a } else { &b }` lends one for change.
- `owned let v = if c { p } else { q }` moves from the one chosen, so each is moved only on its own path ([below](#moving-values-out)).

**When some arms name places and others give values, each value is kept in a hidden local**, as in `let e = if c { enemies[0] } else { makeEnemy() }`. The hidden local is declared where the binding is, and destroyed with it if its arm ran. The binding is then a binding of a place, which can't be consumed. What depends on it depends on every arm's place, and on those hidden locals.

### Conversions

**A converted value is a new value.** When a binding's declared type differs from its initializer's, the conversion says what it does with a place ([05](05-protocols-generics-and-closures.md#implicit-conversions)):

- **A numeric widening reads the place** and makes a new value, so `let total: Int = n` owns its value.
- **These conversions take the value:** wrapping it in an optional or an error union, making a `Box<T>` or an object pointer into one of an existential, and moving a closure into a `Closure`. So from a place, each is written as a move, with `owned` or `consume`, or as a copy of a copyable value: `owned var target: Handle<Enemy>? = h`, or `var target: Handle<Enemy>? = copy h`.
- **Making an `any P` from a place borrows the place shared**, and the binding, `let` or `var`, owns the view. So `var d: any Drawable = sprite` may later point at another value. `&place` makes a `mutable any P` instead ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)).

### Changeable places

**Only a changeable place can be changed, or lent with `&`.** A place is **changeable** when it is:

- a `var` that owns its value;
- a temporary, which its statement owns ([02](02-views-and-dependencies.md#dependencies));
- the place that a `var` given `&place` names, through that binding;
- a `mutable` or `owned` parameter, or `self` in a `mutating` or `consuming` method, a `deinit` or an initializer;
- an owned capture of a `mutating` or `consuming` closure;
- a `var` field, an element, a `modify` projection ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)), or a property or subscript with a `set` ([02](02-views-and-dependencies.md#get-and-set-accessors)), of a changeable place.

**Everything else is read-only, and so is whatever is reached through it**: a `let`, owning or borrowing, a borrowed parameter, `self` in a plain method, a `let` field, a `const` and a global `let`. So `let x = makeEnemy(); var y = &x` is rejected, as `heal(&x)` is.

**There are four exceptions**, the first two checked at run time:

- **A `@threadlocal var`**, which its own thread changes under a dynamic mark on each access ([07](07-concurrency.md#global-state)).
- **An object's value**, which is changeable whatever holds its owner or weak pointer, since each access takes a dynamic mark ([03](03-handles-and-objects.md#dynamic-exclusivity)). So `let r = renderer.weak(); r.value?.submit(mesh)` is fine.
- **A `Synchronized` value**, whose non-`mutating` methods change it through its own synchronization ([07](07-concurrency.md#the-synchronized-contract)).
- **`unsafe` code**, which may change a bare global `var` or an imported C variable ([07](07-concurrency.md#global-state)), and the memory a raw pointer points at, whatever holds the pointer ([10](10-errors-and-safety.md#unsafe-code)).

### Lending a place for change

**`&` marks every place lent for change, in a binding as in a call.** The receiver of a `mutating` method call is the exception, since the call's form shows it. These places take `&`:

- a `mutable` argument;
- the right side of a `var`, `if var`, `guard var` or `while var` that binds a place, or of a pattern with a `var` part bound to a place;
- the target of a `rebind` of a `var` ([02](02-views-and-dependencies.md#pointing-a-name-at-another-place-rebind));
- a loop's sequence whose elements the loop changes, which may be a temporary the loop keeps in a hidden local ([04](04-types.md#iteration)), as in `for (i, var e) in &makeEnemies().enumerated()`;
- a `when` subject that is a place, or a `case` condition's value that is one, with a `var` part;
- the last expression of an `if` or `when` arm whose position lends a place for change, as in `var t = if left { &a } else { &b }`;
- a place holding a `mutating` closure, a `Closure<mutating …>` or a `mutating` function value, made into a new function value ([05](05-protocols-generics-and-closures.md#implicit-conversions));
- a place that a `modify` projection's `yield` lends ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors));
- a place made into a `mutable any P`, as in `var v: mutable any Damageable = &boss`, or holding one that lends a new view of its value ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)).

**What follows `&` is a changeable place, or a member of one that has a mutable form.** Leaving `&` out is a compile error, and so is `&` on something that lends nothing for change.

- **`&` picks a mutable form.** Where a method or property has a shared and a mutable form of one name, the operand of `&` picks the mutable one ([04](04-types.md#shared-mutable-and-consuming-forms-of-one-method)). So `var lives = &particles.life` binds an [`SoA`](04-types.md#struct-of-arrays-soat) column as a `MutableSpan<Float>` it owns, where `let lives = particles.life` gets a `Span<Float>`.
- **A binding of a value lends nothing, so it takes no `&`.** A call result bound to a name is owned by its binding. That includes an **owned exclusive view**: a move-only scoped value ([02](02-views-and-dependencies.md#scoped-values)), such as the guard in `var g = registry.lock()`, which changes the registry through it.
- **A call result lent for change takes `&`, as any changeable place does**, when it is a `mutable` argument or a loop's sequence. It is a temporary, which its statement owns, or which the loop owns, for a sequence. So `heal(&makeEnemy())` changes an enemy that the statement then destroys.
- **A `zip` marks its own arguments**: `for (var v, f) in zip(&vels, forces)`.

## Moving values out

**These take a value, and so move it** ([above](#moves)):

- an assignment, `return`, `throw` and `await`;
- an `owned` argument, and a `consuming` method's receiver ([above](#parameters));
- an `owned` binding ([above](#bindings));
- a `[move x]` capture ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref));
- a global's initializer;
- the elements of a tuple or array literal, and an enum case's payload.

A copyable `const` is the exception: taking one makes a new value (below). A `let` of a place, or a `var` of `&place`, borrows the place instead ([above](#bindings)).

`consume place` writes a move as an expression, and also moves where the code would otherwise borrow: in `f(consume x)` for a borrowed parameter, the moved value is a temporary destroyed at the end of the statement.

```swift
var loot = List<Item>()
give(loot)                            // fine: 'loot' is a local that owns its list
var spare = List<Item>()
show(consume spare)                   // 'show' only borrows; 'consume' moves 'spare' out, destroyed after the statement
give(player.inventory)                // error if 'player' is a mutable parameter: the caller still owns it
let old = replace(&player.inventory, with: List())    // the way to take it: leave a value behind
```

**Only code that owns a place may move from it**, implicitly or with `consume` (**consuming** the place), and only while no borrow of it is live and no scoped value depends on it. The places are:

- a local that owns its value: a `let` or `var` bound to a value, including an owned exclusive view such as `var lives = &particles.life`, or declared `owned`;
- an `owned` parameter, including a function-typed one received owned, and an owned capture inside a `consuming` closure;
- a temporary, such as a call result passed to an `owned` parameter;
- a field of one of those, through stored fields only, named or reached by reflection ([09](09-compile-time.md#what-reflection-can-read)), when no type along the path declares a `deinit`: `take(makeHolder().items)` moves `items` out, destroying the other fields at the end of the statement, and is an error when `makeHolder()`'s type has a `deinit`. A pattern takes an enum's payload under the same condition ([above](#conditions-and-patterns));
- a stored field of `self`, or a part of an enum `self`'s payload through an `owned` pattern, in that type's own `deinit`; the fields and parts it doesn't consume are destroyed after it, last-declared first;
- the same, in a `consuming` method declared in the type's own module, when every path that moves one out then reaches **`discard self`**. That statement ends `self` without its `deinit`, destroying the fields and parts it hasn't consumed, last-declared first, so `consuming func close() throws(IoError)` on a `File` whose `deinit` closes it closes the file once, and a wrapper's `consuming func intoItems() -> List<T>` hands its list out.

After a field is consumed, and until it is assigned again, the whole value can't be used or passed; if the scope ends first, the fields still held are destroyed one by one, last-declared first. Only a place that holds the rest of its value has a field assigned: one that holds no value, or maybe holds one, is given a whole value, made by an initializer ([04](04-types.md#initializers)).

**Nothing else can be consumed**: not a global, `const`s included, a `let` or `var` bound to a place, a borrowed or `mutable` parameter, an owned capture outside a `consuming` closure, a collection's element, or a place reached through a weak pointer, an accessor or a subscript. The alternatives are `copy place`, `place.clone()`, or, through an exclusive view, `replace(&place, with: new)`, `swap(&a, &b)`, or a type's own `take()`, such as `Optional.take()` and `List.take()`. So such a place always holds a value, across a `throw`, an early return and an `await` too.

**Constants.** A `const` is a place in read-only data that lives as long as the program, and a view of it is static storage, which any function may return ([09](09-compile-time.md#consts-that-reach-run-time)). **A `const` of a copyable type is taken without `copy`**, as a new value each time, and a `var` bound to one gets a new value (`var lives = maxLives`), while a `let` borrows it. A `const` of a move-only type can only be borrowed or cloned. A static stored member is a global or a `const` in its type's namespace, and is taken as either is: `Vec3.zero`, a copyable `static const` or a computed property, is taken with no `copy`, as in `Enemy(pos: .zero, hp: 100)`.

**A binding declared without a value**, as in `let lo: Float, hi: Float`, holds none until it is assigned, and a `let` is assigned at most once on each path. **A place that holds a value on only some paths** is **maybe-initialized** where the paths join, and can't be used until assigned again, which the compiler proves statically. At scope end, and when a new value is assigned, its old value is destroyed exactly when there is one, and a partly moved value is tracked per field.

**Giving a place its value in a closure.** A closure may assign a captured place that holds no value, or maybe holds one, when it captures the place exclusively and its body assigns it before any other use, on every path. The capture carries whether the place holds a value: an assignment destroys an old value only if there is one, so a `mutating` closure called twice destroys the first value when it assigns the second. A `let` is given its value this way only by a `consuming` closure, which runs at most once. After the closure's last use, the place is maybe-initialized in the enclosing function, since the closure may never have been called.

## The law of exclusivity

```swift
for (h, var e) in &world.enemies.entries {
    if e.hp <= 0 {
        world.enemies.remove(h)            // error: 'world.enemies' is mutably borrowed by the loop
    }
}
```

**While a mutable borrow of a place is live, no other access to an overlapping place may happen. While a shared borrow is live, no mutable access may happen.** Moving from a place, assigning it and destroying it are mutable accesses to it.

The compiler checks this one function at a time, from its body and the signatures of the functions it calls: a borrow never outlives the function that makes it, except as that function's signature says. The check is **static, in every build, at no run-time cost**. Changing another field during the loop is allowed:

```swift
for (h, e) in world.enemies.entries {
    if e.hp <= 0 { world.commands.append(.despawn(h)) }  // a different field: allowed
}
world.apply(world.commands.take())                       // take() moves the contents out, leaving it empty
```

### State that other code can change

**Only these let other code change a value between two of your uses**, and each says so in its type or declaration:

- an object, through its owner or any of its weak pointers. Each access takes a mark, and a conflicting one panics ([03](03-handles-and-objects.md#dynamic-exclusivity));
- a thread-local, declared `@threadlocal`, whose accesses are marked the same way ([07](07-concurrency.md#global-state));
- a `Synchronized` value, such as a `Mutex`, which changes only through its own synchronization ([07](07-concurrency.md#atomics-and-locks)). A `Slice` into a locked buffer takes the buffer's lock ([06](06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers));
- a channel's ends ([07](07-concurrency.md#queues-and-channels));
- a pool's element, named by a `Handle`, which reads `nil` once the element is removed ([03](03-handles-and-objects.md#pools-and-handles));
- a pinned element, whose address C may hold ([03](03-handles-and-objects.md#pinning-for-c));
- in `unsafe` code, raw pointers, bare global `var`s and imported C variables, which nothing checks.

### Which places overlap

Places overlap by path: `world` and `world.enemies` overlap, since one contains the other.

- **Stored fields of one value are disjoint from each other**, and so are reflection projections of distinct stored fields (`value[f1]`, `value[f2]`, [09](09-compile-time.md#what-reflection-can-read)). Two projections whose fields may be one, as those picked by `Row.field(ofType:)` in code generic over `Row` may, overlap where the borrows are checked; `value[fields: (f1, f2)]` projects both at once, checked distinct at instantiation ([09](09-compile-time.md#tuples-field-lists-and-queries)).
- **Inline array elements at indices known to differ where the borrows are checked are disjoint**, and any other two overlap, since `a[i]` and `a[j]` may be the same element, as may `a[I]` and `a[J]` for value parameters `I` and `J` of a body checked once for all its instantiations ([05](05-protocols-generics-and-closures.md#protocols-and-generics)). A collection's elements are reached through its subscript, an accessor (next).
- **A user-declared computed property or subscript accessor is an access to all of `self`**, whatever it yields. So `var p = &world.physics; var r = &world.render` conflict when both are computed. An imported bitfield's generated accessors are the exception: each, like a reflection projection of the bitfield, accesses only its C memory location (below).

Some places share bytes, so writing one can change the other. Each of these counts as **one place**:

- **Unions:** the members of one union, declared `union` or `@c union` or anonymous inside a struct ([04](04-types.md#untagged-unions), [08](08-c-interop.md#structs-unions-and-enums)), and fields nested at any depth inside them. So `g(&e.f, &e.u)` and `join({ e.f = 1 }, { use(e.u) })` conflict when `f` and `u` are members of one union, and every rule that relies on disjoint fields, reflection projections and SoA splitting included, treats a union this way.
- **Vector lanes:** the lanes of one `Simd` value ([04](04-types.md#simd-and-math)), since storing one lane may rewrite the vector. A swizzle accesses the whole vector, and for a `Simd` `v`, `join({ v.x = a }, { v.y = b })` conflicts. `Vec3`'s `x`, `y` and `z` are ordinary stored fields, which are disjoint, and its swizzles are computed properties, which access all of it (above).
- **Enum payloads:** reaching into a payload, an optional's included, reads the tag, which may be a niche inside the payload ([04](04-types.md#optionals)). So every path into one enum value's payload, through `?.`, `!`, a pattern or reflection's `value[case:]` ([09](09-compile-time.md#what-reflection-can-read)), overlaps every other (`s?.n` and `s?.b` conflict), but one pattern that binds several parts reads the tag once, so for an optional tuple `pair`, `if var (a, b) = &pair` gives two disjoint borrows.
- **Bitfields:** imported bitfields that form one C **memory location** ([08](08-c-interop.md#structs-unions-and-enums)): in `struct { uint32_t a : 20; uint32_t b : 20; }`, `a` and `b` are one place, although they lie in two storage units. Bitfields in different memory locations, or a bitfield and a neighboring field, are separate places that two threads may write at once, as C11 allows.

### Two elements of one collection

Two elements at once need an API that checks at run time that they are distinct:

```swift
if var (a, b) = &world.enemies[h1, h2] {     // nil if h1 == h2 or either is stale
    swap(&a.hp, &b.hp)
}
if var (a, b) = &verts[i, j] { ... }         // lists too: nil if i == j; out of bounds still panics
list.swapAt(i, j)
var (left, right) = list.split(at: mid)        // two disjoint MutableSpans, both depending on list
```

