# 3 · Borrowing

Your game passes enemies to functions all the time. `damage` changes an enemy that lives in the caller's list, such as chapter 1's `enemies`, and `heal` reads a medic to heal another enemy. In C++ both take references, and nothing stops this:

```cpp
void damage(Enemy& e, float amount) { e.hp -= amount; }

Enemy& boss = enemies[0];
enemies.push_back(Enemy{});       // may move every enemy to a new buffer
damage(boss, 10);                 // writes through a dangling reference
```

Rust rejects this code, but its signatures sometimes need lifetime annotations, such as `'a`, to say how long a borrow lasts. Rayo rejects it too, and nothing in this chapter needs an annotation:

```swift
func damage(_ e: mutable Enemy, by amount: Float) { e.hp -= amount }
func heal(_ e: mutable Enemy, from medic: Enemy) { e.hp += medic.hp * 0.1 }

var boss = &enemies[0]                       // 'boss' is enemies[0], lent to be changed
enemies.append(Enemy(pos: [0, 0, 9]))        // error: 'enemies' is borrowed by 'boss' (used below)
damage(&boss, by: 10)
```

Chapter 2 was about who owns a value. This chapter is about code that uses a value without owning it, which borrows the value ([01](../spec/01-values-and-ownership.md)).

## Three ways to pass an argument

**A parameter's convention says what the function does with its argument: reads it, changes it in place, or keeps it** ([01](../spec/01-values-and-ownership.md#parameters)):

```swift
func length(_ v: Vec3) -> Float { ... }                      // borrowed: reads 'v'
func damage(_ e: mutable Enemy, by amount: Float) { ... }    // mutable: changes the caller's enemy
func enlist(_ e: owned Enemy) { ... }                        // owned: keeps the enemy

let speed = length(grunt.vel)
damage(&boss, by: 10)                                        // '&' marks the enemy lent for change
enlist(grunt)                                                // moves 'grunt' in
```

| Convention | Declared as | Call site | The function gets |
| --- | --- | --- | --- |
| borrowed (default) | `_ x: T` | `f(x)` | A **shared borrow**: it reads `x` |
| mutable | `_ x: mutable T` | `f(&x)` | A **mutable borrow** of a changeable place: it changes `x` in place |
| owned | `_ x: owned T` | `f(x)` | The value: a place moves in, and `f(copy x)` passes a copy |

**A borrowed argument holds still for the whole call.** The function can't change it, keep it or take its address, and nothing else changes it before the call returns. The exception is a `Synchronized` value, such as a mutex, which changes through its own locking ([Concurrency](07-concurrency.md#shared-mutable-state)). So the compiler may pass a copy of the argument's bits or the caller's place, and the function can't tell which. C++ makes you choose between `T` and `const T&`, where Rayo picks for you, from the signature: an argument the result still views, for one, is always the caller's place ([01](../spec/01-values-and-ownership.md#borrowed-arguments)).

Since the function can't keep a borrowed argument, it can't move one out either. So returning a borrowed parameter's field takes `copy`, or `clone()` for a move-only one, as chapter 2 showed ([Moves and copies](02-moves-and-copies.md#places-you-dont-own)).

**A `mutable` argument is the caller's place, lent for the call.** The call writes `&` before it, and every change the function makes reaches the caller's place. It works like Swift's `inout` or C#'s `ref`, which are marked at the call too.

**Methods use the same conventions for `self`.** A plain `func` borrows `self`, a `mutating func` takes it `mutable`, and a `consuming func` takes it `owned`. A `mutating` call takes no `&`, since its form already shows the change: `boss.takeDamage(5)`.

**An `owned` parameter takes the value, as chapter 2 showed.** A place passed to it moves in, even when its type is copyable, so `f(copy x)` passes a copy instead ([Moves and copies](02-moves-and-copies.md)). A struct's primary initializer and `List`'s `append` take their arguments `owned`.

