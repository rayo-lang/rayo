# Types, statements, expressions and patterns

[12 · Grammar](../12-grammar.md)

Within a declaration, the grammar describes the types, statements, expressions and patterns that make up its body. The productions below give their syntax; the earlier chapters give them meaning.

## Types

```ebnf
type          = result-base ('!' failure-type)? ;                 (* Mesh!LoadError is Result<Mesh, LoadError>; Level!(IoError | ParseError) (10) *)
result-base   = type-primary type-suffix* ;                        (* '!' applies after '?': Handle<Enemy>?!LoadError; (Mesh!LoadError)? is an optional Result *)
failure-type  = type-name | '(' type ('|' type)* ')' ;             (* a name, or a parenthesized type or error union *)
type-primary  = type-name
              | 'Self' ('.' identifier generic-args?)*             (* Self, Self.Element *)
              | '(' tuple-type-elems? ')'                          (* tuple, or Void when empty *)
              | '(' type ('|' type)+ ')'                           (* error union (10): (IoError | ParseError)? *)
              | '[' (expression | '_') 'of' type ']'               (* Array<T, N>, the inline array; '_' infers the count from the initializer *)
              | '*' type-primary                                   (* raw pointer; *T? is a nullable pointer, *(T?) a pointer to an optional *)
              | 'static' type-name                                 (* a static view (09): static StringView, static Span<T>, and no other type;
                                                                      static Span<T>? is an optional static view *)
              | 'any' composition | 'some' composition | 'mutable' 'any' composition   (* mutable any P: the exclusive existential view *)
              | '@c' 'noalloc'? c-stack? '(' (fn-param-type (',' fn-param-type)* ','?)? ')' '->' type
                                                                   (* C function pointer (08); 'noalloc': its calls allocate nothing (05) *)
              | 'unsafe'? ('mutating' | 'consuming')? '@sendable'? '@noalloc'? '(' (fn-param-type (',' fn-param-type)* ','?)? ')' '->' type ;
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
              | 'defer' block | 'unsafe' block | 'unchecked' block
              | attribute+ do-stmt                                      (* only @checks(…) applies to a block (10) *)
              | rebind-stmt | static-if-stmt | static-for-stmt
              | 'discard' 'self'                                        (* only in a consuming method of the type's own module (01) *)
              | '_' '=' expression                                      (* drops a value on purpose, which an unused one would otherwise make an error (05) *)
              | static-error
              | label ':' (for-stmt | while-stmt | repeat-stmt) ;

assignment    = expression assign-op expression ;
assign-op     = '=' | '+=' | '-=' | '*=' | '/=' | '%=' | '&=' | '|=' | '^=' | '<<=' | '>>=' | '&+=' | '&-=' | '&*=' | '+|=' | '-|=' | '*|=' | '&<<=' | '&>>=' ;
                                                                   (* a ⊕= b is a = a ⊕ b, with a's place worked out once (05) *)
rebind-stmt   = 'rebind' identifier 'to' expression ;                   (* rebind cur to &cur.children[i].value: '&' first for a var, 'borrow' for a let (02) *)

if-expr       = 'if' condition (',' condition)* block ('else' (if-expr | block))? ;   (* has a value only with 'else' (04) *)
guard-stmt    = 'guard' condition (',' condition)* 'else' block ;
condition     = expression
              | 'owned'? ('let' | 'var') pattern '=' expression        (* the pattern binds a new name; 'let x = x' is an error: write 'let x' (01) *)
              | ('let' | 'var') identifier                             (* no '=': 'if let x' is 'if let x = x', 'if var x' is 'if var x = &x' (01) *)
              | 'case' pattern '=' expression ;
when-expr     = 'when' expression? '{' when-arm+ '}' ;
when-arm      = (pattern (',' pattern)* ('where' expression)? | 'else') block ;
                                                                   (* with no subject, an arm's test is one Bool expression, with no ',' list and no 'where' *)
                                                                   (* an arm ends with its block's '}', so arms need no separator *)
for-stmt      = 'for' pattern 'in' expression ('where' expression)? block ;
                                                                   (* 'for x in &s' changes elements in place (04); a for pattern has no 'let', no 'owned' part, and 'var' only on a part that owns its value *)
while-stmt    = 'while' condition (',' condition)* block ;
repeat-stmt   = 'repeat' block 'while' expression ;
do-stmt       = 'do' block catch-clause* ;
catch-clause  = 'catch' pattern? ('where' expression)? block ;

static-if-stmt  = 'static' 'if' expression block ('else' (static-if-stmt | block))? ;
static-for-stmt = 'static' 'for' identifier 'in' expression ('where' expression)? block ;
```

