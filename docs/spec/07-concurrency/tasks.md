# Tasks

[07 · Concurrency](../07-concurrency.md)

## `task` functions: coroutines that wait without a thread

**A `task func` can suspend at `await` while it waits, and continue once what it waits on wakes it.** So one function can describe work that waits, without a thread of its own to park. Most programs have such work:

- a protocol handshake, which sends a greeting, waits for the reply, and gives up when none comes in time;
- a request handler, which waits for a file read or a database query to complete;
- an incremental parser, which takes its input as it arrives, and suspends when it runs out;
- a game script, which opens a door over half a second, and then waits for the player to walk away.

Calling a `task func` returns a **task**, the value its owner runs. The handshake is one:

```swift
task func handshake(_ sock: owned Handle<Socket>) with (net: mutable Reactor) -> Session!NetError {
    try await send(sock, Hello(version: 3))                    // pending until the socket can take the bytes
    let reply = try await receive(sock, timeout: replyLimit)   // fails with .timedOut once the limit passes with no reply
    guard reply.version == 3 else { throw .badVersion }
    return Session(sock, key: reply.key)
}
```

`Reactor` is an I/O library's type, which owns the program's sockets, and which the task's owner lends it at each step as its resume parameter ([below](#semantics)). `send` and `receive` make awaitables that hand the task's `Waker` to the reactor, which calls it once the socket is ready or the limit passes ([Waking a task](#waking-a-task)). Until then nothing polls the task, so one thread can keep thousands of handshakes waiting.

**A game script is a task too.** `openDoor` opens a door over half a second, waits for the player to walk away, and then closes it:

```swift
task func openDoor(_ door: owned Handle<Door>) with (game: mutable Game) {
    guard let d = game.doors[door] else { return }
    game.audio.play(d.creakSound, at: d.pos)
    game.doors[door]?.state = .opening
    await elapsed(.seconds(0.5))           // half a second of the game's own time
    game.doors[door]?.state = .open
    await until { [copy door] game in game.playerDistance(to: door) > 5 }   // game is lent to the condition on each poll
    await closeDoor(door)                   // awaiting a sub-task runs it inline, with its state nested
}
```

**A task runs in steps.** A **step** is one poll of the task, which runs it from where it suspended to the next `await` whose awaitable isn't done. Its owner gives it a step each time it is woken ([Running tasks](#running-tasks)). Tasks are stackless coroutines: what a task keeps from one step to the next lives in its state, whose size is known at compile time ([below](#semantics)).

### Semantics

**A task is a value.** Calling a `task func` runs nothing: it returns the task. A task is its **state**: a struct whose layout the compiler computes. Its size is known statically, so a task never allocates on its own. It lives wherever its owner puts it: a local, a field, a parent task's state when awaited as a sub-task, a task set ([below](#running-tasks)), or the frame of a `block(on:)` call ([below](#waiting-for-wakes-run-and-blockon)).

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
total += await next()                 // fine: 'total' is a local, worked out again on resuming; 'next' can't fail, so no 'try'
game.score += await pointsFor(n)      // error: 'game.score' is worked out before the 'await', through the resume parameter
let p = await pointsFor(n)            // fine: the 'await' comes first
game.score += p                       // and the write after it
```

**In a task whose `Context` is `C`, `await x` needs an `Awaitable` whose `Context` is `C`, polled with the task's resume parameter, or `Void`, polled with `()`.** The operand is checked expecting an `Awaitable` whose `Context` is `C`. So a generic parameter that appears only in the operand's `Context` is bound to `C` before the operand's arguments are checked, as in `await elapsed(.seconds(0.5))`. A closure argument then gets its parameter types from that binding, as `until`'s condition does in `openDoor`.

**`await` takes its operand as an `owned` argument is taken** ([01](../01-values-and-ownership/moving-values-out.md#moving-values-out)): it moves into the task's state and is polled there. So awaiting a local `Future` consumes it.

**Only the task's own body suspends.** `await` appears only in a `task func`'s own body. It can't appear in:

- any other function;
- a closure literal, a nested function, or a local type's or extension's members inside a task, since those are called, not stepped;
- a `defer` block, which also runs when the task is destroyed.

**Destroying a suspended task cleans it up.** Cancelling it, or dropping it or the task set that holds it, destroys its state as leaving every open scope would. The `deinit`s of its live locals and its live `defer` blocks run, in the usual order ([10](../10-errors-and-safety/typed-errors.md#cleanup)), and no other code does. That happens outside any step, with no resume parameter. So a `defer` that is live across an `await` may use only what exists without a step: the state's parameters and owned locals, and the globals any code reaches, not the resume parameter.

**A finished task stays finished.** Once its `poll` has returned `.done` or `.failed`, or a panic has unwound out of it, its result has moved out or never came, and its locals are destroyed. So destroying it runs nothing, and polling it again panics ([10](../10-errors-and-safety/panics.md#what-panics)).

**A panic that unwinds out of a step finishes the task.** The unwind leaves the task's body as a `throw` would: it destroys the task's live locals and runs its live `defer` blocks ([10](../10-errors-and-safety/panics.md#unwinding)). Then it goes on out of the `poll` that ran the step, so the task never yields a result.

**Awaiting a task that panics yields nothing: the panic unwinds through the `await`.** A sub-task runs inline in the step of the task that awaits it, so its panic goes on through the awaiting task, and finishes both, as a panic in a callee unwinds its caller.

**A task never holds itself.** Its state never contains a state of its own type, as it would if its body awaited a call of itself directly or through other `task func`s ([04](../04-types/structs.md#structs)). Recursion goes through an owner, such as a `Box`, so the allocation is visible.

**Results and errors.** A task returns and fails as a function does:

```swift
task func loadLevel(_ id: owned LevelId) with (ctx: mutable Loader) -> Level!LoadError { … }   // a success type and a failure type
let level = try await loadLevel(id)          // in another task: yields the result, or propagates the error
```

### Awaitables

**Whatever a task waits on is an awaitable**: a value the task polls at its steps until it reports that it is done.

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
    case pending          // not done yet: a call of the waker is arranged (below)
}

struct Waker(                     // made by the task's runner
    let target: WeakShared<any WakeTarget>,
    let id: UInt64,
): Copyable {                     // Sendable, derived: it holds only a weak link and an id
    func wake() { … }                           // any thread, including C callbacks; nothing once the target is gone
    func wake(at deadline: Instant<MonotonicClock>) { … }   // the same, once MonotonicClock reaches 'deadline'
}

protocol WakeTarget: Synchronized {   // reached only by shared access, so it changes only through its own synchronization
    func wake(id: UInt64)                       // called from any thread, C callbacks included
    func wake(id: UInt64, at deadline: Instant<MonotonicClock>)
}
```

**`await x` evaluates to `x`'s `Output!Failure` once it finishes**, or to its `Output` where `Failure` is `Never` (below), `.success` for `.done` and `.failure` for `.failed`. For the dependency rules ([02](../02-views-and-dependencies.md#dependencies)), it is the `x.poll(&ctx, waker)` call that returned, with `x` a temporary of its statement. So the value, an error included, depends, exclusively, on each of these:

- the resume parameter;
- `x`'s storage, unless `x` is a `task func`'s call. That task's result can view nothing its state owns, as no function's result views what its `owned` parameters or locals own ([02](../02-views-and-dependencies/dependency-absorption-and-accesses.md#rule-5-the-callee-side)).

**`try await x` propagates the error of `.failed(e)` as `try` does, and `await x` alone keeps it as a value** ([10](../10-errors-and-safety/typed-errors.md#keeping-an-error-as-a-value)). Where `Failure` is `Never`, as it is worked out at the `await`, `await x` has type `Output`, so `total += await next()` needs no `try` ([10](../10-errors-and-safety/typed-errors.md#what-a-failure-type-names)). In code generic over `Failure`, it is still an `Output!Failure`. A `task func` is an awaitable of its success and failure types.

### Waking a task

**`.pending` means the awaitable has arranged for its `Waker` to be called.** Before a poll returns `.pending`, it hands the `Waker` it was given to whatever will let the awaitable make progress. That may be a `Future`'s `Promise` or an I/O completion. An awaitable that waits for a time calls `wake(at:)`, and one that can only find out by looking again, as `until` does, calls `wake()` itself before it returns ([below](#awaitables-in-std)).

**So a task that waits costs nothing until the wake** ([Running tasks](#running-tasks)), apart from the few early polls a deadline allows (below), however many tasks wait with it, and a runner with no woken task can park its thread ([below](#waiting-for-wakes-run-and-blockon)).

**`wake(at:)` asks the task's runner to wake it once `MonotonicClock` reaches `deadline`** ([Time](synchronization.md#time-duration-and-instant)), or at once when the deadline has passed. A runner keeps, for each task, the earliest deadline given to it since its last step began, and clears it as the next step begins, before the poll:

- **The earliest wins.** An awaitable that waits on two times at once, such as a library's choice between two timed waits, wakes the task at the earlier deadline.
- **A stale `Waker` costs a poll at most.** A deadline that an earlier awaitable arranged may wake the task early, which only polls it with nothing changed (below).
- **A pending poll keeps its deadline.** The step clears the old deadline before the poll, so the one that the poll arranges again survives.
- **A deadline may also cost an early poll, but never a spin.** A runner may step a pending task that has a deadline, with nothing changed, once a span that the implementation states has passed since the task's last step began. It may also do so when a `wake(at:)` reaches the runner as the task's step begins. The first comes at most once per that span, and the second at most once per step.

**A task is pending only when the awaitable it is suspended on is.** `await x` polls `x` with the `Waker` that the task's own poll was given. So the wake that `x` arranged wakes the task, and a sub-task passes the same `Waker` on to what it awaits.

**An awaitable arranges each wake with the `Waker` of its latest poll.** A task's runner may hand it a different `Waker` at each poll, so a wake arranged with an older one may reach nothing.

**An awaitable that returns `.pending` with no wake arranged leaves its task suspended until something else wakes it, which may be never.** The compiler can't check this, and no memory is at risk. The task waits as a thread parked on an `Event` that nothing signals does, and destroying it still cleans it up ([Semantics](#semantics)).

**`wake()` upgrades its weak link and calls the target's `wake(id:)` through the new owner** ([06](../06-memory-and-allocators/owning-values.md#sharedt-data-with-many-owners)). So reaching the target takes no lock, though `wake(id:)` itself may. Waking a destroyed target does nothing. When every other owner of the target drops while `wake()` holds the one it upgraded, `wake()` drops the last owner, and destroys and frees the target on the waking thread. `wake(at:)` reaches its target the same way.

**`poll` returns a correct result whenever it is called, since a wake is only a hint.** A wake that an earlier awaitable of the task arranged may still arrive after the task has gone past it. A `Waker` may also outlive its task, so a target may get a wake for an id it no longer runs. So a task may be polled with nothing changed, and then it arranges its wake again and returns `.pending`.

### Awaitables in std

**std's awaitables include these:**

- **`until`**, which is done once its condition holds (below);
- **`nextStep()`**, which waits for the task's next step (below);
- **`sleep(for:)`**, which waits on `MonotonicClock` (below);
- **`elapsed(_:)`**, which waits on a clock that the program supplies (below);
- **`Future<T>`**, whose `Output` is `T?`, `nil` once its `Promise` is gone unfulfilled ([Futures](synchronization.md#futures)).

**`until`, `nextStep()` and `elapsed(_:)` wake their task themselves at each poll that returns `.pending`**, since nothing outside the task tells them when to look again. So their runner polls them at every pass:

- **Under `step`**, once each time the program steps, which suits a frame loop that checks a condition once a frame ([Running tasks](#running-tasks)).
- **Under `run` or `block(on:)`**, again and again, since a woken task keeps the runner from parking ([below](#waiting-for-wakes-run-and-blockon)). The thread then busy-waits until the awaitable is done. Code under such a runner awaits what wakes it instead, such as a `Future` or `sleep(for:)`.

**`nextStep()` returns `.pending` once, and `.done` at its next poll:**

```swift
func nextStep() -> NextStep { … }     // NextStep: an Awaitable whose Context is Void
```

So under `step`, a task that awaits it goes on at the next step, as a script that acts once a frame does. Under `run`, it goes on once the tasks woken before it have had their step, so a long computation can let them run between its parts.

**A timed wait counts from its first poll, and is done at the first poll that finds its time has passed:**

```swift
func sleep(for d: Duration) -> Sleep { … }                         // Sleep: an Awaitable whose Context is Void
func elapsed<C: TimeSource>(_ d: Duration) -> Elapsed<C> { … }     // Elapsed<C>: an Awaitable whose Context is C
extension Game: TimeSource { var now: Instant<Game> { copy simulationTime } }   // so openDoor's wait counts simulation time
```

**`sleep(for:)` waits on `MonotonicClock`, and never busy-waits** ([Time](synchronization.md#time-duration-and-instant)). Its first poll sets its deadline, `d` after `now`, and each poll that isn't due arranges its wake with `wake(at:)`. So under `run` or `block(on:)` the thread parks until the deadline, and under `step` the first step after the deadline resumes the task. Its `Context` is `Void`, so any task may await it.

**`elapsed(_:)` waits on the task's resume parameter, which is a `TimeSource`**, such as a game's simulation time. Each poll compares the parameter's `now` with the time the wait is due, and a poll that isn't due wakes the task itself.

**It wakes itself since nothing tells it when the program's own time advances.** Such a clock usually advances once per pass of the loop that steps the tasks, so a poll at each step comes as often as its time can change. A `TimeSource` that let waits register wakes would have to keep `Waker`s and call them as it advances, a cost on every clock that only a runner that parks would use. So under `run`, a task awaits `sleep(for:)` instead.

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
var scripts = TaskSet<Game>(capacity: 512)                       // resume context type: mutable Game
guard let door = try? scripts.start(openDoor(frontDoor)) else { return }   // nil when all 512 slots are taken
scripts.cancel(door)                                             // runs live locals' deinits and live defers, or, unstepped, destroys its parameters

scripts.step(&game)                                              // wherever the program steps: one step for each task woken, or allowed an early poll, since the last
```

**A task's runner polls it and makes its `Waker`s.** A **runner** may be std's `TaskSet`, std's `block(on:)` ([below](#waiting-for-wakes-run-and-blockon)), or a library's own, whose `Waker`s reach a `WakeTarget` of its own. The runners in std give a pending task its next step only after the task is woken: by a `wake()`, by its deadline passing, or early in the bounded cases that a deadline allows ([Waking a task](#waking-a-task)).

**std's `TaskSet` takes ownership of each task it starts:**

```swift
init(capacity: Int)                                        // TaskSet<C>'s; C: the set's resume context type
init(capacity: Int, notifying loop: Waker)                 // also calls 'loop.wake()' after each wake it records (below)
mutating func start<A: Awaitable>(_ work: owned A) -> Handle<TaskSlot>!TaskSetFull<A>   // the task, moved in
    where A.Context == C, A.Output == Void, A.Failure == Never, A: ~Scoped { … }
mutating func step(_ ctx: mutable C) { … }
var hasWoken: Bool { get }                                 // whether a step now would find a task woken
var deadline: Instant<MonotonicClock>? { get }             // the earliest deadline among its tasks
var runWaker: Waker { get }                                // a Waker of the set itself, for 'run' (below)

struct TaskSetFull<A>(let work: A): Error                  // start's failure: the task, handed back unstarted
```

**`start` fails once every slot is taken, and hands the task back**, as a failed `send` hands back its item ([Disconnected channels](synchronization.md#disconnected-channels)). So a full set never drops a task that its caller still wants.

**A set's wake target comes from `.system`, made when the set is.** The wake target is the `Synchronized` value that the set's `Waker`s reach, and holds each slot's wake and deadline. A thread that wakes a task may hold an owner of it for a moment ([Waking a task](#waking-a-task)), so it never comes from the current allocator, which may be an arena that the program resets.

**A task is woken from the time `start` returns until its runner gives it a step.** Each `wake()` of one of its `Waker`s wakes it again, however many times it comes, so a task that is woken twice before a step gets one step. Each wake happens before the step it leads to, so what the waking thread did before its `wake()` is visible to the task.

**`step` takes the set's woken tasks as it begins, and gives each of them one step:**

- **Deadlines.** It counts as woken each task whose deadline has passed on `MonotonicClock` as it begins. It may also count as woken a task whose early poll a deadline allows ([Waking a task](#waking-a-task)). It clears a task's deadline as that task's step begins ([Waking a task](#waking-a-task)).
- **Order.** It steps them in the order of their slots, and `start` fills the lowest free slot. A step that follows a panic starts after the task that panicked instead (below).
- **Tasks that aren't woken.** It skips them, so they stay suspended, holding their state, until a wake.
- **Wakes during the step.** A wake that comes while the step runs, from the task itself, another task or another thread, counts for the next step. So each task gets one step at most, and `nextStep()` waits for the next `step` ([above](#awaitables-in-std)).

**A task's panic finishes that task, and `step` stops there, letting the panic unwind out of it at once.** The panic finishes only the task that panicked ([above](#semantics)), and the set frees that task's slot as the panic leaves `step`, so the task's handle goes stale. The tasks the step hasn't reached stay woken for the next `step`, which starts with the task after the one that panicked and wraps around. So a task that panics often can't keep the tasks after it from being stepped.

**Stopping at once keeps the other tasks off a half-changed resume parameter.** The panic may have left the resume parameter half-changed, and the owner's `recover` closure sees it first, so it can repair it before any other task runs ([10](../10-errors-and-safety/panics.md#catching-a-panic-catchpanic)). An owner that keeps the program running catches the panic around `step`:

```swift
catchPanic {
    scripts.step(&game)
} recover: { p in
    log("a script failed: \(p.message)")             // that script is gone; the rest wait for the next step
}
```

**A `TaskSet` isn't `Sendable`, since its type doesn't show its tasks' types.** So it and its tasks stay on one thread, and the tasks needn't be `Sendable`. A task is `Sendable` when everything in its state is. Its `Waker`s are `Sendable`, so a wake may come from any thread.

**A wake of a `TaskSet` records the wake and never runs a task's code.** `wake(id:)` marks the task woken, and `wake(id:at:)` sets its deadline. Each makes at most one runtime wake call of its own, for a parked `run` ([below](#waiting-for-wakes-run-and-blockon)), and then calls the notifying `Waker`, if the set has one. The runtime's wake may block briefly where the platform's wake does. The `Waker` that reached the target may also destroy and free it on the waking thread, when it held the last owner ([Waking a task](#waking-a-task)). So real-time code, such as an audio callback, doesn't wake a task itself: it hands the wake to another thread.

### Waiting for wakes: `run` and `block(on:)`

**A thread whose tasks spend most of their time waiting parks until one is woken.** A server's thread waits for its sockets, as this one does:

```swift
var conns = TaskSet<Server>(capacity: 1024)            // the connections' tasks, run with the server's state
_ = conns.start(acceptLoop(listener))                  // puts each new socket in 'server.accepted', and never finishes
while !stopping.load(.acquire) {                      // stopping: a global Atomic<Bool>, which another thread may set
    conns.run(&server, until: { s in !s.accepted.isEmpty || stopping.load(.acquire) })   // parks the thread between wakes
    while let sock = server.accepted.popLast() { _ = conns.start(serve(sock)) }
}
```

A task can't start a task in the set that runs it, since `run` holds the set exclusively. So `run` returns once its condition holds, and the loop starts the new connections' tasks.

**std's two runners that park are `TaskSet`'s `run` and the free function `block(on:)`:**

```swift
mutating func run(_ ctx: mutable C, until done: (mutable C) -> Bool) { … }   // TaskSet<C>'s: steps and parks, until 'done' holds or no task is left
func block<A: Awaitable>(on work: owned A, with ctx: mutable A.Context) -> A.Output!A.Failure { … }   // runs one awaitable to its end
func block<A: Awaitable>(on work: owned A) -> A.Output!A.Failure where A.Context == Void { … }
```

**`done` has the function type of `until`'s condition**, so the same check can serve as either. `until` keeps its condition in the task's state, so it takes one that owns its captures, by its concrete type ([above](#awaitables-in-std)). `run` only calls `done` while it runs, so `done` may borrow what it captures.

**`run` parks on a word in the set's wake target, through `Runtime.park`** ([Parking and waking a thread](synchronization.md#parking-and-waking-a-thread)). An `Event` would not do, since it is set once, and a runner parks again and again. The target also holds a run flag, which `runWaker` sets (below). Each wake records itself, as a woken task, a deadline or the run flag, and only then changes the word and wakes `run` if it is parked ([Running tasks](#running-tasks)).

**`run` repeats these steps, in this order, until it returns:**

1. It steps the set, as `step` does ([Running tasks](#running-tasks)).
2. It returns if the set holds no task, since no wake could come for one.
3. It reads the word.
4. It clears the run flag.
5. It returns if `done(ctx)` is true.
6. It goes back to 1 if a task is woken, a task's deadline has passed, or the run flag is set again.
7. It parks, if the word still holds what 3 read, until a wake or the earliest of the set's deadlines. Then it goes back to 1.

**No wake is lost in that order.** A wake that comes before 3 is seen at 6, or, for a `runWaker` wake, by `done` at 5, since 4 clears the flag first. A wake that comes after 3 is seen at 6, or changes the word, so the park at 7 returns at once. A park may also return with no wake, which leads to a step that polls nothing.

**`done` is checked only after a step**, so a condition that changes with no wake is seen after the next wake. **The park's timeout ends at the earliest deadline**, so the thread sleeps until a task's `sleep(for:)` is due, and that task resumes once its deadline has passed ([Time](synchronization.md#time-duration-and-instant)).

**`runWaker` lets another thread stop `run`, or hand it work.** It is a `Waker` of the set itself, which wakes no task. Its `wake()` sets the run flag and wakes a parked `run`, which steps the set and checks `done` again. So the other thread first changes what `done` reads, through a `Synchronized` value such as an `Atomic`, and then wakes the set. Clearing the flag at 4 synchronizes with the wake that set it, so `done` sees the change:

```swift
let stop = conns.runWaker                // a copy, sent to the thread that stops the server
stopping.store(true, .release)           // on that thread: the Atomic<Bool> that 'done' loads
stop.wake()                              // run steps, finds 'done' true, and returns
```

**A `runWaker` wake doesn't make `hasWoken` true, since it wakes no task, but it does call the set's notifying `Waker`** (below). So an event loop that steps the set wakes too, and checks its own condition to stop.

**A task's panic leaves `run` as it leaves `step`, at once.** The task is finished and its slot freed, and the tasks the step hadn't reached stay woken, for a `step` or `run` that starts after the task that panicked ([Running tasks](#running-tasks)). So the owner's `recover` sees the resume parameter before any other task runs, and the owner then calls `run` again to go on. A panic in `done` unwinds out of `run` too, and finishes no task.

**`block(on:)` runs one awaitable on the calling thread until it is done, and returns its result.** Synchronous code uses it to wait for a task, as here for a load whose reads complete on an I/O thread:

```swift
let level = try block(on: loadLevel(id), with: &loader)   // parks while the load waits for its reads
```

- **What it takes.** It keeps the work in its own frame for the call, so it takes an awaitable of any result, scoped or not, where a `TaskSet` takes only unscoped tasks that return nothing.
- **How it parks.** It polls the work, and parks as `run` does whenever the work is pending and no wake has come since the poll began, until a wake or the work's deadline.
- **Its wake target.** Each thread has one for `block(on:)`, which its first call makes from `.system`, and which the thread's teardown destroys, as it destroys the thread's copy of a thread-local ([Thread teardown](global-state.md#thread-teardown)). So `block(on:)` allocates nothing after a thread's first call, and never from the current allocator.
- **Nested calls.** A `block(on:)` inside another on the same thread shares the thread's wake target. It leaves the target woken as it returns, so the outer call polls its work again, and loses no wake that the inner call took.
- **Panics.** A panic in the work's poll finishes it, if it is a task ([Semantics](#semantics)), and unwinds out of `block(on:)` at once, which destroys the work with the call's frame.

**Called from a task's step, `block(on:)` parks the thread of that task's runner**, so the runner's other tasks wait too. When only those tasks could wake the work, `block(on:)` waits for ever.

**During startup, a `run` or `block(on:)` that would park with no deadline panics**, as any wait that would park until another thread acts does ([Initialization at startup](global-state.md#initialization-at-startup)). A saturated deadline, which never passes, counts as none ([Time](synchronization.md#time-duration-and-instant)).

**A program that waits in an event loop of its own**, such as one in `epoll_wait`, steps the set from that loop. It makes the set with a notifying `Waker`, whose target ends the loop's wait, such as by writing an eventfd. The set calls that `Waker` after recording each wake or deadline, on the waking thread, so a wake from another thread ends the wait too. The set uses only its `wake()`. Each pass waits no longer than the set's `deadline`, and not at all while `hasWoken` is true:

```swift
var conns = TaskSet<Reactor>(capacity: 1024, notifying: loopWaker)   // loopWaker's target writes the loop's eventfd
while reactor.running {
    reactor.wait(polling: conns.hasWoken, until: conns.deadline)      // epoll_wait, at most until the deadline
    conns.step(&reactor)
}
```

**The set calls its notifying `Waker` for every wake it records, a task's wake of itself included.** So a task that awaits `elapsed(_:)`, `until` or `nextStep()` makes `hasWoken` true after each of its steps, and keeps the loop from sleeping, as it keeps `run` from parking ([Awaitables in std](#awaitables-in-std)).

**A notifying `Waker` must not lead back into the same set.** A target that wakes one of the set's tasks would make the set record that wake and call the target again, and the calls would recurse without end.
