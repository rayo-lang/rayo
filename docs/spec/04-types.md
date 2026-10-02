# 04 · Types

```swift
struct Particle(var pos: Vec3, var vel: Vec3, var life: Float)     // laid out in declaration order

let dt: Float = 0.016                             // a literal takes its type from context; with none, 0.016 is a Double
let n: Int32 = 1000
let total: Int = n                                // lossless widening is implicit
let scale = Float(total) / 1024                   // a conversion that may round is spelled out

var particles = SoA<Particle>(capacity: 100_000)  // one buffer per field, still used with field syntax
for var p in &particles {
    p.pos += p.vel * dt                           // vector math: no hidden calls
}

var widgets = List<Box<any Widget>>()             // dynamic dispatch and its heap allocation, both in the type
log("scale \(scale)")                             // formatted straight into the log: no allocation
```

## Numbers

**Integers are fixed-width and two's complement, and floating-point numbers are IEEE 754 binary floats.**

```swift
let hp = 100               // Int
let elapsed = 0.0          // Double: nothing gives the literal another type
let step: Float = 0.5      // Float, from the annotation
let dir: Vec3 = [0, 0, 1]
let move = dir * 0.25      // 0.25 is a Float, from the other operand
let bad = dir * elapsed    // error: 'elapsed' is a Double, and a Double never narrows implicitly
let small: UInt8 = 200
let wide: Int = small      // widening: every UInt8 fits in an Int
```

| Type | Size | Notes |
| --- | --- | --- |
| `Int`, `UInt` | 64-bit | `Int` is the default integer type |
| `Int8` … `Int64`, `UInt8` … `UInt64` | as named | |
| `Float` | 32-bit | |
| `Double` | 64-bit | The default floating-point type |
| `Half` | 16-bit | |
| `Bool` | 1 byte | |

