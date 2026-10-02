# 05 · Protocols, generics and closures

## Protocols and generics

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
    for var t in &targets { t.takeDamage(amount) }
}
```

**A protocol may inherit others, and declare static requirements and associated types, constrained by `where` clauses** ([12](12-grammar.md#files-and-declarations)).

**A conformance binds each associated type in the first of these ways that applies:**

1. by a `typealias`, nested type or generic parameter of that name, as `struct Archetype<Row>(…): Table` binds `Row`;
2. by the associated type's default;
3. from the witness of the first requirement, in the protocol's order, whose declared type names it, with no search.

**`some P` is written only as a parameter's type**, where it is an anonymous type parameter constrained `P`.

**A protocol extension of `P` declares members of every type conforming to `P`**, checked once as generic code over `Self: P`, and adds no requirement or stored member. `extension Damageable { … }` above is one.

- **Defaults.** A member that matches a requirement is its **default**, the witness of each conformance whose type declares none. Only the protocol's module declares defaults. A member matching a requirement in another module's extension is a compile error, so every module sees the same witness ([below](#conformances)).
- **Other members.** Any other member is never a witness. A call to it is resolved statically, with `Self` the receiver's type. A call to it on an `any P` unpacks the receiver as an argument for a `T: P` parameter does ([below](#unpacking-an-existential)).

**Generics are type-checked once, at the definition, against their constraints:**

```swift
func toughest<T: Damageable>(_ xs: Span<T>) -> Float {
    var best: Float = 0
    for x in xs { best = max(best, x.hp) }    // fine: Damageable requires 'hp'
    for x in xs { best += x.armor }           // error here, at the definition: Damageable has no 'armor'
    return best
}
```

So they fail at instantiation only in these cases:

- in compile-time code and the body that holds it (below);
- past the instantiation depth limit (below);
- where a builtin type's conditions on its arguments fail, such as `Simd<T, N>`'s ([04](04-types.md#simd-and-math)) or an inline array's count ([04](04-types.md#tuples-ranges-and-arrays)).

**Compile-time code is one exception: it is checked at each instantiation, and an error there is reported at the instantiation.** It is any of these parts of generic code ([09](09-compile-time.md)):

- `static if` branches, checked only when their condition holds;
- `static for` bodies and static closures, checked per element;
- `const` expressions and reflective operations on a type parameter, such as `Row.field(ofType: Transform.self)` and `T.construct`;
- members generated from generic parameters, and computed names ([09](09-compile-time.md#generating-declarations)).

**In some bodies, the checks of moves, borrows and dependencies run on each instantiation's expanded body.** They are the bodies holding one of these that depends on a compile-time argument:

- a `static if`;
- a `static for`;
- a static closure;
- a reflective projection: `value[f]`, `value[fields:]` or `value[case:]`.

Such a body has its moves, initialization, borrows, dependencies, yields and `self.init` calls checked on each instantiation's expanded body. They are checked there since a branch, an unrolled copy or the place a projection reaches changes what the code after it may use.

**Generics are monomorphized**: compiled separately for each set of type arguments, and never implicitly called through a witness table (a type's table of implementations of a protocol's requirements), in any build or across any module boundary.

**Instantiation always ends.** Since every instantiation is compiled, a generic function or type that reaches itself with a type argument that strictly contains one of its own parameters, as `func nest<T: Copyable>(_ x: T, _ n: Int)` calling `nest((copy x, copy x), n - 1)` does, would need infinitely many. So it is a compile error at the definition. Growth that only instantiation reveals is a compile error at the instantiation where the chain passes the toolchain's instantiation depth limit ([11](11-compilation-model.md#what-the-language-leaves-open)). Such growth comes through a protocol requirement's witness, an unpacking call ([below](#unpacking-an-existential)), compile-time code or value arguments, as in `func f<let N: Int>() { f<N + 1>() }`.

**A generic parameter declared `let` takes a `const` value** of an integer type, `Bool` or an enum without payloads, as `N` does in `Simd<T, N>`. Such a parameter is a **value parameter**. Two arguments are the same exactly when they are the same value: the same integer, the same `Bool` or the same case, whatever `==` the type declares.

**`T.self` is a value that names the type `T`, of type `Type<T>`**: empty, copyable, `Sendable` and `const`. Such a value is a **type value**. So a function can take a type as an argument and bind a type parameter from it, as `func reinterpret<U: Pod>(as _: Type<U>) -> Span<U>?` does for `bytes.reinterpret(as: Vertex.self)`. A type that isn't a name is parenthesized: `(Int, Float).self`, `([4 of Float]).self`. For a protocol `P`, `P.self` names the protocol, and only a reflection query that takes a protocol accepts it, such as `T.conforms(P.self)` ([09](09-compile-time.md#what-reflection-can-read)).

**`T == U`, `T != U` and `T.conforms(P.self)` are `const`**, usable in `static if`. A `where` clause states the same as `T == U`, `T != U` and `T: P` ([12](12-grammar.md#files-and-declarations)).

### Conformances

**A type conforms by declaring it, except the conformances the language gives**: the derived marker protocols, such as `Copyable`, `Sendable` and `Frozen`, and the structural `Equatable`, `Comparable` and `Hashable` conformances ([below](#equality-and-ordering)). A **marker protocol** has no requirements, and states a property of a type. Each requirement is met by a **witness**: a method, initializer, operator, subscript, property or stored field, and for an associated type, a type.

```swift
protocol HasHp { var hp: Float { get set } }
struct Crate(var hp: Float): HasHp        // the stored field 'hp' is the witness
struct Rock(let hp: Float): HasHp         // error: a 'let' field witnesses only get and read requirements
```

- **Conformances are declared** in the type's module or the protocol's (the orphan rule), so lookup is local. An implied conformance obeys it too. Take a conformance to `Q` declared in neither the type's module nor that of a protocol `B` that `Q` inherits. It implies one to `B` only where the type's conformance to `B` is already declared in the type's module or `B`'s, or given by the language. Otherwise it is a compile error that asks for that declaration. So every module that sees the type and `B` sees the one conformance between them.
- **A conformance is one fact for the whole program.** An extension declares a conformance only at a file's top level, never inside a function's or a type's body, where one declaration would stand for one conformance per instantiation. A local type declares its own conformances in its header.
- **A type conforms to a protocol through one conformance.** A conformance to a protocol `Q` implies one, with its conditions, to each protocol `Q` inherits, except where a declared conformance to that protocol already holds for every type it covers. Implied conformances of one type to one protocol with the same conditions are one, so `Comparable, Hashable` implies `Equatable` once. Any other two conformances of one type to one protocol, declared or implied, are a compile error whatever their `where` clauses, since generic code could then see one associated type as two types.
- **Derived and restricted marker protocols are never implied.** A conformance to `Q` implies none of the marker protocols the language derives or restricts: `Copyable`, `Sendable`, `Frozen`, `Pod`, `TrivialFree`, `Scoped` and `Synchronized`. Each one `Q` inherits must already hold for every type the conformance covers, derived or declared under that protocol's own rules. Otherwise the conformance is a compile error, as listing `Copyable` for a move-only type is ([01](01-values-and-ownership.md#copies)). So `protocol Dup: Copyable` admits only copyable types, and a type conforming to `AllocatorImpl`, which inherits `Synchronized`, declares `: unsafe Synchronized` itself, unconditionally (next).
- **`~Copyable`, `~Sendable`, `Scoped` and `Synchronized` are declared unconditionally.** Each is declared in the type's own module, in its declaration or in an unconditional extension ([04](04-types.md#initializers)). None is declared in an extension that gives some of the type's generic arguments, such as `extension Cell<Int>`, or that has a `where` clause. Generic code relies on this, since it derives a generic type's copyability, sendability and scope from its fields, its type arguments and these declarations, for every type argument at once ([01](01-values-and-ownership.md#copies), [07](07-concurrency.md#what-may-cross-threads-sendable), [02](02-views-and-dependencies.md#which-types-are-scoped)).
- **A witness is visible where the conformance is declared.** A member, a stored field included, that code there couldn't name witnesses nothing, so a protocol's module can't reach another module's non-public member through a conformance it declares.
- **A stored field witnesses a requirement only where its name could be used the same way**, since generic code reaches a witness with no `unsafe` in sight. So a `let` field witnesses only `get` and `read` requirements.
    - **`unsafe` fields and union members.** An `unsafe` field, or a union member that isn't safe to read ([04](04-types.md#untagged-unions)), witnesses one only in a conformance declared `: unsafe P`. That promises that every value generic code can read or write through the witness is valid.
    - **Bare global `var`s.** A static stored `var` that isn't `@threadlocal` is a bare global `var` ([07](07-concurrency.md#global-state)). It witnesses only a `{ get }` or `{ get set }` requirement of a copyable type, whose every access copies, and only under `: unsafe P`. There, `: unsafe P` promises that no access through it races with another.
    - **Thread-locals.** A `@threadlocal` static `var` witnesses an access-bound requirement, never one `where yield borrows static`, since every access to it is a dynamic access that what it yields can't outlast, by rule 6 ([02](02-views-and-dependencies.md#rule-6-dynamic-accesses)). When its type is copyable, it also witnesses a `{ get }` or `{ get set }` requirement, each access copying under its own dynamic access.
- **An `unsafe` witness, a function, initializer, operator, subscript or accessor, meets only an `unsafe` requirement**, whose callers write `unsafe`, or any requirement in a conformance declared `: unsafe P`, promising that every call generic code can make through it is safe.

**`unsafe protocol P` declares a contract the compiler can't check**, such as "memory is never handed out twice" for `AllocatorImpl` ([06](06-memory-and-allocators.md#writing-an-allocator-allocatorimpl)).

- **Declared conformances to it are promises.** Every declared conformance to it is written `: unsafe P`. A derived one, as `Frozen` is for a type with no interior mutability ([06](06-memory-and-allocators.md#frozen-types-with-no-interior-mutability)), is no promise. `@safe` modules can declare no `: unsafe` conformance ([10](10-errors-and-safety.md#safe-modules) lists every unverified promise).
- **Inheriting an `unsafe` protocol.** A conformance to a protocol `Q` that isn't `unsafe` itself but inherits an `unsafe` one promises only through the conformance it implies. It needs no `unsafe` when every type it covers already conforms to that protocol, by a conformance declared elsewhere whose conditions `Q`'s imply. Nor does it when that protocol is one of the marker protocols the language derives or restricts, which are never implied and so already hold ([above](#conformances)). Otherwise it is written `: unsafe Q`.

### `any P`: explicit dynamic dispatch

**`any P` holds a value of any type conforming to `P`, and calls its requirements through the witness table.** It is for a type known only at run time, as in a list of different widgets:

```swift
func drawAll(_ items: Span<any Drawable>, _ ctx: mutable DrawContext) {
    for d in items { d.draw(&ctx) }                  // dynamic dispatch, visible in the signature
}

