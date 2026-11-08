# Projections: `read` and `modify` accessors

[02 · Views and dependencies](../02-views-and-dependencies.md)

An accessor that **yields** a place instead of returning a value is a **projection**:

```swift
struct Pool<T>(…) {
    subscript(h: Handle<T>) -> T? where yield borrows self {   // yields the pool's own storage (below)
        read   { if valid(h) { yield dense[slots[h.index].denseIndex] } else { yield nil } }
        modify { if valid(h) { yield &dense[slots[h.index].denseIndex] } else { yield nil } }
    }
}

world.enemies[h]?.hp -= 10                   // modify projection plus optional chaining
if var e = &world.enemies[h] { e.hp = 0 }
let pos = borrow world.enemies[h]!.pos       // borrows through the read projection; '!' panics on a stale handle
```

**A `read` accessor lends a place for reading, and a `modify` accessor for changing.**

An accessor whose declared type is written `T?` is an **optional projection**, yielding either a place of type `T` or `nil`. **Only the `?` written in the declaration makes an optional projection.** An accessor whose type is written `Optional<T>`, or with a type alias of an optional, yields a whole place of that enum type, such as a stored optional field. So `node.next = nil` and `node.next.take()` work through it.

**An optional projection, an optional chain, or a tuple of places, is a place only in its parts:**

