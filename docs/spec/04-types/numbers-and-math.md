# Numbers and math

[04 · Types](../04-types.md)

Numeric types have fixed representations, so their range, overflow and conversions can be specified exactly. SIMD values apply operations to several numbers at once, with their own layout and comparison rules.

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

**A number literal takes its type from its context**, whether it is written in decimal, hexadecimal, octal or binary, or with an exponent: `1_000`, `0xFF`, `0o17`, `0b1010`, `1e-3` ([Literals](collections.md#literals)).

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

**The only implicit numeric conversion is lossless widening along a fixed order.** Lossless means that the target type holds every value of the source exactly, so the conversion loses nothing. The order is fixed, so the conversion never makes the type checker search. It runs:

- from a signed integer type to a wider one, along `Int8 → Int16 → Int32 → Int64`, and from an unsigned one along `UInt8 → UInt16 → …`;
- from an unsigned integer type to a strictly wider signed one;
- from a floating-point type to a wider one, along `Half → Float → Double`;
- from an integer type of at most 16 bits to `Float`, and of 32 bits to `Double`, each of which holds its every value exactly: `Int8`, `Int16`, `UInt8` and `UInt16` to `Float`, and `Int32` and `UInt32` to `Double`.

**`Int` and `UInt` are distinct 64-bit types that sit in that order where `Int64` and `UInt64` do**: `Int32` widens to `Int`, and `UInt32` to `UInt` and `Int`. `Int` and `Int64` never convert implicitly into each other, since neither is wider.

**Every other conversion between number types is explicit.** Each explicit form says what it does with a value the target type can't hold exactly. Together they have a defined result for every input but one (below):

- **Between integer types.** The unlabeled form, such as `Int32(x)`, checks that the value fits. It panics where overflow checks are on, and keeps the low bits where they are off ([10](../10-errors-and-safety/checks-and-build-modes.md#the-checks)). The `truncating:` form always keeps the low bits, and the `clamping:` form saturates.
- **From a floating-point value.** `Int(f)` rounds toward zero. It panics on NaN, or on a value whose integer part doesn't fit, in every build, since targets' conversion instructions disagree on those. `Int(clamping: f)` saturates, and maps NaN to `0`.
- **To a floating-point type.** `Float(d)` of an `Int`, `Float(x)` of a `Double` and `Half(f)` of a `Float` round to nearest. An out-of-range value becomes an infinity of its sign, as IEEE 754 defines.

**The one input without a defined result is NaN or an out-of-range value, converted from a float to an integer inside an `unchecked` block**, which removes the conversion's check ([10](../10-errors-and-safety/checks-and-build-modes.md#unchecked-blocks)). Unchecked, that conversion's failure is undefined behavior ([10](../10-errors-and-safety/checks-and-build-modes.md#the-checks)).

### Integer overflow, division and shifts

```swift
func step(_ x: Int32, _ n: Int32) {
    let a = x + 1       // panics on overflow where overflow checks are on (10), wraps where they are off
    let b = x &+ 1      // always wraps
    let c = x +| 1      // saturates at Int32.max
    let d = x << n      // defined for every n: 0 once n reaches 32, a right shift for a negative n
    let e = x / n       // panics when n is 0, in every build
}

func pack(_ b: UInt8, _ n: Int, _ bit: UInt8) {
    let s = b << n                  // a UInt8: a shift has the type of the value it shifts
    let mask: UInt64 = 1 << bit     // the annotation, not 'bit', gives the 1 its type
}
```

**Every integer operation has a defined result for every operand, in every build and on every target.** The one exception is a division or remainder by zero inside an `unchecked` block, which removes its check ([10](../10-errors-and-safety/checks-and-build-modes.md#unchecked-blocks)).

- **Overflow.** `+ - *` and unary `-` panic on overflow where overflow checks are on, and wrap where they are off. A wrapped result is a wrong value but never an invalid one, and the next bounds check still catches a wrong index. So the overflow check is a diagnostic check, which a build or a scope may turn off ([10](../10-errors-and-safety/checks-and-build-modes.md#check-levels)). The wrapping operators `&+ &- &*` always wrap, and the saturating operators `+| -| *|` saturate.
- **Division.** `/` rounds toward zero, and `a % b` has `a`'s sign. Division and remainder by zero panic in every build, since, unchecked, their failure is undefined behavior ([10](../10-errors-and-safety/checks-and-build-modes.md#the-checks)). `Int.min / -1` overflows in every signed width, and follows the overflow rule: it wraps to `Int.min` where checks are off. `Int.min % -1` is `0` in every build.
- **Shifts.** The count may be of any integer type, and the result has the shifted value's type, so neither operand widens to the other: `b << n` above is a `UInt8`. The other shift rules fix the type of an untyped value, and the result of every count:
    - An untyped shifted value never takes its type from the count. It takes the expected type, else its default, `Int`. So `mask` above shifts a `UInt64`, not a `UInt8` that then widens.
    - `>>` is arithmetic on a signed type and logical on an unsigned one.
    - A negative count shifts the other way: `x << -n` is `x >> n`.
    - A count whose magnitude is at least the bit width, `Int.min` included, shifts every bit out. That gives `0`, or all ones for a right shift of a negative value.
    - A left shift drops bits past the top whatever the sign, so it never overflows.
    - The masking shifts `&<<` and `&>>` use only the count's low bits, `count & (bitWidth - 1)`, as an unsigned amount.

### Floating point

```swift
let p = a * b + c       // rounds twice, after * and after +: never fused into one multiply-add
let q = (a + b) + c     // never reassociated into a + (b + c), which can round differently
```

**Every `Half`, `Float` and `Double` operation, and every floating-point `Simd` lane operation, is one IEEE 754 operation rounded to its own type, in every build.** Nothing is kept in wider precision, contracted, as a multiply and an add are into one fused multiply-add, reassociated or otherwise rewritten. Subnormals are never flushed to zero. So `+ - * /`, square root, comparisons and conversions are bit-identical on every target, toolchain and build. Two things are left open: which NaN a NaN result is, and the results of functions that IEEE 754 doesn't require to be correctly rounded, such as `sin`.

```swift
let lo = min(x, Float.nan)              // NaN: min passes a NaN on
let lowest = minNumber(x, Float.nan)    // x: minNumber skips a NaN
let z = min(-0.0, 0.0)                  // -0.0, which counts as less than +0.0
```

**`min` and `max` of floating-point values are IEEE 754-2019's `minimum` and `maximum`**, for `Half`, `Float` and `Double`, as scalars and lane by lane in a vector ([SIMD and math](#simd-and-math)):

- if either operand is NaN, the result is NaN, and which NaN is left open, as for every NaN result;
- `-0` counts as less than `+0`.

So a NaN propagates instead of disappearing silently. Both operations are also commutative and associative, so a reduction's result doesn't depend on the order in which it combines lanes ([Reductions](#reductions)).

**`minNumber` and `maxNumber` are IEEE 754-2019's `minimumNumber` and `maximumNumber`**, which order `-0` and `+0` as `min` and `max` do but ignore a NaN operand. They return the other operand, and NaN only when both are NaN. They are commutative and associative too. So `min` and `max` never lose a NaN unnoticed, and code that marks missing values with NaN asks to skip them by naming `minNumber` or `maxNumber`.

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
if (a < Vec4(repeating: 8)).all { … }     // 'all' reduces the mask to one Bool
```

**The same type serves any data that one operation can handle several of at once.** A 3D position is a vector of 3 floats, and 64 bytes of text scanned for a delimiter are one `Simd<UInt8, 64>`, compared in one operation ([Masks](#masks)).

**A `Simd<T, N>` is `N` lanes of one type, which its operators work on lane by lane:**

- **Lane types and counts.** `Simd<T, N>` is builtin, over a number type `T`, or `Bool` for masks. It has any power of two from 1 to 64 lanes, or 3. The limit is 64 lanes since a mask of 64 lanes fits in one `UInt64` ([Masks](#masks)). `std.math`'s `Vec2`, `Vec4` and `IVec2` are aliases of `Simd<Float, 2>`, `Simd<Float, 4>` and `Simd<Int32, 2>`.
- **In generic code.** Generic code may name `Simd<T, N>` for its own `T` and `N`. Its `T` and lane count are then checked where they are known, at each instantiation, as a `static error` is ([09](../09-compile-time/constants-and-conditions.md#static-if-and-conditional-compilation)). Operations that compute with lanes, such as arithmetic, comparisons and reductions, need a concrete `T`. A load, a store, a shuffle or a swizzle only moves lanes, so it works for any lane type, a mask's `Bool` and a generic `T` included ([below](#shuffles-and-swizzles)).
- **Operators.** A scalar operand broadcasts to every lane, on either side: `v * 2`, `2 * v`. A comparison gives a mask ([below](#masks)). Integer lanes follow the integer rules ([above](#integer-overflow-division-and-shifts)) lane by lane, so `v / w` panics when any lane of `w` is 0.
- **`min` and `max`.** `min(a, b)` and `max(a, b)` of two vectors work lane by lane, and so do `minNumber` and `maxNumber` of two floating-point vectors. Integer lanes compare by value, and floating-point lanes follow the floating-point rules ([above](#floating-point)).
- **Lanes are never viewed.** A lane is read and assigned by swizzle or by index, and `v[i]` panics when `i` is out of range. No span or `Borrow` of a lane exists, so a vector lends nothing of its own bytes ([02](../02-views-and-dependencies/dependency-projection-and-results.md#shallow-values)).
- **Making a vector.** A vector comes from an array literal, such as `[1, 2, 3, 4]`, from `Vec4.zero` or `Vec4(repeating: 1)`, or from `Simd<T, N>(a, b, …)`. That initializer takes its `N` lanes in order, unlabeled and borrowed, and copies them, as `Vec2(x, y)` and `IVec2(1280, 720)` do.
- **Loads and stores.** `Simd<T, N>(loading: span, at: i)` reads `N` lanes from a `Span<T>`, starting at element `i`, and `v.store(into: &out, at: i)` writes them into a `MutableSpan<T>` there. Neither needs any alignment, since ordinary data is laid out for its elements, not for vectors. A 3-lane load or store touches 3 elements, never the padding lane.
- **Bounds.** A load or a store panics when `i` is negative or `i + N` exceeds the span's count, as indexing does. It is a bounds check, which only an `unchecked` block removes ([10](../10-errors-and-safety/checks-and-build-modes.md#unchecked-blocks)).

**`Simd` operations never become calls at run time, in any build**, since they are builtin. A library type gets the same by declaring its operations `@inline` ([11](../11-compilation-model.md#functions-that-are-never-calls-inline)), as `std.math`'s `Vec3` does.

**A target splits a vector wider than its vector registers into parts that fit**, and runs each operation on each part. Every lane gets the same result either way, since a lane operation reads only its own lanes, and a reduction combines lanes in its own fixed order ([Reductions](#reductions)). So every lane count works on every target, with more instructions where the registers are narrower.

### Vector layout

**A vector's lanes lie end to end, and its alignment is the smaller of its size and 64 bytes, on every target:**

| Type | Size | Alignment |
| --- | --- | --- |
| `Simd<Float, 4>` | 16 bytes | 16 |
| `Simd<UInt8, 64>` | 64 bytes | 64 |
| `Simd<Float, 32>` | 128 bytes | 64 |
| `Simd<Bool, 16>` | 16 bytes | 16 |
| `Simd<Float, 3>` | 16 bytes, the last 4 padding | 16 |

So a vector's layout is the same on every target, and no vector asks for more than 64 bytes of alignment, since none needs more. A vector's C representation takes the same alignment ([08](../08-c-interop/calling-rayo-from-c.md#c-representations)).

**Only the 3-lane form has padding**: it takes the room of four lanes, and its last lane is padding ([below](#vec3-and-three-lane-vectors)).

**A mask stores each lane as a `Bool`, one byte of 0 or 1**, so `Simd<Bool, N>` has `Simd<UInt8, N>`'s size and alignment. A target that keeps masks as bits in a register converts a mask when it stores one.

### Shuffles and swizzles

A **shuffle** builds a vector from lanes of one or two vectors, picked by a list of lane indices known at compile time. So one operation writes any permutation, broadcast or interleave:

```swift
let v: Simd<UInt8, 8> = [10, 11, 12, 13, 14, 15, 16, 17]
let w: Simd<UInt8, 8> = [20, 21, 22, 23, 24, 25, 26, 27]

let r = shuffle(v, [7, 6, 5, 4, 3, 2, 1, 0])          // [17, 16, 15, 14, 13, 12, 11, 10]
let b = shuffle(v, [2, 2, 2, 2])                      // a Simd<UInt8, 4>: lane 2, four times
let z = shuffle(v, w, [0, 8, 1, 9, 2, 10, 3, 11])     // [10, 20, 11, 21, 12, 22, 13, 23]
let bad = shuffle(v, [8, 0])                          // error: lane 8 of one 8-lane vector doesn't exist
```

**`shuffle(a, indices)` and `shuffle(a, b, indices)` take vectors of one type `Simd<T, N>` and an index list of type `[K of Int]`:**

- **Picking lanes.** Lane `i` of the result is lane `indices[i]` of `a` followed by `b`. An index `j` below `N` picks lane `j` of `a`, and an index from `N` to `2N - 1` picks lane `j - N` of `b`, as `8` and up do in `z` above.
- **The result.** It is a `Simd<T, K>`, so `K` must be a lane count. It may differ from `N`, so a shuffle also takes some of a vector's lanes, or repeats them into a wider vector.
- **Compile-time indices.** The index list is a `const` argument, which the compiler evaluates as it does a `const` initializer ([09](../09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const)). So an index outside the vectors is a compile error, and a shuffle never checks at run time.
- **Any lane type.** A shuffle only moves lanes and never computes with them, so it works for every lane type, as loads and stores do ([above](#simd-and-math)).

**Any function that can run at compile time can compute an index list.** In generic code the list is evaluated at each instantiation, since it may depend on that instantiation's `N` ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#checking-generic-code)):

```swift
func reversedLanes<let N: Int>() -> [N of Int] {      // ordinary code, run by the compiler
    var lanes: [N of Int] = .init(repeating: 0)
    for i in 0..<N { lanes[i] = N - 1 - i }
    return lanes
}

func reversed<T, let N: Int>(_ v: Simd<T, N>) -> Simd<T, N> {
    shuffle(v, reversedLanes<N>())                    // computed for each N, and fine for any T
}
```

**A swizzle is shorthand for a shuffle of one vector.** It is a property whose name lists up to four lanes among `x`, `y`, `z` and `w`, which stand for lanes 0 to 3 of a vector of any lane count:

- **Reads.** A swizzle of 2 to 4 lanes is the shuffle with those indices: `v.zyx` is `shuffle(v, [2, 1, 0])`, and `v.xxxx` is `shuffle(v, [0, 0, 0, 0])`. A swizzle of one lane is a lane read, a `T`: `v.y` is `v[1]`.
- **Writes.** A swizzle is assignable when no lane repeats. `v.xz = p` stores `p`'s two lanes into lanes 0 and 2 of `v`, as `v[0] = p[0]` and `v[2] = p[1]` would.
- **Missing lanes.** Naming a lane the vector doesn't have, such as `w` of a 3-lane vector, is a compile error.

### Masks

A comparison of vectors gives a **mask**, a `Simd<Bool, N>` whose lane `i` says whether the comparison holds in lane `i`. A delimiter scan loads 64 bytes at a time from any offset, compares them at once, and turns the mask into an integer to find the first match:

```swift
func firstNewline(in bytes: Span<UInt8>) -> Int? {
    var i = 0
    while i + 64 <= bytes.count {
        let chunk = Simd<UInt8, 64>(loading: bytes, at: i)    // any offset: no alignment needed
        let hits = (chunk == 10).bits                         // a UInt64: bit k is set where byte i + k is a newline
        if hits != 0 { return i + hits.trailingZeroCount }
        i += 64
    }
    for j in i..<bytes.count {                                // the last bytes, fewer than 64, one at a time
        if bytes[j] == 10 { return j }
    }
    return nil
}
```

**A mask chooses lanes, tests them or becomes bits:**

- **Choosing.** `select(mask, a, b)` takes lane `i` from `a` where the mask's lane `i` is true, and from `b` where it is false.
- **Testing.** `any` and `all` reduce a mask to one `Bool`: whether some lane is true, and whether every lane is.
- **Bits.** `mask.bits` holds lane `i` at bit `i` of an unsigned integer: a `UInt8` for up to 8 lanes, and a `UInt16`, `UInt32` or `UInt64` for 16, 32 or 64. The bits above the last lane are 0. Every mask fits in a `UInt64`, which is why a vector has at most 64 lanes.

### Reductions

A **reduction** combines a vector's lanes into one value. A mask has `any`, `all` and `bits` ([above](#masks)), and a vector of numbers has these:

- `sum()`, the lanes added together;
- `min()` and `max()`, the least and greatest lane, as `min` and `max` compare them ([Floating point](#floating-point));
- on floating-point lanes, `minNumber()` and `maxNumber()`, which skip NaN lanes as `minNumber` and `maxNumber` do.

**Every reduction combines lanes in one fixed order, the same on every target**, since a floating-point sum's rounding depends on its order and Rayo never reassociates ([Floating point](#floating-point)):

- **Halves.** A vector of `N` lanes, where `N` is a power of two from 2 up, combines its low half with its high half lane by lane: lane `i` with lane `i + N/2`, the lower lane as the left operand. That gives a vector of `N/2` lanes, which reduces the same way until one lane is left.
- **One lane.** A 1-lane vector reduces to its lane.
- **Three lanes.** A 3-lane vector reduces as `(v[0] ⊕ v[1]) ⊕ v[2]`, where `⊕` is the reduction's operation, and its padding lane is never read.

```swift
let total = v.sum()    // for 8 lanes: ((v[0] + v[4]) + (v[2] + v[6])) + ((v[1] + v[5]) + (v[3] + v[7]))
```

**An integer sum checks each of its additions as `+` does** ([above](#integer-overflow-division-and-shifts)): it panics on overflow where overflow checks are on, and wraps where they are off. The order is fixed, so whether a sum panics is the same on every target:

```swift
let d: Simd<Int8, 4> = [100, 100, -100, -100]
let t = d.sum()        // 0: (100 + -100) + (100 + -100) never overflows, though 100 + 100 would
```

**The order matters only to `sum()`.** `min`, `max`, `minNumber` and `maxNumber` are commutative and associative, so their reductions give the same result in any order ([Floating point](#floating-point)).

### `Vec3` and three-lane vectors

**Three-lane vectors come in two layouts**: the builtin `Simd<T, 3>` takes the room of four lanes, and `std.math`'s `Vec3` the room of three:

```swift
struct Light(var pos: Vec3, var radius: Float)              // 16 bytes: three floats, then one
struct Light4(var pos: Simd<Float, 3>, var radius: Float)    // 32 bytes: the vector alone takes 16, aligned to 16
```

**`Simd<T, 3>` has `Simd<T, 4>`'s size and alignment, and its fourth slot is padding.** So `Simd<T, 3>` is `Pod` when `T` is, but never padding-free ([Plain data: `Pod` and bit casts](data-layout.md#plain-data-pod-and-bit-casts)).

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

It offers `Simd<Float, 3>`'s operators, swizzles and reductions, so for 3D math the two differ only in layout. `shuffle` takes only `Simd` vectors. Its fields are `public`, so it is `Pod` ([Plain data: `Pod` and bit casts](data-layout.md#plain-data-pod-and-bit-casts)).