## Bindings of places

**A local binding of a place says what it does with the place, in a parameter's words** ([01](../spec/01-values-and-ownership.md#bindings)). `let` and `var` say only whether the name may change what it holds.

```swift
let seen = enemies[0]              // a shared borrow: reads the enemy, copies nothing
var boss = &enemies[0]             // a mutable borrow: boss.hp = 0 changes enemies[0]
var spare = copy enemies[0]        // a second enemy, of its own
owned var kept = spare             // a move: 'spare' can't be used until it gets a new value
var e = enemies[0]                 // error: a bare 'var' of a place: write 'copy' or '&'
```

| Binding | Like the parameter | What it does |
| --- | --- | --- |
| `let x = place` | `_ x: T` | Borrows `place` shared: nothing changes, moves or destroys it while `x` is used |
| `var x = &place` | `_ x: mutable T` | Borrows `place` mutably: nothing reaches it but through `x` while `x` is used |
| `owned let x = place`, `owned var x = place` | `_ x: owned T` | Moves the value out of `place` |
| `let x = copy place`, `var x = copy place` | | Makes a copy of a copyable value |

**A bare `var x = place` is an error.** Say which you want: a copy, a move, or a change in place. One exception is a `const` of a copyable type, which a `var` takes as a new value, as chapter 2 showed ([01](../spec/01-values-and-ownership.md#constants)). A widening conversion makes a new value too, as in `var total: Int = small` ([01](../spec/01-values-and-ownership.md#conversions)).

**A binding of a value owns it**, with no `owned` written. A call's result, a literal and `copy place` are values, so `let mesh = loadMesh()` owns its mesh.

**A `let` of a stored field or an element is another name for the place, not a snapshot of it** ([01](../spec/01-values-and-ownership.md#what-a-let-of-a-place-sees)). In Swift, `let before = e.hp` copies. In Rayo it borrows, so the field can't change while `before` is used:

```swift
func hit(_ e: mutable Enemy, by amount: Float) {
    let before = e.hp
    e.hp -= amount                 // error: 'e.hp' is borrowed by 'before' (used below)
    log("hp \(before) to \(e.hp)")
}
```

Writing `let before = copy e.hp` keeps the old value, and the function compiles. A `let` of a computed property, such as `e.isDead`, owns the value its `get` returns.

**Conditions and loops bind the same way** ([01](../spec/01-values-and-ownership.md#conditions-and-patterns)). With `var target: Enemy?`, `if let t = target` reads the enemy it holds, and `if var t = &target` changes that enemy in place. `for e in enemies` reads each element where it is, and `for var e in &enemies` changes each one in place ([04](../spec/04-types.md#iteration)).

## How long a borrow lasts

**A borrow lasts until its last use, not to the end of its scope**, as in Rust ([01](../spec/01-values-and-ownership.md#how-long-a-borrow-lasts)). So the opening's code compiles once `boss` is done before the append:

```swift
var boss = &enemies[0]
damage(&boss, by: 10)                        // the last use of 'boss': its borrow ends here
enemies.append(Enemy(pos: [0, 0, 9]))        // fine: nothing borrows 'enemies' any more
```

**A call's borrows begin when the call does, and last until it returns** ([01](../spec/01-values-and-ownership.md#evaluation-order-and-when-a-calls-borrows-begin)). A call first evaluates its receiver and its arguments, left to right. Then it begins, and every borrow it passes begins with it. So an argument can read a place that the call then lends for change:

```swift
var ids = List<Int>()
ids.append(ids.count)             // fine: 'ids.count' is read, and done, before 'append' borrows 'ids'
```

## The law of exclusivity

**While a place is borrowed mutably, nothing else touches it, and while it is borrowed shared, nothing changes it.** This is the **law of exclusivity** ([01](../spec/01-values-and-ownership.md#the-law-of-exclusivity)). Moving a value out of a place, assigning the place and destroying it all count as changes.

The simplest break is one call that both changes and reads a place:

```swift
heal(&boss, from: boss)            // error: 'boss' is lent for change and read by one call
heal(&boss, from: copy boss)       // fine: the copy is made before the call begins
```

The classic break is changing a collection while a loop walks it. In C++, a `push_back` inside a range `for` can leave the loop's iterator pointing at freed memory. In Rayo, the loop borrows the list until it ends:

```swift
for e in enemies {
    if e.hp > 300 {
        enemies.append(Enemy(pos: copy e.pos))       // error: 'enemies' is borrowed by the loop
    }
}
```

The fix is to gather the new enemies in a list of their own, and add them once the loop is done:

```swift
var spawns = List<Enemy>()
for e in enemies {
    if e.hp > 300 { spawns.append(Enemy(pos: copy e.pos)) }     // another list: fine
}
for s in consume spawns { enemies.append(s) }                   // the first loop has ended
```

`e.pos` is a place in the list, so the new enemy takes `copy e.pos`. Without `copy`, the primary initializer would try to move it out of the list. `for s in consume spawns` moves the list into the loop, which hands each enemy over, so `append` can take it ([04](../spec/04-types.md#iteration)).

**The compiler checks the law one function at a time, in every build, at no run-time cost.** A few kinds of state are checked at run time instead, and each says so in its type or declaration, such as an object behind a `UniquePointer` ([Handles and objects](05-handles-and-objects.md)). `unsafe` code isn't checked at all ([01](../spec/01-values-and-ownership.md#state-that-other-code-can-change)).

## Which places overlap

**The law applies to every place that overlaps the one borrowed** ([01](../spec/01-values-and-ownership.md#which-places-overlap)). Two places **overlap** when one contains the other, or when they may be the same place. So `world` and `world.enemies` overlap.

**Two stored fields of one value don't overlap.** So a function can lend two fields of one struct for change at once:

```swift
struct Player(var pos: Vec3, var hp: Float = 100)
struct World(var player: Player, var enemies: List<Enemy>)

func brawl(_ player: mutable Player, _ enemies: mutable List<Enemy>) { ... }

func update(_ world: mutable World) {
    brawl(&world.player, &world.enemies)               // fine: two different fields
    for var e in &world.enemies {
        e.vel = world.player.pos - e.pos               // fine: the loop borrows only 'world.enemies'
    }
}
```

This holds for stored fields only. A computed property is an access to the whole value, whatever it returns. Places where writing one can change another count as one too, such as the members of a union and the lanes of a SIMD vector. A `Vec3`'s `x`, `y` and `z` are stored fields, so they don't overlap.

**Two elements of one collection do overlap**, since `enemies[i]` and `enemies[j]` may be the same enemy. A subscript is an access to the whole collection, so even `enemies[0]` and `enemies[1]` overlap. An inline array is the exception: its elements at indices known to differ, such as `a[0]` and `a[1]`, are disjoint.

**To use two elements at once, ask for both in one subscript**, which checks at run time that they differ ([01](../spec/01-values-and-ownership.md#two-elements-of-one-collection)):

```swift
heal(&enemies[i], from: enemies[j])          // error: enemies[i] and enemies[j] may be one enemy
if var (patient, medic) = &enemies[i, j] {   // nil when i == j
    heal(&patient, from: medic)
}
enemies.swapAt(i, j)                         // swaps two elements in one call
```

An index out of bounds still panics, as it does in `enemies[i]`.

## Lending with `&`

**`&` marks every place lent for change, in a call, a binding or a loop** ([01](../spec/01-values-and-ownership.md#lending-a-place-for-change)). The ones you meet first are:

- a `mutable` argument, as in `damage(&boss, by: 10)`;
- a `var` that binds a place, as in `var boss = &enemies[0]` or `if var t = &target`;
- a loop that changes the elements it visits, as in `for var e in &enemies`;
- a `when` subject that is a place, when a pattern has a `var` part, as in `when &order { .moveTo(var p) -> p.y = 0; else -> {} }`.

The receiver of a `mutating` method is the exception, as above, since the call's form shows the change. That is why `&` is required: reading a call or a loop, you see every place it borrows to change.

**Leaving `&` out is an error, and so is writing it where nothing is lent for change:**

```swift
damage(boss, by: 10)                    // error: a mutable argument needs '&'
for var e in enemies { e.hp = 0 }       // error: the loop changes the elements, so 'enemies' needs '&'
var fresh = &Enemy(pos: .zero)          // error: a new value is lent to no one, so it takes no '&'
```

### Changeable places

**Only a changeable place can be changed, or lent with `&`** ([01](../spec/01-values-and-ownership.md#changeable-places)). The **changeable** places you meet most are:

- a `var` that owns its value;
- the place that a `var x = &place` names, through `x`;
- a `mutable` or `owned` parameter, and `self` in a `mutating` method;
- a temporary, such as a call's result;
- a `var` field or an element of a changeable place.

**Everything else is read-only, and so is whatever is reached through it**: a `let`, a borrowed parameter, `self` in a plain method, a `let` field and a `const`.

```swift
let grunt = Enemy(pos: [0, 0, 5])
damage(&grunt, by: 10)                  // error: 'grunt' is a 'let', so it can't be changed

func punish(_ e: Enemy) {
    damage(&e, by: 10)                  // error: 'e' is borrowed, so 'punish' can't change it
}
func punish(_ e: mutable Enemy) {
    damage(&e, by: 10)                  // fine: lends the caller's enemy on
}
```

**Some state changes whatever holds it.** An object changes under run-time checks ([Handles and objects](05-handles-and-objects.md)), and a `Synchronized` value, such as a mutex, through its own locking ([Concurrency](07-concurrency.md)).

## No annotations to write

**A borrow never outlives the function that makes it, except as that function's signature says** ([01](../spec/01-values-and-ownership.md#the-law-of-exclusivity)). So the compiler checks each function on its own, from its body and the signatures of the functions it calls.

Every borrow in this chapter ends inside a function:

- A binding's borrow ends at the binding's last use.
- A borrowed or `mutable` argument is borrowed until the call returns, and the function can't keep it.

So a signature tells a caller all it needs: which arguments the call reads, which it changes and which it takes. Nothing has to say how long a borrow lasts, and none of this chapter's code does.

**A borrow outlives a call only inside a view**: a value, such as a `Span`, that borrows memory something else owns. None of this chapter's types is or holds one. A view is how a function hands back part of a list without copying it. In Rust, a function that returns a borrow of one of two arguments needs an annotation such as `'a` to say which. Chapter 4 covers views and what a result may borrow ([Views](04-views.md)).

## In the spec

- [01 Parameters](../spec/01-values-and-ownership.md#parameters): the three conventions, `self` in methods, default arguments, and when a borrowed argument is the caller's place.
- [01 Evaluation order](../spec/01-values-and-ownership.md#evaluation-order-and-when-a-calls-borrows-begin): the order a call works out its parts, and when its borrows begin and end.
- [01 Bindings](../spec/01-values-and-ownership.md#bindings): every form of binding, what a `let` of a place sees, how long a borrow lasts, and how conditions and patterns bind.
- [01 Changeable places](../spec/01-values-and-ownership.md#changeable-places): every changeable place, and the four exceptions, such as objects and `unsafe` code.
- [01 Lending a place for change](../spec/01-values-and-ownership.md#lending-a-place-for-change): every place that takes `&`, and how `&` picks a method's mutable form.
- [01 The law of exclusivity](../spec/01-values-and-ownership.md#the-law-of-exclusivity): which places overlap, two elements at once, and the state other code may change.
- [04 Iteration](../spec/04-types.md#iteration): how a `for` loop borrows its sequence, and the iterators behind it.