var widgets = List<Box<any Widget>>()
widgets.append(Box(Button(label: "Play")))          // allocation, visible in source
for var w in &widgets { w.value.update(dt) }       // mutable any Widget: mutating requirement, dynamic dispatch
```

**`any P` is an existential, and never allocates implicitly.** It comes in these forms:

| Form | What it is | Made from |
| --- | --- | --- |
| `any P` | Shared view: scoped, copyable | A shared borrow of a `T: P`, or a shared projection of an unscoped existential |
| `mutable any P` | Exclusive view: scoped, move-only | An exclusive borrow `&place` of a `T: P`, or a `mutable` projection of an unscoped existential |
| `Box<any P>` | Unscoped existential, on the heap | A `Box` holding an unscoped `T: P` |
| `UniquePointer<any P>`, `WeakPointer<any P>` | Unscoped existentials of objects | An object pointer of the same kind to an unscoped `T: P` |
| `Shared<any P>`, `LocalShared<any P>`, `WeakShared<any P>` | Unscoped existentials of reference-counted values | A reference-counted pointer or weak link of the same kind to an unscoped `T: P` |

**`any P & Sendable`** accepts only `Sendable` types, and is `Sendable` ([07](07-concurrency.md#what-may-cross-threads-sendable)). A `Shared`'s value must be `Frozen` or `Synchronized`, so its existential is `Shared<any P & Frozen>`, or `Shared<any P>` for a `P` that refines `Frozen` or `Synchronized`, as `WakeTarget` refines `Synchronized` ([07](07-concurrency.md#awaitables)).

**`any P` calls only requirements that are neither `mutating` nor `consuming`.** No existential view calls a `consuming` requirement, since none owns the value. An owned `Box<any P>` reaches one by unpacking as an `owned T`, as a static or `init` requirement is called only on an unpacked value's type ([below](#unpacking-an-existential)).

**`mutable any P` is a type of its own.** `&place` makes one wherever one is expected, including assigned into an existing slot, as `d = &crate` in a `for var d` loop over views ([02](02-views-and-dependencies.md#pointing-a-name-at-another-place-rebind)). A `mutating` requirement called through it changes the value it views, so the view must be in a changeable place ([01](01-values-and-ownership.md#changeable-places)), such as a `var` binding, never a shared borrow: `for d in targets { d.takeDamage(1) }` is an error, and `for var d in &targets { … }` works.

So a parameter of type `mutable any P` is received owned unless declared `mutable`, as a `mutating` function type's is ([below](#closure-kinds)), and `func strike(_ d: mutable any Damageable)` can call `mutating` requirements through `d`. A non-`mutating` closure captures it shared, so parallel work can't call `mutating` requirements through it ([07](07-concurrency.md#lending-work-to-other-threads)).

- **At a call**, `&place`, or `&v` for a variable holding one, makes the view the parameter receives ([below](#implicit-conversions)). Stored views keep their places borrowed: after `targets.append(&boss)`, `boss` stays borrowed exclusively, by rule 4 ([02](02-views-and-dependencies.md#rule-4-absorption)).
- **`MutableRef<any P>`**, what a `for var` loop over `&` a `List<any P>` yields, is an exclusive view of a slot holding a shared `any P`. Through it `var d` can reassign the shared view but never reach its value, so `d.takeDamage(1)` is a compile error, since the slot holds a shared view, whose value other views may be reading.
- **`d: mutable (any P)`**, with parentheses, lets a callee reassign which value the caller's shared view refers to ([12](12-grammar.md#parentheses-and-conventions-in-types)).

**`Box<any P>` holds an unscoped value in a heap allocation.** `box.value` projects `any P`, borrowed or `mutable` ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)). Assigning to `box.value`, or through any `mutable any P`, is a compile error, since it could change the value's type and size. Unpacking it as `mutable T` ([below](#unpacking-an-existential)) can replace the value, with one of the same type. `box.downcast(to: T.self)` is an optional projection of the value as a `T`, borrowed or `mutable` as `box.value` is, and `nil` when its dynamic type isn't `T`, so a test that fails moves nothing: `if var s = &box.downcast(to: Slider.self) { s.label = "Go" }`.

**The unscoped existentials are types of their own, which binding a type parameter never makes.** They are `Box<any P>`, and the object pointers, reference-counted pointers and weak links to `any P`. A value of one holds or names only an unscoped value, and comes from one of these:

- the conversion to it ([below](#implicit-conversions));
- for a weak pointer or a weak link, `WeakPointer<any P>(bits:)` or `WeakShared<any P>(bits:)` ([03](03-handles-and-objects.md#weak-pointers-as-bits-and-handing-objects-to-c), [06](06-memory-and-allocators.md#sharedt-data-with-many-owners));
- another unscoped existential of the same protocol, as `u.weak()` makes a `WeakPointer<any P>` from a `UniquePointer<any P>`.

**A box that holds a shared view `any P` itself is a different type**, written `Box<(any P)>`, as `mutable (any P)` is ([12](12-grammar.md#parentheses-and-conventions-in-types)). Generic code gets it from `Box<T>` with `T` bound to `any P`, and it is scoped, since it holds a view ([02](02-views-and-dependencies.md#which-types-are-scoped)).

**Object pointers to `any P`** ([03](03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)) reference heterogeneous objects, as an observer list `List<WeakPointer<any Listener>>` does. Their accesses give what `box.value` does: `any P` for a shared access and `mutable any P` for an exclusive one. `w.downcast(to: T.self)` gives back a `WeakPointer<T>?`. **Reference-counted pointers to `any P`** ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners)) give a shared `any P` through `s.value`, and `w.upgrade()` on a `WeakShared<any P>` gives a `Shared<any P>?`.

**A requirement whose signature mentions `Self` or an associated type can be called only on an unpacked value** ([below](#unpacking-an-existential)), not through `any P`, since two existentials' dynamic types needn't match. A generic requirement, such as `func record<S: Sink>(_ s: mutable S)`, has one witness per `S`, and is callable through `any P` as unpacking works (next): the call reaches the witness of the value's dynamic type, specialized for the call's type arguments.

### Unpacking an existential

```swift
func refill<T: Damageable>(_ t: mutable T) { t.hp = 100 }

