# Place and value properties

[02 · Views and dependencies](../02-views-and-dependencies.md)

A computed property or subscript gives part of a value a name of the type's choosing. Some of those names stand for storage the value already has, as an enemy's `hp` stands for a field inside its `stats`. Others stand for something that lies nowhere in memory, as an angle's degrees are worked out from its radians:

```swift
struct Enemy(var stats: Stats) {
    var hp: Int {                       // a place property: hands out its own storage
        borrow { stats.hp }
        mutate { &stats.hp }
    }
}

struct Angle(var radians: Float) {
    var degrees: Float {                // a value property: a copy out, a write-back through set
        get { radians * 180 / .pi }
        set { radians = newValue * .pi / 180 }
    }
}

enemy.hp -= 10                          // changes enemy.stats.hp where it lies
angle.degrees += 45                     // calls get, then set with the sum
```

**Every computed property or subscript is one of two kinds, fixed by its declaration and never by the code that uses it:**

- **A place property** hands out a place in storage, as `hp` does. It declares a `borrow`, which lends the place for reading, and may add a `mutate`, which lends it for change. Code uses the place as it would use a stored field, except to move out of it, and no accessor code runs once the caller has it.
- **A value property** computes a value and takes one back, as `degrees` does. It declares a `get`, which returns a value, and may add a `set`, which takes a new one. A change works on a copy, which `set` writes back.

A subscript counts as a property here, and wherever the spec names the two kinds: `list[i]` is a place property. A subscript may declare generic parameters, as a function does, so `box[as: Slider.self]` picks the type it hands out ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)).

**A declaration's accessors are one of these:**

- a `borrow`;
- a `borrow` and a `mutate`;
- a `get`;
- a `get` and a `set`.

A body with no accessor keyword returns a value, as a `get` does.

**The declaration fixes the kind, and what the property reaches limits the choice.** A property whose value lies in storage that `self` reaches, or that its declaration names, may be declared either kind ([below](#the-place-lies-in-its-sources)). A property with no such place can only be a value property, as for a value worked out on the spot, such as `degrees`.

**A property that must run code after a change is a value property, and that code goes in its `set`.** A place property hands out the place itself, so nothing of its own runs after the caller changes it.

**Two kinds of field are reached through a copy, as a value property is**, since neither is a place a view could reach:

- an imported C bitfield, whose bits share bytes with other fields ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums));
- an under-aligned field, at an address where a load or store of its type may fault ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)).

## Place properties: `borrow` and `mutate`

```swift
struct Pool<T>(…) {
    subscript(h: Handle<T>) -> T? {                              // hands out part of the pool, never of 'h' (below)
        borrow { if valid(h) { dense[slots[h.index].denseIndex] } else { nil } }
        mutate { if valid(h) { &dense[slots[h.index].denseIndex] } else { nil } }
    }
}

world.enemies[h]?.hp -= 10                   // the mutate accessor, with optional chaining
if var e = &world.enemies[h] { e.hp = 0 }
let pos = borrow world.enemies[h]!.pos       // the borrow accessor; '!' panics on a stale handle
```

