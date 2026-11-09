# Protocols and generics

[05 · Protocols, generics and closures](../05-protocols-generics-and-closures.md)

An area attack can damage enemies, breakable scenery and any later type that has health. The function needs only the operations common to those types:

```swift
protocol Damageable {
    var hp: Float { get set }
    mutating func takeDamage(_ amount: Float)
}

extension Damageable {
    mutating func takeDamage(_ amount: Float) { hp = max(0, hp - amount) }   // default implementation
}

extension Enemy: Damageable {}

func applyAoE<T: Damageable>(_ targets: mutable MutableSpan<T>, amount: Float) {
    for t in &targets { t.takeDamage(amount) }
}
```

**A protocol names requirements that a conforming type meets**, such as the `hp` property and the `takeDamage` method of `Damageable` above. `applyAoE` can change a span of any `Damageable` type. The compiler checks its body against the protocol, then makes a separate instance for each concrete element type ([below](#instantiation)).

**A protocol may inherit others, and declare static requirements and associated types, constrained by `where` clauses** ([12](../12-grammar/declarations.md#files-and-declarations)). An associated type is a type that the protocol leaves to each conformance to choose.

**A requirement whose `where` clause constrains `Self` or an associated type is required only of conformances that satisfy the clause**, as `Comparable`'s `min` and `max` require `Self: Copyable` ([Equality and ordering](operators.md#equality-and-ordering)):

- **Where it is required.** A conformance must meet it under the conformance's own conditions plus the clause, and its witness is checked there. A conditional conformance, `extension X: P where …`, follows the same rule.
- **Witnesses.** A member of the conformer, or of an extension of it whose `where` clause those conditions imply, may be the witness. Otherwise the default applies, to each instantiation where the clause holds. A conformer that never meets the clause provides none, and a member of that name it declares is an ordinary member, not a witness (below).
- **Generic calls.** Generic code may call it only where its own constraints imply the clause.
- **Existentials.** Through `any P` it is callable only when `P` itself implies the clause, since the existential may hold a conformer that fails it.

```swift
func lowest<T: Comparable & Copyable>(_ a: T, _ b: T) -> T { a.min(b) }   // fine: T: Copyable implies the clause
func lowest2<T: Comparable>(_ a: T, _ b: T) -> T { a.min(b) }             // error: T may be move-only
```

A generic conformer can meet such a requirement in a constrained extension. `Pair<T>` is copyable exactly when `T` is, so its conformance's conditions plus `Self: Copyable` imply the extension's `T: Copyable`:

```swift
struct Pair<T: Comparable>(let a: T, let b: T): Comparable {
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.a < rhs.a || (lhs.a == rhs.a && lhs.b < rhs.b) }
}

extension Pair where T: Copyable {
    func min(_ other: Self) -> Self { … }    // the witness of min for every copyable Pair<T>
}
```

**A member of a conforming type, or of an extension of one, with a constrained requirement's name and signature that isn't its witness is a compile error**, wherever it is declared. Otherwise a concrete call would reach the member while generic code reaches the witness. The exception is a conformer that never meets the clause, such as a move-only `Comparable` type that declares its own `min`. Generic code can't call the requirement there, so no two calls disagree:

```swift
extension Pair where T == Int {
    func min(_ other: Self) -> Self { … }    // error: Pair<Int> already has a witness of min, above
}
```

**A conformance binds each associated type in the first of these ways that applies:**

1. by a `typealias`, nested type or generic parameter of that name;
2. by the associated type's default;
3. from the witness of the first requirement, in the protocol's order, whose declared type names it, with no search; in a failure position, it skips witnesses that can't fail (below).

```swift
protocol Table { associatedtype Row }    // the conforming type chooses 'Row'
struct Archetype<Row>(…): Table          // its generic parameter 'Row' binds Table's 'Row'
```

**An associated type `E` in a failure position never binds from a witness that can't fail.** That position is the `E` of a `{ get }` requirement's type `T!E`, or of a function's or initializer's result type, as in `func load() -> Level!E` and `init() -> Self!E`. In a `{ get set }` or place requirement, `E` binds from the witness's type, as in any other position.

**A witness whose type or result type is `T`, `Self`, `T!Never` or `Self!Never` can't fail.** A `T!Never` counts since the wrapper that meets the requirement takes its `T` out as `try` does, which never fails. Such a witness meets the requirement whatever `E` is, and binds nothing ([10](../10-errors-and-safety/typed-errors.md#what-a-failure-type-names)). So step 3 skips it:

- `E` binds from the first requirement, in the protocol's order, that names `E` outside a failure position or whose witness can fail;
- `E` is `Never` when every requirement naming it is in a failure position and no witness can fail, as the pair rule binds from a type that isn't a `Result`.

So the order of the requirements never decides whether a type conforms:

```swift
protocol Gauge {
    associatedtype Failure: Error
    var value: Int!Failure { get }
    func reload() -> Int!Failure
}
struct Fixed(let value: Int): Gauge { func reload() -> Int { value } }         // neither can fail: Failure is Never
struct Sensor(let value: Int): Gauge { func reload() -> Int!IoError { … } }    // Failure is IoError; 'value' meets Int!IoError too

protocol Probe {
    associatedtype Failure: Error
    var value: Int!Failure { get }
    var lastError: Failure? { get }                                            // names Failure outside a failure position
}
struct Thermometer(let value: Int, var lastError: IoError?): Probe             // lastError binds Failure to IoError
```

**`some P` is written only as a parameter's type**, where it is an anonymous type parameter constrained `P`.

## Protocol extensions

**A protocol extension of `P` declares members of every type conforming to `P`**, checked once as generic code over `Self: P`, and adds no requirement or stored member. The extension of `Damageable` above is one. Its members are of two kinds:

- **Defaults.** A member that matches a requirement is its **default**, the witness of each conformance whose type declares none, as `takeDamage` is for `Enemy`. Only the protocol's module declares defaults. A member matching a requirement in another module's extension is a compile error, so every module sees the same witness ([below](#conformances)).
- **Other members.** Any other member is never a witness. A call to it is resolved statically, with `Self` the receiver's type. A call to it on an `any P` unpacks the receiver as an argument for a `T: P` parameter does ([below](#unpacking-an-existential)).

## Checking generic code

**Generics are type-checked once, at the definition, against their constraints:**

```swift
func toughest<T: Damageable>(_ xs: Span<T>) -> Float {
    var best: Float = 0
    for x in xs { best = max(best, x.hp) }    // fine: Damageable requires 'hp'
    for x in xs { best += x.armor }           // error here, at the definition: Damageable has no 'armor'
    return best
}
```

**Checking once keeps type checking local**: a module is checked against the interfaces of the modules it imports, not the bodies of their generics, except for the compile-time code below ([11](../11-compilation-model.md#type-checking-is-local)). The check assumes no more of a type parameter than its constraints say: an unconstrained one may be move-only, scoped, a mutable view or not `Sendable`, among other things. So a body that passes is sound for every instantiation.

**So a generic fails at an instantiation only in these cases, where the arguments decide the outcome:**

- in compile-time code and the body that holds it (below);
- past the instantiation depth limit ([below](#instantiation));
- where a builtin type's conditions on its arguments fail, such as `Simd<T, N>`'s lane count ([04](../04-types/numbers-and-math.md#simd-and-math)) or an inline array's count ([04](../04-types/collections.md#tuples-ranges-and-arrays));
- where a shuffle's index is out of range for a generic `N`, or its result's count isn't a lane count ([04](../04-types/numbers-and-math.md#shuffles-and-swizzles));
- where a swizzle names a lane that a vector of a generic `N` lacks ([04](../04-types/numbers-and-math.md#shuffles-and-swizzles)).

**Compile-time code is one exception: it is checked at each instantiation, and an error there is reported at the instantiation.** Its meaning depends on the type arguments, as the members a type generates from its parameters do ([09](../09-compile-time/declaration-generation.md#generated-members-are-checked-per-instantiation)). It is any of these parts of generic code ([09](../09-compile-time.md)):

- `static if` branches, checked only when their condition holds;
- `static for` bodies and static closures, checked per element;
- `const` expressions and reflective operations on a type parameter, such as `Row.field(ofType:)` and `T.construct`;
- members generated from generic parameters ([09](../09-compile-time/declaration-generation.md#generating-declarations)), and computed names ([09](../09-compile-time/declaration-generation.md#computed-names)).

**So a `static if` branch may use what only some instantiations allow**, as 09's `store` calls `w.bytes(of:)`, which accepts only a padding-free `Pod` type ([09](../09-compile-time/constants-and-conditions.md#static-if-and-conditional-compilation)).

**Some bodies have their moves, borrows and dependencies checked on the body each instantiation expands**, since a branch, an unrolled copy or the place a projection reaches changes what the code after it may use. They are the bodies holding one of these that depends on a compile-time argument:

- a `static if`;
- a `static for`;
- a static closure;
- a reflective projection: `value[f]`, `value[fields:]` or `value[case:]`.

**The checks that run on the expanded body are those of moves, initialization, borrows, dependencies, the places that place properties hand out, and `self.init` calls.** So a move in a `static for` body moves once per element ([09](../09-compile-time/reflection.md#static-reflection)).

## Instantiation

**Generics are monomorphized**: each is compiled separately for each set of type arguments, and never implicitly called through a witness table (a type's table of implementations of a protocol's requirements), in any build or across any module boundary. So a call through a witness table happens only through `any P`, where the source shows it ([11](../11-compilation-model.md#runtime-costs)).

**Instantiation always ends.** Since every instantiation is compiled, a generic function, subscript or type that reaches itself with a type argument that strictly contains one of its own parameters would need infinitely many. So it is a compile error at the definition:

```swift
func nest<T: Copyable>(_ x: T, _ n: Int) {
    guard n > 0 else { return }
    nest((copy x, copy x), n - 1)    // error: nest<T> reaches nest<(T, T)>, whose argument contains T
}
```

**Growth that only instantiation reveals is a compile error at the instantiation where the chain passes the toolchain's instantiation depth limit** ([11](../11-compilation-model.md#what-the-language-leaves-open)). Such growth comes through one of these:

- a protocol requirement's witness;
- an unpacking call ([below](#unpacking-an-existential));
- compile-time code;
- value arguments.

```swift
func f<let N: Int>() { f<N + 1>() }   // grows through its value argument: an error where the chain passes the limit
```

## Value parameters and type values

**A generic parameter declared `let` takes a `const` value** of an integer type, `Bool` or an enum without payloads, as `N` does in `Simd<T, N>`. Such a parameter is a **value parameter**. Two arguments are the same exactly when they are the same value: the same integer, the same `Bool` or the same case, whatever `==` the type declares.

**`T.self` is a value that names the type `T`, of type `Type<T>`**: empty, copyable, `Sendable` and `const`. Such a value is a **type value**. So a function can take a type as an argument and bind a type parameter from it, as a span's `reinterpret` does:

```swift
func reinterpret<U: Pod>(as _: Type<U>) -> Span<U>?   // binds U from the type value it is passed
let verts = bytes.reinterpret(as: Vertex.self)         // U is Vertex
```

**A type that isn't a name is parenthesized**, as in `(Int, Float).self` and `([4 of Float]).self`. For a protocol `P`, `P.self` names the protocol, and only a reflection query that takes a protocol accepts it, such as `T.conforms(P.self)` ([09](../09-compile-time/reflection.md#what-reflection-can-read)).

**`T == U`, `T != U` and `T.conforms(P.self)` are `const`**, usable in `static if`. A `where` clause states the same as `T == U`, `T != U` and `T: P` ([12](../12-grammar/declarations.md#files-and-declarations)).

## Default type arguments

Most maps hash the same way, so std's `Map` lets code leave its hashing type out ([04](../04-types/collections.md#hash-maps-and-sets)):

```swift
struct Map<K: Hashable, V, H: Hashing = SeededHashing>(…)

let a: Map<Name, Int> = [:]                           // Map<Name, Int, SeededHashing>
let b: Map<Name, Int, FixedHashing> = [:]             // the default replaced
let c: Map<Name, Int, FixedHashing> = Map()           // H comes from the expected type
func report<K>(_ m: Map<K, Int>) { … }                // takes only maps with SeededHashing
func reportAny<K, H>(_ m: Map<K, Int, H>) { … }       // takes a map with any hashing type
```

**A type parameter of a struct, enum or union may name a type after `=`**, which a written type that leaves the argument out takes instead. That type is the parameter's **default type argument**. A function's, an initializer's or a subscript's type parameters name none, and neither does a value parameter. A default follows these rules:

- **Trailing.** Every type parameter after one with a default has one too, so written arguments fill the parameters in order.
- **Checked at the declaration.** The default meets the parameter's constraints, and names none of the type's own parameters.
- **Taken where an argument is left out.** A type written with fewer arguments than it has parameters takes the default for each one left out. That holds wherever the type is written: in an annotation, a parameter's or field's type, after `as`, or in an extension's header, as `extension Map<Name, Int>` extends only `Map<Name, Int, SeededHashing>`.
- **Taken where inference gives nothing.** Where a type's arguments come from a call, as for `Map()` above, the default is the last way a parameter binds, after the call's arguments and its expected type ([Operators](operators.md#operators)). So a `_` written for such a parameter, as in `Map<_, _, _>`, takes the default when the initializer leaves it unbound.

**A type written with no arguments at all, in an extension's header, still covers every instance**, so `extension Map` extends maps with every hashing type ([04](../04-types/structs.md#initializers)). **Generic code that should take any hashing type declares a parameter for it**, as `reportAny` does, since `Map<K, V>` in a signature means `Map<K, V, SeededHashing>`.

## Conformances

**A type conforms by declaring it, except the conformances the language gives**: the derived marker protocols, such as `Copyable`, `Sendable` and `Frozen`, the structural `Equatable`, `Comparable` and `Hashable` conformances ([Equality and ordering](operators.md#equality-and-ordering)), and `SimdLane`'s, which no type can declare ([04](../04-types/numbers-and-math.md#simd-and-math)). A **marker protocol** has no requirements, and states a property of a type. Each requirement is met by a **witness**: a method, initializer, operator, subscript, property or stored field, and for an associated type, a type.

```swift
protocol HasHp { var hp: Float { get set } }
struct Crate(var hp: Float): HasHp        // the stored field 'hp' is the witness
struct Rock(let hp: Float): HasHp         // error: a 'let' field witnesses only get and read requirements
```

**These rules say where a conformance is declared, and what it implies:**

- **Conformances are declared** in the type's module or the protocol's (the orphan rule), so lookup is local. An implied conformance obeys it too. Take a conformance to `Q` declared in neither the type's module nor that of a protocol `B` that `Q` inherits. It implies one to `B` only where the type's conformance to `B` is already declared in the type's module or `B`'s, or given by the language. Otherwise it is a compile error that asks for that declaration. So every module that sees the type and `B` sees the one conformance between them.
- **A conformance is one fact for the whole program.** An extension declares a conformance only at a file's top level, never inside a function's or a type's body, where one declaration would stand for one conformance per instantiation. A local type declares its own conformances in its header.
- **A type conforms to a protocol through one conformance.** A conformance to a protocol `Q` implies one, with its conditions, to each protocol `Q` inherits, except where a declared conformance to that protocol already holds for every type it covers. Implied conformances of one type to one protocol with the same conditions are one, so `Comparable, Hashable` implies `Equatable` once. Any other two conformances of one type to one protocol, declared or implied, are a compile error whatever their `where` clauses, since generic code could then see one associated type as two types.
- **Derived and restricted marker protocols are never implied.** A conformance to `Q` implies none of the marker protocols the language derives or restricts: `Copyable`, `Sendable`, `Frozen`, `Pod`, `TrivialFree`, `Scoped`, `Synchronized` and `SimdLane`. Each one `Q` inherits must already hold for every type the conformance covers, derived or declared under that protocol's own rules. Otherwise the conformance is a compile error, as listing `Copyable` for a move-only type is ([01](../01-values-and-ownership/moves-copies-destruction.md#copyable-types)). So a protocol that inherits `Copyable` admits only copyable types, and a type conforming to `AllocatorImpl`, which inherits `Synchronized`, declares `: unsafe Synchronized` itself, unconditionally (next).
- **`~Copyable`, `~Sendable`, `Scoped` and `Synchronized` are declared unconditionally.** Each is declared in the type's own module, in its declaration or in an unconditional extension ([04](../04-types/structs.md#initializers)). None is declared in an extension that gives some of the type's generic arguments, such as an extension of `Cell<Int>`, or that has a `where` clause. Generic code relies on this, since it derives a generic type's copyability, sendability and scope from its fields, its type arguments and these declarations, for every type argument at once ([01](../01-values-and-ownership/moves-copies-destruction.md#copyable-types), [07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable), [02](../02-views-and-dependencies/scoped-values.md#which-types-are-scoped)).

**What a member can witness depends on what its name allows where the conformance is declared:**

- **A member of a constrained extension witnesses only where its clause holds.** It meets a requirement only where the conformance's conditions, plus the requirement's own `where` clause, imply the extension's `where` clause, as `Pair`'s `min` does ([above](#protocols-and-generics)).
- **A witness is in its requirement's namespace.** An instance requirement is met only by an instance member, and a static requirement, an initializer included, only by a static one, since the two are separate namespaces ([Static and instance members](functions-and-closures.md#static-and-instance-members)). So `Int`'s static `min` meets no instance `min(_:)` requirement.
- **A witness is visible where the conformance is declared.** A member, a stored field included, that code there couldn't name witnesses nothing, so a protocol's module can't reach another module's non-public member through a conformance it declares.
- **A stored field witnesses a requirement only where its name could be used the same way**, since generic code reaches a witness with no `unsafe` in sight. So a `let` field witnesses only `get` and `borrow` requirements.
    - **`unsafe` fields and union members.** An `unsafe` field, or a union member that isn't safe to read ([04](../04-types/enums.md#untagged-unions)), witnesses one only in a conformance declared `: unsafe P`. That promises that every value generic code can read or write through the witness is valid.
    - **Bare global `var`s.** A static stored `var` that isn't `@threadlocal` is a bare global `var` ([07](../07-concurrency/global-state.md#global-state)). It witnesses only a `{ get }` or `{ get set }` requirement of a copyable type, whose every access copies, and only under `: unsafe P`. There, `: unsafe P` promises that no access through it races with another.
    - **Thread-locals.** A `@threadlocal` static `var` witnesses no place requirement ([02](../02-views-and-dependencies/place-and-value-properties.md#properties-in-protocols)), since every access to it is a dynamic access that a view of it can't outlast, by rule 6 ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). When its type is copyable, it witnesses a `{ get }` or `{ get set }` requirement, each access copying under its own dynamic access.
- **An `unsafe` witness, a function, initializer, operator, subscript or accessor, meets only an `unsafe` requirement**, or any requirement in a conformance declared `: unsafe P`, promising that every call generic code can make through it is safe. An `unsafe` requirement's callers write `unsafe`, except the build's call for an interned literal ([10](../10-errors-and-safety/unsafe-code.md#what-needs-unsafe)).

**`unsafe protocol P` declares a contract the compiler can't check**, such as "memory is never handed out twice" for `AllocatorImpl` ([06](../06-memory-and-allocators/allocator-implementations.md#writing-an-allocator-allocatorimpl)).

- **Declared conformances to it are promises.** Every declared conformance to it is written `: unsafe P`. A derived one, as `Frozen` is for a type with no interior mutability ([06](../06-memory-and-allocators/owning-values.md#frozen-types-with-no-interior-mutability)), is no promise. `@safe` modules can declare no `: unsafe` conformance, since they reject everything the compiler takes on trust ([10](../10-errors-and-safety/unsafe-code.md#safe-modules)).
- **Inheriting an `unsafe` protocol.** A conformance to a protocol `Q` that isn't `unsafe` itself but inherits an `unsafe` one promises only through the conformance it implies. It needs no `unsafe` when every type it covers already conforms to that protocol, by a conformance declared elsewhere whose conditions `Q`'s imply. Nor does it when that protocol is one of the marker protocols the language derives or restricts, which are never implied and so already hold ([above](#conformances)). Otherwise it is written `: unsafe Q`.

## `any P`: explicit dynamic dispatch

**`any P` holds a value of any type conforming to `P`, and calls its requirements through the witness table.** It is for a type known only at run time, as in a list of different widgets:

```swift
func drawAll(_ items: Span<any Drawable>, _ ctx: mutable DrawContext) {
    for d in items { d.draw(&ctx) }                  // dynamic dispatch, visible in the signature
}

var widgets = List<Box<any Widget>>()
widgets.append(Box(Button(label: "Play")))          // allocation, visible in source
for w in &widgets { w.value.update(dt) }           // mutable any Widget: mutating requirement, dynamic dispatch
```

**`any P` is an existential, and never allocates implicitly**, since no build does work at run time that its source doesn't show ([11](../11-compilation-model.md#runtime-costs)). So the `Box` above is written out. Its forms are views, which borrow a value, and unscoped existentials, which hold one or point at one:

| Form | What it is | Made from |
| --- | --- | --- |
| `any P` | Shared view: scoped, copyable | A shared borrow of a `T: P`, or of an unscoped existential's `value` |
| `mutable any P` | Exclusive view: scoped, move-only | An exclusive borrow `&place` of a `T: P`, or of an unscoped existential's `value` |
| `Box<any P>` | Unscoped existential, on the heap | A `Box` holding an unscoped `T: P` |
| `UniquePointer<any P>`, `WeakPointer<any P>` | Unscoped existentials of objects | An object pointer of the same kind to an unscoped `T: P` |
| `Shared<any P>`, `LocalShared<any P>`, `WeakShared<any P>` | Unscoped existentials of reference-counted values | A reference-counted pointer or weak link of the same kind to an unscoped `T: P` |

**`any P & Sendable`** accepts only `Sendable` types, and is `Sendable` ([07](../07-concurrency/race-freedom-and-sendable.md#what-may-cross-threads-sendable)). An existential hides its value's type, which may not be `Sendable`, so it is `Sendable` only when its protocols say so.

**A `Shared`'s value must be `Frozen` or `Synchronized`** ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)), and an existential is `Frozen` only when its protocols say so, as for `Sendable`. So a `Shared`'s existential is `Shared<any P & Frozen>`, or `Shared<any P>` for a `P` that inherits `Frozen` or `Synchronized`, as `WakeTarget` inherits `Synchronized` ([07](../07-concurrency/tasks.md#awaitables)).

**`any P` calls only requirements that are neither `mutating` nor `consuming`.** It is a shared view, whose value other views may be reading, so it can't change that value ([01](../01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)). No existential view calls a `consuming` requirement, since none owns the value. An owned `Box<any P>` reaches one by unpacking as an `owned T`, as a static or `init` requirement is called only on an unpacked value's type ([below](#unpacking-an-existential)).

**`mutable any P` is a type of its own.** `&place` makes one wherever one is expected, including assigned into an existing slot, as `d = &crate` does in a loop over `&targets` ([02](../02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind)). A `mutating` requirement called through it changes the value it views. So the view must be in a changeable place ([01](../01-values-and-ownership/bindings.md#changeable-places)), such as a `var` binding, never a shared borrow:

```swift
targets.append(&boss)                       // a list of mutable any Damageable views: 'boss' stays borrowed exclusively
for d in targets { d.takeDamage(1) }        // error: 'd' is a shared borrow of a view, not a changeable place
for d in &targets { d.takeDamage(1) }       // fine: the loop lends 'targets', so 'd' can change
```

**So a parameter of type `mutable any P` is received owned** unless declared `mutable`, as a `mutating` function type's is ([Closure kinds](functions-and-closures.md#closure-kinds)). An owned parameter is a changeable place, so `strike` can call `mutating` requirements through `d`:

```swift
func strike(_ d: mutable any Damageable) { d.takeDamage(10) }   // 'd' is received owned
```

**A non-`mutating` closure captures a `mutable any P` shared**, so parallel work can't call `mutating` requirements through it ([07](../07-concurrency/thread-work.md#lending-work-to-other-threads)).

**At a call, `&place`, or `&v` for a variable holding a `mutable any P`, makes the view the parameter receives** ([Implicit conversions](implicit-conversions.md#implicit-conversions)). Stored views keep their places borrowed: after `targets.append(&boss)` above, `boss` stays borrowed exclusively, by rule 4 ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)).

**Exclusive access to a place holding a shared `any P` changes which value it views, never that value:**

- **`MutableRef<any P>`**, what a loop over `&` a `List<any P>` yields, is an exclusive view of a slot holding a shared `any P`. Through it `d` can reassign the shared view but never reach its value. So `d.takeDamage(1)` is a compile error, since the slot holds a shared view, whose value other views may be reading.
- **`d: mutable (any P)`**, with parentheses, lets a callee reassign which value the caller's shared view refers to ([12](../12-grammar/notes.md#parentheses-and-conventions-in-types)).

**`Box<any P>` holds an unscoped value in a heap allocation.** `box.value` is a place property that lends the value as an `any P`, borrowed or `mutable` ([02](../02-views-and-dependencies/place-and-value-properties.md#place-properties-borrow-and-mutate)). Assigning to `box.value`, or through any `mutable any P`, is a compile error, since it could change the value's type and size. Unpacking it as `mutable T` ([below](#unpacking-an-existential)) can replace the value, with one of the same type.

**`box[as: T.self]` is an optional place property that hands out the value as a `T`**, borrowed or `mutable` as `box.value` is, and `nil` when its dynamic type isn't `T`. The language provides it, as it provides `UniquePointer.value` ([02](../02-views-and-dependencies/place-and-value-properties.md#places-behind-a-run-time-check)), since no Rayo declaration can be generic over the protocol inside `Box<any P>`. So a test that fails moves nothing:

```swift
if var s = &box[as: Slider.self] { s.label = "Go" }   // a Slider changes in place; any other value stays as it was
```

**The unscoped existentials are types of their own, which binding a type parameter never makes.** They are `Box<any P>`, and the object pointers, reference-counted pointers and weak links to `any P`. A value of one holds or names only an unscoped value, and comes from one of these:

- the conversion to it ([Implicit conversions](implicit-conversions.md#implicit-conversions));
- for a weak pointer or a weak link, `WeakPointer<any P>(bits:)` or `WeakShared<any P>(bits:)` ([03](../03-handles-and-objects.md#weak-pointers-as-bits-and-handing-objects-to-c), [06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners));
- another unscoped existential of the same protocol, as `u.weak()` makes a `WeakPointer<any P>` from a `UniquePointer<any P>`.

**A box that holds a shared view `any P` itself is a different type**, written `Box<(any P)>`, as `mutable (any P)` is ([12](../12-grammar/notes.md#parentheses-and-conventions-in-types)). Generic code gets it from `Box<T>` with `T` bound to `any P`, and it is scoped, since it holds a view ([02](../02-views-and-dependencies/scoped-values.md#which-types-are-scoped)).

**Object pointers to `any P`** ([03](../03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)) reference objects of different types, as an observer list `List<WeakPointer<any Listener>>` does. Their accesses give what `box.value` does: `any P` for a shared access and `mutable any P` for an exclusive one. `w.downcast(to: T.self)` gives back a `WeakPointer<T>?`.

**Reference-counted pointers to `any P`** ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)) give a shared `any P` through `s.value`, and `w.upgrade()` on a `WeakShared<any P>` gives a `Shared<any P>?`.

**A requirement whose signature mentions `Self` or an associated type can be called only on an unpacked value** ([below](#unpacking-an-existential)), not through `any P`, since two existentials' dynamic types needn't match.

**A generic requirement, one with type parameters of its own, is callable through `any P` too, unless its signature mentions `Self` or an associated type**, as unpacking works (next). It has one witness per set of type arguments, and the call reaches the witness of the value's dynamic type, specialized for the call's type arguments.

## Unpacking an existential

```swift
func refill<T: Damageable>(_ t: mutable T) { t.hp = 100 }

func refillAll(_ targets: mutable List<Box<any Damageable>>) {
    for b in &targets { refill(&b.value) }       // unpacks each box: T is that value's dynamic type
}
```

**Passing an existential to a generic parameter `T: P` unpacks it: `T` is the value's dynamic type for that call.** A shared `any P` unpacks only as a borrowed `T`. A `mutable any P`, or an unscoped existential's `value` lent for change, also unpacks as `mutable T`, whose whole value the generic code may replace, since the type can't change. An owned `Box<any P>` also unpacks as an `owned T`: its value moves out into the call, and its allocation is freed.

**`any P` never conforms to `P`, so it can't bind `T` without unpacking.** Two existentials unpack to two types, and a box's `value` isn't a place of type `any P` that `T` could bind as the view type (below). So passing two boxes' values for one `T` is a compile error:

```swift
swap(&a.value, &b.value)   // error: two Box<any Widget>s, whose values unpack to two types
```

**These rules decide whether a call unpacks:**

- **Where it unpacks.** Only into a parameter whose type is `T` itself, borrowed or `mutable`, or `owned` for an owned `Box<any P>`. Nothing else in the signature may mention `T`: no other parameter, the result, its failure type included, or a `where` clause beyond `T`'s own constraints. `P` must imply every one of `T`'s constraints, and an unscoped existential's `value` or owned value also meets `T: ~Scoped`, since it holds only unscoped values.
- **Where it doesn't.** When `any P` itself meets `T`'s constraints, as it meets those of an unconstrained `T` or of `T: Copyable`, it binds `T` as the view type instead, and a `Box<any P>` that meets them binds `T` as itself. Any other call that would need `T` to be `any P` is a compile error.

**An unpacking call costs one indirect call, and an instance for each possible dynamic type.** An unpacking call site names one generic function, every type argument but `T` fixed. The program holds an instance of it for every type that can be the dynamic type of an existential of `P`:

- each type the program converts to an existential of `P` or of a protocol that implies `P`;
- where the program calls `WeakPointer<any P>(bits:)` or `WeakShared<any P>(bits:)`, the type of each object or `Shared` value the program creates that conforms to `P`.

The call reaches the instance for the value's dynamic type with one indirect call.
