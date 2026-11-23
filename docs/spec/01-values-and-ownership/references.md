# References

[01 · Values and ownership](../01-values-and-ownership.md)

Code often needs a value where it lies: to read an enemy without copying it, or to change it in its list. A reference is the value that lets it do that. It refers to a place, and borrows the place for as long as it is used:

```rayo
struct Enemy(var pos: Vec3, var hp: Float)

func show(_ e: &Enemy) { print("hp \(e.hp)") }    // borrows the caller's enemy, read-only
func heal(_ e: mutable &Enemy) { e.hp = 100 }    // borrows it for change

var boss = Enemy(pos: .zero, hp: 40)
show(boss)                        // a shared reference to 'boss', lent because 'show' takes a '&Enemy'
heal(mutable boss)                // a mutable reference: heal changes 'boss' in place
let seen = &boss                  // a '&Enemy' value, which 'seen' holds
print("hp \(seen.hp)")            // reads boss.hp through the reference
```

A **reference** is a value that refers to a place. A **shared reference**, of type `&T`, reads the place, and a **mutable reference**, of type `mutable &T`, may change it. A reference's type is a type like any other: `&boss` is a `&Enemy`, and `mutable boss` a `mutable &Enemy`. So a parameter, a binding, a field or an element can hold one, and holding one never copies what it refers to.

## Making a reference

**`&p` of a place `p` of type `T` makes a `&T`, and `mutable p` makes a `mutable &T`.** The reference borrows `p`, shared or for change, until the reference's last use, and the law of exclusivity checks that borrow as it checks any other ([Exclusivity](exclusivity.md#the-law-of-exclusivity)). `mutable p` needs `p` to be a [changeable place](bindings.md#changeable-places), so a shared borrow never becomes a write. Where a `&T` is expected, a bare `p` makes the same shared reference, with no `&` written ([below](#places-given-to-a-position)).

