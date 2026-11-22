# References

[01 · Values and ownership](../01-values-and-ownership.md)

Code often needs a value where it lies: to read an enemy without copying it, or to change it in its list. A reference is the value that lets it do that. It refers to a place, and borrows the place for as long as it is used:

```swift
struct Enemy(var pos: Vec3, var hp: Float)

func show(_ e: &Enemy) { print("hp \(e.hp)") }    // borrows the caller's enemy, read-only
func heal(_ e: mutable &Enemy) { e.hp = 100 }    // borrows it for change

var boss = Enemy(pos: .zero, hp: 40)
show(&boss)                       // a shared reference to 'boss'
heal(mutable &boss)               // a mutable reference: heal changes 'boss' in place
let seen = &boss                  // a '&Enemy' value, which 'seen' holds
print("hp \(seen.hp)")            // reads boss.hp through the reference
```

A **reference** is a value that refers to a place. A **shared reference**, of type `&T`, reads the place, and a **mutable reference**, of type `mutable &T`, may change it. A reference's type is a type like any other, written as the reference is made: `&boss` is a `&Enemy`. So a parameter, a binding, a field or an element can hold one, and holding one never copies what it refers to.

## Making a reference

**`&p` of a place `p` of type `T` makes a `&T`, and `mutable &p` makes a `mutable &T`.** The reference borrows `p`, shared or for change, until the reference's last use, and the law of exclusivity checks that borrow as it checks any other ([Exclusivity](exclusivity.md#the-law-of-exclusivity)). `mutable &p` needs `p` to be a [changeable place](bindings.md#changeable-places), so a shared borrow never becomes a write.

- **`&` of a value lends a temporary.** A call's result or a literal is no place, so `&makeEnemy()` lends a temporary that lives to the end of its statement ([02](../02-views-and-dependencies/dependency-projection-and-results.md#temporaries)). So `heal(mutable &makeEnemy())` changes an enemy that the statement then destroys.
- **A member lends a place as it is declared.** `&x.p` of a place property uses its `borrow`, and `mutable &x.p` its `mutate`. `mutable &` of a member with only a `borrow` is a compile error, since nothing lends that place for change ([02](../02-views-and-dependencies/place-and-value-properties.md#place-properties-borrow-and-mutate)).
- **Where a function type is expected, `&f` and `mutable &f` make a function value** of the closure in the place `f`: `&f` from a non-`mutating` closure, and `mutable &f` from a `mutating` one ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)).