**A number literal takes its type from its context**: `1_000`, `0xFF`, `0o17`, `0b1010`, `1e-3` ([below](#literals)).

### Conversions

```swift
let a: Int16 = 300
let b: Int32 = a                 // Int16 to Int32 loses nothing, so it is implicit
let c: Float = a                 // every Int16 is exact in a Float
let d: Int = b                   // Int32 widens to Int
let e = Int32(truncating: d)     // may drop bits: explicit
let f = Float(d)                 // may round: explicit
let g: Int64 = d                 // error: Int and Int64 never convert implicitly
```

**The only implicit numeric conversion is lossless widening along a fixed order**, so it never makes the type checker search:

- `Int8 → Int16 → Int32 → Int64`, and `UInt8 → UInt16 → …`;
- unsigned to a strictly wider signed type;
- `Half → Float → Double`;
- `Int8`, `Int16`, `UInt8` and `UInt16` to `Float`, and `Int32` and `UInt32` to `Double`.

**`Int` and `UInt` are distinct 64-bit types that sit where `Int64` and `UInt64` do**: `Int32` widens to `Int`, and `UInt32` to `UInt` and `Int`. `Int` and `Int64` never convert implicitly into each other, since neither is wider.

**Every other conversion between number types is explicit, and the explicit forms are defined for every input but one:**

- **Between integer types.** The unlabeled `Int32(x)` checks that the value fits: it panics where overflow checks are on, and keeps the low bits where they are off. `truncating:` always keeps the low bits, and `clamping:` saturates.
- **From a floating-point value.** `Int(f)` rounds toward zero and panics on NaN or on a value whose integer part doesn't fit, in every build, since targets' conversion instructions disagree on those. `Int(clamping: f)` saturates, and maps NaN to `0`.
- **To a floating-point type.** `Float(d)` of an `Int`, `Float(x)` of a `Double` and `Half(f)` of a `Float` round to nearest, and an out-of-range value becomes an infinity of its sign, as IEEE 754 defines.

That one is a float-to-integer conversion of NaN or an out-of-range value inside an `unchecked` block, which removes its check ([10](10-errors-and-safety.md#check-levels)).

### Integer overflow, division and shifts

```swift
func step(_ x: Int32, _ n: Int32) {
    let a = x + 1       // panics on overflow where overflow checks are on (10), wraps where they are off
    let b = x &+ 1      // always wraps
    let c = x +| 1      // saturates at Int32.max
    let d = x << n      // defined for every n: 0 once n reaches 32, a right shift for a negative n
    let e = x / n       // panics when n is 0, in every build
}
```

**Every integer operation has a defined result, in every build and on every target**, except a division or remainder by zero inside an `unchecked` block, which removes its check ([10](10-errors-and-safety.md#check-levels)).

- **Overflow.** `+ - *` and unary `-` panic on overflow where overflow checks are on, and wrap where they are off ([10](10-errors-and-safety.md#check-levels)). `&+ &- &*` always wrap, and `+| -| *|` saturate.
- **Division.** `/` rounds toward zero, and `a % b` has `a`'s sign. Division and remainder by zero panic in every build. `Int.min / -1`, in every signed width, follows the overflow rule, wrapping to `Int.min` where checks are off, and `Int.min % -1` is `0` in every build.
- **Shifts.** The count may be of any integer type, and the result has the shifted value's type, so neither operand widens to the other: `b << n` for a `UInt8` `b` and an `Int` `n` is a `UInt8`.
    - An untyped shifted value never takes its type from the count. It takes the expected type, else its default, `Int`. So `let mask: UInt64 = 1 << bit` shifts a `UInt64` for a `UInt8` `bit`, not a `UInt8` that then widens.
    - `>>` is arithmetic on a signed type and logical on an unsigned one.
    - A negative count shifts the other way: `x << -n` is `x >> n`.
    - A count whose magnitude is at least the bit width, `Int.min` included, shifts every bit out. That gives `0`, or all ones for a right shift of a negative value.
    - A left shift drops bits past the top whatever the sign, so it never overflows.
    - `&<<` and `&>>` use only the count's low bits, `count & (bitWidth - 1)`, as an unsigned amount.

### Floating point

```swift
let p = a * b + c       // rounds twice, after * and after +: never fused into one multiply-add
let q = (a + b) + c     // never reassociated into a + (b + c), which can round differently
```

**Every `Half`, `Float` and `Double` operation, and every floating-point `Simd` lane operation, is one IEEE 754 operation rounded to its own type, in every build.** Nothing is kept in wider precision, contracted, reassociated or otherwise rewritten, and subnormals are never flushed. So `+ - * /`, square root, comparisons and conversions are bit-identical on every target, toolchain and build. Left open are which NaN a NaN result is, and functions IEEE 754 doesn't require to be correctly rounded, such as `sin`.

**C or `unsafe` code that changes its thread's floating-point environment, such as to flush subnormals or trap on an invalid operation, makes every floating-point result on that thread the platform's until the environment is restored.**

## SIMD and math

**The language builds in `Simd<T, N>`, the vectors that map to the target's vector hardware, and `std.math` builds the rest in ordinary Rayo:**

```swift
let v: Vec3 = [1, 2, 3]
let w = v * 2 + Vec3(repeating: 1)        // element-wise, with the scalar broadcast to every lane
let n = cross(v, w).normalized            // std.math

var a: Vec4 = [1, 5, 3, 7]
a.xz = v.xy                               // swizzles: read any lanes, assign lanes that don't repeat
let lo = select(a < Vec4(repeating: 4), a, Vec4.zero)   // a comparison gives a Simd<Bool, 4> mask
```

- **`Simd<T, N>` is builtin, over a number type `T`, or `Bool` for masks, with 2, 3, 4, 8 or 16 lanes.** It is stored with no padding and aligned to its size, except the 3-lane form ([below](#vec3-and-three-lane-vectors)). Generic code may name `Simd<T, N>` for its own `T` and `N`. Its `T` and lane count are then checked where they are known, at each instantiation, as a `static error` is ([09](09-compile-time.md#static-if-and-conditional-compilation)), and the lane operations need a concrete `T`. `std.math`'s `Vec2`, `Vec4` and `IVec2` are aliases of `Simd<Float, 2>`, `Simd<Float, 4>` and `Simd<Int32, 2>`.
- **Operators are element-wise.** Comparisons return `Simd<Bool, N>` masks for `select(mask, a, b)`, and a scalar broadcasts: `v * 2`, `2 * v`. A mask's `any` and `all` reduce it to a `Bool`: `if (a < b).all { … }`. Integer lanes follow the integer rules ([above](#integer-overflow-division-and-shifts)) lane by lane, so `v / w` panics when any lane of `w` is 0.
- **Swizzles are properties naming lanes among the first four**, `x`, `y`, `z` and `w`, as `v.zyx` and `v.xxxx` do. They are assignable when no lane repeats: `v.xz = p`. A swizzle of one lane is a `T`, and of 2 to 4 lanes a `Simd<T, k>`. Naming a lane the vector doesn't have, such as `w` of a 3-lane vector, is a compile error.
- **A lane is read and assigned by swizzle or by index, but never viewed.** `v[i]` panics when `i` is out of range. No span or `Borrow` of a lane exists, so a vector lends nothing of its own bytes ([02](02-views-and-dependencies.md#shallow-values)).
- **Literals and initializers**: `[1, 2, 3, 4]`, `Vec4.zero`, `Vec4(repeating: 1)`, and `Simd<T, N>(a, b, …)`, which takes its `N` lanes in order, unlabeled and borrowed, and copies them: `Vec2(x, y)`, `IVec2(1280, 720)`.

**`Simd` operations never become calls at run time, in any build**, since they are builtin. A library type gets the same by declaring its operations `@inline` ([11](11-compilation-model.md#functions-that-are-never-calls-inline)), as `std.math`'s `Vec3` does.

### `Vec3` and three-lane vectors

**Three-lane vectors come in two layouts:**

```swift
struct Light(var pos: Vec3, var radius: Float)              // 16 bytes: three floats, then one
struct Light4(var pos: Simd<Float, 3>, var radius: Float)    // 32 bytes: the vector alone takes 16, aligned to 16
```

**`Simd<T, 3>` has `Simd<T, 4>`'s size and alignment, and its fourth slot is padding.** `Simd<T, 3>` is `Pod` when `T` is, but never padding-free ([below](#plain-data-pod-and-bit-casts)).

**`Vec3` is `std.math`'s struct of three floats**, 12 bytes with no padding, written in ordinary Rayo:

```swift
public struct Vec3(public var x: Float, public var y: Float, public var z: Float): ExpressibleByArrayLiteral {
    @inline public init(_ x: Float, _ y: Float, _ z: Float) { self.init(x: copy x, y: copy y, z: copy z) }

    @inline @noalloc public init<let N: Int>(arrayLiteral e: owned [N of Float]) {   // @noalloc: literals work anywhere
        static if N == 3 { self.init(x: copy e[0], y: copy e[1], z: copy e[2]) }
        else { static error("a Vec3 literal needs 3 elements") }
    }

    @inline public static func + (lhs: Vec3, rhs: Vec3) -> Vec3 { Vec3(lhs.x + rhs.x, lhs.y + rhs.y, lhs.z + rhs.z) }
    ...
}
```

It offers `Simd<Float, 3>`'s operations, so the two differ only in layout. Its fields are `public`, so it is `Pod` ([below](#plain-data-pod-and-bit-casts)).

## Structs

**A struct's stored fields are listed once, in its header**, which is also its **primary initializer**. The body holds everything else:

```swift
struct Camera(
    var position: Vec3,
    var yaw: Float = 0,
    var pitch: Float = 0,
    let fov: Float,                                  // immutable after init
) {
    var forward: Vec3 {                              // computed property
        Vec3(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
    }

    mutating func look(dx: Float, dy: Float) {
        yaw += dx
        pitch = clamp(pitch + dy, -1.5, 1.5)
    }
}

var cam = Camera(position: .zero, fov: 70)           // the primary initializer; defaulted fields may be left out
cam.look(dx: 0.1, dy: 0)
```

**The body never declares a stored field.** It declares computed properties, methods, subscripts, secondary initializers, a `deinit`, static members, nested types and type aliases. A struct with no stored fields may leave the header out, and its primary initializer is then `init()`.

**Layout is the header's order, always:**

- Each field goes at the first multiple of its alignment at or after the end of the field before it, the first at offset 0.
- A struct is aligned to its most-aligned field, and its size is the end of its last field rounded up to the struct's alignment. A struct with no fields has size 0 and alignment 1.
- A number, `Bool` or raw pointer is aligned to its size, and every other type's alignment follows from its own layout.

Every Rayo target's C ABI lays out structs by these rules too ([11](11-compilation-model.md#what-a-target-must-provide)), so a struct whose fields all have C representations is shared with C as it is ([08](08-c-interop.md#c-representations)).

**Attributes adjust and check the layout:**

```swift
struct Header(var tag: UInt8, var size: UInt32)          // 8 bytes: 3 bytes of padding after 'tag'
@packed struct Rec(var id: UInt32, var tag: UInt8)       // 5 bytes, alignment 1
@align(16) struct Slot(var value: Float)                 // 16 bytes, 16-byte aligned
```

- **`@packed`, on a struct or a union, counts every field's alignment as 1**, so the alignment is 1 and there is no padding between or after fields: a struct's sit end to end. Padding inside a field's own type stays. `@packed(N)` caps each field's alignment at `N`, a power of two. C's packed records import as these ([08](08-c-interop.md#what-imports-as-what)).
- **`@align(N)` raises the alignment to at least `N`**, a power of two, and the size rounds up to it. It, `@packed` and `@packed(N)` apply only to a struct or union declaration, and are a compile error elsewhere.
- **`@c` changes no layout**, and rejects fields with no C representation ([08](08-c-interop.md#c-representations)).

**A value never contains itself.** A struct, tuple, enum or union that would hold a value of its own type inline, through its fields, payloads, optionals or inline arrays at any depth, is a compile error. So is a task whose state would ([07](07-concurrency.md#semantics)). Recursion goes through an owner, so the allocation is visible: `case node(Box<Tree>)`.

### Initializers

```swift
struct Spawner(
    var target: Handle<Enemy>?,     // a var of optional type: starts as nil, so it is defaulted
    let owner: Handle<Player>?,     // a let of optional type: no default
    var cooldown: Float = 2,
)
let s = Spawner(owner: nil)         // 'target' and 'cooldown' may be left out
```

**Every value of a struct is built by its primary initializer**, except one that a `Pod` type takes from bytes ([below](#plain-data-pod-and-bit-casts)) and an imported C struct's zero-initialized one ([08](08-c-interop.md#structs-unions-and-enums)). Its parameters are the fields, in order and labeled by name.

- **Defaults.** A field's default makes its argument optional. A field with a default may leave its type to the default, as `var players = Pool<Player>()` does.
- **Optional `var`s.** A `var` declared with an optional type, `T?` written as such, with no default and not `unsafe`, starts as `nil`. It counts as defaulted, for the primary initializer and for reflection's `hasDefault` ([09](09-compile-time.md#what-reflection-can-read)). A `let` of optional type does neither.
- **`unsafe` fields.** An `unsafe` field, such as `Span`'s `baseAddress`, is given its argument only inside `unsafe`, just as naming it needs `unsafe`.

**A type can also offer other initializers:**

```swift
public struct Fraction private init(let num: Int, let den: Int) {   // other modules can't call the primary
    public init(_ num: Int, over den: Int) {
        precondition(den != 0, "zero denominator")
        self.init(num: copy num, den: copy den)
    }
}

public struct Body private init(let mass: Float, let invMass: Float, var velocity: Vec3 = .zero) {
    public init(mass: Float) throws(PhysicsError) {
        guard mass > 0 else { throw .badMass }          // 'self' doesn't exist yet: only the arguments are checked
        self.init(mass: copy mass, invMass: 1 / mass)   // every field is set at once
    }
}
```

**Every other `init` is secondary, and delegates.** It computes and checks what the primary initializer needs, then calls `self.init(…)`: at most once on every path, and exactly once on every path that returns the new value. A call that a path could reach twice, as one in a loop could, is a compile error. That call reaches the primary initializer directly or through other secondary ones, and secondary initializers that call each other without reaching it are a compile error.

- **The header lists fields, not parameters.** Each entry is a `var` or `let` and takes no parameter convention. The value owns its fields, so the primary initializer takes every one `owned`, and `Inventory(items: loot)` moves `loot` in unless the call says `copy loot` or `loot.clone()` ([01](01-values-and-ownership.md#parameters)). A secondary initializer is an ordinary function whose parameters are borrowed unless marked, so it passes `copy x`, or an `owned` parameter, on to the primary one, as `Fraction` does above.
- **Before `self.init`, `self` doesn't exist.** Nothing reads or assigns a field until then, and after it `self` is a whole value, as in a `mutating` method.
- **No value is ever half-built.** The primary initializer sets every field at once, from arguments already evaluated. An `init` that throws or returns `nil` before `self.init` has only its locals to destroy, and one that throws or returns `nil` after it destroys a whole value, running its `deinit` if the type has one.
- **The header sets the primary initializer's access.** It is as visible as the struct unless the header says `private init(…)`, which keeps it inside the module ([11](11-compilation-model.md#modules-and-names)). Other modules then build a value only through a secondary initializer, which can check an invariant such as `Fraction`'s nonzero denominator. A field that isn't `public` is a parameter only inside the module, so elsewhere the primary initializer can be called only if every such field has a default, or through `T.construct` on a `@reflect(private)` type ([09](09-compile-time.md#constructing-values-reflectively)). `unsafe init(…)` makes every call to it `unsafe`, for fields that `unsafe` code trusts, such as an index it doesn't bounds-check.
- **Extensions may add secondary initializers.** They add no stored member or enum case.
- **A `deinit` is declared in the type's own module.** It goes in its body, where a `static if` or `static for` may generate it, or in an **unconditional extension**, one that gives none of the type's generic arguments and has no `where` clause. An extension that gives some, such as `extension Tagged<Int>`, is conditional, as a `where` clause is. A `deinit` makes the type move-only and, unless the type conforms to `PlainDeinit`, makes destroying a value of it a use of what that value borrows ([02](02-views-and-dependencies.md#when-destroying-a-value-counts-as-using-it)). Either effect changes how every use is checked, so every `deinit` is declared unconditionally, as `~Copyable` is ([05](05-protocols-generics-and-closures.md#conformances)).

### Packed structs and under-aligned places

**A `@packed` struct or union can put a field at a misaligned address**, where a load or store of the field's type is invalid ([10](10-errors-and-safety.md#unsafe-code)) and faults on some targets. So the compiler tracks which places may be misaligned, and code uses those only by value:

```swift
@packed struct NetRec(var tag: UInt8, var ids: [4 of UInt32])     // 'ids' starts at offset 1

func sum(_ r: NetRec) -> UInt32 {
    var total: UInt32 = 0
    for i in r.ids { total += i }         // error: binds elements of an under-aligned field in place
    for i in copy r.ids { total += i }    // fine: iterates an aligned copy
    return total
}
```

**These places have a guaranteed alignment:**

- a variable's, or an element's of separately allocated storage, such as a `List`, a pool or a span, is its type's alignment;
- a field's is the smaller of its enclosing place's guarantee and the largest power of two dividing its offset. A tuple's element is a field ([below](#tuples-ranges-and-arrays)), and an element of `[N of T]` or a `Simd` counts as one at offset `index × stride`, using the stride for a dynamic index.

**A place guaranteed less than its type's alignment, at any depth, is under-aligned, and is used only by value.** So `recs[1].id` in a `List` of the 5-byte `Rec` above is under-aligned: `id` is at offset 0, but `recs[1]` itself is guaranteed only 1.

- **No views.** Any borrow of it but an argument is a compile error: a binding or pattern part bound in place, a `when` subject, a span, an `any P`, a `yield` in an accessor, or a `for` loop binding its elements in place. A closure captures the aligned place that holds it instead ([05](05-protocols-generics-and-closures.md#functions-and-closures)).
- **Arguments go through an aligned temporary.** It is copied in, and back for a `mutable` one, a receiver included. A projection reached through such a receiver, or whose `where yield` clause names such an argument, is access-bound, as a bitfield's is ([02](02-views-and-dependencies.md#access-bound-projections)): the temporary is written back when the access ends. A call is a compile error if the argument place would enter the dependency set of its scoped result or thrown error ([02](02-views-and-dependencies.md#rule-3-call-results)), or be absorbed into another argument ([02](02-views-and-dependencies.md#rule-4-absorption)).

**Generic code takes the safe bound.** It is checked once, at its definition ([05](05-protocols-generics-and-closures.md#protocols-and-generics)). A path that crosses no `@packed` struct or union stays aligned, since ordinary layout keeps every field aligned for its type. Below a `@packed` or `@packed(N)` struct or union, generic code computes the enclosing guarantee and each offset only from the parts that don't depend on a type parameter: at least 1, and 1 after any field of parameter-dependent size. A field whose type depends on a parameter is taken to require the largest alignment any type can have. So `m.payload` in a generic function over `@packed(4) struct Msg<T: Copyable>` is under-aligned, and so is `e.rec.id` over `struct Env<T>(var rec: Rec, var body: T)`, which `Env<UInt8>` misaligns.

**Requirement projections stay aligned.** Generic code treats what a requirement yields as aligned, since an under-aligned field, such as `ids` witnessing a `read`/`modify` requirement of `@packed struct NetRec(…): HasIds`, witnesses it only through an aligned temporary ([02](02-views-and-dependencies.md#projections-in-protocols)), and no `yield` names an under-aligned place (above).

**A `@packed` struct can't hold a `Synchronized` value inline**, through its fields, elements and payloads at any depth ([07](07-concurrency.md#atomics-and-locks)). A `Closure` counts as holding one ([05](05-protocols-generics-and-closures.md#unscoped-closures-closuref)). Atomics need their alignment, and shared access to a `Synchronized` value is always in place. What a field owns out of line, such as a `List`'s elements, is aligned and doesn't count.

So the type of a field that depends on a type parameter must be provably free of `Synchronized` values and `Closure`s at the definition, by being one of these:

- `Copyable`, since anything holding either is move-only, as in `@packed struct Msg<T: Copyable>`;
- `Frozen` ([06](06-memory-and-allocators.md#frozen-types-with-no-interior-mutability)), as with `where T.Payload: Frozen`.

A field whose type generates its fields from its parameters ([09](09-compile-time.md#generating-declarations)) is proven free of both only through a `where` clause stating that type `Copyable` or `Frozen`.

## Enums

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
        .circle(let r)         -> .pi * r * r
        .rect(let size)        -> size.x * size.y
        .polygon(let p, let n) -> polygonArea(p[..<Int(n)])
    }
}
```

- **Nonexhaustive enums.** `@nonexhaustive public enum` makes every `when` over it in another module end in `else`.
- **Raw values.** A raw type, as `UInt8` is for `Blend`, is an integer type, and only an enum without payloads declares one. A case may give its raw value with `= value`, a `const` expression, and one that doesn't takes the previous case's plus one, the first `0`. Every raw value, given or taken, must fit the raw type, or the declaration is a compile error. Two cases with one raw value are a compile error. `E(rawValue:)` returns the case whose raw value it is given, or `nil`.
- **Layout.** An enum without payloads is stored as its raw value when it declares a raw type. One without a raw type is stored as a tag numbering its cases from 0, in the smallest unsigned integer type that fits: `UInt8` for up to 256 cases, none or one included. A payload enum is that tag plus a union, except that an optional may keep its tag in a niche of its payload ([below](#optionals)).
- **No cases.** An enum with no cases, such as the prelude's `Never`, has no values, and size 0. So a function whose result type is `Never`, such as `fatalError`, never returns, and it is what the rules below mean by a call that never returns.
- **Initializers.** An enum's `init` builds its value by assigning `self` a whole value, such as a case, under the same rule as a struct's `self.init` ([above](#initializers)). It assigns at most once on every path, and exactly once on every path that returns the new value, as `LoadError`'s `@converts` initializers do ([10](10-errors-and-safety.md#typed-throws)). Before that assignment, `self` doesn't exist.

### Matching with `when`, and choosing with `if`

```swift
let label = when state {
    .idle -> "idle"
    .chase(let t) where t.isBoss -> "fleeing"
    .chase -> "chasing"
    .stunned, .frozen -> {
        playFx(.stars)
        "stuck"                                // a block's value is its last expression
    }
}

let sign = when {                              // no subject: the first arm whose condition holds
    x < 0 -> -1
    x > 0 -> 1
    else -> 0
}

let bonus = if boosted { 10 } else { 0 }
```

**`when` runs the first arm that matches.** With a subject, each arm lists one or more patterns ([12](12-grammar.md#patterns)) and an optional `where` guard, which may use what the patterns bind. Without a subject, each arm is one `Bool` condition. An `else` arm matches whatever is left.

- **Expression patterns.** A pattern that is an expression, such as `maxHp` or `"jump"`, matches when `pattern == subject` is true, and is a compile error unless that `==` takes both operands borrowed, returns `Bool` and doesn't throw. A range, such as `0..<10`, `..<5`, `...5` or `start...`, matches when it contains the subject. A bare identifier compares with an existing value unless it is under `let` or `var`, where it binds a new name ([12](12-grammar.md#patterns)).
- **Type patterns.** `is E` matches, and `let e as E` matches and binds, a subject of type `E`, such as the error of a `do` block that throws only `E`, or a member `E` of an error-union subject ([10](10-errors-and-safety.md#error-unions)). No other subject has type patterns.

  When `E` is itself an error union, as a type parameter may turn out to be, `let e as E` matches a value of any of its members, binds it converted to `E`, and covers each. That conversion makes a new value ([01](01-values-and-ownership.md#conversions)):
    - from a value subject, such as `when consume e` or a `catch`, it takes what the subject held;
    - from a place subject it copies it. So there every member it may match is `Copyable`, and generic code whose `E` is a type parameter declares `E: Copyable`.
- **Exhaustive.** A `when` with a subject covers every value of its subject's type, or ends in `else`. An arm with a `where` guard covers nothing. An expression pattern covers its values only when it is a literal of a number type or `Bool`, or a range between such literals, compared by the language's own `==` or `contains`, never a user-defined one. A `when` without a subject ends in `else` when its value is used.
- **One set of names per arm.** Patterns that share an arm bind the same names, with the same types, and each name the same way: it looks, changes in place, or owns ([01](01-values-and-ownership.md#conditions-and-patterns)). No arm falls through into the next.
- **The subject holds still while arms are tested.** A `when` borrows its subject from when it is evaluated until an arm is chosen, shared, or exclusively when it is marked `&`, and holds a dynamic place's access as any borrow does ([02](02-views-and-dependencies.md#rule-6-dynamic-accesses)). Patterns and guards run under that borrow. So a guard can't change or consume the subject, every part is a shared view inside a guard, and an `owned` part takes its value only once its arm is chosen ([01](01-values-and-ownership.md#conditions-and-patterns)).
- **One pattern as a condition.** `if case .chase(let t) = state { … }` tests one pattern as a `when` arm does, and binds its names for the block. `guard case` and `while case` work the same way.
- **A `guard` leaves when its conditions fail.** Every path through its `else` block ends in `return`, `throw`, `break`, `continue` or a call that never returns, so what its conditions bind is bound on every path after it.
- **Patterns that always match.** A `let` or `var` declaration, a `for` loop, and a `let` or `var` condition (whose pattern matches the optional's value) take only `_`, a name, or a tuple of these, under the binding kinds the position allows ([12](12-grammar.md#statements)).
- **Arms and blocks have values.** An arm's body is an expression, an assignment, whose value is `Void`, or a block whose value is its last expression, as an `unsafe` block's is. An arm that ends in `return`, `throw`, `break`, `continue` or a call that never returns, such as `fatalError`, has no value and fits any type.
- **`if` / `else` is an expression too.** Its branches are blocks with values, and an `if` used for its value has an `else`.
- **Types.** Where the position expects a type, every arm's value takes it, as a `return` would ([05](05-protocols-generics-and-closures.md#implicit-conversions)). Where it expects none, as in a `let` with no annotation, the arms have one type: an arm that is an untyped literal, `nil` or an implicit member such as `.idle` takes the typed arms' type. When every arm there is a literal, they take one default together, as an array literal's elements do ([below](#literals)). Used as a statement, `when` and `if` expect no value: each arm's value is discarded, and the arms' types needn't agree.
- **Ownership.** The arm that runs takes the expression's position ([01](01-values-and-ownership.md#if-and-when-as-values)).

### Optionals

```swift
var target: Handle<Enemy>? = nil     // 8 bytes, the same as Handle<Enemy>
if let t = target { attack(t) }
let hp = enemies[h]?.hp ?? 0         // looks at the element's hp in place, or at a 0
```

**`T?` is `Optional<T>`, an enum whose cases are `.some(T)` and `.none`, written `nil`.** `T?` and `Optional<T>` differ only as a projection's declared type ([02](02-views-and-dependencies.md#projections-read-and-modify-accessors)). A `nil` pattern is `.none` and covers it. `T?` offers `if let x`, `guard let x else { return }`, `x ?? d`, `a?.b?.c`, `x!`, and `x == nil` for any `T` ([05](05-protocols-generics-and-closures.md#equality-and-ordering)). An optional chain can be assigned through: `a?.b = v` writes only when `a` holds a value, and `x? = v` replaces `x`'s value only when it holds one ([01](01-values-and-ownership.md#evaluation-order-and-when-a-calls-borrows-begin)).

**`a ?? b` chooses as an `if` does.** It evaluates `b` only when `a` is `nil`, and hands its position to `a`'s payload or to `b` as an `if` hands it to the arm that runs ([01](01-values-and-ownership.md#if-and-when-as-values)). The payload of a place is a place, and the payload of a value is a value. When `b` is a `T?` too, the position goes to `a` or `b` whole, and the result is a `T?`.

**An optional stores `nil` in a niche, a bit pattern `T` never uses, when `T` has one, and then costs no extra bytes.** These types have one:

- raw pointers, `@c` function pointers, `Box`es, object owners and reference-counted pointers, whose `nil` is null;
- weak pointers, weak links and `Handle`s, whose `nil` is zero. `Handle` is a std type the language names ([11](11-compilation-model.md#modules-and-names)), and its generation is never 0 ([03](03-handles-and-objects.md#pools-and-handles));
- an enum with a spare tag value, whose `nil` is the lowest value of its stored type that no case uses: any Rayo enum that has one, `@nonexhaustive` or not, and an imported C enum the header declares closed ([08](08-c-interop.md#structs-unions-and-enums));
- a struct or tuple, through its first stored field or element that has a niche, whose `nil` is that field's. An imported bitfield never supplies one ([08](08-c-interop.md#structs-unions-and-enums)).

An optional itself has none, and neither has an open imported C enum ([08](08-c-interop.md#structs-unions-and-enums)) or `Bool`, so C reading a Rayo `Bool`'s byte as a `bool` always finds 0 or 1.

**No niche lies inside a `Synchronized` value**, at any depth ([07](07-concurrency.md#the-synchronized-contract)), since other threads write its bytes, as a `Mutex<Handle<T>>`'s `Handle` is written under the lock, while reading a tag is a plain load. So `Mutex<Handle<T>>?` and `Atomic<WeakShared<T>>?` keep their tag outside, in the form below.

**Without a niche, `T?` is laid out as a struct of `T` followed by a `Bool` saying whether it holds a value**, so an exported C header can declare it as that struct ([08](08-c-interop.md#c-representations)).

### Untagged unions

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

- **Layout.** Every member is at offset 0, and the union is sized to its largest member, rounded up to its largest alignment, as a C union is. `@c union` adds the `@c` field checks, and imported C unions arrive in this form ([08](08-c-interop.md#structs-unions-and-enums)).
- **Members.** They are copyable, so a union never has to know which one to destroy, and are all one place for exclusivity ([01](01-values-and-ownership.md#which-places-overlap)).
- **Initializers.** A union is built from one member, as in `Bits(f: 1.5)`, and its own `init` builds its value as an enum's does ([above](#enums)).
- **Access.** Writing a whole new value into a member that isn't `unsafe` is safe: initializing the union with it, or assigning it. An `unsafe` member, like an `unsafe` field, is given a value only inside `unsafe` ([above](#initializers)). Every other access reads, since it starts from the bytes already there: a borrow, `&`, a `mutating` call, `b.u += 1` or a reflective `modify`.
- **Reading.** Reading is safe when every member's type is `Pod`, no member is `unsafe`, and the union is padding-free ([below](#plain-data-pod-and-bit-casts)). Otherwise it needs `unsafe`. Unlike the union's own `Pod` conformance, this doesn't ask its members to be as visible as it: a read names a member it can see, and any bytes are a valid value of that member's type.

## Tuples, ranges and arrays

```swift
let pair: (Int, Float) = (3, 0.5)
let stats: (hp: Float, armor: Float) = (hp: 100, armor: 20)
let (count, weight) = pair                   // destructuring
for i in 0..<count { … }                     // a counted loop
let w: [4 of Float] = [0.1, 0.2, 0.3, 0.4]   // an Array<Float, 4>: four Floats, stored inline
var grid: [64 of Int] = .init(repeating: 0)  // every element is given
let locks: [8 of Mutex<Int>] = .init(generating: { _ in Mutex(0) })   // one call per index, for a move-only type
```

**Tuples may be labeled, and are laid out as a struct of their elements in order** ([above](#structs)). A one-element tuple is labeled or written with a trailing comma, `(x,)` of type `(Int,)`, since `(x)` is just `x`.

**Ranges are copyable values**: `0..<n`, `a...b`, `..<n`, `...b` and `i...`.

**An array, `Array<T, N>`, written `[N of T]`, is `N` values of `T` stored inline**, with no heap allocation, and is copyable when `T` is. It is a language type, and what an array literal makes when nothing asks for another type ([below](#literals)).

**Its length is part of its type, so every element is given when it is made**, in one of these ways:

- by a literal of exactly `N` elements;
- by `.init(repeating:)` of a copyable value;
- by `.init(generating:)`, which calls a closure once per index, in order, and takes each result it returns.

`[_ of T]` takes the count from the initializer.

**An array's elements are laid out end to end**, each at `index × stride`, where a type's **stride** is its size rounded up to its alignment. `N` is at least 0, and `N` times `T`'s stride fits in an `Int`, checked where both are known, as for `Simd` ([above](#simd-and-math)).

## Collections and strings

**Rayo separates collections that own their elements, like `List`, from views that borrow elements something else owns, like `Span`**, which are scoped ([02](02-views-and-dependencies.md#scoped-values)):

```swift
var names = List<String>()                // owns its buffer: move-only, allocated through an allocator
names.append("grunt")
names.append("brute")
let all: Span<String> = names.span        // a view: borrows the list's elements
let firstTwo = names[0..<2]               // also a Span
```

**These rows of the table below are language types:**

- the scoped views `Span`, `MutableSpan` and `StringView`;
- the immortal `StaticSpan` and `StaticString`;
- `Name`;
- the object pointers;
- `Slice`, whose `read()` and `lock()` begin the dynamic accesses the spans they return hold ([02](02-views-and-dependencies.md#rule-6-dynamic-accesses)).

The other rows, such as the owning collections and `Handle`, are std's ([11](11-compilation-model.md#what-the-spec-defines)), except `SoA<T>`, which is builtin ([below](#struct-of-arrays-soat)). Every owning collection is move-only, and each one that allocates carries an allocator ([06](06-memory-and-allocators.md#how-values-record-their-allocator)).

| Type | Owning? | Notes |
| --- | --- | --- |
| `List<T>` | yes | Growable, with the allocator it came from ([06](06-memory-and-allocators.md#how-values-record-their-allocator)) |
| `Span<T>`, `MutableSpan<T>` | no (scoped) | ptr + count; `list.span`, `list[a..<b]` |
| `StaticSpan<T>` | no (immortal) | ptr + count into immortal data, copyable and unscoped ([09](09-compile-time.md#staticspan-views-of-immortal-data)) |
| `Map<K, V>`, `Set<T>` | yes | Hash map and set |
| `InlineList<T, N>` | yes | Growable up to `N` elements, stored inline; never allocates |
| `Pool<T>`, `Handle<T>` | yes / no | Slot map over densely packed elements: dense iteration, elements move on removal ([03](03-handles-and-objects.md#pools-and-handles)) |
| `StablePool<T>` | yes | Stable and pinnable element addresses |
| `UniquePointer<T>`, `WeakPointer<T>` | yes / no | An object on one thread, with checked weak pointers to it ([03](03-handles-and-objects.md#objects-and-weak-pointers-uniquepointert-and-weakpointert)) |
| `Shared<T>`, `LocalShared<T>`, `WeakShared<T>` | yes / yes / no | Reference-counted pointers to a value that many places hold, and checked weak links to a `Shared` one ([06](06-memory-and-allocators.md#sharedt-data-with-many-owners)) |
| `Slice<T>` | no | Checked long-lived view into a buffer behind a `Shared` ([06](06-memory-and-allocators.md#long-lived-views-into-long-lived-buffers)) |
| `SoA<T>` | yes | Struct-of-arrays storage for any struct or tuple type `T` ([below](#struct-of-arrays-soat)) |
| `String` | yes | UTF-8 bytes, allocator |
| `StringView` | no (scoped) | ptr + byte count; one made from a string literal views its immortal bytes, so it borrows nothing |
| `StaticString` | no (immortal) | Text in immortal data, with its length and a NUL after it, copyable and unscoped: a literal, text from the `Name` interner, or a `const` `String`'s `staticString` ([09](09-compile-time.md#consts-that-reach-run-time)) |
| `Name` | no | 64-bit interned hash of a text (below) |

**A `Name` is made only from a text:**

- `let n: Name = "jump"` hashes at compile time, as `Name(s)` does for a `const` string;
- `Name(s)` of any other string, and `Name(interning: s)`, intern at run time, copying the text into `.system` memory whatever the current allocator is.

`n.text` is a `StaticString`, since interned text is never freed. Every `Name` the build makes at compile time, by a literal, a `const` or a compile-time evaluation, is in the interner with its text from startup.

**No two texts share a `Name`.** A build in which two constant names would share one fails. At run time, `Name(s)` panics when another text already has `s`'s hash or interning runs out of memory, and `Name(interning: s)` returns `nil` in both cases.

### Strings

**A string is UTF-8 bytes, and formatting writes straight to wherever the text is going:**

```swift
log("hp \(hp)")                           // written into the log's sink: no allocation
"pos \(p.x), \(p.y)".format(into: &buf)   // written into 'buf': no allocation
let label = String("hp \(hp)")            // builds a new String: allocates, visibly
for g in label.graphemes { … }            // user-perceived characters, through an explicit view
```

- **Strings are indexed by byte offset.** Unicode scalars and graphemes are explicit views, `s.scalars` and `s.graphemes`. A range of a string or string view must start and end on Unicode scalar boundaries, or taking it panics, so every string holds whole UTF-8 sequences ([10](10-errors-and-safety.md#what-panics)).
- **Every string literal is null-terminated.** So `"abc".cString` passes to C at no cost. `s.cchars` views any string's bytes as a `Span<CChar>` without a terminator, for C functions that take a pointer and a length.
- **Interpolation writes into a sink.** An interpolated literal, such as `"hp \(hp)"`, evaluates its segments in order, as a call's arguments ([01](01-values-and-ownership.md#evaluation-order-and-when-a-calls-borrows-begin)), borrowing each, and is a scoped value of a type the compiler builds. That type is `Formattable`: it writes its text and each segment in turn into the sink it is given. Every segment's type must be `Formattable` too, as the number types, `Bool`, the string types and `Name` are:

    ```swift
    protocol TextSink { mutating func write(_ text: StringView) where self borrows static }
    protocol Formattable { func format(into sink: mutable some TextSink) where sink borrows static }
    ```

    A sink keeps only copies of the text it is given ([02](02-views-and-dependencies.md#precise-dependencies-opt-in)), so a format may write a view of its own stack buffer, and a sink takes on no borrow of the temporaries an interpolated literal formats. A function that takes a `Formattable`, as `log` does, writes the text where it is going, so interpolation itself allocates nothing, and `String(…)` allocates visibly. An interpolated literal has this type whatever its context, since no literal protocol takes interpolation, so `let s: String = "hp \(hp)"` is an error, and `String("hp \(hp)")` builds the `String`.

### Literals

**A literal has no type until something expects one**, so `[1, 2, 3]`, `"jump"` and `0.5` become whatever their context asks for:

```swift
let v: Vec3 = [1, 2, 3]                   // a Vec3: exactly 3 elements
let mask: LayerMask = [.player, .enemies] // a user type that conforms: any number of layers
let jump: Name = "jump"                   // hashed at compile time
names.append("grunt")                     // a String that uses the literal's bytes: no allocation
let xs = [3, 4, 5]                        // no context: a [3 of Int], stored inline
let ys: List<_> = [3, 4, 5]               // a List<Int>: the annotation names the type that allocates
let zs = [3, 4, 5] as List<_>             // the same, named by 'as'
spawnAll([a, b])                          // error: the List parameter would allocate unseen
let bad: Vec3 = [1, 2]                    // error: a Vec3 literal needs 3 elements
```

**A type takes a literal by conforming to one of the literal protocols**, whose initializer receives the literal:

| Protocol | Requirement | Conforming types |
| --- | --- | --- |
| `ExpressibleByArrayLiteral` | `init<let N: Int>(arrayLiteral elements: owned [N of ArrayLiteralElement])` | `Array`, `Simd`, `InlineList`, `std.math`'s `Vec3` and matrices; where named, `List` and `Set` |
| `ExpressibleByDictionaryLiteral` | `init<let N: Int>(dictionaryLiteral pairs: owned [N of (Key, Value)])` | `Array` of `(Key, Value)` pairs, user types such as a fixed lookup table; where named, `Map` |
| `ExpressibleByStringLiteral` | `init(stringLiteral text: StaticString)` | `StaticString`, `StringView`, `Name`, `String` |
| `ExpressibleByIntegerLiteral` | `init(integerLiteral value: IntegerLiteralType)` | every number type |
| `ExpressibleByFloatLiteral` | `init(floatLiteral value: FloatLiteralType)` | `Half`, `Float`, `Double` |

- **A literal allocates only where its type is written.** A conformance applies wherever the type is expected when either of these holds:
    - its initializer is `@noalloc` ([06](06-memory-and-allocators.md#allocation-failure)), as those of the number types, `Array`, `Simd`, `InlineList`, `StaticString`, `StringView`, `String` and `std.math`'s `Vec3` and matrices are;
    - its literals convert at compile time (below), as `Name`'s do.

  A conformance that meets neither, as `List`'s, `Set`'s and `Map`'s don't, applies only where that type is spelled at the literal. It is spelled there in the annotation of the declaration the literal is part of, a field's included, or in an `as` applied to it. `_` stands for what the literal fills in, as in `List<_>`. Anywhere else, such as a `List` parameter, a `return`, or an assignment to an existing `List`, the literal is an error. So `spawnAll([a, b])` can't allocate unseen. `@noalloc` code takes none of these, and generic code converts a literal to its `T` only where it writes `T`, since `T`'s initializer may allocate.

  **std's `String` takes a literal without allocating.** It records the current allocator, as every `String` does, and is checked against it at each open like any other ([06](06-memory-and-allocators.md#opening-an-owning-value-checks-it)). But it uses the literal's immortal bytes until the first call that writes or grows it, which copies them into a buffer from that allocator.
- **An array literal's elements arrive inline.** They come as an owned `[N of Element]` whose count is known at compile time, never as a heap buffer. So a type refuses a count it can't hold at compile time, through `static if` and `static error` ([09](09-compile-time.md#static-if-and-conditional-compilation)): `Simd<T, N>` takes exactly `N` elements, `Vec3` exactly 3 and `InlineList<T, 8>` at most 8. Passed where an `[N of T]` with an unbound `N` or `T` is expected, as for `List([1, 2, 3])`, a literal binds `N` to its count and `T` as it does with no context.
- **An integer or float literal is checked against the type it becomes.** A prefix `-` applied directly to it, where an operand begins, is checked with it as one value, so `let lo: Int8 = -128` fits, while `n-1` still subtracts. A postfix member applies to the literal first, so `-128.abs` is `-(128.abs)`. It must fit the conformer's `IntegerLiteralType`, at compile time, and a float literal is rounded once, to its `FloatLiteralType`, which is `Half`, `Float` or `Double`.
- **With no context, a literal has a default type.** An integer literal is an `Int`, a floating-point literal a `Double`, a string literal a `StaticString`, a dictionary literal an `[N of (K, V)]`, and an array literal an `[N of T]`. Its `T` is the type of its typed elements, which must agree. When every element is a literal, they take one default together:
    - for number literals, `Double` if any is a floating-point one, and `Int` if none is;
    - for literals of one other kind, that kind's default, so `["a", "b"]` is a `[2 of StaticString]`.

  Literals of different kinds, such as `1` and `"a"`, are an error. An empty `[]` or `[:]` needs a context.
- **A literal of constants converts at compile time.** A literal of constants is one whose elements, at any depth, are literals or `const`s. It converts when its initializer can run at compile time ([09](09-compile-time.md#running-code-at-compile-time-const)) and the value it builds owns nothing outside its own bytes:
    - no allocation;
    - no object;
    - no `Synchronized` value;
    - no `Allocator` id but `.system`;
    - no pointer but a `StaticString` or `StaticSpan`.

  `Name`, `Simd`, an `[N of T]` or `InlineList` of such values, and `std.math`'s `Vec3` and matrices qualify. Each evaluation takes a new copy of the bytes, as a `const` of a copyable type is taken ([01](01-values-and-ownership.md#constants)). So `let jump: Name = "jump"` costs nothing at run time.

  Any other literal runs its initializer on each evaluation: a `List`'s allocates from the current allocator, and a `String`'s only records it. Whether or not a literal converts, when its initializer can run at compile time, a precondition it breaks on constant elements is a compile error.
- **`true` and `false` are only `Bool`, and `nil` only an optional.**

### Iteration

**A `for` loop borrows each element where it is, so iterating never copies:**

```swift
var total: Float = 0
for e in enemies { total += e.hp }                        // e is each element, borrowed shared
for var e in &enemies { e.hp -= 1 }                       // e is each element, borrowed mutably
for (i, var e) in &enemies.enumerated() { … }             // i is an Int, e a mutable borrow
for (var v, f) in zip(&vels, forces) { v += f * dt }      // two sequences in lockstep
```

```swift
protocol Sequence { associatedtype Iterator: IteratorProtocol; func makeIterator() -> Iterator }
protocol IteratorProtocol { associatedtype Element; mutating func next() -> Element? }   // may lend
protocol SharedIterator: IteratorProtocol {     // elements outlive the iteration (02)
    mutating func next() -> Element? where return outlives self
}
protocol Collection: Sequence where Iterator: SharedIterator { var count: Int { get } }   // what generic algorithms take

protocol MutableSequence {                      // what 'for var x in &s' iterates
    associatedtype MutableIterator: IteratorProtocol   // its Element is an exclusive view: MutableRef<T>, MutableSpan<T>, …
    mutating func makeMutableIterator() -> MutableIterator
}

protocol ConsumingSequence {                    // what a loop over a whole value takes
    associatedtype ConsumingIterator: IteratorProtocol
    consuming func makeConsumingIterator() -> ConsumingIterator
}
```

**A collection's shared and mutable iterators yield views of its elements, and its consuming iterator yields the elements themselves:**

- its iterator yields `Borrow<T>`, a copyable, scoped shared view of one element;
- its mutable iterator yields `MutableRef<T>`, a move-only exclusive one, a one-element `MutableSpan`;
- its consuming iterator yields each `T` itself.

A pattern binds through the view's `value`, so move-only elements iterate like any others.

**A sequence that is a place is iterated where it is.** Such a place is a variable, a stored field, or a `read` or `modify` projection such as `.value`. Anything else, such as `a.enumerated()`, is a whole value. It is moved into a hidden `var` that lives until the loop ends. So is every temporary in the sequence expression, each into its own, in evaluation order: in `for (i, var e) in &makeEnemies().enumerated()` the list is a hidden mutable local. An adaptor in a hidden local keeps its collection borrowed for the whole loop.

**Each element is bound in place when it lives in the collection, and owned when the iterator hands it out as a value of its own** ([01](01-values-and-ownership.md#conditions-and-patterns)). With `S` for what is iterated:

- A loop over `&s` runs `var it = S.makeMutableIterator(); while var r = it.next() { bind pattern to r′; body }`, holding `S`, and through it the collection, exclusively. The `&` selects this form, and is required to change elements, as it is in any binding ([01](01-values-and-ownership.md#lending-a-place-for-change)).
- A loop over a whole value, such as a call result or `consume x`, whose type conforms to `ConsumingSequence` runs `var it = S.makeConsumingIterator(); while let b = it.next() { bind pattern to b′; body }`. The iterator takes `S`, so `for b in consume jobs { finish(b) }` hands each job over, and the iterator's `deinit` destroys the elements a `break`, `return` or `throw` leaves. `[N of T]` conforms, as std's owning collections do.
- Every other loop runs `var it = S.makeIterator(); while let b = it.next() { bind pattern to b′; body }`.
- `b′` is `b.value` for a `Borrow`, borrowing the element in place, and `r′` is `&r.value` for a `MutableRef`. Any other element, such as a range's `Int` or a chunk, is a value the iterator hands out: `b′` is `consume b`, `r′` is `consume r`, and the loop variable owns it for the iteration, as in `for i in 0..<n { ids.append(i) }`. So `for var` without `&` over elements that live in `s` binds a `var` part to a place without `&`, a compile error ([01](01-values-and-ownership.md#lending-a-place-for-change)).
- The pattern binds part by part: through `.value` for a `Borrow` or `MutableRef` part, read-only for a part without `var` and in place for a `var` part, and directly, owned, for any other part. So `for (h, var e) in &pool.entries` binds `e` in place and gives `h` its own handle ([01](01-values-and-ownership.md#the-law-of-exclusivity)). A `zip` with `&` arguments hands out `MutableRef` parts itself, so `for (var v, f) in zip(&vels, forces)` needs no `&` of its own.
- A `where c` after the sequence, as in `for var e in &enemies where e.hp > 0`, runs the body as `if c { body }`, with the pattern bound.

**`while` takes conditions as `if` does**, except that `let x` has no short form there ([01](01-values-and-ownership.md#conditions-and-patterns)). `repeat { … } while c` tests `c` after each pass. A label, as in `outer: for row in grid`, lets a nested loop's `break outer` or `continue outer` name that loop.

**Which elements outlive the iteration follows from the dependency rules** ([02](02-views-and-dependencies.md#dependencies)):

```swift
var names = List<StringView>()
for s in table.entries { names.append(s.name.view) }    // fine: each element depends on 'table', not the iterator
for var chunk in &data.chunks(64) { scale(&chunk) }       // one MutableSpan<Float> at a time
```

**A mutable iterator lends.** Its `mutating` `next()` makes each element depend exclusively on the iterator until the next call. So keeping a chunk past its iteration, or holding two, is a compile error. `split(at:)` gives two at once.

**`zip` is builtin**, since no generic function takes a varying number of arguments with per-argument conventions. `zip(a, &b, c)` borrows `&` arguments exclusively and the rest shared, hands out tuples, and stops at the shortest, so every element is in bounds. A `zip` with an `&` argument is a move-only exclusive view whose only iteration is the consuming one. So a loop over a place holding one is written `for (var x, y) in consume z`, and no two iterators hand out its `MutableRef`s.

### Shared, mutable and consuming forms of one method

**One name can have a shared and a mutable form, each picked by its context:**

```swift
for (i, e) in items.enumerated() { … }           // shared: (Int, Borrow<Item>) elements
for (i, var e) in &items.enumerated() { … }      // exclusive: (Int, MutableRef<Item>) elements
let ages = particles.life                        // Span<Float>
var lives = &particles.life                      // MutableSpan<Float>
particles.life.sort()                            // only the mutable form has sort(), so it is used
```

**A type may declare a non-`mutating` and a `mutating` method or property with the same name and parameters, and each use picks one by its access context alone**, with no search. A `mutating` computed property or subscript, as in `mutating var life: MutableSpan<Float> { get { … } }`, has accessors that take `self` exclusively. The context is exclusive for these:

- an operand of `&` ([01](01-values-and-ownership.md#lending-a-place-for-change));
- an assignment's target;
- a receiver only the exclusive form can serve (below).

Everywhere else it is shared, so a value of the mutable form is written with `&`, as in `func lives(_ p: mutable Particles) -> MutableSpan<Float> { &p.life }` or `Cols(life: &p.life)`.

**For a call's receiver, the least access wins**: the shared form when its declared result has a member that fits, so `data[0..<n].split(at: m)` splits a `Span`, and the exclusive form only otherwise, as for `particles.life.sort()`. `var whole = &data[0..<n]` forces the exclusive form.

**A `consuming` method may share a `mutating` one's name and parameters:**

```swift
var (a, b) = s.split(at: m)             // 's' is a place: the mutating form lends two halves
var (c, d) = (consume s).split(at: m)   // a whole value: the consuming form hands them over
```

- **A receiver that is a whole value picks the `consuming` form**: a call result, a `get` accessor's or subscript's included, or `consume x`.
- **A receiver that is a place picks the `mutating` form**, or, where a shared form exists too, the one its access context picks (above). A place here is a variable, a stored field even of a temporary, or a `read` or `modify` projection.

So `s.split(at: m)` on a `MutableSpan` lends two halves that depend on `s` exclusively. `(consume s).split(at: m)` hands them over, carrying only what `s` carried, by rule 3 ([02](02-views-and-dependencies.md#rule-3-call-results)). A shared `Span`'s `split(at:)` is declared `where return outlives self`, so it needs no pair.

### Plain data: `Pod` and bit casts

**A type where any bytes make a valid value is `Pod`** ("plain old data"), so bytes from a file or a packet can be used as one:

```swift
public struct Vertex(public var pos: Vec3, public var normal: Vec3, public var uv: Vec2)     // every field Pod and public: Pod

let f: Float = 1.5
let bits = UInt32(bitPattern: f)                      // a safe bit cast: Float has no padding
if let verts = bytes.reinterpret(as: Vertex.self) {   // Span<UInt8> to Span<Vertex>?, checked once
    upload(verts)
}
```

**The compiler derives `Pod` for types where every bit pattern is valid and that own nothing:**

- integers, floats, `Half` and their `Simd` vectors (not `Simd<Bool, N>` masks);
- **open** imported C enums and flag enums whose raw type is an integer type, padding-free like it ([08](08-c-interop.md#structs-unions-and-enums));
- arrays and tuples of `Pod`;
- structs with no `deinit` whose stored fields are all `Pod`, all **as visible as the struct**, and none `unsafe`, and whose primary initializer is as visible as the struct too and not `unsafe` ([above](#initializers)). An imported bitfield counts as [08](08-c-interop.md#structs-unions-and-enums) says;
- unions with no `deinit`, named or anonymous in a struct ([08](08-c-interop.md#structs-unions-and-enums)), whose members are all `Pod`, all as visible as the union, and none `unsafe`.

**These are not `Pod`:**

- `Bool`, Rayo enums, closed C enums, pointers, `Handle`s, weak pointers, weak links, `Name` and owners of memory;
- a `Synchronized` type, or anything that holds one at any depth, since other threads write its bytes while a `Pod` read would load them plainly ([07](07-concurrency.md#the-synchronized-contract));
- a type the compiler builds, whose fields nothing names: a closure literal's or a task's state, or an interpolated literal's value ([09](09-compile-time.md#what-reflection-can-read)).

**`@pod` waives only the visibility and `unsafe` conditions.** So it is a compile error on the types listed as not `Pod`, and on a struct or union that has a `deinit` or holds a type that isn't `Pod`.

**The visibility and `unsafe` conditions protect invariants.** A field is as visible as its struct when it is `public` or the struct isn't, and a primary initializer is unless the struct is `public` and its header says `private init` ([11](11-compilation-model.md#modules-and-names)). A type that guards an invariant must not be forged from bytes. One is a `public` `Fraction`, whose `private init` makes every other module pass the nonzero-denominator check. Another is a `struct SlotIndex(public unsafe let raw: UInt32)` or `struct SlotIndex unsafe init(public let raw: UInt32)` that `unchecked` code trusts. Each fails the conditions, so it is `Pod` only through `@pod`, which states that every bit pattern is valid.

**Padding bytes are uninitialized, and a type with none is padding-free**, which the `const` `T.isPaddingFree` reports ([09](09-compile-time.md#what-reflection-can-read)).

- **Unions.** A union is padding-free when every member is and fills it exactly. Bytes a member doesn't cover, including tail padding from `@align(N)`, count as padding.
- **Enums.** An enum, an optional included, is padding-free when each of its values sets every byte. So bytes that a case's payload doesn't fill, or that a `nil` leaves unset, count as padding: `UInt8?` isn't padding-free, and `Handle<T>?`, whose `nil` is all zero, is.
- **Bitfields.** In an imported struct or union, the bitfield bits [08](08-c-interop.md#structs-unions-and-enums) lists count as padding too.

**Casts between `Pod` types depend on padding:**

- **Bit casts.** `U(bitPattern: t)` between `Pod` types of equal size is safe when `t`'s type is padding-free.
- **Span casts.** `span.reinterpret(as: Vertex.self)` views a span of a `Pod` type `A` as a `Span<U>?` of a `Pod` type `U` of nonzero size, here `Vertex`, checking size divisibility and alignment once. A shared cast needs `A` padding-free, so every byte read is initialized. A mutable cast needs both types padding-free, since a store through a padded type leaves its padding unspecified while other views still see `A`.

### Variable-sized structs: `TrailingArray`

**`TrailingArray<Header, Element>` is one allocation of a `Header` followed by `n` `Element`s**, as a network packet or a C API with a flexible array member wants.

```swift
var msg = TrailingArray<PacketHeader, UInt8>(header: h, count: n, repeating: 0)
msg.header.kind = .snapshot
msg.elements[0..<4].copy(from: payload[0..<4]) // MutableSpan<UInt8> over the trailing storage; lengths checked
```

It is move-only, and owns its allocation, whose element count is fixed when it is made. It has a C representation when its header and element types both have one ([08](08-c-interop.md#c-representations)).

- **Layout.** The header starts the allocation, which is aligned for both types, and the elements follow, one `Element` stride apart, from the first multiple of `Element`'s alignment at or after the header's size. The allocation is at least as large as the header's size and as the elements' end, so the whole header lies inside it.
- **Elements in the header's tail padding.** When the header is a struct or tuple, and neither it nor `Element` is or holds a `Synchronized` value, the elements start instead where C puts a flexible array member of `Element`s after the header's fields. They replace any such member the header declares, and start:
    - for a Rayo header, at the first multiple of `Element`'s alignment at or after the end of its last field ([above](#structs));
    - for an imported one, at the offset the target's C ABI gives that member.

  That offset must be a multiple of `Element`'s alignment. A packed imported header whose member C places lower, as `#pragma pack(1)` can, is a compile error as a `TrailingArray` header, since its elements couldn't be both where C reads them and aligned. So the elements can start inside the header's tail padding, or inside the storage unit of a bitfield that ends an imported header.

  A `Synchronized` value may write any of its bytes through a shared borrow, padding included, while the other side is read with plain loads. So with one on either side, the two never share bytes.
- **The header.** `msg.header`'s `read` lends it in place. Its `modify` yields it from a temporary and writes it back whole, except a struct or tuple header, which it writes field by field, each bitfield through its accessor, so the header's tail padding is never written. A view from the `modify` is access-bound ([02](02-views-and-dependencies.md#access-bound-projections)). Code that reaches the header through a pointer, C or `unsafe` Rayo, writes it the same way ([10](10-errors-and-safety.md#unsafe-code)).

### Struct of arrays: `SoA<T>`

**`SoA<T>` stores each field of a struct `T`, or each element of a tuple `T`, in its own buffer**, so a loop reads only the fields it touches, still with field syntax:

```swift
var particles = SoA<Particle>(capacity: 100_000)  // or SoA<Particle>(), as for List
particles.append(Particle(pos: p, vel: v, life: 2))

for var p in &particles {              // p is a row: one place per field
    p.pos += p.vel * dt                // touches only the pos and vel arrays
}
```

**`SoA<T>` is builtin, and its columns are `T`'s stored fields in declaration order**, private ones included, as `T.fields` lists them ([09](09-compile-time.md#static-reflection)). A tuple's columns are `s.0`, `s.1`, and so on, and an anonymous union is one field, so its members share a column. `SoA`'s own members, such as `count`, `capacity` and `append`, hide a field of the same name, whose column `s[field: f]` still reaches.

**Columns are views.** `s.life` returns a `Span` of the column's buffer in a shared context and a `MutableSpan` in an exclusive one ([above](#shared-mutable-and-consuming-forms-of-one-method)), which a binding such as `var lives = &particles.life` owns ([01](01-values-and-ownership.md#lending-a-place-for-change)). The view depends on that column alone, a part of `s` disjoint from the other columns as a stored field is from its siblings ([01](01-values-and-ownership.md#which-places-overlap)), so `&s.pos` and `s.vel` can be held at once. `s[field: f]` returns one column, as `s.f` does, and `s[fields: (f1, f2)]` a tuple of columns. Marked `&`, `s[fields:]` gives each column in the kind of its pattern element: in `let (var ts, vs) = &table.rows[fields: (tf, vf)]`, `ts` is a `MutableSpan` and `vs` a `Span`.

**Each element a `for` loop over `s` hands out, and `s[i]`, is a row.** A **row** is a view of one index across every column. It is shared or, through `&`, exclusive, as `Borrow<T>` and `MutableRef<T>` are for other collections ([above](#iteration)). It has one projection per field of `T`, named as the field is, which lends that field's place in its column. Those places are disjoint, as a struct's stored fields are ([01](01-values-and-ownership.md#which-places-overlap)), so `p.pos += p.vel * dt` writes one while it reads another. A row isn't a `T`: code reads and writes it field by field, and appending and removing move whole `T` values.

**Columns and rows obey the rules of `value[field]` at the use site.** Under those rules ([09](09-compile-time.md#reflection-and-access-control)), a column is a `MutableSpan`, and a row's field can be written, only for a `var` field that could be assigned there, so a `let` field's column is a `Span` even in an exclusive context. A column of an `unsafe` field is available only inside `unsafe`, and a private field's column exists only where the field is visible. Appending and removing whole rows moves whole values, so it needs none of this. A growing operation grows every column or none: when an allocation fails, `tryAppend` throws, and `append` panics, with every column as it was ([06](06-memory-and-allocators.md#allocation-failure)).

