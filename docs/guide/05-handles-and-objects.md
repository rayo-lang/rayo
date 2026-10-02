# 5 · Handles and objects

Your enemies now chase players. Each enemy keeps its target from one frame to the next, and a player can leave the game at any time. The game's menus are a tree of widgets, where each widget knows its parent and can move to a new one.

```cpp
struct Enemy  { Vec3 pos; Player* target; };       // dangles once the player is deleted
struct Widget { Widget* parent; std::vector<std::unique_ptr<Widget>> children; };
```

Each struct keeps a link past the end of the function that made it. A view can't be that link, since a view stays inside the scope that lent it ([Views](04-views.md)). A raw pointer dangles once its target is gone, as above. An index into a list may come to name another player, and a reference-counted pointer keeps a player alive after the player leaves.

Rayo gives you two links that are checked each time they are used, and this chapter teaches both:

```swift
struct Player(var pos: Vec3, var hp: Float = 100)
struct Enemy(
    var pos: Vec3,
    var vel: Vec3 = .zero,
    var hp: Float = 100,
    var target: Handle<Player>?,                       // a handle into a pool of players
)

struct Widget(
    var parent: WeakPointer<Widget>?,                  // a link that reads nil once its widget is gone
    var children = List<UniquePointer<Widget>>(),      // the child widgets, each owned here
    var visible = true,
)
```

## Three tiers of checking

