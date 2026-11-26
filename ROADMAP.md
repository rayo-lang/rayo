# Roadmap

Rayo's [spec](docs/spec/README.md) defines the whole language, and `rayoc` builds it a small version at a time. Each version adds features of the spec end to end: a program that uses them parses, checks, compiles, links and runs. This file gives the feature set of each version, three versions ahead and no further.

## What a version is

**Each version lists its feature set, once.** The list says what the release holds, so it stays the same as those features come to run. The work toward the version, what of it is left, and its bugs and refactors are in the [issue tracker](https://github.com/rayo-lang/rayo/issues).

**From v0.3 on, a version builds one or two features, each a feature of the spec**, such as fixed-width integers or the prelude. Its list names each part of them that it builds, their compile errors included.

**A version is done when every feature it lists runs end to end, and its proof program shows it.** The proof program is one Rayo program, `examples/v0.N/<name>.rayo`, with its expected output beside it in `<name>.out`. A driver test runs it, in debug and in release builds, on every platform CI tests: macOS arm64, Linux x64, Windows x64 and Windows arm64. The driver tests check each feature in detail, so the proof program only puts the features to work together. The other programs in `examples/` use the whole language, more than `rayoc` compiles, and no test runs them.

**A version that builds part of a spec feature leaves the rest mapped in [Not yet planned](#not-yet-planned)**, so every feature of the spec is in a version or in that list.

**A finished version is tagged**, as `v0.1.0`, with short release notes, and the tag marks it done. A version ships no binaries, and is built from source as [TOOLCHAIN.md](TOOLCHAIN.md) says.

## v0.1: functions, integers and structs

The first version proves the language end to end with the smallest set of features a meaningful program needs. Its proof program is a combat simulation: enemies are structs that take hits in a loop until one of them falls, and the program prints their health as it goes.

v0.1 adds:

- functions with labeled parameters, results and recursion, where a `&T` parameter borrows the place a call lends it with `&a`, as `show(&boss)`, and an `Int` or `Bool` parameter `x: T` owns a copy of its argument ([01](docs/spec/01-values-and-ownership/parameters.md#parameters));
- the compile errors for a place given to a `&T` parameter without `&`, which names `&`, and for `&a` given to a parameter that isn't a reference, which names the parameter's type ([01](docs/spec/01-values-and-ownership/references.md#places-given-to-a-position));
- `Int` and `Bool`, with integer literals, the arithmetic operators `+`, `-`, `*`, `/` and `%`, unary `-`, the comparisons, and `&&`, `||` and `!`;
- overflow, which panics in a debug build and wraps in a release build, and division by zero, which panics in both;
- `let` and `var` locals, assignment and compound assignment;
- `if`, `else`, `while`, `break` and `continue`;
- moves and `copy`, with the checks that a local is assigned before it is used;
- struct declarations, whose names are the types of locals and results, and of the place a `&T` parameter refers to, and `copy` of a struct;
- making a struct with its primary initializer, as `Enemy(hp: 100, armor: 5)`, which takes its arguments owned, and reading a field of a struct where a borrow of the field suffices, as `e.hp - 5` or `print(e.hp)`;
- a field of a struct type, given by a nested initializer call or by a local, which the call moves, and read through the struct that holds it, as `e.stats.hp`;
- `copy` of a field of a local or a `&T` parameter, as `copy e.stats` or `copy e.stats.hp`, which leaves the struct whole;
- assigning and compound-assigning a field of a `var` local, as `e.hp -= 5`, and moving a field out, which leaves the struct unusable until the field is assigned again ([01](docs/spec/01-values-and-ownership/moving-values-out.md#what-can-be-moved-from));
- `print(Int)` and `print(Bool)`, each given a place or a value with no `&`, the second printing `true` or `false` ([04](docs/spec/04-types/collections.md#printing)).

## v0.2: `UInt` and inline arrays

An inline array, `[N of T]`, holds `N` values in place, with no heap, and takes a `UInt` as its index ([04](docs/spec/04-types/collections.md#tuples-ranges-and-arrays)).

v0.2 adds:

- the `UInt` type, with literals typed by context, arithmetic and comparisons under the overflow rule, the conversions `UInt(i)` and `Int(u)`, and `print(UInt)` ([04](docs/spec/04-types/numbers-and-math.md#numbers));
- a place given to a `&T` parameter with no `&`, lent as `show(boss)` lends `boss`, in place of v0.1's compile error for it ([05](docs/spec/05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected));
- `[N of T]` as the type of locals, results, struct fields and array elements, and of the place a `&T` parameter borrows, nested arrays included, made by a literal or by `.init(repeating:)`;
- reading, copying, assigning and compound-assigning an element as `a[i]`, through fields and nested arrays, with a `UInt` index ([04](docs/spec/04-types/collections.md#inline-array-elements));
- `a.count`, a `UInt`;
- the `index out of range` panic in every build, and a compile error for an integer literal index out of range;
- a `ref let` that borrows a local or a parameter, or a field or an element of either, read-only, as `ref let x = &a[i]` ([01](docs/spec/01-values-and-ownership/bindings.md#bindings-that-refer-to-a-place));
- the compile errors for a `ref let` given a bare place, which names `&`, and for one given a value, which names `let` and `var`;
- the compile error for a `let` or `var` given such a place, which names `copy`, `consume` and `&`, and the one for an assignment given one, which names `copy` and `consume` ([01](docs/spec/01-values-and-ownership/bindings.md#bindings-that-own-a-value));
- `consume` of the same places, as `let x = consume e`, which moves a local or a field of one, and is an error where a `&T` parameter or an element can't be moved from ([01](docs/spec/01-values-and-ownership/moving-values-out.md#moving-values-out));
- implicit copies of `Int`, `UInt` and `Bool`, which leave the place usable, in a `let`, a `var`, an assignment, a `return`, an initializer's argument and an array literal's element, while a struct or an array keeps the errors ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#implicit-copies)).

## v0.3: changing values in place

A function changes its caller's value through a `mutable &T` parameter, and takes a struct or an array over through a parameter that owns it.

v0.3 adds:

- `mutable &T` parameters, which a call lends a place with `mutable a`, under the [law of exclusivity](docs/spec/01-values-and-ownership/exclusivity.md#the-law-of-exclusivity) ([01](docs/spec/01-values-and-ownership/parameters.md#parameters));
- the compile error for a place given to a `mutable &T` parameter without `mutable`, which names `mutable`, and the one for `mutable a` given to a parameter that doesn't take a mutable reference ([01](docs/spec/01-values-and-ownership/references.md#every-lend-for-change-is-marked));
- the compile errors for changing a temporary: `mutable` of a temporary, and an assignment into one, which v0.1 rejects without naming the fix ([01](docs/spec/01-values-and-ownership/bindings.md#temporaries-are-read-only));
- the compile error for `mutable` of a place that isn't changeable, such as a `let` local or a `&T` parameter or a part of one ([01](docs/spec/01-values-and-ownership/bindings.md#changeable-places));
- parameters `x: T` of a struct or array type, which own their arguments, given as `consume a`, `copy a` or a value, as `keep(makeEnemy())` ([01](docs/spec/01-values-and-ownership/parameters.md#parameters));
- `consume` of an owning parameter and of a field of one, which passes it on, returns it or stores it, or drops it with `_ = consume x` ([01](docs/spec/01-values-and-ownership/moving-values-out.md#moving-values-out));
- the compile error for a struct or an array given to an owning parameter without `consume` or `copy`, which names the marks that fit, and the one for an owning parameter that no code reads ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#unused-values)).

## v0.4: fixed-width integers and raw pointers

A fixed-width integer has the size a file format or a C library asks for, and a raw pointer reaches memory at an address, in code marked `unsafe` ([10](docs/spec/10-errors-and-safety/unsafe-code.md#unsafe-code)).

v0.4 adds:

- `Int8`, `Int16`, `Int32` and `Int64`, and `UInt8`, `UInt16`, `UInt32` and `UInt64`, each implicitly copyable as `Int` is, with literals typed by context, and arithmetic and comparisons under the overflow rule ([04](docs/spec/04-types/numbers-and-math.md#numbers));
- the conversions between any two of these eight types, `Int` and `UInt`, implicit only where they widen, as an `Int16` does to an `Int32`, and written elsewhere, as `Int32(x)`, which checks that the value fits ([04](docs/spec/04-types/numbers-and-math.md#conversions));
- `unsafe { }` blocks, and `unsafe` before an expression, which reading or writing `p.pointee`, offsetting a pointer as `p + n` or `p[i]`, and `ptr(to:)` need ([10](docs/spec/10-errors-and-safety/unsafe-code.md#what-needs-unsafe));
- `*T`, a raw pointer, implicitly copyable as `Int` is, and `ptr(to:)`, which gives a place's address, lent with `mutable` or shared ([10](docs/spec/10-errors-and-safety/unsafe-code.md#taking-an-address));
- reading and writing `p.pointee`, offsetting as `p + n` and `p[i]`, the distance `q - p`, and `p.cast(to: U.self)` ([10](docs/spec/10-errors-and-safety/unsafe-code.md#raw-pointers)).

## v0.5: C calls and the prelude

A program calls the C functions it declares, and prints through std's prelude, which is written in Rayo and which every program sees ([11](docs/spec/11-compilation-model.md#the-prelude)).

v0.5 adds:

- `extern(c) func` declarations of C functions, called only inside `unsafe` ([08](docs/spec/08-c-interop.md#08--c-interop));
- C's integer aliases, `CInt`, `CSize`, `CPtrDiff` and the rest, which the compiler provides for each target as the `IntN` or `UIntN` of its C type's size and signedness ([08](docs/spec/08-c-interop/imports-and-declarations.md#what-imports-as-what));
- the prelude: std's Rayo source, which ships inside `rayoc` and is compiled with every program, and which every program sees without an import ([11](docs/spec/11-compilation-model.md#the-prelude));
- a program's own declarations, which shadow the prelude's names;
- `print(Int)`, `print(UInt)` and `print(Bool)`, moved from the runtime's LLVM IR into the prelude, and written in Rayo over the host's write function, declared with `extern(c) func`: POSIX's `write`, and Windows' `_write`.

A panic stays in the runtime's LLVM IR.

## v0.6: methods

A struct declares in its body the functions that act on it. A call reaches them through a value, as `boss.takeHit(5)`, or through the type, as `Enemy.spawn()` ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#static-and-instance-members)).

v0.6 adds:

- methods in a struct's body, declared `func`, `mutating func` or `consuming func`, which take `self` as a `ref let`, as a `ref var` and owned, as `&T`, `mutable &T` and owning parameters take their arguments ([01](docs/spec/01-values-and-ownership/parameters.md#parameters));
- `self` in a method's body, which a plain or `mutating` method lends on as such a parameter is lent, and a `consuming` one moves or consumes as an owning parameter ([01](docs/spec/01-values-and-ownership/parameters.md#parameters));
- the struct's fields and methods named in a method's body without `self.`, where an ordinary use takes the nearest of the body's locals and parameters, `self`'s members, the struct's static members and the program's declarations ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#static-and-instance-members));
- a call by an unqualified name, which gathers the struct's methods, its static functions and the program's functions of that name, chooses among them by the overload rules, and gives a tie to the member ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#static-and-instance-members));
- a receiver given with no mark, which a plain method borrows, a `mutating` one borrows for change under the law of exclusivity, and a `consuming` one moves ([01](docs/spec/01-values-and-ownership/references.md#unmarked-places), [01](docs/spec/01-values-and-ownership/moving-values-out.md#moving-values-out));
- receivers that are locals, parameters, or fields or elements of either, as `world.boss.takeHit(5)` and `enemies[i].takeHit(5)`;
- a temporary as the receiver of a plain or a `consuming` method, as `makeEnemy().describe()`;
- `static func` members, called through the type, as `Enemy.boss(hp: 300)`, whose bodies see the struct's static members and none of its instance members, and `Self` in a struct's body;
- static and instance members as separate namespaces, and methods that share a name, told apart by their labels and parameter types as free functions are ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#functions-and-closures));
- the compile error for a `mutating` call on a place that isn't changeable, such as a `let` local, a `&T` parameter or `self` in a plain method ([01](docs/spec/01-values-and-ownership/bindings.md#changeable-places));
- the compile error for a `consuming` call on a place that can't be moved from, such as an element, a `&T` or `mutable &T` parameter, or `self` in a plain or `mutating` method ([01](docs/spec/01-values-and-ownership/moving-values-out.md#what-can-be-moved-from));
- the compile error for a `mutating` call on a temporary, which names the temporary, says that changing it does nothing since it is dropped at the end of its statement, and says to store it in a `var` ([01](docs/spec/01-values-and-ownership/bindings.md#temporaries-are-read-only));
- the compile error for two methods that differ only in how they take `self`, and the ones for an instance member reached through the type and a static member reached through a value ([04](docs/spec/04-types/collections.md#mutating-and-consuming-methods), [05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#static-and-instance-members)).

## Not yet planned

This list maps every feature of the spec that no version has finished, in no decided order. Where a version builds part of a feature, its line names the version and the part of the feature it leaves out.

Declarations and types:

- struct initializers other than the primary one ([04](docs/spec/04-types/structs.md#initializers)): v0.1 builds the primary initializer alone;
- `.init(…)` and the other implicit members, such as `.zero` ([05](docs/spec/05-protocols-generics-and-closures/operators.md#operators)): v0.1 makes a struct only by naming its type, and v0.2 builds `.init(repeating:)` of an inline array alone;
- static properties, computed properties and subscripts ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#static-and-instance-members), [02](docs/spec/02-views-and-dependencies/place-and-value-properties.md#place-and-value-properties)): v0.6 builds methods and static functions alone;
- default arguments and field defaults ([01](docs/spec/01-values-and-ownership/parameters.md#default-arguments), [04](docs/spec/04-types/structs.md#initializers)): v0.1's calls and initializers take every argument written out;
- `deinit`, `discard self` and move-only structs ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#destruction), [01](docs/spec/01-values-and-ownership/moving-values-out.md#what-can-be-moved-from), [01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#copyable-types));
- layout attributes, `@align` and packed structs, and the data layouts `Pod`, `TrailingArray` and `SoA` ([04](docs/spec/04-types/structs.md#layout-attributes), [04](docs/spec/04-types/data-layout.md#plain-and-specialized-data-layouts));
- types and functions declared inside a function ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#functions-and-closures));
- nested types, a program's own `typealias` declarations, and extensions ([04](docs/spec/04-types/structs.md#structs), [12](docs/spec/12-grammar/declarations.md#files-and-declarations)): v0.5 builds C's integer aliases alone, which the compiler declares;
- tuples ([04](docs/spec/04-types/collections.md#tuples-ranges-and-arrays));
- `.init(each:)` and `[_ of T]` ([04](docs/spec/04-types/collections.md#tuples-ranges-and-arrays)): v0.2 builds `[N of T]`, made by a literal or by `.init(repeating:)`;
- enums and optionals, and `when` with a subject ([04](docs/spec/04-types/enums.md#enums));
- untagged unions ([04](docs/spec/04-types/enums.md#untagged-unions));
- `Float` and `Double`, with their literals, the arithmetic operators `+`, `-`, `*` and `/`, unary `-`, and the comparisons, each one IEEE 754 operation ([04](docs/spec/04-types/numbers-and-math.md#floating-point));
- a float literal that nothing gives another type, such as `0.5` in `let x = 0.5`, as a `Double` ([04](docs/spec/04-types/numbers-and-math.md#numbers));
- the conversions between a float and an integer, and between `Float` and `Double`, as `Double(i)`, `Float(d)` and `Int(f)`, with the panics of a float that converts to no integer ([04](docs/spec/04-types/numbers-and-math.md#conversions), [04](docs/spec/04-types/numbers-and-math.md#float-to-integer-panics));
- `Half`, and the implicit widening of a floating-point type to a wider one and of an integer to a float ([04](docs/spec/04-types/numbers-and-math.md#conversions)): v0.4 widens an integer type to another alone;
- `Int.min`, `Int.max`, `min` and `max` ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#static-and-instance-members), [05](docs/spec/05-protocols-generics-and-closures/operators.md#equality-and-ordering)): v0.1 to v0.4 build the integer types without them;
- the `truncating:` and `clamping:` conversions between integers, and `Int(clamping: f)` and the other clamping conversions of a float ([04](docs/spec/04-types/numbers-and-math.md#conversions)): v0.2 and v0.4 build the unlabeled conversions between integers alone;
- named functions for a float's truncated remainder and its IEEE 754 remainder, which stand in for `%`, since floats have none ([04](docs/spec/04-types/numbers-and-math.md#floating-point));
- the wrapping, saturating, bitwise and shift operators ([04](docs/spec/04-types/numbers-and-math.md#integer-overflow-division-and-shifts));
- SIMD vectors ([04](docs/spec/04-types/numbers-and-math.md#simd-and-math));
- text ([04](docs/spec/04-types/collections.md#strings));
- `print` of any other `Formattable`, such as text, an interpolated literal, an `Int8` or a `Float` ([04](docs/spec/04-types/collections.md#printing)): v0.1 and v0.2 print `Int`, `Bool` and `UInt` alone, and v0.5 moves those into the prelude;
- backtick identifiers ([12](docs/spec/12-grammar/lexical.md#lexical)).

Statements and control flow:

- `for` loops and ranges ([04](docs/spec/04-types/collections.md#iteration)): v0.2's arrays wait on them for consuming iteration;
- labeled `break` and `continue`, and `repeat`-`while` ([04](docs/spec/04-types/collections.md#iteration)): v0.1 builds `while`, and `break` and `continue` of the innermost loop;
- several conditions in one `if` or `while` ([01](docs/spec/01-values-and-ownership/bindings.md#conditions)): v0.1 takes one `Bool`;
- `guard`, and a `when` with no subject ([04](docs/spec/04-types/enums.md#matching-with-when-and-choosing-with-if));
- `do` blocks ([10](docs/spec/10-errors-and-safety/typed-errors.md#handling-errors-with-do-and-catch));
- `defer` and typed errors ([10](docs/spec/10-errors-and-safety/typed-errors.md#typed-errors)).

Ownership and borrowing:

- `ref var` bindings, as `ref var m = mutable p`, and the errors for a `ref var` given `&p` and a `ref let` given `mutable p` ([01](docs/spec/01-values-and-ownership/bindings.md#bindings-that-refer-to-a-place)): v0.2 builds `ref let` alone;
- `&` of a temporary, as `&makeEnemy()`, and a value lent to a `&T`, as `show(makeEnemy())` ([01](docs/spec/01-values-and-ownership/references.md#making-a-reference)): v0.1 to v0.5 lend only a local, a parameter, a field or an element of one, or a value given to `print`. From v0.6, a plain method borrows a temporary receiver too;
- `consume` of any other place, such as a temporary ([01](docs/spec/01-values-and-ownership/moving-values-out.md#moving-values-out)): v0.2 builds `consume` of a local or a field of one, and v0.3 of an owning parameter or a field of one;
- `ImplicitlyCopyable`, its conformances declared by a struct or an enum, and the other implicitly copyable types, such as tuples, `Handle` and `T?` ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#implicitly-copyable-types)): v0.2 copies `Int`, `UInt` and `Bool` implicitly, and v0.4 the fixed-width integers and `*T`;
- implicit copies in the positions v0.2 doesn't build, such as a condition's binding, a `for` or `when` name and a tuple literal's element ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#implicit-copies));
- a field of a temporary as a method's receiver, as `makeWorld().boss.describe()` ([01](docs/spec/01-values-and-ownership/references.md#unmarked-places)): v0.6 takes a whole temporary as a receiver alone;
- `copy` of a field of a temporary, as `copy makeEnemy().stats`, and a `let` of one, which owns it ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#copies)): v0.1 copies a field of a local or a `&T` parameter, and v0.2 borrows one with a `ref let`;
- references held as values, as `let best = &enemies[0]` holds a `&Enemy`, and the other views, which are [scoped values](docs/spec/02-views-and-dependencies/scoped-values.md), with the dependencies that check them ([01](docs/spec/01-values-and-ownership/references.md#references), [02](docs/spec/02-views-and-dependencies.md#dependencies)): v0.1 to v0.5 build references only as `&T` and `mutable &T` parameters and `ref let` bindings. From v0.6, a plain or `mutating` method's `self` is one too;
- a place lent wherever else a `&T` is expected, as `let top: &Enemy = enemies[0]` lends one, and the conversions of the reference it makes, as to a `&[T]` ([05](docs/spec/05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected)): v0.2 lends a place given to a `&T` parameter;
- closures and function values ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds));
- handles and objects ([03](docs/spec/03-handles-and-objects.md#03--handles-and-objects)).

Protocols, compile time and modules:

- conformances, protocols and user-declared operators ([05](docs/spec/05-protocols-generics-and-closures/protocols-and-generics.md#protocols-and-generics), [05](docs/spec/05-protocols-generics-and-closures/operators.md#operators)): v0.2's arrays wait on them for `==` and the comparisons;
- type values, `T.self` and `Type<T>` ([05](docs/spec/05-protocols-generics-and-closures/protocols-and-generics.md#value-parameters-and-type-values)): v0.4 builds `U.self` only as `cast(to:)`'s argument;
- `const` and globals ([09](docs/spec/09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const), [07](docs/spec/07-concurrency/global-state.md#global-state)): v0.2's arrays wait on `const` for the compile error on a `const` index out of range;
- `static if` and conditional compilation ([09](docs/spec/09-compile-time/constants-and-conditions.md#static-if-and-conditional-compilation));
- reflection, generated declarations and the other compile-time features ([09](docs/spec/09-compile-time.md#09--compile-time));
- attributes, among them `@inline` ([09](docs/spec/09-compile-time/attributes-and-runtime-data.md#attributes), [11](docs/spec/11-compilation-model.md#functions-that-are-never-calls-inline));
- access control and modules ([11](docs/spec/11-compilation-model.md#modules-and-names)).

Safety, memory and the platform:

- the check for running out of stack, which ends the program with a report before anything is written past the stack's end ([10](docs/spec/10-errors-and-safety/panics.md#what-ends-the-program)): v0.1 builds recursion without it;
- `precondition`, `assert`, `unreachable` and `Never` ([10](docs/spec/10-errors-and-safety/panics.md#assert-and-precondition), [04](docs/spec/04-types/enums.md#enums));
- unwinding, and catching a panic ([10](docs/spec/10-errors-and-safety/panics.md#what-a-panic-does));
- `unchecked` blocks and `@checks` ([10](docs/spec/10-errors-and-safety/checks-and-build-modes.md#check-levels));
- heap storage: allocators, generics, and owning collections such as `List` ([06](docs/spec/06-memory-and-allocators.md#06--memory-and-allocators), [04](docs/spec/04-types/collections.md#collections-and-strings));
- concurrency ([07](docs/spec/07-concurrency.md#07--concurrency));
- `*T?`, which needs optionals, and `p.move()`, which needs move-only types ([10](docs/spec/10-errors-and-safety/unsafe-code.md#raw-pointers), [10](docs/spec/10-errors-and-safety/unsafe-code.md#raw-memory)): v0.4 builds `*T` alone;
- `&p[0..<n]` and a run's `baseAddress`, which need ranges and runs ([10](docs/spec/10-errors-and-safety/unsafe-code.md#raw-pointers), [04](docs/spec/04-types/collections.md#runs-of-elements));
- the rest of `unsafe` code: `unsafe func`, `*Void`, the conversions between a pointer and an integer, the alignment queries, the other raw-memory operations, raw allocations and hardware access ([10](docs/spec/10-errors-and-safety/unsafe-code.md#unsafe-code));
- `@safe` modules ([10](docs/spec/10-errors-and-safety/unsafe-code.md#safe-modules));
- `import(c)` of C headers ([08](docs/spec/08-c-interop.md#08--c-interop)): v0.5 reaches C through `extern(c) func` declarations alone;
- `@c` function pointers ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#c-function-pointers));
- calling Rayo from C, through exported functions and callbacks ([08](docs/spec/08-c-interop/calling-rayo-from-c.md#calling-rayo-from-c));
- embedding Rayo in a C program ([08](docs/spec/08-c-interop/c-contract-and-embedding.md#embedding-rayo-in-a-c-program)).

Besides the spec's features, `rayoc` needs a way to install a toolchain ([#184](https://github.com/rayo-lang/rayo/issues/184), [#216](https://github.com/rayo-lang/rayo/issues/216)), and a way to compile std as a library of its own, where v0.5 compiles std's source with every program.