- **An optional projection's place is the unwrapped `T`**: the `T` that `?.`, `!`, `x? = v`, `??`, a `let` or `var` condition or a pattern unwraps.
- **So is the place of an optional chain through a place**, since `a?.b` names the `b` inside `a`'s payload and no `B?` lies in memory.
- **A tuple of places is used element by element**, as a pattern binds them. It comes from `yield (&a, &b)` or `value[fields:]` ([09](../09-compile-time/reflection.md#tuples-field-lists-and-queries)).

**No such `T?` or tuple exists in memory, so none can be:**

- assigned as a whole;
- lent with `&` or bound as a place, except by a condition or pattern that unwraps or destructures it;
- used as a `mutating` or `consuming` receiver, such as `take()`;
- passed as an argument other than a copy.

**An optional projection or chain may still be compared with `nil`.** When `T` is copyable, an optional projection or chain may also be copied wherever a copy is accepted ([01](../01-values-and-ownership/parameters.md#parameters)), as `copy target?.hp` does. `a ?? b` with an optional `b` needs that copy, since it hands on `a` whole ([04](../04-types/enums.md#optionals)).

**A `read` or `modify` accessor yields exactly once on every path that returns normally**, which the compiler checks, so the caller always gets one place. So an optional projection yields `nil` on the paths that have no place to yield. And `yield` stands only in a `read` or `modify` body itself, never where a loop could run it again, and never in one of these inside the body:

- a closure literal or a nested function;
- a local type's or extension's members;
- a `defer` block.

## Access-bound projections

**By default a projection is access-bound, since an accessor may yield a temporary:**

- a value computed on the spot;
- a bitfield's bits read out of its bytes ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums));
- an under-aligned field copied to an aligned place ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)).

An **access-bound** projection's accessor stays suspended at its `yield` until the last use of every value that depends on the access, as for a dynamic access ([Rule 6: Dynamic accesses](dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). So its frame, and the temporary in it, stay as they were while a view of the yield lives. Then it runs the code after the `yield`, such as a `modify`'s write-back.

**Meanwhile the accessor keeps `self` and its subscript arguments lent as the access began them**: shared for a `read`, and exclusively for a `modify` or a `get` and `set` change. So what depends on the access depends on those places too, whatever the shallow rule, `outlives` or `copy` drops from its set.

**A view of an access-bound projection works like any view within the function, but can't leave it** ([Rule 5: The callee side](dependency-absorption-and-accesses.md#rule-5-the-callee-side)), since the access began in that function, and rule 5 rejects a view of one.

## Storage projections

**An accessor declared `where yield borrows self` yields part of `self`'s storage**, so a view of it depends on `self`, as a view of a stored field does, and can outlive the access. Any `yield` item makes a **storage projection** of what the item names:

```swift
struct Flags(var bits: UInt32) {
    var low: UInt16 { read { yield UInt16(truncating: bits) } }    // access-bound: yields a temporary
}
struct Inventory(var items: List<Item>) {
    subscript(i: Int) -> Item where yield borrows self { read { yield items[i] } modify { yield &items[i] } }
}
func firstName(_ inv: Inventory) -> StringView { inv[0].name.view }       // OK: a storage projection
```

**The compiler verifies the claim.** Every `yield` must name a place reached through stored fields and other storage projections from what the item names: `self`, another parameter, or static storage. It must never name a local, a temporary, a bitfield or an under-aligned field.

**Only `unsafe` code can yield a place reached through a raw pointer**, such as a `List`'s buffer or a lock guard's protected value. That code promises that the place lies in storage the named parameter owns or views, and that the code after the `yield` treats it as still borrowed (below).

**The yield stays lent until the accessor returns.** A storage projection's access ends, and the code after its `yield` runs, when the call it is an argument of returns ([01](../01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin)). Otherwise both happen at the end of the full statement that begins it ([Temporaries](dependency-projection-and-results.md#temporaries)).

**The code after the `yield` treats the yielded place as still borrowed**, since the access can end while a view of the yield lives on. That code, a `defer` block or a local's destruction included, never changes the place, and after a `modify` never reads it either:

```swift
extension Inventory {
    var all: List<Item> where yield borrows self {
        read { yield items }
        modify { yield &items; items = List() }                  // error: changes the yielded place
    }
    var watched: List<Item> where yield borrows self {
        read { yield items }
        modify { yield &items; spy.append(items[0].view) }       // error: reads it after a modify
    }
}
```

**On an exclusive view type, a view of the yield depends on the view variable itself** ([Rule 1: Projection](dependency-projection-and-results.md#rule-1-projection)), as on a `MutableSpan` or a `MutableRef`. So this result depends on `s`, and through it on what `s` views:

```swift
func label(_ s: mutable MutableSpan<Item>, _ i: Int) -> StringView { s[i].name.view }
```

**On a view type that `outlives` accepts, `where yield outlives self` says the yield is reached through what the view carries** ([Staying valid after a parameter moves on: `outlives`](dependency-lifetimes.md#staying-valid-after-a-parameter-moves-on-outlives)).

**The standard projections are declared this way:**

- Collection and pool subscripts, `Box.value`, `MutableRef.value`, every lock guard's `.value`, and a `MutableSpan`'s element projections are `where yield borrows self`.
- The projections of `Span`, `StringView` and `Borrow` are `where yield outlives self`.
- `Span`'s and `StringView`'s range `get`s, `first` and `last` are `where return outlives self`.
- The `.value` of a `UniquePointer` or a `WeakPointer` depends on its access ([Rule 6: Dynamic accesses](dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)).
- Properties that build a view, such as `span`, sub-span ranges and an `SoA` column, are `get`s returning a view, not projections ([Rule 3: Call results](dependency-projection-and-results.md#rule-3-call-results)). An `SoA` column's view depends on its column alone ([04](../04-types/data-layout.md#struct-of-arrays-soat)).

## Projections in protocols

**Protocols carry the clause**, and a witness must satisfy it. The first requirement below is access-bound, and the second, declared `where yield borrows self`, isn't:

```swift
protocol Moving { var pos: Vec3 { read modify } }                             // access-bound
protocol Placed { var pos: Vec3 where yield borrows self { read modify } }    // a storage projection
```

So generic code can return a view of a requirement's yield only from a storage projection.

**A stored field witnesses either kind, except an under-aligned field or an imported bitfield**, subject to [05](../05-protocols-generics-and-closures/protocols-and-generics.md#conformances)'s rules on `let`, hidden, static, `unsafe` and union-member fields. Such a field goes through a temporary, so it witnesses only an access-bound requirement.

**An optional projection meets a `read` or `modify` requirement only when the requirement's own declared type is written as an optional, `U?`**, so that generic code treats it as an optional projection too. It never meets one where an associated type or a type parameter turns out to be an optional, or where the requirement is written `Optional<U>`, which asks for a whole place.

**A projection that yields a tuple of places meets no `read` or `modify` requirement.**

## `get` and `set` accessors

```swift
struct Angle(var radians: Float) {
    var degrees: Float {
        get { radians * 180 / .pi }
        set { radians = newValue * .pi / 180 }
    }
}
var a = Angle(radians: 0)
a.degrees = 90                               // calls set
a.degrees += 45                              // calls get, then set with the sum
var d = &a.degrees                           // calls get, lends the result, then calls set once the access ends
```

**A computed property or subscript may return a value from a `get`, and take one in a `set`.** A body with no accessor keyword returns a value as a `get` does. A `set` receives the assigned value as an `owned` parameter named `newValue`.

**A declaration's accessors are one of these:**

- a `get`;
- a `get` and a `set`;
- a `read`;
- a `read` and a `modify`.

**Assignment calls `set`.** So does a compound assignment, since `a ⊕= b` is `a = a ⊕ b` ([05](../05-protocols-generics-and-closures/operators.md#operators)).

**Any other change calls `get`, lends the result, and calls `set` with it once the access ends.** Such changes include binding the property with `&`, passing it as a `mutable` argument, and calling a `mutating` method on it. So the change is access-bound, as a `modify` that yields a temporary is ([above](#access-bound-projections)).

**That `set` call is checked as if written there.** So the change is an error when the `get`'s result may depend on `self` or on a `mutable` argument of the access, which `set` changes while its `newValue` still views it.

**Both calls take the subscript's arguments**, worked out once when a compound assignment or another change calls `get` and then `set`. A borrowed or `mutable` argument is lent to each in turn, and a copyable `owned` one is copied for the `get`. So such an access is a compile error when an `owned` parameter's type is move-only, since one value can't move into two calls.

**Accessors and stored fields meet requirements as follows:**

- **A `get` meets an access-bound `{ read }` requirement**, yielding its result as a temporary.
- **A `get` and a `set` meet an access-bound `{ read modify }` requirement when the `get`'s result can't depend on `self` or on a `mutable` parameter, and no `owned` parameter's type is move-only**, so that the pair of calls is always valid.
- **A `get` meets `{ get }`, and a `get` and a `set` meet `{ get set }`.**
- **When the value's type is copyable, a stored field that [05](../05-protocols-generics-and-closures/protocols-and-generics.md#conformances) allows, or a storage projection, also meets `{ get }` and `{ get set }`.**
- **When the value's type is copyable and unscoped, an access-bound `read` meets `{ get }`, and an access-bound `read` and `modify` meet `{ get set }`.** The `read`'s yield is copied as the `get`, and the `modify` serves as the `set`. A scoped yield's copy would carry an access that ends inside the witness, which rule 5 rejects.
- **An optional projection, or one that yields a tuple of places, meets `{ get }` but never `{ get set }`**, since it has no whole value that a `set` could write ([above](#projections-read-and-modify-accessors)).