## Expressions

**The table lists precedence levels from lowest to highest.** Binary operators are left-associative, except `??` and `->` in types, which are right-associative.

| Level | Operators |
| --- | --- |
| 1 | `??` |
| 2 | `\|\|` |
| 3 | `&&` |
| 4 | `== != < <= > >= as` |
| 5 | `..< ...` |
| 6 | `+ - &+ &- +\| -\| \| ^` |
| 7 | `* / % &* *\| & << >> &<< &>>` |
| 8 | prefix `- ! ~ & ..< ... try try? try! await consume copy borrow unsafe`, then `alloc` and `a.alloc` |
| 9 | postfix `?` `!` `...` `.member` `(args)` `[index]` `{trailing-closure}` |

```ebnf
expression    = operand (binary-op operand | cast-op type)* ;
operand       = prefix-op* allocation? postfix-expr ;
allocation    = (postfix-expr '.')? 'alloc' ;                     (* alloc List<Int>(), level.alloc Box(v), try alloc x.clone(), alloc [1, 2]:
                                                                     the allocator, then what is allocated with it (06) *)
binary-op     = '??' | '||' | '&&' | '==' | '!=' | '<' | '<=' | '>' | '>=' | '..<' | '...'
              | '+' | '-' | '&+' | '&-' | '+|' | '-|' | '|' | '^' | '*' | '/' | '%' | '&*' | '*|' | '&' | '<<' | '>>' | '&<<' | '&>>' ;   (* levels in the table above *)
cast-op       = 'as' ;                                             (* level 4; the right-hand side is a type, not an expression (05) *)
literal       = int-literal | float-literal | string-lit | 'true' | 'false' ;
prefix-op     = '-' | '!' | '~' | '&' | '..<' | '...' | 'try' | 'try?' | 'try!' | 'await' | 'consume' | 'copy' | 'borrow' | 'unsafe' ;
                                                                   (* 'borrow' only where a declaration borrows (01) *)
postfix-expr  = primary postfix* ;
postfix       = '.' (identifier generic-args? | keyword | int-literal)  (* keywords other than 'alloc' allowed after '.': T.self, .init(…); alloc gameplay.Box<Int>(x) *)
              | '?' | '!' | '...' | call-suffix | '[' argument-list ']' ;
call-suffix   = '(' argument-list? ')' trailing-closures? | trailing-closures ;
trailing-closures = trailing-closure (identifier ':' trailing-closure)* ;   (* catchPanic { … } recover: { … }; labels are identifiers *)
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
closure-sig   = capture-list? ('static'? closure-params)? ('->' result-type)? 'in' ;   (* at least one part before 'in' *)
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
              | 'owned'? ('let' | 'var') pattern | 'is' type | 'let' identifier 'as' type ;   (* .circle(var r), .moveTo(let p); each 'let' or 'var' binds a name, so 'let _' and 'let _ as E' are errors (01) *)
tuple-pattern = '(' pattern (',' pattern)* ','? ')' ;
enum-pattern  = type? '.' identifier ('(' (identifier ':')? pattern (',' (identifier ':')? pattern)* ','? ')')? ;
expression-pattern = expression ;                                  (* 0..<10, maxHp, "jump" *)
```

**Three forms in a pattern have two readings each, and these rules choose between them:**

- **A bare identifier** in a `when` arm, an `if case`, `guard case` or `while case`, or a `catch` pattern that isn't under `let` or `var` is an expression pattern, which compares with an existing value. Under a binding kind, and in `for`, `let` and `var` patterns, which must always match ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)), it binds a new name.
- **`.name` and `T.name` in a pattern** are enum patterns. Where the subject's type, or `T`, has no case `name`, `.name` or `T.name` without a payload is an expression pattern of that member, compared with `==`, as `Int.max` is.
- **`as` in a pattern.** `let e as E` is always a type pattern, and a cast inside an expression pattern is parenthesized: `(0 as Int32) { … }`.
