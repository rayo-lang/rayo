# Moving values out

[01 · Values and ownership](../01-values-and-ownership.md)

A move hands a value to a new owner and leaves its old place without that value. It can happen through familiar constructs, even when no `consume` appears. These constructs take a value and therefore move it ([Moves](moves-copies-destruction.md#moves)):

- an assignment, `return`, `throw` and `await`;
- an `owned` argument, and a `consuming` method's receiver ([Parameters](parameters.md#parameters));
- a declaration that doesn't borrow, and an `owned` part of a condition or pattern ([Bindings](bindings.md#bindings));
- a `[move x]` capture ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref));
- a global's initializer;
- the elements of a tuple or array literal, and an enum case's payload.

A copyable `const` is the exception: taking one makes a new value ([below](#constants)). A borrowing binding borrows the place instead ([Bindings](bindings.md#bindings)).

**`consume place` writes a move as an expression.** Moving a place's value out, implicitly or this way, is **consuming** the place. `consume` also moves where the code would otherwise borrow: in `f(consume x)` for a borrowed parameter, the moved value is a temporary, destroyed at the end of the statement.

```swift
var loot = List<Item>()
give(loot)                            // fine: 'loot' is a local that owns its list
var spare = List<Item>()
show(consume spare)                   // 'show' only borrows; 'consume' moves 'spare' out, destroyed after the statement
give(player.inventory)                // error if 'player' is a mutable parameter: the caller still owns it
let old = replace(&player.inventory, with: List())    // the way to take it: leave a value behind
```

## What can be moved from

**Only code that owns a place may move from it**, implicitly or with `consume`. No borrow of that place may be live, and no scoped value may depend on it: a move is a mutable access ([The law of exclusivity](exclusivity.md#the-law-of-exclusivity)). These places can be moved from:

- a local that owns its value: a `let` or `var` that doesn't borrow, including an owned exclusive view such as an `SoA` column bound with `&` ([Lending a place for change](bindings.md#lending-a-place-for-change));
- an `owned` parameter, including a function-typed one received owned, and an owned capture inside a `consuming` closure;
- a temporary, such as a call result passed to an `owned` parameter;
- a field of one of those, through stored fields only, named or reached by reflection ([09](../09-compile-time/reflection.md#what-reflection-can-read)), when no type along the path declares a `deinit`, since a `deinit` takes the whole value;
- a stored field of `self`, or a part of an enum `self`'s payload through an `owned` pattern, in that type's own `deinit`;
- the same, in a `consuming` method declared in the type's own module, when every path that moves one out then reaches `discard self` (below).

**The condition on a field covers a temporary's fields and an enum's payload**, and a pattern takes an enum's payload under the same condition ([Conditions and patterns](bindings.md#conditions-and-patterns)):

```swift
take(makeHolder().items)        // moves 'items' out of the temporary: an error when makeHolder()'s type has a deinit
```

These moves leave the rest of the value to be destroyed:

- **Moving a field out of a temporary**, as above, destroys the other fields at the end of the statement.
- **A `deinit` that consumes some fields and parts leaves the rest to be destroyed after it**, last declared first.
- **`discard self` ends `self` without its `deinit`**, destroying the fields and parts it hasn't consumed, last declared first. So a `consuming` method can end its value without running the `deinit`, as the two below do.

```swift
extension File {
    consuming func close() throws(IoError) { … }   // File's deinit closes it: this closes it, then 'discard self', so it closes once
}
extension Bag {
    consuming func intoItems() -> List<T> { … }    // Bag has a deinit: this moves 'items' out, then 'discard self'
}
```

**After a field is consumed, the whole value can't be used or passed until the field is assigned again.** If the scope ends first, the fields still held are destroyed one by one, last declared first.

**Only a place that holds the rest of its value has a field assigned.** A place that holds no value, or maybe holds one, is given a whole value, made by an initializer, so no value is ever half-built ([04](../04-types/structs.md#initializers)).

**Nothing else can be consumed.** So none of these can:

- a global, `const`s included;
- a borrowing binding;
- a borrowed or `mutable` parameter;
- an owned capture outside a `consuming` closure, since only a `consuming` closure runs at most once ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds));
- a collection's element;
- a place reached through a weak pointer, an accessor or a subscript.

**The alternatives leave a value in the place:**

- `copy place` and `place.clone()` leave it as it was;
- through an exclusive view, `replace(&place, with: new)`, `swap(&a, &b)` or a type's own `take()`, such as `Optional.take()` and `List.take()`, leave a value behind.

So such a place always holds a value, across a `throw`, an early return and an `await` too. A caller, an alias or a later `deinit` that reaches it finds one there.

## Constants

**A `const` that reaches run time is a place in read-only data that lives as long as the program** ([09](../09-compile-time/constants-and-conditions.md#consts-that-reach-run-time)). A view of it is static storage, which any function may return.

**A `const` of a copyable type is taken without `copy`**, as a new value each time. So a `let` or `var` declared from one gets a new value, and `borrow` borrows the const itself. A `const` of a move-only type can only be borrowed or cloned.

```swift
const maxLives = 3

var lives = maxLives               // a new Int, with no 'copy' written
let cap = borrow maxLives          // borrows the const
```

**A static stored member is a global or a `const` in its type's namespace**, and is taken as either is. So `Vec3.zero`, whether a copyable `static const` or a computed property, is taken with no `copy`, as in `Enemy(pos: .zero, hp: 100)`.

## Places that hold no value

**A binding declared without a value holds none until it is assigned.** A `let` is assigned at most once on each path.

```swift
let lo: Float, hi: Float           // no values yet
lo = 0                             // each let is assigned once
hi = 1
```

**A place that holds a value on only some paths is maybe-initialized where the paths join.** A **maybe-initialized** place can't be used until it is assigned again, which the compiler proves statically.

**At scope end, and when a new value is assigned, the old value is destroyed exactly when there is one.** A partly moved value is tracked per field.

**A closure that captures a place exclusively may give it its value**, when the place holds no value, or maybe holds one, and the closure's body assigns it before any other use on every path.

- **The capture carries whether the place holds a value.** An assignment destroys an old value only if there is one. So a `mutating` closure called twice destroys the first value when it assigns the second.
- **A `let` is given its value this way only by a `consuming` closure**, which runs at most once.
- **After the closure's last use, the place is maybe-initialized** in the enclosing function, since the closure may never have been called.
