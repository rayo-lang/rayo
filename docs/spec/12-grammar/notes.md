# Notes

[12 · Grammar](../12-grammar.md)

## Blocks and closure literals

**A closure literal is never a statement.** A `{` at the start of a statement begins a closure literal, and one used as a whole statement is a compile error, since it would never run. `do { … }` groups statements instead:

```swift
{ reset() }         // error: this closure would never run
do { reset() }      // groups statements, and runs them
```

**A `when` arm's body is a block**, as an `if` branch is, and the `{` after its patterns or guard begins it. The block's value is its last expression ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)). So an arm whose value is a closure literal writes it in parentheses.

**A `{` right after `when` begins its body, so that `when` has no subject.** A subject that is a closure literal is written in parentheses:

```swift
when action {
    .retry { attempt() }          // the arm's value is what attempt() returns
    else { ({ attempt() }) }      // a closure literal, in parentheses: the arm's value is the closure
}
when { … }                        // '{' right after 'when' begins the body: no subject
when ({ … }) { … }                // a closure literal as the subject, in parentheses
```

**A block's last expression can't start with `.` on a line of its own**, since that line joins the one above ([where statements end](../12-grammar.md#where-statements-end)). An implicit member on a line of its own as a block's value is written in parentheses:

```swift
let shown: DoorState = if open {
    playSound()
    (.open)                   // written '.open', this line would join the one above: 'playSound().open'
} else { .closed }
```

**In any expression that a statement's block follows, a `{` always starts the block, never a trailing closure.** To pass a closure there, parenthesize the call:

```swift
for x in items.filter { $0.alive } { use(x) }     // error: '{ $0.alive }' is read as the loop's body
for x in items.filter({ $0.alive }) { use(x) }   // the closure is inside the call's parentheses
```

**These are the expressions that a block follows:**

- **Conditions, subjects and tests**: the expressions after `if`, `while`, `when`, `for … in`, `using … =`, `static if` and `static for … in`, the patterns after `catch`, and a `when` arm's patterns or test.
- **`where` clauses before a block**: `for … where`, `static for … where`, `catch … where`, a `when` arm's `where` guard, and the `where` of a declaration.

**Where `else` follows instead of a block, closures work as usual**: in a `guard`'s conditions.

**In expression position, `unsafe` before `{` begins an `unsafe-block-expr`**, an unsafe block whose value is its last expression, not `unsafe` applied to a closure literal, which is written `unsafe ({ … })`. As a statement, `unsafe { … }` is an ordinary unsafe block:

```swift
let now = unsafe { platform_time_seconds() }      // an unsafe block, whose value is the call's
let clock = unsafe ({ platform_time_seconds() })  // 'unsafe' applied to a closure literal
unsafe { platform_set_audio_callback(onAudioEvent, nil) }   // a statement: an ordinary unsafe block
```

## Operators and punctuation

**A `?` after an operand is always postfix optional chaining**, since Rayo has no ternary operator.

**Whitespace tells the prefix and postfix range operators, as in `..<x` and `x...`, from the binary ones.** Between two operands, with whitespace on both sides or on neither, a range operator is binary. Attached to an operand on one side only, it is prefix or postfix, whatever is on its other side: whitespace, a bracket or punctuation.

```swift
let hp = copy target?.hp            // '?' after an operand: optional chaining
let all = 0..<n                     // between two operands, with whitespace on neither side: binary
let tail = xs[3...]                 // attached to 3 only, and closed by ']': postfix
let head = xs[..<n]                 // attached to n only: prefix
```

**The `&` prefix marks a place lent for change.** It is valid only in the positions that 01 lists ([01](../01-values-and-ownership/bindings.md#lending-a-place-for-change)), such as a `mutable` argument, a binding, pattern or loop sequence that lends a place, and an `if` or `when` arm's value that stands in one.

**An operator can be passed as a function value.** Bare, it is allowed only as a whole argument, as in `reduce(0, +)`. Elsewhere it is written in parentheses, `(+)`. The expected function type chooses the overload, using 05's bounded lookup ([05](../05-protocols-generics-and-closures/operators.md#operators)).

```swift
let total = counts.reduce(0, +)         // a bare operator as a whole argument
let add: (Int, Int) -> Int = (+)        // anywhere else, in parentheses
```

**`<` both compares and opens generic arguments, and the parser tells the two apart without knowing what any name means.** In expression position, `identifier <` starts generic arguments only if both of these hold:

- the tokens up to the matching `>` parse as `generic-args`;
- the token after `>` is one of `(`, `.`, `)`, `]`, `,`, `:`, `;`, `?`, `!`, `{`, a newline, or an operator that can't begin an operand: `==`, `!=`, `&&`, `||` or `??`.

**Otherwise `<` is the comparison operator.**

```swift
let xs = List<Int>()                              // '<Int>' parses as generic arguments, and '(' follows
if a < b, c > d { … }                             // two comparisons: 'd' can't follow generic arguments
f(a < b, c > (d))                                 // a generic call 'a<b, c>(d)': written '(c > d)', it is two comparisons
static if T == List<Int> || T == Set<Int> { … }   // '||' can't begin an operand, so '<Int>' is generic arguments
```

**While generic arguments are being parsed, a `>>`, `>>=` or `>=` token is split into `>` followed by the rest.** That holds for generic arguments in a type, and for those after an `identifier <` that starts them:

```swift
var b: Box<Int>= a                                // '>=' splits, so 'b' is a Box<Int>
let q = SpscQueue<Shared<Snapshot>>(capacity: 3)  // '>>' splits, closing two argument lists
```

## Parentheses and conventions in types

**In a type, `(` and `mutable` each have more than one reading.** A `(` can open a function type's parameters, an error union, a tuple, or a single parenthesized type. Before a type, `mutable` can be a parameter convention or part of the type.

**Every `(` in a type is decided with the same bounded lookahead as generic arguments** ([above](#operators-and-punctuation)):

- **Function type parameters.** When the matching `)` is followed by `throws` or `->`, the list is a function type's parameters, so `(IoError | ParseError) -> Void` takes one union parameter.
- **Error unions and tuples.** Otherwise `(A | B)` is an error union and `(A, B)` a tuple.
- **A single type.** A parenthesized single type without a label or a trailing comma is that type, not a one-element tuple. The exception is `(any P)` after `mutable`, or as the type argument of `Box` or an object pointer, which keeps the shared view apart from the form `any` makes there (below).

```swift
typealias OnError = (IoError | ParseError) -> Void    // ')' then '->': one error-union parameter
typealias Failure = (IoError | ParseError)            // an error union
typealias Hit = (target: Handle<Enemy>, damage: Float) // a tuple
typealias Count = (Int)                               // just Int, not a one-element tuple
typealias Single = (Int,)                             // a one-element tuple
```

**In a parameter's type, `mutable` directly followed by `any` is always the exclusive existential view type** ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)). The `mutable` convention on a shared existential view is written `mutable (any P)`, which lets a callee reassign which value the caller's shared view refers to:

```swift
func strike(_ d: mutable any Damageable) { ... }        // the exclusive existential view type
func retarget(_ d: mutable (any Damageable)) { ... }    // the mutable convention on a shared existential view
```

**An expression names a type in two ways**: by a type name followed by a member, as in `Vertex.self`, `T.fields` and `Int.max`, or as an operand of `==` or `!=` that compares types, as in `T == List<Int>` ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#value-parameters-and-type-values)).

**Any other type in an expression is parenthesized.** A `(` in expression position begins such a type when what it holds starts as only a type can, with `*`, `any`, `some`, `mutable any`, `@c` or `[ … of`, or when the matching `)` is followed by `.self`. Any other such type is named through a `typealias` first:

```swift
let size = (*Int).size                // '*' starts as only a type can
let pair = (Int, Float).self          // ')' is followed by '.self'
typealias Pair = (Int, Float)
let p = Pair.construct { … }          // any other such type is named through a typealias
```

**In the type argument of `Box` or an object pointer, `any` right after `<` makes the unscoped existential** ([05](../05-protocols-generics-and-closures/protocols-and-generics.md#any-p-explicit-dynamic-dispatch)). The unscoped existentials are types of their own, which binding a type parameter never makes. So the box that `Box<T>` gives with `T` bound to `any P` is written apart, as `Box<(any P)>`: a box holding a shared existential view.

## Trailing commas

**Every comma-separated list closed by `)`, `]` or `>` allows a trailing comma**, as the productions show. With one, a parenthesized single expression or type, outside a call's arguments and a function type's parameters, is a one-element tuple, as `(x,)` and `(Int,)` are ([above](#parentheses-and-conventions-in-types)).
