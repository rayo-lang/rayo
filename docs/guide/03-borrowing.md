# 3 · Borrowing

A function can do one of three things with a value you pass it: read it, change it, or keep it. In Rayo, each parameter's type says which ([01](../spec/01-values-and-ownership/parameters.md#parameters)).

A function that adds up the game's list of hits only reads it, and one that heals an enemy changes its health. Neither keeps what it's given. Both borrow it instead: they use your value while the call runs, and you keep owning it. Only a function that keeps the value, such as `archive`, takes it from you ([Moves and copies](02-moves-and-copies.md#moves)).

A borrow can go wrong if the memory it reads is freed while the borrow still uses it. Say code borrows one of the values in a list, and then the list grows. Growing may transfer the list's values to a bigger block of memory, and free the old one. The borrow would be left dangling, reading memory that no longer holds the value. The compiler rejects code like this when it compiles it, so the program never runs with a dangling borrow ([01](../spec/01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)).

## Borrowing to read

Here is a function that adds up a list of hits:

```rayo
func total(list: &List<Int>) -> Int {
    var sum = 0
    for h in &list {
        sum += h
    }
    return sum
}

var hits = alloc List<Int>()
hits.append(12)
hits.append(30)
let damage = total(list: hits)          // 42
```

`list`'s type is `&List<Int>`, a reference to a list, so `total` borrows the list to read it. This is a **shared borrow**, since any number of borrows can read the same value at once.

The call writes `hits` with no mark, and still lends the list rather than giving it away. The parameter's type says that `total` only borrows, and a borrow costs the caller nothing: the caller keeps owning the list throughout. A name with no mark never moves a list either, since a move always writes `consume`. So a `&` before `hits` would tell a reader nothing new ([05](../spec/05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected)). Writing `total(list: &hits)` means the same thing.

The loop is different. A loop has no parameter type to say how it takes the list, so `for h in &list` writes `&` to lend the list on and read its elements, as [Loops](#loops) below shows.

Inside `total`, `list` is another name for the caller's list, as `same` referred to `hits` in chapter 2. `total` can read the list through it, but it can't change the list, move it or keep it ([01](../spec/01-values-and-ownership/references.md#references)).

Underneath, the compiler passes `total` either the list's address or a copy of the list's few bytes. The compiler picks one for each parameter from the function's declaration, so every caller passes it the same way. Your code works the same either way. Nothing on the heap is copied ([01](../spec/01-values-and-ownership/parameters.md#borrowed-arguments)).

Those bytes aren't a second list. Nothing owns them, so nothing destroys them, and the heap memory is still freed only once. They can't go stale either. `total` can only read the list, and the compiler makes sure that no other code changes it until `total` returns ([The law of exclusivity](#the-law-of-exclusivity)).

`total` can read the list, but it can't hand it over to anyone. Here is a function that tries, by returning the longer of two lists:

```rayo
func longer(a: &List<Int>, b: &List<Int>) -> List<Int> {
    if a.count >= b.count { return consume a }      // error: 'a' is only borrowed, so it can't move out
    return consume b                                // error: 'b' is only borrowed, so it can't move out
}
```

`return` hands the caller a value that the function owns ([Moves and copies](02-moves-and-copies.md#declaring-assigning-and-returning)). A `&T` parameter owns nothing. Like `same` in chapter 2, it refers to a list someone else owns, and has nothing of its own to hand over.

`longer`'s parameters are references, so its declaration tells every caller that both lists stay theirs. Returning one would break that promise. After `longer(a: hits, b: misses)`, the caller would still use `hits` and `misses`, but one of them would hold nothing.

To return a list, `longer` has to build one that it owns, with `clone()` ([Moves and copies](02-moves-and-copies.md#copies)). That makes it an `alloc func`, as `newRound` is:

```rayo
alloc func longer(a: &List<Int>, b: &List<Int>) -> List<Int> {
    if a.count >= b.count { return alloc a.clone() }
    return alloc b.clone()
}
```

A clone copies every value. A function can also hand back a view of a list it borrowed, which copies nothing ([Views](04-views.md)).

A borrowed `Enemy` follows the same rule:

```rayo
func healthier(a: &Enemy, b: &Enemy) -> Enemy {
    if a.hp >= b.hp { return consume a }    // error: 'a' is only borrowed, so it can't move out
    return copy b                           // fine: a copy of the enemy is the function's own
}
```

`copy b` copies the enemy's few bytes, and nothing more.

A function that reads an `Int` usually takes it as a plain `Int` instead. The caller's number is copied in, with nothing written, since an `Int` is implicitly copyable and its copy costs no more than a borrow would ([Moves and copies](02-moves-and-copies.md#adding-to-a-list)). Returning it copies it again:

```rayo
func atLeastZero(hp: Int) -> Int {
    if hp < 0 { return 0 }
    return hp                   // a copy of the function's own Int
}

let shown = atLeastZero(hp: damage)     // no mark: a copy goes in
```

## Borrowing to change

A parameter with a plain type owns what it's given, as `archive`'s list does. So the function may change it, as a `var`'s value can change. For an `Int`, that is a copy of the caller's number:

```rayo
func turnsToHeal(hp: Int, target: Int) -> Int {
    var turns = 0
    while hp < target {
        hp += 15                // changes the function's own copy
        turns += 1
    }
    return turns
}
```

The caller's variable stays as it was, and the call shows it: `turnsToHeal(hp: current, target: 100)` writes no mark before `current`, so the call can't change it.

To change the caller's variable itself, the function asks for a `mutable &T` parameter, a mutable reference:

```rayo
func heal(hp: mutable &Int) {
    hp += 20
}

var enemyHp = 40
heal(hp: mutable enemyHp)
log("hp \(enemyHp)")            // hp 60
```

`heal` borrows `enemyHp` so that it can change it, and every change it makes to `hp` happens to `enemyHp` itself. This is a **mutable borrow**. Since `heal` must reach `enemyHp` itself, it gets `enemyHp`'s address underneath. You never see that address: inside `heal`, you read and assign `hp` directly.

With `mutable`, you lend `enemyHp` to `heal`. The mark is one word, with no `&`: the parameter's type, `mutable &Int`, says that `heal` gets a reference, and the mark says what the call does to `enemyHp`, which is to lend it for change. Leaving the mark out is an error:

```rayo
heal(hp: enemyHp)               // error: 'heal' takes 'mutable &Int'; write 'mutable enemyHp'
```

The marks are there so that you can see what a call does with each variable: `consume` moves it, and `mutable` lends it to change. A variable with no mark is only lent to read or copied, so it comes back from the call as it went in. A change gives no warning later. `enemyHp` would just hold a different number, with nothing in the call to say why. So among the arguments in a call's parentheses, the ones marked `mutable` are the ones it may change ([01](../spec/01-values-and-ownership/references.md#places-given-to-a-position)).

The value before the dot needs no mark, even when the method changes it, as `hits.append(5)` changes `hits`. The call names that value as the one it acts on. So you know which value might change, though not whether it does. The method's declaration says whether it changes the value. `append`'s does, and `clone()`'s doesn't ([01](../spec/01-values-and-ownership/references.md#unmarked-places)).

Whether through a `mutable` argument or the value before the dot, a call can change only a variable you could change yourself:

```rayo
let startHp = 100
heal(hp: mutable startHp)       // error: 'startHp' is a 'let', so it can't change
let done = alloc List<Int>()
done.append(7)                  // error: 'done' is a 'let', so it can't change
```

A `mutable &T` parameter names the caller's variable, which the function can change, so the function can lend it on:

```rayo
func healTwice(hp: mutable &Int) {
    heal(hp: mutable hp)
    heal(hp: mutable hp)
}
```

Each `heal(hp: mutable hp)` lends `heal` the variable that `healTwice` borrowed from its caller, such as `enemyHp`. Underneath, `heal` gets the same address that `healTwice` got.

## Borrowing in a declaration

You've seen `same`, a `let` that holds a reference to a list ([Moves and copies](02-moves-and-copies.md#declaring-assigning-and-returning)). A declaration that begins with `ref` goes one step further: it takes a reference and names the place it refers to, the way a `&T` parameter names the caller's value.

To borrow something to change it, declare the name with `ref var`, and write `mutable` before what it borrows, as in a call. Here `first` borrows `hits[0]`, which is the list's first element:

```rayo
var hits = alloc List<Int>()
hits.append(12)
hits.append(30)
ref var first = mutable hits[0]
first += 5
log("\(hits[0])")               // 17
```

`first` is another name for `hits[0]`, so every change to `first` lands on the element ([01](../spec/01-values-and-ownership/bindings.md#bindings-that-refer-to-a-place)). Even assigning to `first` assigns to the element: `first = 0` would set `hits[0]` to 0, rather than point `first` somewhere else. The `var` in `ref var` says that the element may change through `first`, not that `first` may come to name something else.

The word and the mark have to agree, and a mismatch is an error:

```rayo
ref var first = hits[0]             // error: write 'mutable hits[0]'
ref var first = &hits[0]            // error: write 'mutable hits[0]'
ref let first = mutable hits[0]     // error: 'mutable' lends for change; declare 'ref var'
```

Every borrow that changes a value says so with `mutable`, in a declaration as at a call. A `ref let` changes nothing, so it takes `&`. A `ref let`, like a `let` with no type written, has no type to say that it borrows, so the `&` is written there, and `ref let first = hits[0]` is an error that asks for it.

A `var` that holds a reference is different from a `ref var`: it is a variable of its own, so assigning it a new reference points it somewhere else ([01](../spec/01-values-and-ownership/bindings.md#bindings-that-own-a-value)):

```rayo
var pick = &hits[0]
pick = hits[1]                  // 'pick' holds a '&Int', so 'hits[1]' is lent: 'pick' refers to the second hit
```

A `ref let` of an element borrows it to read, as `same` borrows the whole list. Moving the element out, though, is an error:

```rayo
let top = consume hits[0]       // error: an element can't move out of its list
```

An element can't leave its list. If it could, the list would still count two values, but its first one would be gone. For an `Int`, a `let` gets a copy of the element, a value of its own, with nothing written:

```rayo
let top = hits[0]
```

In a list of lists, though, each element is a whole list. `copy` is an error there, since a list isn't copyable, and `clone()` would allocate a second list. A borrow reads the element where it sits, and gives it a short name:

```rayo
var rounds = alloc List<List<Int>>()
rounds.append(alloc hits.clone())
ref let latest = &rounds[rounds.count - 1]
log("\(latest.count) hits, \(total(list: latest)) damage")
```

`latest` names the last round, so the `log` call doesn't have to repeat `rounds[rounds.count - 1]`.

## Changing a list while it's borrowed

While `latest` borrows an element of `rounds`, `rounds` can't change:

```rayo
ref let latest = &rounds[rounds.count - 1]
rounds.append(alloc List<Int>())  // error: 'rounds' is borrowed by 'latest' (used below)
log("\(latest.count) hits")
```

`rounds` keeps its lists in one block of heap memory, and `latest` refers to the last of them where it sits in that block. If `append` needed more room than the block has, it would allocate a bigger block, transfer the lists to it, and free the old block. `latest` would still refer to the old block, and `latest.count` would read freed memory.

The compiler can't know whether an `append` will need a bigger block, and doesn't try. While `latest` is in use, it rejects any change to `rounds`. A borrow doesn't last to the end of its block, though. It ends at its last use. So the fix is to finish with `latest` first ([01](../spec/01-values-and-ownership/bindings.md#how-long-a-borrow-lasts)):

```rayo
ref let latest = &rounds[rounds.count - 1]
log("\(latest.count) hits")
rounds.append(alloc List<Int>())
```

Moving a list away counts as changing it too:

```rayo
let same = &hits
archive(list: consume hits)     // error: 'hits' is borrowed by 'same' (used below)
log("\(same.count)")
```

`same.count` would read a list that `hits` no longer holds. Assigning a new list to `hits` is an error too, since assigning changes `hits`. `same` refers to the list in `hits`, so that list must stay there while `same` is used.

## Loops

A `for` loop writes how it takes its list, since no parameter type says it. `&hits` lends the list to read, `mutable hits` lends it to change its elements, and `consume hits` hands the elements over. A loop over `&hits` borrows the list for its whole run, and on each pass, `h` names one element where it sits, read-only:

```rayo
for h in &hits {
    h += 5                      // error: 'h' is a 'ref let'; write 'mutable hits' to change the elements
}
```

To change the elements, lend the list to the loop with `mutable`. Then each `h` may change its element, so `h += 5` changes `hits` ([04](../spec/04-types/collections.md#iteration)):

```rayo
for h in mutable hits {
    h += 5
}
```

Since the loop borrows the whole list, its body can't change the list itself:

```rayo
for h in &hits {
    if h > 20 {
        hits.append(h)          // error: 'hits' is borrowed by the loop
    }
}
```

This is the same problem as with `latest`: `append` may transfer the values to a bigger block while the loop still reads the old one.

To add values that the loop finds, collect them in a list of their own. Then add them once the loop is done:

```rayo
var big = alloc List<Int>()
for h in &hits {
    if h > 20 { big.append(h) }
}
for b in consume big {
    hits.append(b)
}
```

The first loop borrows `hits` and changes `big`, which is a different list, and `big.append(h)` gets a copy of each `Int` it's given. The second loop takes `big` over with `consume`, so each `b` owns one value, and hands it to `hits`, which nothing borrows any more.

## The law of exclusivity

The errors with `latest`, `same` and the loop that appended to `hits` all come from one rule, the **law of exclusivity** ([01](../spec/01-values-and-ownership/exclusivity.md#the-law-of-exclusivity)). It's a rule about **places**. A place is anything that holds a value, such as a variable or one element of a list.

The law says that at any moment, a place can have any number of readers, or a single changer and nothing else.

Every read or change of a place uses it. A borrow keeps using its place until the last line that uses the borrow. A list holds its elements, so using the list uses each of them. That's why `rounds.append` clashed with `latest`, which was still using one of the elements.

Reads can happen together. A read changes nothing, so it can't spoil another read. That's why any number of shared borrows can be in use at once. Here the loop and `total` both borrow `hits` to read it at the same time, which is fine:

```rayo
for h in &hits {
    log("\(h) of \(total(list: hits))")
}
```

A change can't happen while a shared borrow is in use, even a change that frees nothing:

```rayo
var hp = 100
let before = &hp
hp -= 10                        // error: 'hp' is borrowed by 'before' (used below)
log("lost \(before - hp)")
```

If the change were allowed, `before` would read 90, since it refers to `hp`, and the log would say "lost 0". With `let before = hp`, `before` holds a copy of its own, and keeps the 100 ([Moves and copies](02-moves-and-copies.md#declaring-assigning-and-returning)).

A mutable borrow is the strictest case. While it's in use, no other use of its place may happen at all, not even a read. That's what makes a mutable borrow **exclusive**, and it's where the law gets its name.

Here `i` is an index that the program works out while it runs, and `top` borrows the first hit of the first round to change it:

```rayo
ref var top = mutable rounds[0][0]
rounds[i] = alloc List<Int>()   // error: 'rounds' is mutably borrowed by 'top' (used below)
top += 5
```

When `i` is 0, the assignment destroys the first round, and frees the block that holds its hits. Then `top += 5` would write to freed memory.

The compiler doesn't compare indexes into a list, so even `rounds[1] = alloc List<Int>()` is rejected here. `rounds[1]` isn't plain address arithmetic. It runs the list's own code to find the element, and that code could reach any part of the list. So a use of any element counts as a use of the whole list.

A read can clash with a mutable borrow too. One call can do it alone, when it gets the same list twice:

```rayo
func addAll(target: mutable &List<Int>, source: &List<Int>) {
    for x in &source {
        target.append(x)
    }
}

addAll(target: mutable hits, source: hits)      // error: two borrows of 'hits' overlap for the whole call
```

The compiler doesn't look inside `addAll` to find this. Its declaration alone says that `target` may change a list while `source` reads one. Here both are `hits`, so the loop over `source` would read the list while `append` changes it. If `append` transferred the values to a bigger block, the loop would go on reading the old block, which has been freed.

The fix is to give `addAll` a second list to read. A clone is worth its cost here, since `addAll` needs the values as they were before it started appending:

```rayo
addAll(target: mutable hits, source: alloc hits.clone())
```

A call works in two steps. First, it works out its arguments, left to right. Here, `alloc hits.clone()` reads `hits`, builds a new list, and is done with `hits`. Working out `mutable hits` only finds the place to lend. The lending starts when the call begins, after the clone is made ([01](../spec/01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin)). The clone's read of `hits` ends before the call's change begins. During the call, `addAll` reads one list and changes another.

A value that a call makes and nothing names, such as this clone, is a **temporary**. It lives only until the end of the statement that made it, unless a parameter that owns its argument takes it ([02](../spec/02-views-and-dependencies/dependency-projection-and-results.md#temporaries)). `source` only borrows the clone, so the clone is destroyed at the end of this statement. In `rounds.append(alloc hits.clone())`, `append` took its clone, and `rounds` owns it.

The compiler checks the law when it compiles, in every build. So for the values in this chapter, the check costs nothing while the program runs.

Some values bend this chapter's rules. A value that several pointers can reach can't always be checked while compiling, so it's checked while the program runs instead ([Handles and objects](05-handles-and-objects.md)). And a `Mutex` can change with no `mutable`, even while it's borrowed to read. Its lock lets only one piece of code use what it holds at a time, whether to read it or to change it ([Concurrency](07-concurrency.md)).

## In the spec

- [01 Parameters](../spec/01-values-and-ownership/parameters.md#parameters): the three ways a function takes an argument.
- [01 References](../spec/01-values-and-ownership/references.md#references): `&T` and `mutable &T`, how they're made, and which of them copy.
- [01 Borrowed arguments](../spec/01-values-and-ownership/parameters.md#borrowed-arguments): when a borrowed argument is passed as its bits, and when as the caller's place.
- [01 What can be moved from](../spec/01-values-and-ownership/moving-values-out.md#what-can-be-moved-from): which places can be moved from, and what to do with the rest.
- [01 Changeable places](../spec/01-values-and-ownership/bindings.md#changeable-places): every place that can be changed or lent with `mutable`.
- [01 Places given to a position](../spec/01-values-and-ownership/references.md#places-given-to-a-position): where code writes `&`, `mutable`, `consume` or `copy`, and why the value a method is called on needs none.
- [01 Bindings](../spec/01-values-and-ownership/bindings.md#bindings): how `ref let` and `ref var` name a place, and how long a borrow lasts.
- [01 Evaluation order](../spec/01-values-and-ownership/parameters.md#evaluation-order-and-when-a-calls-borrows-begin): the order a call works out its parts, and when its borrows begin.
- [01 The law of exclusivity](../spec/01-values-and-ownership/exclusivity.md#the-law-of-exclusivity): which places overlap, two elements of one list at once, and the values checked while the program runs.
- [02 Temporaries](../spec/02-views-and-dependencies/dependency-projection-and-results.md#temporaries): how long a value that nothing names lives.
- [04 Iteration](../spec/04-types/collections.md#iteration): how a `for` loop borrows the list it runs over.
- [05 Places lent where a reference is expected](../spec/05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected): where a place with no mark is lent, and where code writes `&`.
