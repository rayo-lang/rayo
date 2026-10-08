# 1 · Basics

Suppose a game records damage to an enemy. Start with a complete program that subtracts a hit and reports the health left:

```swift
func main() {
    let damage = 30
    var hp = 100
    hp -= damage
    log("hp is now \(hp)")          // hp is now 70
}
```

Rayo starts at `main` ([07](../spec/07-concurrency/global-state.md#initialization-at-startup)). The program has familiar pieces, but their details matter when values begin to own memory. `let` and `var` say which names may change. Number types do not silently discard information, and a function's parameters say what it may do with its arguments. From here on, we'll look at one part of the program at a time.

## Variables

A variable gives a value a name. The program uses `let` for `damage`, since it never changes, and `var` for `hp`, which loses health. Writing `\(hp)` inside the quotes puts its value into the text.

If you try to change a `let`, the program doesn't compile:

```swift
damage = 40                     // error: 'damage' is a 'let', so it can't change
```

Use `let` when you do not need to assign a new value. It tells a reader that the name keeps its original value, without making them check the rest of the function. A `let` can still hand its value to a new owner; chapter 2 shows what happens then ([Moves and copies](02-moves-and-copies.md#adding-to-a-list)).

Every variable also has a type, which stays the same for as long as the variable exists. Usually Rayo works the type out from the starting value: `hp` starts at `100`, a whole number, so it's an `Int`, Rayo's usual type for whole numbers. When you want another type, you write it after the name:

```swift
let speed: Float = 4            // the 4 becomes a Float to match
var level: UInt8 = 1            // and this 1 a UInt8
```

## Numbers

Rayo has the number types you'd expect. `Int8`, `Int16`, `Int32` and `Int64` hold whole numbers of different sizes, `UInt8` to `UInt64` hold whole numbers that can't be negative, and `Int` and `UInt` are 64 bits wide. For numbers with a fractional part, there are `Float` and `Double` ([04](../spec/04-types/numbers-and-math.md#numbers)).

A number written in the code, such as `2`, doesn't have a type of its own. It takes the type that the code around it asks for:

```swift
let dt: Float = 0.016
let step = dt * 2               // 2 becomes a Float, because dt is one
```

When nothing around a number asks for a type, it falls back on a default: a whole number becomes an `Int`, and one with a decimal point becomes a `Double`:

```swift
let count = 60                  // an Int
let elapsed = 0.5               // a Double
```

### Mixing number types

When you combine two different number types, Rayo converts one of them for you only if nothing can be lost on the way. A `Double` can hold every `Float` exactly, so multiplying the two gives a `Double`. Turning the `Double` result into a `Float` could round it, so Rayo won't do it on its own. You have to ask, by writing the conversion out:

```swift
let total = dt * elapsed            // a Double
let short: Float = dt * elapsed     // error: a Double doesn't turn into a Float by itself
let fine = Float(dt * elapsed)      // a Float, rounded because you asked
```

The same rule decides when a whole number mixes with another type. An `Int8` turns into an `Int` by itself, since an `Int` holds every `Int8`. An `Int`, though, never turns into a `Float` or a `Double` by itself, even where C and Java would convert it quietly. A `Double` reaches far bigger numbers than an `Int` does, but it keeps only about 16 digits exactly, and a large `Int` has 19.

```swift
let extra: Int8 = 5
let score = count + extra           // an Int: every Int8 fits in an Int
let wrong = dt * count              // error: an Int doesn't turn into a Float by itself
let right = dt * Float(count)
```

The difference from `dt * 2` is that a written number like `2` has no type yet, so it can become a `Float`, while a variable like `count` already has one. Each conversion you write marks a spot where a value might change, which is exactly where you'd want to look when a result comes out wrong.

### Overflow

Each whole-number type has a largest and a smallest value. An `Int8` holds -128 to 127, so this addition has no answer that fits:

```swift
let hp8: Int8 = 120
let a = hp8 + 10                // the 10 becomes an Int8 too, and 130 doesn't fit
```

Going past the limit is called **overflow**, and Rayo treats it as a bug. What happens next depends on how the program was built. Rayo builds a program in one of two modes: `debug`, for while you're developing, and `release`, for when you ship ([10](../spec/10-errors-and-safety/checks-and-build-modes.md#build-modes)).

A `debug` build checks every addition, subtraction and multiplication. When one overflows, the program stops right there and reports where it happened. Stopping like this is called a **panic**. A `release` build leaves the checks out so the program runs faster, and an overflowing result wraps around, past the largest value to the smallest, so the wrong number carries on unnoticed.

Sometimes going past the limit isn't a bug. A hash function relies on numbers wrapping around, and a meter that fills up should simply stop when it's full. For those cases, Rayo has operators, such as `&+` and `+|`, that say what to do at the limit, so they never panic:

```swift
let b = hp8 &+ 10               // -126: wraps around
let c = hp8 +| 10               // 127: stops at the largest Int8
```

Dividing a whole number by zero always panics, in both modes, since no answer would make sense ([04](../spec/04-types/numbers-and-math.md#integer-overflow-division-and-shifts)).

## Values with fields

So far, health has been a number on its own. A game needs to keep it beside an enemy's position and velocity. A `struct` gives those values one name:

```swift
import std.math

struct Enemy(
    var pos: Vec3,
    var vel: Vec3 = .zero,
    var hp: Float = 100,
)

var enemy = Enemy(pos: .zero)
enemy.hp -= 30
```

`Enemy` has three fields. The call supplies `pos`; `vel` and `hp` take their declared defaults. `Vec3` is a three-number vector from `std.math` ([04](../spec/04-types/numbers-and-math.md#simd-and-math)). `enemy` is a `var` because the program changes one of its fields. Later chapters use this same `Enemy` to show what happens when a value moves, is borrowed, or is stored in a pool.

## Functions

A function takes some values, does its work, and can give a value back ([05](../spec/05-protocols-generics-and-closures/functions-and-closures.md#functions-and-closures)):

```swift
func burnDamage(perSecond: Float, seconds: Float) -> Float {
    perSecond * seconds
}

let burn = burnDamage(perSecond: 12.5, seconds: 3)     // 37.5
```

`-> Float` says that `burnDamage` gives back a `Float`. A call to `burnDamage` writes each parameter's name next to its value, in the order they're declared, so `burnDamage(perSecond: 12.5, seconds: 3)` shows which number is which without a trip to the declaration.

When a function that returns a value has a body of one expression, like `burnDamage`, that expression's value is what it returns. A longer body says what it returns with `return`:

```swift
func average(total: Float, count: Int) -> Float {
    let n = Float(count)
    return total / n
}
```

A function that gives nothing back leaves out the `->`:

```swift
func report(hp: Int) {
    log("hp is \(hp)")
}
```

Inside `report`, `hp` behaves like a `let`: `report` can read it, but not change it. Chapter 3 shows the other ways a function can take a parameter, including one that lets it change a variable you pass it ([Borrowing](03-borrowing.md)).

## Making decisions with `if`

An `if` runs code only when a condition holds:

```swift
if hp <= 0 {
    log("defeated")
} else if hp < 30 {
    log("badly hurt")
} else {
    log("still fighting")
}
```

A condition is a `Bool`, a value that is either `true` or `false`. Comparisons such as `hp <= 0` give you one, and you can combine them with `&&` (and), `||` (or) and `!` (not), as in `hp > 0 && !shielded`.

An `if` can also give back a value, the value of whichever branch ran. That's handy when a variable's starting value depends on a condition:

```swift
let bonus = if boosted { 10 } else { 0 }
```

Without this, you'd have to declare `bonus` as a `var` and set it in each branch. It also takes the place of the `? :` operator of C and Java, which Rayo doesn't have. Since the `if` has to produce a value either way, it needs an `else`, and both branches must give the same type, here an `Int` ([04](../spec/04-types/enums.md#matching-with-when-and-choosing-with-if)).

## Loops

A `while` loop repeats its body for as long as a condition holds, checking it before each pass. This one counts how many seconds an enemy lasts under steady damage:

```swift
var hp = 100
var seconds = 0
while hp > 0 {
    hp -= 12
    seconds += 1
}
log("defeated after \(seconds) seconds")       // defeated after 9 seconds
```

When you know how many times to repeat, a `for` loop over a **range** is simpler:

```swift
for wave in 1...3 {
    log("wave \(wave)")
}
```

The range `1...3` holds the numbers 1, 2 and 3, and the loop runs once for each, with `wave` holding the current one. A range written `0..<count` stops just before `count`, like `i < count` in a C or Java loop, so a loop over it runs `count` times ([04](../spec/04-types/collections.md#tuples-ranges-and-arrays)).

Inside any loop, `continue` skips the rest of the current pass, and `break` leaves the loop altogether:

```swift
for i in 0..<100 {
    if i % 2 == 0 { continue }      // skip the even numbers
    if i > 7 { break }              // stop after 7
    log("\(i)")                     // 1, 3, 5, 7
}
```

## In the spec

- [04 Types](../spec/04-types/numbers-and-math.md#numbers): the number types, how a number written in the code takes its type, and which conversions happen on their own.
- [04 Types](../spec/04-types/numbers-and-math.md#integer-overflow-division-and-shifts): what every integer operation does at its limits.
- [05 Protocols, generics and closures](../spec/05-protocols-generics-and-closures/functions-and-closures.md#functions-and-closures): functions, their parameters and what they return.
- [10 Errors and safety](../spec/10-errors-and-safety/checks-and-build-modes.md#build-modes): the build modes, and the checks each one keeps.
