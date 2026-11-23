# Absorption, callee checks and dynamic accesses

[02 · Views and dependencies](../02-views-and-dependencies.md#dependencies)

Across a call, the caller and callee have different parts of the dependency check. The caller accounts for views the callee may store in an argument lent for change; the callee verifies what it actually returns or stores. Accesses the compiler cannot prove safe from place names alone also need a run-time check that lasts as long as their views.

## Rule 4: Absorption

**After a call, every scoped argument given to a `mutable &T` parameter, a `mutating` method's `self` included, takes on what the other arguments borrow.** This is the caller's side of rule 5 for stores. A callee can store a view into a `mutable` argument, as `append` does, and rule 5 lets it store only what its caller lent it. Absorption adds all of that to the argument's set, so the caller learns what the argument borrows after the call without seeing the body.

**An owned argument that is a mutable view absorbs too** (below). Each absorbing argument takes on the places and sets of the `&` arguments, and the sets of the `mutable` and scoped owned ones, with the kinds of rule 3:

```swift
tokens.append(Token(text: src))        // 'tokens' depends on 'src' from here on
lexer.lex(into: mutable tokens)        // 'lexer' and 'tokens' stay free of each other
```

**Another `mutable` argument's place flows in only when a `where` item names it** ([Precise dependencies (opt-in)](dependency-lifetimes.md#precise-dependencies-opt-in)), since rule 5 rejects storing a view of another `mutable &T` parameter's place unless an item names it. A function that keeps references into one `mutable` argument in another names it:

```swift
func chunks(_ data: mutable &List<Float>, into work: mutable &List<mutable &[Float]>)
    where work borrows data                  // 'work' keeps references into 'data'
```

**Where the place assigned is known, assigning a variable that owns its value, or a stored field, replaces that place's set** ([Naming a field](dependency-lifetimes.md#naming-a-field)). The old value is destroyed, so nothing it reached is reachable through the place. Through a binding that may name one of several places, the assignment adds to each place's set instead, since the others may still hold their old views:

```swift
ref var r = if flip { mutable d1 } else { mutable d2 }      // an assignment through 'r' adds to the sets of both
```

**Any other change to part of a value, such as to an element, adds to the value's set.**

**Stores through an exclusive view reach what it views.** Such a store lands in memory that the view's exclusive dependencies own, so those places can then reach what was stored. So a dependency added to an exclusive view, or to a place reached through one, is also added to **every place the view depends on exclusively**, transitively. That holds however the dependency is added, and each time, the collection the view came from then depends on `tmp` or `crate`:

```swift
for v in mutable views { v = tmp }                          // by assignment through the view
fill(mutable left, tmp)                                     // by absorption into it, here a 'mutableSplit' half
for d in mutable targets { d = mutable crate; break }       // by storing a borrow into a list of mutable references, once
```

**Writing a whole new value through an exclusive view adds and never replaces**, since the view may cover only part of what it depends on.

**When such a place belongs to the caller, the store is a store into the caller's place, and rule 5 applies.** That holds whatever brought the view in: a `mutable &T` parameter or an owned value that holds a mutable reference. Every exclusive dependency a parameter carries in is treated like a `mutable &T` parameter, by rule 5 and by its use at every exit ([below](#rule-5-the-callee-side)).

**On the caller's side, an owned argument that is a mutable view absorbs like a `mutable` one**, since it can be stored through too. Examples are an owned struct of mutable references and a `List<mutable &any Damageable>` ([Mutable views](dependency-projection-and-results.md#mutable-views)). So `views`, which `low` and `high` were split from, absorbs this call's other arguments:

```swift
let (low, high) = views.span.mutableSplit(at: 2)
poison(Halves(low: consume low, high: consume high), tmp)    // 'views' depends on 'tmp' from here on
```

**An owned function value is no absorbing argument, even a `mutating` one, which is a mutable view**, since nothing a call of it stores into its captures may depend on its arguments ([05](../05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-from-its-parameters)). The same holds for a closure of concrete type owned through a `some F` parameter, or through a type parameter constrained to a function type. So the temporary key below leaves nothing borrowed:

```swift
func forEachMatch(_ key: &Key, _ body: mutating (&Symbol) -> Void) { … }

var hits = alloc List<&Text>()
forEachMatch(Key(text: "if", hash: h)) { _ in hits.append(name) }     // 'hits' takes on 'name', never the temporary key
print("\(hits.count) matches")
```

A function value or a closure given to a `mutable &T` parameter absorbs as any `mutable` argument does, since the callee may replace it with another closure.

**A `&` argument absorbs nothing, whatever it carries**, since nothing is stored through a shared view. What safe code can write through a shared path holds only unscoped values: an object's value, a thread-local and the contents of a `Synchronized` value ([Generic code and `~Scoped`](scoped-values.md#generic-code-and-scoped)).

**In generic code, a value whose type may be a mutable view counts as one where a store reaches the caller's place, and where an owned argument absorbs.** Such a type is a type parameter, an associated type, a `some P`, or a type that depends on one, unless its constraints include `Copyable` or `~Scoped`. So an owned `T` absorbs like a `mutable` argument. What a parameter of such a type carries in counts as exclusive. So when an owned `T` parameter, with `T: Sink`, stores `&local` through `put`, that is a store into the caller's place.

**For these rules, creating a closure counts as a call to a primary initializer whose arguments are its captures**, so a closure's captures are tracked as a call's arguments are. No code can name or call that initializer ([09](../09-compile-time/reflection.md#what-reflection-can-read)). The captures are passed this way:

- an exclusive by-reference capture as a `mutable` argument;
- a shared one as a `&` argument;
- an owned one to a parameter that owns it.

So `names` depends on `tmp` from the closure's creation, whether or not the closure is called:

```swift
var add = { names.append(tmp) }     // 'names' depends on 'tmp' from here on
```

**A `consuming` closure's exclusive captures also take on each other's places**, since its one call may store a view of one into another (rule 5).

**When a closure is called, its `mutable` arguments absorb the closure's dependency set**, as its `self` ([Closure calls](dependency-projection-and-results.md#closure-calls)):

```swift
let put: (mutable &List<&Text>) -> Void = { o in o.append(src) }
put(mutable out)                        // 'out' depends on 'src' from here on
```

**An argument that absorbs a place the closure captures exclusively also depends on the closure, exclusively, unless the call consumes it.** What the caller can see decides this, as it does for a result ([Closure calls](dependency-projection-and-results.md#closure-calls)).

**The closure itself absorbs nothing from its arguments**, since nothing it stores into its captures may depend on its parameters ([05](../05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-from-its-parameters)). So nothing it was lent reaches its captures, and a closure lent data for one call, such as a lock's, can't keep a view of it.

**An access through a place property is a call to its accessor**, with `self` and the subscript's arguments, and its place depends on its sources ([Place and value properties](place-and-value-properties.md#what-a-place-depends-on)). No accessor code runs after the caller's access. So what the caller stores into a `mutate`'s place is a change to part of each source it depends on exclusively, and of what that source holds exclusively. Each of those takes it on (above). An argument that is no source, such as a key or a `mutable &T` parameter no item names, takes on nothing.

## Rule 5: The callee side

**A function can return or store only what its caller lent it.** Rules 3 and 4 tell the caller what a call borrows from the signature, and rule 5 checks each body against that. So the caller's sets hold without the caller seeing the body. A returned scoped value, an error it fails with included, and anything stored into a scoped `mutable &T` parameter, may depend only on:

- the `&` and `mutable &T` parameters and their dependency sets, except that what is stored into a `mutable &T` parameter depends on another `mutable &T` parameter itself only when a `where` item names it ([above](#rule-4-absorption));
- the sets carried in by scoped owned parameters, which belong to the caller and flow back through rules 3 and 4;
- static storage.

**Static storage** is global `let`s and `const`s ([07](../07-concurrency/global-state.md#global-state)), and the views that the `Synchronized` values in them lend, such as a lock guard or `Once.get()` ([07](../07-concurrency/synchronization.md#the-synchronized-contract)). Such a global is never moved or destroyed ([07](../07-concurrency/global-state.md#shutdown)), so any function may return a view of it.

**What a C entry returns to C, or stores into what C lent it, may depend on less** ([08](../08-c-interop/calling-rayo-from-c.md#what-a-c-entry-hands-back-to-c)), since nothing in Rayo holds what it borrowed once it returns.

```swift
func name() -> &Text {
    let s = alloc "temp"
    return s                           // error: the returned reference depends on local 's', which is destroyed on return
}
```

**Rule 5 rejects what rules 3 and 4 couldn't report to the caller:**

- **A view of what the function itself owns or began**, since each is released or ended when the call returns. That is a local, storage an owned parameter owns but not the borrows it carries, a thread-local, or a dynamic access or a value property's change begun inside the function. The parameters of an `@export` or `@c` function that C passes by value, and those of a closure literal converted to a `@c` type, count as owned here ([08](../08-c-interop/calling-rayo-from-c.md#calling-rayo-from-c)).
- **Anything stored into a `mutable &T` parameter `p` that depends on a place overlapping `p`**, since rule 4 tells the caller nothing new about its own argument. The caller's set for `p` would have to name `p` itself.
- **Anything stored through a parameter's exclusive dependencies that depends on the parameter's own storage**, which rule 4 never reports.

For example, with a `Doc` that keeps a reference to its own text, and a struct that holds a mutable reference:

```swift
struct Doc(var text: String, var first: (&Text)?): Scoped

func index(_ d: mutable &Doc) {
    d.first = d.text                   // error: a store into 'd' that depends on a part of 'd'
}
doc.first = doc.text                   // fine in the caller's own body: 'doc' then depends on 'doc.text'

struct Lines(var out: mutable &[&Text], var s: String, var view: &Text): Scoped {
    mutating func fill() {
        out[0] = s                     // error: a store through 'out' that depends on self's own storage
        out[0] = view                  // fine: a copy, which depends only on what the field 'view' carries
    }
}
```

**In the caller's own body, that assignment is an error only when destroying `doc` uses the dependency** ([When destroying a value counts as using it](dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)).

**Scoped `mutable &T` parameters count as used at every exit**: each `return`, `throw` and propagating `try`, each point that can panic ([10](../10-errors-and-safety/panics.md#unwinding)), and the end of the body. So a callee can't store a view into `out` and then free what it points at, even on its way out with an error or a panic. At a call that can panic, they count as used with what that call may have stored in them, as rule 4 adds after it returns ([above](#rule-4-absorption)), since the panic may leave from inside it.

**A closure body is checked as a method whose `self` is the closure.** Its by-reference captures are places `self` depends on, shared or exclusive, and a result or a store into a `mutable &T` parameter may depend on them.

**A closure's owned captures are always an owned parameter's own storage, whatever the closure's kind.** A closure may be called through a view of its storage, and a call through a `consuming` type ends that view and destroys a `consuming` closure's captures ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds), [05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)). So a result or a store may depend on what owned captures carry, never on the captures themselves:

```swift
let f = { [move s] in &s }     // error: the result refers to an owned capture
```

**A store into a capture may depend on these:**

- places captured by shared reference;
- what any capture carries;
- static storage.

**Nothing a closure stores into its captures may depend on its parameters** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-from-its-parameters)), so a closure can return what depends on one, but can't store it:

```swift
let names = alloc entries.map { &$0.name }   // the closure returns what depends on its parameter; storing it would be an error
log("\(names.count) names")
```

**A store into a capture may not depend on a place the closure captures exclusively**, unless the closure is `consuming`, since the next call may change or free it:

```swift
var fill = { buf.append(1); views.append(buf) }    // error: the next call changes 'buf'
```

## Rule 6: Dynamic accesses

**An access to an object, a `Slice` or a thread-local lasts until nothing uses it.** The compiler can't prove these accesses safe, so each is checked at run time, in the dynamic tier ([01](../01-values-and-ownership.md#tiers-of-checking)). Rule 6 makes that check last as long as anything that came through the access. Each of these **dynamic accesses** is itself a dependency:

- an access to an object's value, through its owner or a weak pointer;
- an access to a `Slice`'s buffer, through its `read()` or `lock()` ([06](../06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers));
- an access to a thread-local `var`.

**A view derived from the access, or passed through a call, depends on it:**

```swift
let items = &r.value!.items       // derived from the access to the object 'r' points at
let e = first(r.value!)           // passed through a call
```

**The access is held until the last use of every value that depends on it**, so the run-time mark covers the view for its whole life. When the access ends, the language releases its mark itself. When a panic unwinds instead, the mark is released once the unwind has destroyed the last value that depends on the access ([10](../10-errors-and-safety/panics.md#unwinding)). A value property's change is held the same way, with `set` called once it ends, and never on an unwind ([Value properties: `get` and `set`](place-and-value-properties.md#value-properties-get-and-set)).

**A site in a loop's body or `while` condition holds one access at a time**, since a set names an access by the site that began it. Each time the site begins a dynamic access, or a value property's change, no value that depends on the access it began the last time may be used from then on:

```swift
for w in &nodes { names.append(w.value!.name) }    // error
```

That loop is an error, since every pass would keep its own access: the second pass's `append` uses `names`, which depends on the first pass's.

**An assignment that points a reference at a place reached through itself is an exception.** It may begin an access while the reference depends on the old one, since the assignment moves the reference to the new access ([Assigning a reference to a `var`](dependency-lifetimes.md#assigning-a-reference-to-a-var)).
