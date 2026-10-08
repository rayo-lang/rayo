# 3 · Borrowing

A function can do one of three things with a value you pass it: read it, change it, or keep it. In Rayo, each parameter says which ([01](../spec/01-values-and-ownership/parameters.md#parameters)).

A function that adds up a list of hits only reads the list, and one that heals a player changes the player's health. Neither keeps what it's given. Both borrow it instead: they use your value while the call runs, and you keep owning it. Only a function that keeps the value, such as `archive`, takes it from you ([Moves and copies](02-moves-and-copies.md#moves)).

A borrow can go wrong if the memory it reads is freed while the borrow still uses it. Say code borrows one of the values in a list, and then the list grows. Growing may transfer the list's values to a bigger block of memory, and free the old one. The borrow would be left dangling, reading memory that no longer holds the value. The compiler rejects code like this when it compiles it, so the program never runs with a dangling borrow ([01](../spec/01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)).

## Borrowing to read

Here is a function that adds up a list of hits:

```swift
func total(list: List<Int>) -> Int {
    var sum = 0
    for h in list {
        sum += h
    }
    return sum
}

var hits = List<Int>()
hits.append(12)
hits.append(30)
let damage = total(list: hits)          // 42
```

`list` has nothing written before its type, so `total` borrows the list to read it. This is a **shared borrow**, since any number of borrows can read the same value at once.

Inside `total`, `list` is another name for the caller's list, as `same` was another name for `hits`. `total` can read the list through it, but it can't change the list, move it or keep it.

Underneath, the compiler passes `total` either the list's address or a copy of the list's few bytes. The compiler picks one for each parameter from the function's declaration, so every caller passes it the same way. Your code works the same either way. Nothing on the heap is copied.

Those bytes aren't a second list. Nothing owns them, so nothing destroys them, and the heap memory is still freed only once. They can't go stale either. `total` can only read the list, and the compiler makes sure that no other code changes it until `total` returns ([The law of exclusivity](#the-law-of-exclusivity)).

An `Int` borrowed to read can be passed as a copy of its bytes the same way. So borrowing an `Int` can cost no more than copying it ([01](../spec/01-values-and-ownership/parameters.md#borrowed-arguments)).

`total` can read the list, but it can't hand it over to anyone. Here is a function that tries, by returning the longer of two lists:

```swift
func longer(a: List<Int>, b: List<Int>) -> List<Int> {
    if a.count >= b.count { return a }      // error: 'a' is only borrowed, so it can't move out
    return b                                // error: 'b' is only borrowed, so it can't move out
}
```

`return` hands the caller a value that the function owns ([Moves and copies](02-moves-and-copies.md#declaring-assigning-and-returning)). A plain parameter owns nothing. It's like a `let` that borrows, such as `let same = borrow hits`: it can't change, and it has nothing of its own to hand over.

`longer`'s parameters have nothing written before their types, so its declaration tells every caller that both lists stay theirs. Returning one would break that promise. After `longer(a: hits, b: misses)`, the caller would still use `hits` and `misses`, but one of them would hold nothing.

To return a list, `longer` has to build one that it owns, with `clone()` ([Moves and copies](02-moves-and-copies.md#copies)):

```swift
func longer(a: List<Int>, b: List<Int>) -> List<Int> {
    if a.count >= b.count { return a.clone() }
    return b.clone()
}
```

A clone copies every value. A function can also hand back a view of a list it borrowed, which copies nothing ([Views](04-views.md)).

An `Int` follows the same rule:

```swift
func atLeastZero(hp: Int) -> Int {
    if hp < 0 { return 0 }
    return hp                   // error: 'hp' is only borrowed, so it can't move out
}
```

For an `Int`, a copy is what you'd want anyway. Rayo still asks you to write it, since it never makes a second value unless you ask, whatever the type ([Moves and copies](02-moves-and-copies.md#adding-to-a-list)). Here, `copy hp` copies the `Int`'s few bytes, and nothing more:

```swift
func atLeastZero(hp: Int) -> Int {
    if hp < 0 { return 0 }
    return copy hp
}
```

Declaring a variable from a borrowed parameter needs a copy too, for the same reason. Here a function counts the turns of healing it takes to reach a target, and keeps a running value of its own:

```swift
func turnsToHeal(hp: Int, target: Int) -> Int {
    var current = hp            // error: 'hp' is only borrowed, so it can't move out
    var turns = 0
    while current < target {
        current += 15
        turns += 1
    }
    return turns
}
```

A declaration takes its value, as `return` does ([Moves and copies](02-moves-and-copies.md#declaring-assigning-and-returning)), and `hp` isn't `turnsToHeal`'s to give. So `turnsToHeal` copies it:

```swift
var current = copy hp
```

## Borrowing to change

A plain parameter can't be changed, so this `heal` doesn't compile:

```swift
func heal(hp: Int) {
    hp += 20                    // error: 'hp' is borrowed, so 'heal' can't change it
}
```

You might expect `hp` to be `heal`'s own copy, which it could change freely. Say a caller passes a variable that holds 40. `heal` would change only its copy, and the caller's variable would still hold 40 when `heal` returns. Nothing would tell you that the healing was lost. For a list, the copy would also be a hidden clone, allocating memory on every call.

So a plain parameter only borrows, whether it holds an `Int` or a list. A function that wants a value of its own to change can copy or clone it, as `turnsToHeal` copies `hp` into `current`. Or it can take the value `owned`, as `archive` does. An `owned` parameter is the function's own, as a `var`'s value is, so the function can change it. The caller gives the value up in exchange.

To change the caller's variable itself, the function asks for a `mutable` parameter:

```swift
func heal(hp: mutable Int) {
    hp += 20
}

var playerHp = 40
heal(hp: &playerHp)
log("hp \(playerHp)")           // hp 60
```

`heal` borrows `playerHp` so that it can change it, and every change it makes to `hp` happens to `playerHp` itself. This is a **mutable borrow**. Since `heal` must reach `playerHp` itself, it gets `playerHp`'s address underneath. You never see that address: inside `heal`, you read and assign `hp` directly.

With `&`, you lend `playerHp` to `heal`, and leaving the `&` out is an error:

```swift
heal(hp: playerHp)              // error: a mutable argument needs '&'
```

The `&` is there so that you can see the change. A move needs no mark, since the compiler stops you if you use the variable again. A change gives no such warning. `playerHp` would just hold a different number, with nothing in the call to say why. So among the arguments in a call's parentheses, the ones marked `&` are the ones it may change.

The value before the dot needs no `&`, even when the method changes it, as `hits.append(5)` changes `hits`. The call names that value as the one it acts on. So you know which value might change, though not whether it does. The method's declaration says whether it changes the value. `append`'s does, and `clone()`'s doesn't ([01](../spec/01-values-and-ownership/bindings.md#lending-a-place-for-change)).

Whether through an `&` argument or the value before the dot, a call can change only a variable you could change yourself:

```swift
let startHp = 100
heal(hp: &startHp)              // error: 'startHp' is a 'let', so it can't change
let done = List<Int>()
done.append(7)                  // error: 'done' is a 'let', so it can't change
```

A `mutable` parameter is one the function can change, so the function can lend it on:

```swift
func healTwice(hp: mutable Int) {
    heal(hp: &hp)
    heal(hp: &hp)
}
```

Each `heal(hp: &hp)` lends `heal` the variable that `healTwice` borrowed from its caller, such as `playerHp`. Underneath, `heal` gets the same address that `healTwice` got.

## Borrowing in a declaration

A declaration can borrow too. Declaring a variable from another one moves the value, so a declaration that borrows has to say so. You've seen `let same = borrow hits`, which borrows a list to read it ([Moves and copies](02-moves-and-copies.md#declaring-assigning-and-returning)).

To borrow something to change it, write `&` before it, as in a call. Declare the name with `var`, since you'll change the value through it. Here `first` borrows `hits[0]`, which is the list's first element:

```swift
var hits = List<Int>()
hits.append(12)
hits.append(30)
var first = &hits[0]
first += 5
log("\(hits[0])")               // 17
```

`first` is another name for `hits[0]`, so every change to `first` lands on the element ([01](../spec/01-values-and-ownership/bindings.md#bindings)). Even assigning to `first` assigns to the element: `first = 0` would set `hits[0]` to 0, rather than point `first` somewhere else.

Reading an element is fine, as the `log` call does. Declaring a variable from the element itself isn't:

```swift
let top = hits[0]               // error: an element can't move out of its list
```

A declaration takes its value, and an element can't leave its list. If it could, the list would still count two values, but its first one would be gone. For an `Int`, copy the element instead:

```swift
let top = copy hits[0]
```

In a list of lists, though, each element is a whole list. `copy` is an error there, since a list isn't copyable, and `clone()` would allocate a second list. A borrow reads the element where it sits, and gives it a short name:

```swift
var rounds = List<List<Int>>()
rounds.append(hits.clone())
let latest = borrow rounds[rounds.count - 1]
log("\(latest.count) hits, \(total(list: latest)) damage")
```

`latest` names the last round, so the `log` call doesn't have to repeat `rounds[rounds.count - 1]`.

## Changing a list while it's borrowed

While `latest` borrows an element of `rounds`, `rounds` can't change:

```swift
let latest = borrow rounds[rounds.count - 1]
rounds.append(List<Int>())      // error: 'rounds' is borrowed by 'latest' (used below)
log("\(latest.count) hits")
```

`rounds` keeps its lists in one block of heap memory, and `latest` refers to the last of them where it sits in that block. If `append` needed more room than the block has, it would allocate a bigger block, transfer the lists to it, and free the old block. `latest` would still refer to the old block, and `latest.count` would read freed memory.

The compiler can't know whether an `append` will need a bigger block, and doesn't try. While `latest` is in use, it rejects any change to `rounds`. A borrow doesn't last to the end of its block, though. It ends at its last use. So the fix is to finish with `latest` first ([01](../spec/01-values-and-ownership/bindings.md#how-long-a-borrow-lasts)):

```swift
let latest = borrow rounds[rounds.count - 1]
log("\(latest.count) hits")
rounds.append(List<Int>())
```

Moving a list away counts as changing it too:

```swift
let same = borrow hits
archive(list: hits)             // error: 'hits' is borrowed by 'same' (used below)
log("\(same.count)")
```

`same.count` would read a list that `hits` no longer holds. Assigning a new list to `hits` is an error too, since assigning changes `hits`. `same` is a `let`, so it must keep reading the list it started with.

## Loops

A `for` loop over `hits` borrows the list for its whole run, and on each pass, `h` names one element where it sits. The loop only reads the list, so `h` can't change:

```swift
for h in hits {
    h += 5                      // error: 'h' is borrowed, so the loop can't change it
}
```

To change the elements, lend the list to the loop with `&`. Then each `h` may change its element, so `h += 5` changes `hits` ([04](../spec/04-types/collections.md#iteration)):

```swift
for h in &hits {
    h += 5
}
```

Since the loop borrows the whole list, its body can't change the list itself:

```swift
for h in hits {
    if h > 20 {
        hits.append(copy h)     // error: 'hits' is borrowed by the loop
    }
}
```

This is the same problem as with `latest`: `append` may transfer the values to a bigger block while the loop still reads the old one.

To add values that the loop finds, collect them in a list of their own. Then add them once the loop is done:

```swift
var big = List<Int>()
for h in hits {
    if h > 20 { big.append(copy h) }
}
for b in big {
    hits.append(copy b)
}
```

The first loop borrows `hits` and changes `big`, which is a different list. Each `h` only borrows its element, so `big` gets a copy of it. The second loop borrows `big` and changes `hits`, which nothing borrows any more.

## The law of exclusivity

The errors with `latest`, `same` and the loop that appended to `hits` all come from one rule, the **law of exclusivity** ([01](../spec/01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)). It's a rule about **places**. A place is anything that holds a value, such as a variable or one element of a list.

The law says that at any moment, a place can have any number of readers, or a single changer and nothing else.

Every read or change of a place uses it. A borrow keeps using its place until the last line that uses the borrow. A list holds its elements, so using the list uses each of them. That's why `rounds.append` clashed with `latest`, which was still using one of the elements.

Reads can happen together. A read changes nothing, so it can't spoil another read. That's why any number of shared borrows can be in use at once. Here the loop and `total` both borrow `hits` to read it at the same time, which is fine:

```swift
for h in hits {
    log("\(h) of \(total(list: hits))")
}
```

A change can't happen while a shared borrow is in use, even a change that frees nothing:

```swift
var hp = 100
let before = borrow hp
hp -= 10                        // error: 'hp' is borrowed by 'before' (used below)
log("lost \(before - hp)")
```

If the change were allowed, `before` would read 90, since it's another name for `hp`, and the log would say "lost 0". With `let before = copy hp`, `before` holds a value of its own, and keeps the 100 ([Moves and copies](02-moves-and-copies.md#declaring-assigning-and-returning)).

A mutable borrow is the strictest case. While it's in use, no other use of its place may happen at all, not even a read. That's what makes a mutable borrow **exclusive**, and it's where the law gets its name.

Here `i` is an index that the program works out while it runs, and `top` borrows the first hit of the first round to change it:

```swift
var top = &rounds[0][0]
rounds[i] = List<Int>()         // error: 'rounds' is mutably borrowed by 'top' (used below)
top += 5
```

When `i` is 0, the assignment destroys the first round, and frees the block that holds its hits. Then `top += 5` would write to freed memory.

The compiler doesn't compare indexes into a list, so even `rounds[1] = List<Int>()` is rejected here. `rounds[1]` isn't plain address arithmetic. It runs the list's own code to find the element, and that code could reach any part of the list. So a use of any element counts as a use of the whole list.

A read can clash with a mutable borrow too. One call can do it alone, when it gets the same list twice:

```swift
func addAll(target: mutable List<Int>, source: List<Int>) {
    for x in source {
        target.append(copy x)
    }
}

addAll(target: &hits, source: hits)     // error: two borrows of 'hits' overlap for the whole call
```

The compiler doesn't look inside `addAll` to find this. Its declaration alone says that `target` may change a list while `source` reads one. Here both are `hits`, so the loop over `source` would read the list while `append` changes it. If `append` transferred the values to a bigger block, the loop would go on reading the old block, which has been freed.

The fix is to give `addAll` a second list to read. A clone is worth its cost here, since `addAll` needs the values as they were before it started appending:

```swift
addAll(target: &hits, source: hits.clone())
```

A call works in two steps. First, it works out its arguments, left to right. Here, `hits.clone()` reads `hits`, builds a new list, and is done with `hits`. Working out `&hits` only finds the place to lend. The lending starts when the call begins, after the clone is made ([01](../spec/01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin)). The clone's read of `hits` ends before the call's change begins. During the call, `addAll` reads one list and changes another.

A value that a call makes and nothing names, such as this clone, is a **temporary**. It lives only until the end of the statement that made it, unless an `owned` parameter takes it ([02](../spec/02-views-and-dependencies/dependency-projection-and-results.md#temporaries)). `addAll` only borrows the clone, so the clone is destroyed at the end of this statement. In `rounds.append(hits.clone())`, `append` took its clone, and `rounds` owns it.

The compiler checks the law when it compiles, in every build. So for the values in this chapter, the check costs nothing while the program runs.

Some values bend this chapter's rules. A value that several pointers can reach can't always be checked while compiling, so it's checked while the program runs instead ([Handles and objects](05-handles-and-objects.md)). And a `Mutex` can change with no `&`, even while it's borrowed to read. Its lock lets only one piece of code use what it holds at a time, whether to read it or to change it ([Concurrency](07-concurrency.md)).

## In the spec

- [01 Parameters](../spec/01-values-and-ownership/parameters.md#parameters): the three ways a function takes an argument.
- [01 Borrowed arguments](../spec/01-values-and-ownership/parameters.md#borrowed-arguments): when a borrowed argument is passed as its bits, and when as the caller's place.
- [01 What can be moved from](../spec/01-values-and-ownership/moving-values-out.md#what-can-be-moved-from): which places can be moved from, and what to do with the rest.
- [01 Changeable places](../spec/01-values-and-ownership/bindings.md#changeable-places): every place that can be changed or lent with `&`.
- [01 Lending a place for change](../spec/01-values-and-ownership/bindings.md#lending-a-place-for-change): every place that takes `&`, and why the value a method is called on doesn't.
- [01 Bindings](../spec/01-values-and-ownership/bindings.md#bindings): `borrow` and `&` in a declaration, and how long a borrow lasts.
- [01 Evaluation order](../spec/01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin): the order a call works out its parts, and when its borrows begin.
- [01 The law of exclusivity](../spec/01-values-and-ownership/exclusivity.md#the-law-of-exclusivity): which places overlap, two elements of one list at once, and the values checked while the program runs.
- [02 Temporaries](../spec/02-views-and-dependencies/dependency-projection-and-results.md#temporaries): how long a value that nothing names lives.
- [04 Iteration](../spec/04-types/collections.md#iteration): how a `for` loop borrows the list it runs over.
