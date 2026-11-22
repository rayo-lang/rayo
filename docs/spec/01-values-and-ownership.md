# 01 · Values and ownership

Ownership answers a basic question about every value: who is responsible for it? Code can hand a value to a new owner, make a separate copy, or borrow it for a time. Those choices affect when the value is destroyed and which parts of the program may use it. This chapter defines the operations and the access rules that keep them safe.

```swift
struct Enemy(var pos: Vec3, var hp: Float)

var a = Enemy(pos: .zero, hp: 100)
var b = consume a                  // a move: 'b' takes over the enemy, and 'a' can't be used any more
var c = copy b                     // a copy, written out: Enemy is copyable, so this is a memcpy
c.hp = 50                          // 'b' is unchanged
var hp = b.hp                      // a copy, not written: a Float is implicitly copyable
ref let seen = &b                  // a borrow: a read-only name for 'b', nothing copied
print("hp \(seen.hp)")

func heal(_ e: mutable &Enemy) { e.hp = 100 }
heal(mutable &b)                   // lends 'b' to heal, which changes it in place: no copy
```

In this example, `a` hands its enemy to `b`, `copy b` makes a separate value in `c`, and `hp` gets a copy of `b.hp` with nothing written, since a `Float` is implicitly copyable. `seen` names `b` where it lies, and `heal` changes `b` through a mutable reference. The following rules explain why each operation leaves a different set of names usable.

A **place** is storage that holds a value: a local, a global, a parameter or a temporary, or a part of one, such as `enemy.hp` or `list[i]`.

**Every value has one owner**, which decides when the value is destroyed. The exception is reference counting: `Shared<T>` lets several owners share one value, and the last owner to let go destroys it ([06](06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)). Code that uses a value without owning it **borrows** it, through a reference: `&b` lends `b` shared, and `mutable &b` lends it for change ([References](01-values-and-ownership/references.md#references)).

**A second value exists only where the code or the value's type asks for one:**

- with `copy` or `clone()` ([Copies](01-values-and-ownership/moves-copies-destruction.md#copies));
- by taking a value of an implicitly copyable type, such as an `Int`, from a place ([Implicit copies](01-values-and-ownership/moves-copies-destruction.md#implicit-copies));
- by taking a copyable `const` ([Constants](01-values-and-ownership/moving-values-out.md#constants));
- through an operation that copies its operands ([Operations that copy](01-values-and-ownership/moves-copies-destruction.md#operations-that-copy)).

## Tiers of checking

Rayo checks each pattern of memory use at one of three levels, its **tiers**: statically, by the compiler; dynamically, by a check at each use; or not at all, in `unsafe` code, `unchecked` blocks and C.

**Each pattern is checked in the cheapest tier that can check it.** A pattern the static checker can't prove is checked at run time, in the dynamic tier. It is never forbidden for that reason, and never forced into `unsafe`.

| Tier | Mechanisms | Checked | Cost |
| --- | --- | --- | --- |
| **Static** | Values, moves, references and the borrows they make, scoped values, dependencies | By the compiler, inside one function body | Zero |
| **Dynamic** | `Handle<T>` into pools; `UniquePointer<T>` + `WeakPointer<T>` for objects; `WeakShared<T>` links to reference-counted values; `Slice<T>` of a buffer; thread-local `var`s; the locks of `Synchronized` types ([07](07-concurrency/synchronization.md#atomics-and-locks)); an owning value's allocator word ([06](06-memory-and-allocators/arena-safety.md#opening-an-owning-value-checks-it)) | At each use: a stale link reads `nil` or panics instead of dangling, and conflicting uses panic or wait instead of racing | A check per use, visible in the type, or for a thread-local in its `@threadlocal` declaration |
| **Unsafe** | `*T` raw pointers and raw memory, calls into C, `unchecked`, and the other operations that 10 lists ([10](10-errors-and-safety/unsafe-code.md#what-needs-unsafe)) | Not checked | Zero |

**Safe code** is the code of the first two tiers: everything outside `unsafe` code, `unchecked` blocks and C. It has no undefined behavior ([11](11-compilation-model.md#what-the-language-leaves-open)).

## Subchapters

- [Moving, copying and destroying values](01-values-and-ownership/moves-copies-destruction.md)
- [References](01-values-and-ownership/references.md)
- [Parameters](01-values-and-ownership/parameters.md)
- [Bindings](01-values-and-ownership/bindings.md)
- [Moving values out](01-values-and-ownership/moving-values-out.md)
- [The law of exclusivity](01-values-and-ownership/exclusivity.md)