func refillAll(_ targets: mutable List<Box<any Damageable>>) {
    for var b in &targets { refill(&b.value) }   // unpacks each box: T is that value's dynamic type
}
```

**Passing an existential to a generic parameter `T: P` unpacks it: `T` is the value's dynamic type for that call.** A shared `any P` unpacks only as a borrowed `T`. A `mutable any P`, or a `mutable` projection of an unscoped existential, also unpacks as `mutable T`, whose whole value the generic code may replace, since the type can't change. An owned `Box<any P>` also unpacks as an `owned T`: its value moves out into the call, and its allocation is freed.

`any P` never conforms to `P`, so it can't bind `T` without unpacking. Two existentials unpack to two types, so `swap(&a.value, &b.value)` is a compile error: the two can't unpack as one `T`, and a box's projection isn't a place of type `any P` that `T` could bind as the view type (below).

- **Where it unpacks.** Only into a parameter whose type is `T` itself, borrowed or `mutable`, or `owned` for an owned `Box<any P>`. Nothing else in the signature may mention `T`: no other parameter, the result, the error type, or a `where` clause beyond `T`'s own constraints. `P` must imply every one of `T`'s constraints, and an unscoped existential's projection or owned value also meets `T: ~Scoped`, since it holds only unscoped values.
- **Where it doesn't.** When `any P` itself meets `T`'s constraints, as it meets those of an unconstrained `T` or of `T: Copyable`, it binds `T` as the view type instead, and a `Box<any P>` that meets them binds `T` as itself. Any other call that would need `T` to be `any P` is a compile error.

**An unpacking call costs one indirect call, and an instance for each possible dynamic type.** An unpacking call site names one generic function, every type argument but `T` fixed. The program holds an instance of it for every type that can be the dynamic type of an existential of `P`:

- each type the program converts to an existential of `P` or of a protocol that implies `P`;
- where the program calls `WeakPointer<any P>(bits:)` or `WeakShared<any P>(bits:)`, the type of each object or `Shared` value the program creates that conforms to `P`.

The call reaches the instance for the value's dynamic type with one indirect call.

## Operators

Operators are `static func`s declared on a type or in an extension of it, named by the operator:

```swift
extension Vec3 {                                                // in std.math
    @inline public static func * (lhs: Vec3, rhs: Float) -> Vec3 { ... }
    @inline public static func * (lhs: Float, rhs: Vec3) -> Vec3 { ... }   // declared on Vec3; found via rhs
    @inline public static func - (v: Vec3) -> Vec3 { ... }                 // one parameter: prefix, as in -v
}

