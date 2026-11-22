# Bindings

[01 · Values and ownership](../01-values-and-ownership.md)

**A declaration says two things about the binding it makes, with one word for each: whether the binding owns a value or refers to a place, and whether it may change.** A parameter's convention says the same where the parameter is declared ([Parameters](parameters.md#parameters)). So the declaration tells a reader what the source may do while the name lives, whether the name can be consumed, and who destroys the value.

| | Can't change | May change |
| --- | --- | --- |
| Owns a value | `let x = v` | `var x = v` |
| Refers to a place | `ref let x = p` | `ref var x = &p` |

**`ref` marks a binding that refers to a place.** `ref let` borrows the place read-only, and `ref var` borrows it for change. A `let` or `var` declaration without `ref` owns what it binds, and a condition's binding writes the same four words with the same meanings ([below](#conditions)). A `for` name or a `when` payload name writes none of them, since its subject says what it is ([below](#for-and-when-names)). Each other operation has one spelling, the same in every position: `&` lends a place for change, `copy` makes a second value, and `consume` moves the value out ([Moving values out](moving-values-out.md#moving-values-out)).

```swift
var enemies = loadEnemies()

ref let seen = enemies[0]          // refers to the enemy, read-only: nothing copied
ref var boss = &enemies[0]         // refers to it for change: boss.hp = 0 changes enemies[0]
var spare = copy enemies[0]        // a second enemy of its own
let last = enemies[1]              // error: write 'copy' or 'consume' before 'enemies[1]', or declare 'ref let'
let hp = enemies[1].hp             // a Float is implicitly copyable: a copy, with nothing written
ref var next = enemies[1]          // error: write '&enemies[1]'
ref let other = &enemies[1]        // error: '&' lends for change; declare 'ref var'
let first = consume enemies[0]     // error: an element can't move out of its list
let mesh = loadMesh()              // a value, not a place: the binding owns it
let all = consume enemies          // a move: 'enemies' can't be used until it gets a new value
```

