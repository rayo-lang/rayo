# Roadmap

Rayo's [spec](docs/spec/README.md) defines the whole language, and `rayoc` builds it a small version at a time. Each version adds a few features of the spec, end to end: a program that uses them parses, checks, compiles, links and runs. This file gives the feature set of each version, two versions ahead and no further.

## What a version is

**Each version lists its feature set, once.** The list says what the release holds, so it stays the same as those features come to run. The work toward the version, what of it is left, and its bugs and refactors are in the [issue tracker](https://github.com/rayo-lang/rayo/issues).

**A version is done when every feature it lists runs end to end, and its proof program shows it.** The proof program is one Rayo program, `examples/v0.N/<name>.rayo`, with its expected output beside it in `<name>.out`. A driver test runs it, in debug and in release builds, on every platform CI tests: macOS arm64, Linux x64, Windows x64 and Windows arm64. The driver tests check each feature in detail, so the proof program only puts the features to work together. The other programs in `examples/` use the whole language, more than `rayoc` compiles, and no test runs them.

**A version that builds part of a spec feature leaves the rest mapped in [Not yet planned](#not-yet-planned)**, so every feature of the spec is in a version or in that list.

**A half version, such as v0.2.5, adds one small feature.** It has no proof program of its own: it extends the program of the version before it.

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
- `print(Int)`, and `print(Bool)`, which prints `true` or `false` ([04](docs/spec/04-types/collections.md#printing)).

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

## v0.2.5: `Float` and `Double`

v0.2.5 adds:

- `Float` and `Double`, with their literals, the arithmetic operators `+`, `-`, `*` and `/`, unary `-`, and the comparisons, each one IEEE 754 operation ([04](docs/spec/04-types/numbers-and-math.md#floating-point));
- a float literal that nothing gives another type, such as `0.5` in `let x = 0.5`, as a `Double` ([04](docs/spec/04-types/numbers-and-math.md#numbers));
- implicit copies of `Float` and `Double`, as v0.2 makes of `Int`, `UInt` and `Bool` ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#implicit-copies));
- the conversions between every pair of `Int`, `UInt`, `Float` and `Double` that v0.2 doesn't build, as `Double(i)`, `Float(d)` and `Int(f)` ([04](docs/spec/04-types/numbers-and-math.md#conversions)):
    - a float to an integer rounds toward zero, and panics in every build with `float to integer conversion of NaN` or `float to integer conversion out of range`;
    - an integer to a float, and a `Double` to a `Float`, round to nearest, and a value too large for a `Float` becomes an infinity;
- `print(Float)` and `print(Double)`, which print the shortest decimal that reads back as the same value ([04](docs/spec/04-types/collections.md#printing)).

Its proof program extends v0.2's.

## v0.3: changing values in place

v0.3 adds:

- `mutable &T` parameters, which a call lends a place with `mutable &a`, and parameters `x: T` of a struct or array type, which own their arguments, with the [law of exclusivity](docs/spec/01-values-and-ownership/exclusivity.md#the-law-of-exclusivity), and the error for an owning parameter that no code reads ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#unused-values));
- the compile errors for a place given to a `mutable &T` parameter without `mutable &`, and for a struct or an array given to an owning parameter without `consume` or `copy`, each of which names the marks that fit;
- the compile error for `mutable &a` given to a parameter that doesn't take a mutable reference;
- `mutating func`, whose `self` names the receiver's place as a `mutable &T` parameter names its argument's.

## Not yet planned

This list maps every feature of the spec that no version has finished, in no decided order. Where a version builds part of a feature, its line names the version and the part of the feature it leaves out.

Declarations and types:

- struct initializers other than the primary one ([04](docs/spec/04-types/structs.md#initializers)): v0.1 builds the primary initializer alone;
- `.init(…)` and the other implicit members, such as `.zero` ([05](docs/spec/05-protocols-generics-and-closures/operators.md#operators)): v0.1 makes a struct only by naming its type, and v0.2 builds `.init(repeating:)` of an inline array alone;
- methods, `self`, static members and computed properties, and subscripts ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#static-and-instance-members), [02](docs/spec/02-views-and-dependencies/place-and-value-properties.md#place-and-value-properties)): v0.3 adds `mutating func` alone;
- default arguments and field defaults ([01](docs/spec/01-values-and-ownership/parameters.md#default-arguments), [04](docs/spec/04-types/structs.md#initializers)): v0.1's calls and initializers take every argument written out;
- `deinit` and move-only structs ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#destruction), [01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#copyable-types));
- layout attributes, `@align` and packed structs, and the data layouts `Pod`, `TrailingArray` and `SoA` ([04](docs/spec/04-types/structs.md#layout-attributes), [04](docs/spec/04-types/data-layout.md#plain-and-specialized-data-layouts));
- types and functions declared inside a function ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#functions-and-closures));
- nested types, type aliases and extensions ([04](docs/spec/04-types/structs.md#structs), [12](docs/spec/12-grammar/declarations.md#files-and-declarations));
- tuples ([04](docs/spec/04-types/collections.md#tuples-ranges-and-arrays));
- `.init(each:)` and `[_ of T]` ([04](docs/spec/04-types/collections.md#tuples-ranges-and-arrays)): v0.2 builds `[N of T]`, made by a literal or by `.init(repeating:)`;
- enums and optionals, and `when` with a subject ([04](docs/spec/04-types/enums.md#enums));
- untagged unions ([04](docs/spec/04-types/enums.md#untagged-unions));
- the other number types, and implicit widening between them ([04](docs/spec/04-types/numbers-and-math.md#conversions)): v0.1 builds `Int`, v0.2 `UInt`, and v0.2.5 `Float` and `Double`, all without implicit widening, and v0.2's array literals wait on the rest to widen their elements;
- `Int.min`, `Int.max`, `min` and `max` ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#static-and-instance-members), [05](docs/spec/05-protocols-generics-and-closures/operators.md#equality-and-ordering)): v0.1 builds `Int` without them;
- `Int(clamping: f)` and the other clamping conversions of a float ([04](docs/spec/04-types/numbers-and-math.md#conversions)): v0.2.5 builds the unlabeled form alone;
- named functions for a float's truncated remainder and its IEEE 754 remainder, which stand in for `%`, since floats have none ([04](docs/spec/04-types/numbers-and-math.md#floating-point));
- the wrapping, saturating, bitwise and shift operators ([04](docs/spec/04-types/numbers-and-math.md#integer-overflow-division-and-shifts));
- SIMD vectors ([04](docs/spec/04-types/numbers-and-math.md#simd-and-math));
- text ([04](docs/spec/04-types/collections.md#strings));
- `print` of any other `Formattable`, such as text, an interpolated literal or `Half` ([04](docs/spec/04-types/collections.md#printing)): v0.1, v0.2 and v0.2.5 print `Int`, `Bool`, `UInt`, `Float` and `Double` alone;
- backtick identifiers ([12](docs/spec/12-grammar/lexical.md#lexical)).

Statements and control flow:

- `for` loops and ranges ([04](docs/spec/04-types/collections.md#iteration)): v0.2's arrays wait on them for consuming iteration;
- labeled `break` and `continue`, and `repeat`-`while` ([04](docs/spec/04-types/collections.md#iteration)): v0.1 builds `while`, and `break` and `continue` of the innermost loop;
- several conditions in one `if` or `while` ([01](docs/spec/01-values-and-ownership/bindings.md#conditions)): v0.1 takes one `Bool`;
- `guard`, and a `when` with no subject ([04](docs/spec/04-types/enums.md#matching-with-when-and-choosing-with-if));
- `do` blocks ([10](docs/spec/10-errors-and-safety/typed-errors.md#handling-errors-with-do-and-catch));
- `defer` and typed errors ([10](docs/spec/10-errors-and-safety/typed-errors.md#typed-errors)).

Ownership and borrowing:

- `ref var` bindings, as `ref var m = mutable &p`, and the errors for a `ref var` given `&p` and a `ref let` given `mutable &p` ([01](docs/spec/01-values-and-ownership/bindings.md#bindings-that-refer-to-a-place)): v0.2 builds `ref let` alone;
- `&` and `mutable &` of a temporary, as `heal(mutable &makeEnemy())`, and a value lent to a `&T`, as `show(makeEnemy())` ([01](docs/spec/01-values-and-ownership/references.md#making-a-reference)): v0.1 to v0.3 lend only a local, a parameter, a field or an element of one, or a value given to `print`;
- `consume` of any other place, such as a parameter that owns its argument, or a temporary ([01](docs/spec/01-values-and-ownership/moving-values-out.md#moving-values-out)): v0.2 builds `consume` of a local or a field of one;
- `ImplicitlyCopyable`, its conformances declared by a struct or an enum, and the other implicitly copyable types, such as tuples, `Handle` and `T?` ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#implicitly-copyable-types)): v0.2 copies `Int`, `UInt` and `Bool` implicitly, and v0.2.5 `Float` and `Double`;
- implicit copies in the positions v0.2 doesn't build, such as a condition's binding, a `for` or `when` name and a tuple literal's element ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#implicit-copies));
- `copy` of a field of a temporary, as `copy makeEnemy().stats`, and a `let` of one, which owns it ([01](docs/spec/01-values-and-ownership/moves-copies-destruction.md#copies)): v0.1 copies a field of a local or a `&T` parameter, and v0.2 borrows one with a `ref let`;
- references held as values, as `let best = &enemies[0]` holds a `&Enemy`, and the other views, which are [scoped values](docs/spec/02-views-and-dependencies/scoped-values.md), with the dependencies that check them ([01](docs/spec/01-values-and-ownership/references.md#references), [02](docs/spec/02-views-and-dependencies.md#dependencies)): v0.1 and v0.2 build references only as `&T` parameters and `ref let` bindings;
- a place lent wherever else a `&T` is expected, as `let top: &Enemy = enemies[0]` lends one, and the conversions of the reference it makes, as to a `&[T]` ([05](docs/spec/05-protocols-generics-and-closures/implicit-conversions.md#places-lent-where-a-reference-is-expected)): v0.2 lends a place given to a `&T` parameter;
- closures and function values ([05](docs/spec/05-protocols-generics-and-closures/functions-and-closures.md#closure-kinds));
- handles and objects ([03](docs/spec/03-handles-and-objects.md#03--handles-and-objects)).

Protocols, compile time and modules:

- conformances, protocols and user-declared operators ([05](docs/spec/05-protocols-generics-and-closures/protocols-and-generics.md#protocols-and-generics), [05](docs/spec/05-protocols-generics-and-closures/operators.md#operators)): v0.2's arrays wait on them for `==` and the comparisons;
- `const` and globals ([09](docs/spec/09-compile-time/constants-and-conditions.md#running-code-at-compile-time-const), [07](docs/spec/07-concurrency/global-state.md#global-state)): v0.2's arrays wait on `const` for the compile error on a `const` index out of range;
- reflection, `static if`, generated declarations and the other compile-time features ([09](docs/spec/09-compile-time.md#09--compile-time));
- attributes, among them `@inline` ([09](docs/spec/09-compile-time/attributes-and-runtime-data.md#attributes), [11](docs/spec/11-compilation-model.md#functions-that-are-never-calls-inline));
- access control and modules ([11](docs/spec/11-compilation-model.md#modules-and-names)).

Safety, memory and the platform:

- the check for running out of stack, which recursion needs ([10](docs/spec/10-errors-and-safety/panics.md#what-ends-the-program)): v0.1 builds recursion without it;
- `precondition`, `assert`, `unreachable` and `Never` ([10](docs/spec/10-errors-and-safety/panics.md#assert-and-precondition), [04](docs/spec/04-types/enums.md#enums));
- unwinding, and catching a panic ([10](docs/spec/10-errors-and-safety/panics.md#what-a-panic-does));
- `unchecked` blocks and `@checks` ([10](docs/spec/10-errors-and-safety/checks-and-build-modes.md#check-levels));
- heap storage: allocators, generics, and owning collections such as `List` ([06](docs/spec/06-memory-and-allocators.md#06--memory-and-allocators), [04](docs/spec/04-types/collections.md#collections-and-strings));
- concurrency ([07](docs/spec/07-concurrency.md#07--concurrency));
- C interop, and the raw pointers and `unsafe` code it needs ([08](docs/spec/08-c-interop.md#08--c-interop), [10](docs/spec/10-errors-and-safety/unsafe-code.md#unsafe-code)).

Besides the spec's features, `rayoc` needs a way to install a toolchain ([#184](https://github.com/rayo-lang/rayo/issues/184), [#216](https://github.com/rayo-lang/rayo/issues/216)).