**References follow the dependency rules, as every view does, and need no lifetimes.** Both kinds conform to `Scoped`, so a reference stays within the scope that lent it, and a struct or enum that holds one is scoped too ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)). What a reference depends on is the place it borrows ([02](../02-views-and-dependencies.md#dependencies)).

**`?` binds tighter than `&`.** So `&T?` is a reference to an optional, and `(&T)?` is an optional reference. A pool's element is an optional place, so `&world.enemies[h]` is a `&Enemy?`, and an optional view of elements is written `(&[T])?` ([12](../12-grammar/notes.md#references-and-unsized-types)).

**A shared reference is implicitly copyable, and a mutable reference is move-only.** The language makes `&T` conform to `ImplicitlyCopyable`, as it makes numbers conform, since a copy is one more shared borrow of the same place, which the law of exclusivity allows ([Implicitly copyable types](moves-copies-destruction.md#implicitly-copyable-types)). `mutable &T` is `~Copyable`, since two copies would be two mutable aliases of one place.

## Forwarding through a reference

**A reference forwards its members, methods, subscripts and operators to the value it refers to.** So `r.hp`, `r.takeDamage(1)`, `r[i]` and `r + v` reach that value, as they would through the place itself. This is **forwarding**, and it lets code use a reference wherever it would use the value.

**Writing through a reference needs a mutable reference, held in a changeable place.** That covers assigning a member, calling a `mutating` method and using a `mutate` accessor. So a `var` that holds a `mutable &T` writes through it, and a `let` that holds one can't, as a `let` changes nothing it holds ([Changeable places](bindings.md#changeable-places)).

```swift
var best = &enemies[0]              // a '&Enemy'
print("hp \(best.hp)")              // reads enemies[0].hp through 'best'
best.hp = 0                         // error: 'best' is a shared reference
var lead = mutable &enemies[1]      // a 'mutable &Enemy' in a var
lead.hp -= 10                       // writes enemies[1].hp
lead.takeDamage(1)                  // a mutating method, through the reference
let held = mutable &enemies[2]
held.hp = 0                         // error: a 'let' can't write through the reference it holds; declare 'var held'
```

**A reference has no members of its own, except one the language gives it.** `mutable &[T]` has `consumingSplit(at:)`, which takes the reference and hands over two mutable references to its halves. The halves carry only what the reference carried, so they may outlive a borrow of the place that held it ([04](../04-types/collections.md#mutating-and-consuming-methods)):

```swift
let whole = mutable &samples.span                   // a 'mutable &[Float]'
var (low, high) = whole.consumingSplit(at: 64)      // takes 'whole', and hands over its halves
low[0] = 0                                          // writes samples[0]
```

## Reborrowing

**`&r` or `mutable &r` of a place `r` that holds a reference refers to what `r` refers to.** The result is a new reference to the same place, which keeps `r` borrowed until the new reference's last use: shared for `&r`, exclusively for `mutable &r`. This is a **reborrow**. `mutable &r` needs `r` changeable and holding a `mutable &T`, since writing through a reference needs both ([above](#forwarding-through-a-reference)).

**So a function can be given one mutable reference twice, one call after the other**, and the reference stays usable after each:

```swift
func scale(_ s: mutable &[Float]) { for x in mutable &s { x *= 2 } }

for chunk in data.mutableChunks(64) {
    scale(mutable &chunk)           // a new 'mutable &[Float]' of what 'chunk' refers to
    scale(mutable &chunk)           // and another, after the first one's last use
}
```

**Only where the expected type is a reference to a reference does `&r` refer to the place `r` itself**, as a parameter of type `&(&T)` expects:

```swift
func peek(_ r: &(&Enemy)) { … }    // refers to a place that holds a reference
peek(&best)                         // refers to 'best' itself
```

## Layout

**A reference is one pointer, or a pointer and what it needs to reach an unsized value** ([below](#unsized-types)):

- `&T` and `mutable &T` of a sized `T` are one pointer;
- `&[T]`, `mutable &[T]` and `&Text` are a pointer and a count;
- `&any P` and `mutable &any P` are a pointer and a witness table, and their layout is otherwise left open ([11](../11-compilation-model.md#what-the-language-leaves-open)).

## Unsized types

**Some types have no size known where code is compiled, so their values can't sit in a place of their own.** These are the **unsized** types:

- **`[T]`, a run of elements**, such as a list's elements, a range of them, or an `SoA` column ([04](../04-types/collections.md#collections-and-strings));
- **`Text`, a run of UTF-8**, such as a `String`'s text or a literal's ([04](../04-types/collections.md#strings));
- **`any P`, an existential**, a value of some type that conforms to `P` ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)).

**An unsized type is held only behind a reference, a `Box`, an object pointer or a reference-counted pointer.** It is never a local's, a field's, a parameter's, a result's, an element's or a payload's type by itself. It never binds a type parameter that isn't `@opaque` either ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#type-parameters-with-no-known-size-opaque)).

**A place of unsized type is never assigned, moved or copied as a whole**, since nothing knows its size. Its parts are changed through a `mutable &`, as `some[0] = 0` changes an element below. So a `mutable &[T]` made from a `List<T>`, or a `mutable &any P` made from a `T: P`, can't store a value of another type in that place ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)).

```swift
let all = &hits.span                // a '&[Int]': a pointer and a count
var some = mutable &hits[0..<4]     // a 'mutable &[Int]' of the first four elements
some[0] = 0                         // writes hits[0]
let name: &Text = &player.name      // a '&String' converts to a reference to its text
let greeting = "hello"              // a string literal is a 'static &Text'
let d: &any Drawable = &sprite      // an existential reference to 'sprite'
let run: [Int] = hits.span          // error: '[Int]' is unsized; write '&hits.span'
```

**A reference to a sized value converts to one of an unsized type where the expected type says so**, as `&List<T>` does to `&[T]`, `&String` to `&Text`, and `&T` to `&any P` for a `T: P` ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)).

## Places given to a position

**Every borrow, move and copy of a place is written where it happens**, so a reader sees from the code alone what happens to the place. A **position** is a part of the code that takes a value:

- an argument, a subscript's index argument and an initializer's argument included, and an enum case's payload;
- a loop's or a `when`'s subject;
- the initializer of a declaration or of a condition's binding;
- the right side of `=`, as in `_ = consume g`;
- the operand of `return`, `throw`, `await`, `try`, `try?` or `try!`;
- an element of a tuple, array or dictionary literal.

**A place given to a position writes one of four marks before it:**

- `&p` lends it shared ([above](#making-a-reference));
- `mutable &p` lends it for change;
- `consume p` moves its value out ([Moving values out](moving-values-out.md#moving-values-out));
- `copy p` makes a second value ([Copies](moves-copies-destruction.md#copies)).

**A bare place of any type but an implicitly copyable one is a compile error that names the marks that fit.** A place of an implicitly copyable type is copied with nothing written ([Implicit copies](moves-copies-destruction.md#implicit-copies)). The last expression of an `if` or `when` arm or of an `unsafe` block stands in its position, and writes its mark there, as does each operand of `??` ([Bindings](bindings.md#if-and-when-as-values)).

**The value a position takes has the type it expects, so a mark that doesn't fit is a compile error.** A `&T` parameter takes a shared reference, a `mutable &T` parameter a mutable one, and a `T` parameter a `T` ([Parameters](parameters.md#parameters)). So a value given to a `&T` parameter is a compile error too, and `&makeEnemy()` lends one as a temporary:

```swift
func keep(_ e: Enemy) { … }         // owns its argument

show(boss)                          // error: 'show' takes '&Enemy'; write '&boss'
keep(boss)                          // error: 'keep' takes 'Enemy'; write 'consume boss' or 'copy boss'
show(makeEnemy())                   // error: 'show' takes '&Enemy'; write '&makeEnemy()'
keep(copy boss)                     // fine: a copy of the enemy
let hp = boss.hp                    // a Float is implicitly copyable: a copy, with nothing written
```

**Three other operands take a place with no mark, since the code around them already says what happens:**

- **A method's receiver.** The method's declaration says what it does with `self`: a plain `func` borrows it, a `mutating` one borrows it for change, from a changeable place, and a `consuming` one takes it ([Parameters](parameters.md#parameters)).
- **An operator's operands.** Operators borrow their operands. An operator declares each parameter `&T`, or `T` where `T` is implicitly copyable, so an operand never moves ([05](../05-protocols-generics-and-closures/operators.md#operators)).
- **The segments of an interpolated string**, which format through a borrowing method, as a receiver does ([04](../04-types/collections.md#printing)).

```swift
static func == (lhs: &Ranked, rhs: &Ranked) -> Bool { … }   // each operand is borrowed
static func * (lhs: Vec3, rhs: Float) -> Vec3 { … }         // a Vec3 is implicitly copyable: each operand is copied
```

**Some places give a position a value of its own with no mark**, so the place is left as it was or dies anyway:

- **A copyable `const`**, which gives a new value each time ([Constants](moving-values-out.md#constants));
- **A conversion that makes a value from the place**, such as a copyable value's conversion to or from its static type ([Conversions](bindings.md#conversions));
- **A part of a temporary**, such as `makeEnemy().pos`, which dies with its statement, so the position takes it as a value, moving it out where [What can be moved from](moving-values-out.md#what-can-be-moved-from) allows.