pos += vel * dt                                                 // pos = pos + vel * dt
```

**Lookup is bounded: the candidates for `a ⊕ b` are the operators declared on the types of `a` and `b`, and nothing else.** Those include the defaults of protocols the types conform to, such as `Equatable`'s `!=`, and, for a type parameter, its constraints' requirements.

- **The set is fixed.** The declarable operators are the ones the grammar lists ([12](12-grammar.md#files-and-declarations)), with fixed precedence. The others are built in: `&&` and `||` take `Bool`s and `??` an optional ([04](04-types.md#optionals)), each evaluating its right side only when needed, and `..<` and `...` make a range of a copyable `Comparable` type, borrowing their operands and copying them in, so `0..<count` leaves `count` usable.
- **Typed operands may widen.** When both operands are typed, a candidate applies when each operand is of its parameter's type or widens to it ([04](04-types.md#conversions)). If exactly one candidate needs no widening, it wins; otherwise exactly one must apply, or the expression is ambiguous. So `clock += dt` with `clock: Double` and `dt: Float` adds two `Double`s.
- **The parameter count decides the form.** A function with one parameter declares a prefix operator, and one with two a binary operator. `-` has both forms, `!` and `~` are only prefix, and the rest only binary.
- **Compound assignment is shorthand.** `a ⊕= b` means `a = a ⊕ b`, with the place `a` worked out once ([01](01-values-and-ownership.md#evaluation-order-and-when-a-calls-borrows-begin)), so `hp[next()] -= 1` calls `next()` once. No type declares `+=`, so it always agrees with `+`.

**Untyped operands take their type from the other side.** A literal or an implicit member expression (`2`, `0.5`, `.pi`, `.zero`) has no type until something expects one. An implicit member names a static member, case or initializer of the expected type, and where a `T?` is expected, of `T?` first and then of `T`, as `.init(bitPattern: bits)` does for a `*Void?` parameter. When one operand of `a ⊕ b` is untyped and the other typed:

- The candidates are the operators on the typed operand's type that take it in its position and whose matching parameter the untyped operand fits. `v * 2` with `v: Vec3` keeps only `*(Vec3, Float)`, so `2` is a `Float`. A shift is the exception: its untyped value never takes its type from the count ([04](04-types.md#integer-overflow-division-and-shifts)).
- If several remain, the one whose parameter has the typed operand's own type wins; otherwise the expression is ambiguous.
- When both are untyped, the expression is untyped, typed by its context the same way, or else by the literal defaults: `Double` if either is a floating-point literal, and `Int` if not ([04](04-types.md#literals)).

Operators apply one at a time, so `Float(i) / 1024 * 2 * .pi` types each step from the one before.

**Generic calls work the same way.** A call binds its type parameters from its typed arguments first, then each untyped argument takes its parameter's type. Typed arguments that bind one type parameter to different types bind it to the one the others widen to, as `max(f, d)` does to `Double` for a `Float` and a `Double`, or are an error. So `max(0, hp - amount)` binds `T` to `Float`, and `0` is a `Float`. A type parameter no typed argument binds is bound by matching the expected type against the call's result type, part by part: `let b: Float = max(0, 1)` is a `Float` call, and `let s: Seconds<Game> = seconds(0.5)` binds `C` to `Game`, as `await` does ([07](07-concurrency.md#semantics)). Otherwise it gets the literals' default: `max(0, 1)` alone is an `Int` call.

### Equality and ordering

```swift
struct Tile(let x: Int32, let y: Int32): Hashable      // == and hash(into:) derived from the fields

struct Version(let major: Int, let minor: Int): Comparable {    // == derived; < written
    static func < (lhs: Version, rhs: Version) -> Bool {
        lhs.major < rhs.major || (lhs.major == rhs.major && lhs.minor < rhs.minor)
    }
}
```

**Three protocols declare `==`, `<` and hashing:**

- **`Equatable`** requires `==` and `!=`. A default `!=` is `!(a == b)`.
- **`Comparable: Equatable`** requires `<`, `<=`, `>` and `>=`. The defaults are `a > b` as `b < a`, `a <= b` as `a < b || a == b`, and `a >= b` as `b < a || a == b`, so a type with unordered values, such as `Float` with NaN, gets them right from `<` and `==` alone.
- **`Hashable: Equatable`** requires `func hash(into hasher: mutable Hasher)`, which feeds `hasher`, std's hash state, and must give equal hashes for values that `==` calls equal.

A type may replace any default with its own operator. **A struct or enum that declares `Equatable`, `Comparable` or `Hashable` gets `==` derived** when it doesn't write one and all of its fields or payloads are `Equatable`, **and for `Hashable`, `hash(into:)`** when they are all `Hashable`: field by field in header order, and for an enum, the case, then its payload. So `struct Entry(let key: Int, let h: Handle<Enemy>): Comparable` writes only `<`. `<` is never derived, since no order is right for every type.

**Derived code reads only what a witness could** ([above](#conformances)). A derived `==` or `hash(into:)` reads every stored field plainly, so it is derived over an `unsafe` field, or a union member that isn't safe to read, only when the conformance is declared `: unsafe P`, promising that such a read is valid and races with nothing.

The integers conform to `Comparable` and `Hashable`, and `Bool`, raw pointers and `Handle`s to `Hashable`. `Half`, `Float` and `Double` conform to `Comparable`, with IEEE 754's comparisons: a NaN is unequal to every value, itself included, and unordered. `Simd` vectors don't conform, since their comparisons return masks ([04](04-types.md#simd-and-math)).

- **Enums without payloads.** They are `Hashable` without declaring it, so `e == .missing` works on any of them.
- **Tuples and inline arrays.** A tuple is `Equatable`, `Hashable` or `Comparable` when each element is, comparing element by element in order, and `[N of T]` is the same when `T` is.
- **Optionals.** Every optional compares with `nil`: `x == nil` and `x != nil` test for a value, whatever `T` is. `T?` is `Equatable` or `Hashable` when `T` is.
- **Text.** `StaticString`, `StringView` and `String` are `Comparable` and `Hashable`. They compare their bytes, and order them byte by byte, a prefix before any longer text. `Name` is `Hashable` and compares its 64-bit hash.

## Functions and closures

A **closure** is a value of a closure literal's concrete type ([below](#closures-by-concrete-type-some-f)). Passed for a function-type parameter, it becomes a view of itself, which may borrow locals and never allocates, and the function type says whether it only reads what it captures, writes it, or consumes it:

```swift
func each(_ xs: Span<Enemy>, _ body: (Enemy) -> Void) { for x in xs { body(x) } }
func eachMut(_ xs: Span<Enemy>, _ body: mutating (Enemy) -> Void) { for x in xs { body(x) } }

