# Explicitly stepped tasks

[07 · Concurrency](../07-concurrency.md)

## `task` functions: explicitly stepped coroutines

**A `task func` can suspend at `await`, and continue when its owner steps it.** So one function can describe work that spans many steps, as `openDoor` below opens a door over half a second, waits for the player to walk away, and then closes it. Calling one returns a **task**, the value its owner steps:

```swift
task func openDoor(_ door: owned Handle<Door>) with (game: mutable Game) {
    guard let d = game.doors[door] else { return }
    game.audio.play(d.creakSound, at: d.pos)
    game.doors[door]?.state = .opening
    await seconds(0.5)
    game.doors[door]?.state = .open
    await until { [copy door] game in game.playerDistance(to: door) > 5 }   // game is lent to the condition on each poll
    await closeDoor(door)                   // awaiting a sub-task runs it inline, with its state nested
}
```

**Each step runs the task to the next `await` whose awaitable isn't done**, whenever its owner steps it. Tasks are stackless coroutines: what a task keeps from one step to the next lives in its state, whose size is known at compile time ([below](#semantics)).

### Semantics

**A task is a value.** Calling a `task func` runs nothing: it returns the task. A task is its **state**: a struct whose layout the compiler computes. Its size is known statically, so a task never allocates on its own. It lives wherever its owner puts it: a local, a field, a parent task's state when awaited as a sub-task, or a task set ([below](#running-tasks)).

**A task is move-only, and it borrows nothing.** It is move-only since a copy would be a second owner of its locals. It borrows nothing, since its parameters are unscoped and no borrow is live across an `await` (below).

