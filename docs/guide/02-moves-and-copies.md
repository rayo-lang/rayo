# 2 · Moves and copies

In the first chapter, an enemy lost health when it took a hit. To keep a record of those hits, put their damage in a list. A list allocates memory on the heap for its values, and may allocate more as you add them:

```swift
var hits = List<Int>()
hits.append(12)
hits.append(30)
log("\(hits.count) hits")       // 2 hits
```

`List<Int>()` makes an empty list of `Int`s. `append` adds a value at the end, and `count` says how many values the list holds ([04](../spec/04-types/collections.md#collections-and-strings)). `hits` is a `var`, since appending changes the list.

That heap memory has to be freed when the list is no longer needed, and freed only once. If it's freed too early, something else may get that memory while the list still reads it. Freeing it twice corrupts memory, and never freeing it leaks it.

Rayo frees it for you, with no garbage collector: the compiler places the code that frees it.

## Owners

A list in a function's local variable is destroyed when the function returns:

```swift
func recordFight() {
    var hits = List<Int>()
    hits.append(12)
    log("\(hits.count) hits")
}                               // 'hits' goes out of scope, and its list is destroyed
```

Every value in Rayo has an **owner**, and lives as long as its owner holds it ([01](../spec/01-values-and-ownership.md)). Here the list's owner is `hits`.

A variable goes out of scope at the end of the block that declares it. Then the value it owns is **destroyed**: everything the value holds is released. For a list, that means its heap memory is freed.

You never write a `free`. The compiler knows where each variable goes out of scope, and puts the code that destroys its value there ([01](../spec/01-values-and-ownership/moves-copies-destruction.md#destruction)).

A value is also destroyed when its owner is assigned another value, since nothing owns the old one any more:

```swift
var hits = List<Int>()
hits.append(12)
hits = List<Int>()              // the first list is destroyed here
```

## Moves

A parameter marked `owned` takes over the value passed to it ([01](../spec/01-values-and-ownership/parameters.md#parameters)):

```swift
func archive(list: owned List<Int>) { ... }

var hits = List<Int>()
hits.append(12)
archive(list: hits)
log("\(hits.count)")            // error: 'hits' was moved
```

Passing `hits` to `archive` **moves** the list. `archive`'s parameter becomes its owner, and `hits` holds nothing any more. So using `hits` after the call is an error: there's no list in it to use ([01](../spec/01-values-and-ownership/moves-copies-destruction.md#moves)).

Nothing in the call marks the move, since `archive`'s declaration already says `owned`. If you miss it, the compiler tells you as soon as you use `hits` again.

Moves are how Rayo frees the list's memory exactly once. A move hands the list from one owner to the next, so the list never has two owners at once. Here `archive`'s parameter ends up with it. Then either `archive` moves the list on, or the list is destroyed when `archive` returns. Either way, `hits` holds nothing when it goes out of scope, so it has nothing to destroy.

A move is also cheap. The list itself is only a few bytes, which say where its heap memory is and how big it is. A move hands those bytes to the new owner, and the values on the heap stay where they are.

A `var` that has been moved from can be assigned a new value, and is usable again:

```swift
hits = List<Int>()
hits.append(5)                  // fine
```

Most parameters aren't `owned`. A plain parameter, with nothing written before its type, **borrows** its argument: it reads the value without owning it ([Borrowing](03-borrowing.md)). Passing a list to one moves nothing, so the caller still owns the list afterwards. Operators such as `-` only read their values too, and so does `\(…)` inside quotes.

## Adding to a list

A list owns the values in it, so `append`'s parameter is `owned`. Adding a variable's value to a list moves the value in, whatever its type:

```swift
let best = 30
hits.append(best)
log("best is \(best)")          // error: 'best' was moved
```

The list now owns the 30, just as a list of strings would own a string added the same way.

`best` is a `let`, and it still moved. A `let` can't change, but it can hand its value over. After that, it can't be used at all. So wherever you can use a `let`, it still holds the value it started with.

In C, Java or Swift, `best` would be copied quietly, since it's an `Int`. Rayo moves it instead. That's no slower: a move copies at most the same few bytes a copy would ([01](../spec/01-values-and-ownership/moves-copies-destruction.md#moves)).

The difference is what happens to `best` afterwards. In Rayo, a value passed to an `owned` parameter moves, whatever its type. So you can tell whether a variable is still usable after a call without knowing its type. And a second value never appears unless you ask for one.

A value written in the call, as in `hits.append(12)`, is made right there, so no variable gives anything up.

## Copies

To add `best` to the list and still use it afterwards, add a copy:

```swift
let best = 30
hits.append(copy best)
log("best is \(best)")          // fine: best is 30
```

`copy` duplicates a value's own bytes. An `Int`'s bytes are the whole value, so the copy is a second, separate number ([01](../spec/01-values-and-ownership/moves-copies-destruction.md#copies)).

`copy` doesn't work on a list:

```swift
let backup = copy hits          // error: 'List<Int>' is not copyable
let twin = hits.clone()         // a second list, sharing nothing with the first
```

`copy` would duplicate only the list's own bytes, and those don't hold its values. They only say where the values are on the heap. So a copy of them would be a second list sharing the first one's heap memory. When both lists were destroyed, that memory would be freed twice.

So `copy` works only on a **copyable** type, such as a number or a `Bool`. A type can be copyable only if it owns nothing outside its own bytes ([01](../spec/01-values-and-ownership/moves-copies-destruction.md#copyable-types)). `List` owns heap memory, so it's **move-only**, and `copy` refuses it.

To get a second list, you have to build one: allocate memory for it, and fill it with values of its own. Only the type knows what it owns and how to rebuild it, so its author writes a method for that, `clone()`. `List` has one. A move-only type you define has one only if you write it.

A clone is meant to be fully independent of the original: changing or destroying one never affects the other. Rayo never calls `clone()` on its own, since it runs the type's code and usually allocates.

## Declaring, assigning and returning

Declaring a variable from another one moves the value into it, the same way passing it to an `owned` parameter moves it ([01](../spec/01-values-and-ownership/bindings.md#bindings)):

```swift
let finished = hits
log("\(hits.count)")            // error: 'hits' was moved
```

Assigning to a variable that already exists moves the value the same way. So does `return`, which moves a value out to the caller ([01](../spec/01-values-and-ownership/moving-values-out.md#moving-values-out)):

```swift
func newRound() -> List<Int> {
    var round = List<Int>()
    round.append(0)
    return round
}

let current = newRound()        // 'current' owns the new list
var older = List<Int>()
older = current                 // older's first list is destroyed, and 'current' holds nothing
```

So if you need a variable's old value after changing it, copy it first:

```swift
var hp = 100
let before = copy hp
hp -= 10
log("lost \(before - hp)")      // lost 10
```

Without `copy`, the 100 would move into `before`, leaving `hp` with nothing. Then `-=` would be an error, since it reads `hp` first.

To give a value a second name without moving or copying it, borrow it:

```swift
var hits = List<Int>()
hits.append(12)
let same = borrow hits
log("\(same.count)")            // 1
```

`same` is another name for the list in `hits`. Nothing moved and nothing was copied. `hits` still owns the list, and `same` only borrows it, the way a plain parameter borrows its argument ([01](../spec/01-values-and-ownership/bindings.md#bindings)).

A borrow comes with one restriction. `same` is a `let`, and a `let` keeps the value it started with. So the list can't change while you still use `same`:

```swift
let same = borrow hits
hits.append(5)                  // error: 'hits' is borrowed by 'same' (used below)
log("\(same.count)")
```

Once `same` isn't used any more, `hits` can change the list again. Chapter 3 shows the rest of borrowing, including how to borrow a value to change it ([Borrowing](03-borrowing.md)).

## A value that may have moved

The compiler follows every path through the code to know whether a variable still holds a value. Here the list moves on only one path:

```swift
var hits = List<Int>()
if bossFight {
    archive(list: hits)
}
log("\(hits.count)")            // error: 'hits' may have been moved
```

When `bossFight` is true, `archive` takes the list. By the time it returns, it has destroyed the list or handed it to another owner. Either way, `hits` holds nothing, and `hits.count` would read a list that isn't there. The compiler can't know whether `bossFight` will be true, since that's decided only when the program runs. So it rejects the read.

The fix is to make sure every path leaves `hits` holding a list ([01](../spec/01-values-and-ownership/moving-values-out.md#places-that-hold-no-value)):

```swift
if bossFight {
    archive(list: hits)
    hits = List<Int>()
}
log("\(hits.count)")            // fine
```

If `hits` isn't used again, there's nothing to fix. The compiler still places the code that destroys the list at the end of the block. Which path ran is known only when the program runs, so that code checks then whether there's a list left to destroy.

## In the spec

- [01 Moves](../spec/01-values-and-ownership/moves-copies-destruction.md#moves): what a move does.
- [01 Moving values out](../spec/01-values-and-ownership/moving-values-out.md#moving-values-out): every construct that moves a value, and what can be moved from.
- [01 Parameters](../spec/01-values-and-ownership/parameters.md#parameters): `owned` and the other parameter conventions.
- [01 Copies](../spec/01-values-and-ownership/moves-copies-destruction.md#copies): `copy` and `clone()`, and which types are copyable.
- [01 Bindings](../spec/01-values-and-ownership/bindings.md#bindings): what each form of `let` and `var` does with what it's given.
- [01 Destruction](../spec/01-values-and-ownership/moves-copies-destruction.md#destruction): when a value is destroyed, and in what order.
- [01 Places that hold no value](../spec/01-values-and-ownership/moving-values-out.md#places-that-hold-no-value): how the compiler tracks what each variable holds on every path.
- [04 Collections and strings](../spec/04-types/collections.md#collections-and-strings): `List` and the other collections.
