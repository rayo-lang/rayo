# Structs

[04 · Types](../04-types.md)

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

**A struct's fields lie in memory in its layout order.** A struct's **layout order** sorts its fields by decreasing alignment, and keeps declaration order among fields of equal alignment. Every alignment is a power of two and every size a multiple of its alignment, so no padding falls between fields, only after the last. The rule alone fixes the order, so a struct has one layout on every target and in every build.

**A `@c` or `@packed` struct's layout order is its declaration order**, for a layout that something outside the program fixes, such as a C header, a file format or a network packet.

**Everything else follows declaration order**, since it concerns what the fields mean, not where they lie: the primary initializer's parameters, `T.fields`, `SoA`'s columns, derived `==` and `hash(into:)`, and destruction ([01](../01-values-and-ownership/moves-copies-destruction.md#destruction)).

**The compiler places the fields, in layout order, by these rules:**

- **Offsets.** Each field goes at the first multiple of its alignment at or after the end of the field before it, the first at offset 0.
- **The struct's size and alignment.** A struct is aligned to its most-aligned field, and its size is the end of its last field rounded up to the struct's alignment. A struct with no fields has size 0 and alignment 1.
- **Each type's alignment.** A number, `Bool` or raw pointer is aligned to its size, and every other type's alignment follows from its own layout.

**Every Rayo target's C ABI places a struct's fields by these rules too** ([11](../11-compilation-model.md#what-a-target-must-provide)). So a struct whose fields all have C representations crosses to C as the C struct that declares its fields in layout order ([08](../08-c-interop/calling-rayo-from-c.md#c-representations)). A `@c` struct crosses as the one that declares them as it does.

**Attributes change or check the layout:**

```swift
struct Hit(var crit: Bool, var damage: Double, var team: UInt8)       // 16 bytes: 'damage', 'crit', 'team', then 6 bytes of padding
@c struct CHit(var crit: Bool, var damage: Double, var team: UInt8)   // 24 bytes, in declared order: 7 bytes of padding after 'crit'
@packed struct Rec(var id: UInt32, var tag: UInt8)                    // 5 bytes, alignment 1, in declared order
@align(16) struct Slot(var value: Float)                              // 16 bytes, 16-byte aligned
```

- **`@packed`, on a struct or a union, counts every field's alignment as 1.** So the alignment is 1, and there is no padding between or after fields: a struct's fields sit end to end. Padding inside a field's own type stays. `@packed(N)` caps each field's alignment at `N`, a power of two. C's packed records import as these ([08](../08-c-interop/imports-and-inline-c.md#what-imports-as-what)).
- **`@align(N)` raises the alignment to at least `N`**, a power of two, and the size rounds up to it.
- **`@c` keeps the declared order, and rejects fields with no C representation** ([08](../08-c-interop/calling-rayo-from-c.md#c-representations)). It changes nothing else, since every target's C ABI already places fields by the rules above.

**`@packed`, `@packed(N)` and `@align(N)` apply only to a struct or union declaration**, and are a compile error elsewhere.

**A value never contains itself.** A struct, tuple, enum or union that would hold a value of its own type inline, through its fields, payloads, optionals or inline arrays at any depth, is a compile error. So is a task whose state would ([07](../07-concurrency/tasks.md#semantics)). Recursion goes through an owner, so the allocation is visible:

```swift
enum Tree {
    case leaf(value: Float)
    case node(Box<Tree>)          // the subtree lives in an allocation of its own, which the Box owns
}
struct Chain(var next: Chain?)    // error: a Chain would hold a Chain inline, in its optional
```

## Initializers

```swift
struct Spawner(
    var target: Handle<Enemy>?,     // a var of optional type: starts as nil, so it is defaulted
    let owner: Handle<Player>?,     // a let of optional type: no default
    var cooldown: Float = 2,
    var spawned = Pool<Enemy>(),    // the default gives the field its type
)
let s = Spawner(owner: nil)         // 'target', 'cooldown' and 'spawned' may be left out
```

**Every value of a struct is built by its primary initializer**, except a value that a `Pod` type takes from bytes ([Plain data: `Pod` and bit casts](data-layout.md#plain-data-pod-and-bit-casts)) and an imported C struct's zero-initialized one ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)). The primary initializer's parameters are the fields, in order and labeled by name:

- **Owned fields.** The header lists fields, not parameters: each entry is a `var` or `let`, and takes no parameter convention. The value owns its fields, so the primary initializer takes every one `owned`: `Inventory(items: loot)` moves `loot` in, unless the call says `copy loot` or `loot.clone()` ([01](../01-values-and-ownership/parameters.md#parameters)).
- **Defaults.** A field's default makes its argument optional. A field with a default may leave its type to the default, as `spawned` does above.
- **Optional `var`s.** A `var` declared with an optional type, `T?` written as such, with no default and not `unsafe`, starts as `nil`. It counts as defaulted, for the primary initializer and for reflection's `hasDefault` ([09](../09-compile-time/reflection.md#what-reflection-can-read)). A `let` of optional type does neither.
- **`unsafe` fields.** An `unsafe` field, such as `Span`'s `baseAddress`, is given its argument only inside `unsafe`, just as naming it needs `unsafe`.

**A type can also offer other initializers**, which can check an invariant before the value exists:

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

**Every other `init` is secondary, and delegates.** It computes and checks what the primary initializer needs, then calls `self.init(…)`. It is an ordinary function whose parameters are borrowed unless marked. So it passes `copy x`, or an `owned` parameter, on to the primary one, as `Fraction` does above.

**A secondary initializer calls `self.init` at most once on every path, and exactly once on every path that returns the new value.** A call that a path could reach twice, as one in a loop could, is a compile error. The call reaches the primary initializer directly or through other secondary ones, and secondary initializers that call each other without reaching it are a compile error.

**Before `self.init`, `self` doesn't exist.** Nothing reads or assigns a field until then, and after it `self` is a whole value, as in a `mutating` method.

**No value is ever half-built.** The primary initializer sets every field at once, from arguments already evaluated. An `init` that throws or returns `nil` before `self.init` has only its locals to destroy. One that throws or returns `nil` after it destroys a whole value, running its `deinit` if the type has one.

**The header sets the primary initializer's access.** It is as visible as the struct unless the header says `private init(…)`, which keeps it inside the module ([11](../11-compilation-model.md#modules-and-names)). Other modules then build a value only through a secondary initializer, which can check an invariant such as `Fraction`'s nonzero denominator. Two more things in the header limit who can call it:

- **Fields that aren't `public`.** Such a field is a parameter only inside the module. So elsewhere the primary initializer can be called only if every such field has a default, or through `T.construct` on a `@reflect(private)` type ([09](../09-compile-time/reflection.md#constructing-values-reflectively)).
- **`unsafe init(…)`** makes every call to the primary initializer `unsafe`, for fields that `unsafe` code trusts, such as an index it doesn't bounds-check.

**Extensions may add secondary initializers.** They add no stored member or enum case.

**A `deinit` is declared in the type's own module, unconditionally**, as `~Copyable` is ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#conformances)). It goes in the type's body, where a `static if` or `static for` may generate it, or in an **unconditional extension**: one that gives none of the type's generic arguments and has no `where` clause. An extension that gives some, such as `extension Tagged<Int>`, is conditional, as one with a `where` clause is.

**That keeps a `deinit` part of the type everywhere.** A `deinit` makes the type move-only and, unless the type conforms to `PlainDeinit`, makes destroying a value of it a use of what that value borrows ([02](../02-views-and-dependencies/dependency-lifetimes.md#when-destroying-a-value-counts-as-using-it)). Either effect changes how every use is checked. So code that checked the type as copyable, or its destruction as no use, never meets a value that has one.

## Packed structs and under-aligned places

**A `@packed` struct or union can put a field at a misaligned address**, where a load or store of the field's type is invalid ([10](../10-errors-and-safety/unsafe-code.md#raw-accesses)) and faults on some targets. So the compiler tracks which places may be misaligned, and code uses those only by value:

```swift
@packed struct NetRec(var tag: UInt8, var ids: [4 of UInt32])     // 'ids' starts at offset 1

func sum(_ r: NetRec) -> UInt32 {
    var total: UInt32 = 0
    for i in r.ids { total += i }         // error: binds elements of an under-aligned field in place
    for i in copy r.ids { total += i }    // fine: iterates an aligned copy
    return total
}
```

**These places have a guaranteed alignment**, which their address is always a multiple of:

- **Variables and separately allocated elements.** A variable's guarantee, or an element's of separately allocated storage, such as a `List`, a pool or a span, is its type's alignment.
- **Fields.** A field's guarantee is the smaller of its enclosing place's guarantee and the largest power of two dividing its offset. A tuple's element is a field ([Tuples, ranges and arrays](collections.md#tuples-ranges-and-arrays)). An element of `[N of T]` or a `Simd` counts as one at offset `index × stride`, using the stride for a dynamic index.

**A place guaranteed less than its type's alignment, at any depth, is under-aligned, and is used only by value.** So `recs[1].id` in a `List` of the 5-byte `Rec` above is under-aligned: `id` is at offset 0, but `recs[1]` itself is guaranteed only 1. Using it by value means that nothing borrows it where it lies:

- **No views.** Any borrow of it but an argument is a compile error: a binding or pattern part bound in place, a `when` subject, a span, an `any P`, a `yield` in an accessor, or a `for` loop binding its elements in place. A closure captures the aligned place that holds it instead ([05](../05-protocols-generics-and-closures/functions-and-closures.md#capturing-places)).
- **Arguments go through an aligned temporary.** It is copied in, and back for a `mutable` one, a receiver included. A projection reached through such a receiver, or whose `where yield` clause names such an argument, is access-bound, as a bitfield's is ([02](../02-views-and-dependencies/projections-and-accessors.md#access-bound-projections)): the temporary is written back when the access ends. A call is a compile error if the argument place would enter the dependency set of its scoped result or thrown error ([02](../02-views-and-dependencies/dependency-projection-and-results.md#rule-3-call-results)), or be absorbed into another argument ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)).

**Generic code takes the safe bound**, since it is checked once, at its definition ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#checking-generic-code)). A path that crosses no `@packed` struct or union stays aligned, since ordinary layout keeps every field aligned for its type. Below a `@packed` or `@packed(N)` struct or union, generic code computes the enclosing guarantee and each offset only from the parts that don't depend on a type parameter: at least 1, and 1 after any field of parameter-dependent size. A field whose type depends on a parameter is taken to require the largest alignment any type can have:

```swift
@packed(4) struct Msg<T: Copyable>(var tag: UInt8, var payload: T)
struct Env<T>(var rec: Rec, var body: T)

func unpack<T: Copyable>(_ m: Msg<T>, _ e: Env<T>) {
    let p = copy m.payload      // by value: under-aligned, since T may need more than 4
    let id = copy e.rec.id      // by value: under-aligned, since Env<UInt8> misaligns it
}
```

**Requirement projections stay aligned.** Generic code treats what a requirement yields as aligned, for two reasons. An under-aligned field, such as `ids` in a `NetRec` that conforms to a protocol requiring `ids`, witnesses a `read` or `modify` requirement only through an aligned temporary ([02](../02-views-and-dependencies/projections-and-accessors.md#projections-in-protocols)). And no `yield` names an under-aligned place (above).

**A `@packed` or `@packed(N)` struct can't hold a `Synchronized` value inline**, through its fields, elements and payloads at any depth ([07](../07-concurrency/synchronization.md#atomics-and-locks)). Atomics need their alignment, and shared access to a `Synchronized` value is always in place, never through a temporary. A `Closure` counts as holding one, since its inline captures may hold one unseen in its type ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)). What a field owns out of line, such as a `List`'s elements, is aligned and doesn't count.

So the type of a field that depends on a type parameter must be provably free of `Synchronized` values and `Closure`s at the definition, by being one of these:

- `Copyable`, since anything holding either is move-only, as `Msg` above declares its `T`;
- `Frozen`, which holds neither ([06](../06-memory-and-allocators/owning-values.md#frozen-types-with-no-interior-mutability)), as with `where T.Payload: Frozen`.

A field whose type generates its fields from its parameters ([09](../09-compile-time/declaration-generation.md#generating-declarations)) is proven free of both only through a `where` clause stating that type `Copyable` or `Frozen`.