var dead = 0
each(enemies.span) { e in log("hp \(e.hp)") }                // reads only: a plain function type
eachMut(enemies.span) { e in if e.hp <= 0 { dead += 1 } }    // writes 'dead': a mutating function type
each(enemies.span) { e in if e.hp <= 0 { dead += 1 } }       // error: a mutating closure where a non-mutating one is expected
```

- **Overloads.** Functions may share a name when their argument labels or parameter types differ, and a type's methods and properties also when only their `self` convention does ([04](04-types.md#shared-mutable-and-consuming-forms-of-one-method)). A call keeps the candidates whose parameters its arguments match by label, in order, with parameters that have defaults free to be left out ([01](01-values-and-ownership.md#default-arguments)), then those that its arguments typed without context fit, each of the parameter's type or converting to it implicitly ([Implicit conversions](#implicit-conversions)). An argument that needs context, such as a literal, a closure literal or a `.member`, then takes each remaining candidate's parameter type, and a candidate it doesn't fit drops out. If exactly one candidate needs no conversion, it wins, and so does the one among several such candidates that alone declares no type parameters of its own, so `f(_: Int)` beats `f<T>(_: T)` for an `Int`; otherwise exactly one must remain, or the call is ambiguous. A call `T(x)` with one unlabeled literal argument makes the literal a `T`, as `x as T` does, so `Float(0)` is the `Float` zero.
- **Calls the language makes.** Besides the calls it writes, code calls: a `deinit` that a scope's end, an overwrite or a `consume` runs, an accessor, an operator, a `@converts` or literal initializer, an expression pattern's `==` or a range pattern's `contains`, a parameter's or field's default, the calls that build an interpolated string, a `for` loop's calls to `makeIterator` or `makeMutableIterator` and to the iterator's `next`, and an `await`'s calls to its operand's `poll` ([07](07-concurrency.md#awaitables)). Each is a call whose callee is known statically, and the rules for calls apply to it.
- **Return types.** A function declared without `->` returns `Void`, except a non-public one whose body is a single expression, which returns that expression's type, unless it is `main`, `@c`, `@export`, a `task func` or a protocol witness.
- **Every path returns.** A body that is a single expression returns its value, unless the result type is `Void`, where the value is discarded. Otherwise, in a function, closure, `get` or `task` body whose result type isn't `Void`, every path ends in a `return` with a value, a `throw` or a call that never returns ([04](04-types.md#enums)). A function whose result type is `Never` has no `return`, and no path reaches its end. A `while true` loop that no `break` leaves never completes, so no path continues past it.
- **A closure literal's body is a function body of its own.** `return` and `throw` leave the closure, `break` and `continue` target only loops inside it, and `await` can't appear in it, even in a `task func` ([07](07-concurrency.md#semantics)).
- **A closure captures places, not variables.** It captures as precisely as its body names them: a body that reads `world.players` borrows that field, not `world`. So a closure reading one field can be passed alongside an exclusive borrow of another, and two closures in one call may each write a different field. The captured place is the longest path the body names through the places [01](01-values-and-ownership.md#which-places-overlap) keeps apart: stored fields, reflection projections of a field known where the borrows are checked, and inline array elements at an index known there. A body that names a binding of a place captures the place the binding names, as worked out when it was bound, with the binding's dependency set and the dynamic accesses it holds, which stay held while the closure lives. The path stops before any other accessor, subscript or index, an optional chain, a force unwrap or a payload, and an object's access, which the body evaluates on each call, and before an under-aligned place, capturing the aligned place that holds it ([04](04-types.md#packed-structs-and-under-aligned-places)). A bitfield is captured through its C memory location ([08](08-c-interop.md#structs-unions-and-enums)).
- **A closure's parameter types come from a written parameter clause or the expected type**, never from the body ([12](12-grammar.md#expressions) gives the syntax of trailing closures, `$0` and `{ x in … }`).
- **A declaration inside a body names none of the body's locals, parameters or `self`**, whether it is a nested function, a member, accessor, initializer, `deinit` or field default of a local type, or a member of a local extension. Only closure literals capture.

### Closure kinds

A closure's type says what it does with its captures, and the compiler infers this kind from the literal's body:

| Kind | Function type | The closure's body |
| --- | --- | --- |
| Non-`mutating` | `(Int) -> Void` | Only reads its captures |
| `mutating` | `mutating (Int) -> Void` | Writes a capture |
| `consuming` | `consuming () -> Mesh` | Moves out of a capture |

- **Non-`mutating`.** Its function types accept only closures that only read their captures, shared-borrowed or owned, so a job system may run one on many threads at once ([07](07-concurrency.md#lending-work-to-other-threads)): `xs.forEachInParallel { _ in n += 1 }` is a type error, and a `sort(by:)` comparator can't write the pool it reads.
- **`mutating`.** A literal whose body makes any mutable access to a captured place, assigning it, lending it with `&` in any position [01](01-values-and-ownership.md#lending-a-place-for-change) lists, calling a `mutating` method on it or capturing it exclusively in a nested literal, captures that place **exclusively**. A `mutating` function value is move-only, and calling it mutates the closure itself, so it is passed `mutable` or owned, and runs on one thread at a time.
- **`consuming`.** A literal whose body moves out of a capture, with `consume input` or by taking it anywhere a value is taken ([01](01-values-and-ownership.md#moves)), owns that capture: it moves in when the closure is created, as `[move input]` would. Calling the closure consumes it, so the compiler checks it is called at most once. Copying a capture, as `var y = copy input` does, doesn't make it `consuming`. A literal checked against a `consuming` function type, or a `some F` whose `F` is one, is `consuming` whatever its body does: its concrete type satisfies only `consuming` function types, and it is called at most once.

**A parameter of `mutating` or `consuming` function type, or of `some F` where `F` is one, is received owned** unless declared `mutable` ([01](01-values-and-ownership.md#parameters)). So `func lock<R: ~Scoped>(_ body: consuming (mutable T) -> R) -> R` needs no `owned`, and a function value passed there moves in. A closure passed for a function-type parameter is converted first ([below](#function-typed-values)), so a local holding a `mutating` closure is passed with `&` and stays usable after the call, while one holding a `consuming` closure is passed without `&`, and the conversion consumes it. A local passed for a `some F` parameter whose `F` is `mutating` or `consuming` moves in, unless the parameter is `mutable`.

**The kinds nest.** A non-`mutating` value is accepted where a `mutating` or `consuming` one is expected, and a `mutating` one where a `consuming` one is, for values only, never through `mutable` ([Implicit conversions](#implicit-conversions)), and never adding ownership ([below](#function-typed-values)).

### What a closure may keep: `keep`

A closure can't keep what it is lent for one call, such as the data behind a lock, unless the parameter is declared `keep`:

```swift
m.lock { d in kept = d.items.span }            // error: 'd' is lent only for the call
forEachLine(src.view) { lines.append(copy $0) }   // fine: forEachLine's closure takes a 'keep' parameter
```

**Closure parameters are call-scoped.** Nothing that depends on one may be stored into the closure's captures, by [02](02-views-and-dependencies.md#rule-5-the-callee-side)'s rules for a closure body, and a call absorbs nothing into the captures (rule 4). A closure may still return what depends on a parameter, as `entries.map { $0.name.view }` does. The call's result and `mutable` arguments still depend on what the closure captures, since the closure is the call's `self`.

**`keep` in the function type**, as in `func forEachLine(_ text: StringView, _ body: mutating (keep StringView) -> Void)`, lets the closure store what it derives from that parameter into its captures. It marks a borrowed or `owned` parameter, never a `mutable` one, which is the caller's place, and `keep` on it is a compile error. A call absorbs the `keep` argument's dependency set, with rule 3's kinds, into every place the closure depends on exclusively, so `lines` above ends up depending on `src`, and the calling function must be allowed that store by its own rule 5.

- **A borrowed `keep` parameter lends only what it carries.** Its own storage belongs to the call, as a local's does, so the closure never keeps a view of the parameter itself, its bytes or what it owns, and a call absorbs only the argument's dependency set, never the argument place, which lets the caller pass a local or a temporary. So a closure that keeps views of a list's elements takes `keep Span<T>`, and one that keeps an `any P` view of the parameter, `{ s in named.append(s) }`, is rejected.
- **A `keep owned` parameter gives the closure its value too**, which it may move into its captures with what that value carries, as `{ chunk in parts.append(chunk) }` does with a `keep owned MutableSpan<Float>`, a move-only view no borrowed parameter could give up.
- **`keep` never changes what a callee receives.** It receives what the same parameter without `keep` would ([01](01-values-and-ownership.md#parameters)), also when a conversion adds it.
- **`keep` is part of the type.** A closure type without it is accepted where one with it is expected, not the reverse, since a plain closure's receiver relies on nothing flowing into its captures.

### Unscoped closures: `Closure<F>`

A callback stored in a struct, or a thread's body, outlives the call that made it, so it owns its captures instead of borrowing:

```swift
struct Hotkey(var action: Closure<() -> Void>)