**Locals that are live across an `await`, and parameters, are stored in the state.** So they must be owned: every task parameter is declared `owned` ([01](../01-values-and-ownership/parameters.md#parameters)), and its type is unscoped. A `task func` method is `consuming` or `static`, so `self` is owned too, and its type is unscoped.

**The `with (...)` clause declares the task's one resume parameter**, whose type is its `Context` ([below](#awaitables)), or `Void` when there is none. The owner passes it in fresh at every step, as `scripts.step(&game)` does ([below](#running-tasks)). It is declared `mutable`, since the owner only lends it for the step and every awaitable's `poll` takes it `mutable`. It has no default value.

**No borrow and no dynamic access may be live across an `await`**, since the task's owner may move or destroy its state between steps. That means none of these may be live there:

- a scoped value ([02](../02-views-and-dependencies/scoped-values.md#where-a-scoped-value-can-go));
- a binding or pattern part that borrows a place;
- a borrowed place the statement has already worked out when it suspends, such as an assignment's left side or an argument place before the `await`. The exception is a place in the task's parameters or owned locals, reached through stored fields and indices without reading an optional.

**The resume parameter is exempt**, since each step lends it anew.

`d` in `openDoor` borrows the door and ends before the first `await`. So using it after the `await` is a compile error, and code there reads `game.doors[door]` again.

**A place in the task's own state is worked out again on resuming**, from the index values already computed, since only the task's body reaches that state. So an assignment to a local may await on its right side, while one to a place reached through the resume parameter may not:

```swift
total += await next()                 // fine: 'total' is a local, worked out again on resuming
game.score += await pointsFor(n)      // error: 'game.score' is worked out before the 'await', through the resume parameter
let p = await pointsFor(n)            // fine: the 'await' comes first
game.score += p                       // and the write after it
```

**In a task whose `Context` is `C`, `await x` needs an `Awaitable` whose `Context` is `C`, polled with the task's resume parameter, or `Void`, polled with `()`.** The operand is checked expecting an `Awaitable` whose `Context` is `C`. So a generic parameter that appears only in the operand's `Context` is bound to `C` before the operand's arguments are checked, as in `await seconds(0.5)`. A closure argument then gets its parameter types from that binding, as `until`'s condition does in `openDoor`.

**`await` takes its operand as an `owned` argument is taken** ([01](../01-values-and-ownership/moving-values-out.md#moving-values-out)): it moves into the task's state and is polled there. So awaiting a local `Future` consumes it.

**Only the task's own body suspends.** `await` appears only in a `task func`'s own body. It can't appear in:

- any other function;
- a closure literal, a nested function, or a local type's or extension's members inside a task, since those are called, not stepped;
- a `defer` block, which also runs when the task is destroyed.

**Destroying a suspended task cleans it up.** Cancelling it, or dropping it or the task set that holds it, destroys its state as leaving every open scope would. The `deinit`s of its live locals and its live `defer` blocks run, in the usual order ([10](../10-errors-and-safety/typed-errors.md#cleanup)), and no other code does. That happens outside any step, with no resume parameter. So a `defer` that is live across an `await` may use only what exists without a step: the state's parameters and owned locals, and the globals any code reaches, not the resume parameter.

**A finished task stays finished.** Once its `poll` has returned `.done` or `.failed`, its result has moved out and its locals are destroyed, so destroying it runs nothing, and polling it again panics ([10](../10-errors-and-safety/panics.md#what-panics)).

**A task never holds itself.** Its state never contains a state of its own type, as it would if its body awaited a call of itself directly or through other `task func`s ([04](../04-types/structs.md#structs)). Recursion goes through an owner, such as a `Box`, so the allocation is visible.

**Results and errors.** A task returns and throws as a function does:

```swift
task func loadLevel(_ id: owned LevelId) with (ctx: mutable Loader) throws(LoadError) -> Level { … }   // a result type and an error type
let level = try await loadLevel(id)          // in another task: yields the result, or propagates the error
```

### Awaitables

**Whatever a task waits on is an awaitable**: a value the task polls at each step until it reports that it is done.

```swift
protocol Awaitable {
    associatedtype Context
    associatedtype Output = Void
    associatedtype Failure: Error = Never
    mutating func poll(_ ctx: mutable Context, _ waker: Waker) -> Poll<Output, Failure>
}

enum Poll<Output, Failure: Error> {
    case done(Output)
    case failed(Failure)
    case pending          // poll me again at the next step
    case waiting          // a stepper may skip me until someone calls the waker I stored
}

struct Waker(                     // made by whatever steps the task
    let target: WeakShared<any WakeTarget>,
    let id: UInt64,
): Copyable {                     // Sendable, derived: it holds only a weak link and an id
    func wake() { … }             // any thread, including C callbacks; nothing once the target is gone
}

protocol WakeTarget: Synchronized {   // reached only by shared access, so it changes only through its own synchronization
    func wake(id: UInt64)             // called from any thread, C callbacks and real-time threads included
}
```

**`await x` evaluates to `x`'s `Output` once it is done.** For the dependency rules ([02](../02-views-and-dependencies/dependency-rules.md#dependencies)), it is the `x.poll(&ctx, waker)` call that returned `.done`, with `x` a temporary of its statement. So the value, and an error that `try await` throws, depend, exclusively, on each of these:

- the resume parameter;
- `x`'s storage, unless `x` is a `task func`'s call. That task's result can view nothing its state owns, as no function's result views what its `owned` parameters or locals own ([02](../02-views-and-dependencies/dependency-rules/absorption-and-accesses.md#rule-5-the-callee-side)).

**An awaitable whose `Failure` isn't `Never` is awaited with `try await`**, and `.failed(e)` throws `e` there ([10](../10-errors-and-safety.md)). A `task func` is an awaitable of its return and error types.

**Only its owner's `step` resumes a task, but a step needn't visit every task.**

- A **pending** task is polled every step.
- A **waiting** task isn't. Its awaitable has handed the `Waker` to whatever will complete it, such as a `Future`, an I/O completion or a timer wheel. The next `step` after a wake resumes it.

**`wake()` upgrades its weak link and calls the target's `wake(id:)` through the new owner** ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)). So reaching the target takes no lock and never waits, though `wake(id:)` itself may. Waking a destroyed target does nothing. When every other owner of the target drops while `wake()` holds the one it upgraded, `wake()` drops the last owner, and destroys the target on the waking thread.

**`poll` returns a correct result whenever it is called**, since a poll may still come at any step, woken or not. A wake is only a hint: it may reach a target for an id it no longer runs, since a `Waker` may outlive its task.

**std's awaitables include these:**

- **`until`**, which takes a condition (below);
- **`Future<T>`**, whose `Output` is `T`;
- **timed waits**, which `seconds` makes (below).

**A timed wait's `Context` `C` gives the program's own time, through the `now` property that `TimeSource` requires:**

```swift
func seconds<C: TimeSource>(_ s: Double) -> Seconds<C> { … }            // a timed wait; TimeSource requires 'var now: Double { get }'
extension Game: TimeSource { var now: Double { copy simulationTime } }   // so openDoor's seconds(0.5) counts simulation time
```

**A suspended task's awaitable is stored in its state, so it can't hold a borrow either.** So `until`'s condition receives the resume parameter as its argument on every poll. `until` takes the condition by concrete type and moves it in ([05](../05-protocols-generics-and-closures/functions-and-closures.md#closures-by-concrete-type-some-f)):

```swift
func until<C, F>(_ cond: owned F) -> Until<C, F> where F: (mutable C) -> Bool, F: ~Scoped { … }   // the condition by its own type, moved in
```

It stores the condition by value in the task's state, never boxed, with its captures counting against the state's size. Being unscoped, the condition owns and lists its captures, as `[copy door]` does. A condition that captures the resume parameter, or any other borrow, is rejected:

```swift
await until { game.isOver }             // error: the condition captures the resume parameter
await until { game in game.isOver }     // fine: the condition takes it as its argument
```

### Running tasks

```swift
var scripts = TaskSet<Game>(capacity: 512)           // resume context type: mutable Game
let t = scripts.start(openDoor(frontDoor))           // returns Handle<TaskSlot>
scripts.cancel(t)                                    // runs live locals' deinits and live defers, or, unstepped, destroys its parameters

scripts.step(&game)                                  // wherever the program steps: resumes pending and woken tasks once each
```

**std's `TaskSet` takes ownership of each task it starts:**

```swift
mutating func start<A: Awaitable>(_ work: owned A) -> Handle<TaskSlot>        // TaskSet<C>'s: the task, moved in
    where A.Context == C, A.Output == Void, A.Failure == Never, A: ~Scoped { … }   // C: the set's resume context type
```

**A `TaskSet` isn't `Sendable`, since its type doesn't show its tasks' types.** So it and its tasks stay on one thread, and the tasks needn't be `Sendable`. A task is `Sendable` when everything in its state is.
