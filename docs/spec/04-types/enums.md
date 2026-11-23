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

func area(_ s: &Shape) -> Float {
    return when &s {
        .circle(r)         { .pi * r * r }
        .rect(size)        { size.x * size.y }
        .polygon(p, n)     { polygonArea(p[..<UInt(n)]) }     // lends a '&[Vec2]' of the first n points
    }
}
```

**An enum's declaration also fixes how other modules match it, how its cases are numbered and stored, and how it is built:**

- **Nonexhaustive enums.** A `public` enum marked `@nonexhaustive` makes every `when` over it in another module end in `else`.
- **Raw values.** A raw type, as `UInt8` is for `Blend`, is an integer type, and only an enum without payloads declares one. A case may give its raw value with `= value`, a `const` expression. One that doesn't takes the previous case's plus one, the first `0`. Every raw value, given or taken, must fit the raw type, or the declaration is a compile error. Two cases with one raw value are a compile error. So `E(rawValue:)` returns the one case whose raw value it is given, or `nil`.
- **Layout.** An enum without payloads is stored as its raw value when it declares a raw type. One without a raw type is stored as a tag numbering its cases from 0, in the smallest unsigned integer type that fits: `UInt8` for up to 256 cases, none or one included. A payload enum is that tag plus a union, except that an optional may keep its tag in a niche of its payload ([below](#optionals)). A `T!Never` stores no tag at all, since its `.failure` holds a `Never` and so has no values ([10](../10-errors-and-safety/typed-errors.md#what-a-failure-type-names)). It is laid out as `T`, and keeps `T`'s niches, so `(Handle<Enemy>!Never)?` costs what `Handle<Enemy>?` does.
- **No cases.** An enum with no cases, such as the prelude's `Never`, has no values, and size 0. So a function whose result type is `Never`, such as `fatalError`, never returns, and it is what the rules below mean by a call that never returns.
- **Initializers.** An enum's `init` builds its value by assigning `self` a whole value, such as a case, under the same rule as a struct's `self.init` ([Initializers](structs.md#initializers)). It assigns at most once on every path, and exactly once on every path that returns the new value, as `LoadError`'s `@converts` initializers do ([10](../10-errors-and-safety/typed-errors.md#typed-errors)). Before that assignment, `self` doesn't exist.

## Matching with `when`, and choosing with `if`

```swift
let label = when &state {
    .idle { "idle" }
    .chase(t) where t.isBoss { "fleeing" }
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
if state == .idle { wander() }                 // a case without a payload, tested in a condition
```

**`when` runs the first arm that matches.** With a subject, each arm lists one or more patterns ([12](../12-grammar/constructs.md#patterns)) and an optional `where` guard, which may use what the patterns bind. Without a subject, each arm tests one `Bool` condition. An `else` arm matches whatever is left. Every arm's body is a block, as an `if` branch is.

**A pattern says which values its arm matches, and what it binds.** At its top level it compares the subject with a value, matches a case, or matches a type. Names bind only inside a case's payload, and in a type pattern:

- **Expression patterns.** A pattern that is an expression, such as `maxHp` or `"jump"`, matches when `pattern == subject` is true. It is a compile error unless that `==` takes both operands borrowed and returns `Bool`, which can't fail. A range, such as `0..<10`, `..<5`, `...5` or `start...`, matches when it contains the subject. A bare identifier at the top level is an expression pattern, which compares with the constant or variable it names, except as the name of a type pattern (below) ([12](../12-grammar/constructs.md#patterns)).
- **Case patterns.** `.name` matches the case `name`, whatever its payload holds, and `.name(…)` matches its payload part by part too. Inside the parentheses, a bare name binds its part, `_` matches it without binding it, and a nested case pattern matches it further. A literal or `nil` is the only comparison a payload holds, as in `.damage(0)`, and any other goes in the arm's `where`. An optional is matched with `nil` and `.some(t)`.
- **Type patterns.** `is E` matches, and `e as E` matches and binds, a subject or a payload part of type `E`, such as the error of a `do` block that fails only with `E`, or a member `E` of an error union ([10](../10-errors-and-safety/typed-errors.md#error-unions)). Nothing else has type patterns.

  When `E` is itself an error union, as a type parameter may turn out to be, `e as E` matches a value of any of its members, binds it converted to `E`, and covers each. That conversion makes a new value ([01](../01-values-and-ownership/bindings.md#conversions)):
    - from a value subject, such as `when consume e` or a `catch`, it takes what the subject held;
    - from a reference subject, such as `when &e`, it copies it. So there every member it may match is `Copyable`, and generic code whose `E` is a type parameter declares `E: Copyable`.
- **Exhaustive.** A `when` with a subject covers every value of its subject's type, or ends in `else`. An arm with a `where` guard covers nothing. An expression pattern covers its values only when it is a literal of a number type or `Bool`, or a range between such literals, compared by the language's own `==` or `contains`, never a user-defined one. A literal in a payload covers its value the same way. A `when` without a subject ends in `else` when its value is used.
- **One set of names per arm.** Patterns that share an arm bind the same names, with the same types. The subject says what each name is, a `ref let` or a `ref var` of its part, or an owner, so every pattern of the arm binds it the same way ([01](../01-values-and-ownership/bindings.md#for-and-when-names)). No arm falls through into the next.

```swift
let label = when &hit {
    .miss { "miss" }
    .damage(0) { "graze" }                           // a literal inside a payload compares
    .damage(d) where d >= lethal { "fatal" }         // any other comparison goes in 'where'
    .damage(lethal) { "fatal" }                      // error: 'lethal' is already declared, and a name in a payload binds
    .damage { "wounded" }
}
```

**A `when`'s subject writes its mark, as a loop's does**: `when &e`, `when mutable &e`, `when consume e`, or a value, such as a call's result ([01](../01-values-and-ownership/bindings.md#for-and-when-names)).

**The subject holds still while arms are tested.** A `when` borrows its subject from when it is evaluated until an arm is chosen: shared, or exclusively when it is marked `mutable &`. It holds a dynamic place's access as any borrow does ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-6-dynamic-accesses)). Patterns and guards run under that borrow, so a guard sees the value its arm then binds. A guard can't change or consume the subject, every part is a shared view inside a guard, and a part of a consumed subject, or of any value subject, takes its value only once its arm is chosen ([01](../01-values-and-ownership/bindings.md#for-and-when-names)).

**Declarations, conditions and `for` loops take patterns that always match: they bind names, and test nothing of their own** ([01](../01-values-and-ownership/bindings.md#conditions-and-patterns)).

**A `guard` leaves when its conditions fail.** Every path through its `else` block ends in `return`, `throw`, `break`, `continue` or a call that never returns, so what its conditions bind is bound on every path after it.

**A `when` and an `if` are expressions, whose value is that of the arm that runs:**

- **Arms and blocks have values.** An arm's value is its block's last expression, as an `unsafe` block's is. An arm that ends in an assignment or in `_ = x` has the value `Void`. An arm that ends in `return`, `throw`, `break`, `continue` or a call that never returns, such as `fatalError`, has no value and fits any type.
- **`if` / `else` is an expression too.** Its branches are blocks with values, and an `if` used for its value has an `else`.
- **Types.** Where the position expects a type, every arm's value takes it, as a `return` would ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)). Where it expects none, as in a `let` with no annotation, the arms have one type: an arm whose value is an untyped literal, `nil` or an implicit member such as `.idle` takes the typed arms' type. When every arm's value there is a literal, they take one default together, as an array literal's elements do ([Literals](collections.md#literals)). Used as a statement, `when` and `if` expect no value, and the arms' types needn't agree. Each arm's value then goes unused, so it is a `Void` or a `Never`, or the arm drops it with `_ =` ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unused-values)).
- **Ownership.** The arm that runs takes the expression's position: whatever the position does with a value, such as borrowing, moving or returning it, it does with the arm's ([01](../01-values-and-ownership/bindings.md#if-and-when-as-values)).

## Optionals

```swift
var target: Handle<Enemy>? = nil     // 8 bytes, the same as Handle<Enemy>
if target != nil { attack(target) }  // a Handle<Enemy> inside the check
let hp = enemies[h]?.hp ?? 0         // the element's hp, copied, or 0 when 'h' names no enemy
```

**`T?` is `Optional<T>`, an enum whose cases are `.some(T)` and `.none`, written `nil`.** A `nil` pattern is `.none` and covers it. The two spellings differ only as a place property's declared type. There `T?` makes an optional place property, which hands out a place of type `T` or `nil`, and `Optional<T>` makes one that hands out a whole place of the enum ([02](../02-views-and-dependencies/place-and-value-properties.md#optional-places-and-tuples-of-places)). The prelude declares `T?` implicitly copyable where `T` is, so a `Handle<Enemy>?` copies with no `copy` written ([01](../01-values-and-ownership/moves-copies-destruction.md#implicitly-copyable-types)).

**`T?` offers these operations:**

- narrowing a place by checking it against `nil` ([below](#narrowing));
- binding what an optional holds to a new name, with an optional binding such as `if let` or `guard ref let` ([01](../01-values-and-ownership/bindings.md#conditions));
- a default, with `x ?? d` (below);
- chaining, with `a?.b?.c`;
- forcing, with `x!`;
- a comparison with `nil`, `x == nil`, for any `T` ([05](../05-protocols-generics-and-closures/operators.md#equality-and-ordering)).

**An optional chain can be assigned through when it ends in a member or an element.** `a?.b = v` and `a?[i] = v` write only when `a` holds a value, and evaluate `v` before they read `a` ([01](../01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin)). A chain with nothing after the `?` is a compile error that points to an optional binding. The binding evaluates the right side only when the optional holds a value, so nothing is destroyed when nothing is written:

```swift
x? = consume spare                                 // error: write 'if ref var t = mutable &x { t = consume spare }'
if ref var t = mutable &x { t = consume spare }    // moves 'spare' in only when 'x' holds a value
```

**`a ?? b` chooses as an `if` does.** It evaluates `b` only when `a` is `nil`, and hands its position to `a`'s payload or to `b`, as an `if` hands it to the arm that runs ([01](../01-values-and-ownership/bindings.md#if-and-when-as-values)). So each operand writes the mark that position needs. When `b` is a `T?` too, the position goes to `a` or `b` whole, and the result is a `T?`.

**Where `a` is a reference to an optional, a `&T?` or a `mutable &T?`, its payload is a reference of the same kind to the value inside.** So `??` gives a reference to `a`'s payload or `b`'s, as a `ref` binding unwraps such a reference in a condition ([01](../01-values-and-ownership/bindings.md#conditions)):

```swift
ref let shown = &nickname ?? &player.name    // names the String inside 'nickname', or the player's name
let label = nickname ?? player.name          // error: write 'copy', 'consume' or '&' before 'nickname'
```

**An optional stores `nil` in a niche, a bit pattern `T` never uses, when `T` has one, and then costs no extra bytes.** These types have one:

- raw pointers, `@c` function pointers, `Box`es, object owners and reference-counted pointers, whose `nil` is null;
- weak pointers, weak links and `Handle`s, whose `nil` is zero. `Handle` is a std type the language names ([11](../11-compilation-model.md#the-prelude)), and its generation is never 0 ([03](../03-handles-and-objects.md#pools-and-handles));
- an enum with a spare tag value, whose `nil` is the lowest value of its stored type that no case uses: any Rayo enum that has one, `@nonexhaustive` or not, and an imported C enum the header declares closed ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums));
- a struct or tuple, through its first stored field or element that has a niche, whose `nil` is that field's. An imported bitfield never supplies one ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums));
- a `T!Never` whose `T` has one, whose `nil` is `T`'s, since it stores no tag of its own (above).

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

An optional binding, such as `if ref let`, binds what such a place holds to a new name instead ([01](../01-values-and-ownership/bindings.md#conditions)). A place that narrows can be unwrapped either way, and each way fits different code ([01](../01-values-and-ownership/bindings.md#unwrapping-an-optional)).

**The narrowed place is its payload, as a place.** Reading it reads the payload in place, and `mutable &x` lends the payload, which can't become `nil`, as a `mutable &T`.

**Where a `T?` is expected, or a member that `Optional` declares is named, the narrowed place is the whole optional.** So `x` given to a `&T?` parameter lends the whole optional as it is, and `x.take()` is `Optional`'s `take()`.

**The narrowing ends wherever the place could become `nil`**, and the place is a `T?` again until the next check. These are the ending events:

- an assignment to a place that overlaps it ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap));
- lending it as a `mutable &T?`, or lending a place that overlaps it for change, except its payload lent as a `mutable &T`;
- moving out of it, or out of a place that contains it;
- a closure capturing it, or a place that overlaps it, exclusively ([05](../05-protocols-generics-and-closures/functions-and-closures.md#capturing-places));
- an assignment of a reference to the `var` it is reached through ([02](../02-views-and-dependencies/dependency-lifetimes.md#assigning-a-reference-to-a-var));
- an `await`, for a place reached through a task's resume parameter, which the owner lends anew at each step ([07](../07-concurrency/tasks.md#semantics)).

**Moving out of a narrowed place moves the whole payload**, and leaves the place holding no value, as any move does ([01](../01-values-and-ownership/moving-values-out.md#places-that-hold-no-value)). So the place can't be used until it is assigned again. A part of the payload moves out only through a pattern, as for any enum's payload ([01](../01-values-and-ownership/moving-values-out.md#what-can-be-moved-from)).

## Untagged unions

**An untagged union stores several types in the same bytes, with nothing recording which is there:**

```swift
union Bits { var f: Float; var u: UInt32 }          // Pod and padding-free
union Mixed { var byte: UInt8; var word: UInt32 }   // 'byte' covers one byte of four: not padding-free

var b = Bits(f: 1.5)       // a union is initialized by writing one member
b.u = 7                    // writing a member is safe
let x = b.f                // reads the bits of 7 as a Float: safe, since Bits is Pod and padding-free
var m = Mixed(word: 0)
unsafe { use(m.byte) }     // reading a member of Mixed needs unsafe
```

- **Layout.** Every member is at offset 0, and the union is sized to its largest member, rounded up to its largest alignment, as a C union is. A packed union counts each member's alignment as 1, or at most `N`, as a packed struct does ([Layout attributes](structs.md#layout-attributes)). `@c union` adds the `@c` field checks, and imported C unions arrive in this form ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)).
- **Members.** They are copyable, since a union doesn't record which member it holds, and so couldn't tell which one to destroy. They are all one place for exclusivity, since writing one can change another ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)).
- **Initializers.** A union is built from one member, as in `Bits(f: 1.5)`, and its own `init` builds its value as an enum's does ([above](#enums)).
- **Access.** Writing a whole new value into a member that isn't `unsafe` is safe: initializing the union with it, or assigning it. An `unsafe` member, like an `unsafe` field, is given a value only inside `unsafe` ([Initializers](structs.md#initializers)). Every other access reads, since it starts from the bytes already there: a reference made with `&` or `mutable &`, a `mutating` call, `b.u += 1` or a reflective change through `value[field]`.
- **Reading.** Reading is safe when every member's type is `Pod`, no member is `unsafe`, and the union is padding-free ([Plain data: `Pod` and bit casts](data-layout.md#plain-data-pod-and-bit-casts)), since whatever a write left is then a valid value of the member read. Otherwise it needs `unsafe`. Unlike the union's own `Pod` conformance, this doesn't ask its members to be as visible as it: a read names a member it can see, and any bytes are a valid value of that member's type.
