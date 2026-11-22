# Parameters

[01 · Values and ownership](../01-values-and-ownership.md)

**A parameter's type says what the function does with its argument**: owns it, borrows it, or borrows it for change.

```swift
func length(_ v: Vec3) -> Float { ... }                       // owns a copy: a Vec3 is implicitly copyable
func show(_ e: &Enemy) { ... }                                 // borrows the caller's enemy: reads it, can't change it
func damage(_ e: mutable &Enemy, by amount: Float) { ... }     // borrows it for change: changes the caller's enemy
func adopt(_ items: List<Item>) { ... }                        // owns its argument: keeps the list

length(boss.pos)                        // a copy goes in, and boss.pos stays as it was
show(&boss)                             // '&' lends 'boss' shared
damage(mutable &boss, by: 10)           // 'mutable &' lends it for change; 'boss' must be a changeable place
adopt(loot)                             // error: 'adopt' takes 'List<Item>'; write 'consume loot'
adopt(consume loot)                     // 'loot' is moved in and can't be used after
adopt(alloc backpack.items.clone())     // a clone is a new value, so nothing moves
```

| Parameter | Declared as | Call site | Inside the body |
| --- | --- | --- | --- |
| Owns its argument | `_ x: T` | `f(consume a)`, `f(copy a)` or a value, and `f(a)` for an implicitly copyable `a` | A value the callee owns, as a `var` owns its value |
| Borrows it | `_ x: &T` | `f(&a)` | A `ref let` of the caller's place ([below](#borrowed-arguments)) |
| Borrows it for change | `_ x: mutable &T` | `f(mutable &a)` | A `ref var` of the caller's place, which must be a [changeable place](bindings.md#changeable-places) |

**A call writes its arguments as every position does** ([References](references.md#places-given-to-a-position)). So a call shows what it does with each place it is given, and a mark that doesn't match its parameter is a compile error, such as `show(boss)` for `&boss`.

**Each kind of parameter holds its argument in its own way, and so does `self`:**

- **A parameter `x: T` owns its argument as a `var` owns its value.** It may change or consume it. It is destroyed when the call ends, by returning or a panic's unwind, unless the callee has moved it on ([Destruction by unwinding](moves-copies-destruction.md#destruction-by-unwinding)). A `consuming` method's `self` is held the same way.
- **A `&T` parameter is a `ref let` of the caller's place, and a `mutable &T` parameter is a `ref var` of it** ([Bindings](bindings.md#bindings-that-refer-to-a-place)). So the parameter names the place, of type `T`, and passing it on writes `&x` or `mutable &x`. Through a `mutable &T` parameter, `x += 1` writes the caller's value, and `x = makeEnemy()` replaces it.
- **Only a parameter whose type is a reference names a place.** A parameter whose type holds a reference, such as `(&Enemy)?` or `List<&Enemy>`, owns the value it is given, as any `x: T` does.
- **Methods take `self` as their declaration says.** A plain `func` takes it as a `ref let`, a `mutating func` as a `ref var`, and a `consuming func` owns it. A struct's primary initializer takes its fields owned, since the value owns its fields ([04](../04-types/structs.md#initializers)). So `World(enemies: consume enemies)` moves `enemies` in.

```swift
func bump(_ x: mutable &Int) { x += 1 }       // writes the caller's Int
func respawn(_ e: mutable &Enemy) {
    e = makeEnemy()                           // replaces the caller's enemy
    damage(mutable &e, by: 5)                 // lends it on for change
}
```

**Parameter types line up across an indirection.** A protocol witness, a function converted to a function type, and a function type converted to another declare each parameter with the type of what they stand for, a reference included, and take `self` the same way ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)). So a call through any of them passes its arguments as a direct call would ([below](#borrowed-arguments)).

**A `mutable &` argument's changes reach the caller's place when the call returns**, even when it is lent through a temporary that is written back, as a bitfield or an under-aligned field is ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)). When the call unwinds instead, changes through a value property, such as a bitfield, are lost, since its `set` isn't called ([02](../02-views-and-dependencies/place-and-value-properties.md#panics-during-a-change)). An under-aligned field's temporary is still written back ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)).

## Argument labels

**A call writes each argument after its argument label, if it has one, and in the order of the parameters.** A parameter of a function or an initializer gets its **argument label** in one of three ways:

- a name written before the parameter's own name is its label, as `by` is below;
- a `_` written there leaves the argument unlabeled, so the call writes no label;
- with neither, the parameter's own name is its label, as `overcharge`'s is below.

```swift
func heal(_ e: mutable &Enemy, by amount: Float, overcharge: Bool) { ... }

heal(mutable &boss, by: 10, overcharge: true)       // 'e' takes no label, and 'overcharge' is labeled by its name
heal(mutable &boss, 10, overcharge: true)           // error: the second argument needs the label 'by'
heal(e: mutable &boss, by: 10, overcharge: true)    // error: the first argument takes no label
heal(mutable &boss, overcharge: true, by: 10)       // error: 'by' comes before 'overcharge'
```

A label may be a keyword, as `in` is in `index(of: &h, in: &handles)` ([12](../12-grammar/lexical.md#lexical)). Three kinds of call differ from a call to a named function:

- **Subscripts.** A subscript's parameter is unlabeled unless a label is written, so `list[i]` passes `i` to `subscript(i: UInt)`, and `a[as: Tooltip.self]` passes a type to a parameter written `as t`.
- **Operators.** An operator's parameters take no labels, since `a + b` writes none ([05](../05-protocols-generics-and-closures/operators.md#operators)).
- **Function values.** A function type's parameters have no labels, so a call to a function value, such as `body(0)`, writes none ([05](../05-protocols-generics-and-closures/functions-and-closures.md#function-typed-values)).

## Default arguments

**A default value makes an argument optional:**

```swift
func spawn(_ kind: Kind, at pos: Vec3 = .zero) { ... }
spawn(.grunt)                                           // leaves out 'at:', so 'pos' is .zero
```

- **The default is checked where it is declared**, as the body of a function with no parameters whose result type is the parameter's type. So it names no other parameter and no `self`, and a reference or other view it returns views only static storage ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)).
- **A call that leaves the argument out calls that function** in the argument's position, as part of the call's own statement ([below](#evaluation-order-and-when-a-calls-borrows-begin)).
- **A `mutable &T` parameter has no default**, since it stands for a place of the caller's.
- **A field's default works the same way** in the primary initializer ([04](../04-types/structs.md#initializers)).

## Borrowed arguments

**Safe code in the callee can't change, keep or take the address of a `&T` argument's place, and nothing else changes it before the call returns** ([The law of exclusivity](exclusivity.md#the-law-of-exclusivity)). The exception is a `Synchronized` value the place holds, which changes through its own synchronization ([07](../07-concurrency/synchronization.md#the-synchronized-contract)).

**So the callee may see a copy of the argument's bits or the caller's place, and the compiler chooses.** The callee can't tell them apart. These `&T` arguments are always the caller's place, since their address matters:

- **A `Synchronized` value.** An argument that is or holds one at any depth, since such a value's identity is its address, and it changes through a shared borrow. A `Closure<F>` counts, since its captures may hold one ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)).
- **The argument of `ptr(to:)`**, whose result is its address ([10](../10-errors-and-safety/unsafe-code.md#taking-an-address)).
- **A source of a place property's place.** `self` by default, and each parameter a `where return borrows` item names, whatever the place's type, since the place lies inside it ([02](../02-views-and-dependencies/place-and-value-properties.md#the-place-lies-in-its-sources)).
- **An argument still viewed after the call.** The result, an error in it included, or an absorbing argument may view the argument's own storage, which in a copy would be the callee's. An absorbing argument is a `mutable &` one, or an owned value that holds a mutable view, such as a `mutating` function value (rule 4 in [02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-4-absorption)).

[Rules 3 and 4](../02-views-and-dependencies.md#dependencies), and a `where` clause's `return` items, tell which arguments may still be viewed: they go by the signature's types, and by which arguments are [shallow](../02-views-and-dependencies/dependency-projection-and-results.md#shallow-values). An `Int` or a `List<Int>` result views nothing. A place property's place is no result, so neither of these spares its sources.

**Which arguments are the caller's place follows from the signature alone**: the function called, its result type, its `where` clause, and each parameter's type.

- **Adding `keep` to a parameter changes none of this** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-keep)).
- **A call through a function value passes its arguments as a direct call would**, since every function-type conversion keeps the parameter types, and so which arguments are places ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)). `ptr(to:)` is never a function value ([10](../10-errors-and-safety/unsafe-code.md#taking-an-address)).

## Evaluation order, and when a call's borrows begin

```swift
items.append(items.count)                // fine: items.count is read, and done, before append borrows items
upload(builder.finish(builder.count))    // fine: count is read before finish takes builder
f(mutable &x, &x)                        // error: two borrows of x overlap for the whole call
```

**Evaluation is left to right, and a call's borrows begin with the call.** So a value read for an argument is done before the call lends or takes its place, and every borrow and take of one call is checked against the others. The order is fixed, so two implementations never disagree about it ([11](../11-compilation-model.md#what-the-language-leaves-open)). The one exception is the message of `fatalError`, `precondition` or `assert`, evaluated only when the call panics ([10](../10-errors-and-safety/panics.md#messages)). A call runs in this order:

1. **It evaluates its callee, then its receiver, then its arguments.** Evaluating `&a`, `mutable &a` or `consume a` works out which place `a` names: its base first, then its indices, left to right. A receiver that names a place is worked out the same way.
2. **Then the call begins.** Every borrow it passes begins, and lasts until the call returns, and every value it takes leaves its place. A panic before this step leaves those places as they were, and the unwind destroys the argument values made so far, as temporaries ([Destruction by unwinding](moves-copies-destruction.md#destruction-by-unwinding)).
3. **As it begins, it runs the accessors those places reach**, in the order the places were worked out, receiver first. These are each place property's `borrow` or `mutate`, and the `get` of each value property that the call lends for change ([02](../02-views-and-dependencies/place-and-value-properties.md#place-and-value-properties)). A panic in this step ends the borrows already begun, and the unwind destroys the values step 2 took, as temporaries, as in `f(consume a, mutable &list[99])`.
4. **When it returns, it calls the `set` of each such value property, in reverse order.** A change that the result still depends on is the exception: its `set` runs at that value's last use ([02](../02-views-and-dependencies/place-and-value-properties.md#value-properties-get-and-set)). An unwind calls none of them, and destroys each copy a `get` made ([10](../10-errors-and-safety/panics.md#unwinding)). A place property's access runs no code as it ends, whether the call returns or unwinds.

**Any other `get` runs as its argument or receiver is evaluated.** It makes a value, whatever the call then does with it: borrows it, changes it, takes it, or calls a method on it. Its result keeps what it depends on borrowed (rule 3 in [02](../02-views-and-dependencies/dependency-projection-and-results.md#rule-3-call-results)).

```swift
items.insert(consume x, at: items.count)   // count's get has returned before insert borrows items
```

**Working out a place never accesses it**, except for an optional chain (`?.`) or a force unwrap (`!`) after `&` or `mutable &`. Unwrapping reads the optional, so the borrow up to that point begins there, and lasts until the call returns:

```swift
damage(mutable &world.enemies[h]!, by: reinforce(mutable &world.enemies))   // error: '!' begins the borrow of world.enemies before reinforce runs
```

**These keep the same left-to-right order:**

- operator operands, the elements of tuple and array literals, and the segments of an interpolated string;
- an assignment, which works out its left place, evaluates its right side, then writes;
- a compound assignment `a ⊕= b`, which works out `a`'s place once, evaluates `b`, then reads the place, applies `⊕` and writes the result back ([05](../05-protocols-generics-and-closures/operators.md#operators)).

**Some operands are skipped.** `&&`, `||` and `??` evaluate their right side only when the left doesn't decide. Optional chaining skips the rest of the chain at a `nil`, arguments included.

**An assignment through an optional chain or `!` reads the optional only after evaluating its right side.** When the left side holds one, the assignment works out its left place up to the first `?` or `!`. Then it evaluates its right side, and only then reads the optional and works out the rest, so the right side's accesses have ended by then. A compound assignment does the same. When the chain stops at a `nil`, the right side's value is dropped. A chain on the left ends in a member or an element, so `x? = v` is a compile error ([04](../04-types/enums.md#optionals)).

```swift
pool[h]?.hp = 0                                               // works out pool[h], evaluates 0, then reads the optional
pool[a]?.hp = pool[b]!.hp                                     // fine: pool[b] is read before pool[a]'s optional is
world.enemies[h]?.hp -= reinforce(mutable &world.enemies)     // fine: reinforce returns before the optional is read
```