| Form | Like the parameter | Meaning | Cost |
| --- | --- | --- | --- |
| `ref let x = place` | `_ x: T` | A shared **borrow** of `place`, of any type: `place` can't be changed, moved or destroyed while `x` is live | None |
| `ref var x = &place` | `_ x: mutable T` | A mutable **borrow** of a [changeable place](#changeable-places): `place` is reachable only through `x` while `x` is live | None |
| `let x = consume place`, `var x = consume place` | `_ x: owned T` | A **move** from a place the code owns ([What can be moved from](moving-values-out.md#what-can-be-moved-from)): `place` can't be used until it gets a new value | A `memcpy` at most |
| `let x = copy place`, `var x = copy place` | | An independent **copy** of a copyable value; a move-only one is copied with `alloc place.clone()` | A `memcpy` |
| `let x = f()`, `var x = f()` | | The binding owns the value, even a move-only scoped value such as a `MutableSpan` or a lock guard ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)); `_ = x` ends it early, unless its type is implicitly copyable | None |
| `let x = place`, `var x = place`, of an implicitly copyable type | | An independent **copy**, with nothing written ([Implicit copies](moves-copies-destruction.md#implicit-copies)) | A `memcpy` |
| `let x = place`, `var x = place`, of any other type | | A compile error that names `copy`, `consume` and `ref let`, with the exceptions below | |

## Bindings that refer to a place

**A binding that refers to a place it borrows is a borrowing binding**, and can't be consumed, since the place's value has another owner. A declaration or a condition makes one only with `ref`. A `for` name or a `when` payload name makes one when its subject is a place ([below](#for-and-when-names)).

- **`ref let` and `ref var` declare locals**, so they appear only in a function or closure body. A borrow lasts no longer than the body that makes it ([How long a borrow lasts](#how-long-a-borrow-lasts)).
- **A `ref var` takes `&` before its place, and a `ref let` takes none**, since `&` marks every mutable borrow of a place ([Lending a place for change](#lending-a-place-for-change)). So a `ref var` given a place without `&` is a compile error that says to write it. A `ref let` given a place with `&` is one that says to declare `ref var`, since a `ref let` changes nothing.
- **`var` on a borrowing binding means the place may change through it**, never that the name may point elsewhere. So `x = q` on a `ref var` writes `q` into the place `x` refers to. Pointing the name at another place is a `rebind` ([02](../02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind)).
- **A `ref let` or `ref var` given a value, with no place to refer to, is a compile error** that says to write `let` or `var`, which own it. A call's result, a literal, an operator's result, `copy place`, `consume place` and what a value property's `get` returns are values. So is a place in a temporary's own storage, such as `makeEnemy().hp`, which a `let` owns instead ([below](#bindings-that-own-a-value)). An `if`, `when` or `??` whose arms mix places and values is the exception: each value is kept in a hidden local ([below](#if-and-when-as-values)).
- **Views taken from a `ref let` depend on the place itself** ([02](../02-views-and-dependencies/dependency-projection-and-results.md#rule-1-projection)).
- **A place that a `where return outlives self` place property hands out from a temporary lies outside the temporary**, such as `makeSpan()[0]`. So a `ref let` can refer to it, depending on what the temporary carries ([02](../02-views-and-dependencies/dependency-projection-and-results.md#temporaries)).
- **No borrowing binding may bind an under-aligned place**: that is a compile error, since a load or store of its type at that address may be invalid, and fault on some targets ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)).

```swift
ref var lead = &enemies[0]
lead = makeEnemy()                 // writes the new enemy into enemies[0]; 'lead' still refers to it
ref let hp = makeEnemy().hp        // error: the enemy dies with the statement; write 'let'
```

## Bindings that own a value

**A `let` or `var` declaration owns what it binds**, as a binding of a call's result does. So it can move its value on, and a `let` still can't change it. A condition's `let` or `var` owns an optional's payload by the same rules ([below](#conditions)).

- **A `let` or `var` given a place writes `copy` or `consume` before it, or is declared `ref let`.** Leaving all three out is a compile error that names them, since the place's value already has an owner. That holds as well for an expression the initializer hands its position to: the last expression of an `if` or `when` arm or of an `unsafe` block ([below](#if-and-when-as-values)), or an operand of `??` ([04](../04-types/enums.md#optionals)). The exceptions are below.
- **A `let` or `var` given `&place` is a compile error that says to write `ref var`**, since `&` lends the place, and a binding without `ref` refers to no place. Where `&place` makes a view of a type of its own, such as the mutable form of a `get`, the binding owns that view instead ([Lending a place for change](#lending-a-place-for-change)).
- **An assignment from a place writes `copy` or `consume`**, and leaving both out is a compile error that names them, as [Moves](moves-copies-destruction.md#moves) says. A place of an implicitly copyable type needs neither, as below.

**Four exceptions need none of `copy`, `consume` and `ref let`, since each gives the binding a value of its own to own:**

- **A place of an implicitly copyable type** is copied, and stays usable ([Implicit copies](moves-copies-destruction.md#implicit-copies)). So `let x = p`, `var x = p` and `x = p` of an `Int` copy it.
- **A copyable `const`** gives a new value each time ([Constants](moving-values-out.md#constants)).
- **A conversion that makes a value from the place**, such as a view of it, a numeric widening, or a copyable value's conversion to or from its static type, gives a new value ([below](#conversions)).
- **A place in a temporary's own storage dies with its statement**, such as `makeEnemy().pos`. So a `let` or `var` of one owns that value, moving it out as [What can be moved from](moving-values-out.md#what-can-be-moved-from) allows. Where that can't move it, the binding is a compile error unless it is written with `copy`, or with `alloc` and `.clone()`.

## What a `ref let` sees

**Changing a place while a `ref let` that refers to it is used is a compile error**, since the `ref let` is a shared borrow ([The law of exclusivity](exclusivity.md#the-law-of-exclusivity)). For a place reached through an object or a thread-local, it is a panic instead ([below](#how-long-a-borrow-lasts)). A `Synchronized` value still changes through its own synchronization ([07](../07-concurrency/synchronization.md#the-synchronized-contract)).

**Making a field computed, or stored, never silently changes what a binding of it gets.** What a binding of `e.f` gets follows from how `f` is declared:

- **A stored field** is a place: a `ref let` refers to it, and `consume` moves it out of `e`, as [What can be moved from](moving-values-out.md#what-can-be-moved-from) allows.
- **A value property** gives the value its `get` returns, which a `let` owns ([02](../02-views-and-dependencies/place-and-value-properties.md#value-properties-get-and-set)).
- **A place property** lends its place, as a stored field does, and can't be moved from ([02](../02-views-and-dependencies/place-and-value-properties.md#place-properties-borrow-and-mutate)).

So a binding that fits one form is a compile error under the other. A `let` of a stored field takes `copy`, `consume` or `ref let`, and a `ref let` of a value property has no place to refer to. A `let` of an implicitly copyable field fits both, since it copies the stored field and owns what the `get` returns:

```swift
extension Enemy { var isDead: Bool { hp <= 0 } }   // computed

func hit(_ e: mutable Enemy, _ d: Float) {
    ref let before = e.hp
    e.hp -= d                      // error: 'before' still refers to e.hp
    log(before)
    let now = e.hp                 // stored: a copy of the Float, as a computed 'hp' would give
    let dead = e.isDead            // computed: the Bool it returned, which 'dead' owns
    ref let gone = e.isDead        // error: 'isDead' is computed, so there is no place to refer to; write 'let'
    save(dead)                     // fine: save takes an owned parameter
    let hp = consume e.hp          // error: 'e' is a mutable parameter, so e.hp can't move out of it
}
```

## How long a borrow lasts

**A borrow lasts until its last use, not to the end of the scope.** Once `boss` above is last used, `enemies` is free again. Where destroying the value that holds the borrow is a use ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)), that destruction is its last use.

**A borrowing binding of a dynamic place holds its access until its last use.** A dynamic place is one reached through a thread-bound object's owner or weak pointer, or a thread-local, and the binding holds that dynamic access (rule 6 in [02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). So a call in between that changes the object panics. When a panic unwinds through the binding's scope, the access is released once the unwind has destroyed the last value that depends on it ([Destruction by unwinding](moves-copies-destruction.md#destruction-by-unwinding)).

**A `let` or `var` declaration never holds a dynamic access itself**, since it refers to no place. Only a view it owns can depend on one, as any view taken through the access does ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). So a change to an object between a `let`'s uses panics only where the `let` holds such a view. The exception is a `let` or `var` that a `rebind` has pointed at a place, which then holds that place's access as a borrowing binding does ([02](../02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind)). A `ref let` or `ref var` condition is a borrowing binding as its declaration is, and so is a `for` or `when` name bound to a part of a place ([below](#for-and-when-names)).

## Names in scope

**A local or a parameter can't take a name that a local or a parameter in scope already has.** That holds whether the other one was declared in the same block or in an enclosing one, and the compiler rejects the second declaration. So each name stands for one binding wherever the body uses it. A reader never has to work out which of two declarations a use reaches. What the compiler says about a name, that it was moved, is borrowed or is narrowed, is about the one binding declared with it.

```swift
func total(_ prices: Span<Int>, discount: Int) -> Int {
    let discount = min(discount, 50)         // error: 'discount' is already declared, as a parameter
    var sum = 0
    for p in prices {
        let net = p - discount
        sum += net
    }
    let net = sum - discount                 // fine: the loop's 'net' went out of scope with its block
    for net in prices { sum += net }         // error: 'net' is already declared, in the enclosing block
    return net
}
```

**A local is in scope from the end of its declaration to the end of the block that declares it.** So a declaration's initializer never sees its own name. It reads an outer one, such as a global's, and the declaration is an error only where that outer one is a local or a parameter:

```swift
let limit = 10                               // a global

func clamp(_ n: Int) -> Int {
    let limit = limit * 2                    // fine: the initializer reads the global 'limit'
    return min(n, limit)
}
```

**A parameter is in scope through the whole body of the function or closure that takes it.** A `task func`'s resume parameter, which its `with (...)` clause declares, is a parameter of its body too ([07](../07-concurrency/tasks.md#semantics)).

**A `let`, `var`, `ref let`, `ref var` or `const` in a body declares a local, and so does each name these constructs bind**, in scope where the construct uses it:

- an `if`'s or a `while`'s condition names, in each later condition of its list and in its block;
- a `guard`'s condition names, in each later condition of its list and after the `guard` to the end of the enclosing block, but not in its `else` block;
- a `when` arm's names, in its `where` guard and its block;
- a `catch` clause's names, such as `e` in `catch e` or `field` in `catch .badValue(field)`, in its `where` guard and its block;
- a `for` or `static for` pattern's names, in its `where` clause and its block;
- a closure literal's parameters, written or implicit, such as `$0`, in its body.

**The rule holds wherever a body sees a name:**

- **One declaration.** Two names of one parameter list, one pattern or one list of conditions can't be the same either, as in the first two lines below. The patterns that share a `when` arm bind one set of names, so a name they repeat is one binding, not a reuse ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)).
- **Closure literals.** A closure's body sees the enclosing body's locals and parameters, and captures those it names ([05](../05-protocols-generics-and-closures/functions-and-closures.md#capturing-places)). So its parameters and locals can't take their names, and that includes its implicit parameters: a closure that names `$0` can't contain another closure that names `$0`. A capture list names a local or a parameter already declared, and declares nothing new.
- **Nested functions and local types.** Their bodies see none of the enclosing body's locals or parameters ([05](../05-protocols-generics-and-closures/functions-and-closures.md#functions-and-closures)), and neither does a member of a local extension. So they may reuse those names, since nothing they would shadow is in scope there.
- **Names declared outside the body.** The rule covers only locals and parameters. A local may share the name of a function, a field or a global, and lookup decides which one each use reaches ([05](../05-protocols-generics-and-closures/functions-and-closures.md#static-and-instance-members)).

```swift
func pair(_ a: Int, _ a: Bool) { … }                              // error: 'a' is already declared, as a parameter
ref let (lo, lo) = bounds                                         // error: 'lo' is already declared, in this pattern

alloc func names(_ entries: Span<Entry>) -> List<StringView> {
    alloc entries.map { entries in entries.name.view }            // error: 'entries' is already declared, as a parameter
}
let ready = alloc groups.map { alloc $0.items.filter { $0.ok } }  // error: '$0' is already declared, by the outer closure
let kept = alloc groups.map { g in alloc g.items.filter { $0.ok } }   // fine: the outer closure names its parameter

func report(_ count: UInt) {
    func double(_ count: UInt) -> UInt { count * 2 }    // fine: 'double' sees none of report's parameters
    log("\(double(count))")
}
```

**So a `let`, a `var` or a `ref` binding always gives the reader a name to follow.** It binds at least one name ([below](#bindings-with-no-name)), and no name it binds is one a local or a parameter in scope already has. An optional local or parameter is unwrapped under its own name by narrowing, which binds nothing ([below](#unwrapping-an-optional)).

## Conditions and patterns

**A condition's binding writes `let`, `var`, `ref let` or `ref var`, with the meaning each word has in a declaration, and a `for` name or a `when` payload name writes no word, since its subject says what it is.** The two subsections below give each rule ([Conditions](#conditions), [`for` and `when` names](#for-and-when-names)). Each position in a pattern reads a bare name one way ([12](../12-grammar/constructs.md#patterns)).

**No pattern holds a `let` or `var` of its own.** A declaration's, a condition's or a `for` loop's pattern is a name, `_` or a tuple of these, and every name in it binds. Code that binds names in two ways writes a declaration for each, as a `ref var` and a `ref let` borrow two fields of one value in two ways ([09](../09-compile-time/reflection.md#tuples-field-lists-and-queries)). A `when` arm's pattern has rules of its own ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)).

### Conditions

**A condition of an `if`, a `while` or a `guard` holds only what can fail: a `Bool` test, or an optional binding.** An **optional binding** binds its names to the value inside an optional, and only when the optional holds one. Its word says what the names are:

```swift
if let job = queue.pop() { done.append(job) }        // owns the job that pop moved out
if var job = queue.pop() { job.priority += 1 }       // owns it, and may change it
if ref let e = world.enemies[h] { log(e.hp) }        // refers to the enemy where it lies in the pool
if ref var e = &world.enemies[h] { e.hp = 0 }        // refers to it for change
while let job = queue.pop() { run(job) }             // each job in turn, until pop returns nil
guard ref let e = world.enemies[h] else { return }   // refers to the enemy to the end of the scope
```

- **A binding follows the rules of a declaration with the same word** ([above](#bindings)). `let` and `var` own the payload, so a `let` or `var` given a place is the compile error that names `copy`, `consume` and `ref let`, unless the place's type is implicitly copyable, as `T?` is where `T` is. Then the binding owns a copy, and the place stays as it was. `ref let` refers to the payload read-only, and `ref var` refers to it for change, with `&` before its place. A `ref let` or `ref var` given a value is the compile error that says to write `let` or `var`.
- **The right side is any expression of optional type**, `copy place` and `consume place` included. A `let` or `var` of a value, such as a call's result, takes the payload out of it. `consume x` moves the whole optional out of `x`, whether it holds a value or not, and the binding owns its payload. `copy x` gives the binding a copy, and leaves `x` free for the block to change.
- **A binding whose right side isn't an optional is a compile error** that says to declare the name before the `if`, `while` or `guard`, since such a binding can't fail. A name for something that is always there belongs in a declaration.
- **A `guard` binds as an `if` does**, and its names stay in scope after it, to the end of the enclosing block ([Names in scope](#names-in-scope)).
- **The pattern binds at least one name** ([below](#bindings-with-no-name)). A tuple pattern binds the parts of an optional tuple, such as two elements of one pool ([Two elements of one collection](exclusivity.md#two-elements-of-one-collection)).

```swift
if let e = copy world.enemies[h] {
    world.enemies.remove(h)                       // fine: 'e' is a copy, so nothing borrows the pool
    spawnCorpse(e)
}
if let m = consume reply { send(m) }              // moves the optional out: 'reply' holds no value after this
if let t = world.target { chase(t) }              // a Handle<Enemy>? is implicitly copyable: 't' owns a copy
if ref let e = enemies[0] { … }                   // error: 'enemies[0]' isn't an optional; declare 'ref let e' before the 'if'
```

**A condition list's subjects are held together, under the law of exclusivity, as one call's arguments are** ([Evaluation order](parameters.md#evaluation-order-and-when-a-calls-borrows-begin)). Each binding's borrow or take is checked against every other one's in the list. So two bindings can't borrow overlapping places when either lends its place for change:

```swift
if ref var a = &world.enemies[h1], ref var b = &world.enemies[h2] { … }   // error: both lend 'world.enemies' for change; write 'ref var (a, b) = &world.enemies[h1, h2]'
```

**A `Bool` test that checks an optional against `nil` may narrow it instead of binding it** ([below](#unwrapping-an-optional)).

**A condition holds no case or comparison pattern, so it tests a case with `==`, and a `when` binds a payload** ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)). Every enum compares with one of its cases that carries no payload, as in `state == .idle` ([05](../05-protocols-generics-and-closures/operators.md#equality-and-ordering)). A case with a payload is matched by a `when` arm, which binds the payload's names for the arm's block:

```swift
if state == .idle { wander() }
when state {
    .chase(t) { track(t) }                        // 't' borrows the payload of 'state'
    else {}
}
```

### `for` and `when` names

**A `for` name and a `when` payload name are bare, and the subject says what each one is.** A loop or a match binds all its names from one subject, so the subject's form says once what they all are: a place, a place lent with `&`, or a value. A `for` loop's iterator decides which elements it hands out as values of their own ([04](../04-types/collections.md#iteration)):

| What the name binds | The name is |
| --- | --- |
| A part of a place, as in `for e in enemies` or `when event` | A read-only borrow of it, or the owner of a copy when its type is implicitly copyable ([Implicit copies](moves-copies-destruction.md#implicit-copies)) |
| A part of a place lent with `&`, as in `for e in &enemies` or `when &shape` | A mutable borrow of it, whatever its type |
| A value: what an iterator hands out as its own, or a part of a call's result, of `consume s` or of `copy s` | Its owner |

- **Nothing points such a name at another value.** It takes no `let` or `var`. An owned name is read-only, as a `let` is, and code that would change its value declares a `var` from it. An exclusive view it owns, such as a chunk, still writes through itself ([Exclusive access](#exclusive-access)). A mutable borrow writes through to its element or part, as a `ref var` does, so `r *= 2` below changes `shape`.
- **A borrowing name can't be consumed**, since what it borrows has another owner. An owned name can be, as a `let` can.
- **`consume` marks a subject whose names own what they bind**, as `&` marks one whose names borrow it for change. `consume` takes the subject out of a place the code owns ([What can be moved from](moving-values-out.md#what-can-be-moved-from)), as in the second example below.
- **A `when` name takes its part out of a value subject only once its arm is chosen**, since patterns and guards run under a borrow of the subject until then ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)).
- **A `deinit` on the path keeps a value subject whole.** This holds in an arm where any of its patterns has, on the path to a part, a type that declares a `deinit`, whichever pattern matched. The value stays whole in a hidden local until the arm ends, as a `for` loop's sequence does. The arm's names borrow its parts, read-only, or for change where the subject is marked `&`. So the `deinit` runs on the changed value, and nothing moves out of it.
- **A temporary subject lent with `&` is kept whole the same way**, as a loop keeps `&makeEnemies()` ([04](../04-types/collections.md#iteration)), so its names borrow its parts for change until the arm ends.
- **In a type's own `deinit`, that type's `deinit` keeps nothing whole**, since it is already running. So `when consume self` takes an enum `self`'s payload apart there ([What can be moved from](moving-values-out.md#what-can-be-moved-from)).
- **A subject in a temporary's own storage that can't be moved out is kept whole the same way**, with the whole temporary in that hidden local, as `connect().state` is where `Conn` declares a `deinit`.

```swift
when &shape {
    .circle(r) { r *= 2 }                  // a mutable borrow: doubles the radius inside 'shape'
    else {}
}
when consume event {
    .message(m) { inbox.append(m) }        // 'event' is moved out: 'm' owns the message
    else {}
}
for e in enemies { e.hp = 0 }              // error: 'e' is a read-only borrow; write '&enemies' to change the elements
for i in 0..<n { i += 1 }                  // error: 'i' owns its Int, and is read-only; declare 'var j = i' to change a copy
```

## Bindings with no name

**Every binding that a `let`, `var`, `ref let` or `ref var` makes binds at least one name, or it is a compile error.** The words say how its names hold what they bind: whether they own it or refer to it, and whether they may change it ([above](#bindings)). With no name, they say nothing. Each binding of a declaration is one binding, so `let lo = 0, _ = f()` is an error, though `lo` is bound. So is each optional binding of a condition ([above](#conditions)).

A `_` is fine inside a pattern that binds another name, as in `ref let (a, _) = pair`. A `for` name and a `when` payload name write no word for a missing name to leave unexplained, so a `_` in their place is fine.

```swift
ref let (a, _) = pair                     // fine: binds 'a'
let _ = save(level)                       // error: binds no name
let lo = 0, _ = f()                       // error: the second binding binds no name
ref let (_, _) = pair                     // error: binds no name
if let _ = target { ... }                 // error: binds no name; write 'target != nil'
for _ in 0..<3 { spawn() }                // fine: a loop's name writes no word
```

**Code that binds nothing has a form without `let` or `var`:**

- `_ = x` drops a value on purpose ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unused-values));
- `x != nil` tests whether an optional holds a value ([04](../04-types/enums.md#optionals));
- `is E` matches a value of type `E` without binding it ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if));
- a `_` on its own matches any part of a payload without binding it, as in `.pair(a, _)` ([12](../12-grammar/constructs.md#patterns)).

## Unwrapping an optional

**Narrowing unwraps an optional under its own name, and a binding unwraps it under a new one.** Checking `x != nil` narrows a local, a parameter or a stored field of one in place, with no binding at all ([04](../04-types/enums.md#narrowing)). Anything else that holds an optional, such as an element, a global or a place reached through an object, binds its payload to a new name. That name can't be one that a local or a parameter in scope has ([Names in scope](#names-in-scope)):

```swift
var reply: Message? = conn.receive()
if reply != nil { log("got \(reply.kind)") }    // narrows 'reply' to the Message inside it
if ref let t = window.value.target { … }        // a place reached through an object, under a name of its own
if ref let reply = reply { … }                  // error: 'reply' is already declared; write 'reply != nil'
```

**For a place that narrows, narrowing and a `ref let` or `ref var` binding give the block the same payload**, under the place's own name or a new one. A block that only reads the payload does the same with either, and so does one that changes it in place. They differ in what the block may do to the optional itself:

- **Narrowing keeps the place an optional.** The block may assign it, `nil` included, move its payload out, call `take()` on it or pass it whole to a `T?` parameter, and each event that could make it `nil` ends the narrowing.
- **A `ref let` or `ref var` binding borrows the payload**, which holds the optional still while the binding is live. So nothing can make it `nil` there, and the binding can't be consumed.

So narrowing fits code that goes on treating the place as an optional, such as code that clears it once done with it. A binding fits code that needs only the payload. For a place that doesn't narrow, such as a global or a thread-local, a binding is the only checked way to name the payload, since `x!` panics on `nil`, and `x?.` and `??` check again at each use. A `ref let` or `ref var` binding holds the place's borrow until its last use, and a thread-local's access with it ([How long a borrow lasts](#how-long-a-borrow-lasts)):

```swift
@threadlocal var session: Session? = nil

func report() {
    guard ref let s = session else { return }   // refers to this thread's session in place, holding its access
    log(s.name)
}
```

## `if` and `when` as values

**An `if` or `when` expression hands its position to the arm that runs.** Whatever the position does with a value, it does with the arm's last expression, as if that expression stood there: borrows it, lends it for change, moves it or returns it. An `unsafe` block used as an expression hands its position to its last expression the same way ([10](../10-errors-and-safety/unsafe-code.md#unsafe-code)).

```swift
ref let e = if first { enemies[0] } else { enemies[1] }             // refers to one of the two
ref var t = if left { &a } else { &b }                              // refers to one for change
let v = if c { consume p } else { consume q }                       // moves from the one chosen
let w = if c { p } else { q }                                       // error: write 'copy' or 'consume' before 'p', or declare 'ref let'
```

What depends on `e` depends on both places ([02](../02-views-and-dependencies.md#dependencies)). `v` moves from the one chosen, so each of `p` and `q` is moved only on its own path ([Moving values out](moving-values-out.md#moving-values-out)).

**When some arms give places to a `ref let` or `ref var` and others give values, each value is kept in a hidden local:**

```swift
ref let e = if c { enemies[0] } else { makeEnemy() }         // the new enemy is kept in a hidden local
```

The hidden local is declared where the binding is, and destroyed with it if its arm ran. The binding is then a borrowing binding, which can't be consumed. What depends on it depends on every arm's place, and on those hidden locals.

## Conversions

**A converted value is a new value.** When a binding's declared type differs from its initializer's, the conversion says what it does with a place ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)):

- **A numeric widening, and a copyable value's conversion to or from its [static type](../02-views-and-dependencies/scoped-values.md#converting-to-and-from-a-static-type), read the place** and make a new value, which the binding owns. A move-only value's conversion to or from its static type takes it, as the conversions below do.
- **These conversions take the value**, so in a binding a place takes `consume` or `copy` before it, and leaving both out is a compile error that names them. A place of an implicitly copyable type is copied instead, as `h` is below ([Implicit copies](moves-copies-destruction.md#implicit-copies)):
    - wrapping it in an optional or an error union, or as a `Result`'s `.success`;
    - making a `Box<T>` or an object pointer into one of an existential;
    - moving a closure into a `Closure`.
- **Making an `any P` from a place borrows the place shared**, as making any view of it does, and the binding, `let` or `var`, owns the view. So a `var` of one may later point at another value. `&place` makes a `mutable any P` instead ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)). A `String` or a `List` made into its view borrows the place shared too ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)).

```swift
let total: Int = n                          // 'n' is an Int32: the widened Int is a new value 'total' owns
let all: Span<Enemy> = enemies              // borrows the List 'enemies'; 'all' owns the view
var spare: Enemy? = copy boss               // wrapping a copy of the enemy
let pick: Enemy? = boss                     // error: wrapping takes the enemy; write 'copy' or 'consume'
var last: Enemy? = consume boss             // or wrapping the enemy itself, moved out of 'boss'
var target: Handle<Enemy>? = h              // a Handle is implicitly copyable: wrapping a copy, and 'h' stays usable
var d: any Drawable = sprite                // borrows 'sprite'; 'd' owns the view, and may later view another value
```

## Changeable places

**Only a changeable place can be changed, or lent with `&`**, so a shared borrow never becomes a write. A place is **changeable** when it is:

- a `var` that owns its value;
- a temporary, which its statement owns ([02](../02-views-and-dependencies/dependency-projection-and-results.md#temporaries));
- the place that a `ref var`, or a `for` or `when` name of a subject lent with `&`, refers to, through that binding;
- a `mutable` or `owned` parameter, or `self` in a `mutating` or `consuming` method, a `deinit` or an initializer, except `self` in an exclusive view's `mutating` member (below);
- an owned capture of a `mutating` or `consuming` closure;
- a `var` field, an element, or a property with a `mutate` or a `set` ([02](../02-views-and-dependencies/place-and-value-properties.md#place-and-value-properties)), of a changeable place;
- a place that an exclusive view held with [exclusive access](#exclusive-access) hands out through a `mutate`, such as `lives[0]` for a `MutableSpan` that a `let` owns.

**Everything else is read-only**: a `let`, a `ref let`, a borrowed parameter, `self` in a plain method, a `let` field, a `const` and a global `let`. So is whatever is reached through one of these, except a place listed above, such as an element of a `MutableSpan` that a `let` owns.

```swift
let x = makeEnemy()
ref var y = &x                     // error: a let is read-only, even one that owns its value
heal(&x)                           // error: the same
```

**There are four exceptions, each with its own way of keeping exclusivity**, the first two checked at run time:

- **A `@threadlocal var`**, which its own thread changes under a dynamic mark on each access ([07](../07-concurrency/global-state.md#thread-locals)).
- **An object's value**, which is changeable whatever holds its owner or weak pointer, since each access takes a dynamic mark ([03](../03-handles-and-objects.md#dynamic-exclusivity)).
- **A `Synchronized` value**, whose non-`mutating` methods change it through its own synchronization ([07](../07-concurrency/synchronization.md#the-synchronized-contract)).
- **`unsafe` code**, which may change a bare global `var` or an imported C variable ([07](../07-concurrency/global-state.md#global-state)), and the memory a raw pointer points at, whatever holds the pointer ([10](../10-errors-and-safety/unsafe-code.md#raw-accesses)). It promises to keep exclusivity itself ([10](../10-errors-and-safety/unsafe-code.md#what-unsafe-code-upholds)).

```swift
let r = renderer.weak()
_ = r.value?.submit(mesh)          // fine: an object's value is changeable through a let of a weak pointer
```

**An exclusive view writes through itself with exclusive access, not a changeable place**, which is why the places it hands out are changeable ([02](../02-views-and-dependencies/scoped-values.md#exclusive-views)).

### Exclusive access

**A place is held with exclusive access when nothing else reaches it while it is used**, whether or not it may change. That is what writing through an exclusive view needs, and an owned binding has it as a mutable borrow does:

| The view is held by | Writes through it |
| --- | --- |
| an owned `let`, or a value an iterator hands out | yes |
| a `ref var`, a `mutable` parameter, a part of a `&` subject | yes |
| any other changeable place, or a parameter received owned | yes |
| a `ref let`, a borrowed parameter, an element of a sequence that isn't lent | no |

- **Every changeable place is held with exclusive access**, and so are these, which can't change: a `let` that owns its value, a `for` or `when` name that owns what it binds ([above](#for-and-when-names)), and `self` in an exclusive view's `mutating` member.
- **A stored field of a place held with exclusive access is held so too**, whether it is a `let` or a `var` field.
- **A shared borrow is never held with exclusive access, and nor is anything reached through it**, since other code may read the place at the same time. That covers `self` in a plain method and a capture of a non-`mutating` closure too.

## Lending a place for change

**`&` marks every place lent for change, in a binding as in a call.** The receiver of a `mutating` method call is the exception, since the call's form shows it. These places take `&`, each lent to code that may change it:

- a `mutable` argument;
- the place a `ref var` declaration or condition refers to;
- the target of a `rebind` of a `ref var` or a `var` ([02](../02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind));
- a loop's sequence whose elements the loop changes, which may be a temporary the loop keeps in a hidden local ([04](../04-types/collections.md#iteration));
- a `when` subject whose payload names change its parts, which may be a temporary the `when` keeps in a hidden local ([above](#for-and-when-names));
- the last expression of an `if` or `when` arm whose position lends a place for change;
- a place holding a `mutating` closure, a `Closure<mutating …>` or a `mutating` function value, made into a new function value ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions));
- the place that a place property's `mutate` hands out ([02](../02-views-and-dependencies/place-and-value-properties.md#place-properties-borrow-and-mutate));
- a place made into a `mutable any P` ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch));
- an exclusive view held with exclusive access that lends a new view of what it views ([02](../02-views-and-dependencies/scoped-values.md#exclusive-views)).

```swift
for (i, e) in &makeEnemies().enumerated() { ... }       // the loop keeps the new list in a hidden local, and changes it
ref var t = if left { &a } else { &b }                   // the arm's place is lent for change
let v: mutable any Damageable = &boss                    // a mutable any P made from 'boss'
```

**What follows `&` is a changeable place, a member of one that has a mutable form, or an exclusive view held with exclusive access.** Leaving `&` out is a compile error, and so is `&` on something that lends nothing for change. An exclusive view that isn't a changeable place lends only what it views: a new view of it, or its elements to a loop, never the place that holds the view ([02](../02-views-and-dependencies/scoped-values.md#exclusive-views)).

- **`&` picks a mutable form.** Where a method or property has a shared and a mutable form of one name, the operand of `&` picks the mutable one ([04](../04-types/collections.md#shared-mutable-and-consuming-forms-of-one-method)). So a binding of `&particles.life` binds an [`SoA`](../04-types/data-layout.md#struct-of-arrays-soat) column as a `MutableSpan<Float>` that it owns, where a binding of `particles.life` gets a `Span<Float>`, as in the example below.
- **A binding of a value lends nothing, so it takes no `&`.** A call result bound to a name is owned by its binding. That includes an owned value of a move-only scoped type ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)), such as the guard that `registry.lock()` returns, which changes the registry through it.
- **A call result lent for change takes `&`, as any changeable place does**, when it is a `mutable` argument, a loop's sequence or a `when` subject. It is a temporary, which its statement owns, or which the loop or the `when` owns in a hidden local, as in the example below.
- **A `zip` marks its own arguments**, as in `zip(&vels, forces)`, so a loop over it needs no `&` of its own ([04](../04-types/collections.md#iteration)).

```swift
let lives = &particles.life        // the mutable form: a MutableSpan<Float> that 'lives' owns
lives[0] = 1
let ages = particles.life          // the shared form: a Span<Float>
log("first age \(ages[0])")
let g = registry.lock()            // no '&': 'g' owns the guard, and changes the registry through it
g.value.flush()
heal(&makeEnemy())                 // the statement owns the new enemy, and destroys it after the call
```
