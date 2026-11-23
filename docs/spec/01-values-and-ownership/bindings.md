# Bindings

[01 · Values and ownership](../01-values-and-ownership.md)

**A declaration says two things about the binding it makes, with one word for each: whether the binding holds a value or is a place, and whether it may change.** A parameter's type says the same where the parameter is declared ([Parameters](parameters.md#parameters)). So the declaration tells a reader what the source may do while the name lives, whether the name can be consumed, and who destroys the value.

| | Can't change | May change |
| --- | --- | --- |
| Holds a value | `let` | `var` |
| Is a place | `ref let` | `ref var` |

**`ref` marks a binding that is a place.** It takes a reference and names the place the reference refers to: `ref let` names it read-only, and `ref var` names it for change. A `let` or `var` holds a value, which it owns, and that value may be a reference: `let best = &enemies[0]` holds a `&Enemy`. A condition's binding writes the same four words with the same meanings ([below](#conditions)). A `for` name or a `when` payload name writes none of them, since its subject says what it is ([below](#for-and-when-names)).

**An initializer given a place writes `&`, `mutable &`, `consume` or `copy` before it**, as every position does, unless the place's type is implicitly copyable, or the binding is annotated with a `&T`, which lends it ([References](references.md#places-given-to-a-position)). So each binding shows what it does to the place it is given:

```swift
var enemies = loadEnemies()

ref let seen = &enemies[0]           // names the enemy, read-only: nothing copied
ref var boss = mutable &enemies[0]   // names it for change: boss.hp = 0 changes enemies[0]
let best = &enemies[1]               // holds a '&Enemy', a reference to the enemy
let top: &Enemy = enemies[1]         // the same: the annotation expects a reference, so 'enemies[1]' is lent
var spare = copy enemies[0]          // a second enemy of its own
let last = enemies[1]                // error: write 'copy' or '&' before 'enemies[1]'
let hp = enemies[1].hp               // a Float is implicitly copyable: a copy, with nothing written
ref let next = enemies[1]            // error: write '&enemies[1]'
ref var other = &enemies[1]          // error: write 'mutable &enemies[1]'
ref let lead = mutable &enemies[1]   // error: 'mutable &' lends for change; declare 'ref var'
let first = consume enemies[0]       // error: an element can't move out of its list
let mesh = loadMesh()                // a value, not a place: the binding owns it
let all = consume enemies            // a move: 'enemies' can't be used until it gets a new value
```