- **`&` of a value lends a temporary, and `mutable` of one is a compile error.** A call's result or a literal is no place, so `&makeEnemy()` lends a temporary that lives to the end of its statement ([02](../02-views-and-dependencies/dependency-projection-and-results.md#temporaries)). A temporary isn't changeable, so `heal(mutable makeEnemy())` is an error ([Bindings](bindings.md#temporaries-are-read-only)). A `mutable &T` that a call returns is passed on as it is, as `scale(grid.mutableRow(3))` passes one.
- **`mutable` of a `&` expression is a compile error that names `mutable p`**, so `mutable &boss` says to write `mutable boss`. The reference `&boss` makes is a temporary, so `mutable` can't lend it.
- **A member lends a place as it is declared.** `&x.p` of a place property uses its `borrow`, and `mutable x.p` its `mutate`. `mutable` of a member with only a `borrow` is a compile error, since nothing lends that place for change ([02](../02-views-and-dependencies/place-and-value-properties.md#place-properties-borrow-and-mutate)).
- **Where a function type is expected, `&f` and `mutable f` make a function value** of the closure in the place `f`: `&f` from a non-`mutating` closure, and `mutable f` from a `mutating` one ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)).

**`mutable` marks a lend for change**: it says both that the place is lent and that it is lent for change. A mutable reference's type is written `mutable &T`, since a type says that its values are references, while a lend says only how a place is lent. `mutable`, like `&`, takes the whole place after it, member and call chain included, so `mutable world.enemies[i]` lends one enemy ([12](../12-grammar/notes.md#operators-and-punctuation)).

**References follow the dependency rules, as every view does, and need no lifetimes.** Both kinds conform to `Scoped`, so a reference stays within the scope that lent it, and a struct or enum that holds one is scoped too ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)). What a reference depends on is the place it borrows ([02](../02-views-and-dependencies.md#dependencies)).

**A reference to an optional is written `&T?`, and an optional reference `(&T)?`**, as the grammar's precedence of `?` and `&` gives ([12](../12-grammar/notes.md#references-and-unsized-types)). A pool's element is an optional place, so `&world.enemies[h]` is a `&Enemy?`.

**A shared reference is implicitly copyable, and a mutable reference is move-only.** The language makes `&T` conform to `ImplicitlyCopyable`, as it makes numbers conform, since a copy is one more shared borrow of the same place, which the law of exclusivity allows ([Implicitly copyable types](moves-copies-destruction.md#implicitly-copyable-types)). `mutable &T` is `~Copyable`, since two copies would be two mutable aliases of one place.

## Forwarding through a reference

**A reference forwards its members, methods, subscripts and operators to the value it refers to.** So `r.hp`, `r.takeDamage(1)`, `r[i]` and `r + v` reach that value, as they would through the place itself. This is **forwarding**, and it lets code use a reference wherever it would use the value.

**Writing through a reference needs a mutable reference, held in a changeable place or a temporary.** That covers assigning a member, calling a `mutating` method and using a `mutate` accessor. So a `var` that holds a `mutable &T` writes through it, and a `let` that holds one can't, as a `let` changes nothing it holds ([Changeable places](bindings.md#changeable-places)). A temporary that holds one writes through it, as `grid.mutableRow(3)[0] = 1` does where `mutableRow` returns a `mutable &[Float]`, since the change reaches storage the temporary doesn't own.

```rayo
var best = &enemies[0]              // a '&Enemy'
print("hp \(best.hp)")              // reads enemies[0].hp through 'best'
best.hp = 0                         // error: 'best' is a shared reference
var lead = mutable enemies[1]       // a 'mutable &Enemy' in a var
lead.hp -= 10                       // writes enemies[1].hp
lead.takeDamage(1)                  // a mutating method, through the reference
let held = mutable enemies[2]
held.hp = 0                         // error: a 'let' can't write through the reference it holds; declare 'var held'
```

**A reference itself has no members, except one the language gives it.** Every member a call reaches through a reference is the referent's, by forwarding, as `[T]`'s own `split(at:)` and `mutableSplit(at:)` are ([04](../04-types/collections.md#mutating-and-consuming-methods)). The one exception is `mutable &[T]`'s `consumingSplit(at:)`, which takes the reference itself and hands over two mutable references to its halves. The halves carry only what the reference carried, so they may outlive a borrow of the place that held it:

```rayo
let whole = mutable samples.span                    // a 'mutable &[Float]'
var (low, high) = whole.consumingSplit(at: 64)      // takes 'whole', and hands over its halves
low[0] = 0                                          // writes samples[0]
```

## Reborrowing

**`&r` or `mutable r` of a place `r` that holds a reference refers to what `r` refers to.** The result is a new reference to the same place, a **reborrow**, and what it depends on follows from the kind of reference `r` holds ([02](../02-views-and-dependencies.md#dependencies)):

- **Through a shared reference.** `&r` of a place that holds a `&T` carries what `r` carries, and leaves `r` itself unborrowed. A `&T` is implicitly copyable, so a copy of `r` would give the same reference, and the new one needs nothing of the place that holds `r`.
- **Through a mutable reference.** `&r` or `mutable r` of a place that holds a `mutable &T` keeps `r` borrowed until the new reference's last use, shared for `&r` and exclusively for `mutable r`, and carries what `r` carries too. While the new reference is used, `r` can't reach the place in a way that conflicts with it, so the two are never two ways to change one place.

`mutable r` lends `r` for change, so it needs `r` changeable and holding a `mutable &T`. A temporary that holds one, such as a call's result, is passed on as it is ([above](#making-a-reference)). A mutable reference is passed on for change as `mutable r`, as `chunk` is below, since every lend for change is marked ([below](#every-lend-for-change-is-marked)).

**So a function can be given one mutable reference twice, one call after the other**, and the reference stays usable after each:

```rayo
func scale(_ s: mutable &[Float]) { for x in mutable s { x *= 2 } }

for chunk in data.mutableChunks(64) {
    scale(mutable chunk)            // a new 'mutable &[Float]' of what 'chunk' refers to
    scale(mutable chunk)            // and another, after the first one's last use
}
```

**Only where the expected type is a reference to a reference does `&r` refer to the place `r` itself**, as a parameter of type `&(&T)` expects. A bare `r` is lent there the same way ([below](#places-given-to-a-position)):

```rayo
func peek(_ r: &(&Enemy)) { … }    // refers to a place that holds a reference
peek(best)                          // lends 'best' itself, as '&best' would
```

## Layout

**A reference is one pointer, or a pointer and what it needs to reach an unsized value** ([below](#unsized-types)):

- `&T` and `mutable &T` of a sized `T` are one pointer;
- `&[T]`, `mutable &[T]` and `&Text` are a pointer and a count;
- `&any P` and `mutable &any P` are a pointer and a witness table, and their layout is otherwise left open ([11](../11-compilation-model.md#what-the-language-leaves-open)).

## Unsized types

**Some types have no size known where code is compiled, so their values can't sit in a place of their own.** These are the **unsized** types:

- **`[T]`, a run of elements**, such as a list's elements, a range of them, or an `SoA` column ([04](../04-types/collections.md#runs-of-elements));
- **`Text`, a run of UTF-8**, such as a `String`'s text or a literal's ([04](../04-types/collections.md#strings));
- **`any P`, an existential**, a value of some type that conforms to `P` ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)).

**An unsized type is held only behind a reference, a `Box`, an object pointer or a reference-counted pointer.** It is never a local's, a field's, a parameter's, a result's, an element's or a payload's type by itself. It binds no type parameter either, though `Type<T>` names any type, so `Text.self` is a type value ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#type-parameters-stand-for-sized-types)).

**A place of unsized type is never assigned, moved or copied as a whole**, since nothing knows its size. Its parts are changed through a mutable reference, as `some[0] = 0` changes an element below. So a `mutable &[T]` made from a `List<T>`, or a `mutable &any P` made from a `T: P`, can't store a value of another type in that place ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)).

```rayo
let all = &hits.span                // a '&[Int]': a pointer and a count
var some = mutable hits[0..<4]      // a 'mutable &[Int]' of the first four elements
some[0] = 0                         // writes hits[0]
let name: &Text = player.name       // lends the String, and its '&String' converts to a reference to its text
let greeting = "hello"              // a string literal is a 'static &Text'
let d: &any Drawable = sprite       // an existential reference to 'sprite'
let run: [Int] = hits.span          // error: '[Int]' is unsized; declare 'run' a '&[Int]'
```

**A reference to a sized value converts to one of an unsized type where the expected type says so**, as `&List<T>` does to `&[T]`, `&String` to `&Text`, and `&T` to `&any P` for a `T: P` ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)).

## Places given to a position

**What happens to a place given to a position is written there, or follows from the type the position expects**, so a reader sees from the code alone what happens to the place. A **position** is a part of the code that takes a value:

- an argument to a function or a method;
- a subscript's index argument;
- an initializer's argument, and an enum case's payload;
- a loop's or a `when`'s subject;
- the initializer of a declaration or of a condition's binding;
- the right side of `=`, as in `_ = consume g`;
- the operand of `return`, `throw`, `await`, `try`, `try?` or `try!`;
- an element of a tuple, array or dictionary literal.

**A place given to a position may write one of four marks before it:**

- `&p` lends it shared ([above](#making-a-reference));
- `mutable p` lends it for change;
- `consume p` moves its value out ([Moving values out](moving-values-out.md#moving-values-out));
- `copy p` makes a second value ([Copies](moves-copies-destruction.md#copies)).

**A bare place is taken in one of two ways:**

- **Where a `&T` is expected, it is lent shared**, as `&p` would lend it, unless its own type fits ([05](../05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected)). So a `&T` parameter takes `boss` or `&boss` alike, and a place of an implicitly copyable type is lent there too, not copied.
- **Anywhere else, a place of an implicitly copyable type is copied** with nothing written, as its own type decides ([Implicit copies](moves-copies-destruction.md#implicit-copies)).

**Any other bare place is a compile error that names the marks that fit**, except in the cases [below](#unmarked-places). Where no `&T` is expected, code writes `&` to lend a place ([05](../05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected)). The last expression of an `if` or `when` arm or of an `unsafe` block stands in its position, and writes its mark there, as does each operand of `??` ([Bindings](bindings.md#if-and-when-as-values)).

**The value a position takes has the type it expects, so a mark that doesn't fit is a compile error.** A `&T` parameter takes a shared reference, a `mutable &T` parameter a mutable one, and a `T` parameter a `T` ([Parameters](parameters.md#parameters)). So `&boss` given to an owning parameter is a compile error, and so is a bare `boss` given to a `mutable &T` one ([below](#every-lend-for-change-is-marked)). A value given to a `&T` parameter is lent as a temporary, as `&makeEnemy()` lends one ([above](#making-a-reference)):

```rayo
func keep(_ e: Enemy) { … }         // owns its argument

show(boss)                          // lends 'boss' shared, since 'show' takes '&Enemy'
keep(boss)                          // error: 'keep' takes 'Enemy'; write 'consume boss' or 'copy boss'
keep(&boss)                         // error: 'keep' takes 'Enemy', not a reference
heal(boss)                          // error: 'heal' takes 'mutable &Enemy'; write 'mutable boss'
show(makeEnemy())                   // lends a temporary enemy, which the statement then destroys
keep(copy boss)                     // fine: a copy of the enemy
let hp = boss.hp                    // a Float is implicitly copyable: a copy, with nothing written
```

### Every lend for change is marked

**Every lend for change is marked with `mutable`, a forwarded one included.** A lend for change changes the caller's place, where a shared lend only reads, so the line that takes the borrow shows it. So a bare place given where a `mutable &T` is expected, or given to a `ref var`, is a compile error that names `mutable p`, as `heal(boss)` above is. A place that holds a mutable reference is lent on the same way: a function given `s` passes it on as `scale(mutable s)`, and `ref var t = mutable r` reborrows through `r` ([above](#reborrowing)).

**A change made in place takes no mark**, since the change shows where it happens, and the place must be changeable ([Changeable places](bindings.md#changeable-places)):

- a `mutating` method's receiver ([below](#unmarked-places));
- the left side of `=`, or of a compound assignment such as `+=`;
- a write through a closure's captures ([05](../05-protocols-generics-and-closures/functions-and-closures.md#capturing-places));
- an `await`, which lends the task's resume parameter for change to what it awaits, so the change shows at the `await` ([07](../07-concurrency/tasks.md#semantics)).

### Unmarked places

**Besides those, three operands take a place with no mark, since the code around them already says what happens:**

- **A method's receiver.** The method's declaration says what it does with `self`: a plain `func` borrows it, a `mutating` one borrows it for change, from a changeable place, and a `consuming` one takes it ([Parameters](parameters.md#parameters)).
- **An operator's operands.** Operators borrow their operands. An operator declares each parameter `&T`, or `T` where `T` is implicitly copyable, so an operand never moves ([05](../05-protocols-generics-and-closures/operators.md#operators)).
- **The segments of an interpolated string**, which format through a borrowing method, as a receiver does ([04](../04-types/collections.md#printing)).

```rayo
static func == (lhs: &Ranked, rhs: &Ranked) -> Bool { … }   // each operand is borrowed
static func * (lhs: Vec3, rhs: Float) -> Vec3 { … }         // a Vec3 is implicitly copyable: each operand is copied
```

**Some places take no mark, since the position makes a value of its own from them, or borrows through them as a mark would**, so the place is left as it was or dies anyway:

- **A copyable `const`**, which gives a new value each time ([Constants](moving-values-out.md#constants));
- **A conversion that makes a value from the place**, such as a copyable value's conversion to or from its static type ([Conversions](bindings.md#conversions));
- **A part of a temporary**, such as `makeEnemy().pos`, which dies with its statement, so the position takes it as a value, moving it out where [What can be moved from](moving-values-out.md#what-can-be-moved-from) allows;
- **A place that holds a `&T`, given to a `ref let`**, which reborrows through it, as `ref let e = r` does, since copying a shared reference lends nothing ([above](#reborrowing)). A place that holds a `mutable &T` writes `&r` there, as any other shared lend where nothing expects a `&T` does.