let id = 7
var ping = Hotkey(action: { [copy id] in log("pressed \(id)") })   // 'id' is copied in, and stays usable here
var level = Box(Level())
var load = Hotkey(action: { [move level] in start(level.value) })  // 'level' is moved in: it can't be used after this
var oops = Hotkey(action: { log("pressed \(id)") })                // error: 'id' isn't listed
```

**`Closure<F>`**, such as `Closure<mutating (Int) -> Int>`, is an unscoped, move-only value that owns every capture. It is `Sendable` only when its function type is `@sendable`, such as `Closure<mutating @sendable (Int) -> Int>` ([Function-typed values](#function-typed-values)).

- **Captures are listed.** Each is `[move x]`, or `[copy x]` for a copyable value, which leaves `x` usable, and `self` is listed too, which only a `consuming` method can move. An unlisted capture is a compile error. A capture the body moves out of is already owned ([Closure kinds](#closure-kinds)) and needs no entry. A global is never a capture of any closure: the body reaches it as any function does ([07](07-concurrency.md#global-state)).
- **Size.** 32 bytes, holding up to 24 bytes of captures inline. The captures are laid out as a literal's are ([below](#closures-by-concrete-type-some-f)), and they are inline when that struct's size is at most 24 bytes, its alignment is at most 8, and no capture has a layout the language or a library leaves open, such as a task's state, a `Pin<T>` or a value that holds one ([11](11-compilation-model.md#what-the-language-leaves-open)). Other captures go in an out-of-line context that the closure owns ([06](06-memory-and-allocators.md#the-current-allocator)), the one allocation a conversion makes without its type written at the literal: the capture list shows at the literal what moves in, and so whether it fits. The context comes from the current allocator. In `@noalloc` code, a conversion into a `Closure` that allocates is an error.
- **It counts as holding a `Synchronized` value.** Its inline captures may hold one, unseen in its type, so a borrowed `Closure` is always the caller's place ([01](01-values-and-ownership.md#borrowed-arguments)), and a `@packed` struct can't hold one.
- **An out-of-line context is checked like any owning storage** ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)). Calling a `Closure` whose context outlived its allocator's memory, such as an arena reset since, panics, and destroying it skips its captures' `deinit`s and the free, as for a stale `Box`.
- **Calling.** A stored `Closure<mutating …>` needs `mutable` access to be called, and calling a `Closure<consuming …>` consumes it.

### Closures by concrete type: `some F`

A closure can also be held by its own concrete type, which never allocates:

```swift
func times(_ n: Int, _ body: some mutating () -> Void) { … }   // monomorphized for each literal: never boxed

