# Parameters

[01 · Values and ownership](../01-values-and-ownership.md)

**A parameter's convention says what the function does with its argument**: looks at it (the default), changes it in place, or keeps it.

```swift
func length(_ v: Vec3) -> Float { ... }                 // borrows v: reads it, can't change it
func damage(_ e: mutable Enemy, by amount: Float) { ... } // borrows e mutably: changes the caller's enemy
func adopt(_ items: owned List<Item>) { ... }       // takes ownership: keeps the list
func remember(_ pos: owned Vec3) { ... }            // takes ownership: keeps the position

damage(&boss, by: 10)                                   // '&' marks the mutable borrow; 'boss' must be a changeable place
adopt(loot)                                             // 'loot' is moved in and can't be used after
adopt(backpack.items.clone())                           // a clone is a new value, so nothing moves
remember(copy e.pos)                                    // a copy moves in, and e.pos stays as it was
```

| Convention | Declared as | Call site | Callee receives |
| --- | --- | --- | --- |
| borrowed (default) | `_ x: T` | `f(x)` | A shared borrow ([below](#borrowed-arguments)) |
| mutable | `_ x: mutable T` | `f(&x)` | A mutable borrow of a [changeable place](bindings.md#changeable-places) |
| owned | `_ x: owned T` | `f(x)` | The value: a place moves in, whatever its type, and `f(copy x)` passes a copy |

- **The callee owns an `owned` argument as a `var` owns its value.** It may change or consume it. It is destroyed when the call ends, unless the callee moves it on. A `consuming` method's `self` is held the same way.
- **Methods use the same conventions for `self`.** A plain `func` borrows it, a `mutating func` takes it `mutable`, and a `consuming func` takes it `owned`. A struct's primary initializer takes its fields `owned`, since the value owns its fields ([04](../04-types/structs.md#initializers)). So `World(enemies: enemies)` moves `enemies` in.
- **Conventions line up across an indirection.** A protocol witness, a function converted to a function type, and a function type converted to another declare each parameter, and `self`, with the convention of what they stand for ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)). So a call through any of them passes its arguments as a direct call would ([below](#borrowed-arguments)).
- **A `mutable` argument's changes always reach the caller's place**, even when it is lent through a temporary that is written back, as a bitfield or an under-aligned field is ([04](../04-types/structs.md#packed-structs-and-under-aligned-places)).

**Some parameters are received `owned` with no `owned` written**, unless they are declared `mutable`. Each is used in a way that a borrowed parameter, which is read-only, can't be ([Changeable places](bindings.md#changeable-places)):

- **Function values that change or consume their captures.** This covers a parameter of a `mutating` or `consuming` function type, and one of a type parameter constrained to one, written `some F` or named. Calling such a value changes or consumes the closure, so a borrowed one could never be called ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds)).
- **`mutable any P`.** It is a view of its own, and calling a `mutating` requirement through it needs the view in a changeable place ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)).

## Default arguments

**A default value makes an argument optional:**

```swift
func spawn(_ kind: Kind, at pos: Vec3 = .zero) { ... }
spawn(kind)                                             // leaves out 'at:', so 'pos' is .zero
```

- **The default is checked where it is declared**, as the body of a function with no parameters that returns the parameter's type and doesn't throw. So it names no other parameter and no `self`, and a view it returns views only static storage ([02](../02-views-and-dependencies/dependency-rules/absorption-and-accesses.md#rule-5-the-callee-side)).
- **A call that leaves the argument out calls that function** in the argument's position, as part of the call's own statement ([below](#evaluation-order-and-when-a-calls-borrows-begin)).
- **A `mutable` parameter has no default**, since it stands for a place of the caller's.
- **A field's default works the same way** in the primary initializer ([04](../04-types/structs.md#initializers)).

## Borrowed arguments

**Safe code in the callee can't change, keep or take the address of a borrowed argument, and nothing else changes it before the call returns** ([The law of exclusivity](exclusivity.md#the-law-of-exclusivity)). The exception is a `Synchronized` value the argument holds, which changes through its own synchronization ([07](../07-concurrency/synchronization.md#the-synchronized-contract)).

**So the callee may see a copy of the argument's bits or the caller's place, and the compiler chooses.** The callee can't tell them apart. These borrowed arguments are always the caller's place, since their address matters:

- **A `Synchronized` value.** An argument that is or holds one at any depth, since such a value's identity is its address, and it changes through a shared borrow. A `Closure<F>` counts, since its captures may hold one ([05](../05-protocols-generics-and-closures/functions-and-closures.md#unscoped-closures-closuref)).
- **The argument of `ptr(to:)`**, whose result is its address ([10](../10-errors-and-safety/unsafe-code.md#taking-an-address)).
- **An argument still viewed after the call.** The result, a thrown error, a storage projection's yield ([02](../02-views-and-dependencies/projections-and-accessors.md#storage-projections)) or an absorbing argument may view the argument's own storage, which in a copy would be the callee's. An absorbing argument is a `mutable` one, or an `owned` mutable view, such as a `MutableSpan` or a `mutating` closure (rule 4 in [02](../02-views-and-dependencies/dependency-rules/absorption-and-accesses.md#rule-4-absorption)).

[Rules 3 and 4](../02-views-and-dependencies/dependency-rules.md#dependencies), and an accessor's `where yield` clause, tell which arguments may still be viewed: they go by the signature's types, and by which arguments are [shallow](../02-views-and-dependencies/dependency-rules/projection-and-results.md#shallow-values). An `Int` or a `List<Int>` result views nothing.

**Which arguments are the caller's place follows from the signature alone**: the function called, its result and error types, its `where yield` clause, and each parameter's type and convention.

- **Adding `keep` to a parameter changes none of this** ([05](../05-protocols-generics-and-closures/functions-and-closures.md#what-a-closure-may-keep-keep)).
- **A call through a function value passes its arguments as a direct call would**, since every function-type conversion keeps the conventions, and which arguments are places ([05](../05-protocols-generics-and-closures/implicit-conversions.md#implicit-conversions)). `ptr(to:)` is never a function value ([10](../10-errors-and-safety/unsafe-code.md#taking-an-address)).

## Evaluation order, and when a call's borrows begin

```swift
items.append(items.count)     // fine: items.count is read, and done, before append borrows items
builder.finish(builder.count) // fine: count is read before finish takes builder
f(&x, x)                      // error: two borrows of x overlap for the whole call
```

**Evaluation is left to right, and a call's borrows begin with the call.** So a value read for an argument is done before the call lends or takes its place, and every borrow and take of one call is checked against the others. The order is fixed, so two implementations never disagree about it ([11](../11-compilation-model.md#what-the-language-leaves-open)). A call runs in this order:

1. **It evaluates its callee, then its receiver, then its arguments.** Evaluating a borrowed or `mutable` argument works out which place it names: its base first, then its indices, left to right. An `owned` argument or a `consuming` receiver that names a place is worked out the same way.
2. **Then the call begins.** Every borrow it passes begins, and lasts until the call returns, and every value it takes leaves its place.
3. **As it begins, it runs the accessors those places reach**, in the order the places were worked out, receiver first. These are the `read` and `modify` projections, and the `get` of each `get` and `set` pair that the call lends for change ([02](../02-views-and-dependencies/projections-and-accessors.md#projections-read-and-modify-accessors)).
4. **When it returns, it ends those accesses in reverse order**, running the code after each `yield` and calling each `set`. An access-bound projection's access that the result still depends on is the exception: it ends at that value's last use ([02](../02-views-and-dependencies/projections-and-accessors.md#access-bound-projections)).

**Any other `get` runs as its argument or receiver is evaluated.** It makes a value, whatever the call then does with it: borrows it, changes it as a mutable form's view, takes it, or calls a method on it. Its result keeps what it depends on borrowed (rule 3 in [02](../02-views-and-dependencies/dependency-rules/projection-and-results.md#rule-3-call-results)).

```swift
items.insert(x, at: items.count)   // count's get has returned before insert borrows items
```

**Working out a place never accesses it**, except for an optional chain (`?.`) or a force unwrap (`!`) in a borrowed or `mutable` argument. Unwrapping reads the optional, so the borrow up to that point begins there, and lasts until the call returns:

```swift
damage(&world.enemies[h]!, by: reinforce(&world.enemies))   // error: '!' begins the borrow of world.enemies before reinforce runs
```

**These keep the same left-to-right order:**

- operator operands, the elements of tuple and array literals, and the segments of an interpolated string;
- an assignment, which works out its left place, evaluates its right side, then writes;
- a compound assignment `a ⊕= b`, which works out `a`'s place once, evaluates `b`, then reads the place, applies `⊕` and writes the result back ([05](../05-protocols-generics-and-closures/operators.md#operators)).

**Some operands are skipped.** `&&`, `||` and `??` evaluate their right side only when the left doesn't decide. Optional chaining skips the rest of the chain at a `nil`, arguments included.

**An assignment through `?.`, `?` or `!` reads the optional only after evaluating its right side.** When the left side holds one, the assignment works out its left place up to the first of them. Then it evaluates its right side, and only then reads the optional and works out the rest, so the right side's accesses have ended by then. A compound assignment does the same. When the chain stops at a `nil`, the right side's value is dropped.

```swift
pool[h]?.hp = 0                                       // works out pool[h], evaluates 0, then reads the optional
requests[h]? = v                                      // the same through '?': v is evaluated before the optional is read
pool[a]?.hp = copy pool[b]!.hp                        // fine: pool[b] is read before pool[a]'s optional is
world.enemies[h]?.hp -= reinforce(&world.enemies)     // fine: reinforce returns before the optional is read
```
