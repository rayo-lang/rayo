# 1 · Basics

You're writing a small arena game. Enemies spawn, walk toward the player, take damage and die. This chapter writes that code, and on the way covers the everyday parts of Rayo: functions, structs, enums, optionals, loops, closures, protocols, strings and errors.

```swift
import std.math

struct Enemy(var pos: Vec3, var vel: Vec3 = .zero, var hp: Float = 100) {
    var isDead: Bool { hp <= 0 }

    mutating func takeDamage(_ amount: Float) {
        hp -= amount
    }
}

func update(_ enemies: mutable List<Enemy>, dt: Float) {
    for var e in &enemies where !e.isDead {
        e.pos += e.vel * dt
    }
}
```

The `mutable` and the `&` above are about ownership: who owns each value, and how code borrows it. Chapters 2 to 4 cover ownership, and this chapter keeps to code where it doesn't get in the way.

## Modules and functions

A **module** is a set of source files that are checked and built together. A declaration is visible throughout its module, and `public` exports it to modules that import this one ([11](../spec/11-compilation-model.md#modules-and-names)):

```swift
import std.math                                         // Vec3, and the vector operations

public func lengthSquared(_ v: Vec3) -> Float {          // other modules may call it
    v.x * v.x + v.y * v.y + v.z * v.z
}
func armor(_ e: Enemy) -> Float { e.hp * 0.5 }          // only this module can
```

A call writes each parameter's label before its argument, as in `update(&enemies, dt: 0.016)`. `_` means the caller writes none, so the call is `armor(boss)`. A body that is a single expression returns its value. A public function's signature names only public types, so `armor` can't be public while `Enemy` isn't.

## Numbers

**A number literal takes its type from where it is used.** With nothing to go on, an integer literal is an `Int` and a floating-point one a `Double` ([04](../spec/04-types.md#numbers)):

```swift
let count = 60                 // Int
let elapsed = 0.0              // Double
let dt: Float = 0.016          // Float, from the annotation
let step = dt * 2              // 2 is a Float, taken from the other operand
let wrong = dt * elapsed       // error: 'elapsed' is a Double, and a Double never narrows on its own
let small: Int32 = 500
let total: Int = small         // widening that loses nothing is implicit
let scale = Float(total)       // a conversion that may round is written out
```

`let` names a value that doesn't change, and `var` one that may.

**Integer overflow is a bug, not a wrap.** By default, `a + b` panics on overflow in `dev` and `profile` builds, and wraps in `ship` builds ([10](../spec/10-errors-and-safety.md#the-checks)). When you want wrapping, say so with `&+`, and `+|` saturates. Division by zero panics in every build.

## Structs

**A struct lists its stored fields once, in its header, and the header is also how you build one** ([04](../spec/04-types.md#structs)):

```swift
struct Enemy(var pos: Vec3, var vel: Vec3 = .zero, var hp: Float = 100)

var grunt = Enemy(pos: [0, 0, 5])               // vel and hp take their defaults
var brute = Enemy(pos: [3, 0, 8], hp: 400)
```

The header is the struct's **primary initializer**: one parameter per field, in order, labeled with the field's name. A field with a default may be left out. Fields are laid out in the header's order, as in C, so a struct whose fields C understands can be shared with C as it is.

The body holds everything else: computed properties, methods and other initializers. It never declares a stored field.

```swift
struct Enemy(var pos: Vec3, var vel: Vec3 = .zero, var hp: Float = 100) {
    var isDead: Bool { hp <= 0 }                // computed, on each use

    mutating func takeDamage(_ amount: Float) { // may change self
        hp -= amount
    }
}

grunt.takeDamage(30)
```

A plain method only reads `self`. A `mutating` one may change it, so it is called only on something that may change, such as a `var`.

## Enums and `when`

**An enum is one of several cases, and each case may carry values.** A `when` takes one apart ([04](../spec/04-types.md#enums)):

```swift
enum Order {
    case idle
    case moveTo(Vec3)
    case wait(seconds: Float)
}

func describe(_ order: Order) -> StaticString {
    when order {
        .idle -> "idle"
        .moveTo(let p) where p.y > 10 -> "flying"
        .moveTo -> "walking"
        .wait -> "waiting"
    }
}
```

`when` runs the first arm that matches. It must cover every case, so adding a case to `Order` makes every `when` over it that has no `else` a compile error until you handle the new case. A `where` guard adds a condition to an arm. `let p` binds the case's value for that arm.

**`when` and `if` are expressions**, so they can give a value ([04](../spec/04-types.md#matching-with-when-and-choosing-with-if)):

```swift
let bonus = if boosted { 10 } else { 0 }
let sign = when {
    x < 0 -> -1
    x > 0 -> 1
    else -> 0
}
```

## Optionals

**`T?` is a `T` or `nil`**, and Rayo has no null otherwise ([04](../spec/04-types.md#optionals)):

```swift
var target: Vec3? = nil

if let t = target {                      // runs only when target holds a value
    log("chasing \(t.x)")
}
let goal = target ?? home                // target's value, or home when it is nil
let height = target?.y ?? 0              // target's y, or 0 when target is nil
let sure = target!                       // panics when target is nil
```

An optional costs no extra space when its type has a bit pattern it never uses, as handles and pointers do. Otherwise it adds a flag.

## Lists and loops

**`List<T>` is a growable array that owns its elements** ([04](../spec/04-types.md#collections-and-strings)):

```swift
var enemies = List<Enemy>()
enemies.append(Enemy(pos: [0, 0, 5]))
enemies.append(Enemy(pos: [3, 0, 8], hp: 400))
```

**A `for` loop looks at each element where it is**, so iterating never copies. To change the elements, the loop marks the list with `&` and the element with `var` ([04](../spec/04-types.md#iteration)):

```swift
var total: Float = 0
for e in enemies { total += e.hp }                    // reads each enemy in place

for var e in &enemies { e.takeDamage(5) }             // changes each enemy in place
for var e in &enemies where e.isDead { e.vel = .zero }
for i in 0..<enemies.count { log("enemy \(i)") }      // a range of Ints
```

The `&` is how Rayo shows, at the call or the loop, that something is lent out to be changed. Chapter 3 says why it is required ([Borrowing](03-borrowing.md)).

**A bracketed literal is an inline array unless you name another type.** `[1, 2, 3]` alone is a `[3 of Int]`, stored inline with no heap allocation. A `List` allocates, so a list literal names its type where it is written:

```swift
let xs = [3, 4, 5]                  // [3 of Int], inline
let ys: List<_> = [3, 4, 5]         // List<Int>, allocated
spawnAll([a, b])                    // error: a List parameter would allocate without saying so
```

## Closures

**A closure is a function written inline** ([05](../spec/05-protocols-generics-and-closures.md#functions-and-closures)). `{ e in … }` names its parameters, and `$0` is the first one when it names none. A closure passed last may follow the call's parentheses:

```swift
func each(_ xs: Span<Enemy>, _ body: (Enemy) -> Void) { for x in xs { body(x) } }

each(enemies.span) { e in log("hp \(e.hp)") }       // a trailing closure
each(enemies.span) { log("at \($0.pos.x)") }         // $0: the first parameter
```

`(Enemy) -> Void` is a **function type**, and `enemies.span` lends the list's elements for reading. A closure can use the locals around it, which it **captures**. Passed to a function, it borrows them for the call, and never allocates.

**A closure's type says whether it changes what it captures:**

```swift
func eachMut(_ xs: Span<Enemy>, _ body: mutating (Enemy) -> Void) { for x in xs { body(x) } }

var dead = 0
eachMut(enemies.span) { e in if e.isDead { dead += 1 } }   // writes 'dead': a mutating closure
each(enemies.span) { e in if e.isDead { dead += 1 } }      // error: a mutating closure where a non-mutating one is expected
```

The compiler works out a closure's kind from its body. Chapter 7 shows why the kind matters once closures run on other threads ([Concurrency](07-concurrency.md)).

## Protocols and generics

**A protocol names what a type must have** ([05](../spec/05-protocols-generics-and-closures.md#protocols-and-generics)). Each thing it names is a **requirement**. A type **conforms** by declaring it, in its header or in an `extension`, which adds members and conformances to a type declared elsewhere. The type's own members meet the requirements ([05](../spec/05-protocols-generics-and-closures.md#conformances)):

```swift
protocol Damageable {
    var hp: Float { get set }
    mutating func takeDamage(_ amount: Float)
}

extension Enemy: Damageable {}              // Enemy's 'hp' field and 'takeDamage' method meet both
```

**A generic function works for every type that meets its constraints:**

```swift
func applyAoE<T: Damageable>(_ targets: mutable List<T>, amount: Float) {
    for var t in &targets { t.takeDamage(amount) }
}

applyAoE(&enemies, amount: 25)
```

A generic function is type-checked once, at its definition, against its constraints. A body that uses something `Damageable` doesn't require is an error there, not at a call. Code that runs in the compiler is the main exception ([C and compile time](08-c-and-compile-time.md)). The compiler then builds a copy for each type it is used with, so a call through `T` costs what a direct call does.

## Strings

**A string is UTF-8 bytes, and formatting writes straight into its destination** ([04](../spec/04-types.md#strings)):

```swift
log("hp \(e.hp) at \(e.pos.x)")         // written into the log: no allocation
let label = String("enemy \(i)")        // a new String: this allocates, and says so
```

An interpolated literal isn't a `String`. It is a small value that writes its pieces into whatever takes it, such as a log, a file or a buffer. With nothing else to go on, a plain string literal is a `StaticString`, text that lives for the whole run. `String` owns its text and allocates, so you build one only when you want to keep the text.

## Errors and panics

**Rayo separates errors a caller should handle from bugs** ([10](../spec/10-errors-and-safety.md)):

- **A recoverable error**, such as a missing file, is a value the function throws. Its signature names the error type, and the caller must handle it.
- **A bug**, such as an index out of bounds or `!` on `nil`, **panics**: the program reports it and stops. A panic never unwinds.

```swift
enum LoadError: Error {
    case notFound
    case corrupt(offset: Int)
}

func loadLevel(_ path: StringView) throws(LoadError) -> Level { ... }

do {
    let level = try loadLevel("arena.lvl")
    start(level)
} catch .notFound {
    log("no such level")
} catch .corrupt(let at) {
    log("level is corrupt at byte \(at)")
}
```

`try` passes an error on to the caller, which must throw a compatible type. `try?` turns one into `nil`, and `try!` panics on one. Throwing costs what returning does: the error comes back as a value, with no unwinding and no allocation ([10](../spec/10-errors-and-safety.md#typed-throws)).

`precondition(count < capacity, "queue full")` checks a caller's promise in every build, and panics when it fails. `assert` checks an internal invariant, by default only in `dev` builds ([10](../spec/10-errors-and-safety.md#assert-and-precondition)).

## A first look at places

One rule shows up as soon as you name a list's element:

```swift
let first = enemies[0]          // another name for the element: nothing is copied
var spare = copy enemies[0]     // a second enemy, of its own
var e = enemies[0]              // error: write 'copy' for a copy, or '&' to change the element in place
```

`enemies[0]` is a **place**: storage that holds a value. Rayo never copies a value unless the code says `copy`, so a binding of a place either names it, or says what it does with it. The next two chapters are about exactly this ([Moves and copies](02-moves-and-copies.md), [Borrowing](03-borrowing.md)).

## In the spec

- [04 Types](../spec/04-types.md): numbers and their conversions, structs and initializers, enums and `when`, optionals, collections, strings, literals and loops.
- [05 Protocols, generics and closures](../spec/05-protocols-generics-and-closures.md#functions-and-closures): functions, labels and what a body returns.
- [10 Errors and safety](../spec/10-errors-and-safety.md): typed `throws`, `do` and `catch`, and every case that panics.
- [11 Compilation model](../spec/11-compilation-model.md#modules-and-names): modules, `public` and imports.
