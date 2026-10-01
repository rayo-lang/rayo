# 12 · Grammar

The grammar is normative for syntax only: what a program means is in chapters 01–11.

The productions don't show where one statement ends and the next begins. Newlines decide that:

```swift
let total = base +              // a line that ends in a binary operator continues
    bonus * 2
let hps = enemies
    .filter({ $0.hp > 0 })      // a line that starts with '.' joins the one above
    .map({ copy $0.hp })
spawn(
    at: origin,                 // inside ( and [, newlines are whitespace
    count: 3
)
if ready { start() }
else { wait() }                 // a line that starts with 'else' joins the one above
x = 1; y = 2                    // ';' separates statements on one line
```

**Newlines end statements, and `;` separates statements on one line.** The rules below decide where a newline doesn't end a statement, and where an arm of a `when` begins:

- **Inside brackets, newlines are whitespace.** Where the innermost unclosed bracket is `(` or `[`, a newline never ends anything, so an argument list or array literal can span lines and close on a line of its own. Where it is `{`, the other rules apply.
- **A line continues** when it ends in a binary operator (a `>` that closes generic arguments isn't one), `=` or a compound assignment, `->`, `,`, `(`, `[`, `{`, or an attribute (`@reflect` on its own line applies to the declaration below it).
- **The next line joins the current one** when it starts with `.` (method chaining), a binary operator other than the prefix-capable `-`, `&`, `..<` and `...`, or with `else`, `catch`, `where`, `throws` or `->`, so a signature can wrap before its result. So a line that starts with `-x` or `..<n` starts a new statement, unless the line above continues.
- **In a `when` body, a line starts a new arm when it reaches `->` outside brackets and braces, alone or with the lines that continue its patterns and guard**: those that start with `where` or `->`, and each line after one ending in `,`. A line that is itself such a continuation starts none. This rule comes before the one on a leading `.`, so `.idle -> …` and `else -> …` begin arms, and so do `.chase(let t)` on one line and `where t.isBoss -> "fleeing"` on the next, together. Any other line in the body follows the rules above, so an arm's body can continue on the next line. A function type in a `when` body, after `as` or inside generic arguments, is parenthesized, as in `f as ((Int) -> Int)`, so its `->` never starts an arm.

The grammar is EBNF: `?` means optional, `*` zero or more, `+` one or more, `|` alternation, and `'x'` a literal token. Text between `(*` and `*)` is a comment. Where the productions alone leave a choice open, [Notes](#notes) at the end settles it. The chapters' examples sometimes show a declaration without its body, or with `…` in it, where the body doesn't matter; those are sketches, not source.

## Lexical

```ebnf
identifier   = (letter | '_') (letter | digit | '_')* | '`' any-keyword '`'
             | '$' digits                                     (* implicit closure parameters: $0, $1 *)
             | '\(' expression ')' ;                          (* computed name, from a const string (09) *)
int-literal  = digits | '0x' hexdigits | '0b' bindigits | '0o' octdigits ;   (* '_' allowed between digits *)
float-literal= digits '.' digits exponent? | digits exponent ;      (* '_' allowed between digits *)
exponent     = ('e' | 'E') ('+' | '-')? digits ;
string-lit   = '"' (char | escape | '\(' expression ')')* '"'
             | '"""' newline (char | newline | escape | '\(' expression ')')* newline (' ' | '\t')* '"""' ;
plain-string-lit = '"' (char | escape)* '"'
             | '"""' newline (char | newline | escape)* newline (' ' | '\t')* '"""' ;   (* no interpolation: the strings C reads (08) *)
escape       = '\' ('0' | 'n' | 'r' | 't' | '\' | '"' | "'" | 'u{' hexdigits '}') ;
comment      = '//' to-end-of-line | '/*' nested-comment '*/' ;
```

A source file is UTF-8, and one that isn't is a compile error. `\u{…}` holds one to eight hex digits naming a Unicode scalar value, 0 to D7FF or E000 to 10FFFF, and stands for its UTF-8 encoding; any other value is a compile error. A `-` is always an operator; [04](04-types.md#literals) says when a prefix one is checked with its literal as one value.

`any-keyword` is any keyword or contextual keyword below. A multi-line string holds the lines between its delimiters, each with the closing `"""` line's indentation removed, and joined by `\n`: the newlines after the opening `"""` and before the closing one aren't part of it. After `.` in a member access, an integer literal ends before the next `.`, so `t.0.1` is two element accesses.

Keywords: `let var const func task struct enum protocol extension typealias import public private
init deinit self Self if else guard when case for in while repeat break continue return
throw throws try catch do defer static mutable owned consuming copy consume mutating any some
where with await yield unsafe unchecked using extern as is nil true false
associatedtype subscript`.

`read`, `modify`, `get`, `set`, `c`, `allocator`, `move`, `of`, `error`, `prefix`, `noalloc`, `stack`, `union`, `keep`, `borrows`, `outlives`, `rebind`, `to` and `discard` are contextual keywords: they are keywords only in the positions below and can be used as identifiers anywhere else. `union` is a keyword only after a declaration's attributes and modifiers, or at the start of an import config rule, when an identifier follows it, so `a.union(b)` stays a method call. `keep` is a keyword only at the start of a function type's parameter, when a convention or a type follows it, so a parameter whose type is named `keep` still parses. `error` is a keyword only after `static`, `prefix` only in an `import c … where` clause, `noalloc` only at the start of a rule inside an import config or after `extern c`, and `stack` only at the start of such a rule, after `extern c` or its `noalloc`, or after `@c` in a type. `borrows` and `outlives` are keywords only in a `where` clause, right after an item's subject: a requirement starts with a type, which a dotted path such as `out.items` also parses as, and the token after it tells a `borrows-item` from a constraint. `rebind` is a keyword only at the start of a statement when an identifier follows it, so a call `rebind(x)` still parses, and `to` only after `rebind` and that identifier. `discard` is a keyword only at the start of a statement when `self` follows it.

**Argument labels may be keywords.** A parameter's external label, and the label of an argument, can be any keyword: `func index(of x: T, in s: Span<T>)` is called as `index(of: x, in: s)`. An argument's label is always followed by `:`, and a parameter's external label by its internal name and then `:`, with the convention after the `:`, so a keyword label is never ambiguous.

## Files and declarations

```ebnf
file          = file-item* ;
file-item     = import | declaration | file-static-if | file-static-for | static-error ;
file-static-if= 'static' 'if' expression '{' file-item* '}' ('else' (file-static-if | '{' file-item* '}'))? ;
                                                                   (* top level: may include or exclude whole imports, under 09's rule for their conditions *)
file-static-for= 'static' 'for' identifier 'in' expression ('where' expression)? '{' file-item* '}' ;
                                                                   (* generates declarations, once per element; no import inside, at any depth (09) *)
static-error  = 'static' 'error' '(' string-lit ')' ;              (* a compile error where this is built or instantiated (09);
                                                                      each interpolated segment is a const, formatted at compile time *)
import        = 'import' module-path ('as' identifier)?
              | 'import' 'c' plain-string-lit ('as' identifier)? ('where' 'prefix' ':' plain-string-lit)? c-import-config? ;
c-import-config = 'unsafe' '{' c-import-rule* '}' ;                 (* asserted facts; rejected in @safe modules *)
c-import-rule = 'noalloc' identifier (',' identifier)*             (* C functions that allocate nothing (08) *)
              | c-stack identifier (',' identifier)*                 (* the stack those functions need (08) *)
              | ('struct' | 'union' | 'enum') identifier 'in' plain-string-lit ;   (* the header whose reading has a type this one only declares (08) *)
module-path   = identifier ('.' identifier)* ;

declaration   = attribute* modifier* ( let-decl | var-decl | const-decl | func-decl | task-decl
              | struct-decl | union-decl | enum-decl | protocol-decl | extension-decl | typealias-decl
              | extern-c-decl ) ;
modifier      = 'public' | 'private' | 'static' | 'mutating' | 'consuming' | 'unsafe' ;
                                                                   (* each only where a chapter gives it a meaning, and a compile error elsewhere:
                                                                      'public' and 'private' on a declaration outside a function body (11),
                                                                      'static' on a type's member, 'mutating' and 'consuming' on a method,
                                                                      'mutating' on a computed property or subscript (04),
                                                                      'unsafe' on a function, initializer, subscript, accessor, field or protocol.
                                                                      An extern-c-decl or protocol-decl only at a file's top level *)
attribute     = '@' (type-name | keyword) ('(' attribute-args? ')')? ;   (* a keyword right after '@' is an attribute name: @guard; @ui.Bounds names another module's *)
attribute-args= attribute-arg (',' attribute-arg)* ','? ;
attribute-arg = ((identifier | keyword) ':')? (expression | keyword) ;   (* @packed(4); @checks(.all); @reflect(private), a keyword argument; @export(c, name: "nav_path"), a labeled one *)

const-decl    = 'const' identifier (':' type)? '=' expression ;
let-decl      = 'owned'? 'let' binding (',' binding)* ;              (* let lo = 0, hi = 10; 'owned' only on a local (01) *)
var-decl      = 'owned'? 'var' binding (',' binding)* | 'var' identifier ':' type where-clause? accessor-block ;
binding       = pattern (':' type)? ('=' expression)? ;

func-decl     = 'func' func-name generic-params? param-clause throws-clause? ('->' type)?
                where-clause? block ;
func-name     = identifier | operator ;
operator      = '+' | '-' | '*' | '/' | '%' | '==' | '!=' | '<' | '<=' | '>' | '>=' | '&' | '|' | '^'
              | '<<' | '>>' | '&<<' | '&>>' | '&+' | '&-' | '&*' | '+|' | '-|' | '*|' | '!' | '~' ;   (* the fixed operator set.
                                                                   One parameter declares a prefix operator ('-', '!', '~'), two a binary one (05) *)
label         = identifier ;
task-decl     = 'task' 'func' identifier generic-params? param-clause
                ('with' '(' identifier ':' 'mutable' type ')')? throws-clause? ('->' type)? where-clause? block ;
                                                                   (* one resume parameter (07) *)
param-clause  = '(' (param (',' param)* ','?)? ')' ;
param         = (arg-label | '_')? identifier ':' param-convention? type ('=' expression)? ;
arg-label     = identifier | keyword ;                            (* func index(of x: T, in s: Span<T>) *)
param-convention = 'mutable' | 'owned' ;                           (* none: borrowed, or owned for a mutating or consuming function type, some F of one, or mutable any P (05) *)
throws-clause = 'throws' | typed-throws ;                          (* bare 'throws' only on a non-public function with a body (10) *)
typed-throws  = 'throws' '(' type ('|' type)* ')' ;                (* throws(IoError | ParseError): an error union (10) *)

struct-decl   = 'struct' identifier generic-params? primary-init? inheritance? where-clause? ('{' member* '}')? ;
                (* a struct's body declares no stored field: its 'var's are computed or static, and its 'let's static (04) *)
primary-init  = (modifier* 'init')? '(' (field (',' field)* ','?)? ')' ;   (* the stored fields, in layout order: struct Fraction private init(let num: Int, let den: Int) *)
field         = attribute* modifier* ('var' | 'let') identifier (':' type)? ('=' expression)?   (* a type, a default, or both *)
              | field-static-if
              | 'static' 'for' identifier 'in' expression ('where' expression)? '{' fields? '}'
              | static-error ;
field-static-if = 'static' 'if' expression '{' fields? '}' ('else' (field-static-if | '{' fields? '}'))? ;
fields        = field (',' field)* ','? ;
union-decl    = 'union' identifier generic-params? inheritance? where-clause? '{' member* '}' ;   (* stored members overlap (04) *)
enum-decl     = 'enum' identifier generic-params? inheritance? where-clause? '{' (enum-case | member)* '}' ;
enum-case     = attribute* 'case' case-item (',' case-item)* ;
case-item     = identifier ('(' tuple-type-elems ')' | '=' expression)? ;   (* a raw value only in an enum without payloads (04) *)
protocol-decl = 'protocol' identifier inheritance? where-clause? '{' protocol-member* '}' ;   (* 'unsafe protocol P': every conformance is ': unsafe P' (05) *)
protocol-member = 'associatedtype' identifier inheritance? ('=' type)?
              | attribute* modifier* 'func' func-name generic-params? param-clause typed-throws? ('->' type)? where-clause?
              | attribute* modifier* 'var' identifier ':' type where-clause? '{' ('get' 'set'? | 'read' 'modify'?) '}'
              | attribute* modifier* 'subscript' param-clause '->' type where-clause? '{' ('get' 'set'? | 'read' 'modify'?) '}'
              | attribute* modifier* 'init' '?'? generic-params? param-clause typed-throws? where-clause? ;   (* static var version: Int { get }; @converts init(_ e: owned IoError) *)
extension-decl= 'extension' type inheritance? where-clause? '{' member* '}' ;
                                                                   (* no stored member or enum case, directly or generated, and a deinit
                                                                      only in an unconditional extension, in the type's module (04);
                                                                      a conformance only at a file's top level (05) *)
typealias-decl= 'typealias' identifier generic-params? '=' type ;
extern-c-decl = 'extern' 'c' ( plain-string-lit | 'noalloc'? c-stack? 'func' identifier param-clause ('->' type)? ) ;
c-stack       = 'stack' '(' expression ')' ;                        (* the stack, in bytes, the C function needs at most: a const Int expression (08) *)

member        = declaration | init-decl | deinit-decl | subscript-decl | static-if-decl | static-for-decl | static-error ;
init-decl     = attribute* modifier* 'init' '?'? generic-params? param-clause throws-clause? where-clause? block ;
deinit-decl   = attribute* 'deinit' block ;                         (* '@noalloc' is the attribute with a meaning here (06) *)
subscript-decl= attribute* modifier* 'subscript' param-clause '->' type where-clause? accessor-block ;
accessor-block= '{' ( statement* | accessor+ ) '}' ;              (* 'get', 'set', 'read' or 'modify' first, after attributes and modifiers, then '{', begins an accessor, never a call *)
accessor      = attribute* modifier* ('get' | 'set' | 'read' | 'modify') block ;   (* the accessors are 'get', 'get set', 'read' or 'read modify' (02); unsafe get { … } *)

inheritance   = ':' conformance (',' conformance)* ;
conformance   = 'unsafe'? type                                    (* struct Queue<T>(…): unsafe Synchronized: an unverified promise *)
              | '~' type ;                                        (* only ~Copyable and ~Sendable: opt out of the derived conformance (01, 07) *)
generic-params= '<' generic-param (',' generic-param)* ','? '>' ;
generic-param = identifier (':' constraint ('&' constraint)*)? | 'let' identifier ':' type ;   (* value parameter: Simd<Float, 4> *)
where-clause  = 'where' requirement (',' requirement)* ;
requirement   = type ':' constraint ('&' constraint)* | type ('==' | '!=') type   (* where A != B: two distinct types *)
              | borrows-item ;
borrows-item  = subject ('borrows' | 'outlives') source ;          (* where return borrows self, out borrows text (02) *)
subject       = 'return' ('.' field-step)* | 'yield' | ('self' | identifier) ('.' field-step)* ;   (* return.name: a stored field of the result; 'self' only where it absorbs under rule 4 (02) *)
source        = 'static' | ('self' | identifier) ('.' field-step)* ;   (* 'static' only after 'borrows'; a path of stored fields *)
field-step    = identifier | int-literal ;                         (* a stored field, or a tuple element: return.0 *)
constraint    = type | '~' type ;                                 (* only ~Scoped: T isn't scoped (02) *)

static-if-decl= 'static' 'if' expression '{' (enum-case | member)* '}' ('else' (static-if-decl | '{' (enum-case | member)* '}'))? ;
static-for-decl= 'static' 'for' identifier 'in' expression ('where' expression)? '{' (enum-case | member)* '}' ;
                                                                   (* generates members (09); enum-case only in an enum's own body *)
```

A computed name, `\(expression)`, may stand for an identifier only where a declaration is named (a type, function, variable, constant, enum case, or a parameter's name, never its argument label), after `.` in a member access or an implicit member expression, and as a primary expression that names a declaration in scope, such as a generated function it calls. Anywhere else, such as a type annotation, a pattern or an argument label, it is an error. Inside a string literal, `\(` keeps its meaning of interpolation.

## Types

```ebnf
type          = type-primary type-suffix* ;
type-primary  = type-name
              | 'Self' ('.' identifier generic-args?)*             (* Self, Self.Element *)
              | '(' tuple-type-elems? ')'                          (* tuple, or Void when empty *)
              | '(' type ('|' type)+ ')'                           (* error union (10): (IoError | ParseError)? *)
              | '[' (expression | '_') 'of' type ']'               (* Array<T, N>, the inline array; '_' infers the count from the initializer *)
              | '*' type-primary                                   (* raw pointer; *T? is a nullable pointer, *(T?) a pointer to an optional *)
              | 'any' composition | 'some' composition | 'mutable' 'any' composition   (* mutable any P: the exclusive existential view *)
              | '@c' 'noalloc'? c-stack? '(' (fn-param-type (',' fn-param-type)* ','?)? ')' '->' type
                                                                   (* C function pointer (08): never throws; 'noalloc': its calls allocate nothing (05) *)
              | 'unsafe'? ('mutating' | 'consuming')? '@sendable'? '@noalloc'? '(' (fn-param-type (',' fn-param-type)* ','?)? ')' typed-throws? '->' type ;
                                                                   (* function type; 'unsafe' calls need 'unsafe' (05);
                                                                      'mutating' may write its captures, 'consuming' is call-once;
                                                                      '@sendable' holds only closures with Sendable captures (07);
                                                                      '@noalloc' holds only functions whose calls can't allocate (05) *)
composition   = type-primary ('&' type-primary)* ;                 (* any P & Sendable; any P? is (any P)?; after a cast operator, the type takes every '&' that follows *)
type-name     = identifier generic-args? ('.' identifier generic-args?)* ;   (* Enemy, gameplay.Enemy, T.Element, List<gameplay.Enemy> *)
fn-param-type = 'keep'? param-convention? type ('|' type)* ;      (* some (mutable Context) -> Bool; mutating (keep StringView) -> Void; (IoError | ParseError) -> Void;
                                                                     'keep' only without a convention or with 'owned' (05) *)
type-suffix   = '?' ;                                              (* '*' binds to the name, '?' applies after *)
generic-args  = '<' generic-arg (',' generic-arg)* ','? '>' ;
generic-arg   = type | expression | '_' ;                          (* '_' only in a declaration's annotation or after 'as': filled from the initializer, as in List<_> (04) *)
tuple-type-elems = (identifier ':')? type (',' (identifier ':')? type)* ','? ;   (* (Int,) is a one-element tuple; (Int) is Int *)
```

## Statements

```ebnf
block         = '{' statement* '}' ;
statement     = declaration | expression | assignment | guard-stmt
              | for-stmt | while-stmt | repeat-stmt | do-stmt                (* 'if' and 'when' are expressions *)
              | 'return' expression? | 'throw' expression | 'break' label? | 'continue' label?
              | 'defer' block | 'unsafe' block | 'unchecked' block | using-stmt
              | attribute+ do-stmt                                      (* only @checks(…) applies to a block (10) *)
              | rebind-stmt | static-if-stmt | static-for-stmt | yield-stmt
              | 'discard' 'self'                                        (* only in a consuming method of the type's own module (01) *)
              | static-error
              | label ':' (for-stmt | while-stmt | repeat-stmt) ;
yield-stmt    = 'yield' ( yield-operand | '(' yield-operand (',' yield-operand)+ ','? ')' ) ;   (* yield (&a, &b): a tuple of places *)
yield-operand = '&'? expression ;

assignment    = expression assign-op expression ;
assign-op     = '=' | '+=' | '-=' | '*=' | '/=' | '%=' | '&=' | '|=' | '^=' | '<<=' | '>>=' | '&+=' | '&-=' | '&*=' | '+|=' | '-|=' | '*|=' | '&<<=' | '&>>=' ;
                                                                   (* a ⊕= b is a = a ⊕ b, with a's place worked out once (05) *)
rebind-stmt   = 'rebind' identifier 'to' expression ;                   (* rebind cur to &cur.children[i].value: '&' first for a var (02) *)

if-expr       = 'if' condition (',' condition)* block ('else' (if-expr | block))? ;   (* has a value only with 'else' (04) *)
guard-stmt    = 'guard' condition (',' condition)* 'else' block ;
condition     = expression
              | 'owned'? ('let' | 'var') pattern ('=' expression)?     (* '=' may be omitted only in 'if let x' and 'guard let x', short for '= x' *)
              | 'case' pattern '=' expression ;
when-expr     = 'when' expression? '{' when-arm+ '}' ;
when-arm      = (pattern (',' pattern)* ('where' expression)? | 'else') '->' arm-body ;
                                                                   (* with no subject, an arm's test is one Bool expression, with no ',' list and no 'where' *)
arm-body      = block | expression | assignment                     (* an assignment's value is Void *)
              | 'return' expression? | 'throw' expression | 'break' label? | 'continue' label? ;
                                                                   (* arms are separated as statements are: by newlines, or ';' on one line *)
for-stmt      = 'for' pattern 'in' expression ('where' expression)? block ;
                                                                   (* 'for var x in &s' changes elements only over '&s' (04); a for pattern has no top-level 'let' and no 'owned' part *)
while-stmt    = 'while' condition (',' condition)* block ;
repeat-stmt   = 'repeat' block 'while' expression ;
do-stmt       = 'do' block catch-clause* ;
catch-clause  = 'catch' pattern? ('where' expression)? block ;

using-stmt    = 'using' 'allocator' '=' expression block ;
static-if-stmt  = 'static' 'if' expression block ('else' (static-if-stmt | block))? ;
static-for-stmt = 'static' 'for' identifier 'in' expression ('where' expression)? block ;
```

## Expressions

Precedence from lowest to highest. Binary operators are left-associative, except `??` and `->` in types, which are right-associative.

| Level | Operators |
| --- | --- |
| 1 | `??` |
| 2 | `\|\|` |
| 3 | `&&` |
| 4 | `== != < <= > >= as` |
| 5 | `..< ...` |
| 6 | `+ - &+ &- +\| -\| \| ^` |
| 7 | `* / % &* *\| & << >> &<< &>>` |
| 8 | prefix `- ! ~ & ..< ... try try? try! await consume copy unsafe` |
| 9 | postfix `?` `!` `...` `.member` `(args)` `[index]` `{trailing-closure}` |

```ebnf
expression    = operand (binary-op operand | cast-op type)* ;
operand       = prefix-op* postfix-expr ;
binary-op     = '??' | '||' | '&&' | '==' | '!=' | '<' | '<=' | '>' | '>=' | '..<' | '...'
              | '+' | '-' | '&+' | '&-' | '+|' | '-|' | '|' | '^' | '*' | '/' | '%' | '&*' | '*|' | '&' | '<<' | '>>' | '&<<' | '&>>' ;   (* levels in the table above *)
cast-op       = 'as' ;                                             (* level 4; the right-hand side is a type, not an expression (05) *)
literal       = int-literal | float-literal | string-lit | 'true' | 'false' ;
prefix-op     = '-' | '!' | '~' | '&' | '..<' | '...' | 'try' | 'try?' | 'try!' | 'await' | 'consume' | 'copy' | 'unsafe' ;
postfix-expr  = primary postfix* ;
postfix       = '.' (identifier generic-args? | keyword | int-literal)  (* keywords allowed after '.': T.self, .init(…); gameplay.Box<Int>(x) *)
              | '?' | '!' | '...' | call-suffix | '[' argument-list ']' ;
call-suffix   = '(' argument-list? ')' trailing-closure* | trailing-closure+ ;
argument-list = argument (',' argument)* ','? ;
argument      = (arg-label ':')? ('&'? expression | operator) ;      (* combine: + passes the operator as a function value *)
primary       = identifier generic-args? | literal | 'self' | 'Self' | 'nil'
              | '(' operator ')'                                    (* operator as a function value: (+), (<) *)
              | '.' (identifier | keyword)                          (* implicit member: .zero, .opening, .init *)
              | '(' ')'                                             (* the empty tuple: Void's one value *)
              | '(' (identifier ':')? expression (',' (identifier ':')? expression)* ','? ')'   (* grouping or tuple; labels as in (hp: 100, armor: 20); (x,) is a one-element tuple *)
              | '(' (tuple-type-elems | type ('|' type)+) ')' '.' (identifier | keyword)   (* a type that isn't a name, then a member: (Int, Float).self; see Notes *)
              | '[' (expression (',' expression)* ','?)? ']'        (* array literal: an Array, or a type that conforms to ExpressibleByArrayLiteral (04) *)
              | '[' (':' | expression ':' expression (',' expression ':' expression)* ','?) ']'   (* dictionary literal; [:] is empty *)
              | closure | unsafe-block-expr | if-expr | when-expr ;
unsafe-block-expr = 'unsafe' '{' statement* expression '}' ;       (* value is the final expression *)
closure       = '{' closure-sig? statement* '}' ;
closure-sig   = capture-list? ('static'? closure-params)? ('->' type)? 'in' ;   (* at least one part before 'in' *)
closure-params= identifier (',' identifier)* | param-clause ;
                (* { [move input] in … } has captures only; 'static' marks a static closure,
                   whose body is instantiated per compile-time argument, as in T.construct; a closure
                   passed to a compile-time list's filter or map is instantiated per element unmarked *)
capture-list  = '[' capture (',' capture)* ','? ']' ;
capture       = ('move' | 'copy') (identifier | 'self') ;          (* 'move self' only in a consuming method (05) *)
trailing-closure = closure ;
```

## Patterns

```ebnf
pattern       = '_' | identifier | tuple-pattern | enum-pattern | expression-pattern
              | 'owned'? ('let' | 'var') pattern | 'is' type | 'let' identifier 'as' type ;   (* for (h, var e) in … *)
tuple-pattern = '(' pattern (',' pattern)* ','? ')' ;
enum-pattern  = type? '.' identifier ('(' (identifier ':')? pattern (',' (identifier ':')? pattern)* ','? ')')? ;
expression-pattern = expression ;                                  (* 0..<10 ->, maxHp ->, "jump" -> *)
```

- **A bare identifier** in a `when` arm, an `if case`, `guard case` or `while case`, or a `catch` pattern that isn't under `let` or `var` is an expression pattern. Under a binding kind, and in `for`, `let` and `var` patterns, which must always match ([04](04-types.md#matching-with-when-and-choosing-with-if)), it binds a new name.
- **`.name` and `T.name` in a pattern** are enum patterns. Where the subject's type, or `T`, has no case `name`, `.name` or `T.name` without a payload is an expression pattern of that member, compared with `==`, as `Int.max ->` is.
- **`as` in a pattern.** `let e as E` is always a type pattern, and a cast inside an expression pattern is parenthesized: `(0 as Int32) -> …`.

## Notes

### Blocks and closure literals

**A closure literal is never a statement.** A `{` at the start of a statement begins a closure literal, and one used as a whole statement, which would never run, is a compile error; `do { … }` groups statements:

```swift
{ reset() }         // error: this closure would never run
do { reset() }      // groups statements, and runs them
```

**A `{` right after a `when` arm's `->` begins a block**, as the `{` after an `if` condition, an `else` or a `when` subject does, and the block's value is its last expression ([04](04-types.md#matching-with-when-and-choosing-with-if)). An arm whose value is a closure writes it in parentheses: `.retry -> ({ attempt() })`. A `{` right after `when` begins its body, so that `when` has no subject; a subject that is a closure literal is written in parentheses, `when ({ … }) { … }`.

**A block's last expression can't start with `.` on a line of its own**, since that line joins the one above (the newline rules at the top of this chapter): in `if open { playSound()` followed by `.open }` on the next line, the value would be `playSound().open`. An implicit member on a line of its own as a block's value is written in parentheses: `(.open)`.

**No trailing closures in condition positions.** In any expression that a statement's block follows, a `{` always starts the block, never a trailing closure. To pass a closure there, parenthesize the call:

```swift
for x in items.filter { $0.alive } { use(x) }     // error: '{ $0.alive }' is read as the loop's body
for x in items.filter({ $0.alive }) { use(x) }   // the closure is inside the call's parentheses
```

- Those expressions are the ones after `if`, `while`, `when`, `for … in`, `using … =`, `static if` and `static for … in`, and the patterns after `catch`. A `guard`'s conditions are followed by `else`, so closures work there as usual.
- So is every `where` clause that precedes a block: `for … where`, `static for … where`, `catch … where`, and the `where` of a declaration.
- A `when` arm's tests and `where` guard are followed by `->`, so closures work there as usual.

**`unsafe` before `{`** in expression position is an `unsafe-block-expr`, not `unsafe` applied to a closure literal, which is written `unsafe ({ … })`. As a statement, `unsafe { … }` is an ordinary unsafe block.

### Operators and punctuation

**The range operators, and `?`.** Rayo has no ternary operator, so a `?` after an operand is always postfix optional chaining. Whitespace separates prefix `..<x` and postfix `x...` from the binary range operators. Between two operands, with whitespace on both sides or on neither, as in `0..<n`, a range operator is binary. Attached to an operand on one side only, it is prefix or postfix, whatever is on its other side, whitespace, a bracket or punctuation, as in `xs[3...]` and `xs[..<n]`.

```swift
let hp = copy target?.hp                     // optional chaining
let tail = xs[3...]                          // postfix: attached to 3, and closed by ']'
```

**The `&` prefix** marks a place lent for change, and is valid only in the positions [01](01-values-and-ownership.md#bindings) lists, such as a `mutable` argument, a binding, pattern or loop sequence that lends a place, and an `if` or `when` arm's value that stands in one.

**Operators as values.** A bare operator is allowed only as a whole argument (`reduce(0, +)`). Elsewhere it's written parenthesized, `(+)`. The overload is chosen by the expected function type, using the bounded lookup of [05](05-protocols-generics-and-closures.md#operators).

```swift
let total = counts.reduce(0, +)         // a bare operator as a whole argument
let add: (Int, Int) -> Int = (+)        // anywhere else, in parentheses
```

**Generic arguments and `<`.** `<` both compares and opens generic arguments, and the parser tells the two apart without knowing what any name means. In expression position, `identifier <` starts generic arguments only if the tokens up to the matching `>` parse as `generic-args`, and the token after `>` is one of `(`, `.`, `)`, `]`, `,`, `:`, `;`, `?`, `!`, `{`, a newline, or an operator that can't begin an operand, `==`, `!=`, `&&`, `||` or `??`, as in `static if T == List<Int> || T == Set<Int>`. Otherwise `<` is the comparison operator.

```swift
let xs = List<Int>()          // '<Int>' parses as generic arguments, and '(' follows
if a < b, c > d { … }         // two comparisons: 'd' can't follow generic arguments
f(a < b, c > (d))             // a generic call 'a<b, c>(d)': written '(c > d)', it is two comparisons
```

- While generic arguments are being parsed, in a type or after an `identifier <` that starts them, a `>>`, `>>=` or `>=` token is split into `>` followed by the rest, so `var b: Box<Int>= a` declares a `Box<Int>`. So `SpscQueue<Shared<Snapshot>>(capacity: 3)` closes two argument lists.

### Parentheses and conventions in types

In a type, `(` can open a function type's parameters, an error union, a tuple, or a single parenthesized type. Before a type, `mutable` can be a parameter convention or part of the type.

**Parenthesized types.** Every `(` in a type is decided with the same bounded lookahead as generic arguments ([above](#operators-and-punctuation)). When the matching `)` is followed by `throws` or `->`, the list is a function type's parameters, and `(IoError | ParseError) -> Void` takes one union parameter, except in a `when` arm's patterns, where the first `->` outside brackets is the arm's arrow, so `let x as (A | B) -> …` binds an error union. Otherwise `(A | B)` is an error union and `(A, B)` a tuple. A parenthesized single type without a label or a trailing comma is that type, not a one-element tuple, except that `(any P)` after `mutable` or as the type argument of `Box` or an object pointer keeps the shared view apart from the form `any` makes there (below).

```swift
typealias OnError = (IoError | ParseError) -> Void    // ')' then '->': one error-union parameter
typealias Failure = (IoError | ParseError)            // an error union
typealias Hit = (target: Handle<Enemy>, damage: Float) // a tuple
typealias Count = (Int)                               // just Int, not a one-element tuple
typealias Single = (Int,)                             // a one-element tuple
```

**`mutable any`.** In a parameter's type, `mutable` directly followed by `any` is always the exclusive existential view type ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)). The `mutable` convention on a shared existential view is written `mutable (any P)`:

```swift
func strike(_ d: mutable any Damageable) { ... }        // the exclusive existential view type
func retarget(_ d: mutable (any Damageable)) { ... }    // the mutable convention on a shared existential view
```

**A type in an expression.** An expression names a type by a type name followed by a member, as in `Vertex.self`, `T.fields` and `Int.max`, or as an operand of `==` or `!=` that compares types, as in `T == List<Int>` ([05](05-protocols-generics-and-closures.md#protocols-and-generics)). Any other type is parenthesized there: `(Int, Float).self`, `(*Int).size`. A `(` in expression position begins such a type when what it holds starts as only a type can, with `*`, `any`, `some`, `mutable any`, `@c` or `[ … of`, or when the matching `)` is followed by `.self`. Any other such type is named through a `typealias` first: after `typealias Pair = (Int, Float)`, `Pair.construct { … }` is an expression.

**Unscoped existentials.** In the type argument of `Box` or an object pointer, `any` right after `<` makes the unscoped existential ([05](05-protocols-generics-and-closures.md#any-p-explicit-dynamic-dispatch)). Parenthesized, `Box<(any P)>` is a box holding a shared existential view.

### Trailing commas

**Trailing commas** are allowed in every comma-separated list closed by `)`, `]` or `>`, as the productions show.