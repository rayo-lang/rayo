# Numbers and math

[04 · Types](../04-types.md)

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

**A `Simd<T, N>` is `N` lanes of one type, which its operators work on lane by lane:**

- **Lane types and counts.** `Simd<T, N>` is builtin, over a number type `T`, or `Bool` for masks, with 2, 3, 4, 8 or 16 lanes. It is stored with no padding and aligned to its size, except the 3-lane form ([below](#vec3-and-three-lane-vectors)). `std.math`'s `Vec2`, `Vec4` and `IVec2` are aliases of `Simd<Float, 2>`, `Simd<Float, 4>` and `Simd<Int32, 2>`.
- **In generic code.** Generic code may name `Simd<T, N>` for its own `T` and `N`. Its `T` and lane count are then checked where they are known, at each instantiation, as a `static error` is ([09](../09-compile-time/constants-and-conditions.md#static-if-and-conditional-compilation)). The lane operations need a concrete `T`.
- **Operators.** A scalar operand broadcasts to every lane, on either side: `v * 2`, `2 * v`. A comparison returns a `Simd<Bool, N>` mask for `select(mask, a, b)`, and a mask's `any` and `all` reduce it to one `Bool`. Integer lanes follow the integer rules ([above](#integer-overflow-division-and-shifts)) lane by lane, so `v / w` panics when any lane of `w` is 0.
- **Swizzles.** A swizzle is a property whose name lists lanes among the first four, `x`, `y`, `z` and `w`, as `v.zyx` and `v.xxxx` do. A swizzle of one lane is a `T`, and of 2 to 4 lanes a `Simd<T, k>`. It is assignable when no lane repeats, as in `v.xz = p`. Naming a lane the vector doesn't have, such as `w` of a 3-lane vector, is a compile error.
- **Lanes are never viewed.** A lane is read and assigned by swizzle or by index, and `v[i]` panics when `i` is out of range. No span or `Borrow` of a lane exists, so a vector lends nothing of its own bytes ([02](../02-views-and-dependencies/dependency-projection-and-results.md#shallow-values)).
- **Making a vector.** A vector comes from an array literal, such as `[1, 2, 3, 4]`, from `Vec4.zero` or `Vec4(repeating: 1)`, or from `Simd<T, N>(a, b, …)`. That initializer takes its `N` lanes in order, unlabeled and borrowed, and copies them, as `Vec2(x, y)` and `IVec2(1280, 720)` do.

**`Simd` operations never become calls at run time, in any build**, since they are builtin. A library type gets the same by declaring its operations `@inline` ([11](../11-compilation-model.md#functions-that-are-never-calls-inline)), as `std.math`'s `Vec3` does.

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

It offers `Simd<Float, 3>`'s operations, so the two differ only in layout. Its fields are `public`, so it is `Pod` ([Plain data: `Pod` and bit casts](data-layout.md#plain-data-pod-and-bit-casts)).
