# Functions and closures

[05 · Protocols, generics and closures](../05-protocols-generics-and-closures.md)

Functions state what their calls accept and return. Closures also carry code together with the values or places they capture, so their type must say how a call may use that captured state. A closure may remain a concrete value, become a function-typed view, or be stored for later use.

A **closure** is a value of a closure literal's concrete type ([below](#closures-by-concrete-type-some-f)). Passed for a function-type parameter, it becomes a view of itself, which may borrow locals and never allocates. The function type says whether the closure only reads what it captures, writes it, or consumes it:

```rayo
func each(_ xs: &[Enemy], _ body: (&Enemy) -> Void) { for x in &xs { body(x) } }
func eachMut(_ xs: &[Enemy], _ body: mutating (&Enemy) -> Void) { for x in &xs { body(x) } }

var dead = 0
each(enemies) { e in log("hp \(e.hp)") }                 // reads only: a plain function type
eachMut(enemies) { e in if e.hp <= 0 { dead += 1 } }     // writes 'dead': a mutating function type
each(enemies) { e in if e.hp <= 0 { dead += 1 } }        // error: a mutating closure where a non-mutating one is expected
```

**Functions may share a name when their argument labels ([01](../01-values-and-ownership/parameters.md#argument-labels)) or parameter types differ.** Whether a method is plain, `mutating` or `consuming` never tells overloads apart, so two methods of a type that differ only in how they take `self` are a compile error ([04](../04-types/collections.md#mutating-and-consuming-methods)). A call picks among such overloads in these steps:

1. It keeps the candidates whose parameters its arguments match by label, in order. A parameter that has a default may be left out ([01](../01-values-and-ownership/parameters.md#default-arguments)). Trailing closures are matched to each candidate's parameters by the trailing-closure scan, and a candidate the scan rejects drops out ([below](#trailing-closures)).
2. It keeps those that its arguments typed without context fit. Each such argument is of its parameter's type, or converts to it implicitly ([Implicit conversions](implicit-conversions.md#implicit-conversions)). A generic candidate whose type arguments, bound from those arguments, fail its constraints drops out. So `min(v, w)` on two vectors picks the vector form, since `Simd` isn't `Comparable` ([04](../04-types/numbers-and-math.md#simd-and-math)).
3. Each argument that needs context takes each remaining candidate's parameter type, and a candidate it doesn't fit drops out. An integer literal fits a parameter type only where the type holds its value, as the calls of `g` and `h` after these steps show. Such an argument is a literal, a closure literal, a `.member`, a call whose type a default type argument would complete, as `alloc Map()`'s would ([Operators](operators.md#operators)), or a bare name whose match is a generic or overloaded function. The expected type resolves such a name as it resolves any overloaded name ([Function-typed values](#function-typed-values)).
4. If exactly one candidate needs no conversion, it wins. Among several candidates that need no conversion, the one that alone declares no type parameters of its own wins, as below. Otherwise exactly one candidate must remain, or the call is ambiguous.

```rayo
func f(_ x: Int) { … }      // wins for an Int argument: it alone declares no type parameters
func f<T>(_ x: T) { … }     // needs no conversion either, but declares T
```

**A literal's value counts in step 3, so it can pick the overload.** A `-` on a literal is part of the literal, so `-1` fits no unsigned type ([04](../04-types/collections.md#literals)). Any other untyped value, such as `100 + 200`, fits by its type alone, since these steps work out no arithmetic. A `-` on such a value fits only a signed type, the only kind that has `-` ([04](../04-types/numbers-and-math.md#integer-overflow-division-and-shifts)).

```rayo
func g(_ x: UInt) { … }
func g(_ x: Int) { … }
func h(_ x: UInt) { … }
func h(_ x: Bool) { … }

g(-1)           // calls g(_: Int): a UInt doesn't hold -1
g(-(1 + 2))     // calls g(_: Int): only a signed type has '-'
g(5)            // error: both types hold 5, so the call is ambiguous
g(100 + 200)    // error: arithmetic fits every integer type, so the call is ambiguous
h(-1)           // error: no 'h' takes the arguments
```

**A type that takes a literal by conforming to `ExpressibleByIntegerLiteral` fits by its conformance alone.** Its initializer checks the literal's value at compile time ([04](../04-types/collections.md#literals)). A value that fails that check is the literal's own error, reported once the call has picked its overload, and plays no part in picking it.

**A place lent where a `&T` is expected is a conversion, so of two overloads that differ only in whether they take an argument by reference, the one that takes it as written wins** ([Implicit conversions](implicit-conversions.md#places-lent-where-a-reference-is-expected)). A `&Int` converts to no `Int`, so `&a` picks the overload that takes a reference. A bare place of a type that isn't implicitly copyable picks the owning overload the same way, and then writes `consume` or `copy` as an owning parameter needs ([01](../01-values-and-ownership/references.md#places-given-to-a-position)).

```rayo
func g(_ x: Int) { … }      // g(a) calls this one: it takes 'a' as written
func g(_ x: &Int) { … }     // g(&a) calls this one, since '&a' is a '&Int'
func h(_ e: Enemy) { … }    // h(boss) calls this one, and is an error: write 'consume boss', 'copy boss' or '&boss'
func h(_ e: &Enemy) { … }   // h(&boss) calls this one
```

**A bare argument that every remaining candidate lends counts in step 4 as the `&p` it makes**, since the lending then tells no candidate apart. So only the conversions after it count. A map of `String` keys looks up a `&String` and a `&Text` ([04](../04-types/collections.md#hash-maps-and-sets)), and both lend `name` in `scores[name]`. The `&String` lookup takes the `&name` with no further conversion, so it wins, as it does for `scores[&name]`.

**These steps resolve each call on its own, without backtracking**, so type checking stays local ([11](../11-compilation-model.md#type-checking-is-local)).

**A call `T(x)` with one unlabeled literal argument makes the literal a `T`**, as `x as T` does, so `Float(0)` is the `Float` zero.

**The language makes calls the code doesn't write, and the rules for calls apply to each.** Each one's callee is known statically. So the checks on calls cover them, such as the check that a global's initializer reads no global before it is initialized ([07](../07-concurrency/global-state.md#initialization-at-startup)). They are:

- a `deinit` that a scope's end, an overwrite or a `consume` runs;
- an accessor or an operator;
- a `@converts` or literal initializer;
- an expression pattern's `==`, or a range pattern's `contains`;
- a parameter's or field's default;
- the calls that build an interpolated string;
- a `for` loop's calls to `makeIterator` or `makeMutableIterator`, and to the iterator's `next`;
- an `await`'s calls to its operand's `poll` ([07](../07-concurrency/tasks.md#awaitables)).

**A function declared without `->` returns `Void`.** The exception is a non-public function whose body is a single expression: it returns that expression's type, unless it is `main`, `@c`, `@export`, a `task func` or a protocol witness. A public function is never an exception, since other modules are checked against its declaration, never its body ([11](../11-compilation-model.md#type-checking-is-local)).

**Every path returns.** A body that is a single expression returns its value, unless the result type is `Void`, where the value must itself be a `Void` or a `Never`, since any other would go unused ([below](#unused-values)). Otherwise, in a function, closure, `get` or `task` body whose result type isn't `Void` or a `Void!E`, every path ends in a `return` with a value, a `throw` or a call that never returns ([04](../04-types/enums.md#enums)). So does every path of a `borrow` or `mutate` body, whose `return` hands out a place. A path that reaches the end of a `Void!E` body returns `.success(())`.

**A function whose result type is `Never` has no `return`**, and no path reaches its end. A `while true` loop that no `break` leaves never completes, so no path continues past it.

**A closure literal's body is a function body of its own.** `return` and `throw` leave the closure, `break` and `continue` target only loops inside it, and `await` can't appear in it, even in a `task func`, since a closure is called, not stepped ([07](../07-concurrency/tasks.md#semantics)).

**A closure's parameter types come from a written parameter clause or the expected type**, never from the body, since inference is local ([11](../11-compilation-model.md#type-checking-is-local)). The grammar gives the syntax of trailing closures, `$0` and `{ x in … }` ([12](../12-grammar/constructs.md#expressions)). **A closure's parameters hold their arguments as a function's do**: a `&T` or `mutable &T` parameter names the caller's place, and a `T` parameter owns its argument ([01](../01-values-and-ownership/parameters.md#parameters)). So `e` above is a `ref let` of each enemy, and `body(x)` lends it.

**Only closure literals capture.** These declarations inside a body name none of the body's locals, parameters or `self`:

- a nested function;
- a member, accessor, initializer, `deinit` or field default of a local type;
- a member of a local extension.

## Static and instance members

**A type's static members and its instance members are separate namespaces**, so a static member and an instance member may share a name whatever their kinds and parameters. Qualified code reaches a static member through its type, and an instance member through a value:

```rayo
let lowest = Int.min        // the static property
let m = x.min(y)            // Comparable's instance method, for an Int 'x'
```

The overload rules above, by labels, parameter types and how a method takes `self`, apply within each namespace.

**Each body inside a type is an instance body or a static body**, which decides the members it sees unqualified:

- **Instance bodies.** These are instance methods, initializers, `deinit`, and the accessors of instance properties and subscripts. They see the type's instance members in scope 3 and its static members in scope 4 (below). Where both exist, a call reaches the instance member, and `Self.min`, or an ordinary use, neither a call nor a function value, reaches the static one. The exception is an instance property, which an ordinary use reaches first, being the nearer match.
- **Static bodies.** These are static members and the accessors of static properties. They see no instance members, so only scope 4 holds the type's members for them.
- **Default values.** A default value, of a field or a parameter, sees only static members ([01](../01-values-and-ownership/parameters.md#default-arguments)).
- **Closure literals.** A closure literal looks names up as its enclosing body does. One that names `self` or an instance member captures `self` by the capture rules ([Capturing places](#capturing-places)).
- **Nested functions.** A nested function sees the generic parameters of the function it is in and the enclosing type's static members, but no instance member, since it names no `self` ([above](#functions-and-closures)).
- **Nested types.** A nested type's members see its instance members in scope 3, and in scope 4 its generic parameters, static members and nested types, then each enclosing type's, outward. A member of a local type sees no instance member of the enclosing type, as a nested function doesn't.

**An unqualified name is looked up in these scopes, in order:**

1. the body's locals and parameters ([01](../01-values-and-ownership/bindings.md#names-in-scope));
2. the generic parameters of the function the body belongs to;
3. the instance members the body sees (above);
4. the body's own type, then each enclosing type outward: its generic parameters, static members and nested types;
5. the module's scope, where a prelude name counts unless a declaration of the module or one it imports shadows it ([11](../11-compilation-model.md#the-prelude)).

Each member is in one scope, instance members in 3 and static ones in 4, so no member is found twice:

```rayo
struct Ring<let N: UInt> {
    func cap() -> UInt { N }                  // scope 4: Ring's own value parameter
}

extension Int {
    func check(_ x: Int) { if x < min { … } }   // an ordinary use: skips the method min(_:) and reaches Int.min
}
```

**The nearest match, in scope order, decides how a name resolves.** For a call or a function value, a match that can't be called is skipped, and the search goes on. For an ordinary use, neither a call nor a function value, the nearest match ends the search, whatever it is. A name that isn't called, whether a function value or an ordinary use, skips instance methods, since an instance method is never a value.

**A match that can be called, but isn't a function, ends the search for a call or a function value:**

- a local, a parameter or a property whose type is a function type, a closure's concrete type or a `Closure<F>` ([Closures by concrete type](#closures-by-concrete-type-some-f)). A call `onHit(3)` whose nearest `onHit` is such a field calls the field, even when its type doesn't fit the call;
- a type, or a type parameter, which a call calls for an initializer. A value parameter can't be called, so the search skips it.

**When the first match that can be called is a function, the name gathers candidates across scopes:**

- **Calls.** The candidates are every function of that name in that match's scope and in scopes 3 to 5 together. Those hold the instance members the body sees, the static members of its own type and the enclosing types outward, and the module's scope. The overload rules choose among them ([above](#functions-and-closures)). So `min(a, b)` reaches the free two-argument function, `min(b)` reaches the member, and `helper()` in a member of `Outer.Inner` reaches a static `Outer.helper`.
- **Function values.** A name used as a function value (below), not called, draws its candidates from the same scopes, and the expected type chooses, as for any overloaded name ([Function-typed values](#function-typed-values)). Instance methods aren't function values, so they are never candidates there.
- **Ties.** Step 4's tie-breaks apply first, so a free `f(_ x: Int)` beats a generic member `f<T>(_ x: T)`. A tie left after them goes to the candidate from the nearest scope. So a nested `func f(_ x: Int)` shadows a free one, an enclosing type's static function beats a free one, and a member beats a free one.

**A bare name is used as a function value wherever a function type is expected before the name is resolved**, as in these places:

- a `let` or `var` with a type annotation;
- an assignment to a function-typed place, such as `handler = max`;
- a `return`, or a single-expression body, whose result is a function type, a closure's included, as in `pick` ([Function-typed values](#function-typed-values));
- an element of an array literal whose element type is a declared function type;
- an argument to a callee left with a single candidate, counted after step 1's label and arity filter, so `use(x:)` and `use(f:)` leave one;
- a default value of a function-typed parameter or field.

Anywhere else, such as an argument to a callee left with several candidates, the name is an ordinary use and takes the nearest match. A nearest match that isn't a function is typed in step 2 ([above](#functions-and-closures)).

**So neither a member nor a name that can't be called hides a free function that the call's arguments fit better:**

```rayo
extension Comparable where Self: Copyable {
    func clamped(_ lo: Self, _ hi: Self) -> Self {
        max(consume lo, min(copy self, consume hi))    // fine: two arguments fit only the free min and max, not self.min(_:)
    }
}

extension Int {
    static func cap(_ x: Int) -> Int { max(0, min(x, 100)) }   // fine: the properties Int.min and Int.max can't be called
}

struct Bounds(let min: Float, let max: Float) {
    func clamp(_ x: Float) -> Float { max(min, min(x, max)) }  // the calls skip the fields; the arguments name them
    func show() { use(max) }                                   // the field: 'use' is overloaded, so this is no function value
}

func use(_ x: Float) { … }                                     // so use(max) above calls this one
func use(_ f: (Float, Float) -> Float) { … }
```

## Unused values

```rayo
enemies.popLast()                 // error: the popped enemy is never used
_ = enemies.popLast()             // fine: dropped on purpose
alloc scores.sorted()             // error: a sorted copy, never used; 'scores.sort()' sorts in place
let saved = save(level)           // error if no code reads 'saved': its error would be lost
```

**A value whose type isn't `Void` or `Never` must be used, or it is a compile error.** A value nobody uses is usually a bug: an error dropped, or `alloc x.sorted()` written where `x.sort()` was meant. The rule covers every type, so it also catches an error however deeply a value holds it ([10](../10-errors-and-safety/typed-errors.md#keeping-an-error-as-a-value)). `Void` carries nothing, and an expression of type `Never` never finishes, so neither is checked. A call that returns `Void!Never` has type `Void` ([10](../10-errors-and-safety/typed-errors.md#what-a-failure-type-names)), so it is exempt too.

**A value is unused when it is:**

- an expression written as a statement;
- the value of a `when` or `if` arm, where the `when` or `if` is a statement ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if));
- the single expression of a body whose result type is `Void`;
- held in a parameter that owns its argument, which no code reads;
- assigned to a local, by its declaration or a later assignment, where no path from there reads it before an assignment overwrites it or the local's scope ends.

```rayo
var r = save(a)                   // error: the next line overwrites it before any code reads it
r = save(b)
check(r)
r = save(c)                       // error: no code reads it before the scope ends
```

**A value that one path reads is used, though another path overwrites it**, since the compiler can't tell which path a run takes. So is a value that a loop's next pass reads, though the last pass leaves it unread.

**`_ = consume x` drops a value on purpose.** It takes `x`'s value, and destroys it at the end of its statement. `_ = x` of an implicitly copyable value drops a copy, and leaves `x` as it was ([01](../01-values-and-ownership/references.md#places-given-to-a-position)). `let _ = x` is a compile error ([01](../01-values-and-ownership/bindings.md#bindings-with-no-name)).

```rayo
_ = r.value?.submit(mesh)         // a Void?: nil if the object was gone and 'submit' never ran
_ = try? save(level)              // a Void?: nil if the save failed

let zone = profiler.zone("physics")   // kept only so its deinit records the time
step(mutable world, dt: dt)
_ = consume zone                  // the zone ends here, and this line moves it out

func adopt(_ item: Item) {
    _ = consume item              // this 'adopt' keeps nothing, so it drops what it was handed
}
```

**An optional chain or a `try?` on a call that returns `Void` gives a `Void?`, which must be used too.** It says whether the call ran, and code that ignores it says so with `_ =`.

**A local kept only for what its `deinit` does is ended with `_ = consume x` where its effect should stop.** That statement uses the local, so it isn't unused, and the code shows where a lock is released or a zone ends. Any later borrow, call or move also uses it. Its destruction doesn't: that it uses what the value borrows is a matter of dependencies ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)), not of this rule.

**A parameter that owns its argument, and that the body doesn't need, is dropped with `_ = consume x`.** A parameter always has a name, since `_` before it is only its argument label.

**In generic code, a value whose type is a type parameter or an associated type must be used too.** That follows from checking generic code once: the check knows only that the type may not be `Void` ([Checking generic code](protocols-and-generics.md#checking-generic-code)).

## Trailing closures

**Trailing closures fill the call's parameters in order, scanning forward from those the parentheses give.** A parameter **takes a closure** when its type is one of these:

- a function type;
- `some F`, or a type parameter constrained to a function type ([below](#closures-by-concrete-type-some-f));
- `Closure<F>` ([below](#unscoped-closures-closuref));
- an optional of any of these, such as `(() -> Void)?`, whose `.some` the closure converts to ([04](../04-types/enums.md#optionals)).

**The scan matches each trailing closure to one parameter:**

- the first, unlabeled one goes to the first parameter that takes a closure;
- each later one carries a label, and goes to the next parameter with that argument label;
- a parameter the scan passes over takes its default, and passing over one without a default is a compile error.

So `catchPanic { … } recover: { p in … }` passes its body, then its `recover` closure ([10](../10-errors-and-safety/panics.md#catching-a-panic-catchpanic)), and `s.spawn { … }` passes its closure for a `some F` parameter. A second unlabeled closure is a compile error ([12](../12-grammar/notes.md#blocks-and-closure-literals)):

```rayo
func f(_ a: () -> Void, onCancel: (() -> Void)? = nil, done: () -> Void) { … }
f { start() } done: { finish() }     // the first closure goes to 'a', and 'onCancel' takes its default
f { start() } { finish() }           // error: a trailing closure after the first carries a label

func h(_ done: (() -> Void)? = nil) { … }
h { finish() }                       // the closure converts to the optional's .some
```

## Capturing places

**A closure captures places, not variables.** It captures as precisely as its body names them: a body that reads `world.players` borrows that field, not `world`. So a closure reading one field can be passed alongside an exclusive borrow of another, and two closures in one call may each write a different field.

**The captured place is the longest path the body names through parts kept apart from their siblings** ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)). Those parts are:

- stored fields;
- reflection projections of a field known where the borrows are checked;
- inline array elements at an index known where the borrows are checked, each a place of its own ([04](../04-types/collections.md#inline-array-elements)).

**The path stops before the steps the body evaluates on each call:**

- any other accessor, subscript or index;
- an optional chain, a force unwrap or a payload;
- an object's access;
- a step through a reference, which the body reads from the place that holds it, so the closure captures that place ([01](../01-values-and-ownership/references.md#forwarding-through-a-reference)).

**The path also stops before an under-aligned place**, so the closure captures the aligned place that holds it, since no reference to an under-aligned place may exist ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)). A bitfield is captured through its C memory location, since the bitfields of one memory location are one place for exclusivity ([08](../08-c-interop/imports-and-declarations.md#structs-unions-and-enums)).

**A body that names a borrowing binding captures the place the binding names**, as worked out when it was bound. The capture brings the binding's dependency set and the dynamic accesses the binding holds, which stay held while the closure lives.

## Closure kinds

A closure's type says what it does with its captures, and the compiler infers this kind from the literal's body:

| Kind | Function type | The closure's body |
| --- | --- | --- |
| Non-`mutating` | `(Int) -> Void` | Only reads its captures |
| `mutating` | `mutating (Int) -> Void` | Writes a capture |
| `consuming` | `consuming () -> Mesh` | Moves out of a capture |

- **Non-`mutating`.** Its function types accept only closures that only read their captures, shared-borrowed or owned. So a job system may run one on many threads at once ([07](../07-concurrency/thread-work.md#lending-work-to-other-threads)), and a `sort(by:)` comparator can't write the pool it reads.
- **`mutating`.** A literal captures a place **exclusively** when its body makes any mutable access to it:
    - assigning it;
    - lending it with `mutable`, wherever `mutable` may lend a place ([01](../01-values-and-ownership/references.md#making-a-reference));
    - calling a `mutating` method on it;
    - writing through a mutable reference it holds;
    - capturing it exclusively in a nested literal.

  **Writing through a reference is a mutable access to the place that holds it**, since the write needs that place changeable ([01](../01-values-and-ownership/references.md#forwarding-through-a-reference)). So a literal that writes through a `var` holding a `mutable &[T]` captures the `var` exclusively. One that writes through a `let`'s reference is a compile error, as writing through it outside the literal is. A non-`mutating` literal that captures a mutable reference only reads through it, so parallel work never calls a `mutating` requirement through a captured `mutable &any P`.

  A `mutating` function value is move-only, and calling it mutates the closure itself. So a place holding one is lent with `mutable` or moved with `consume`, and it runs on one thread at a time. A temporary of `mutating` function type is called as it is, since its call changes only the closure it views ([01](../01-values-and-ownership/bindings.md#temporaries-are-read-only)).
- **`consuming`.** A literal whose body moves out of a capture owns that capture. The body moves out with `consume input`, or by taking the capture anywhere a value is taken ([01](../01-values-and-ownership/moves-copies-destruction.md#moves)). The capture moves in when the closure is created, as `[move input]` would. Calling the closure consumes it, so the compiler checks it is called at most once. Copying a capture with `copy` doesn't make it `consuming`, and neither does taking an implicitly copyable one, which copies it ([01](../01-values-and-ownership/moves-copies-destruction.md#implicit-copies)).

  A literal checked against a `consuming` function type, or a `some F` whose `F` is one, is `consuming` whatever its body does. Its concrete type satisfies only `consuming` function types, and it is called at most once.

**A closure that writes a capture is `mutating`, so a parallel loop rejects it:**

```rayo
var n = 0
particles.forEachInParallel { _ in n += 1 }   // error: writes 'n', so it is mutating, but the loop runs it on many threads
var lives = mutable particles.life
times(3) { lives[0] += 1 }                    // fine: captures 'lives' exclusively, and writes through it
lives[0] = 0                                  // fine: the literal's last use is above, so 'lives' is free again
```

**A parameter of function type, or of `some F`, owns its function value or closure, as every `x: T` parameter owns its argument** ([01](../01-values-and-ownership/parameters.md#parameters)). So its body may call it whatever its kind: a `mutating` one from a changeable place, and a `consuming` one once. How a closure gets there depends on the parameter's type:

- **A closure passed for a function-type parameter is converted first** ([below](#function-typed-values)). So a local holding a `mutating` closure is passed as `mutable f`, and stays usable after the call. A local holding a `consuming` closure is passed as `consume f`, and the conversion consumes it.
- **A closure passed for a `some F` parameter moves in**: a literal, or `consume f` of a local. A `mutable &some F` parameter borrows the caller's closure for change instead, as `mutable f` lends it, and a `&some F` parameter borrows it shared.

**`Mutex`'s `lock` is one such function**: its parameter owns the function value, which it calls once:

```rayo
func lock<R: ~Scoped>(_ body: consuming (mutable &T) -> R) -> R { … }   // Mutex<T>'s: 'body' owns its function value
```

**The kinds nest.** A non-`mutating` value is accepted where a `mutating` or `consuming` one is expected, and a `mutating` one where a `consuming` one is. That holds for values only, never for what a mutable reference refers to ([Implicit conversions](implicit-conversions.md#conversions-through-a-mutable-reference)), and it never adds ownership ([below](#function-typed-values)).

## What a closure may keep from its parameters

A closure keeps nothing that depends on its parameters, whether a parameter is lent its argument or given it:

```rayo
m.lock { d in kept = d.items.span }                   // error: 'kept' would depend on 'd', the closure's parameter
let names = alloc entries.map { &$0.name }            // fine: the closure returns a reference into its parameter, and keeps none
for line in src.lines() { collected.append(line) }    // fine: lines() returns a SharedIterator, whose lines outlive it
```

**Nothing a closure stores into its captures may depend on its parameters, or on what they carry.** Rule 5 rejects such a store in a closure body ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)), and a call absorbs nothing from its arguments into the closure, by rule 4 ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)). A closure may still return what depends on a parameter, as the `map` above does. The call's result, and every absorbing argument, by rule 4, still depend on what the closure captures, since the closure is the call's `self`.

**The closure's caller may lend data that stays safe only for the call**, as an `RwLock`'s `read` lends its data while it holds the lock, and releases the lock when the closure returns ([07](../07-concurrency/synchronization.md#locks-mutex-and-rwlock)). A dependency says what a value borrows, but not that the borrow ends with the call, so the closure's captures may depend on none of its parameters. So no view of the data outlives the lock.

**Code that collects what it is handed loops over an iterator.** An iterator that conforms to `SharedIterator` hands out elements that outlive the iteration, since its `next()` is declared `where return outlives self` ([02](../02-views-and-dependencies/dependency-lifetimes.md#staying-valid-after-a-parameter-moves-on-outlives)). So `collected` above depends on `src`, never on the iterator, and the loop's body may store each line.

## Unscoped closures: `Closure<F>`

A callback stored in a struct, or a thread's body, outlives the call that made it, so it owns its captures instead of borrowing:

```rayo
struct Hotkey(var action: Closure<() -> Void>)

let id = 7
var ping = Hotkey(action: { [copy id] in log("pressed \(id)") })   // 'id' is copied in, and stays usable here
var level = alloc Box(alloc Level())
var load = Hotkey(action: { [move level] in start(level.value) })  // 'level' is moved in: it can't be used after this
var oops = Hotkey(action: { log("pressed \(id)") })                // error: 'id' isn't listed
```

**`Closure<F>`**, such as `Closure<mutating (Int) -> Int>`, is an unscoped, move-only value that owns every capture. It is `Sendable` only when its function type is `@sendable`, such as `Closure<mutating @sendable (Int) -> Int>` ([below](#function-typed-values)).

- **Captures are listed.** Each is `[move x]`, or `[copy x]` for a copyable value, which leaves `x` usable. An implicitly copyable value is listed with `copy` too, as `id` is above, since the list is where a closure says how it holds each capture. `self` is listed too, and only a `consuming` method can move it. An unlisted capture is a compile error. A capture the body moves out of is already owned ([above](#closure-kinds)) and needs no entry. A global is never a capture of any closure: the body reaches it as any function does ([07](../07-concurrency/global-state.md#global-state)).
- **Size.** A `Closure` holds small captures inline, laid out as a struct, as a literal's are ([below](#closures-by-concrete-type-some-f)). How much it holds inline, and so its own size, is a layout choice the language leaves open, and code never depends on it ([11](../11-compilation-model.md#what-the-language-leaves-open)). A capture whose layout the language or a library leaves open, such as a task's state, a `Pin<T>` or a value that holds one, is never inline.
- **Allocation.** Captures that aren't inline go in an out-of-line context that the closure owns. So converting a closure to a `Closure` may allocate, as `append` may, and takes no `alloc`: the `Closure` type shows that it may. The context's allocator follows the rule for allocations with no construction ([06](../06-memory-and-allocators/allocator-basics.md#allocations-with-no-construction)).
- **It counts as holding a `Synchronized` value.** Its inline captures may hold one, unseen in its type. So a `Closure` given to a `&T` parameter is always the caller's place ([01](../01-values-and-ownership/parameters.md#borrowed-arguments)), and a packed struct can't hold one ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)).
- **An out-of-line context is checked like any owning storage** ([06](../06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)). Calling a `Closure` whose context outlived its allocator's memory, as when an arena was reset since the closure was made, panics. Destroying such a `Closure` skips its captures' `deinit`s and the free, as for a stale `Box`.
- **Calling.** A stored `Closure<mutating …>` is called only from a changeable place, and calling a `Closure<consuming …>` consumes it.

## Closures by concrete type: `some F`

A closure can also be held by its own concrete type, which never allocates:

```rayo
func times(_ n: UInt, _ body: some mutating () -> Void) { … }   // monomorphized for each literal: never boxed

var hits = 0
var misses = 0
var onHit = { hits += 1 }                           // no annotation: the literal's own concrete type
var onMiss: mutating () -> Void = { misses += 1 }   // annotated: the function type, a view of the literal
```

**Every closure literal has its own anonymous concrete type.** A local initialized with a literal and no type annotation has that type, so it only ever holds that literal; with an annotation it has the function type. The type is laid out as a struct whose fields are its captures ([04](../04-types/structs.md#structs)), declared in this order: the listed captures, in list order, then the others, by reference or moved, in order of first use. A capture by reference is a pointer.

- **A `some F` parameter**, for a function type `F` of any kind, is an anonymous type parameter `B: F`, and takes the literal by its concrete type. The callee is monomorphized for it, and the closure is stored by value, **never boxed or allocated, whatever its size**, like a struct whose fields are its captures. `until` takes its condition this way, so an awaiting task never allocates ([07](../07-concurrency/tasks.md#awaitables-in-std)).
- **Function-type constraints.** A type satisfies `B: F`, for a function type `F`, when it is a closure's concrete type, a function type or a `Closure<G>`, and its values convert to `F` ([Implicit conversions](implicit-conversions.md#implicit-conversions)), which the kinds decide ([above](#closure-kinds)). Generic code calls a `B` as an `F`, converts it to `F`, and, when `B: ~Scoped`, moves it into a `Closure<F>`.
- **The captures decide whether it is scoped.** A literal's type is scoped when any capture is by reference or of a scoped type, such as a `[copy s]` of a `&[T]`. It then depends on the places it captures by reference and on what its captures carry. It is unscoped only when every capture is owned and unscoped ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)).
- **The captures and the kind decide whether it is copyable.** It is copyable when every capture is by shared reference, or owned and copyable, and the literal isn't `consuming`, which is called at most once.
- **Where the type must be unscoped**, as for a parameter constrained `F: ~Scoped`, a literal owns and lists its captures, as for a `Closure`. Elsewhere it captures by reference, except what its capture list names or its body moves out of.

## C function pointers

```rayo
@c func half(_ x: Int32) -> Int32 { x / 2 }
let f: @c (Int32) -> Int32 = half               // a named @c func converts
let g: @c (Int32) -> Int32 = { x in x + 1 }     // so does a literal that captures nothing
unsafe { print(f(4)) }                          // calling one is unsafe
```

**`@c (Int32) -> Int32` is a C function pointer.** It has no room for captures. Its parameters and result cross in their C representations, a `Result` it returns included ([08](../08-c-interop/calling-rayo-from-c.md#c-representations)). Calling one is `unsafe`, since the type can't tell a Rayo function from a C one. These convert to it:

- a literal that captures nothing;
- a named `@c func`, `@export`, imported or `extern(c)` function, or a `@c` value, when its parameters and result have the same types as the pointer type's.

**Inside `unsafe`, a function also converts to a `@c` type whose types differ but have the same C representations** ([08](../08-c-interop/calling-rayo-from-c.md#c-representations)). So a `WeakPointer<Body>` parameter meets a `UInt64` one. A `mutable &T` parameter also meets a `*T` or `*T?` one there, since both cross as `T*`:

```rayo
enum PadButton: Int32 { case start, back }      // crosses as its raw type, Int32
@c func onButton(_ b: PadButton) { … }          // converts to @c (Int32) -> Void
@c func onUpdate(_ s: mutable &State) { … }     // converts to @c (*State) -> Void: both cross as State*
```

**The `unsafe` code that makes such a conversion promises both of these:**

- every call through the pointer passes values valid for the function's own types, and a pointer for a `mutable &T` parameter meets what 08 asks of one ([08](../08-c-interop/c-contract-and-embedding.md#what-c-must-uphold));
- every value the function returns, or writes through a `mutable &T` parameter or a pointer, is valid for the pointer type's types, as 08 asks of C.

**`unsafe (UInt32) -> Void` is an unsafe function type**, whose calls need `unsafe`. Any Rayo function value converts to the `unsafe` form of its type, never back.

**An `unsafe func` converts only to `unsafe` function types** and `Closure`s of them, and, when it is also `@c`, imported or declared with `extern(c)`, to `@c` types. So no function value hides its call from the caller. It satisfies a `some F` or a function-type constraint only when `F` is `unsafe`. Every imported or `extern(c)` function is an `unsafe func` ([08](../08-c-interop/imports-and-declarations.md#what-imports-as-what)).

**A `@c` value converts only to another `@c` type, or its optional**, as above, never to a Rayo function type, a `Closure` or an `unsafe` form. It has no room for captures and no callee known statically, so a Rayo function value of it needs a wrapper that captures the pointer, and a literal writes that wrapper out. A literal that calls C inside an `unsafe` block is an ordinary Rayo function:

```rayo
let now: () -> Double = { unsafe { platform_time_seconds() } }   // a Rayo function type, though its body calls C
```

## Function-typed values

A function-typed value views its closure's storage, so it can't outlive that storage:

```rayo
let put: (mutable &List<&Text>) -> Void = { o in o.append(src) }    // the literal lives as long as 'put'
func pick() -> (Int, Int) -> Int { max }                           // fine: a named function views no storage
func inc() -> (Int) -> Int { return { x in x + 1 } }               // fine: nor does a literal that captures nothing
func sorted(by less: (Int, Int) -> Bool = { a, b in a < b }) { … } // fine, as a default, for the same reason
func mk() -> () -> Int { let x = 5; return { [copy x] in x } }     // error: the result would view mk's temporary
```

**A value of function type is a view of a closure's storage**, where all its captures, owned ones included, live. Converting a closure to a function type makes such a view. A closure here is any value of a closure's concrete type, such as a literal, a local, parameter or field of a literal's anonymous type, or a `some F` parameter. The view depends on the storage and on what the closure carries ([02](../02-views-and-dependencies/dependency-projection-and-results.md#closure-calls)). A non-`mutating` function value is a copyable shared view; a `mutating` or `consuming` one is move-only. None is implicitly copyable, so a place holding one writes a mark wherever it is given ([01](../01-values-and-ownership/moves-copies-destruction.md#implicitly-copyable-types)).

- **A non-`consuming` closure is borrowed as its kind needs** ([Implicit conversions](implicit-conversions.md#function-values-of-closures-in-places)). A non-`mutating` one is borrowed shared, whatever the function type, so the place holding it is lent with `&`, as in `each(xs, &show)`. A `mutating` one is borrowed exclusively, so the place holding it is lent with `mutable`, as in `run(mutable grow)`, and is usable again after the view's last use.
- **A `consuming` closure is handed over.** The conversion consumes the source place, written `consume f` ([01](../01-values-and-ownership/moving-values-out.md#moving-values-out)), and the value takes over the captures but not their memory, so it still can't outlive that memory. Calling it moves out of the captures and destroys the rest; dropping it uncalled destroys them all.
- **Converting a function value never adds ownership.** A value accepted where a stronger kind is expected views the same storage the same way: called through a `consuming` type, a borrowed closure runs with the access it was lent, and dropping the value destroys nothing.
- **Named functions and operators are function values too.** A named function other than `ptr(to:)` ([10](../10-errors-and-safety/unsafe-code.md#taking-an-address)), a static method or an operator, such as `max` or the `+` in `combine: +`, converts to each of these, with parameter types lining up as a witness's do ([01](../01-values-and-ownership/parameters.md#parameters)):
    - `Closure<F>`, for a function type `F` its signature matches;
    - any function type its signature matches, of any kind;
    - if it can't fail, such a type whose result adds a failure type, as `(Int) -> Int!IoError` does for `abs`, when that type leaves the same arguments the caller's place ([01](../01-values-and-ownership/parameters.md#borrowed-arguments)). The compiler makes a function that returns each of its results as `.success`. A function whose result is `T!Never` can't fail either, and its wrapper takes the `T` out as `try` does first ([10](../10-errors-and-safety/typed-errors.md#what-a-failure-type-names)).

  A named function views no storage and depends on nothing, which is why `pick` compiles. An overloaded name is resolved by the expected type. A closure literal that captures nothing converts the same way, since its storage holds nothing. So `inc` and the default of `sorted(by:)` above compile.
- **`@sendable` function types**, such as `@sendable (mutable &Particle) -> Void`, hold only closures whose captures, by reference or owned, all have `Sendable` types, and their values are `Sendable` ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)). A named function always converts to one. A `@sendable` value converts to the same type without the mark, never the reverse, and `Closure<F>` and `some F` carry the mark the same way.

**A literal is kept in a hidden local when it is in one of these places, and the local there depends on its storage after the statement**, by rules 3 and 4 ([02](../02-views-and-dependencies.md#dependencies)):

- a local's initializer;
- the right side of an assignment to a local, or to a path of stored fields from one.

Within either, the literal may be anywhere outside nested closure bodies:

- directly;
- as a call argument at any depth, such as to a primary initializer;
- as an element of a tuple or array literal;
- as an `if` or `when` arm's value.

**The hidden local belongs to the local's scope** ([01](../01-values-and-ownership/moves-copies-destruction.md#destruction)). So `put` above stays usable for its whole scope, and so does `h` here:

```rayo
let h = Handler(onClick: { … })   // the literal is an argument in a local's initializer: kept in a hidden local
```

- **Each such literal gets its own hidden local**, which holds a value only if the literal was made.
- **Each hidden local is destroyed right after the local it was made for.** So the value holding the view is gone first, and what the literal captured, such as a guard on an earlier local's mutex, is released before that local is destroyed.
- **A literal assigned on every pass of a loop reuses its hidden local**, so a still-live copy of the previous value conflicts with the assignment.

**Any other literal is an owning temporary that lives to the end of its full statement** ([02](../02-views-and-dependencies/dependency-projection-and-results.md#temporaries)). Examples are a `return` operand and an argument in another kind of statement. So `mk` fails, and so does appending a literal to a `List<() -> Int>` used after the statement.
