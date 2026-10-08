# Absorption, callee checks and dynamic accesses

[02 · Views and dependencies](../02-views-and-dependencies.md#dependencies)

Across a call, the caller and callee have different parts of the dependency check. The caller accounts for views the callee may store in a mutable argument; the callee verifies what it actually returns or stores. Accesses the compiler cannot prove safe from place names alone also need a run-time check that lasts as long as their views.

## Rule 4: Absorption

**After a call, every scoped `mutable` argument, a `mutating` method's `self` included, takes on what the other arguments borrow.** This is the caller's side of rule 5 for stores. A callee can store a view into a `mutable` argument, as `append` does, and rule 5 lets it store only what its caller lent it. Absorption adds all of that to the argument's set, so the caller learns what the argument now borrows without seeing the body.

**An `owned` argument that is a mutable view, and a `modify`'s yield, absorb too** (below). Each absorbing argument takes on the places and sets of the borrowed arguments, and the sets of the `mutable` and scoped `owned` ones, with the kinds of rule 3:

```swift
tokens.append(Token(text: src.view))   // 'tokens' now depends on 'src'
lexer.lex(into: &tokens)               // 'lexer' and 'tokens' stay free of each other
```

**Another `mutable` argument's place flows in only when a `where` item names it** ([Precise dependencies (opt-in)](dependency-lifetimes.md#precise-dependencies-opt-in)), since rule 5 rejects storing a view of another `mutable` parameter's place unless an item names it. A function that keeps views of one `mutable` argument in another names it:

```swift
func chunks(_ data: mutable List<Float>, into work: mutable List<MutableSpan<Float>>)
    where work borrows data                  // 'work' keeps views of 'data'
```

**Where the place assigned is known, assigning a variable that owns its value, or a stored field, replaces that place's set** ([Naming a field](dependency-lifetimes.md#naming-a-field)). The old value is destroyed, so nothing it reached is reachable through the place. Through a binding that may name one of several places, the assignment adds to each place's set instead, since the others may still hold their old views. That happens after a `rebind` on one path, or after this:

```swift
var r = if flip { &d1 } else { &d2 }    // an assignment through 'r' adds to the sets of both
```

**Any other change to part of a value, such as to an element, adds to the value's set.**

**Stores through an exclusive view reach what it views.** Such a store lands in memory that the view's exclusive dependencies own, so those places can now reach what was stored. So a dependency added to an exclusive view, or to a place reached through one, is also added to **every place the view depends on exclusively**, transitively. That holds however the dependency is added, and each time, the collection the view came from then depends on `tmp` or `crate`:

```swift
for v in &views { v = tmp.span }        // by assignment through the view
fill(&left, tmp.span)                   // by absorption into it, here a 'split' half
for d in &targets { d = &crate; break }       // by storing a borrow into a list of exclusive views, once
```

**Writing a whole new value through an exclusive view adds and never replaces**, since the view may cover only part of what it depends on.

**When such a place belongs to the caller, the store is a store into the caller's place, and rule 5 applies.** That holds whatever convention brought the view in: a `mutable` parameter, an `owned` `MutableSpan`, a `mutable any P`, or an owned `mutating` closure with exclusive captures. Every exclusive dependency a parameter carries in is treated like a `mutable` parameter, by rule 5 and by its use at every exit ([below](#rule-5-the-callee-side)).

**On the caller's side, an `owned` argument that is a mutable view absorbs like a `mutable` one**, since it can be stored through too. Examples are an `owned` `MutableSpan`, a `mutable any P` and a `mutating` closure ([Mutable views](dependency-projection-and-results.md#mutable-views)). So `poison(consume left)` makes `views`, which `left` was split from, absorb the call's other arguments.

**A borrowed argument absorbs nothing, whatever it carries**, since nothing is stored through a borrowed view. What safe code can write through a shared path holds only unscoped values: an object's value, a thread-local and the contents of a `Synchronized` value ([Generic code and `~Scoped`](scoped-values.md#generic-code-and-scoped)).

**In generic code, a value whose type may be a mutable view counts as one where a store reaches the caller's place, and where an `owned` argument absorbs.** Such a type is a type parameter, an associated type, a `some P`, or a type that depends on one, unless its constraints include `Copyable` or `~Scoped`. So an `owned T` absorbs like a `mutable` argument. What a parameter of such a type carries in counts as exclusive. So when an `owned T` parameter, with `T: Sink`, stores `local.view` through `put`, that is a store into the caller's place.

**For these rules, creating a closure counts as a call to a primary initializer whose arguments are its captures**, so a closure's captures are tracked as a call's arguments are. No code can name or call that initializer ([09](../09-compile-time/reflection.md#what-reflection-can-read)). The captures are passed this way:

- an exclusive by-reference capture as a `mutable` argument;
- a shared one borrowed;
- an owned one `owned`.

So `names` depends on `tmp` from the closure's creation, whether or not the closure is called:

```swift
var add = { names.append(tmp.view) }    // 'names' now depends on 'tmp'
```

**A `consuming` closure's exclusive captures also take on each other's places**, since its one call may store a view of one into another (rule 5).

**When a closure is called, its `mutable` arguments absorb the closure's dependency set**, as its `self` ([Closure calls](dependency-projection-and-results.md#closure-calls)):

```swift
let put: (mutable List<StringView>) -> Void = { o in o.append(src.view) }
put(&out)                               // 'out' now depends on 'src'
```

**An argument that absorbs a place the closure captures exclusively also depends on the closure, exclusively, unless the call consumes it.** What the caller can see decides this, as it does for a result ([Closure calls](dependency-projection-and-results.md#closure-calls)).

**The closure itself absorbs only what its `keep` arguments carry**, never the argument places ([05](../05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-keep)). A `mutating` closure absorbs what its `keep` arguments carry into itself, and so into the places it depends on exclusively. Its other parameters are call-scoped, lent only for the call, so nothing it was lent reaches its captures. So a closure lent data for one call, such as a lock's, can't keep a view of it.

**A projection access is a call to its accessor**, with the subscript's arguments and `self`. A `modify`'s yield is one more `mutable` argument, since the code after the `yield` may store what the caller wrote there: a subscript's `mutable` parameter absorbs it ([Projections: `read` and `modify` accessors](projections-and-accessors.md#projections-read-and-modify-accessors)).

## Rule 5: The callee side

**A function can return, throw or store only what its caller lent it.** Rules 3 and 4 tell the caller what a call borrows from the signature, and rule 5 checks each body against that. So the caller's sets hold without the caller seeing the body. A returned or thrown scoped value, and anything stored into a scoped `mutable` parameter, may depend only on:

- the borrowed or `mutable` parameters and their dependency sets, except that what is stored into a `mutable` parameter depends on another `mutable` parameter itself only when a `where` item names it ([above](#rule-4-absorption));
- the sets carried in by scoped `owned` parameters, which belong to the caller and flow back through rules 3 and 4;
- static storage.

**Static storage** is global `let`s and `const`s ([07](../07-concurrency/global-state.md#global-state)), and the views that the `Synchronized` values in them lend, such as a lock guard or `Once.get()` ([07](../07-concurrency/synchronization.md#the-synchronized-contract)). Such a global is never moved or destroyed ([07](../07-concurrency/global-state.md#shutdown)), so any function may return a view of it.

**What a C entry returns to C, or stores into what C lent it, may depend on less** ([08](../08-c-interop/calling-rayo-from-c.md#what-a-c-entry-hands-back-to-c)), since nothing in Rayo holds what it borrowed once it returns.

```swift
func name() -> StringView {
    let s: String = "temp"
    return s.view                      // error: returned view depends on local 's', which is destroyed on return
}
```

**Rule 5 rejects what rules 3 and 4 couldn't report to the caller:**

- **A view of what the function itself owns or began**, since each is released or ended when the call returns. That is a local, storage an `owned` parameter owns but not the borrows it carries, a thread-local, or a dynamic access or access-bound projection begun inside the function. The non-`mutable` parameters of an `@export` or `@c` function, or of a closure literal converted to a `@c` type, count as `owned` here, since C passes them by value ([08](../08-c-interop/calling-rayo-from-c.md#calling-rayo-from-c)).
- **Anything stored into a `mutable` parameter `p` that depends on a place overlapping `p`**, since rule 4 tells the caller nothing new about its own argument. The caller's set for `p` would have to name `p` itself.
- **Anything stored through a parameter's exclusive dependencies that depends on the parameter's own storage**, which rule 4 never reports.

For example, with a `Doc` that keeps a view of its own text, and a struct that holds an exclusive view:

```swift
struct Doc(var text: String, var first: StringView?): Scoped

func index(_ d: mutable Doc) {
    d.first = d.text.view              // error: a store into 'd' that depends on a part of 'd'
}
doc.first = doc.text.view              // fine in the caller's own body: 'doc' then depends on 'doc.text'

struct Lines(var out: MutableSpan<StringView>, var s: String, var view: StringView): Scoped {
    mutating func fill() {
        out[0] = s.view                // error: a store through 'out' that depends on self's own storage
        out[0] = copy view             // fine: depends only on what the field 'view' carries
    }
}
```

**In the caller's own body, that assignment is an error only when destroying `doc` uses the dependency** ([When destroying a value counts as using it](dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)).

**Scoped `mutable` parameters count as used at every exit**: each `return`, `throw` and propagating `try`, and the end of the body. So a callee can't store a view into `out` and then free what it points at, even on its way out with an error.

**A closure body is checked as a method whose `self` is the closure.** Its by-reference captures are places `self` depends on, shared or exclusive, and a result or a store into a `mutable` parameter may depend on them.

**A closure's owned captures are always an `owned` parameter's own storage, whatever the closure's kind.** A closure may be called through a view of its storage, and a call through a `consuming` type ends that view and destroys a `consuming` closure's captures ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds), [05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)). So a result or a store may depend on what owned captures carry, never on the captures themselves:

```swift
let f = { [move s] in s.view }     // error: the result views an owned capture
```

**A store into a capture may depend on these:**

- places captured by shared reference;
- what any capture carries;
- what parameters declared `keep` carry ([05](../05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-keep));
- static storage.

**Parameters not declared `keep` are call-scoped**, lent only for one call, so a closure can return what depends on one, but can't store it:

```swift
entries.map { $0.name.view }      // returns what depends on its parameter; storing it would be an error
```

**A store into a capture may not depend on a place the closure captures exclusively**, unless the closure is `consuming`, since the next call may change or free it:

```swift
var fill = { buf.append(1); views.append(buf.span) }   // error: the next call changes 'buf'
```

## Rule 6: Dynamic accesses

**An access to an object, a `Slice` or a thread-local lasts until nothing uses it.** The compiler can't prove these accesses safe, so each is checked at run time, in the dynamic tier ([01](../01-values-and-ownership.md#tiers-of-checking)). Rule 6 makes that check last as long as anything that came through the access. Each of these **dynamic accesses** is itself a dependency:

- an access to an object's value, through its owner or a weak pointer;
- an access to a `Slice`'s buffer, through its `read()` or `lock()` ([06](../06-memory-and-allocators/owning-values.md#long-lived-views-into-long-lived-buffers));
- an access to a thread-local `var`.

**A view derived from the access, or passed through a call, depends on it:**

```swift
let items = r.value!.items.span   // derived from the access to the object 'r' points at
let e = first(r.value!)           // passed through a call
```

**The access is held until the last use of every value that depends on it**, so the run-time mark covers the view for its whole life. An access-bound projection's access is held the same way, with its accessor suspended at the `yield`.

**A site in a loop's body or `while` condition holds one access at a time**, since a set names an access by the site that began it. Each time the site begins a dynamic access, or an access-bound projection's access, no value that depends on the access it began the last time may be used from then on:

```swift
for w in nodes { names.append(w.value!.name.view) }   // error
```

That loop is an error, since every pass would keep its own access: the second pass's `append` uses `names`, which depends on the first pass's.

**A `rebind` step through objects is an exception.** It may begin an access while its target depends on the old one, since the step moves that target to the new access ([`rebind`](dependency-lifetimes.md#pointing-a-name-at-another-place-rebind)).
