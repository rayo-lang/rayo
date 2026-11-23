# Plain and specialized data layouts

[04 · Types](../04-types.md)

Rayo normally lays out a value according to its fields. Systems code sometimes needs stronger guarantees about those bytes or a different way to store repeated values. The type's layout rules make those choices explicit, from the size every type has to plain data, trailing arrays and struct-of-arrays storage.

## Sizes fixed when the program is built

```swift
let w: [4 of Float] = [0.1, 0.2, 0.3, 0.4]   // 16 bytes: the count is part of the type
let names = alloc ["ana", "bo"]              // a List: a fixed-size value, with its elements in storage it allocated
let first: &Text = names[0]                  // a pointer and a length, whatever the text's length
```

**Every sized type has a size and an alignment fixed when the program is built**, which `T.size` and `T.alignment` read ([09](../09-compile-time/reflection.md#what-reflection-can-read)). So any value can live in a field, in an array or in a register, and on the stack up to a bound ([below](#the-largest-value-on-the-stack)), and a move copies a number of bytes known from its type ([01](../01-values-and-ownership/moves-copies-destruction.md#moves)). A generic function is compiled for each type it is called with, so its type parameters have fixed sizes too ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#instantiation)).

**The unsized types have no size of their own, so they have no values that sit in a place by themselves:**

- **`[T]`, `Text` and `any P`**, which code holds only behind a value of fixed size that refers to them ([01](../01-values-and-ownership/references.md#unsized-types));
- **an `@opaque` type**, a C type whose layout Rayo doesn't know or whose members it can't map, usable only behind a pointer ([08](../08-c-interop/imports-and-inline-c.md#what-imports-as-what)).

`T.size` and `T.alignment` of an unsized type are compile errors. No type parameter stands for one, so every generic body may rely on its types having a size ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#type-parameters-stand-for-sized-types)).

**No value's size depends on what it holds.** A count whose bound is fixed when the program is built is part of the type, and the elements lie inside the value. That bound is an array's `N` ([Tuples, ranges and arrays](collections.md#tuples-ranges-and-arrays)), or the capacity of an `InlineList` or of std's `FixedString`, which may hold fewer ([Collections and strings](collections.md#collections-and-strings)). A count with no such bound puts the elements outside the value, which reaches them through a fixed-size part:

- **an owner**, such as a `List`, a `String` or a `TrailingArray`, holds them in storage it allocated ([06](../06-memory-and-allocators/allocator-basics.md#allocating-with-alloc));
- **a reference to an unsized run**, a `&[T]` or a `&Text`, holds a pointer to them and their count, and lends them from wherever they lie ([01](../01-values-and-ownership/references.md#layout)).

### The largest value on the stack

```swift
func main() {
    let grid: [268435456 of Int] = .init(repeating: 0)   // error: 2^31 bytes, one more than a value on the stack takes
    let row: [1024 of Int] = .init(repeating: 0)          // fine: 8 KiB
}
```

**One value on the stack takes at most 2^31 − 1 bytes.** That is `CPtrDiff.max` on a target with 32-bit pointers ([11](../11-compilation-model.md#what-a-target-must-provide)). So a program whose values fit on one target's stack fits on every target's. The values on the stack are a function's:

- locals;
- parameters;
- result, which lies on its caller's stack;
- temporaries, each of which holds a value that no local holds, such as a call's result whose field the code reads, or the value that `_ =` drops.

**A larger value is a compile error where the source gives its type**: at a local's type annotation, or at its value where it has none, and at a parameter's or a result's written type. A temporary's error is at the expression that makes it. A type may still be larger than the bound, since a value of it that never lies on the stack takes no stack.

**A function's values together have no bound.** A run that has too little stack left for them ends the program, as any running out of stack does ([10](../10-errors-and-safety/panics.md#what-ends-the-program)).

## Plain data: `Pod` and bit casts

**A type where any bytes make a valid value is `Pod`** ("plain old data"), so bytes from a file or a packet can be used as one:

```swift
public struct Vertex(public var pos: Vec3, public var normal: Vec3, public var uv: Vec2)     // every field Pod and public: Pod

let f: Float = 1.5
let bits = UInt32(bitPattern: f)                      // a safe bit cast: Float has no padding
if let verts = bytes.reinterpret(as: Vertex.self) {   // a '&[UInt8]' to a '(&[Vertex])?', checked once
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
- pointers and references, which are never null ([Optionals](enums.md#optionals)), and `Handle`s, weak pointers and weak links, which hold only bits Rayo gave out ([08](../08-c-interop/c-contract-and-embedding.md#what-c-must-uphold));
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
- **Run casts.** `bytes.reinterpret(as: Vertex.self)` refers to a run of a `Pod` type `A` as a `(&[U])?` of a `Pod` type `U` of nonzero size, here `Vertex`, checking size divisibility and alignment once. Its alignment check is an alignment query, so it runs at compile time for a `U` aligned no more than the run's allocation ([10](../10-errors-and-safety/unsafe-code.md#raw-pointers)). This shared cast needs `A` padding-free, so every byte read is initialized.
- **Mutable run casts.** `bytes.mutableReinterpret(as: Vertex.self)` gives a `(mutable &[U])?`, checked the same way ([Shared and mutable views of one collection](collections.md#shared-and-mutable-views-of-one-collection)). It needs both types padding-free, since a store through a padded type leaves its padding unspecified while other references still see `A`.

## A header and trailing elements: `TrailingArray`

**`TrailingArray<Header, Element>` is one allocation of a `Header` followed by `n` `Element`s**, as a network packet or a C API with a flexible array member wants.

```swift
var msg = alloc TrailingArray<PacketHeader, UInt8>(header: h, count: n, repeating: 0)
msg.header.kind = .snapshot
msg.elements[0..<4].copy(from: payload[0..<4])  // a '[UInt8]' place in the trailing storage; lengths checked
```

It is move-only, and owns its allocation, whose element count is fixed when it is made. `msg.elements` is the elements as a `[Element]` place, with a `borrow` and a `mutate` ([Runs of elements](collections.md#runs-of-elements)). **`Header` must be copyable**, since the header is read and written as a value (below). It has a C representation when its header and element types both have one ([08](../08-c-interop/calling-rayo-from-c.md#c-representations)).

**The header starts the allocation, and the elements follow it.** The allocation is aligned for both types. The elements follow one `Element` stride apart, from the first multiple of `Element`'s alignment at or after the header's size. The allocation is at least as large as the header's size and as the elements' end, so the whole header lies inside it.

**When the header is a struct or tuple, the elements start instead where C puts a flexible array member of `Element`s after the header's fields**, as long as `Element` neither is nor holds a `Synchronized` value. They replace any such member the header declares, and start:

- for a Rayo header, at the first multiple of `Element`'s alignment at or after the end of its last field ([Structs](structs.md#structs));
- for an imported one, at the offset the target's C ABI gives that member.

**That offset must be a multiple of `Element`'s alignment.** A packed imported header whose member C places lower, as `#pragma pack(1)` can, is a compile error as a `TrailingArray` header, since its elements couldn't be both where C reads them and aligned. So the elements can start inside the header's tail padding, or inside the storage unit of a bitfield that ends an imported header.

**A `Synchronized` element keeps the elements from sharing the header's bytes.** It may write any of its bytes through a shared borrow, padding included, while the header is read with plain loads. The header itself holds no `Synchronized` value, since every such value is move-only ([01](../01-values-and-ownership/moves-copies-destruction.md#types-that-are-always-move-only)).

**A struct or tuple header is written field by field, so its tail padding, where elements may lie, is never written.** A whole store may write every byte of a value, padding included ([10](../10-errors-and-safety/unsafe-code.md#raw-accesses)), and a `mutate` would let any code store the header whole. So `msg.header` is a value property, which is why `Header` must be copyable: its `get` returns a copy of the header, and its `set` writes a new one back ([02](../02-views-and-dependencies/place-and-value-properties.md#value-properties-get-and-set)). Code that reaches the header through a pointer, C or `unsafe` Rayo, writes it the same way ([10](../10-errors-and-safety/unsafe-code.md#raw-accesses)).

**The `set` writes a struct or tuple header field by field, each bitfield through its accessor, and any other header whole.** A scoped header can be assigned but not otherwise changed, since the copy the `get` returns depends on `msg`, which the `set` changes ([02](../02-views-and-dependencies/place-and-value-properties.md#value-properties-get-and-set)).

## Struct of arrays: `SoA<T>`

**`SoA<T>` stores each field of a struct `T`, or each element of a tuple `T`, in its own buffer**, so a loop reads only the fields it touches, still with field syntax:

```swift
var particles = alloc SoA<Particle>(capacity: 100_000)  // or alloc SoA<Particle>(), as for List
particles.append(Particle(pos: p, vel: v, life: 2))

for p in mutable &particles {          // p is a row: one place per field
    p.pos += p.vel * dt                // touches only the pos and vel arrays
}
```

**`SoA<T>` is builtin, and its columns are `T`'s stored fields in declaration order**, private ones included, as `T.fields` lists them ([09](../09-compile-time/reflection.md#static-reflection)). A tuple's columns are `s.0`, `s.1`, and so on. An anonymous union is one field, so its members share a column. `SoA`'s own members, such as `count`, `capacity` and `append`, hide a field of the same name, whose column `s[field: f]` still reaches.

**Columns are places.** `s.life` is the column's buffer as a `[Float]` place, a place property with a `borrow` and a `mutate`. So `&s.life` is a `&[Float]`, and `mutable &s.life` a `mutable &[Float]` ([Shared and mutable views of one collection](collections.md#shared-and-mutable-views-of-one-collection)). A reference to a column depends on that column alone, a part of `s` disjoint from the other columns, as a stored field is from its siblings ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)). So `mutable &s.pos` and `&s.vel` can be held at once:

```swift
var lives = mutable &particles.life    // a 'mutable &[Float]' of one column
let vels = &particles.vel              // a '&[Vec3]' of another, held at the same time
lives[0] -= 1
```

**Subscripts reach columns by field.** `s[field: f]` is one column, a place with both accessors, as `s.f` is. `s[fields: (f1, f2)]` hands out a tuple of shared references to several columns, and `s[mutableFields: (f1, f2)]` a tuple of mutable references. A tuple of references is a value, not a place, so its two forms have two names, as a method's do ([Shared and mutable views of one collection](collections.md#shared-and-mutable-views-of-one-collection)):

```swift
var (ts, vs) = table.rows[mutableFields: (tf, vf)]  // 'ts' and 'vs' are mutable references to two distinct columns
```

**Each element that a loop over `&s` or `mutable &s` hands out is a row.** A **row** is a value that lends one index across every column: shared from `&s`, and exclusive from `mutable &s`. The loop name owns each row, as it owns a chunk ([Iteration](collections.md#iteration)). `s.row(i)` and `s.mutableRow(i)` hand out the row at index `i` the same way. A row has one place property per field of `T`, named as the field is, which lends that field's place in its column.

**A shared row's field places have only a `borrow`.** So a row from `&s` or `s.row(i)` reads its fields, and `mutable &` of one, or a write through it, is a compile error. Only a row from `mutable &s` or `s.mutableRow(i)` lends its fields with `mutable &`, since only it holds `s` exclusively.

**A row's places are disjoint, as a struct's stored fields are** ([01](../01-values-and-ownership/exclusivity.md#which-places-overlap)), so `p.pos += p.vel * dt` writes one while it reads another. A row isn't a `T`: code reads and writes it field by field, and appending and removing move whole `T` values.

**Columns and rows obey the rules of `value[field]` at the use site.** Under those rules ([09](../09-compile-time/reflection.md#reflection-and-access-control)), a column can be lent with `mutable &`, and a row's field written, only for a `var` field that could be assigned there. So a `let` field's column has only a `borrow`, and `mutable &` of it, or `s[mutableFields:]` naming it, is a compile error. A column of an `unsafe` field is available only inside `unsafe`, and a private field's column exists only where the field is visible. Appending and removing whole rows moves whole values, so it needs none of this.

**A growing operation grows every column or none.** When an allocation fails, `tryAppend` fails with `AllocError`, with every column as it was, and `append` ends the program ([06](../06-memory-and-allocators/allocation-lifecycle.md#allocation-failure)).
