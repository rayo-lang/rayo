# Bindings

[01 · Values and ownership](../01-values-and-ownership.md)

**A declaration takes the value it is given, as an assignment does, unless it says it borrows.** `let` and `var` say only whether the binding may change what it holds. So a declaration moves a value out of a place, whatever its type. `borrow` borrows the place instead, and `&` lends it for change.

```swift
var enemies = loadEnemies()

let seen = borrow enemies[0]       // looks: a read-only name for the enemy, nothing copied
var boss = &enemies[0]             // changes it in place: boss.hp = 0 changes enemies[0]
var spare = copy enemies[0]        // a second enemy of its own
let first = enemies[0]             // error: an element can't move out of its list
let mesh = loadMesh()              // a value, not a place: the binding owns it
let all = enemies                  // a move: 'enemies' can't be used until it gets a new value
```

| Form | Like the parameter | Meaning | Cost |
| --- | --- | --- | --- |
| `let x = place`, `var x = place` | `_ x: owned T` | A **move** from a place the code owns ([What can be moved from](moving-values-out.md#what-can-be-moved-from)): `place` can't be used until it gets a new value. A copyable `const` gives a new value instead ([Constants](moving-values-out.md#constants)) | A `memcpy` at most |
| `let x = borrow place` | `_ x: T` | A shared **borrow** of `place`, of any type: `place` can't be changed, moved or destroyed while `x` is live | None |
| `var x = &place` | `_ x: mutable T` | A mutable **borrow** of a [changeable place](#changeable-places): `place` is reachable only through `x` while `x` is live | None |
| `let x = copy place`, `var x = copy place` | | An independent **copy** of a copyable value; a move-only one is copied with `alloc place.clone()` | A `memcpy` |
| `let x = f()`, `var x = f()` | | The binding owns the value, even a move-only scoped value such as a `MutableSpan` or a lock guard ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)); `_ = x` ends it early | None |
| `var x = borrow place` | | A compile error, since `=` on a `var` that borrows writes the place it names ([02](../02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind)), which a shared borrow can't | |

- **A binding that names a place it borrows is a borrowing binding**, and can't be consumed. A declaration makes one with `borrow` or `&` on a place, unless the initializer makes a value of its own from the place, such as a view ([below](#lending-a-place-for-change)). A condition or pattern makes one by binding a place ([below](#conditions-and-patterns)).
- **A binding of anything that isn't a place owns it**, as a binding of a call's result does: a literal, an operator's result, `copy place` or `consume place`. A binding that owns its value can move it on, and a `let` still can't change it.
- **`borrow` on a value binds the value itself**, which the binding owns, since there is no place to borrow. A value property, whose accessor is a `get`, gives such a value ([below](#what-a-borrowing-let-sees)).
- **`borrow` is written only where a declaration borrows**, and a borrowed argument and a condition borrow with nothing written. A declaration writes it:
    - on its initializer;
    - on an expression the initializer hands its position to: the last expression of an `if` or `when` arm or of an `unsafe` block ([below](#if-and-when-as-values)), or an operand of `??` ([04](../04-types/enums.md#optionals));
    - on the place a `rebind` of the binding names ([02](../02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind)).
- **Views taken from a borrowing `let` depend on the place itself** ([02](../02-views-and-dependencies/dependency-projection-and-results.md#rule-1-projection)).
- **A place in a temporary's own storage dies with its statement**, such as `makeEnemy().pos`. So `borrow` of one owns that value instead, moving it out as [What can be moved from](moving-values-out.md#what-can-be-moved-from) allows. Where that can't move it, the binding is a compile error unless it is written with `copy`, or with `alloc` and `.clone()`.
- **A place that a `where return outlives self` place property hands out from a temporary lies outside the temporary**, such as `makeSpan()[0]`. So `borrow` of one borrows it, depending on what the temporary carries ([02](../02-views-and-dependencies/dependency-projection-and-results.md#temporaries)).
- **Neither borrowing form may bind an under-aligned place**: that is a compile error, since a load or store of its type at that address may be invalid, and fault on some targets ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)).

## What a borrowing `let` sees

**Changing a place while a `let` that borrows it is used is a compile error**, since the `let` is a shared borrow ([The law of exclusivity](exclusivity.md#the-law-of-exclusivity)). For a place reached through an object or a thread-local, it is a panic instead ([below](#how-long-a-borrow-lasts)). A `Synchronized` value still changes through its own synchronization ([07](../07-concurrency/synchronization.md#the-synchronized-contract)).

**Making a field computed, or stored, never silently changes what a binding of it gets.** What a binding of `e.f` gets follows from how `f` is declared:

- **A stored field** moves out of `e`, as [What can be moved from](moving-values-out.md#what-can-be-moved-from) allows, and `borrow` gives another name for the field.
- **A value property** gives the value its `get` returns, which the binding owns, with or without `borrow` ([02](../02-views-and-dependencies/place-and-value-properties.md#value-properties-get-and-set)).
- **A place property** lends its place to `borrow`, as a stored field does, and can't be moved from ([02](../02-views-and-dependencies/place-and-value-properties.md#place-properties-borrow-and-mutate)).

Where the stored and the computed forms would differ, the stored form is a compile error:

```swift
extension Enemy { var isDead: Bool { hp <= 0 } }   // computed

func hit(_ e: mutable Enemy, _ d: Float) {
    let before = borrow e.hp
    e.hp -= d                      // error: 'before' still names e.hp
    let dead = e.isDead            // computed: the Bool it returned, which 'dead' owns
    save(dead)                     // fine: save takes an owned parameter
    let hp = e.hp                  // error: 'e' is a mutable parameter, so e.hp can't move out of it
}
```

## How long a borrow lasts

**A borrow lasts until its last use, not to the end of the scope.** Once `boss` above is last used, `enemies` is free again. Where destroying the value that holds the borrow is a use ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)), that destruction is its last use.

**A borrowing binding of a dynamic place holds its access until its last use.** A dynamic place is one reached through a thread-bound object's owner or weak pointer, or a thread-local, and the binding holds that dynamic access (rule 6 in [02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). So a call in between that changes the object panics. When a panic unwinds through the binding's scope, the access is released once the unwind has destroyed the last value that depends on it ([Destruction by unwinding](moves-copies-destruction.md#destruction-by-unwinding)).

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

**A `let`, `var` or `const` in a body declares a local, and so does each name these constructs bind**, in scope where the construct uses it:

- an `if`'s or a `while`'s condition names, in each later condition of its list and in its block;
- a `guard`'s condition names, in each later condition of its list and after the `guard` to the end of the enclosing block, but not in its `else` block;
- a `when` arm's names, in its `where` guard and its block;
- a `catch` clause's names, such as `e` in `catch let e` or `field` in `catch .badValue(let field)`, in its `where` guard and its block;
- a `for` or `static for` pattern's names, in its `where` clause and its block;
- a closure literal's parameters, written or implicit, such as `$0`, in its body.

**The rule holds wherever a body sees a name:**

- **One declaration.** Two names of one parameter list, one pattern or one list of conditions can't be the same either, as in the first two lines below. The patterns that share a `when` arm bind one set of names, so a name they repeat is one binding, not a reuse ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)).
- **Closure literals.** A closure's body sees the enclosing body's locals and parameters, and captures those it names ([05](../05-protocols-generics-and-closures/functions-and-closures.md#capturing-places)). So its parameters and locals can't take their names, and that includes its implicit parameters: a closure that names `$0` can't contain another closure that names `$0`. A capture list names a local or a parameter already declared, and declares nothing new.
- **Nested functions and local types.** Their bodies see none of the enclosing body's locals or parameters ([05](../05-protocols-generics-and-closures/functions-and-closures.md#functions-and-closures)), and neither does a member of a local extension. So they may reuse those names, since nothing they would shadow is in scope there.
- **Names declared outside the body.** The rule covers only locals and parameters. A local may share the name of a function, a field or a global, and lookup decides which one each use reaches ([05](../05-protocols-generics-and-closures/functions-and-closures.md#static-and-instance-members)).

```swift
func pair(_ a: Int, _ a: Bool) { … }                              // error: 'a' is already declared, as a parameter
let (lo, lo) = bounds                                             // error: 'lo' is already declared, in this pattern

alloc func names(_ entries: Span<Entry>) -> List<StringView> {
    alloc entries.map { entries in entries.name.view }            // error: 'entries' is already declared, as a parameter
}
let ready = alloc groups.map { alloc $0.items.filter { $0.ok } }  // error: '$0' is already declared, by the outer closure
let kept = alloc groups.map { g in alloc g.items.filter { $0.ok } }   // fine: the outer closure names its parameter

func report(_ count: Int) {
    func double(_ count: Int) -> Int { count * 2 }    // fine: 'double' sees none of report's parameters
    log("\(double(count))")
}
```

**`if let x` is the one binding that takes the name of a local or a parameter in scope**: it unwraps the optional `x` under its own name ([below](#unwrapping-under-the-same-name-if-let-x)).

**So a `let` or a `var` always gives the reader a name to follow.** It binds at least one name ([below](#bindings-with-no-name)), and apart from `if let x`, no name it binds is one a local or a parameter in scope already has.

## Conditions and patterns

**A condition or a pattern borrows a place it binds, unless it says `owned`.** It looks inside a value, at an optional's payload or an enum case's, so where a declaration's default is to take, its default is to look. `guard` and `while` work the same way as `if`:

```swift
if let e = world.enemies[h] { ... }        // looks at the enemy in place
if var e = &world.enemies[h] { ... }       // changes it in place
if let v = pool.take(h) { ... }            // owns the value that take moved out
```

- **A `let` looks at the place, and a `var` changes it in place**, with the place marked `&`.
- **`owned` takes the value out of a place the code owns**, as a declaration does ([above](#bindings)).
- **A value, such as a call's result, is owned by the binding**, as in a declaration.

**A condition may also unwrap an optional under the name it already has**, as `if let x` does ([below](#unwrapping-under-the-same-name-if-let-x)). Narrowing unwraps a local, a parameter or a stored field of one in place, with no binding at all ([04](../04-types/enums.md#narrowing)).

**In a `when`, each part of a pattern binds as a condition does:**

- **A `let` part looks at what it matches, and a `var` part changes it in place.** For a `var` part, the subject is marked `&`, as in the example below.
- **An `owned` part takes what it matches out of a subject the code owns.** It moves as a field is moved out ([What can be moved from](moving-values-out.md#what-can-be-moved-from)): only when no type on the path to it declares a `deinit`, except in that type's own `deinit`, since a `deinit` takes the whole value. It also moves only once its arm is chosen, since patterns and guards run under a borrow of the subject until then ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)).
- **When the subject is a value, every part owns what it matches.**
- **A `deinit` on the path keeps a value subject whole.** This holds in an arm where any of its patterns has, on the path to a part, a type that declares a `deinit`, whichever pattern matched. The value stays whole in a hidden local until the arm ends, as a `for` loop's sequence does. The arm's `let` parts look at it, and its `var` parts change it in place, so the `deinit` runs on the changed value, and nothing moves out of it. The subject still takes no `&`, since the hidden local is the arm's own.
- **A subject in a temporary's own storage that can't be moved out is kept whole the same way**, with the whole temporary in that hidden local, as `connect().state` is where `Conn` declares a `deinit`.

```swift
when &shape {
    .circle(var r) { r *= 2 }      // a var part: doubles the radius inside 'shape'
    else {}
}
```

**`if case`, `guard case` and `while case` bind the same way**, with the value after `=` as the subject. A `guard`'s hidden local lives to the end of the enclosing scope, as the names it binds do.

**`for` patterns bind elements in place, changeable when the loop lends its sequence with `&`**, and own what the iterator hands out as a value of its own, such as a `Range`'s `Int`. So a `for` pattern writes no `let`, and writes `var` only on a part that owns its value ([04](../04-types/collections.md#iteration)).

## Bindings with no name

**Every binding that a `let` or `var` makes binds at least one name, or it is a compile error.** The keyword says how its names hold what they bind: whether they may change it, and in a condition or a pattern whether they look at it or change it in place ([above](#conditions-and-patterns)). With no name, it says nothing. Each of these is one binding:

- **Each binding of a declaration**, so `let lo = 0, _ = f()` is an error, though `lo` is bound.
- **The pattern after `let` or `var` in a condition.**
- **Each `let` or `var` part of a pattern**, so `.pair(let a, let _)` is an error, though `a` is bound. A type pattern under `let` is such a part, so `let _ as E` is an error.

A `_` is fine inside a pattern whose `let` or `var` binds another name, as in `let (a, _) = pair`.

```swift
let (a, _) = pair                         // fine: binds 'a'
let _ = save(level)                       // error: binds no name
let lo = 0, _ = f()                       // error: the second binding binds no name
let (_, _) = pair                         // error: binds no name
if let _ = target { ... }                 // error: binds no name
if case .pair(let a, _) = p { ... }       // fine: the 'let' binds 'a'
if case .pair(let a, let _) = p { ... }   // error: the second 'let' binds no name
```

**Code that binds nothing has a form without `let` or `var`:**

- `_ = x` drops a value on purpose ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unused-values));
- `x != nil` tests whether an optional holds a value ([04](../04-types/enums.md#optionals));
- `is E` matches a value of type `E` without binding it ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if));
- a `_` on its own matches any part of a pattern without binding it, as in `.pair(let a, _)` ([12](../12-grammar/constructs.md#patterns)).

## Unwrapping under the same name: `if let x`

```swift
var reply: Message? = conn.receive()
if let reply { log("got \(reply.kind)") }      // the Message inside 'reply', looked at in place
if var reply { reply.retries += 1 }            // changes the Message inside 'reply' in place
if let reply = reply { … }                     // error: write 'if let reply'
guard let reply else { return }                // the Message, to the end of the scope
```

**`if let x` means `if let x = x`, and `if var x` means `if var x = &x`.** Each binds a new local `x` to the payload of the optional that `x` names, so the payload keeps the name the code already uses for it. `guard` and `while` take the short form as `if` does, and so does each condition in a list. The new `x` is in scope as any condition's names are ([Names in scope](#names-in-scope)), and shadows what `x` named there.

**The long form is a compile error wherever the short form means the same**, since it repeats a name the short form writes once. That is a `let` or `var` condition of an `if`, a `guard` or a `while` whose pattern is a bare name and whose value is the same bare name, behind `&` for a `var`. It is an error whatever `x` names: a local, a parameter, a property of `self`, a global or a thread-local. The error points to `if let x` or `if var x`, except where `while let x` is an error itself (below). There the long form gets that error instead, which points to `while x != nil` for a local or a parameter.

**A `case` condition that means the same is the long form too**, for the same reason, so the error points to the short form there as well:

```swift
if case .some(let reply) = reply { … }         // error: write 'if let reply'
if case .some(var reply) = &reply { … }        // error: write 'if var reply'
```

**With `owned`, which has no short form (below), `owned let x = x` is an error only where `x` is a local or a parameter**, since it reuses that name. The error asks for a name of its own.

**The short form binds what the long form would** ([above](#conditions-and-patterns)):

- **A `let` looks at the payload in place**, when `x` names a place.
- **A `var` changes the payload in place.** So `x` names a [changeable place](#changeable-places), as `&x` requires. `if var x` is a compile error where `x` is read-only: a `let`, owning or borrowing, a borrowed parameter, a global `let` or a `const`, or a property of `self` in a plain method, one neither `mutating` nor `consuming`. Its `var` marks the lend, which `&` marks elsewhere ([Lending a place for change](#lending-a-place-for-change)).
- **A value is owned by the binding**, as when `x` names a value property of `self`, whose `get` returns a new optional at each use. `if var x` is a compile error there, since `&` on a value lends nothing ([Lending a place for change](#lending-a-place-for-change)). A `var` with a name of its own, such as `v` in `if var v = x`, owns the value and may change it.

**`x` is a bare name, which lookup resolves as it resolves any use** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#static-and-instance-members)). It may name whatever lookup finds that holds an optional:

- a local or a parameter;
- a property of `self`, in an instance body;
- a global, a static stored property included: a `let`, a `const` or a `@threadlocal var` ([07](../07-concurrency/global-state.md#global-state)).

**A bare global `var` takes the short form only inside an `unsafe` block**, since every access to one needs `unsafe` ([07](../07-concurrency/global-state.md#global-state)), and the short form has no expression to write it on.

**A path has no short form**, since the new local would take a name the code never wrote. A stored field of a local or a parameter narrows instead (below). Any other path binds to a name of its own with the long form:

```swift
if let t = window.value.target { … }           // a place reached through an object, under a name of its own
```

**The short form takes no `owned`.** Its new `x` is the old one's payload, in place, so the name still stands for one value. `owned` would move the payload out, and leave the place behind the name holding no value. The one name would then stand for two bindings in different states, as a reused name does. Code that takes the payload moves it out of the narrowed place, or binds it to a name of its own:

```swift
if owned let m = reply { send(m) }             // moves the Message out: 'reply' holds no value after this
```

**`while let x` and `while var x` are compile errors wherever no code can change `x` while the loop runs**, since such a loop could end only through `break`, `return` or `throw`. Its binding holds the optional still while it is live, so nothing can make it `nil` then. In these places, nothing can change `x` between the binding's uses either:

- **A local or a parameter.** The binding shadows the optional's name through the body, and nothing else reaches it. The error points to `while x != nil`, whose narrowing lets the body assign the place, and ends when it does.
- **A place nothing ever changes.** That is a global `let`, a static stored `let` or a `const`.
- **`self`'s own storage in a plain method**, whose `self` is borrowed shared for the whole call. That is a stored field of `self`, or a place property that hands out part of `self` ([02](../02-views-and-dependencies/place-and-value-properties.md#place-properties-borrow-and-mutate)).

In the last two cases the optional can't change between passes, so the loop means an `if let x` around a `while true`. The error points to `if let x`, with `while true` inside it where the body repeats.

**Elsewhere each pass can find a different optional**, so the loop is allowed:

- a value property, whose `get` makes a new optional each pass;
- a place reached through an object, a weak pointer or a thread-local, which a call can change between passes;
- a changeable property of `self` in a `mutating` method, which the body can assign through `self`.

```swift
var next: Job? = queue.pop()
while let next { run(next) }                   // error: nothing in the body can change 'next'; write 'while next != nil'
while next != nil {                            // narrows 'next' for the body
    run(next)
    next = queue.pop()                         // ends the narrowing, until the condition checks again
}
```

**For a place that narrows, `if x != nil` and `if let x` give the block the same payload under the same name.** A local, a parameter or a stored field of one narrows ([04](../04-types/enums.md#narrowing)). A block that only reads the payload does the same with either. One that changes the payload in place does the same under narrowing as with `if var x`. They differ in what the block may do to the optional itself:

- **Narrowing keeps the place an optional.** The block may assign it, `nil` included, move its payload out, call `take()` on it or pass it whole to a `T?` parameter, and each event that could make it `nil` ends the narrowing.
- **`if let x` binds a borrowing binding of the payload**, which holds the optional still while it is live. So nothing can make it `nil` there, and the binding can't be consumed.

So narrowing fits code that goes on treating the place as an optional, such as code that clears it once done with it. `if let x` fits code that needs only the payload. For a place that doesn't narrow, such as a global or a thread-local, a binding is the only checked way to name the payload, since `x!` panics on `nil`, and `x?.` and `??` check again at each use. `if let x` gives that binding the place's own name. The binding holds the place's borrow until its last use, and a thread-local's access with it ([How long a borrow lasts](#how-long-a-borrow-lasts)):

```swift
@threadlocal var session: Session? = nil

func report() {
    guard let session else { return }       // looks at this thread's session in place, holding its access
    log(session.name)
}
```

## `if` and `when` as values

**An `if` or `when` expression hands its position to the arm that runs.** Whatever the position does with a value, it does with the arm's last expression, as if that expression stood there: borrows it, lends it for change, moves it or returns it. An `unsafe` block used as an expression hands its position to its last expression the same way ([10](../10-errors-and-safety/unsafe-code.md#unsafe-code)).

```swift
let e = if first { borrow enemies[0] } else { borrow enemies[1] }   // borrows one of the two
var t = if left { &a } else { &b }                                  // lends one for change
let v = if c { p } else { q }                                       // moves from the one chosen
```

What depends on `e` depends on both places ([02](../02-views-and-dependencies.md#dependencies)). `v` moves from the one chosen, so each of `p` and `q` is moved only on its own path ([Moving values out](moving-values-out.md#moving-values-out)).

**When some arms borrow places and others give values, each value is kept in a hidden local:**

```swift
let e = if c { borrow enemies[0] } else { makeEnemy() }      // the new enemy is kept in a hidden local
```

The hidden local is declared where the binding is, and destroyed with it if its arm ran. The binding is then a borrowing binding, which can't be consumed. What depends on it depends on every arm's place, and on those hidden locals.

## Conversions

**A converted value is a new value.** When a binding's declared type differs from its initializer's, the conversion says what it does with a place ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)):

- **A numeric widening, and a [static value](../02-views-and-dependencies/scoped-values.md#static-values)'s conversion to its plain type, read the place** and make a new value, which the binding owns.
- **These conversions take the value**, so from a place, each moves it as a declaration does, unless the code writes a copy of a copyable value:
    - wrapping it in an optional or an error union, or as a `Result`'s `.success`;
    - making a `Box<T>` or an object pointer into one of an existential;
    - moving a closure into a `Closure`.
- **Making an `any P` from a place borrows the place shared**, as making any view of it does, and the binding, `let` or `var`, owns the view. So a `var` of one may later point at another value. `&place` makes a `mutable any P` instead ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)). A `String` or a `List` made into its view borrows the place shared too ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)).

```swift
let total: Int = n                          // 'n' is an Int32: the widened Int is a new value 'total' owns
let all: Span<Enemy> = enemies              // borrows the List 'enemies'; 'all' owns the view
var spare: Handle<Enemy>? = copy h          // wrapping a copy of the handle
var target: Handle<Enemy>? = h              // or wrapping the handle itself, moved out of 'h'
var d: any Drawable = sprite                // borrows 'sprite'; 'd' owns the view, and may later view another value
```

## Changeable places

**Only a changeable place can be changed, or lent with `&`**, so a shared borrow never becomes a write. A place is **changeable** when it is:

- a `var` that owns its value;
- a temporary, which its statement owns ([02](../02-views-and-dependencies/dependency-projection-and-results.md#temporaries));
- the place that a `var` given `&place` names, through that binding;
- a `mutable` or `owned` parameter, or `self` in a `mutating` or `consuming` method, a `deinit` or an initializer;
- an owned capture of a `mutating` or `consuming` closure;
- a `var` field, an element, or a property with a `mutate` or a `set` ([02](../02-views-and-dependencies/place-and-value-properties.md#place-and-value-properties)), of a changeable place.

**Everything else is read-only, and so is whatever is reached through it**: a `let`, owning or borrowing, a borrowed parameter, `self` in a plain method, a `let` field, a `const` and a global `let`.

```swift
let x = makeEnemy()
var y = &x                         // error: a let is read-only, even one that owns its value
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

## Lending a place for change

**`&` marks every place lent for change, in a binding as in a call.** The receiver of a `mutating` method call is the exception, since the call's form shows it. These places take `&`, each lent to code that may change it:

- a `mutable` argument;
- the place a `var` borrows, in a declaration or in an `if var`, `guard var` or `while var`, and a place that a pattern's `var` part binds;
- the target of a `rebind` of a `var` ([02](../02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind));
- a loop's sequence whose elements the loop changes, which may be a temporary the loop keeps in a hidden local ([04](../04-types/collections.md#iteration));
- a `when` subject that is a place, or a `case` condition's value that is one, with a `var` part;
- the last expression of an `if` or `when` arm whose position lends a place for change;
- a place holding a `mutating` closure, a `Closure<mutating …>` or a `mutating` function value, made into a new function value ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions));
- the place that a place property's `mutate` hands out ([02](../02-views-and-dependencies/place-and-value-properties.md#place-properties-borrow-and-mutate));
- a place made into a `mutable any P`, or holding one that lends a new view of its value ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)).

```swift
for (i, e) in &makeEnemies().enumerated() { ... }       // the loop keeps the new list in a hidden local, and changes it
var t = if left { &a } else { &b }                       // the arm's place is lent for change
var v: mutable any Damageable = &boss                    // a mutable any P made from 'boss'
```

**What follows `&` is a changeable place, or a member of one that has a mutable form.** Leaving `&` out is a compile error, and so is `&` on something that lends nothing for change. The short form `if var x` writes no place for `&` to mark, so its `var` marks the lend ([above](#unwrapping-under-the-same-name-if-let-x)).

- **`&` picks a mutable form.** Where a method or property has a shared and a mutable form of one name, the operand of `&` picks the mutable one ([04](../04-types/collections.md#shared-mutable-and-consuming-forms-of-one-method)). So a binding of `&particles.life` binds an [`SoA`](../04-types/data-layout.md#struct-of-arrays-soat) column as a `MutableSpan<Float>` that it owns, where a binding of `particles.life` gets a `Span<Float>`, as in the example below.
- **A binding of a value lends nothing, so it takes no `&`.** A call result bound to a name is owned by its binding. That includes an **owned exclusive view**: a move-only scoped value ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)), such as the guard that `registry.lock()` returns, which changes the registry through it.
- **A call result lent for change takes `&`, as any changeable place does**, when it is a `mutable` argument or a loop's sequence. It is a temporary, which its statement owns, or which the loop owns, for a sequence, as in the example below.
- **A `zip` marks its own arguments**, as in `zip(&vels, forces)`, so a loop over it needs no `&` of its own ([04](../04-types/collections.md#iteration)).

```swift
var lives = &particles.life        // the mutable form: a MutableSpan<Float> that 'lives' owns
lives[0] = 1
let ages = particles.life          // the shared form: a Span<Float>
log("first age \(ages[0])")
var g = registry.lock()            // no '&': 'g' owns the guard, and changes the registry through it
g.value.flush()
heal(&makeEnemy())                 // the statement owns the new enemy, and destroys it after the call
```
