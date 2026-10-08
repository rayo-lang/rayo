# Destruction, precise dependencies and `rebind`

[02 · Views and dependencies](../02-views-and-dependencies.md)

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

A field `*T` holds a `T` here, as it does for [scopedness](scoped-values.md#which-types-are-scoped).

**Such a value stays live until it is destroyed**: at scope end, or when it is overwritten or consumed. A maybe-initialized one ([01](../01-values-and-ownership/moving-values-out.md#places-that-hold-no-value)) stays live until the scope end or assignment that destroys it if it still holds a value. Any other value is live only until its last use.

**Such a value's destruction uses its whole dependency set when it is itself one of the values above**, or when it holds one and is one of these, whose parts have no sets of their own ([below](#naming-a-field)):

- an enum, an optional included;
- an inline array;
- a `Box`;
- a value of a type parameter.

**Otherwise, a struct's or tuple's destruction uses only the sets the caller keeps for the stored fields and tuple elements that are or hold one**, each by the same rule.

**Either way, until its destruction, the value holds the dynamic accesses in the sets that destruction uses** (rule 6).

**What a value's destruction uses can't include a part of the value**, at any depth. That conflicts with destroying it, as moving it would, since a `deinit` takes an owned `self` and may change one part before reading another. Take a `Doc` that keeps a view of its own text:

```swift
struct Doc(var text: String, var first: StringView?): Scoped

doc.first = doc.text.view                     // 'doc' now depends on its own field 'text'
```

- That assignment is fine.
- It is still fine when `Doc` holds a lock guard in another field, whose destruction uses only the guard's own set.
- It is an error once `Doc` has a non-`PlainDeinit` `deinit`, or when the guard locks a mutex that `Doc` holds.

**A type conforms to `PlainDeinit` when its `deinit` only destroys what it owns alone and frees its own buffers.** The conformance is declared with `unsafe`, since it is a contract the compiler can't check ([10](../10-errors-and-safety/unsafe-code.md#unverified-promises)). Destroying one then uses only what destroying its elements uses, and skipping its own `deinit` can only leak. Any `deinit` may be skipped, as a stale value's elements' are ([10](../10-errors-and-safety/unsafe-code.md#aliasing-and-skipped-deinits)).

**So a `List<StringView>`, whose std type conforms, keeps nothing borrowed when dropped at scope end**, while a `List<MutexGuard<T>>` keeps its mutexes borrowed until then. An object's owner, a `Pin`, a `LocalPin` and `Shared` don't conform, since their `deinit`s change state they don't own alone.

## Lock guards are released on the thread that took them

```swift
var g = registry.lock()
Thread.start { [move g] in g.value.flush() }  // error: a guard isn't Sendable, so it stays on the thread that took it
```

A **guard type** is a type declared `@guard`: the type of a value that holds a lock for as long as it lives, which a `Synchronized` type's method returns from a shared `self` ([Mutable views](dependency-rules/projection-and-results.md#mutable-views)), as `MutexGuard` is.

**`@guard` makes a type scoped, move-only and not `Sendable`: `Scoped`, `~Copyable` and `~Sendable`.**

- **`Scoped`**, since a guard points into its lock ([07](../07-concurrency/synchronization.md#the-synchronized-contract)), so it is a view of memory that can be freed ([Scoped values](scoped-values.md#scoped-values)).
- **`~Copyable`**, since a copy would release the lock a second time.
- **`~Sendable`.** Nothing that isn't `Sendable` moves to or is lent to another thread, even inside a type parameter, an existential or a closure. So a guard is dropped, or consumed as a `Condvar` wait consumes one, only on the thread that took it, as many platform mutexes require ([07](../07-concurrency/synchronization.md#locks-mutex-and-rwlock)).

## Precise dependencies (opt-in)

**A `where` clause can say what a function's result, an accessor's yield or an absorbing parameter depends on.** By default a result depends on every argument rule 3 names, even one it only read. The clause helps where that gets in the way, as with a lookup keyed by a view into a buffer you want to advance:

```swift
extension SymbolTable {
    func find(_ key: StringView) -> Span<Symbol>?
        where return borrows self                // the result borrows only the table, not the key
}

func split(_ text: StringView, by separator: StringView, into out: mutable List<StringView>)
    where out borrows text                       // 'out' takes on only text, not 'separator'

func builtinName(_ key: StringView) -> StringView
    where return borrows static                  // only static storage: the key doesn't stay borrowed

let tok = lexer.peek()                           // shared on lexer
let syms = symbols.find(tok.text)                // shared on symbols only
lexer.advance()                                  // OK: tok's last use is above
use(syms)
```

**An item's subject, what depends, is one of these:**

- `return`, for the result and any thrown error;
- `yield`, for what an accessor yields ([Storage projections](projections-and-accessors.md#storage-projections));
- a parameter that absorbs under rule 4, for what it takes on: a `mutable` one, `self` in a `mutating` method included, or an `owned` one that is a mutable view, such as an `owned` `MutableSpan`.

**An item says what its subject depends on:**

- **`borrows x`**: the parameter `x` and what `x` borrows, and no other parameter. The subject may still view static storage, as rule 5 allows every function. Rules 3 and 4 apply to `x` alone, so a shallow argument still contributes only its set to a sealed subject.
- **`borrows static`**: static storage only.
- **`outlives x`**: only what `x` borrows, so the subject stays valid after `x` changes or is gone ([below](#staying-valid-after-a-parameter-moves-on-outlives)).

**Several items may name one subject, which then depends on all of them.** A subject no item names follows the default rules.

```swift
extension SymbolTable {
    func search(_ key: StringView) -> Span<Symbol>?
        where return borrows self, return borrows key   // the result depends on the table and the key
}
```

**The compiler verifies the clause in the callee**, with rule 5 restricted to what the items name, so a wrong clause is a compile error. The clause names parameters, their stored fields ([below](#naming-a-field)) or `static`, nothing more.

**A view that `unsafe` code builds from a raw pointer carries no dependencies to verify.** So its signature's dependencies, by the default rules or the clause, are part of what that code promises.

### Staying valid after a parameter moves on: `outlives`

**`where return outlives self` lets an iterator over shared elements hand out elements that outlive the iteration:**

```swift
struct SpanIterator<T>(var rest: Span<T>): SharedIterator, Scoped {
    mutating func next() -> Borrow<T>? where return outlives self { ... }   // elements borrow the collection, not the iterator
}

var names = List<StringView>()
for s in table.entries { names.append(s.name.view) }   // names depends on 'table', shared
use(names)                                              // fine; mutating 'table' here would be the error
```

Without the clause, each element would depend exclusively on the iterator, and the next `next()` would conflict with `names`.

**Iterators that hand out mutable views stay lending**: each view depends on the iterator, exclusively, so the next `next()` conflicts while the view lives. That holds for one that hands out [`MutableRef`](../04-types/collections.md#iteration)s or `MutableSpan` chunks, since two live exclusive views from one iterator would alias.

**`outlives x` requires that nothing `x` carries can be changed through `x` or end with it.** So `x`'s type can hold no mutable view ([Mutable views](dependency-rules/projection-and-results.md#mutable-views)), and destroying one is no use ([above](#when-destroying-a-value-counts-as-using-it)). In generic code, this must hold for every type argument the constraints allow.

- **`Span`, a span iterator and `List<StringView>` qualify.** So the function below leaves `src` free once it returns, where by default `dst` would keep the borrowed `src` itself borrowed.
- **An iterator over a `MutableSpan` doesn't**, since it could hand out a view and then replace the data under it.
- **A read guard doesn't either.** It carries only a shared borrow, but dropping it releases the lock, so a guard's `.value` is declared `where yield borrows self`.

```swift
func copyAll(from src: List<StringView>, into dst: mutable List<StringView>)
    where dst outlives src                       // 'dst' takes on what 'src' carries, not 'src' itself
```

**Inside `next()`, verification uses rule 1's shared-view case** ([Rule 1: Projection](dependency-rules/projection-and-results.md#rule-1-projection)), so this body gives `b` the collection's set, not the field's:

```swift
let b = rest.first
rest = rest[1...]
return b
```

**Generic code sees the clause through the protocol.** `IteratorProtocol.next()` has no clause, since some iterators over shared elements lend, such as a line reader that reuses one buffer. So generic code over it treats elements as lent. The refinement **`SharedIterator`** declares `next()` `where return outlives self`, and `Collection` requires `Iterator: SharedIterator`.

**A witness must satisfy its requirement's clause**, depending on no more than it declares, so generic code can rely on the requirement alone. The compiler checks this at the conformance.

**A value moved out of an owner carries only what the owner carried.** `where return outlives p` is also allowed, whatever `p` carries, on a function whose result is **moved out** of `p`'s own storage, where `p` is `self` or a `mutable` parameter:

- `popLast()`, `remove(at:)` and `Optional.take()`, with `where return outlives self`;
- `replace(&place, with:)`, with `where return outlives place`.

**A value `p` owns can view `p`'s own storage only by making `p` depend on a part of itself.** Then `&p` conflicts with that dependency, so the call can't be made. So what such a call returns depends only on what `p` carried, with the same kinds, and a worklist over a `List<MutableSpan<Float>>` works:

```swift
while var s = work.popLast() {                  // 'work' stays free while 's' holds its buffer
    let p = partition(&s)
    let (low, high) = (consume s).split(at: p)  // the halves carry what 's' carried
    work.append(low)
    work.append(high)
}
```

The consuming `split(at:)` hands the halves over with what `s` carried, where the lending `s.split(at: p)` would tie them to `s` ([04](../04-types/collections.md#shared-mutable-and-consuming-forms-of-one-method)).

### Naming a field

**An item may name a path of a parameter's stored fields and tuple elements, and a subject may be followed by one**, since a value may carry borrows of several places while a result comes from one of them. So a subject may be `return.name`, `return.0`, or `q.table` for a `mutable` parameter `q`, which then takes on what the item names in that field only:

```swift
struct Query(
    var name: StringView,                        // borrows the request text
    var table: Span<Entry>,                      // borrows the symbol table
): Scoped

func lookup(_ q: Query) -> Borrow<Entry>?
    where return outlives q.table                // an entry of the table, never of the request

func makeQuery(_ text: StringView, _ t: Span<Entry>) -> Query
    where return.name borrows text, return.table borrows t

var request = readRequest()
let e = lookup(Query(name: request.view, table: symbols.span))
request = readRequest()                          // fine: 'e' borrows symbols, not the request
use(e)
```

**The caller keeps a set per stored field of a struct, and per element of a tuple**, down through nested stored fields. A value's own set is their union.

- A primary initializer gives each field its argument's set.
- Assigning a stored field replaces its set, where the place assigned is known ([Rule 4: Absorption](dependency-rules/absorption-and-accesses.md#rule-4-absorption)).
- A call result gets per-field sets only from `return.f` items. Its other fields get what a plain `return` item names, or what the default rules give the whole result.
- Elements, enum payloads, what a `Box` holds, and a value of a type parameter have a single set.

**A `mutable` argument's fields may trade what they carry**, as in a `mutating` method that swaps two fields. So after the call, each stored field of the argument, at every depth, has the union of all its fields' sets from before, plus what the call gives it. A field that a `p.f` item names is the exception: it keeps its own set, plus what the items name, and the callee proves it took nothing from `p`'s other fields.

```swift
struct Pair(var a: StringView, var b: StringView): Scoped {
    mutating func flip() { let t = copy a; a = copy b; b = t }
}
var pair = Pair(a: s1.view, b: s2.view)
pair.flip()                                      // both fields now depend on 's1' and 's2'
```

**A path goes through stored fields only**, since an accessor is an access to all of `self` ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)). `borrows q.table` means that field and what it borrows. `outlives q.table` means only what it borrows, under the conditions above applied to the field's type. The callee proves the item with the same per-field sets for its own locals.

## Pointing a name at another place: `rebind`

**A borrowing binding is a name for the place it borrows, so `=` on it writes the place:**

```swift
var cur = &tree.root
cur = Node()                                     // replaces the node in tree.root
```

A cursor walking down a structure moves the name itself with `rebind … to …`:

```swift
struct Node(var value: Int = 0, var children: List<Box<Node>> = [])

var cur = &tree.root
for i in path {
    guard i < cur.children.count else { break }
    rebind cur to &cur.children[i].value         // 'cur' now names that child; nothing is written
}
cur.children.append(Box(Node(value: 0)))
tree.root.value = 1                              // error if placed before the last use of 'cur'
```

**`rebind x to p` makes the local `x` name the place `p` from then on**, as if declared with it there.

- `x` is a local declared in the same function or closure body, not a parameter or a capture.
- `p` has `x`'s type, and is lent as `x`'s declaration lent its place: a changeable place marked `&` for a `var`, and marked `borrow` for a `let`, which still changes nothing.

**`=` never rebinds**: `cur = &child` is a compile error, and `rebind` does that instead. `&p` is a value only where it makes a view of a type of its own:

- a `mutable any P`;
- a function value made from a `mutating` closure, a `Closure<mutating …>` or a `mutating` function value ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions));
- the mutable form of a `get`, such as `&list.span` ([04](../04-types/collections.md#shared-mutable-and-consuming-forms-of-one-method)).

**Then `x = &p` writes that view into the place `x` names**, as `d = &crate` does in a loop over `&targets`, and `x` still names the same place.

**A place reached through `x` keeps `x`'s set.** It lies inside the one `x` named, so the original borrow of `tree.root` lasts until `x`'s last use.

**Any other place starts a new borrow.** `x`'s set becomes `p`'s, and the old place is free once nothing else depends on it.

**Through objects, the cursor holds one mark.** A step through an object's owner or weak pointer takes the new object's access ([Rule 6: Dynamic accesses](dependency-rules/absorption-and-accesses.md#rule-6-dynamic-accesses)), as a `rebind` to a child's value does when the children are held by `UniquePointer`s. That access **replaces** the previous object's access in `x`'s set, so the cursor holds a mark only on the object it stands on, however deep the walk. The previous access ends once nothing else depends on it.

**This is safe because the new place lies in another object's value, guarded by the new mark.** If an alias removes the child from the previous object, destroying the object the cursor stands on panics ([03](../03-handles-and-objects.md#destroying-an-object)), and any other alias reaching it still conflicts.

**A target reached through an access-bound projection is an error**, since each step would nest another suspended access ([Access-bound projections](projections-and-accessors.md#access-bound-projections)).

**A binding that owns its value can be rebound**, such as either of these:

```swift
var cur = buildTree()                            // owns the tree the call returned
var lives = &particles.life                      // owns the MutableSpan the mutable form returns
```

**The first `rebind` of such a binding hands the value to a hidden local** of the binding's scope, destroyed at its end. The value stays where it is, so views already taken from it stay valid and depend on that local. A lock guard handed over this way stays locked until the scope ends.

**After the first `rebind` of a binding that owns its value, `x` names a place, so it can't be consumed.** When a path or a loop pass may skip the `rebind`, `x` can't be consumed after it on any path, and the hidden local is maybe-initialized ([01](../01-values-and-ownership/moving-values-out.md#places-that-hold-no-value)).
