# Borrowed references and object graphs

[Hard cases](../hard-cases.md)

## A. Borrowed and stored references

**Borrows are checked statically within a function, with no lifetime parameters.** A view of memory that can be freed must stay within the scope that lent it, though, so a `Span` or a `StringView` can't be stored in long-lived state ([02](../../spec/02-views-and-dependencies/scoped-values.md#scoped-values)). Stored references move to the dynamic tier instead: weak pointers, `Slice` and `Handle`, each checked at each use. These cases probe both sides of that line: code that should stay free and static, and code that needs stored references but shouldn't need `unsafe`.

### A1 · Views into a buffer the function owns (also A4)

**A tokenizer's tokens view the text they came from, instead of copying it.** A function loads a large text into an owned `String` and splits it into tokens whose text views the source. The tokens are collected into a list, filtered, and handed on. Copying each token's text into a `String` of its own would allocate once per token, since a `String` owns heap memory ([01](../../spec/01-values-and-ownership/moves-copies-destruction.md#copyable-types)).

- **Must accept** tokens that view the source without copying text, in a token list that lives as long as the function needs it.

### A2 · Collecting views through helpers, loops and callbacks (also A15, part of A24)

**Code collects views of a text into a list it owns, and uses the list afterwards.** It does so through a helper, a loop and a callback:

```swift
func splitLines(_ text: StringView, into out: mutable List<StringView>) { ... }

splitLines(source.view, into: &lines)                           // the helper appends to the caller's list
for entry in table.entries { names.append(entry.name.view) }   // a loop over a collection
forEachLine(src.view) { line in lines.append(copy line) }      // a callback
print(lines.count)
```

The caller has to know which text the list views. Changing that text, as `source.append` would, may move it to a larger buffer and free the old one, which the list still views ([safety argument](../safety-argument.md)).

The criteria below also use these patterns:

```swift
work.append(&data[0..<n])                    // a quicksort's worklist: the first pending range, as a span
while var s = work.popLast() { … }           // each pass pops the next pending range
lexer.lex(into: &tokens)                     // appends tokens that view the lexer's source
fill(&keys, &values)                         // fills two lists of views
let texts = t.map { copy $0.text }           // 't' is a Span<Token>
let labels = entries.map { $0.name.view }    // a view of each entry's name
for row in rows { spans.append(row.span) }   // 'rows' is a List<[4 of Float]>
copyAll(from: src, into: &dst)               // copies the views that 'src' holds into 'dst'
```

- **Must accept** the helper, the loop and the callback in the first block, and a user-defined sequence, such as a lexer used as a `for` sequence, whose elements are collected the same way, with no fallback to index loops.
- In the helper and the callback, the dependency is created *inside the callee*, and the caller must learn about it with no annotation, or with a small checked one.
- **Must accept** a quicksort without recursion that keeps its pending ranges as spans in a worklist, starting and popping as above, with `data` untouchable until `work` is dead.
- **Must accept**, with no `where` clause, the `lex` and `fill` calls above over two `List<StringView>`s, each list used afterwards: a list takes on what the other arguments view, not the arguments themselves.
- **Must accept** the `map` over a `Span<Token>` and the `map` over `entries` above, each result used after the call, and the loop over a `List<[4 of Float]>`, with `spans` used after the loop.
- **Must accept** the `copyAll` call above over two `List<StringView>`s, with a checked annotation, then `src` changed while `dst`'s views are used.

### A3 · A result that depends on only one argument

**A lookup takes a key that views one buffer and returns a view into another**, and the code then changes the first buffer while it still uses the result. A parser does this when it looks a token's text up in a symbol table, then advances the lexer:

```swift
let tok = lexer.peek()                         // view into lexer's buffer
let entry = symbols.find(tok.text)             // view into symbols; key only used for lookup
lexer.advance()                                // mutates lexer
use(entry)

func labelOf(_ d: any Named) -> StringView { d.label() }   // an ordinary helper over an existential view
```

The difficulty is that, by default, a call's result depends on everything the call was lent, even an argument it only read ([02](../../spec/02-views-and-dependencies/dependency-lifetimes.md#precise-dependencies-opt-in)).

- **Must accept** this sequence, possibly with a small annotation on `find` that the compiler checks. If the spec's answer is "restructure", count it as Solved with cost, and state how common the pattern is in parsers and lookups.
- **Must accept** a struct holding a view of a request and a view of a table, passed to a lookup whose result depends only on the table, then the request replaced while the result is used.
- **Must accept** ordinary helpers with no annotation, such as `span.min(by: …)`, `max(a.view, b.view)` or `grid.row(y + 1)`, whose results depend only on what they view, never on a scalar argument such as `y + 1`, and `labelOf` above, whose result is used after its statement.

### A5 · Long-lived views into a long-lived buffer

**A large buffer is loaded once, and many long-lived structs hold views of ranges inside it for as long as it lives**, as the components of a loaded level hold views of its package. Separately, code keeps `Slice<T>`s into a blob that several threads share under a lock, replaces the whole blob with a shorter one, and reads through an old slice. An old slice may then reach past the new blob's end ([06](../../spec/06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers)).

- **Must accept** storing those views in long-lived structs, without copying the data. Name the cost of whatever replaces the views (offsets, a shared owner): run-time checks, and bytes per view where the spec fixes a layout.
- **Must accept** reads through slices that still fit, without re-creating them.

### A6 · A mutable cursor re-targeted down a tree

**A walk down a tree keeps one mutable cursor, and re-targets it to a child at each step.** The walk starts at the root, follows a path chosen at run time, then inserts a child at the end of the path. Each node owns its children:

```swift
struct Node(var value: Int, var children: List<Box<Node>>)   // a value, and the boxes that own its children
```

In C++, the cursor is a pointer that the loop points at each child in turn:

```cpp
Node* cur = &root;
for (int i : path) cur = cur->children[i].get();    // re-target the cursor to a child
cur->children.push_back(std::make_unique<Node>());
```

A cursor that binds a place can't be re-targeted with `=`, which writes the place the binding names ([02](../../spec/02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind)).

- **Must accept** a loop that re-targets the mutable cursor to a child each iteration.
- **Must accept** the same walk when the children are `List<UniquePointer<Node>>` and the tree is 10,000 levels deep, without a run-time mark held per level.

### A7 · Accessors, user subscripts and columns (also part of A24)

**Code needs two *computed* projections of one value mutably at once**: `modify` accessors, not stored fields ([02](../../spec/02-views-and-dependencies/projections-and-accessors.md#projections-read-and-modify-accessors)).

```swift
var p = &world.physics     // a modify accessor
var r = &world.render      // another one, on the same world
step(&p, &r)
```

The criteria below also use these patterns:

```swift
var lives = &particles.life                          // an SoA column, taken as a MutableSpan<Float>

node.next = nil                                      // through a property that yields a stored optional field
node.next.take()                                     // takes the value out through the same property
pool[a]?.hp = copy pool[b]!.hp                       // one element's field, assigned from another's
world.enemies[h]?.hp -= reinforce(&world.enemies)    // the right side lends the whole pool for change
let hp = copy target?.hp                             // a copy through an optional chain
if let c = h?.cell { use(c.tag.span) }               // a view through an optional chain
```

- State whether this compiles. If it doesn't, give the idiom and its cost. Rust has the same limitation, so "same as Rust, and here is the workaround" is an acceptable answer.
- **Must accept** a user container, such as a ring buffer over raw memory, whose `modify` subscript yields an element, and a function that takes the container `mutable` and returns a view of that element.
- **Must accept** an `SoA<T>` column, a view of the buffer that holds one field of `T`, taken as a `MutableSpan` as `lives` is above, and moved into a struct of views, into a closure, or into an `owned` parameter.
- **Must accept** the optional chains through projections above, the first two through a property that yields a stored optional field.

### A8 · A graph with cross-links, freed all at once

**A graph of many nodes that link to each other is built, searched and freed all at once**, as a navigation graph is per level. Each node has links to its neighbors, and a parent link set during a search. In C++:

```cpp
struct NavNode {
    Vec3 pos;
    std::vector<NavNode*> neighbors;
    NavNode* parent;                 // set during a search
};
```

- **Must accept** building the graph, a search over it such as A*, and freeing it all at once.
- The cost of the replacement (indices vs. pointers: size and checks) must be stated.

### A9 · A value that owns a buffer and views into it (self-referential)

**A value owns some bytes and wants fast views of a table inside them**, as a font owns its file and views its glyph table. In C++:

```cpp
struct Font {
    std::vector<uint8_t> file;              // owns the bytes
    std::span<const GlyphRecord> glyphs;    // points into 'file'
};
```

- State the idiom. An offset-based answer is acceptable if its cost is named.

### A10 · Lending iterator over mutable chunks

**Iterate `MutableSpan<Float>` chunks of 64 elements from a list, and pass each chunk to a kernel that mutates it.** In Rust:

```rust
for chunk in data.chunks_mut(64) { simd_kernel(chunk); }
```

Two mutable chunks from one iterator, live at once, would alias ([02](../../spec/02-views-and-dependencies/dependency-lifetimes.md#staying-valid-after-a-parameter-moves-on-outlives)).

- **Must accept** safe code with no copies.

### A11 · Locks: guards and closures

**Code holds a lock across several statements, without a closure.** It acquires the lock, gets a view of the protected data, uses the view across several statements, and releases the lock at scope end. In Rust:

```rust
{
    let mut reg = REGISTRY.lock().unwrap();   // the guard
    let list = &mut reg.entries;              // a view of the protected data
    list.push(e);
    list.sort();
}                                             // unlocked here
```

Separately, the closure form of the lock returns a value computed from the protected data. The criteria below use it, and guards moved into closures:

```swift
let count = mutex.lock { data in … }                              // the closure form, returning what it computes
let h = Handler(onClick: { [move g] in print(g.value.count) })    // a guard 'g', moved into a stored closure
let n = total({ [move g] in g.value.count })                      // another guard 'g', moved into a closure argument
```

- **Must accept** the guard as a scoped value, or state the closure-only cost.
- **Must accept** a helper that returns the guard, as a method of a struct holding the mutex or as a free function over a global mutex, and a service-locator function that returns the view a global `Once` lends.
- **Must accept** the closure form returning an owned result, generically.
- **Must accept** a guard moved into a closure, as `h` and `n` above show, with `n`'s line followed by taking the same lock again.
- **Must accept** two `Slice`s of one locked blob read at once on one thread, and a shared lock's `read` nested in its own `read`, even while a writer waits.
- **Must accept** a struct of `Synchronized` fields and reference-counted pointers to other `Synchronized` values, such as a log `Mutex` and an audio mixer, shared by every thread with no lock of its own and used from any thread.

### A12 · Sorting with a comparator that borrows

**Sort a list of handles by a key the comparator reads from the pool they index**, such as each object's distance to a point. In C++:

```cpp
std::sort(targets.begin(), targets.end(), [&](Handle a, Handle b) {
    return dist(enemies[a].pos, player) < dist(enemies[b].pos, player);
});
```

- **Must accept** a comparator closure that borrows the pool and isn't allocated.

### A13 · Interned strings

**An interner returns ids that are cheap to compare and to store in other values, and that resolve back to text.**

- **Must accept** storing interned ids in pool elements, comparing them in O(1), and getting the text for logging.
- State what replaces Rust's `&'static str` / `&'interner str`.

### A14 · Callbacks that need context

**A callback registered now must mutate program state when it fires later**, as a UI button's "on click" does. Elsewhere, a factory function builds and returns a closure that owns its captures. A callback that outlives the call that made it owns its captures instead of borrowing them ([05](../../spec/05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)), so it can't hold a borrow of the state it changes.

The criteria below use these function values:

```swift
let put: (mutable List<StringView>) -> Void = { … }                  // a local function value made from a literal
let h = Handler(onClick: { … })                                      // a literal passed to a struct's initializer
let r = wrap({ [move s] in s.count })                                // a closure kept by its concrete type in a generic struct
each(enemies.span) { e in if e.hp < 10 { low.append(tag.view) } }    // a closure passed for a 'some F' parameter
```

- **Must accept** a safe idiom, spelled out, such as a handle plus an event queue, or a context passed at fire time.
- **Must accept** the factory returning its closure as a `Closure<() -> Int>`.
- **Must accept** each of these:
    - a local holding a function value made from a literal, such as `put` or `h` above, used for the rest of its scope;
    - a named function or operator stored as a function value and called long after;
    - a literal that captures nothing as a parameter's default or as a returned plain function type.
- **Must accept** a local tokenizer closure that advances a captured position and returns views of a shared source, with two tokens live at once.
- **Must accept** a `mutating` closure local that owns a moved-in list, passed to a function taking `consuming () -> Void` and then called again, its list destroyed once.
- **Must accept** a closure kept by its concrete type in a generic struct, as `r` keeps it above, with its field passed to a function that takes a plain function type.
- **Must accept** the call to `each` above through a `some mutating (Enemy) -> Void` parameter, with `low` depending only on `tag` afterwards.

### A17 · Remembering what a function saw

**A function scans a local list of candidates and wants to keep the ones it picked for later calls.** It can't keep a view of its local list past the call, since the list is destroyed when the function returns ([02](../../spec/02-views-and-dependencies/dependency-rules/absorption-and-accesses.md#rule-5-the-callee-side)).

- **Must accept** keeping them as owned values, such as a `List<T>` of copies, or as `Handle`s.

### A19 · Enumerating while mutating, in parallel

**A job system's parallel loop hands its body each element of a collection together with the element's index.** A sequential loop over a temporary does the same:

```swift
grid.cells.forEachIndexedInParallel { i, cell in cell.value = f(i) }   // each call gets an element and its index
for (i, e) in &makeItems().enumerated() { … }                        // sequential, over a temporary whose elements it changes
```

- **Must accept** with the true index in every call and no copy of the collection. Show how the library's splitting keeps each part's starting index.
- **Must accept** the sequential form over a temporary above, which changes its elements, with the true index in every iteration and no copy of the temporary.

### A20 · Mutating through a list of existential views

**A function collects mutable views of values of three different types into a local list.** The types conform to one protocol, and the function then calls a mutating requirement through each view. In C++:

```cpp
Damageable* targets[] = { &player, &boss, &crate };   // three different types
for (Damageable* t : targets) t->takeDamage(10);
```

- **Must accept** with no boxing and no allocation beyond the list.

---

## B. Object graphs

### B1 · A hierarchy updated parent-first, with reparenting

**A tree of many nodes with parent handles and child lists is updated parent-first**, and a node can be reparented during the same update, as a scene graph's transforms are.

- **Must accept** O(n) update, reparenting, and cycle prevention (reparenting a node under its own descendant must be detected).

### B2 · Two arguments that may be one value

**A function mutates two values that may be the same one**, as `attack(attacker, target)` does when an entity damages itself. In C++:

```cpp
void attack(Entity& attacker, Entity& target) {
    attacker.stamina -= 10;
    target.hp -= attacker.power;
}
attack(e, e);    // both parameters name one entity
```

The law of exclusivity lets nothing else reach a place while it is mutably borrowed, so one call can't lend the same value for change twice ([01](../../spec/01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)).

- **Must accept** an idiom that handles the aliasing case correctly and explicitly.

### B3 · A coroutine waiting on an object that is destroyed

**A coroutine waits on a condition about an object, and meanwhile another part of the program destroys the object and a new one reuses its slot.** The coroutine is a `task`, which its owner steps explicitly ([07](../../spec/07-concurrency/tasks.md#semantics)). This one waits for an enemy to be gone:

```swift
await until { [copy target] game in game.enemies[target] == nil }   // the condition, polled at each step
```

- **Must hold:** the task observes that the object is gone, and doesn't observe the new occupant.

### B4 · Event dispatch

**Parts of a program publish events, and handlers in other parts mutate shared state in response.** Handlers can publish further events.

- **Must accept** a design with no global mutable state and no stored mutable borrow of anything.
- It must be deterministic in order.
- Handler recursion (an event published while dispatching) must have defined behavior.

### B5 · Moving a value between containers

**A move-only value, such as an item that owns a `String` description, moves from one container to another.** A collection's element can't simply be moved out, since its place must still hold a value for every later use ([01](../../spec/01-values-and-ownership/moving-values-out.md#what-can-be-moved-from)).

The criteria below use these declarations and statements:

```swift
consuming func close() throws(IoError)               // on a file whose deinit closes it
consuming func intoItems() -> List<T>                // on a wrapper, moving its field out

give(makeLoot().item)                                // a field moved out of a call result
builder.finish(builder.count)                        // 'finish' is consuming
adopt(list, list.count)                              // 'adopt' takes its first parameter owned
when connect().state { .open(let buf) { … } … }      // matches part of a temporary whose type has a deinit
when connect() { .open(var b) { b.append(0) } … }    // changes a payload in place
for s in consume tags { names.append(s) }            // 'tags' is an inline array of Strings
let e = if c { borrow enemies[0] } else { makeEnemy() }     // a place on one path, a value on the other
let b = borrow attr ?? Bounds(lo: 0, hi: 1)                 // the same, through ??
```

- **Must accept** moving it without cloning. If the values live in a pool and the containers hold handles, show that instead, and state which is idiomatic.
- **Must accept** the same moves through `replace(&slot, with:)`, `swap`, an `Optional` field's `take()` or `remove(at:)`.
- **Must accept** moving a field out of an owned local, or out of a call result as `give` does above, whose type has no `deinit`. The rest is destroyed at the scope's or statement's end.
- **Must accept** a `deinit` handing a field, or a `List` in its enum's own payload, to another owner.
- **Must accept** `close` above on a file whose `deinit` closes it, closing it once on every path, and a wrapper's `intoItems` above, which moves its field out.
- **Must accept** the `finish` call above for a `consuming` `finish`, and the `adopt` call for an `owned` first parameter.
- **Must accept** matching a temporary whose type has a `deinit`, as the first `when` above does, and changing a payload in place, as the second does.
- **Must accept** the loop over `consume tags` above, over an inline array of `String`s, with a `break`.
- **Must accept** the bindings of `e` and `b` above, each borrowing on one path and owning on the other, used in later statements.

### B7 · Queries over optional components

**Entities have optional components of many types.** A query needs every entity with two given components but not a third, with dense iteration.

- **Must accept** an ECS-style library written in Rayo with no macros, using reflection or generics, iterating in parallel through a job system with statically checked disjointness between component storages.

---