| Form | Like the parameter | Meaning | Cost |
| --- | --- | --- | --- |
| `ref let x = &place` | `_ x: &T` | A shared **borrow** of `place`, of any type: `place` can't be changed, moved or destroyed while `x` is live | None |
| `ref var x = mutable &place` | `_ x: mutable &T` | A mutable **borrow** of a [changeable place](#changeable-places): `place` is reachable only through `x` while `x` is live | None |
| `let x = &place`, `let x: &T = place`, `var x = mutable &place` | | The binding holds a reference to `place`, which borrows it as a `ref` binding would, and a `var` may later point it elsewhere ([below](#bindings-that-own-a-value)) | The reference's own bytes ([References](references.md#layout)) |
| `let x = consume place`, `var x = consume place` | `_ x: T` | A **move** from a place the code owns ([What can be moved from](moving-values-out.md#what-can-be-moved-from)): `place` can't be used until it gets a new value | A `memcpy` at most |
| `let x = copy place`, `var x = copy place` | | An independent **copy** of a copyable value; a move-only one is copied with `alloc place.clone()` | A `memcpy` |
| `let x = f()`, `var x = f()` | | The binding owns the value, even a move-only scoped value such as a `mutable &[T]` or a lock guard ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)); `_ = consume x` ends it early | None |
| `let x = place`, `var x = place`, of an implicitly copyable type | | An independent **copy**, with nothing written ([Implicit copies](moves-copies-destruction.md#implicit-copies)) | A `memcpy` |
| `let x = place`, `var x = place`, of any other type | | A compile error that names the marks that fit, with the exceptions that [References](references.md#places-given-to-a-position) lists | |

## Bindings that refer to a place

**A binding that is a place it borrows is a borrowing binding**, and can't be consumed, since the place's value has another owner. A declaration or a condition makes one only with `ref`. A `&T` or `mutable &T` parameter is one ([Parameters](parameters.md#parameters)), and so is a `for` or `when` name whose subject is a reference ([below](#for-and-when-names)).

- **`ref let` and `ref var` declare locals**, so they appear only in a function or closure body. A borrow lasts no longer than the body that makes it ([How long a borrow lasts](#how-long-a-borrow-lasts)).
- **A `ref let` takes a shared reference, and a `ref var` a mutable one**: `&p` or `mutable &p` of a place, or a reference value, such as a place that holds one or a call that returns one. A `ref var` needs a mutable reference, since it may change the place.
- **`var` on a borrowing binding means the place may change through it, never that the name may point elsewhere.** So `x = q` on a `ref var` writes `q` into the place `x` names. A `ref` binding never points elsewhere, though a `var` that holds a reference does ([below](#bindings-that-own-a-value)).
- **Views taken from a `ref let` depend on the place itself** ([02](../02-views-and-dependencies/dependency-projection-and-results.md#rule-1-projection)).
- **No borrowing binding may bind an under-aligned place**: that is a compile error, since a load or store of its type at that address may be invalid, and fault on some targets ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)).

**An initializer that doesn't agree with its `ref` binding is a compile error that names the fix:**

- `ref let x = p`, with a bare place `p` of a type that isn't a reference, says to write `&p`;
- `ref let x = mutable &p` says to declare `ref var`, since a `ref let` changes nothing;
- `ref var x = &p` says to write `mutable &p`;
- a `ref let` or `ref var` given a value that isn't a reference says to write `let` or `var`, which own it.

**A value that isn't a reference has no place to name.** A literal, an operator's result, `copy place`, `consume place`, what a value property's `get` returns, and a call's result of any type but a reference are such values. So is a part of a temporary, such as `makeEnemy().hp`, which a `let` owns instead ([below](#bindings-that-own-a-value)).

**A binding given a reference to a temporary is a compile error**, since the temporary dies with its statement and the binding would outlive it. So `ref let x = &makeEnemy()` and `let x = &makeEnemy()` both say to write `let x = makeEnemy()`. An `if` or `when` whose arms mix references to places and to temporaries is the exception: each temporary is kept in a hidden local ([below](#if-and-when-as-values)).

**A place reached through a reference that a temporary holds lies outside the temporary**, as `rows()[0]` does where `rows()` returns a `&[Row]`. So does a place that a `where return outlives self` place property hands out from a temporary. So a `ref let` can name either, depending on what the temporary carries ([02](../02-views-and-dependencies/dependency-projection-and-results.md#temporaries)).

**`ref var t = r`, where `r` is a changeable place holding a `mutable &T`, reborrows through `r`** ([References](references.md#reborrowing)). `t` names what `r` refers to, and `r` stays borrowed exclusively while `t` is used, so it isn't moved. `ref let e = r`, where `r` holds a `&T`, names what `r` refers to the same way.

```swift
ref var lead = mutable &enemies[0]
lead = makeEnemy()                   // writes the new enemy into enemies[0]; 'lead' still names it
ref let hp = &makeEnemy().hp         // error: the enemy dies with the statement; write 'let hp = makeEnemy().hp'
var pick = mutable &enemies[1]
ref var target = pick                // reborrows: 'target' names enemies[1], and 'pick' stays usable after it
target.hp = 0
```

## Bindings that own a value

**A `let` or `var` declaration owns the value it holds**, as a binding of a call's result does, and a reference is a value like any other. So it can move its value on, and a `let` still can't change it. A condition's `let` or `var` owns an optional's payload by the same rules ([below](#conditions)).

- **A `let` or `var` given a place writes a mark before it** ([above](#bindings)). Leaving it out is a compile error that names the marks that fit, since the place's value already has an owner. An annotation that is a `&T`, or an optional, a result or a static type of one, is the exception, and lends the place ([05](../05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected)). That holds as well for an expression the initializer hands its position to: the last expression of an `if` or `when` arm or of an `unsafe` block ([below](#if-and-when-as-values)), or an operand of `??` ([04](../04-types/enums.md#optionals)).
- **A `let` or `var` given `&p` or `mutable &p` holds the reference**, which borrows `p` as its kind says until the binding's last use ([References](references.md#making-a-reference)).
- **Writing through a reference that a `let` or `var` holds follows the rule for writing through any reference**, which only a `var` holding a `mutable &T` meets ([References](references.md#forwarding-through-a-reference)).
- **An assignment from a place writes a mark**, as every position does, unless the place it assigns holds a `&T`, or an optional, a result or a static type of one, which lends it ([Moves](moves-copies-destruction.md#moves), [05](../05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected)).

**Assigning to a `var` that holds a reference points it elsewhere.** `best = e` makes `best` refer to `e`, and the place it referred to is free once nothing else depends on it. What the `var` depends on from then on follows the dependency rules ([02](../02-views-and-dependencies.md#dependencies)):

```swift
var best = &enemies[0]
for e in &enemies { if e.hp > best.hp { best = e } }    // points 'best' at the enemy with the most hp
print("best hp \(best.hp)")
```

## What a `ref let` sees

**Changing a place while a `ref let` that names it is used is a compile error**, since the `ref let` is a shared borrow ([The law of exclusivity](exclusivity.md#the-law-of-exclusivity)). For a place reached through an object or a thread-local, it is a panic instead ([below](#how-long-a-borrow-lasts)). A `Synchronized` value still changes through its own synchronization ([07](../07-concurrency/synchronization.md#the-synchronized-contract)).

**Making a field computed, or stored, never silently changes what a binding of it gets.** What a binding of `e.f` gets follows from how `f` is declared:

- **A stored field** is a place: `&e.f` refers to it, and `consume` moves it out of `e`, as [What can be moved from](moving-values-out.md#what-can-be-moved-from) allows.
- **A value property** gives the value its `get` returns, which a `let` owns ([02](../02-views-and-dependencies/place-and-value-properties.md#value-properties-get-and-set)).
- **A place property** lends its place, as a stored field does, and can't be moved from ([02](../02-views-and-dependencies/place-and-value-properties.md#place-properties-borrow-and-mutate)).

So a binding that fits one form is a compile error under the other. A `let` of a stored field takes `copy`, `consume` or `&`, and `&` of a value property refers to a temporary that dies with its statement. A `let` of an implicitly copyable field fits both, since it copies the stored field and owns what the `get` returns:

```swift
extension Enemy { var isDead: Bool { hp <= 0 } }   // computed

func hit(_ e: mutable &Enemy, _ d: Float) {
    ref let before = &e.hp
    e.hp -= d                      // error: 'before' still names e.hp
    print("\(before)")
    let now = e.hp                 // stored: a copy of the Float, as a computed 'hp' would give
    let dead = e.isDead            // computed: the Bool it returned, which 'dead' owns
    ref let gone = &e.isDead       // error: 'isDead' is computed, so '&' lends a temporary; write 'let'
    save(dead)                     // fine: a Bool is implicitly copyable
    let hp = consume e.hp          // error: 'e' is a 'mutable &' parameter, so e.hp can't move out of it
}
```

## How long a borrow lasts

**A borrow lasts until its last use, not to the end of the scope.** Once `boss` above is last used, `enemies` is free again. A reference that a `let` or `var` holds borrows until the reference's last use, as a `ref` binding does. Where destroying the value that holds the borrow is a use ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)), that destruction is its last use.

**A borrowing binding of a dynamic place holds its access until its last use.** A dynamic place is one reached through a thread-bound object's owner or weak pointer, or a thread-local, and the binding holds that dynamic access (rule 6 in [02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). So a call in between that changes the object panics. When a panic unwinds through the binding's scope, the access is released once the unwind has destroyed the last value that depends on it ([Destruction by unwinding](moves-copies-destruction.md#destruction-by-unwinding)).

**A `let` or `var` declaration never holds a dynamic access itself**, since it is no place. Only a value it owns can depend on one, as a reference or any other view taken through the access does ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). So a change to an object between a `let`'s uses panics only where the `let` holds such a value, as `let s = &window.value` does. A `ref let` or `ref var` condition is a borrowing binding as its declaration is, and so is a `for` or `when` name whose subject is a reference ([below](#for-and-when-names)).

## Names in scope

**A local or a parameter can't take a name that a local or a parameter in scope already has.** That holds whether the other one was declared in the same block or in an enclosing one, and the compiler rejects the second declaration. So each name stands for one binding wherever the body uses it. A reader finds the declaration a use reaches by its name alone. What the compiler says about a name, that it was moved, is borrowed or is narrowed, is about the one binding declared with it.

```swift
func total(_ prices: &[Int], discount: Int) -> Int {
    let discount = min(discount, 50)         // error: 'discount' is already declared, as a parameter
    var sum = 0
    for p in &prices {
        let net = p - discount
        sum += net
    }
    let net = sum - discount                 // fine: the loop's 'net' went out of scope with its block
    for net in &prices { sum += net }        // error: 'net' is already declared, in the enclosing block
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
ref let (lo, lo) = &bounds                                        // error: 'lo' is already declared, in this pattern

alloc func ids(_ entries: &[Entry]) -> List<EntityId> {
    alloc entries.map { entries in entries.id }                   // error: 'entries' is already declared, as a parameter
}
let ready = alloc groups.map { alloc $0.items.filter { $0.ok } }  // error: '$0' is already declared, by the outer closure
let kept = alloc groups.map { g in alloc g.items.filter { $0.ok } }   // fine: the outer closure names its parameter

func report(_ count: UInt) {
    func double(_ count: UInt) -> UInt { count * 2 }    // fine: 'double' sees none of report's parameters
    print("\(double(count))")
}
```

**So a `let`, a `var` or a `ref` binding always gives the reader a name to follow.** It binds at least one name ([below](#bindings-with-no-name)), and no name it binds is one a local or a parameter in scope already has. An optional local or parameter is unwrapped under its own name by narrowing, which binds nothing ([below](#unwrapping-an-optional)).

## Conditions and patterns

**A condition's binding writes `let`, `var`, `ref let` or `ref var`, with the meaning each word has in a declaration, and a `for` name or a `when` payload name writes no word, since its subject says what it is.** The two subsections below give each rule ([Conditions](#conditions), [`for` and `when` names](#for-and-when-names)). Each position in a pattern reads a bare name one way ([12](../12-grammar/constructs.md#patterns)).

**No pattern holds a `let` or `var` of its own.** A declaration's, a condition's or a `for` loop's pattern is a name, `_` or a tuple of these, and every name in it binds. Code that binds names in two ways writes a declaration for each, as a `ref var` and a `ref let` borrow two fields of one value in two ways ([09](../09-compile-time/reflection.md#tuples-field-lists-and-queries)). A `when` arm's pattern has rules of its own ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)).

### Conditions

**A condition of an `if`, a `while` or a `guard` holds only what can fail: a `Bool` test, or an optional binding.** An **optional binding** binds its names to the value inside an optional, and only when the optional holds one. Its word says what the names are:

```swift
if let job = queue.pop() { done.append(consume job) }      // owns the job that pop moved out
if var job = queue.pop() { job.priority += 1 }             // owns it, and may change it
if ref let e = &world.enemies[h] { print("hp \(e.hp)") }   // names the enemy where it lies in the pool
if ref var e = mutable &world.enemies[h] { e.hp = 0 }      // names it for change
while let job = queue.pop() { run(consume job) }           // each job in turn, until pop returns nil
guard ref let e = &world.enemies[h] else { return }        // names the enemy to the end of the scope
```

- **A binding follows the rules of a declaration with the same word** ([above](#bindings)). `let` and `var` own the payload, so a place given to one writes a mark, unless its type is implicitly copyable, as `T?` is where `T` is. Then the binding owns a copy, and the place stays as it was.
- **A `ref let` or `ref var` takes a reference to an optional, `&T?` or `mutable &T?`, and names its payload**: `ref let` read-only, and `ref var` for change. Given a value that isn't a reference, it is the compile error that says to write `let` or `var`.
- **The right side of a `let` or `var` binding is any expression of optional type**, `copy place` and `consume place` included. A `let` or `var` of a value, such as a call's result, takes the payload out of it. `consume x` moves the whole optional out of `x`, whether it holds a value or not, and the binding owns its payload. `copy x` gives the binding a copy, and leaves `x` free for the block to change.
- **A binding whose right side isn't an optional, or a reference to one, is a compile error** that says to declare the name before the `if`, `while` or `guard`, since such a binding can't fail. A name for something that is always there belongs in a declaration. So `if let r = &x` is the compile error that says its right side is a reference, not an optional.
- **A `guard` binds as an `if` does**, and its names stay in scope after it, to the end of the enclosing block ([Names in scope](#names-in-scope)).
- **The pattern binds at least one name** ([below](#bindings-with-no-name)). A tuple pattern binds the parts of an optional tuple, such as two elements of one pool ([Two elements of one collection](exclusivity.md#two-elements-of-one-collection)).

```swift
if let e = copy world.enemies[h] {
    world.enemies.remove(h)                       // fine: 'e' is a copy, so nothing borrows the pool
    spawnCorpse(consume e)
}
if let m = consume reply { send(consume m) }      // moves the optional out: 'reply' holds no value after this
if let t = world.target { chase(t) }              // a Handle<Enemy>? is implicitly copyable: 't' owns a copy
if let e = &world.enemies[h] { … }                // error: the right side is a reference, not an optional; declare 'ref let e'
if ref let e = &enemies[0] { … }                  // error: 'enemies[0]' isn't an optional; declare 'ref let e' before the 'if'
```

**A condition list's subjects are held together, under the law of exclusivity, as one call's arguments are** ([Evaluation order](parameters.md#evaluation-order-and-when-a-calls-borrows-begin)). Each binding's borrow or take is checked against every other one's in the list. So two bindings can't borrow overlapping places when either lends its place for change:

```swift
if ref var a = mutable &world.enemies[h1], ref var b = mutable &world.enemies[h2] { … }   // error: both lend 'world.enemies' for change; write 'ref var (a, b) = mutable &world.enemies[h1, h2]'
```

**A `Bool` test that checks an optional against `nil` may narrow it instead of binding it** ([below](#unwrapping-an-optional)).

**A condition holds no case or comparison pattern, so it tests a case with `==`, and a `when` binds a payload** ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)). Every enum compares with one of its cases that carries no payload, as in `state == .idle` ([05](../05-protocols-generics-and-closures/operators.md#equality-and-ordering)). A case with a payload is matched by a `when` arm, which binds the payload's names for the arm's block:

```swift
if state == .idle { wander() }
when &state {
    .chase(t) { track(t) }                        // 't' names the payload of 'state', a handle, read-only
    else {}
}
```

### `for` and `when` names

**A `for` name and a `when` payload name are bare, and what each one is follows from the subject.** A loop or a match binds all its names from one subject, so the subject says once what they all are. A subject is `&s`, `mutable &s`, `consume s`, or a value, such as a call's result or a range. A bare place is a compile error, unless its type is implicitly copyable, in which case the loop or the `when` takes a copy ([References](references.md#places-given-to-a-position), [05](../05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected)).

| Subject | Each name |
| --- | --- |
| A shared reference: `for e in &enemies`, or a place or a call that holds or returns a `&[T]` | A `ref let` of the element or part |
| A mutable reference: `for e in mutable &enemies`, `mutable &r` of a place `r` that holds a `mutable &[T]`, or a call that returns one | A `ref var` of the element or part |
| `consume` of a place: `for job in consume jobs` | Owns each element or part |
| Any other value: `for i in 0..<n`, `for job in queue.drain()`, or a copy of an implicitly copyable place | Owns each element or part |

**A subject whose value is a reference is iterated or matched as that reference**, however it is written, so a place that holds a `mutable &[T]` gives `ref var` names once it is reborrowed with `mutable &r` ([Reborrowing](references.md#reborrowing)). For a `for` name, the iterator each form picks says whether each element lies in storage or is a value the sequence makes ([04](../04-types/collections.md#iteration)).

**A sequence's elements may be tuples that hold references**, as `enumerated()` hands out a `(UInt, &Item)` and `mutableEnumerated()` a `(UInt, mutable &Item)`. A loop name owns each tuple, so `e.order = i` through a `mutable &Item` element writes the item.

- **A name that owns its value may change it, but is never assigned as a whole.** It takes no `let` or `var`, and nothing points it at another value, so `job = Job()` below is a compile error. Otherwise it is a [changeable place](#changeable-places). So `job.priority += 1` changes the job, a `mutating` method may be called on it, and `mutable &job` lends it. A mutable reference it owns, such as a chunk, writes through itself.
- **A `ref var` name writes through to its element or part**, as a `ref var` binding does, so `r *= 2` below changes `shape`.
- **A `ref` name can't be consumed**, since what it names has another owner. A name that owns its value can be, as a `let` can.
- **A `when` name takes its part out of a value subject only once its arm is chosen**, since patterns and guards run under a borrow of the subject until then ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)).
- **A `deinit` on the path keeps a value subject whole.** This holds in an arm where any of its patterns has, on the path to a part, a type that declares a `deinit`, whichever pattern matched. The value stays whole in a hidden local until the arm ends, as a `for` loop's sequence does. The arm's names then name its parts, read-only, or for change where the subject is a mutable reference. So the `deinit` runs on the changed value, and nothing moves out of it.
- **A temporary subject lent with `&` or `mutable &` is kept whole the same way**, as a loop keeps `mutable &makeEnemies()` ([04](../04-types/collections.md#iteration)), so its names name its parts until the arm ends.
- **In a type's own `deinit`, that type's `deinit` keeps nothing whole**, since it is already running. So `when consume self` takes an enum `self`'s payload apart there ([What can be moved from](moving-values-out.md#what-can-be-moved-from)).
- **A subject in a temporary's own storage that can't be moved out is kept whole the same way**, with the whole temporary in that hidden local, as `connect().state` is where `Conn` declares a `deinit`.

```swift
when mutable &shape {
    .circle(r) { r *= 2 }                  // a 'ref var' of the radius: doubles it inside 'shape'
    else {}
}
when consume event {
    .message(m) { inbox.append(consume m) }   // 'event' is moved out: 'm' owns the message
    else {}
}
for e in &enemies { e.hp = 0 }             // error: 'e' is a 'ref let'; write 'mutable &enemies' to change the elements
for e in mutable &enemies { e.hp -= 1 }    // fine: 'e' is a 'ref var' of each enemy
for e in enemies { … }                     // error: write '&enemies', 'mutable &enemies' or 'consume enemies'
for job in queue.drain() {
    job.priority += 1                      // fine: 'job' owns the job
    job = Job()                            // error: a loop name is never assigned as a whole
}
for chunk in data.mutableChunks(64) { chunk[0] = 0 }        // fine: the loop owns each chunk, and writes through it
for (i, e) in items.mutableEnumerated() { e.order = i }     // 'e' is a 'mutable &Item' that the loop's tuple owns
for i in 0..<n { i += 1 }                  // error: a loop name is never assigned as a whole; declare 'var j = i' to change a copy
```

## Bindings with no name

**Every binding that a `let`, `var`, `ref let` or `ref var` makes binds at least one name, or it is a compile error.** The words say how its names hold what they bind: whether they hold a value or are a place, and whether they may change it ([above](#bindings)). With no name, they say nothing. Each binding of a declaration is one binding, so `let lo = 0, _ = f()` is an error, though `lo` is bound. So is each optional binding of a condition ([above](#conditions)).

A `_` is fine inside a pattern that binds another name, as in `ref let (a, _) = &pair`. A `for` name and a `when` payload name write no word for a missing name to leave unexplained, so a `_` in their place is fine.

```swift
ref let (a, _) = &pair                    // fine: binds 'a'
let _ = save(level)                       // error: binds no name
let lo = 0, _ = f()                       // error: the second binding binds no name
ref let (_, _) = &pair                    // error: binds no name
if let _ = target { ... }                 // error: binds no name; write 'target != nil'
for _ in 0..<3 { spawn(.grunt) }          // fine: a loop's name writes no word
```

**Code that binds nothing has a form without `let` or `var`:**

- `_ = consume x` drops a value on purpose, and so does `_ = x` of an implicitly copyable one ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unused-values));
- `x != nil` tests whether an optional holds a value ([04](../04-types/enums.md#optionals));
- `is E` matches a value of type `E` without binding it ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if));
- a `_` on its own matches any part of a payload without binding it, as in `.pair(a, _)` ([12](../12-grammar/constructs.md#patterns)).

## Unwrapping an optional

**Narrowing unwraps an optional under its own name, and a binding unwraps it under a new one.** Checking `x != nil` narrows a local, a parameter or a stored field of one in place, with no binding at all ([04](../04-types/enums.md#narrowing)). Anything else that holds an optional, such as an element, a global or a place reached through an object, binds its payload to a new name. That name can't be one that a local or a parameter in scope has ([Names in scope](#names-in-scope)):

```swift
var reply: Message? = conn.receive()
if reply != nil { print("got \(reply.kind)") }    // narrows 'reply' to the Message inside it
if ref let t = &window.value.target { … }         // a place reached through an object, under a name of its own
if ref let reply = &reply { … }                   // error: 'reply' is already declared; write 'reply != nil'
```

**For a place that narrows, narrowing and a `ref let` or `ref var` binding give the block the same payload**, under the place's own name or a new one. A block that only reads the payload does the same with either, and so does one that changes it in place. They differ in what the block may do to the optional itself:

- **Narrowing keeps the place an optional.** The block may assign it, `nil` included, move its payload out, call `take()` on it or pass it whole as a `T?` argument, and each event that could make it `nil` ends the narrowing.
- **A `ref let` or `ref var` binding borrows the payload**, which holds the optional still while the binding is live. So nothing can make it `nil` there, and the binding can't be consumed.

So narrowing fits code that goes on treating the place as an optional, such as code that clears it once done with it. A binding fits code that needs only the payload. For a place that doesn't narrow, such as a global or a thread-local, a binding is the only checked way to name the payload, since `x!` panics on `nil`, and `x?.` and `??` check again at each use. A `ref let` or `ref var` binding holds the place's borrow until its last use, and a thread-local's access with it ([How long a borrow lasts](#how-long-a-borrow-lasts)):

```swift
@threadlocal var session: Session? = nil

func report() {
    guard ref let s = &session else { return }   // names this thread's session in place, holding its access
    print("\(s.name)")
}
```

## `if` and `when` as values

**An `if` or `when` expression hands its position to the arm that runs.** Whatever the position does with a value, it does with the arm's last expression, as if that expression stood there: borrows it, moves it or returns it. So each arm writes its own mark. An `unsafe` block used as an expression hands its position to its last expression the same way ([10](../10-errors-and-safety/unsafe-code.md#unsafe-code)).

```swift
ref let e = if first { &enemies[0] } else { &enemies[1] }          // names one of the two
var t = if left { mutable &a } else { mutable &b }                 // holds a mutable reference to one
let v = if c { consume p } else { consume q }                      // moves from the one chosen
let w = if c { p } else { q }                                      // error: write 'copy', 'consume' or '&' before 'p'
```

What depends on `e` depends on both places ([02](../02-views-and-dependencies.md#dependencies)). `v` moves from the one chosen, so each of `p` and `q` is moved only on its own path ([Moving values out](moving-values-out.md#moving-values-out)).

**When some arms give a `ref let` or `ref var` references to places and others give references to temporaries, each temporary is kept in a hidden local:**

```swift
ref let e = if c { &enemies[0] } else { &makeEnemy() }      // the new enemy is kept in a hidden local
```

The hidden local is declared where the binding is, and destroyed with it if its arm ran. The binding is then a borrowing binding, which can't be consumed. What depends on it depends on every arm's place, and on those hidden locals.

## Conversions

**A converted value is a new value.** When a binding's declared type differs from its initializer's, the conversion says what it does with a place ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)):

- **A numeric widening, and a copyable value's conversion to or from its [static type](../02-views-and-dependencies/scoped-values.md#converting-to-and-from-a-static-type), read the place** and make a new value, which the binding owns. A move-only value's conversion to or from its static type takes it, as the conversions below do.
- **A place given where a reference is expected is lent**, and the binding holds the reference, as `all` below holds one to the elements of `enemies` ([05](../05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected)). The conversions below then apply to that reference, never to the place.
- **These conversions take the value**, so a place given to them writes `consume` or `copy` before it, as every position does. A place of an implicitly copyable type is copied, as `h` is below ([Implicit copies](moves-copies-destruction.md#implicit-copies)). A place lent where a `(&T)?` is expected is the exception: wrapping takes the reference the lend makes, and the place is only borrowed. The conversions that take the value are:
    - wrapping it in an optional or an error union, or as a `Result`'s `.success`;
    - making a `Box<T>` or an object pointer into one of an existential;
    - moving a closure into a `Closure`.
- **A reference converts to a reference of an unsized type**, as `&List<T>` does to `&[T]`, `&String` to `&Text`, and `&T` to `&any P`. The new reference refers to the same storage, and borrows it as the first one did ([References](references.md#unsized-types)).

```swift
let total: Int = n                          // 'n' is an Int32: the widened Int is a new value 'total' owns
let all: &[Enemy] = enemies                 // refers to the List's elements, and borrows 'enemies'
var spare: Enemy? = copy boss               // wrapping a copy of the enemy
let pick: Enemy? = boss                     // error: wrapping takes the enemy; write 'copy' or 'consume'
var last: Enemy? = consume boss             // or wrapping the enemy itself, moved out of 'boss'
var target: Handle<Enemy>? = h              // a Handle is implicitly copyable: wrapping a copy, and 'h' stays usable
var d: &any Drawable = sprite               // refers to 'sprite', and may later refer to another value
```

## Changeable places

**Only a changeable place can be changed, or lent with `mutable &`**, so a shared borrow never becomes a write. A place is **changeable** when it is:

- a `var`;
- a temporary, which its statement owns ([02](../02-views-and-dependencies/dependency-projection-and-results.md#temporaries));
- the place a `ref var` names: a `ref var` binding, a `mutable &T` parameter, `self` in a `mutating` method, or a `for` or `when` name whose subject is a mutable reference;
- a `for` or `when` name that owns its value, which is never assigned as a whole ([above](#for-and-when-names));
- a parameter that owns its argument, or `self` in a `consuming` method, a `deinit` or an initializer;
- an owned capture of a `mutating` or `consuming` closure;
- the place a `mutable &T` refers to, reached through a changeable place that holds the reference ([References](references.md#forwarding-through-a-reference));
- a `var` field, an element, or a property with a `mutate` or a `set` ([02](../02-views-and-dependencies/place-and-value-properties.md#place-and-value-properties)), of a changeable place.

**Everything else is read-only, and so is whatever is reached through it**: a `let`, a `ref let`, a `&T` parameter, `self` in a plain method, a `let` field, a `const` and a global `let`. So is a `for` or `when` name whose subject is a shared reference, or that holds a copy, and the place any shared reference refers to. So is the place a `let` reaches through a reference it holds ([References](references.md#forwarding-through-a-reference)).

```swift
let x = makeEnemy()
ref var y = mutable &x             // error: a let is read-only, even one that owns its value
heal(mutable &x)                   // error: the same
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
