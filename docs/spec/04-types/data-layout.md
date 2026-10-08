# Plain and specialized data layouts

[04 · Types](../04-types.md)

Rayo normally lays out a value according to its fields. Systems code sometimes needs stronger guarantees about those bytes or a different way to store repeated values. The type's layout rules make those choices explicit, including plain data, trailing arrays and struct-of-arrays storage.

## Plain data: `Pod` and bit casts

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
- **open** imported C enums and flag enums whose raw type is an integer type, padding-free like it ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums));
- arrays and tuples of `Pod`;
- structs with no `deinit` whose stored fields are all `Pod`, all **as visible as the struct**, and none `unsafe`, and whose primary initializer is as visible as the struct too and not `unsafe` ([Initializers](structs.md#initializers)). An imported bitfield counts as [08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums) says;
- unions with no `deinit`, named or anonymous in a struct ([08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums)), whose members are all `Pod`, all as visible as the union, and none `unsafe`.

**These are not `Pod`:**

- `Bool`, which is 0 or 1, and Rayo enums and closed C enums, which hold one of their cases ([08](../08-c-interop/c-contract-and-embedding.md#what-c-must-uphold));
- pointers, which are never null ([Optionals](enums.md#optionals)), and `Handle`s, weak pointers and weak links, which hold only bits Rayo gave out ([08](../08-c-interop/c-contract-and-embedding.md#what-c-must-uphold));
- `Name`;
- owners of memory, since bytes taken as one would be a second owner of what it holds ([10](../10-errors-and-safety/unsafe-code.md#values-views-and-threads));
- a `Synchronized` type, or anything that holds one at any depth, since other threads write its bytes while a `Pod` read would load them plainly ([07](../07-concurrency/synchronization.md#the-synchronized-contract));
- a type the compiler builds, whose fields nothing names: a closure literal's or a task's state, or an interpolated literal's value ([09](../09-compile-time/reflection.md#what-reflection-can-read)).

**`@pod` waives only the visibility and `unsafe` conditions.** So it is a compile error on the types listed as not `Pod`, and on a struct or union that has a `deinit` or holds a type that isn't `Pod`.

**The visibility and `unsafe` conditions protect invariants, since a type that guards one must not be forged from bytes.** A field is as visible as its struct when it is `public` or the struct isn't. A primary initializer is, unless the struct is `public` and its header says `private init` ([11](../11-compilation-model.md#modules-and-names)). A `public` `Fraction` guards one, since its `private init` makes every other module pass the nonzero-denominator check ([Initializers](structs.md#initializers)). So it fails the conditions, and so do these, which `unchecked` code trusts:

```swift
struct SlotIndex(public unsafe let raw: UInt32)     // an unsafe field
struct SlotId unsafe init(public let raw: UInt32)   // an unsafe primary initializer
```

Each is `Pod` only through `@pod`, which states that every bit pattern is valid.

**Padding bytes are uninitialized, and a type with none is padding-free**, which the `const` `T.isPaddingFree` reports ([09](../09-compile-time/reflection.md#what-reflection-can-read)).

- **Unions.** A union is padding-free when every member is and fills it exactly. Bytes a member doesn't cover, including tail padding from `@align(N)`, count as padding.
- **Enums.** An enum, an optional included, is padding-free when each of its values sets every byte. So bytes that a case's payload doesn't fill, or that a `nil` leaves unset, count as padding: `UInt8?` isn't padding-free, and `Handle<T>?`, whose `nil` is all zero, is.
- **Bitfields.** In an imported struct or union, the bitfield bits [08](../08-c-interop/imports-and-inline-c.md#structs-unions-and-enums) lists count as padding too.

**Casts between `Pod` types depend on padding**, so that no uninitialized byte is read as data:

- **Bit casts.** `U(bitPattern: t)` between `Pod` types of equal size is safe when `t`'s type is padding-free.
- **Span casts.** `span.reinterpret(as: Vertex.self)` views a span of a `Pod` type `A` as a `Span<U>?` of a `Pod` type `U` of nonzero size, here `Vertex`, checking size divisibility and alignment once. A shared cast needs `A` padding-free, so every byte read is initialized. A mutable cast needs both types padding-free, since a store through a padded type leaves its padding unspecified while other views still see `A`.

## Variable-sized structs: `TrailingArray`

**`TrailingArray<Header, Element>` is one allocation of a `Header` followed by `n` `Element`s**, as a network packet or a C API with a flexible array member wants.

```swift
var msg = TrailingArray<PacketHeader, UInt8>(header: h, count: n, repeating: 0)
msg.header.kind = .snapshot
msg.elements[0..<4].copy(from: payload[0..<4]) // MutableSpan<UInt8> over the trailing storage; lengths checked
```

It is move-only, and owns its allocation, whose element count is fixed when it is made. It has a C representation when its header and element types both have one ([08](../08-c-interop/calling-rayo-from-c.md#c-representations)).

**The header starts the allocation, and the elements follow it.** The allocation is aligned for both types. The elements follow one `Element` stride apart, from the first multiple of `Element`'s alignment at or after the header's size. The allocation is at least as large as the header's size and as the elements' end, so the whole header lies inside it.

**When the header is a struct or tuple, the elements start instead where C puts a flexible array member of `Element`s after the header's fields**, as long as neither the header nor `Element` is or holds a `Synchronized` value. They replace any such member the header declares, and start:

- for a Rayo header, at the first multiple of `Element`'s alignment at or after the end of its last field ([Structs](structs.md#structs));
- for an imported one, at the offset the target's C ABI gives that member.

**That offset must be a multiple of `Element`'s alignment.** A packed imported header whose member C places lower, as `#pragma pack(1)` can, is a compile error as a `TrailingArray` header, since its elements couldn't be both where C reads them and aligned. So the elements can start inside the header's tail padding, or inside the storage unit of a bitfield that ends an imported header.

**A `Synchronized` value on either side keeps the two from sharing bytes.** It may write any of its bytes through a shared borrow, padding included, while the other side is read with plain loads.

**A struct or tuple header is written field by field, so its tail padding, where elements may lie, is never written.** `msg.header`'s `read` lends the header in place. Its `modify` yields it from a temporary and writes it back whole, except a struct or tuple header, which it writes field by field, each bitfield through its accessor. A whole store may write every byte of a value, padding included ([10](../10-errors-and-safety/unsafe-code.md#raw-accesses)). A view from the `modify` is access-bound ([02](../02-views-and-dependencies/projections-and-accessors.md#access-bound-projections)). Code that reaches the header through a pointer, C or `unsafe` Rayo, writes it the same way ([10](../10-errors-and-safety/unsafe-code.md#raw-accesses)).

## Struct of arrays: `SoA<T>`

**`SoA<T>` stores each field of a struct `T`, or each element of a tuple `T`, in its own buffer**, so a loop reads only the fields it touches, still with field syntax:

```swift
var particles = SoA<Particle>(capacity: 100_000)  // or SoA<Particle>(), as for List
particles.append(Particle(pos: p, vel: v, life: 2))

for p in &particles {                  // p is a row: one place per field
    p.pos += p.vel * dt                // touches only the pos and vel arrays
}
```

**`SoA<T>` is builtin, and its columns are `T`'s stored fields in declaration order**, private ones included, as `T.fields` lists them ([09](../09-compile-time/reflection.md#static-reflection)). A tuple's columns are `s.0`, `s.1`, and so on. An anonymous union is one field, so its members share a column. `SoA`'s own members, such as `count`, `capacity` and `append`, hide a field of the same name, whose column `s[field: f]` still reaches.

**Columns are views.** `s.life` returns a `Span` of the column's buffer in a shared context and a `MutableSpan` in an exclusive one ([Shared, mutable and consuming forms of one method](collections.md#shared-mutable-and-consuming-forms-of-one-method)), which a binding of `&particles.life` owns ([01](../01-values-and-ownership/bindings.md#lending-a-place-for-change)). The view depends on that column alone, a part of `s` disjoint from the other columns as a stored field is from its siblings ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)). So `&s.pos` and `s.vel` can be held at once.

**Subscripts reach columns by field.** `s[field: f]` returns one column, as `s.f` does, and `s[fields: (f1, f2)]` a tuple of columns. Marked `&`, `s[fields:]` gives each column in the kind of its pattern element:

```swift
let (var ts, vs) = &table.rows[fields: (tf, vf)]   // 'ts' is a MutableSpan, and 'vs' a Span
```

**Each element a `for` loop over `s` hands out, and `s[i]`, is a row.** A **row** is a view of one index across every column. It is shared or, through `&`, exclusive, as `Borrow<T>` and `MutableRef<T>` are for other collections ([Iteration](collections.md#iteration)). It has one projection per field of `T`, named as the field is, which lends that field's place in its column. Those places are disjoint, as a struct's stored fields are ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)), so `p.pos += p.vel * dt` writes one while it reads another. A row isn't a `T`: code reads and writes it field by field, and appending and removing move whole `T` values.

**Columns and rows obey the rules of `value[field]` at the use site.** Under those rules ([09](../09-compile-time/reflection.md#reflection-and-access-control)), a column is a `MutableSpan`, and a row's field can be written, only for a `var` field that could be assigned there. So a `let` field's column is a `Span` even in an exclusive context. A column of an `unsafe` field is available only inside `unsafe`, and a private field's column exists only where the field is visible. Appending and removing whole rows moves whole values, so it needs none of this.

**A growing operation grows every column or none.** When an allocation fails, `tryAppend` throws, and `append` panics, with every column as it was ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)).