**Rayo checks each pattern in the cheapest tier that can check it** ([01](../spec/01-values-and-ownership.md#tiers-of-checking)):

- **Static.** Moves, borrows and views, which chapters 2 to 4 covered. The compiler checks them inside one function body, at no cost when the program runs.
- **Dynamic.** Handles, objects and the other links that a value may store, and a few kinds of state, such as thread-locals and locks. Each use is checked when it runs: a stale link reads `nil` or panics instead of dangling, and conflicting uses panic or wait instead of racing.
- **Unsafe.** Raw pointers and calls into C, which nothing checks ([C and compile time](08-c-and-compile-time.md)).

**A pattern the compiler can't prove moves to the dynamic tier, never into `unsafe`.** A link that a struct keeps can outlive the function that stored it, so no one function body can check it. Rayo doesn't forbid such a link: it checks the link at each use. The check shows in the type: a checked link to a player is a `Handle<Player>`.

Code in the first two tiers is **safe code**, and it has no undefined behavior.

## Pools and handles

**A `Pool<T>` owns its elements, and a `Handle<T>` names one of them** ([03](../spec/03-handles-and-objects.md#pools-and-handles)). `insert` moves a value in and returns its handle:

```swift
var players = Pool<Player>(capacity: 8)
let p1 = players.insert(Player(pos: .zero))            // p1: Handle<Player>
var grunt = Enemy(pos: [5, 0, 5], target: copy p1)    // the enemy keeps a copy of the handle
```

A **handle** is 8 bytes and copyable, so you store copies of it anywhere: in fields, in lists, as map keys. `Handle<Player>?` is 8 bytes too, since `nil` is all zero bits, which no handle is. A primary initializer takes each field's value as its own, so the code passes `copy p1` to keep `p1`.

**`pool[h]` is an optional: the element, or `nil` once it is removed.** It is a projection, so it reaches the element where it lies in the pool and never copies it ([02](../spec/02-views-and-dependencies.md#projections-read-and-modify-accessors)):

```swift
players[p1]?.hp -= 10                          // changes the player in place, or does nothing if it is gone
if let p = players[p1] { log("hp \(p.hp)") }   // looks at the player in place
if var p = &players[p1] { p.pos.y += 1 }       // changes it through 'p'
let hp = players[p1]?.hp ?? 0                  // its hp, or 0
let sure = players[p1]!                        // panics if it is gone
```

**Removing an element makes every copy of its handle stale at once, and a stale handle reads `nil`:**

```swift
players.remove(p1)                             // the player leaves the game
let gone = players[p1] == nil                  // true, and so is players[grunt.target!] == nil
```

`take(h)` is the other way out: it moves the element out of the pool and hands it to you, as an optional.

**A stale handle never names a later element.** A handle holds a slot's index and a **generation**, which tells apart the elements that use that slot over time. A slot whose generation would wrap around is never used again. So a handle to a player who left reads `nil` forever, even once a new player takes the slot.

So code that follows a handle deals with `nil`, and the code that removes a player needs to know nothing about who links to it. Below, `guard` binds as `if` does, and its `else` must leave the scope, here with `continue` ([04](../spec/04-types.md#matching-with-when-and-choosing-with-if)):

```swift
func chase(_ enemies: mutable Pool<Enemy>, _ players: Pool<Player>, dt: Float) {
    for var e in &enemies {
        guard let t = e.target, let p = players[t] else { continue }   // no target, or it left
        e.pos += (p.pos - e.pos).normalized * dt
    }
}
```

A pool stores its elements densely, side by side, so a loop over the pool runs over them with no gaps. `for (h, e) in enemies.entries` gives each element's handle as well.

### Removals move elements

**A removal may move the pool's last element into the hole it leaves.** That keeps the elements dense, and a handle still finds its element after the move. A borrow of the element itself would not. As with any collection, a borrow of one element borrows the whole pool, so nothing changes the pool while the borrow is used:

```swift
let p2 = players.insert(Player(pos: [4, 0, 0]))
let p3 = players.insert(Player(pos: [8, 0, 0]))
let p = players[p2]!                           // borrows the player where it lies, inside the pool
players.remove(p3)                             // error: 'players' is borrowed by 'p' (used below)
log("hp \(p.hp)")
```

`players[p2]` borrows the pool for as long as `p` is used, as any borrow of a place does ([Borrowing](03-borrowing.md)). Keep the handle instead, and look the element up again after the removal:

```swift
players.remove(p3)
if let p = players[p2] { log("hp \(p.hp)") }   // p2 still finds its player, wherever it moved
```

A loop borrows the pool the same way, so it can't remove from it, whatever kind of pool it is. Collect the handles, and remove them after the loop:

```swift
var dead = List<Handle<Enemy>>()
for (h, e) in enemies.entries where e.hp <= 0 { dead.append(h) }   // 'h' is the loop's own handle, so it moves in
for h in dead { enemies.remove(h) }
```

## Objects and weak pointers

**A `UniquePointer<T>` owns one value, its object, and any number of `WeakPointer<T>`s link to it** ([03](../spec/03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)). The owner is move-only. A **weak pointer** is 8 bytes and copyable, so you can store as many as you like:

```swift
var menu = UniquePointer(Widget())                     // the one owner of a new widget
let m: WeakPointer<Widget> = menu.weak()               // a link to it
menu.value.children.append(UniquePointer(Widget(parent: menu.weak())))
```

**A pool suits many values of one type that a loop runs over, as enemies are.** An object suits a value that stands on its own and that other values point at, such as a widget or a renderer.

**Through the owner, `value` is the object itself. Through a weak pointer, it is an optional**, which reads `nil` once the object is destroyed. So a weak pointer never dangles:

```swift
menu.value.visible = false                     // the owner keeps the object alive: no optional
m.value?.visible = true                        // nil, and skipped, if the menu is gone
if var w = &m.value { w.visible = true; w.parent = nil }
m.value!.visible = false                       // panics if the menu is gone
if m.value == nil { log("menu closed") }       // checks only that the menu lives
```

**An object's value may change through any of its links**, even a `let` one, since each access is checked when it runs ([below](#dynamic-exclusivity)). Using a weak pointer never makes a second owner: the object still has exactly one.

### Moving an owner

**Moving an owner never moves its object, so its weak pointers keep working.** Reparenting a widget moves its owner from one list to another:

```swift
var toolbar = UniquePointer(Widget())
let save = menu.value.children[0].weak()               // a link to the menu's first child
var moved = menu.value.children.remove(at: 0)          // its owner leaves the menu's list
moved.value.parent = toolbar.weak()
toolbar.value.children.append(moved)                   // and joins the toolbar's
save.value?.visible = true                             // still the same widget
```

### Objects stay on their home thread

**An object is used and destroyed only on the thread that made it, its home thread** ([03](../spec/03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)). `UniquePointer` and `WeakPointer` aren't `Sendable`, so no value that holds one moves to another thread or is lent to one ([Concurrency](07-concurrency.md)). So an object's checks never synchronize with another thread. Data that several threads own together lives behind a reference-counted `Shared<T>` instead ([Memory and allocators](06-memory-and-allocators.md)), and chapter 7 shows the other ways threads share data ([Concurrency](07-concurrency.md)).

## Dynamic exclusivity

**Each access to an object takes a mark, and an access that conflicts with a live one panics** ([03](../spec/03-handles-and-objects.md#dynamic-exclusivity)). It is the law of exclusivity from chapter 3, checked at run time:

- **A read access**, such as a `let` binding or a call to a plain method, holds a shared mark. Any number may be live at once.
- **A modify access**, such as an assignment, a `var` binding of `&` or a `mutating` call, holds an exclusive mark. No other access may be live with it.
- **Each mark lasts until the last use of what depends on the access**, as a borrow does ([02](../spec/02-views-and-dependencies.md#rule-6-dynamic-accesses)). Comparing a weak pointer's `value` with `nil` takes no mark.

Two weak pointers to one object are aliases the compiler can't see. Here the attacker and the target may be the same fighter, as when a fighter's own spell hits it:

```swift
struct Fighter(var hp: Float = 100, var stamina: Float = 100)

func attack(_ attacker: WeakPointer<Fighter>, _ target: WeakPointer<Fighter>) {
    guard var a = &attacker.value else { return }      // a modify access, held while 'a' is used
    target.value?.hp -= 10                             // panics when both name one fighter: 'a' holds its mark
    a.stamina -= 10
}
```

**The panic comes before the conflicting access touches the value**, so aliased links never corrupt it. The same check catches an observer that calls back into the object that is notifying it, when either one changes the object.

**Keep each access short, and code that may alias works.** Here each access ends with its statement, since nothing uses it after:

```swift
func attack(_ attacker: WeakPointer<Fighter>, _ target: WeakPointer<Fighter>) {
    attacker.value?.stamina -= 10                      // this access ends here
    target.value?.hp -= 10                             // fine, even when both name one fighter
}
```

A `let` of an object's value holds its read access the same way, so changing the object while the `let` is still used panics ([01](../spec/01-values-and-ownership.md#what-a-let-of-a-place-sees)). Fighters kept in a pool instead need no marks: `&fighters[h1, h2]` lends two of them at once, and is `nil` when both handles name one fighter or either is stale ([01](../spec/01-values-and-ownership.md#two-elements-of-one-collection)).

## Destroying an object

**Dropping or overwriting the owner destroys the object at once** ([03](../spec/03-handles-and-objects.md#destroying-an-object)). Its `deinit` runs, and from then every weak pointer to it reads `nil`. Like a handle, a weak pointer holds a generation, so it never names an object made later.

Resetting the arena an object lives in destroys it too, and its owner is then stale: an access through it panics ([03](../spec/03-handles-and-objects.md#objects-in-arenas-and-other-allocators)). Chapter 6 covers arenas ([Memory and allocators](06-memory-and-allocators.md)).

**Destroying an object while an access to it is live panics**, since its `deinit` would run under code that still uses it. So a widget can't destroy itself from inside its own method:

```swift
extension Widget {
    mutating func closeMenu() { parent!.value!.children.removeAll() }   // destroys every item, this one included
}

let button = toolbar.value.children[0].weak()
button.value!.closeMenu()                // panics: the widget is destroyed while 'closeMenu' still runs on it
toolbar.value.children.removeAll()       // instead: no child is in use, so each one's deinit runs here
```

A widget that wants to close records that, and the code that holds its owner removes it once the access has ended.

**A weak pointer owns nothing, so a cycle that runs through one keeps nothing alive.** Each widget links to its parent, and its parent owns it, yet dropping `menu` destroys the whole tree.

Owners can still form a cycle: a widget moved under one of its own children would end up owning itself, and would live until its thread ends. Code that reparents checks for that first.

## Pinning for C

**A pin keeps a value at its address, for C, for as long as the pin lives** ([03](../spec/03-handles-and-objects.md#pinning-for-c)):

- **An object.** `menu.pin()` on its owner returns a `LocalPin<Widget>`, which stays on the object's home thread.
- **A `StablePool` element.** A `StablePool` never moves its elements, so `stablePool.pin(h)` returns a `Pin<T>?`, which is `nil` for a stale handle.
- **Not a `Pool` element.** A dense `Pool` can't pin, since a removal moves its elements.

While a pin lives, its memory is never freed or reused. Destroying a pinned object still makes its weak pointers read `nil` at once, but its `deinit` waits for the last pin to drop. The address itself, `pin.address`, is a raw pointer that only `unsafe` code reads, and chapter 8 hands it to C ([C and compile time](08-c-and-compile-time.md)).

## In the spec

- [01 Values and ownership](../spec/01-values-and-ownership.md#tiers-of-checking): the three tiers, what each checks and what it costs.
- [02 Views and dependencies](../spec/02-views-and-dependencies.md#rule-6-dynamic-accesses): how long an access to an object lasts, and what depends on it.
- [02 Views and dependencies](../spec/02-views-and-dependencies.md#projections-read-and-modify-accessors): `pool[h]` as an optional projection.
- [03 Handles and objects](../spec/03-handles-and-objects.md): pools and handles, objects and weak pointers, dynamic exclusivity, destruction, objects in arenas, weak pointers as bits for C, and pins.
- [07 Concurrency](../spec/07-concurrency.md#what-may-cross-threads-sendable): why objects stay on their home thread.
- [10 Errors and safety](../spec/10-errors-and-safety.md#what-panics): every panic the dynamic tier can raise.
