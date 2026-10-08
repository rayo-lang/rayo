# 5 · Handles and objects

Your enemies now chase players. Each enemy keeps its target from one frame to the next, and a player can leave the game at any time. The game's menus are a tree of widgets, where each widget knows its parent and can move to a new one. In C++ you might write:

```cpp
struct Enemy  { Vec3 pos; Player* target; };       // dangles once the player is deleted
struct Widget { Widget* parent; std::vector<std::unique_ptr<Widget>> children; };
```

The enemy needs a link it can use in a later frame. The widget needs one after its parent moves elsewhere. Each familiar choice has a cost:

- a view stays within the scope that lent it, so it cannot serve as this long-lived link ([Views](04-views.md));
- a raw pointer can dangle once its target is gone;
- an index into a list may come to name another player;
- a reference-counted pointer keeps a player alive after the player leaves.

Rayo gives you two links that are checked each time you use them:

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

**Rayo checks each pattern of memory use in the cheapest of three tiers that can check it** ([01](../spec/01-values-and-ownership.md#tiers-of-checking)):

- **Static.** Moves, borrows and views. The compiler checks them inside one function body, at no cost when the program runs.
- **Dynamic.** Handles, objects and the other links that a value may store, and a few kinds of state, such as thread-locals and locks. Each use is checked when it runs: a stale link reads `nil` or panics instead of dangling, and conflicting uses panic or wait instead of racing.
- **Unsafe.** Raw pointers and calls into C, which nothing checks ([C and compile time](08-c-and-compile-time.md)).

**A pattern the compiler can't prove moves to the dynamic tier, never into `unsafe`.** A link that a struct keeps can outlive the function that stored it, so no one function body can check it. Rayo checks the link at each use instead of forbidding it.

**You can see each dynamic check in the code.** It shows in a type, such as `Handle<Player>`, or for a thread-local, in its declaration.

**Safe code is the code of the first two tiers, and it has no undefined behavior.**

## Pools and handles

```swift
var players = Pool<Player>(capacity: 8)
let p1 = players.insert(Player(pos: .zero))            // p1: Handle<Player>
var grunt = Enemy(pos: [5, 0, 5], target: copy p1)    // the enemy keeps a copy of the handle

players[p1]?.hp -= 10                          // changes the player in place, or does nothing if it's gone
if var p = &players[p1] { p.pos.y += 1 }       // changes it through 'p'
let hp = copy players[p1]?.hp ?? 0             // a copy of its hp, or 0
let sure = borrow players[p1]!                 // panics if it's gone

players.remove(p1)                             // the player leaves the game
let gone = players[grunt.target!] == nil       // true: every copy of the handle is stale

func chase(_ enemies: mutable Pool<Enemy>, _ players: Pool<Player>, dt: Float) {
    for e in &enemies {
        guard e.target != nil, let p = players[e.target] else { continue }   // no target, or it left
        e.pos += (p.pos - e.pos).normalized * dt
    }
}
```

`Pool<T>` owns its elements, while `Handle<T>` names one ([03](../spec/03-handles-and-objects.md#pools-and-handles)). `insert` moves the player into `players` and gives back `p1`, a handle the enemy can keep. The handle is eight bytes and copyable, so other enemies can keep the same target without owning the player. An optional handle takes eight bytes too: all-zero bits mean `nil`.

Looking up `players[p1]` reaches the player where it sits in the pool; it does not copy the player ([02](../spec/02-views-and-dependencies/projections-and-accessors.md#projections-read-and-modify-accessors)). The lookup gives `nil` after the player leaves. In `chase`, `guard` skips an enemy with no target or with a target that has left. `guard` keeps `p` bound after the condition, and its `else` must leave the current scope ([04](../spec/04-types/enums.md#matching-with-when-and-choosing-with-if)).

Removing a player makes every copy of its handle **stale**. A handle stores a slot index and a **generation**, which distinguishes players that occupy the same slot at different times. Once removed, the old handle continues to read `nil`, even if another player takes that slot. Code that removes a player need not find every enemy that targeted it. If you need to take the player out rather than destroy it, `take(h)` removes it and returns it as an optional.

The pool keeps its elements densely packed, so a loop visits them without gaps. `enemies.entries` also gives the loop each element's handle.

### Removals move elements

```swift
let p2 = players.insert(Player(pos: [4, 0, 0]))
let p3 = players.insert(Player(pos: [8, 0, 0]))
let p = borrow players[p2]!                    // borrows the player where it lies, inside the pool
players.remove(p3)                             // error: 'players' is borrowed by 'p' (used below)
log("hp \(p.hp)")
```

**A removal may move the pool's last element into the hole it leaves.** That keeps the elements dense. A handle still finds its element after the move, but a borrow of the old spot wouldn't.

**A borrow of one element borrows the whole pool**, as with any collection, so nothing changes the pool while the borrow is in use ([Borrowing](03-borrowing.md)).

**Keep the handle instead, and look the element up again after the removal:**

```swift
players.remove(p3)
if let p = players[p2] { log("hp \(p.hp)") }   // p2 still finds its player, wherever it moved

var dead = List<Handle<Enemy>>()
for (h, e) in enemies.entries where e.hp <= 0 { dead.append(h) }   // 'h' is the loop's own handle, so it moves in
for h in dead { enemies.remove(h) }
```

**A loop borrows the pool the same way, so it can't remove from it.** Collect the handles, and remove them after the loop.

## Objects and weak pointers

```swift
var menu = UniquePointer(Widget())                     // the one owner of a new widget
let m: WeakPointer<Widget> = menu.weak()               // a link to it
menu.value.children.append(UniquePointer(Widget(parent: menu.weak())))

menu.value.visible = false                             // through the owner: the widget itself
m.value?.visible = true                                // nil, and skipped, if the menu is gone
if var w = &m.value { w.visible = true; w.parent = nil }
m.value!.visible = false                               // panics if the menu is gone
if m.value == nil { log("menu closed") }               // checks only that the menu lives
```

**A `UniquePointer<T>` owns one value, and any number of `WeakPointer<T>`s link to it** ([03](../spec/03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)). The value it owns is its **object**.

**The owner is move-only, so an object has exactly one.** Using a weak pointer never makes a second owner.

**A weak pointer is 8 bytes and copyable**, so you can store as many as you like.

**Through the owner, `value` is the object itself.** The owner keeps the object alive, so there is no optional.

**Through a weak pointer, `value` is an optional, which reads `nil` once the object is destroyed.** So a weak pointer never dangles.

**An object's value may change through any of its links, even a `let` one**, since each access is checked when it runs ([below](#dynamic-exclusivity)).

**Use a pool for many values of one type that a loop runs over, such as enemies.** Use an object for a value that stands on its own and that other values point at, such as a widget or a renderer.

### Moving an owner

```swift
var toolbar = UniquePointer(Widget())
let save = menu.value.children[0].weak()               // a link to the menu's first child
var moved = menu.value.children.remove(at: 0)          // its owner leaves the menu's list
moved.value.parent = toolbar.weak()
toolbar.value.children.append(moved)                   // and joins the toolbar's
save.value?.visible = true                             // still the same widget
```

**Moving an owner never moves its object, so its weak pointers keep working.** To reparent a widget, you move its owner from one list to another.

### Objects stay on their home thread

**An object is used and destroyed only on the thread that made it, its home thread** ([03](../spec/03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)).

**`UniquePointer` and `WeakPointer` aren't `Sendable`**, the protocol of types whose values may cross threads. So no value that holds one moves to another thread, or is lent to one ([Concurrency](07-concurrency.md)), and an object's checks never synchronize with another thread.

**Data that several threads own together lives behind a reference-counted `Shared<T>` instead** ([Memory and allocators](06-memory-and-allocators.md)). Chapter 7 shows the other ways threads share data ([Concurrency](07-concurrency.md)).

## Dynamic exclusivity

**Each access to an object takes a mark, and an access that conflicts with a live one panics** ([03](../spec/03-handles-and-objects.md#dynamic-exclusivity)). It's the law of exclusivity from chapter 3, checked at run time, since the compiler can't see which weak pointers name one object:

- **A read access**, such as a `let` binding or a call to a plain method, holds a shared mark. Any number may be live at once.
- **A modify access**, such as an assignment, a `var` binding of `&` or a `mutating` call, holds an exclusive mark. No other access may be live with it.
- **Each mark lasts until the last use of whatever depends on the access**, as a borrow does ([02](../spec/02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)).

**Comparing a weak pointer's `value` with `nil` takes no mark**, so it never conflicts.

**Two weak pointers to one object are aliases the compiler can't see.** Here the attacker and the target may be the same fighter, as when a fighter's own spell hits it:

```swift
struct Fighter(var hp: Float = 100, var stamina: Float = 100)

func attack(_ attacker: WeakPointer<Fighter>, _ target: WeakPointer<Fighter>) {
    guard var a = &attacker.value else { return }      // a modify access, held while 'a' is used
    target.value?.hp -= 10                             // panics when both name one fighter: 'a' holds its mark
    a.stamina -= 10
}
```

**The panic comes before the conflicting access touches the value**, so aliased links never corrupt it.

**The same check catches an observer that calls back into the object notifying it**, when either one changes the object.

**Keep each access short, and code that may alias works.** An access that nothing uses afterwards ends with its statement:

```swift
func attack(_ attacker: WeakPointer<Fighter>, _ target: WeakPointer<Fighter>) {
    attacker.value?.stamina -= 10                      // this access ends here
    target.value?.hp -= 10                             // fine, even when both name one fighter
}
```

**A `let` that borrows an object's value holds a read access the same way**, so changing the object while the `let` is still in use panics ([01](../spec/01-values-and-ownership/bindings.md#what-a-borrowing-let-sees)).

**Elements of a pool need no marks.** `&fighters[h1, h2]` lends two of them at once, and is `nil` when both handles name one fighter or either is stale ([01](../spec/01-values-and-ownership/exclusivity.md#two-elements-of-one-collection)).

## Destroying an object

**Dropping or overwriting the owner destroys the object at once** ([03](../spec/03-handles-and-objects.md#destroying-an-object)). Its `deinit` runs, and from then on every weak pointer to it reads `nil`.

**Like a handle, a weak pointer holds a generation, so it never names an object made later.**

**Resetting the arena an object lives in destroys it too.** Its owner is then stale, and an access through it panics ([03](../spec/03-handles-and-objects.md#objects-in-arenas-and-other-allocators)). Chapter 6 teaches arenas ([Memory and allocators](06-memory-and-allocators.md)).

**Destroying an object while an access to it is live panics**, since its `deinit` would run under code that still uses it. So a widget can't destroy itself from inside its own method:

```swift
extension Widget {
    mutating func closeMenu() { parent!.value!.children.removeAll() }   // destroys every item, this one included
}

let button = toolbar.value.children[0].weak()
button.value!.closeMenu()                // panics: the widget is destroyed while 'closeMenu' still runs on it
toolbar.value.children.removeAll()       // instead: no child is in use, so each one's deinit runs here
```

**To close itself, a widget records that it wants to**, and the code that holds its owner removes it once the access has ended.

**A weak pointer owns nothing, so a cycle through one keeps nothing alive.** Each widget links to its parent, and its parent owns it, yet dropping `menu` destroys the whole tree.

**Owners can still form a cycle.** A widget moved under one of its own children would end up owning itself, and would live until its thread ends. Check for that before you reparent a widget.

## Pinning for C

**A pin keeps a value at one address for as long as the pin lives, so C can use that address** ([03](../spec/03-handles-and-objects.md#pinning-for-c)). You can pin an object or a `StablePool` element, but not a `Pool` element:

- **An object.** `menu.pin()` on its owner returns a `LocalPin<Widget>`, which stays on the object's home thread.
- **A `StablePool` element.** A `StablePool` never moves its elements, so `stablePool.pin(h)` returns a `Pin<T>?`, which is `nil` for a stale handle.
- **Not a `Pool` element.** A `Pool` can't pin, since a removal moves its elements.

**While a pin lives, its memory is never freed or reused.**

**Destroying a pinned object still makes its weak pointers read `nil` at once, but its `deinit` waits for the last pin to drop.**

**The address itself, `pin.address`, is a raw pointer that only `unsafe` code can read.** Chapter 8 hands it to C ([C and compile time](08-c-and-compile-time.md)).

## In the spec

- [01 Values and ownership](../spec/01-values-and-ownership.md#tiers-of-checking): the three tiers, what each checks and what it costs.
- [02 Views and dependencies](../spec/02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses): how long an access to an object lasts, and what depends on it.
- [02 Views and dependencies](../spec/02-views-and-dependencies/projections-and-accessors.md#projections-read-and-modify-accessors): `pool[h]` as an optional projection.
- [03 Handles and objects](../spec/03-handles-and-objects.md): pools and handles, objects and weak pointers, dynamic exclusivity, destruction, objects in arenas, weak pointers as bits for C, and pins.
- [07 Concurrency](../spec/07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable): why objects stay on their home thread.
- [10 Errors and safety](../spec/10-errors-and-safety/panics.md#what-panics): every panic the dynamic tier can raise.