var hits = 0
var misses = 0
var onHit = { hits += 1 }                           // no annotation: the literal's own concrete type
var onMiss: mutating () -> Void = { misses += 1 }   // annotated: the function type, a view of the literal
```

**Every closure literal has its own anonymous concrete type.** A local initialized with a literal and no type annotation has that type, so it only ever holds that literal; with an annotation it has the function type. It is laid out as a struct of its captures ([04](04-types.md#structs)): the listed ones in list order, then the others, by reference or moved, in order of first use, with a capture by reference as a pointer.

- **A `some F` parameter**, for a function type `F` of any kind, is an anonymous type parameter `B: F`, and takes the literal by its concrete type. The callee is monomorphized for it, and the closure is stored by value, **never boxed or allocated, whatever its size**, like a struct whose fields are its captures. `until { ctx in … }` takes its condition this way, so an awaiting task never allocates ([07](07-concurrency.md#awaitables)).
- **Function-type constraints.** A type satisfies `B: F`, for a function type `F`, when it is a closure's concrete type, a function type or a `Closure<G>`, and its values convert to `F` ([below](#implicit-conversions)), which the kinds decide ([above](#closure-kinds)). Generic code calls a `B` as an `F`, converts it to `F`, and, when `B: ~Scoped`, moves it into a `Closure<F>`.
- **The captures decide whether it is scoped.** A literal's type is scoped when any capture is by reference or of a scoped type, depending on the places it captures by reference and on what its captures carry, such as a `[copy s]` of a `Span`. It is unscoped only when every capture is owned and unscoped ([02](02-views-and-dependencies.md#scoped-values)).
- **The captures and the kind decide whether it is copyable.** It is copyable when every capture is by shared reference, or owned and copyable, and the literal isn't `consuming`, which is called at most once.
- **Where the type must be unscoped**, as for a parameter constrained `F: ~Scoped`, a literal owns and lists its captures, as for a `Closure`. Elsewhere it captures by reference, except what its capture list names or its body moves out of.

### C function pointers

```swift
@c func half(_ x: Int32) -> Int32 { x / 2 }
let f: @c (Int32) -> Int32 = half               // a named @c func converts
let g: @c (Int32) -> Int32 = { x in x + 1 }     // so does a literal that captures nothing and doesn't throw
unsafe { print(f(4)) }                          // calling one is unsafe
```

`@c (Int32) -> Int32` is a C function pointer, with no room for captures, and it never throws, since C can't receive an error. Literals that capture nothing and don't throw convert to it, and so do named `@c func`, `@export`, imported and `extern c` functions and `@c` values whose parameters and result have the same types and conventions, and which need no more stack than the pointer type declares ([08](08-c-interop.md#the-stack-a-c-call-needs)). Calling one is `unsafe`, since the type can't tell a Rayo function from a C one.

**Inside `unsafe`, a function also converts to a `@c` type whose types differ but have the same C representations**, as `@c func onButton(_ b: Button)` does to `@c (Int32) -> Void`, or a `WeakPointer<Body>` parameter to a `UInt64` one. A `mutable T` parameter also meets a `*T` or `*T?` one there, since both cross as `T*`, so `@c func onUpdate(_ s: mutable State)` converts to `@c (*State) -> Void`. That code promises that every call through the pointer passes values valid for the function's own types, a pointer for a `mutable` parameter meeting what [08](08-c-interop.md#what-c-must-uphold) asks of one, and that every value the function returns, or writes through a `mutable` parameter or a pointer, is valid for the pointer type's, as 08 asks of C.

**`@c noalloc (Int32) -> Int32` is a C function pointer whose calls allocate nothing**, so `@noalloc` code may call one ([06](06-memory-and-allocators.md#allocation-failure)). What converts to it allocates nothing: a named `@noalloc` function, an imported or `extern c` function declared `noalloc` ([08](08-c-interop.md#c-calls-in-noalloc-code-noalloc)), a literal whose body passes the `@noalloc` check, or another `@c noalloc` value. Inside `unsafe`, a `@c` value without the mark converts too, as a pointer C handed over does, and that code promises what `noalloc` asserts. The mark converts away, never back outside `unsafe`.

**`unsafe (UInt32) -> Void` is an unsafe function type**, whose calls need `unsafe`. An `unsafe func` declared in Rayo converts only to `unsafe` function types, to `Closure`s of them and, when it is also `@c`, to `@c` types, so no function value hides an `unsafe` call from its caller, and it satisfies a `some F` or a function-type constraint only when `F` is `unsafe`. Any Rayo function value converts to the `unsafe` form of its type, never back.

**C code stays behind `@c` types.** An imported or `extern c` function, though an `unsafe func` too ([08](08-c-interop.md#what-imports-as-what)), converts only to `@c` types, which carry its stack need ([08](08-c-interop.md#the-stack-a-c-call-needs)), and a `@c` value converts only to another `@c` type, or its optional, as above: never to a Rayo function type, a `Closure` or an `unsafe` form, whose calls wouldn't check that need. A literal that calls C inside an `unsafe` block is an ordinary Rayo function: `let now: () -> Double = { unsafe { platform_time_seconds() } }`.

### Function-typed values

A function-typed value views its closure's storage, so it can't outlive that storage:

```swift
let put: (mutable List<StringView>) -> Void = { o in o.append(src.view) }    // the literal lives as long as 'put'
func pick() -> (Int, Int) -> Int { max }                                   // fine: a named function views no storage
func mk() -> () -> Int { let x = 5; return { [copy x] in copy x } }        // error: the result would view mk's temporary
```

**A value of function type is a view of a closure**: of the closure's storage, where all its captures, owned ones included, live. Converting a closure, any value of a closure's concrete type (a literal, a local, parameter or field of a literal's anonymous type, or a `some F` parameter), to a function type makes such a view, which depends on the storage and on what the closure carries ([02](02-views-and-dependencies.md#closure-calls)). A non-`mutating` function value is a copyable shared view; a `mutating` or `consuming` one is move-only.

- **A non-`consuming` closure is borrowed as its kind needs**: a non-`mutating` one shared, whatever the function type, and a `mutating` one exclusively, so the place holding it is lent with `&` ([01](01-values-and-ownership.md#lending-a-place-for-change)), as in `run(&grow)`, and is usable again after the view's last use.
- **A `consuming` closure is handed over.** The conversion consumes the source place ([01](01-values-and-ownership.md#moving-values-out)), and the value takes over the captures but not their memory, so it still can't outlive that memory. Calling it moves out of the captures and destroys the rest; dropping it uncalled destroys them all.
- **Converting a function value never adds ownership.** A value accepted where a stronger kind is expected views the same storage the same way: called through a `consuming` type, a borrowed closure runs with the access it was lent, and dropping the value destroys nothing.
- **Named functions and operators are function values too.** A named function other than `ptr(to:)` ([10](10-errors-and-safety.md#unsafe-code)), a static method or an operator, such as `max` or the `+` in `combine: +`, converts to `Closure<F>` and to any function type its signature matches, of any kind, and, if it doesn't throw, throwing an error type that leaves the same arguments places (below), with parameter conventions lining up as a witness's do ([01](01-values-and-ownership.md#parameters)). It views no storage and depends on nothing, which is why `pick` compiles. An overloaded name is resolved by the expected type. A closure literal that captures nothing converts the same way, since its storage holds nothing, so `func sorted(by less: (Int, Int) -> Bool = { a, b in a < b })` and `return { x in x + 1 }` compile.
- **`@sendable` function types**, such as `@sendable (mutable Particle) -> Void`, hold only closures whose captures, by reference or owned, all have `Sendable` types, and their values are `Sendable` ([07](07-concurrency.md#what-may-cross-threads-sendable)). A named function always converts to one. A `@sendable` value converts to the same type without the mark, never the reverse, and `Closure<F>` and `some F` carry the mark the same way.
- **`@noalloc` function types**, such as `@noalloc (mutable MutableSpan<Float>) -> Void`, hold only functions whose calls can't allocate: a `@noalloc` named function, or a literal whose body passes the `@noalloc` check ([06](06-memory-and-allocators.md#allocation-failure)). Where a call may destroy the literal's captures, the check covers that destruction too: for a `consuming` literal, and for any literal moved into a `Closure` or passed owned for a `some F`, since a call through a `consuming` type destroys what it doesn't move out. A call through one counts as a `@noalloc` call. The mark converts away as `@sendable` does, never the reverse, and `Closure<F>` and `some F` carry it the same way.

**Where the storage lives.** A literal in a local's initializer, or on the right side of an assignment to a local or a path of stored fields from one, anywhere in it outside nested closure bodies (directly, as a call argument at any depth such as to a primary initializer, as an element of a tuple or array literal, or as an `if` or `when` arm's value), is kept in a **hidden local** of the local's scope when the local depends on its storage after the statement (rules 3 and 4 in [02](02-views-and-dependencies.md#dependencies)). Each such literal gets its own, holding a value only if the literal was made, and destroyed right after the local it was made for, so the value holding the view is gone first, and what the literal captured, such as a guard on an earlier local's mutex, is released before that local is destroyed. So `put` above, and `let h = Handler(onClick: { … })`, stay usable for their whole scope. A literal assigned on every pass of a loop reuses its hidden local, so a still-live copy of the previous value conflicts with the assignment.

Any other literal, such as a `return` operand or an argument in another kind of statement, is an owning temporary that lives to the end of its full statement ([02](02-views-and-dependencies.md#temporaries)). So `mk` fails, and so does appending a literal to a `List<() -> Int>` used after the statement.

## Implicit conversions

```swift
owned var target: Handle<Enemy>? = h            // T to T?, taking h
let seen: any Drawable = sprite                 // a shared borrow of 'sprite' to an existential view
var w: Box<any Widget> = Box(Slider(…))         // Box<Slider> to Box<any Widget>: no new allocation
let pickMax: (Int, Int) -> Int = max            // a named function to a function type
```

Numbers widen along their fixed order ([Conversions](04-types.md#conversions)). **Otherwise there are six kinds of implicit conversion, each decided by the expected type alone.** All are free except moving a closure into a `Closure`, which may allocate, and an error's `@converts` initializer, which runs:

- **`T` → `T?`**: where a `U?` is expected, a value that converts to `U` below converts and is then wrapped, in the same local step, as a named `@c func` passed for a nullable C callback is. It takes the value ([01](01-values-and-ownership.md#conversions)).
- **A shared borrow of a `T` that meets every protocol of the composition → `any P`**, and an exclusive borrow `&x` → `mutable any P` ([`any P`](#any-p-explicit-dynamic-dispatch)); `&v` of a changeable place holding a `mutable any P` makes a new view of the same value (below), and a shared borrow of such a place gives a shared `any P` view of the same value while the place stays borrowed shared. An existential of `P` also converts to one of `Q` when `P` implies `Q`, as `any Widget` does to `any Drawable` for `protocol Widget: Drawable`, or `any P & Sendable` to `any P`: a view stays a view, and an unscoped existential keeps its allocation. From a place, a shared view makes a new view of the same value while the place stays borrowed shared, a `mutable any P` is taken, or with `&v` lends a new view, and an unscoped existential is taken.
- **`Box<T>` → `Box<any P>`**, and likewise for each object pointer, reference-counted pointer and weak link, such as `WeakPointer<T>` → `WeakPointer<any P>` and `Shared<T>` → `Shared<any P>`, where `T` meets every protocol of the composition, as `T: Sendable` does for `any P & Sendable`, and `T: ~Scoped`. It takes the value, moving it out of a place as an `owned` binding would ([01](01-values-and-ownership.md#moves)). `~Scoped` makes the erasure sound: the existential forgets `T` and any dependency `T` carries, so `T` must carry none ([02](02-views-and-dependencies.md#generic-code-and-scoped)).
- **Closures to function types** ([Function-typed values](#function-typed-values)):
    - a closure, named function or operator to a function type;
    - a `Closure<F>` place to the function type `F`, or to any function type a value of type `F` converts to (below), borrowed as `F`'s kind needs, as a closure is ([above](#function-typed-values)). Converting a `Closure<consuming …>` consumes it but keeps its out-of-line context until the place is next assigned or its scope ends, whichever comes first, and then frees it without destroying the captures, which the function value took;
    - a literal that captures nothing and doesn't throw, a named `@c func`, `@export`, imported or `extern c` function, or a `@c` value, to a `@c` function pointer with the same types, or inside `unsafe` the same C representations, and the same conventions, that declares at least its stack need ([C function pointers](#c-function-pointers));
    - a Rayo function value to a stronger kind (non-`mutating` to `mutating` or `consuming`, `mutating` to `consuming`), a non-throwing one to the same type throwing an error type that leaves the same borrowed arguments always the caller's place ([01](01-values-and-ownership.md#borrowed-arguments)), as any unscoped one does, to a type whose parameters add `keep`, to the type without `@sendable` or `@noalloc`, or to its `unsafe` form, with every parameter convention unchanged ([01](01-values-and-ownership.md#parameters)), within the limits [C function pointers](#c-function-pointers) sets for `unsafe` and C functions.
- **Closures to `Closure<F>`** ([Unscoped closures](#unscoped-closures-closuref)): a closure literal, an owned value of a closure's concrete type, or a named function or operator moves into a `Closure`, allocating when its captures exceed the inline size. A `Closure<F>` converts to a `Closure<G>` when a function value of type `F` converts to `G` (above), keeping its context.
- **Errors** ([10](10-errors-and-safety.md#error-unions)): a value of an error union's member, or of a union whose members it all has, to that union, taking the value as `T` → `T?` does; and under `try` or `throw`, an error to the enclosing function's error type through a `@converts` initializer ([10](10-errors-and-safety.md#propagating-errors-with-try)).

**`x as T` expects a `T`, as an annotation does**, so `x` takes one of these conversions or a numeric widening ([Conversions](04-types.md#conversions)), or, for a literal, becomes a `T` ([04](04-types.md#literals)). It never tests a type at run time. Anything else is explicit, such as `box.downcast(to: T.self)` ([`any P`](#any-p-explicit-dynamic-dispatch)).

**No conversion applies through `mutable`.** An `&` argument has exactly its parameter's type: no widening, no `T → T?`, no closure-kind or `keep` subsumption. Otherwise the callee could store, say, a `mutating` closure into a variable the caller still sees as a non-`mutating` one that a job system may call on many threads. The exceptions make new views rather than converting a variable, each lending its place until the view's last use: `&x` → `mutable any P`; `&v` for a changeable place `v` holding a `mutable any P`, a new view of the same value; `&f` → the function value of a `mutating` closure or `Closure<mutating …>` `f`; and `&f` for a changeable place `f` holding a `mutating` function value, a new view of the same closure. So a function that takes a `mutating` callback can pass it on twice, as `eachMut(a, &body); eachMut(b, &body)`.