**A `borrow` lends a place for reading, and a `mutate` lends it for change.** Each body hands out its place as a `get` body returns a value: as its single expression, or with `return`. A `mutate` body marks its place with `&`, as every place lent for change is marked ([01](../01-values-and-ownership/bindings.md#lending-a-place-for-change)). Nothing is copied or moved, so the caller reaches the place itself.

**The access ends at the last use of the place and of every value that depends on it**, as a borrow of a stored field does, and nothing runs then. So `world.enemies[h]?.hp -= 10` changes the element where it lies in the pool. A view of the place can outlive the statement that took it, as a view of a field can ([below](#what-a-place-depends-on)).

### The place lies in its sources

**A place property's place lies in its sources, which its declaration names.** A **source** is a place, or what a place borrows, that the handed-out place may be part of. By default the sources are `self` and what it borrows, as `where return borrows self` would name them, or static storage for a `static` property. So a subscript's arguments are only keys, as `h` is for `Pool`. A `where` item with `return` as its subject names the sources instead ([Precise dependencies (opt-in)](dependency-lifetimes.md#precise-dependencies-opt-in)):

- **`where return borrows x`**: the parameter `x`, `self` included, and what `x` borrows;
- **`where return outlives x`**: only what `x` borrows, such as the elements a span views ([below](#what-a-place-depends-on));
- **`where return borrows static`**: static storage.

Several items name several sources, and then `self` is a source only when an item names it:

```swift
extension Node {
    subscript(graft g: mutable Node) -> Node where return borrows g {   // hands out part of 'g', not of self
        borrow { g } mutate { &g }
    }
}
```

**A `mutate` hands out a place only in `self`, a `mutable` parameter, or what one of them views exclusively**, since only those are changeable places ([01](../01-values-and-ownership/bindings.md#changeable-places)).

**The compiler verifies that every place a body hands out lies in its sources.** It checks the place as rule 5 checks a result, restricted to the sources, whatever the place's type ([Rule 5: The callee side](dependency-absorption-and-accesses.md#rule-5-the-callee-side)). So the place must be reached from a source through stored fields, elements and other place properties. This is an error, since `other` is no source:

```swift
extension Inventory {
    subscript(from other: Inventory) -> Item { borrow { other.items[0] } }   // error: 'other' isn't a source
}
```

**The place is never one of these, since none is storage the caller could go on using:**

- a local, a temporary or an `owned` parameter's own storage, each of which ends when the body returns;
- the result of a value property's `get`, which is such a temporary;
- an imported bitfield or an under-aligned field, which is reached only through a copy (above);
- a place reached through a dynamic access the body begins, such as an object's `value`, since that access ends when the body returns ([Rule 6: Dynamic accesses](dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)).

**Only `unsafe` code can hand out a place reached through a raw pointer**, such as an element of a `List`'s buffer or a lock guard's protected value. That code promises that the place lies in storage its sources own or view, and stays there for as long as the place's dependencies last ([below](#what-a-place-depends-on)).

**From where the body names its place, the place is lent to the caller**: shared from a `borrow`, and exclusively from a `mutate`. So code that runs as the body exits, such as a `defer` block or a local's destruction, follows the law of exclusivity with it ([01](../01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)):

```swift
extension Inventory {
    var all: List<Item> {
        borrow { items }
        mutate {
            defer { items = List() }             // error: changes the place the body hands out
            return &items
        }
    }
}
```

### What a place depends on

**A place property's place depends on its sources, as a stored field depends on the value that holds it.** It depends on each source place that a `borrows` item names, or `self` by default, and on what each source borrows. A view taken from the place depends on the same:

```swift
struct Inventory(var items: List<Item>) {
    subscript(i: Int) -> Item { borrow { items[i] } mutate { &items[i] } }
}
func firstName(_ inv: Inventory) -> StringView { inv[0].name.view }   // fine: the view depends on 'inv', not on '0'
```

**The kinds are rule 3's**, since the accessor is a call ([Rule 3: Call results](dependency-projection-and-results.md#rule-3-call-results)). The place depends exclusively on each `mutable` source, and on `self` through a `mutate` when `self` is a source. It depends shared on every other source, and on no argument that isn't one. Each source's set keeps its own kinds. So `cur[graft: &spare]` depends exclusively on `spare` and what it holds, not on `cur`, and a `mutable` parameter that no item names, such as a log the accessor writes to, stays free.

**The place depends on a source place whatever the place's type.** The shallow and sealed exemptions spare a value a call returns, which can't reach a shallow argument's own bytes ([Shallow values](dependency-projection-and-results.md#shallow-values)). A place lies inside its source, so they never apply to it:

```swift
struct Pair(var a: Int, var b: Int) {
    var first: Int { borrow { a } mutate { &a } }
}
func leak() -> any Equatable {
    let p = Pair(a: 1, b: 2)
    return p.first                       // error: the view depends on local 'p', which is destroyed on return
}
```

**Each source place is the caller's place, never a bit copy**, since the place lies inside it ([01](../01-values-and-ownership/parameters.md#borrowed-arguments)).

**On an exclusive view type, a view of the place depends on the view variable itself** ([Rule 1: Projection](dependency-projection-and-results.md#rule-1-projection)), as on a `MutableSpan` or a `MutableRef`. So this result depends on `s`, and through it on what `s` views:

```swift
func label(_ s: mutable MutableSpan<Item>, _ i: Int) -> StringView { s[i].name.view }
```

**On a view type that `outlives` accepts, `where return outlives self` says the place is reached through what the view carries** ([Staying valid after a parameter moves on: `outlives`](dependency-lifetimes.md#staying-valid-after-a-parameter-moves-on-outlives)). So a view of a span's element depends on what the span views, not on the variable that holds the span.

### Optional places and tuples of places

A place property whose declared type is written `T?` is an **optional place property**: its body hands out either a place of type `T` or `nil`, as `Pool`'s subscript does for a stale handle. **Only the `?` written in the declaration makes an optional place property.** A place property whose type is written `Optional<T>`, or with a type alias of an optional, hands out a whole place of that enum type, such as a stored optional field. So `node.next = nil` and `node.next.take()` work through it.

**An optional place property, an optional chain, or a tuple of places, is a place only in its parts:**

- **An optional place property's place is the unwrapped `T`**: the `T` that `?.`, `!`, `x? = v`, `??`, a `let` or `var` condition or a pattern unwraps.
- **So is the place of an optional chain through a place**, since `a?.b` names the `b` inside `a`'s payload and no `B?` lies in memory.
- **A tuple of places is used element by element**, as a pattern binds them. It comes from a body that hands out several places at once, as `(&a, &b)`, or from `value[fields:]` ([09](../09-compile-time/reflection.md#tuples-field-lists-and-queries)).

**No such `T?` or tuple exists in memory, so none can be:**

- assigned as a whole;
- lent with `&` or bound as a place, except by a condition or pattern that unwraps or destructures it;
- used as a `mutating` or `consuming` receiver, such as `take()`;
- passed as an argument other than a copy.

**An optional place property or chain may still be compared with `nil`.** When `T` is copyable, one may also be copied wherever a copy is accepted ([01](../01-values-and-ownership/parameters.md#parameters)), as `copy target?.hp` does. `a ?? b` with an optional `b` needs that copy, since it hands on `a` whole ([04](../04-types/enums.md#optionals)).

### Places behind a run-time check

**The `value` of a `UniquePointer` or a `WeakPointer` is a place property that the language provides, and each access through it is a dynamic access** ([Rule 6: Dynamic accesses](dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). The language takes the object's mark as the access begins: a shared mark for a `borrow`, and an exclusive one for a `mutate` ([03](../03-handles-and-objects.md#dynamic-exclusivity)). It releases the mark itself when the access ends, at the last use of every value that depends on the access. No accessor code runs at either end.

**A type that needs code to run when an access ends hands out a guard instead**: a value whose `deinit` runs that code, as a lock's guard releases the lock ([Lock guards are released on the thread that took them](dependency-lifetimes.md#lock-guards-are-released-on-the-thread-that-took-them)). The guard's `value` is then an ordinary place property of the guard.

## Value properties: `get` and `set`

```swift
var a = Angle(radians: 0)
a.degrees = 90                               // calls set
a.degrees += 45                              // calls get, then set with the sum
var d = &a.degrees                           // calls get, lends the copy, then calls set once the access ends

struct Flags(var bits: UInt32) {
    var low: UInt16 { UInt16(truncating: bits) }      // a get: these 16 bits lie in no place of their own
}
```

**A `get` returns a value, and a `set` takes one.** A `set` receives the assigned value as an `owned` parameter named `newValue`. A binding of what a `get` returns owns it, with or without `borrow` ([01](../01-values-and-ownership/bindings.md#what-a-borrowing-let-sees)).

**Assignment calls `set`.** So does a compound assignment, since `a ⊕= b` is `a = a ⊕ b` ([05](../05-protocols-generics-and-closures/operators.md#operators)).

**Any other change calls `get`, lends the copy it returns, and calls `set` with that copy once the access ends.** Such changes include binding the property with `&`, passing it as a `mutable` argument, and calling a `mutating` method on it. Until then, the copy lives in a hidden local of the caller.

**The access is held until the last use of every value that depends on it**, as a dynamic access is ([Rule 6: Dynamic accesses](dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). So a view of the copy depends on the access, and `set` runs only once nothing uses the copy. **Such a view works like any view within the function, but can't leave it** ([Rule 5: The callee side](dependency-absorption-and-accesses.md#rule-5-the-callee-side)), since the access began in that function.

**Meanwhile the access keeps `self` and the subscript's arguments lent as it began them**, `self` exclusively, since `set` changes it. So what depends on the access depends on those places too, whatever the shallow rule, `outlives` or `copy` drops from its set.

**That `set` call is checked as if written there.** So the change is an error when the `get`'s result may depend on `self` or on a `mutable` argument of the access, which `set` changes while its `newValue` still views it.

**Both calls take the subscript's arguments**, worked out once when a compound assignment or another change calls `get` and then `set`. A borrowed or `mutable` argument is lent to each in turn, and a copyable `owned` one is copied for the `get`. So such an access is a compile error when an `owned` parameter's type is move-only, since one value can't move into two calls.

## Panics during a change

**A panic in the middle of a change leaves what a place property hands out as changed so far, and a value property as it was** ([10](../10-errors-and-safety/panics.md#panics)):

- **Through a place property**, code changes the storage itself. So every change made before the panic stays, exactly as if the code had written the field directly.
- **Through a value property**, `set` isn't called. The half-changed copy is destroyed instead, so the property keeps its old value.
- **Through an object's `value`**, a place property, the changes stay too. The language releases the object's mark as the panic leaves the frame that began the access, as it does when the access ends ([above](#places-behind-a-run-time-check)).

**Through an under-aligned field, a panic follows 04's rule for its temporary instead** ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)).

```swift
func drain(_ hp: mutable Int) { hp -= 10; precondition(hp > 0) }
func turn(_ deg: mutable Float) { deg += 90; precondition(deg < 360) }

drain(&enemy.hp)          // on a panic, enemy.stats.hp stays 10 lower
turn(&angle.degrees)      // on a panic, set never runs, so angle.radians is as it was
```

## Properties in protocols

**A protocol requires either a place property or a value property**, and a witness hands out what the requirement promises:

```swift
protocol Moving { var pos: Vec3 { borrow mutate } }     // a place: generic code may keep a view of it
protocol Aiming { var heading: Float { get set } }      // a value: a copy out, a write-back through set
```

**A place requirement carries its `where` clause, and a witness must satisfy it**, so its place depends on no more than the clause allows. So generic code can keep a view of a place requirement's place, as of a stored field.

**Accessors and stored fields meet requirements as follows:**

- **A place property meets a place requirement whose accessors it declares**: a `borrow` meets `{ borrow }`, and a `borrow` and a `mutate` meet either requirement.
- **A stored field meets a place requirement**, subject to [05](../05-protocols-generics-and-closures/protocols-and-generics.md#conformances)'s rules on `let`, hidden, static, `unsafe` and union-member fields. An under-aligned field or an imported bitfield is the exception, since it has no place to hand out.
- **A `get` meets `{ get }`, and a `get` and a `set` meet `{ get set }`.**
- **When the value's type is copyable, a stored field or a place property also meets `{ get }` and `{ get set }`.** Its place is copied for the `get`, and assigned for the `set`, so `{ get set }` needs a `mutate` or a `var` field. Generic code then changes a copy, as through any value property, so a panic before the `set` loses the change even though the witness is a place ([above](#panics-during-a-change)).
- **A value property never meets a place requirement**, since what its `get` returns lies in no storage that generic code could keep a view of.
- **An optional place property meets a place requirement only when the requirement's own declared type is written as an optional, `U?`**, so that generic code treats it as an optional place property too. It never meets one where an associated type or a type parameter turns out to be an optional, or where the requirement is written `Optional<U>`, which asks for a whole place.
- **A place property that hands out a tuple of places meets no place requirement.**
- **An optional place property, or one that hands out a tuple of places, meets `{ get }` but never `{ get set }`**, since it has no whole value that a `set` could write ([above](#optional-places-and-tuples-of-places)).

## The standard place properties

**The standard library's place properties have these sources:**

- Collection and pool subscripts, `Box.value`, `MutableRef.value`, every lock guard's `.value`, and a `MutableSpan`'s element places lie in `self` or what it borrows, the default.
- The place properties of `Span`, `StringView` and `Borrow` are `where return outlives self`.
- The `.value` of a `UniquePointer` or a `WeakPointer` is the language's own, and depends on its access ([above](#places-behind-a-run-time-check)).

**Properties that build a view are value properties**, such as `span`, sub-span ranges and an `SoA` column: each `get` returns a new view, which depends on what the call was given ([Rule 3: Call results](dependency-projection-and-results.md#rule-3-call-results)). `Span`'s and `StringView`'s range `get`s, `first` and `last` are `where return outlives self`, so their views depend on what the span views. An `SoA` column's view depends on its column alone ([04](../04-types/data-layout.md#struct-of-arrays-soat)).
