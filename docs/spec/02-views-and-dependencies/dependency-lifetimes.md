# Destruction, precise dependencies and assigning references

[02 · Views and dependencies](../02-views-and-dependencies.md)

A dependency usually matters while the value that carries it can still be used. Destruction can extend that time when it runs code that reaches borrowed memory. Signatures can state more precise dependencies, and assigning a reference to a `var` changes which place the `var` refers to.

## When destroying a value counts as using it

```swift
var m = Mutex(0)
var g = m.lock()
g.value += 1                                  // g's last use written out
var n = consume m                             // error: destroying g at scope end still uses m
```

**Some values may act when destroyed, as a lock guard unlocks its mutex.** A `deinit` may read and write what its value borrows, so the borrows of such a value last until its destruction.

**Destroying a value is a use when it is, or holds at any depth, one of these:**

- a value whose type declares a `deinit` that isn't `PlainDeinit` (below);
- a `consuming` function value, which may own handed-over captures in the storage it views ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values));
- a value of a type parameter, an associated type or a `some P`, unless constrained `Copyable` or `TrivialFree` ([06](../06-memory-and-allocators/allocation-lifecycle.md#releasing-a-value-without-destroying-it-trivialfree)), since generic code is checked once for every type it may stand for;
- in generic code, a value of a type whose members a `static if` or `static for` generates from its generic arguments, when those members may include a `deinit` or a stored field ([09](../09-compile-time/declaration-generation.md#generated-members-are-checked-per-instantiation)), unless a `where` clause states it `Copyable` or `TrivialFree`.

A field `*T` holds a `T` here, as it does for [scopedness](scoped-values.md#which-types-are-scoped). A reference holds none of these here, since dropping one destroys nothing it refers to.

**Such a value stays live until it is destroyed**: at scope end, or when it is overwritten or consumed. A maybe-initialized one ([01](../01-values-and-ownership/moving-values-out.md#places-that-hold-no-value)) stays live until the scope end or assignment that destroys it if it still holds a value. Any other value is live only until its last use.

**Such a value's destruction uses its whole dependency set when it is itself one of the values above**, or when it holds one and is one of these, whose parts have no sets of their own ([below](#naming-a-field)):

- an enum, an optional included;
- an inline array;
- a `Box`;
- a value of a type parameter.

**Otherwise, a struct's or tuple's destruction uses only the sets the caller keeps for the stored fields and tuple elements that are or hold one**, each by the same rule.

**Either way, until its destruction, the value holds the dynamic accesses in the sets that destruction uses** (rule 6).

**What a value's destruction uses can't include a part of the value**, at any depth. That conflicts with destroying it, as moving it would, since a `deinit` owns `self` and may change one part before reading another. Take a `Doc` that keeps a reference to its own text:

```swift
struct Doc(var text: String, var first: (&Text)?): Scoped

doc.first = doc.text                          // 'doc' depends on its own field 'text' from here on
```

- That assignment is fine.
- It is still fine when `Doc` holds a lock guard in another field, whose destruction uses only the guard's own set.
- It is an error once `Doc` has a non-`PlainDeinit` `deinit`, or when the guard locks a mutex that `Doc` holds.

**A type conforms to `PlainDeinit` when its `deinit` only destroys what it owns alone and frees its own buffers.** The conformance is declared with `unsafe`, since it is a contract the compiler can't check ([10](../10-errors-and-safety/unsafe-code.md#unverified-promises)). Destroying one then uses only what destroying its elements uses, and skipping its own `deinit` can only leak. Any `deinit` may be skipped, as a stale value's elements' are ([10](../10-errors-and-safety/unsafe-code.md#aliasing-and-skipped-deinits)).

**So a `List<&Text>`, whose std type conforms, keeps nothing borrowed when dropped at scope end**, while a `List<MutexGuard<T>>` keeps its mutexes borrowed until then. An object's owner, a `Pin`, a `LocalPin` and `Shared` don't conform, since their `deinit`s change state they don't own alone.

## Lock guards are released on the thread that took them

```swift
var g = registry.lock()
_ = Thread.start { [move g] in g.value.flush() }  // error: a guard isn't Sendable, so it stays on the thread that took it
```

A **guard type** is a type declared `@guard`: the type of a value that holds a lock for as long as it lives, which a `Synchronized` type's method returns from a shared `self` ([Mutable views](dependency-projection-and-results.md#mutable-views)), as `MutexGuard` is.

**`@guard` makes a type scoped, move-only and not `Sendable`: `Scoped`, `~Copyable` and `~Sendable`.**

- **`Scoped`**, since a guard points into its lock ([07](../07-concurrency/synchronization.md#the-synchronized-contract)), so it is a view of memory that can be freed ([Scoped values](scoped-values.md#scoped-values)).
- **`~Copyable`**, since a copy would release the lock a second time.
- **`~Sendable`.** Nothing that isn't `Sendable` moves to or is lent to another thread, even inside a type parameter, an existential or a closure. So a guard is dropped, or consumed as a `Condvar` wait consumes one, only on the thread that took it, as many platform mutexes require ([07](../07-concurrency/synchronization.md#locks-mutex-and-rwlock)).

**What a guard lends depends on the guard itself**, so nothing lent under the lock outlives it. That covers its `.value`, a place property whose source is the guard ([Place and value properties](place-and-value-properties.md#the-place-lies-in-its-sources)). It also covers a value read from one of its stored fields, which depends on the guard instead of inheriting the field's set ([Rule 2: Transitivity](dependency-projection-and-results.md#rule-2-transitivity)).

## Precise dependencies (opt-in)

**A `where` clause can say what a function's result, a place property's place or an absorbing parameter depends on.** By default a result depends on every argument rule 3 names, even one it only read. The clause helps where that gets in the way, as with a lookup keyed by a reference into a buffer you want to advance:

```swift
extension SymbolTable {
    func find(_ key: &Text) -> (&[Symbol])?
        where return borrows self                // the result borrows only the table, not the key
}

func split(_ text: &Text, by separator: &Text, into out: mutable &List<&Text>)
    where out borrows text                       // 'out' takes on only text, not 'separator'

func builtinName(_ key: &Text) -> &Text
    where return borrows static                  // only static storage: the key doesn't stay borrowed

let tok = lexer.peek()                           // shared on lexer
let syms = symbols.find(tok.text)                // shared on symbols only
lexer.advance()                                  // OK: tok's last use is above
print("\(syms?.count ?? 0) symbols")
```

**An item's subject, what depends, is one of these:**

- `return`, for the result, an error it fails with included, or for the place a place property hands out ([What a place depends on](place-and-value-properties.md#what-a-place-depends-on));
- a parameter that absorbs under rule 4, for what it takes on: a `mutable &` one, `self` in a `mutating` method included, or one that owns a mutable view, such as an owned struct of mutable references.

**An item says what its subject depends on.** In every item, a `&T` or `mutable &T` parameter `x`, or the `self` of a plain or `mutating` method, stands for the place it names, so `x` is the caller's place, and what `x` borrows is that place's set ([01](../01-values-and-ownership/parameters.md#parameters)):

- **`borrows x`**: the parameter `x` and what `x` borrows, and no other parameter. The subject may still view static storage, as rule 5 allows every function. Rules 3 and 4 apply to `x` alone, so a shallow argument still contributes only its set to a sealed subject. For a place property's place, `x` is a source instead: the shallow and sealed exemptions don't apply, and static storage counts only when an item names it ([Place and value properties](place-and-value-properties.md#the-place-lies-in-its-sources)).
- **`borrows static`**: static storage only.
- **`outlives x`**: only what `x` borrows, so the subject stays valid after `x` changes or is gone ([below](#staying-valid-after-a-parameter-moves-on-outlives)).

**Several items may name one subject, which then depends on all of them.** A subject no item names follows the default rules.

```swift
extension SymbolTable {
    func search(_ key: &Text) -> (&[Symbol])?
        where return borrows self, return borrows key   // the result depends on the table and the key
}
```

**The compiler verifies the clause in the callee**, with rule 5 restricted to what the items name, so a wrong clause is a compile error. The clause names parameters, their stored fields ([below](#naming-a-field)) or `static`, nothing more.

**A view that `unsafe` code builds from a raw pointer carries no dependencies to verify.** So its signature's dependencies, by the default rules or the clause, are part of what that code promises.

### Staying valid after a parameter moves on: `outlives`

**`where return outlives self` lets an iterator over shared elements hand out elements that outlive the iteration:**

```swift
struct ElementIterator<T>(var rest: &[T]): SharedIterator, Scoped {
    mutating func next() -> (&T)? where return outlives self { ... }   // elements borrow the collection, not the iterator
}

var names = alloc List<&Text>()
for s in &table.entries { names.append(s.name) }    // names depends on 'table', shared
print("\(names.count) names")                      // fine; changing 'table' here would be the error
```

Without the clause, each element would depend exclusively on the iterator, and the next `next()` would conflict with `names`.

**Iterators that hand out mutable views stay lending**: each view depends on the iterator, exclusively, so the next `next()` conflicts while the view lives. That holds for one that hands out [`mutable &T`](../04-types/collections.md#iteration) elements or `mutable &[T]` chunks, since two live mutable references from one iterator would alias.

**`outlives x` requires that nothing `x` carries can be changed through `x` or end with it.** So `x`'s type can hold no mutable view ([Mutable views](dependency-projection-and-results.md#mutable-views)), and destroying one is no use ([above](#when-destroying-a-value-counts-as-using-it)). In generic code, this must hold for every type argument the constraints allow.

- **A `&[T]`, an iterator over one and a `List<&Text>` qualify.** So the function below leaves `src` free once it returns, where by default `dst` would keep the borrowed `src` itself borrowed.
- **An iterator over a `mutable &[T]` doesn't**, since it could hand out a reference and then replace the data under it.
- **A read guard doesn't either.** It carries only a shared borrow, but dropping it releases the lock, so a guard's `.value` depends on the guard itself, a place property's default ([Place and value properties](place-and-value-properties.md#the-place-lies-in-its-sources)).

```swift
func copyAll(from src: &List<&Text>, into dst: mutable &List<&Text>)
    where dst outlives src                       // 'dst' takes on what 'src' carries, not 'src' itself
```

**Inside `next()`, verification uses rule 1's case of a shared reference** ([Rule 1: Projection](dependency-projection-and-results.md#rule-1-projection)), so this body gives `b` what `rest` carries, the collection's set, not the field's:

```swift
let b = &rest[0]
rest = rest[1...]
return b
```

**Generic code sees the clause through the protocol.** `IteratorProtocol.next()` has no clause, since some iterators over shared elements lend, such as a line reader that reuses one buffer. So generic code over it treats elements as lent. The refinement **`SharedIterator`** declares `next()` `where return outlives self`, and `Collection` requires `Iterator: SharedIterator`.

**A witness must satisfy its requirement's clause**, depending on no more than it declares, so generic code can rely on the requirement alone. The compiler checks this at the conformance.

**A value moved out of an owner carries only what the owner carried.** `where return outlives p` is also allowed, whatever `p` carries, on a function whose result is **moved out** of `p`'s own storage, where `p` is `self` or a `mutable &` parameter:

- `popLast()`, `remove(at:)` and `Optional.take()`, with `where return outlives self`;
- `replace(mutable &place, with:)`, with `where return outlives place`.

**A value `p` owns can view `p`'s own storage only by making `p` depend on a part of itself.** Then `mutable &p` conflicts with that dependency, so the call can't be made. So what such a call returns depends only on what `p` carried, with the same kinds, and a worklist over a `List<mutable &[Float]>` works:

```swift
while var s = work.popLast() {                  // 'work' stays free while 's' holds its reference
    let p = partition(mutable &s)
    let (low, high) = s.consumingSplit(at: p)   // the halves carry what 's' carried
    work.append(consume low)
    work.append(consume high)
}
```

`consumingSplit(at:)` hands the halves over with what `s` carried, where `s.mutableSplit(at: p)` would lend them, tied to `s` ([04](../04-types/collections.md#mutating-and-consuming-methods)).

### Naming a field

**An item may name a path of a parameter's stored fields and tuple elements, and a subject may be followed by one**, since a value may carry borrows of several places while a result comes from one of them. So a subject may be `return.name`, `return.0`, or `q.table` for a `mutable &` parameter `q`, which then takes on what the item names in that field only:

```swift
struct Query(
    var name: &Text,                             // refers to the request text
    var table: &[Entry],                         // refers to the symbol table
): Scoped

func lookup(_ q: Query) -> (&Entry)?
    where return outlives q.table                // an entry of the table, never of the request

func makeQuery(_ text: &Text, _ t: &[Entry]) -> Query
    where return.name borrows text, return.table borrows t

var request = readRequest()
let e = lookup(Query(name: request, table: symbols))
request = readRequest()                          // fine: 'e' borrows symbols, not the request
print("\(e?.id ?? 0)")
```

**The caller keeps a set per stored field of a struct, and per element of a tuple**, down through nested stored fields. A value's own set is their union.

- A primary initializer gives each field its argument's set.
- Assigning a stored field replaces its set, where the place assigned is known ([Rule 4: Absorption](dependency-absorption-and-accesses.md#rule-4-absorption)).
- A call result gets per-field sets only from `return.f` items. Its other fields get what a plain `return` item names, or what the default rules give the whole result.
- Elements, enum payloads, what a `Box` holds, and a value of a type parameter have a single set.

**A `mutable &` argument's fields may trade what they carry**, as in a `mutating` method that swaps two fields. So after the call, each stored field of the argument, at every depth, has the union of all its fields' sets from before, plus what the call gives it. A field that a `p.f` item names is the exception: it keeps its own set, plus what the items name, and the callee proves it took nothing from `p`'s other fields.

```swift
struct Pair(var a: &Text, var b: &Text): Scoped {
    mutating func flip() { let t = a; a = b; b = t }
}
var pair = Pair(a: s1, b: s2)
pair.flip()                                      // both fields depend on 's1' and 's2' from here on
```

**A path goes through stored fields only**, since an accessor is an access to all of `self` ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)). `borrows q.table` means that field and what it borrows. `outlives q.table` means only what it borrows, under the conditions above applied to the field's type. The callee proves the item with the same per-field sets for its own locals.

## Assigning a reference to a `var`

**A `var` that holds a reference refers to another place once it is assigned another reference** ([01](../01-values-and-ownership/bindings.md#bindings-that-own-a-value)). A cursor walking down a structure does this at each step, assigning a reference to a place reached through the cursor itself:

```swift
struct Node(var value: Int = 0, var children: List<Box<Node>> = alloc [])

var cur = mutable &tree.root
for i in &path {
    guard i < cur.children.count else { break }
    cur = mutable &cur.children[i].value         // 'cur' refers to that child from here on; no node is written
}
cur.children.append(alloc Box(Node(value: 0)))
tree.root.value = 1                              // error if placed before the last use of 'cur'
```

**What the `var` depends on follows the place the new reference refers to:**

- **A place reached through the `var` keeps the `var`'s set.** It lies inside the place the old reference referred to, so the original borrow of `tree.root` lasts until `cur`'s last use. The assignment ends the old reference, so the new one takes over what the old one carried, and keeps no borrow of `cur` itself. So nothing conflicts with the write, where a reborrow through a `cur` that holds a mutable reference would keep `cur` borrowed ([01](../01-values-and-ownership/references.md#reborrowing)).
- **A step through a place property also takes on its other sources.** One whose sources go beyond `self` may reach a place in another argument, as `mutable &cur[graft: mutable &spare]` does. So the `var`'s set also takes on every other dependency of the new place ([Place and value properties](place-and-value-properties.md#the-place-lies-in-its-sources)).
- **Any other place starts a new borrow.** The `var`'s set becomes the new reference's, as every assignment to a variable that owns its value replaces its set (rule 4 in [Absorption](dependency-absorption-and-accesses.md#rule-4-absorption)).

**The `var` is a local declared in the same function or closure body**, not a parameter, a capture or a field, so the body sees every use of it. A mutable reference reached through any other place keeps that place borrowed, as a reborrow does, so assigning it back there conflicts with that borrow. Through a shared reference the place drops out anyway ([Rule 1: Projection](dependency-projection-and-results.md#rule-1-projection)), so `rest = rest[1...]` above works in a field too.

**A cursor over a value that a call returns keeps the value in a local of its own**, since a `var` that owns a value can't be assigned a reference:

```swift
var tree = buildTree()                           // owns the tree the call returned
var at = mutable &tree.root                      // the cursor, which assignments point elsewhere
```

**Through objects, the cursor holds one mark.** A step through an object's owner or weak pointer takes the new object's access ([Rule 6: Dynamic accesses](dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)), as a step to a child's value does when the children are held by `UniquePointer`s. That access **replaces** the previous object's access in the `var`'s set, so the cursor holds a mark only on the object it stands on, however deep the walk. The previous access ends once nothing else depends on it.

**This is safe because the new place lies in another object's value, guarded by the new mark.** If an alias removes the child from the previous object, destroying the object the cursor stands on panics ([03](../03-handles-and-objects.md#destroying-an-object)), and any other alias reaching it still conflicts.

**A step to a place reached through a value property's change is an error**, since each step would nest another change whose `set` waits for the cursor's last use ([Value properties: `get` and `set`](place-and-value-properties.md#value-properties-get-and-set)). A step through a place property is fine, since its place lies in storage.
