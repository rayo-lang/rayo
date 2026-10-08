# Operators

[05 · Protocols, generics and closures](../05-protocols-generics-and-closures.md)

Most operators are calls written with punctuation instead of a function name; short-circuiting forms such as `&&` are built in. A declared operator determines which types it accepts, while separate rules decide how operators group in an expression and how equality and ordering work.

**Operators are `static func`s declared on a type or in an extension of it, named by the operator:**

```swift
extension Vec3 {                                                // in std.math
    @inline public static func * (lhs: Vec3, rhs: Float) -> Vec3 { ... }
    @inline public static func * (lhs: Float, rhs: Vec3) -> Vec3 { ... }   // declared on Vec3; found via rhs
    @inline public static func - (v: Vec3) -> Vec3 { ... }                 // one parameter: prefix, as in -v
}

pos += vel * dt                                                 // pos = pos + vel * dt
```

**Lookup is bounded: the candidates for `a ⊕ b` are the operators declared on the types of `a` and `b`, and nothing else.** Those include the defaults of protocols the types conform to, such as `Equatable`'s `!=`, and, for a type parameter, its constraints' requirements. No global set of operators exists to search, so type checking stays local ([11](../11-compilation-model.md#type-checking-is-local)).

**The other rules fix what an operator expression can mean:**

- **The set is fixed.** The declarable operators are the ones the grammar lists ([12](../12-grammar/declarations.md#files-and-declarations)), with fixed precedence. The others are built in:
    - `&&` and `||` take `Bool`s, and `??` takes an optional ([04](../04-types/enums.md#optionals)). Each evaluates its right side only when needed.
    - `..<` and `...` make a range of a copyable `Comparable` type. They borrow their operands and copy them in, so `0..<count` leaves `count` usable.
- **Typed operands may widen.** When both operands are typed, a candidate applies when each operand is of its parameter's type or widens to it ([04](../04-types/numbers-and-math.md#conversions)). If exactly one candidate needs no widening, it wins; otherwise exactly one must apply, or the expression is ambiguous. So with `clock` a `Double` and `dt` a `Float`, `clock += dt` adds two `Double`s.
- **The parameter count decides the form.** A function with one parameter declares a prefix operator, and one with two a binary operator. `-` has both forms, `!` and `~` are only prefix, and the rest only binary.
- **Compound assignment is shorthand.** `a ⊕= b` means `a = a ⊕ b`, with the place `a` worked out once ([01](../01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin)), so `hp[next()] -= 1` calls `next()` once. No type declares `+=`, so it always agrees with `+`.

**Untyped operands take their type from the other side.** A literal or an implicit member expression (`2`, `0.5`, `.pi`, `.zero`) has no type until something expects one. An implicit member names a static member, case or initializer of the expected type. Where a `T?` is expected, it names one of `T?` first and then of `T`, as `.init(bitPattern: bits)` does for a `*Void?` parameter. When one operand of `a ⊕ b` is untyped and the other typed:

- The candidates are the operators on the typed operand's type that take it in its position and whose matching parameter the untyped operand fits. With `v` a `Vec3`, `v * 2` keeps only `*(Vec3, Float)`, so `2` is a `Float`. A shift is the exception: its untyped value never takes its type from the count ([04](../04-types/numbers-and-math.md#integer-overflow-division-and-shifts)).
- If several remain, the one whose parameter has the typed operand's own type wins; otherwise the expression is ambiguous.

**When both operands are untyped, the expression is untyped**, typed by its context the same way, or else by the literal defaults: `Double` if either is a floating-point literal, and `Int` if not ([04](../04-types/collections.md#literals)).

**Operators apply one at a time**, each step typed from the one before:

```swift
let angle = Float(i) / 1024 * 2 * .pi   // Float(i) / 1024 is a Float, so 2 and .pi are Floats too
```

**Generic calls work the same way.** A call binds each type parameter in the first of these ways that applies:

1. From its typed arguments. Typed arguments that bind it to different types bind it to the one the others widen to, or are an error.
2. By matching the expected type against the call's result type, part by part, as `await` does ([07](../07-concurrency/tasks.md#semantics)).
3. From the literals' default.

**Each untyped argument then takes its parameter's type.** The first four calls below bind `T` or `C` in these three ways, and the last gives its untyped `0` the type `Float`:

```swift
let m = max(f, d)                      // f: Float, d: Double: T is Double, which f widens to
let b: Float = max(0, 1)               // from the expected type: a Float call
let s: Seconds<Game> = seconds(0.5)    // from the expected type: C is Game
let n = max(0, 1)                      // from the literals' default: an Int call
hp = max(0, hp - amount)               // T is Float, from 'hp - amount', so 0 is a Float
```

## Equality and ordering

```swift
struct Tile(let x: Int32, let y: Int32): Hashable      // == and hash(into:) derived from the fields

struct Version(let major: Int, let minor: Int): Comparable {    // == derived; < written
    static func < (lhs: Version, rhs: Version) -> Bool {
        lhs.major < rhs.major || (lhs.major == rhs.major && lhs.minor < rhs.minor)
    }
}
```

**Three protocols declare `==`, `<` and hashing:**

- **`Equatable`** requires `==` and `!=`, and gives `!=` a default.
- **`Comparable: Equatable`** requires `<`, `<=`, `>` and `>=`, and gives each but `<` a default.
- **`Hashable: Equatable`** requires `hash(into:)`, which feeds std's hash state, a `Hasher`. It must give equal hashes for values that `==` calls equal.

    ```swift
    protocol Hashable: Equatable {
        func hash(into hasher: mutable Hasher)   // borrows self, feeds 'hasher', and returns nothing
    }
    ```

**The defaults are these, written in terms of `==` and `<`.** So a type with unordered values, such as `Float` with NaN, gets `>`, `<=` and `>=` right from `<` and `==` alone:

```swift
a != b    // default: !(a == b)
a > b     // default: b < a
a <= b    // default: a < b || a == b
a >= b    // default: b < a || a == b
```

**A type may replace any default with its own operator.**

**A struct or enum that declares `Equatable`, `Comparable` or `Hashable` gets `==` derived, and for `Hashable`, `hash(into:)`.** Each is derived only when the type doesn't write it, and when all of its fields or payloads conform: to `Equatable` for `==`, and to `Hashable` for `hash(into:)`. A derived member goes field by field in header order, and for an enum, takes the case and then its payload. So `Version` above writes only `<`. `<` is never derived, since no order is right for every type.

**Derived code reads only what a witness could** ([Conformances](protocols-and-generics.md#conformances)). A derived `==` or `hash(into:)` reads every stored field plainly. So it is derived over an `unsafe` field, or a union member that isn't safe to read, only when the conformance is declared `: unsafe P`. That declaration promises that such a read is valid and races with nothing.

**These types come with their conformances:**

- **Integers.** They are `Comparable` and `Hashable`.
- **`Bool`, raw pointers and `Handle`s.** They are `Hashable`.
- **`Half`, `Float` and `Double`.** They are `Comparable`, with IEEE 754's comparisons: a NaN is unequal to every value, itself included, and unordered.
- **Enums without payloads.** They are `Hashable` without declaring it, so `e == .missing` works on any of them.
- **Tuples and inline arrays.** A tuple is `Equatable`, `Hashable` or `Comparable` when each element is, comparing element by element in order, and `[N of T]` is the same when `T` is.
- **Optionals.** Every optional compares with `nil`: `x == nil` and `x != nil` test for a value, whatever `T` is. `T?` is `Equatable` or `Hashable` when `T` is.
- **Text.** `StaticString`, `StringView` and `String` are `Comparable` and `Hashable`. They compare their bytes, and order them byte by byte, a prefix before any longer text. `Name` is `Hashable` and compares its 64-bit hash.

**`Simd` vectors don't conform**, since their comparisons return masks ([04](../04-types/numbers-and-math.md#simd-and-math)).
