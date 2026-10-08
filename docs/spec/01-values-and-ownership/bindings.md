# Bindings

[01 · Values and ownership](../01-values-and-ownership.md)

**A declaration takes the value it is given, as an assignment does, unless it says it borrows.** `let` and `var` say only whether the binding may change what it holds. So a declaration moves a value out of a place, whatever its type. `borrow` borrows the place instead, and `&` lends it for change.

```swift
var enemies = loadEnemies()

let seen = borrow enemies[0]       // looks: a read-only name for the enemy, nothing copied
var boss = &enemies[0]             // changes it in place: boss.hp = 0 changes enemies[0]
var spare = copy enemies[0]        // a second enemy of its own
let first = enemies[0]             // error: an element can't move out of its list
let mesh = loadMesh()              // a value, not a place: the binding owns it
let all = enemies                  // a move: 'enemies' can't be used until it gets a new value
```

| Form | Like the parameter | Meaning | Cost |
| --- | --- | --- | --- |
| `let x = place`, `var x = place` | `_ x: owned T` | A **move** from a place the code owns ([What can be moved from](moving-values-out.md#what-can-be-moved-from)): `place` can't be used until it gets a new value. A copyable `const` gives a new value instead ([Constants](moving-values-out.md#constants)) | A `memcpy` at most |
| `let x = borrow place` | `_ x: T` | A shared **borrow** of `place`, of any type: `place` can't be changed, moved or destroyed while `x` is live | None |
| `var x = &place` | `_ x: mutable T` | A mutable **borrow** of a [changeable place](#changeable-places): `place` is reachable only through `x` while `x` is live | None |
| `let x = copy place`, `var x = copy place` | | An independent **copy** of a copyable value; a move-only one is copied with `.clone()` | A `memcpy` |
| `let x = f()`, `var x = f()` | | The binding owns the value, even a move-only scoped value such as a `MutableSpan` or a lock guard ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)); `consume x` ends it early | None |
| `var x = borrow place` | | A compile error, since `=` on a `var` that borrows writes the place it names ([02](../02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind)), which a shared borrow can't | |

- **A binding that names a place it borrows is a borrowing binding**, and can't be consumed. A declaration makes one with `borrow` or `&` on a place, unless the initializer makes a value of its own from the place, such as a view ([below](#lending-a-place-for-change)). A condition or pattern makes one by binding a place ([below](#conditions-and-patterns)).
- **A binding of anything that isn't a place owns it**, as a binding of a call's result does: a literal, an operator's result, `copy place` or `consume place`. A binding that owns its value can move it on, and a `let` still can't change it.
- **`borrow` on a value binds the value itself**, which the binding owns, since there is no place to borrow. A property whose accessor is a `get` gives such a value ([below](#what-a-borrowing-let-sees)).
- **`borrow` is written only where a declaration borrows**, and a borrowed argument and a condition borrow with nothing written. A declaration writes it:
    - on its initializer;
    - on an expression the initializer hands its position to: the last expression of an `if` or `when` arm or of an `unsafe` block ([below](#if-and-when-as-values)), or an operand of `??` ([04](../04-types/enums.md#optionals));
    - on the place a `rebind` of the binding names ([02](../02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind)).
- **Views taken from a borrowing `let` depend on the place itself** ([02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#rule-1-projection)).
- **A place in a temporary's own storage dies with its statement**, such as `makeEnemy().pos`. So `borrow` of one owns that value instead, moving it out as [What can be moved from](moving-values-out.md#what-can-be-moved-from) allows. Where that can't move it, the binding is a compile error unless it is written with `copy` or `.clone()`.
- **A place that a `where yield outlives self` projection yields from a temporary lies outside the temporary**, such as `makeSpan()[0]`. So `borrow` of one borrows it, depending on what the temporary carries ([02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#temporaries)).
- **Neither borrowing form may bind an under-aligned place**: that is a compile error, since a load or store of its type at that address may be invalid, and fault on some targets ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)).

## What a borrowing `let` sees

**Changing a place while a `let` that borrows it is used is a compile error**, since the `let` is a shared borrow ([The law of exclusivity](exclusivity.md#the-law-of-exclusivity)). For a place reached through an object or a thread-local, it is a panic instead ([below](#how-long-a-borrow-lasts)). A `Synchronized` value still changes through its own synchronization ([07](../07-concurrency/synchronization.md#the-synchronized-contract)).

**Making a field computed, or stored, never silently changes what a binding of it gets.** What a binding of `e.f` gets follows from how `f` is declared:

- **A stored field** moves out of `e`, as [What can be moved from](moving-values-out.md#what-can-be-moved-from) allows, and `borrow` gives another name for the field.
- **A property whose accessor is a `get`** gives the value the `get` returns, which the binding owns, with or without `borrow`.
- **A `read` projection** lends what it yields to `borrow`, and can't be moved from ([02](../02-views-and-dependencies/projections-and-accessors.md#projections-read-and-modify-accessors)).

Where the stored and the computed forms would differ, the stored form is a compile error:

```swift
extension Enemy { var isDead: Bool { hp <= 0 } }   // computed

func hit(_ e: mutable Enemy, _ d: Float) {
    let before = borrow e.hp
    e.hp -= d                      // error: 'before' still names e.hp
    let dead = e.isDead            // computed: the Bool it returned, which 'dead' owns
    save(dead)                     // fine: save takes an owned parameter
    let hp = e.hp                  // error: 'e' is a mutable parameter, so e.hp can't move out of it
}
```

## How long a borrow lasts

**A borrow lasts until its last use, not to the end of the scope.** Once `boss` above is last used, `enemies` is free again. Where destroying the value that holds the borrow is a use ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)), that destruction is its last use.

**A borrowing binding of a dynamic place holds its access until its last use.** A dynamic place is one reached through a thread-bound object's owner or weak pointer, or a thread-local, and the binding holds that dynamic access (rule 6 in [02](../02-views-and-dependencies/dependency-rules/absorption-and-accesses.md#rule-6-dynamic-accesses)). So a call in between that changes the object panics.

## Conditions and patterns

**A condition or a pattern borrows a place it binds, unless it says `owned`.** It looks inside a value, at an optional's payload or an enum case's, so where a declaration's default is to take, its default is to look. `guard` and `while` work the same way as `if`:

```swift
if let e = world.enemies[h] { ... }        // looks at the enemy in place
if var e = &world.enemies[h] { ... }       // changes it in place
if let v = pool.take(h) { ... }            // owns the value that take moved out
```

- **A `let` looks at the place, and a `var` changes it in place**, with the place marked `&`.
- **`owned` takes the value out of a place the code owns**, as a declaration does ([above](#bindings)).
- **A value, such as a call's result, is owned by the binding**, as in a declaration.

**Narrowing unwraps a local, a parameter or a stored field of one in place** ([04](../04-types/enums.md#narrowing)), so a condition always names what it binds, with no short form.

**In a `when`, each part of a pattern binds as a condition does:**

- **A `let` part looks at what it matches, and a `var` part changes it in place.** For a `var` part, the subject is marked `&`, as in the example below.
- **An `owned` part takes what it matches out of a subject the code owns.** It moves as a field is moved out ([What can be moved from](moving-values-out.md#what-can-be-moved-from)): only when no type on the path to it declares a `deinit`, except in that type's own `deinit`, since a `deinit` takes the whole value. It also moves only once its arm is chosen, since patterns and guards run under a borrow of the subject until then ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)).
- **When the subject is a value, every part owns what it matches.**
- **A `deinit` on the path keeps a value subject whole.** This holds in an arm where any of its patterns has, on the path to a part, a type that declares a `deinit`, whichever pattern matched. The value stays whole in a hidden local until the arm ends, as a `for` loop's sequence does. The arm's `let` parts look at it, and its `var` parts change it in place, so the `deinit` runs on the changed value, and nothing moves out of it. The subject still takes no `&`, since the hidden local is the arm's own.
- **A subject in a temporary's own storage that can't be moved out is kept whole the same way**, with the whole temporary in that hidden local, as `connect().state` is where `Conn` declares a `deinit`.

```swift
when &shape {
    .circle(var r) { r *= 2 }      // a var part: doubles the radius inside 'shape'
    else {}
}
```

**`if case`, `guard case` and `while case` bind the same way**, with the value after `=` as the subject. A `guard`'s hidden local lives to the end of the enclosing scope, as the names it binds do.

**`for` patterns bind elements in place, changeable when the loop lends its sequence with `&`**, and own what the iterator hands out as a value of its own, such as a `Range`'s `Int`. So a `for` pattern writes no `let`, and writes `var` only on a part that owns its value ([04](../04-types/collections.md#iteration)).

## `if` and `when` as values

**An `if` or `when` expression hands its position to the arm that runs.** Whatever the position does with a value, it does with the arm's last expression, as if that expression stood there: borrows it, lends it for change, moves it or returns it. An `unsafe` block used as an expression hands its position to its last expression the same way ([10](../10-errors-and-safety/unsafe-code.md#unsafe-code)).

```swift
let e = if first { borrow enemies[0] } else { borrow enemies[1] }   // borrows one of the two
var t = if left { &a } else { &b }                                  // lends one for change
let v = if c { p } else { q }                                       // moves from the one chosen
```

What depends on `e` depends on both places ([02](../02-views-and-dependencies/dependency-rules.md#dependencies)). `v` moves from the one chosen, so each of `p` and `q` is moved only on its own path ([Moving values out](moving-values-out.md#moving-values-out)).

**When some arms borrow places and others give values, each value is kept in a hidden local:**

```swift
let e = if c { borrow enemies[0] } else { makeEnemy() }      // the new enemy is kept in a hidden local
```

The hidden local is declared where the binding is, and destroyed with it if its arm ran. The binding is then a borrowing binding, which can't be consumed. What depends on it depends on every arm's place, and on those hidden locals.

## Conversions

**A converted value is a new value.** When a binding's declared type differs from its initializer's, the conversion says what it does with a place ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)):

- **A numeric widening reads the place** and makes a new value, which the binding owns.
- **These conversions take the value**, so from a place, each moves it as a declaration does, unless the code writes a copy of a copyable value:
    - wrapping it in an optional or an error union;
    - making a `Box<T>` or an object pointer into one of an existential;
    - moving a closure into a `Closure`.
- **Making an `any P` from a place borrows the place shared**, as making any view of it does, and the binding, `let` or `var`, owns the view. So a `var` of one may later point at another value. `&place` makes a `mutable any P` instead ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)).

```swift
let total: Int = n                          // 'n' is an Int32: the widened Int is a new value 'total' owns
var spare: Handle<Enemy>? = copy h          // wrapping a copy of the handle
var target: Handle<Enemy>? = h              // or wrapping the handle itself, moved out of 'h'
var d: any Drawable = sprite                // borrows 'sprite'; 'd' owns the view, and may later view another value
```

## Changeable places

**Only a changeable place can be changed, or lent with `&`**, so a shared borrow never becomes a write. A place is **changeable** when it is:

- a `var` that owns its value;
- a temporary, which its statement owns ([02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#temporaries));
- the place that a `var` given `&place` names, through that binding;
- a `mutable` or `owned` parameter, or `self` in a `mutating` or `consuming` method, a `deinit` or an initializer;
- an owned capture of a `mutating` or `consuming` closure;
- a `var` field, an element, a `modify` projection ([02](../02-views-and-dependencies/projections-and-accessors.md#projections-read-and-modify-accessors)), or a property or subscript with a `set` ([02](../02-views-and-dependencies/projections-and-accessors.md#get-and-set-accessors)), of a changeable place.

**Everything else is read-only, and so is whatever is reached through it**: a `let`, owning or borrowing, a borrowed parameter, `self` in a plain method, a `let` field, a `const` and a global `let`.

```swift
let x = makeEnemy()
var y = &x                         // error: a let is read-only, even one that owns its value
heal(&x)                           // error: the same
```

**There are four exceptions, each with its own way of keeping exclusivity**, the first two checked at run time:

- **A `@threadlocal var`**, which its own thread changes under a dynamic mark on each access ([07](../07-concurrency/global-state.md#thread-locals)).
- **An object's value**, which is changeable whatever holds its owner or weak pointer, since each access takes a dynamic mark ([03](../03-handles-and-objects.md#dynamic-exclusivity)).
- **A `Synchronized` value**, whose non-`mutating` methods change it through its own synchronization ([07](../07-concurrency/synchronization.md#the-synchronized-contract)).
- **`unsafe` code**, which may change a bare global `var` or an imported C variable ([07](../07-concurrency/global-state.md#global-state)), and the memory a raw pointer points at, whatever holds the pointer ([10](../10-errors-and-safety/unsafe-code.md#raw-accesses)). It promises to keep exclusivity itself ([10](../10-errors-and-safety/unsafe-code.md#what-unsafe-code-upholds)).

```swift
let r = renderer.weak()
r.value?.submit(mesh)              // fine: an object's value is changeable through a let of a weak pointer
```

## Lending a place for change

**`&` marks every place lent for change, in a binding as in a call.** The receiver of a `mutating` method call is the exception, since the call's form shows it. These places take `&`, each lent to code that may change it:

- a `mutable` argument;
- the place a `var` borrows, in a declaration or in an `if var`, `guard var` or `while var`, and a place that a pattern's `var` part binds;
- the target of a `rebind` of a `var` ([02](../02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind));
- a loop's sequence whose elements the loop changes, which may be a temporary the loop keeps in a hidden local ([04](../04-types/collections.md#iteration));
- a `when` subject that is a place, or a `case` condition's value that is one, with a `var` part;
- the last expression of an `if` or `when` arm whose position lends a place for change;
- a place holding a `mutating` closure, a `Closure<mutating …>` or a `mutating` function value, made into a new function value ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions));
- a place that a `modify` projection's `yield` lends ([02](../02-views-and-dependencies/projections-and-accessors.md#projections-read-and-modify-accessors));
- a place made into a `mutable any P`, or holding one that lends a new view of its value ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)).

```swift
for (i, e) in &makeEnemies().enumerated() { ... }       // the loop keeps the new list in a hidden local, and changes it
var t = if left { &a } else { &b }                       // the arm's place is lent for change
var v: mutable any Damageable = &boss                    // a mutable any P made from 'boss'
```

**What follows `&` is a changeable place, or a member of one that has a mutable form.** Leaving `&` out is a compile error, and so is `&` on something that lends nothing for change.

- **`&` picks a mutable form.** Where a method or property has a shared and a mutable form of one name, the operand of `&` picks the mutable one ([04](../04-types/collections.md#shared-mutable-and-consuming-forms-of-one-method)). So a binding of `&particles.life` binds an [`SoA`](../04-types/data-layout.md#struct-of-arrays-soat) column as a `MutableSpan<Float>` that it owns, where a binding of `particles.life` gets a `Span<Float>`, as in the example below.
- **A binding of a value lends nothing, so it takes no `&`.** A call result bound to a name is owned by its binding. That includes an **owned exclusive view**: a move-only scoped value ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)), such as the guard that `registry.lock()` returns, which changes the registry through it.
- **A call result lent for change takes `&`, as any changeable place does**, when it is a `mutable` argument or a loop's sequence. It is a temporary, which its statement owns, or which the loop owns, for a sequence, as in the example below.
- **A `zip` marks its own arguments**, as in `zip(&vels, forces)`, so a loop over it needs no `&` of its own ([04](../04-types/collections.md#iteration)).

```swift
var lives = &particles.life        // the mutable form: a MutableSpan<Float> that 'lives' owns
let ages = particles.life          // the shared form: a Span<Float>
var g = registry.lock()            // no '&': 'g' owns the guard, and changes the registry through it
heal(&makeEnemy())                 // the statement owns the new enemy, and destroys it after the call
```
