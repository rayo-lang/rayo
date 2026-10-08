# Reflection and systems patterns

[Hard cases](../hard-cases.md)

## H. Compile time and reflection

**Rayo's compile-time code has three parts: `const` evaluation, `static if` and `static for`, and static reflection** ([09](../09-compile-time.md)). These cases ask for what other languages write with macros or an external generator, written instead as library code.

### H1 · Loading data written by older versions of its types

**Load data written by an older version of a program's types**, as a save game from version 3 is loaded into version 7, or as a hot reload carries live values into new code. Fields were renamed, added, retyped, and removed across versions, and enum cases removed. The second criterion's migration is this one:

```swift
let migrated = T.construct { static field in consume old[field] }   // builds each field by moving it out of 'old'
```

- **Must accept** a reflection-driven loader plus per-type migration hooks, written as a library without a macro system or any language feature specific to loading.
- **Must accept** a migration that rebuilds a value field by field from an owned old one, as above, for a type with no `deinit` that holds `List`s.

### H3 · Registration without macros

**Every type of some kind must be registered in a global registry at startup**, as C++ does with static-init macros. Safe code has no unsynchronized mutable global, since every thread can reach a global ([07](../07-concurrency/global-state.md#global-state)).

- **Must accept** an idiom with no unsynchronized global state.

### H4 · Generated types

**Libraries need types generated from other types' declarations.** A network replication layer, for one, sends only the fields of an object that changed since the last update, so for every type it needs a record with one optional per replicated field ([09](../09-compile-time.md)). Three kinds of generated types are needed:

1. For every struct with fields marked by an attribute, such as `@Replicated`, a library needs a `Delta<T>` holding one optional per marked field, under the field's own name, plus a generic `diff` and `apply`, and it serializes each delta.
2. A library needs `Overrides<T>`, with every field optional.
3. A library needs one enum with a case per type in another module that conforms to a protocol.

The last criterion's `Node` holds a type generated from it:

```swift
struct Node(var pending: Delta<Node>)      // a field whose type is generated from Node itself
```

- **Must accept** each written once, as library code with no macros, no external generator and no per-type hand-written code, serialization included. Concrete code names the generated members directly (`delta.hp`), and generic code reaches them through reflection.
- **Must hold:** `TypeInfo` and reflection see generated types as they see written ones.
- **Must accept** two closures of one `join` writing two generated fields of one `Delta<Enemy>`, and `Node` above.

---

## I. Systems patterns that must not be forbidden

**Each of these is ordinary in C or C++.** Report the tier and the ceremony next to the C++ version.

### I1 · Pointers between long-lived objects

**A value points at another that outlives it**, one part of a program holds pointers to three others, and two values point at each other and both mutate through the link. In C++:

```cpp
struct Camera;
struct Player { Camera* camera; Vec3 pos; };
struct Camera { Player* target; float zoom; };
```

In Rayo, a view of memory that can be freed, such as a `Span`, can't be stored in long-lived state, since it must stay within the scope that lent it ([02](../02-views-and-dependencies/scoped-values.md#scoped-values)).

- **Must accept** in safe code, without making either of the pair own the other.
- State the per-access cost, and whether it is avoidable where the compiler can see the target is alive.

### I2 · Intrusive doubly linked list

**Link nodes embedded in objects, each object in two lists at once, with O(1) unlink given just the object.** In C++:

```cpp
struct Link { Link* prev; Link* next; };
struct Enemy {
    Link active;      // in the "active" list
    Link inCell;      // in its grid cell's list
    // ...
};
void unlink(Link& l) { l.prev->next = l.next; l.next->prev = l.prev; }
```

- **Must accept** in safe code or with a small audited `unsafe` core.

### I3 · Re-entrant observer

**An object notifies its listeners, and a listener calls back into the same object during the notification.** In C++:

```cpp
void Door::open() {
    isOpen = true;
    for (Listener* l : listeners) l->onOpened(*this);   // a listener calls lock() on this door
}
```

- **Must accept** some safe way to write this.
- If the natural version panics at run time, the types involved must announce the panic, and the report names the idiomatic alternative.

### I4 · Global configuration and logging

**A global configuration is read everywhere, including from lent work and worker threads, and edited while the program runs.** A global logger is called from every thread at once. Safe code has no unsynchronized mutable global, since every thread can reach a global ([07](../07-concurrency/global-state.md#global-state)).

- **Must accept** in safe code, with concurrency behavior that suits contention. Two threads logging at the same time must not panic.
- The cost of each access must be stated.
- **Must accept** as safe globals an inline array of 64 mutexes built without a 64-element literal, a struct of `Synchronized` fields, a `Shared<Mutex<Job>>`, a `List<Mutex<Job>>`, and an array of `@sendable` `Closure`s.

### I5 · Waiter registered from the stack

**A function declares a local `Waiter`, registers a pointer to it in a global wait list, blocks until signaled, and unregisters**, as the Linux kernel's wait queues and many job systems do. In C++:

```cpp
void waitForJob() {
    Waiter w;                 // lives in this stack frame
    waitList.add(&w);         // a global list now points into the frame
    w.block();                // until another thread signals w
    waitList.remove(&w);      // forgetting this leaves the list dangling
}
```

- *(inherently unsafe, or dynamic)*: state which tier it lands in, and whether anything stops a forgotten unregister from dangling.

### I6 · Load-in-place data with pointer fixups

**Read a blob from disk into memory, then patch relative offsets into pointers, so the blob's structs point into the blob itself.** Use it in place with zero parsing. In C:

```c
struct Mesh { Vertex* verts; uint32_t count; };            // on disk, 'verts' holds an offset
mesh->verts = (Vertex*)(blob + (uintptr_t)mesh->verts);    // the fixup
```

- *(inherently unsafe at the fixup step)*: the fixup must be a small `unsafe` core, and *using* the loaded data must be safe code.

### I7 · Variable-sized struct

**A header followed by N trailing elements in one allocation (C flexible array member), created and accessed in Rayo.** Network packets and C APIs with a flexible array member want this layout ([04](../04-types/data-layout.md#variable-sized-structs-trailingarray)).

- **Must accept** with a safe accessor for the trailing elements.

### I8 · Tagged pointers and NaN-boxing

**Pack a type tag into the low bits of an aligned pointer, or a pointer into a NaN's payload bits**, as a VM's value type does.

- *(inherently unsafe)*: the `unsafe` surface must be one small type.

### I9 · Lock-free MPSC queue implementation

**Implement a lock-free multi-producer, single-consumer queue**, as std's `MpscQueue` could be, from atomics and raw memory. Conforming to `Synchronized` is what lets several threads change a value through shared borrows, since its non-`mutating` methods change it only through its own synchronization ([07](../07-concurrency/synchronization.md#the-synchronized-contract)).

- *(inherently unsafe)*: the spec must provide atomics with explicit orderings, and a way to conform the result to `Synchronized`.

### I10 · Placement construction into preallocated memory

**Construct values in a caller-provided buffer, such as a ring buffer of commands with variable-sized entries, and destroy them in place.**

- **Must accept** with a small `unsafe` core, or safely through a std type.

### I11 · Hand-written vtables and C-style inheritance

**A base struct that holds a pointer to a table of functions is embedded as the first field of derived structs**, and code casts between them, in a layout a C library requires:

```c
struct VTable { void (*update)(struct Base* self, float dt); };
struct Base   { const struct VTable* vt; };
struct Player { struct Base base; float hp; };      // Base is the first field

void player_update(struct Base* b, float dt) {
    struct Player* p = (struct Player*)b;           // the cast
    p->hp -= dt;
}
```

- *(inherently unsafe at the cast)*: Rayo's layout rule must guarantee the prefix, and the casts must be one wrapper.

### I12 · Type punning and bit reinterpretation

**Reinterpret a `Float` as a `UInt32`, and view a `Span<UInt8>` as a span of a struct type, with checks for alignment and size.** Code uses bytes from a file or a packet as values this way ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)).

- **Must hold:** a bit cast is safe from a padding-free `Pod` type to a `Pod` type of the same size ([04](../04-types/data-layout.md#plain-data-pod-and-bit-casts)), and the span reinterpretation is safe when checked.
- State which types qualify.

### I13 · Memory-mapped I/O / volatile access

**Write to a device register or a device-visible, write-combined region, with the required volatile and ordering semantics.**

- *(inherently unsafe)*: the spec must expose volatile loads and stores, and fences.

### I14 · Destruction deferred until an external event

**A resource must not be freed until an external event, such as a GPU fence, has signaled**, even though the program dropped its last reference earlier.

- **Must accept** deferred destruction tied to an external event, with no use-after-free possible in safe code.

---
