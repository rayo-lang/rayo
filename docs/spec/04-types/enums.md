# Enums

[04 · Types](../04-types.md)

**An enum is one of several cases, each of which may carry a payload.** Enums are Rayo's tagged unions, and a `when` takes them apart ([below](#matching-with-when-and-choosing-with-if)):

```swift
enum Blend: UInt8 { case opaque, alpha, additive }          // plain enum with a raw type

enum Shape {
    case circle(radius: Float)
    case rect(size: Vec2)
    case polygon(points: [8 of Vec2], count: UInt8)
}

func area(_ s: Shape) -> Float {
    return when s {
        .circle(let r)         { .pi * r * r }
        .rect(let size)        { size.x * size.y }
        .polygon(let p, let n) { polygonArea(p[..<Int(n)]) }
    }
}
```

**An enum's declaration also fixes how other modules match it, how its cases are numbered and stored, and how it is built:**

- **Nonexhaustive enums.** A `public` enum marked `@nonexhaustive` makes every `when` over it in another module end in `else`.
- **Raw values.** A raw type, as `UInt8` is for `Blend`, is an integer type, and only an enum without payloads declares one. A case may give its raw value with `= value`, a `const` expression. One that doesn't takes the previous case's plus one, the first `0`. Every raw value, given or taken, must fit the raw type, or the declaration is a compile error. Two cases with one raw value are a compile error. So `E(rawValue:)` returns the one case whose raw value it is given, or `nil`.
- **Layout.** An enum without payloads is stored as its raw value when it declares a raw type. One without a raw type is stored as a tag numbering its cases from 0, in the smallest unsigned integer type that fits: `UInt8` for up to 256 cases, none or one included. A payload enum is that tag plus a union, except that an optional may keep its tag in a niche of its payload ([below](#optionals)).
- **No cases.** An enum with no cases, such as the prelude's `Never`, has no values, and size 0. So a function whose result type is `Never`, such as `fatalError`, never returns, and it is what the rules below mean by a call that never returns.
- **Initializers.** An enum's `init` builds its value by assigning `self` a whole value, such as a case, under the same rule as a struct's `self.init` ([Initializers](structs.md#initializers)). It assigns at most once on every path, and exactly once on every path that returns the new value, as `LoadError`'s `@converts` initializers do ([10](../10-errors-and-safety/typed-errors.md#typed-throws)). Before that assignment, `self` doesn't exist.

## Matching with `when`, and choosing with `if`

```swift
let label = when state {
    .idle { "idle" }
    .chase(let t) where t.isBoss { "fleeing" }
    .chase { "chasing" }
    .stunned, .frozen {
        playFx(.stars)
        "stuck"                                // a block's value is its last expression
    }
}

let sign = when {                              // no subject: the first arm whose condition holds
    x < 0 { -1 }
    x > 0 { 1 }
    else { 0 }
}

let bonus = if boosted { 10 } else { 0 }
if case .chase(let t) = state { track(t) }     // one pattern as a condition
```

**`when` runs the first arm that matches.** With a subject, each arm lists one or more patterns ([12](../12-grammar/constructs.md#patterns)) and an optional `where` guard, which may use what the patterns bind. Without a subject, each arm tests one `Bool` condition. An `else` arm matches whatever is left. Every arm's body is a block, as an `if` branch is.

**A pattern says which values its arm matches, and what it binds:**

- **Expression patterns.** A pattern that is an expression, such as `maxHp` or `"jump"`, matches when `pattern == subject` is true. It is a compile error unless that `==` takes both operands borrowed, returns `Bool` and doesn't throw. A range, such as `0..<10`, `..<5`, `...5` or `start...`, matches when it contains the subject. A bare identifier compares with an existing value unless it is under `let` or `var`, where it binds a new name ([12](../12-grammar/constructs.md#patterns)).
- **Type patterns.** `is E` matches, and `let e as E` matches and binds, a subject of type `E`, such as the error of a `do` block that throws only `E`, or a member `E` of an error-union subject ([10](../10-errors-and-safety/typed-errors.md#error-unions)). No other subject has type patterns.

  When `E` is itself an error union, as a type parameter may turn out to be, `let e as E` matches a value of any of its members, binds it converted to `E`, and covers each. That conversion makes a new value ([01](../01-values-and-ownership/bindings.md#conversions)):
    - from a value subject, such as `when consume e` or a `catch`, it takes what the subject held;
    - from a place subject it copies it. So there every member it may match is `Copyable`, and generic code whose `E` is a type parameter declares `E: Copyable`.
- **Exhaustive.** A `when` with a subject covers every value of its subject's type, or ends in `else`. An arm with a `where` guard covers nothing. An expression pattern covers its values only when it is a literal of a number type or `Bool`, or a range between such literals, compared by the language's own `==` or `contains`, never a user-defined one. A `when` without a subject ends in `else` when its value is used.
- **One set of names per arm.** Patterns that share an arm bind the same names, with the same types, and each name the same way: it looks, changes in place, or owns ([01](../01-values-and-ownership/bindings.md#conditions-and-patterns)). No arm falls through into the next.

**The subject holds still while arms are tested.** A `when` borrows its subject from when it is evaluated until an arm is chosen: shared, or exclusively when it is marked `&`. It holds a dynamic place's access as any borrow does ([02](../02-views-and-dependencies/dependency-rules/absorption-and-accesses.md#rule-6-dynamic-accesses)). Patterns and guards run under that borrow, so a guard sees the value its arm then binds. A guard can't change or consume the subject, every part is a shared view inside a guard, and an `owned` part takes its value only once its arm is chosen ([01](../01-values-and-ownership/bindings.md#conditions-and-patterns)).

**Conditions and declarations use patterns too:**

- **One pattern as a condition.** `if case` tests one pattern as a `when` arm does, and binds its names for its block, as in the last line above. `guard case` and `while case` work the same way.
- **A `guard` leaves when its conditions fail.** Every path through its `else` block ends in `return`, `throw`, `break`, `continue` or a call that never returns, so what its conditions bind is bound on every path after it.
- **Patterns that always match.** A `let` or `var` declaration, a `for` loop, and a `let` or `var` condition (whose pattern matches the optional's value) take only `_`, a name, or a tuple of these, under the binding kinds the position allows ([12](../12-grammar/constructs.md#statements)).

**A `when` and an `if` are expressions, whose value is that of the arm that runs:**

- **Arms and blocks have values.** An arm's value is its block's last expression, as an `unsafe` block's is. An arm that ends in an assignment has the value `Void`. An arm that ends in `return`, `throw`, `break`, `continue` or a call that never returns, such as `fatalError`, has no value and fits any type.
- **`if` / `else` is an expression too.** Its branches are blocks with values, and an `if` used for its value has an `else`.
- **Types.** Where the position expects a type, every arm's value takes it, as a `return` would ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)). Where it expects none, as in a `let` with no annotation, the arms have one type: an arm whose value is an untyped literal, `nil` or an implicit member such as `.idle` takes the typed arms' type. When every arm's value there is a literal, they take one default together, as an array literal's elements do ([Literals](collections.md#literals)). Used as a statement, `when` and `if` expect no value: each arm's value is discarded, and the arms' types needn't agree.
- **Ownership.** The arm that runs takes the expression's position: whatever the position does with a value, such as borrowing, moving or returning it, it does with the arm's ([01](../01-values-and-ownership/bindings.md#if-and-when-as-values)).

## Optionals

```swift
var target: Handle<Enemy>? = nil     // 8 bytes, the same as Handle<Enemy>
if target != nil { attack(target) }  // a Handle<Enemy> inside the check
let hp = borrow enemies[h]?.hp ?? 0  // looks at the element's hp in place, or at a 0
```

**`T?` is `Optional<T>`, an enum whose cases are `.some(T)` and `.none`, written `nil`.** A `nil` pattern is `.none` and covers it. The two spellings differ only as a projection's declared type: there `T?` makes an optional projection, which yields a place of type `T` or `nil`, and `Optional<T>` makes one that yields a whole place of the enum ([02](../02-views-and-dependencies/projections-and-accessors.md#projections-read-and-modify-accessors)).

**`T?` offers these operations:**

- narrowing a place by checking it against `nil` ([below](#narrowing));
- binding what an optional holds to a new name, with `if let` and `guard let` ([01](../01-values-and-ownership/bindings.md#conditions-and-patterns));
- a default, with `x ?? d` (below);
- chaining, with `a?.b?.c`;
- forcing, with `x!`;
- a comparison with `nil`, `x == nil`, for any `T` ([05](../05-protocols-generics-and-closures/operators.md#equality-and-ordering)).

**An optional chain can be assigned through.** `a?.b = v` writes only when `a` holds a value, and `x? = v` replaces `x`'s value only when it holds one ([01](../01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin)).

**`a ?? b` chooses as an `if` does.** It evaluates `b` only when `a` is `nil`, and hands its position to `a`'s payload or to `b`, as an `if` hands it to the arm that runs ([01](../01-values-and-ownership/bindings.md#if-and-when-as-values)). The payload of a place is a place, and the payload of a value is a value. When `b` is a `T?` too, the position goes to `a` or `b` whole, and the result is a `T?`.

**An optional stores `nil` in a niche, a bit pattern `T` never uses, when `T` has one, and then costs no extra bytes.** These types have one:

- raw pointers, `@c` function pointers, `Box`es, object owners and reference-counted pointers, whose `nil` is null;
- weak pointers, weak links and `Handle`s, whose `nil` is zero. `Handle` is a std type the language names ([11](../11-compilation-model.md#the-prelude)), and its generation is never 0 ([03](../03-handles-and-objects.md#pools-and-handles));
- an enum with a spare tag value, whose `nil` is the lowest value of its stored type that no case uses: any Rayo enum that has one, `@nonexhaustive` or not, and an imported C enum the header declares closed ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums));
- a struct or tuple, through its first stored field or element that has a niche, whose `nil` is that field's. An imported bitfield never supplies one ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)).

**These have no niche:**

- an optional itself;
- an open imported C enum, which may hold any value of its underlying type ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums));
- `Bool`, so C reading a Rayo `Bool`'s byte as a `bool` always finds 0 or 1.

**No niche lies inside a `Synchronized` value**, at any depth ([07](../07-concurrency/synchronization.md#the-synchronized-contract)). Other threads write its bytes, as a `Mutex<Handle<T>>`'s `Handle` is written under the lock, while reading a tag is a plain load. So `Mutex<Handle<T>>?` and `Atomic<WeakShared<T>>?` keep their tag outside, in the form below.

**Without a niche, `T?` is laid out as a struct of `T` followed by a `Bool` saying whether it holds a value**, so an exported C header can declare it as that struct ([08](../08-c-interop/calling-rayo-from-c.md#c-representations)).

### Narrowing

```swift
if e.target != nil {
    chase(e.target)                // 'e.target' is a Handle<Player> here
    e.target = nil
    chase(e.target)                // error: 'e.target' may be nil after the assignment above
}
guard e.target != nil else { return }
chase(e.target)                    // a Handle<Player> to the end of the scope
```

**Checking that an optional place isn't `nil` narrows it to its payload's type, for as long as nothing can make it `nil`.** So code uses the payload where it checked it, with no new name. The compiler follows every path, as it does to know whether a place holds a value ([01](../01-values-and-ownership/moving-values-out.md#places-that-hold-no-value)).

**A place is narrowed wherever every path to that point passed a check, with no ending event (below) since.** The check is `x != nil` or `nil != x`, and a place is narrowed:

- inside an `if` or `while` whose condition is the check, and in each condition after it, joined by `&&` or `,`;
- after a `guard` whose condition is the check;
- in an arm of a `when` with no subject, when the arm's condition is the check;
- in the right operand of `||` after `x == nil`, in the `else` of `if x == nil`, and after an `if x == nil` whose body always leaves the scope.

**A place narrows only when the code making the check sees every change to it**: a local, a parameter, or a stored field of one, at any depth. A borrowing binding is a local, so the place it names narrows whatever it borrows ([01](../01-values-and-ownership/bindings.md#bindings)). These don't narrow:

- an element, and a subscript's or a computed property's result, since each use runs the accessor again;
- a global, and a place reached through an object, a weak pointer or a thread-local, since other code reaches them ([01](../01-values-and-ownership/bindings.md#how-long-a-borrow-lasts)).

`if let` binds what such a place holds to a new name instead ([01](../01-values-and-ownership/bindings.md#conditions-and-patterns)).

**The narrowed place is its payload, as a place.** Reading it reads the payload in place, and `&` lends the payload, which can't become `nil`, to a `mutable T`.

**Where a `T?` is expected, or a member that `Optional` declares is named, the narrowed place is the whole optional.** So passing it to a `T?` parameter borrows the optional, with no conversion, and `x.take()` is `Optional`'s `take()`.

**The narrowing ends wherever the place could become `nil`**, and the place is a `T?` again until the next check. These are the ending events:

- an assignment to a place that overlaps it ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap));
- lending it as a `mutable T?`, or lending a place that overlaps it for change, except its payload lent as a `mutable T`;
- moving out of it, or out of a place that contains it;
- a closure capturing it, or a place that overlaps it, exclusively ([05](../05-protocols-generics-and-closures/functions-and-closures.md#capturing-places));
- a `rebind` of the local it is reached through ([02](../02-views-and-dependencies/dependency-lifetimes.md#pointing-a-name-at-another-place-rebind));
- an `await`, for a place reached through a task's resume parameter, which the owner lends anew at each step ([07](../07-concurrency/tasks.md#semantics)).

**Moving out of a narrowed place moves the whole payload**, and leaves the place holding no value, as any move does ([01](../01-values-and-ownership/moving-values-out.md#places-that-hold-no-value)). So the place can't be used until it is assigned again. A part of the payload moves out only through a pattern, as for any enum's payload ([01](../01-values-and-ownership/moving-values-out.md#what-can-be-moved-from)).

## Untagged unions

**An untagged union stores several types in the same bytes, with nothing recording which is there:**

```swift
union Bits { var f: Float; var u: UInt32 }          // Pod and padding-free
union Mixed { var byte: UInt8; var word: UInt32 }   // 'byte' covers one byte of four: not padding-free

var b = Bits(f: 1.5)       // a union is initialized by writing one member
b.u = 7                    // writing a member is safe
let x = copy b.f           // reads the bits of 7 as a Float: safe, since Bits is Pod and padding-free
var m = Mixed(word: 0)
unsafe { use(m.byte) }     // reading a member of Mixed needs unsafe
```

- **Layout.** Every member is at offset 0, and the union is sized to its largest member, rounded up to its largest alignment, as a C union is. `@c union` adds the `@c` field checks, and imported C unions arrive in this form ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)).
- **Members.** They are copyable, so a union never has to know which one to destroy. They are all one place for exclusivity, since writing one can change another ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)).
- **Initializers.** A union is built from one member, as in `Bits(f: 1.5)`, and its own `init` builds its value as an enum's does ([above](#enums)).
- **Access.** Writing a whole new value into a member that isn't `unsafe` is safe: initializing the union with it, or assigning it. An `unsafe` member, like an `unsafe` field, is given a value only inside `unsafe` ([Initializers](structs.md#initializers)). Every other access reads, since it starts from the bytes already there: a borrow, `&`, a `mutating` call, `b.u += 1` or a reflective `modify`.
- **Reading.** Reading is safe when every member's type is `Pod`, no member is `unsafe`, and the union is padding-free ([Plain data: `Pod` and bit casts](data-layout.md#plain-data-pod-and-bit-casts)), since whatever a write left is then a valid value of the member read. Otherwise it needs `unsafe`. Unlike the union's own `Pod` conformance, this doesn't ask its members to be as visible as it: a read names a member it can see, and any bytes are a valid value of that member's type.
