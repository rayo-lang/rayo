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
3. From the result type of a closure literal argument, once the parameter's type has given the literal its parameter types. Closure literals that bind it to different types combine as typed arguments do in step 1.
4. From the literals' default. The literal arguments left to bind it take one default together, as an array literal's elements do ([04](../04-types/collections.md#literals)).

**A static call or an initializer on a generic type written without type arguments binds the type's parameters from the call**, in the same four ways, as a generic function's parameters are bound. So `Thread.start { 0 }` binds `Thread`'s `R` from its closure ([07](../07-concurrency/thread-work.md#work-that-outlives-the-caller-threads)), while `Channel<Request>.make(capacity: 64)` writes its argument.

**A closure literal binds through the type its body gives it, which the rule for a bare `!` works out** ([10](../10-errors-and-safety/typed-errors.md#what-a-failure-type-names)):

- **Its success type** is the type of what its `return`s or its single expression give. A `Result` it returns whole gives its success type, whether alone or beside plain values. A body that is no single expression and has no `return` gives `Void`, even when it never completes, as a `while true` loop doesn't.
- **Its failure type** is the union of what its body propagates, a `Result` returned whole included.
- **A pair `R!E`** in the parameter's type binds from those two types by the pair rule there. So a literal that can't fail binds `E` to `Never`.
- **An untyped literal it returns**, such as `1`, binds nothing. It counts as a literal argument, which leaves the type parameter to step 4.

```swift
let half = catchPanic { 1 } recover: { _ in 2.5 }    // both results are literals, so step 4 makes R a Double
```

**An expected type that isn't a `Result` binds only the success type of a result type `R!E`.** The match binds `R` from it, and leaves `E` to the arguments, as `try` leaves an expected failure type open ([10](../10-errors-and-safety/typed-errors.md#propagating-errors-with-try)). Where `E` then binds to `Never`, the call is an `R` ([10](../10-errors-and-safety/typed-errors.md#what-a-failure-type-names)), which fits. Otherwise the call is a `Result`, which doesn't, and the error says to write `try`:

```swift
let caught: Panic? = catchPanic { piece(); return nil } recover: { p in copy p }   // R is Panic?; neither closure fails, so EB and ER are Never
let level: Level = catchPanic { try loadLevel(path) } recover: { _ in Level() }    // error: the call is a Level!(IoError | ParseError); write 'try'
```

**Each untyped argument then takes its parameter's type.** The first four calls below bind `T` or `C` in the first, second and last of those ways, and the last call gives its untyped `0` the type `Float`:

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
- **`Comparable: Equatable`** requires `<`, `<=`, `>`, `>=`, and, of a copyable type, the methods `min(_:)` and `max(_:)`, and gives each but `<` a default. The methods borrow both values and return a copy of the lesser or the greater, as `..<` copies its operands in (above):

    ```swift
    func min(_ other: Self) -> Self where Self: Copyable
    func max(_ other: Self) -> Self where Self: Copyable
    ```
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
a.min(b)  // default: b when b < a, else a
a.max(b)  // default: a when b < a, else b
```

**Every witness of `min` returns `self`, and every witness of `max` returns `other`, when neither operand is less than the other in the order they use**, as the defaults do. That order is `<` for every type but `Half`, `Float` and `Double`, whose witnesses put `-0` below `+0` ([04](../04-types/numbers-and-math.md#floating-point)). A NaN operand is never a tie: the float witnesses give NaN for it. Values that tie can still differ, so the rule fixes which one a call returns:

```swift
struct Ranked(let rank: Int, let id: UInt32): Comparable {       // compares on its rank alone
    static func == (lhs: Ranked, rhs: Ranked) -> Bool { lhs.rank == rhs.rank }
    static func < (lhs: Ranked, rhs: Ranked) -> Bool { lhs.rank < rhs.rank }
}

let a = Ranked(rank: 1, id: 7)
let b = Ranked(rank: 1, id: 9)
let lo = a.min(b)    // a, with id 7: the two tie, so min returns self
let hi = a.max(b)    // b, with id 9: max returns other
```

**A type may replace any default with its own operator or method.** `Half`, `Float` and `Double` replace `min` and `max` with IEEE 754-2019's `minimum` and `maximum`, so that a NaN operand gives NaN and `-0` counts as less than `+0` ([04](../04-types/numbers-and-math.md#floating-point)).

**The free functions `min(a, b)` and `max(a, b)` call `a.min(b)` and `a.max(b)`**, as `max(0, 1)` and `max(f, d)` above do. So generic code over `Comparable & Copyable` gives the same result as concrete code, bit for bit, for every type it is instantiated with. They borrow their arguments, so a place passed to them stays usable:

```swift
func min<T: Comparable & Copyable>(_ a: T, _ b: T) -> T { a.min(b) }
func max<T: Comparable & Copyable>(_ a: T, _ b: T) -> T { a.max(b) }
```

**A move-only `Comparable` type, such as `String`, has no `min` or `max`**, since neither can return a copy of a borrowed value of it ([Protocols and generics](protocols-and-generics.md#protocols-and-generics)). Code compares such values with `<` and moves the one it keeps.

**The methods share their names with static properties such as `Int.min` and `Int.max`**, which they may, since static and instance members are separate namespaces ([Static and instance members](functions-and-closures.md#static-and-instance-members)).

**A struct or enum that declares `Equatable`, `Comparable` or `Hashable` gets `==` derived, and for `Hashable`, `hash(into:)`.** Each is derived only when the type doesn't write it, and when all of its fields or payloads conform: to `Equatable` for `==`, and to `Hashable` for `hash(into:)`. A derived member goes field by field in header order, and for an enum, takes the case and then its payload. So `Version` above writes only `<`. `<` is never derived, since no order is right for every type.

**Derived code reads only what a witness could** ([Conformances](protocols-and-generics.md#conformances)). A derived `==` or `hash(into:)` reads every stored field plainly. So it is derived over an `unsafe` field, or a union member that isn't safe to read, only when the conformance is declared `: unsafe P`. That declaration promises that such a read is valid and races with nothing.

**These types come with their conformances:**

- **Integers.** They are `Comparable` and `Hashable`.
- **`Bool`, raw pointers and `Handle`s.** They are `Hashable`.
- **`Half`, `Float` and `Double`.** They are `Comparable`, with IEEE 754's comparisons: a NaN is unequal to every value, itself included, and unordered. Their `min` and `max` methods are IEEE 754-2019's `minimum` and `maximum` ([04](../04-types/numbers-and-math.md#floating-point)).
- **Enums without payloads.** They are `Hashable` without declaring it, so `e == .missing` works on any of them.
- **Tuples and inline arrays.** A tuple is `Equatable`, `Hashable` or `Comparable` when each element is, comparing element by element in order, and `[N of T]` is the same when `T` is.
- **Optionals.** Every optional compares with `nil`: `x == nil` and `x != nil` test for a value, whatever `T` is. `T?` is `Equatable` or `Hashable` when `T` is.
- **Text.** `StaticString`, `StringView` and `String` are `Comparable` and `Hashable`. They compare their bytes, and order them byte by byte, a prefix before any longer text. `Name` is `Hashable`: two are equal exactly when their texts are, though `==` never reads the text ([04](../04-types/collections.md#collections-and-strings)).

**`Simd` vectors don't conform**, since their comparisons return masks ([04](../04-types/numbers-and-math.md#simd-and-math)).
