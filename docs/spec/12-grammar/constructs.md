# Types, statements, expressions and patterns

[12 · Grammar](../12-grammar.md)

Within a declaration, the grammar describes the types, statements, expressions and patterns that make up its body. The productions below give their syntax; the earlier chapters give them meaning.

## Types

```ebnf
type          = result-base ('!' failure-type)? ;                 (* Mesh!LoadError is Result<Mesh, LoadError>; Level!(IoError | ParseError) (10) *)
result-base   = type-primary type-suffix* ;                        (* '!' applies after '?': Handle<Enemy>?!LoadError; (Mesh!LoadError)? is an optional Result;
                                                                      &Mesh!LoadError is a Result whose success value is a &Mesh *)
failure-type  = type-name | '(' type ('|' type)* ')' ;             (* a name, or a parenthesized type or error union *)
type-primary  = type-name
              | 'Self' ('.' identifier generic-args?)*             (* Self, Self.Element *)
              | '(' tuple-type-elems? ')'                          (* tuple, or Void when empty *)
              | '(' type ('|' type)+ ')'                           (* error union (10): (IoError | ParseError)? *)
              | ref-type
              | '[' type ']'                                       (* a run of elements, an unsized type (01): &[Float] *)
              | '[' (expression | '_') 'of' type ']'               (* Array<T, N>, the inline array; '_' infers the count from the initializer *)
              | '*' type-primary                                   (* raw pointer; *T? is a nullable pointer, *(T?) a pointer to an optional *)
              | 'static' type-primary                              (* a static type (02): static &Text, static Token, static &any Logger;
                                                                      (static &[Float])? is an optional static reference *)
              | 'any' composition | 'some' composition
ref-type      = 'mutable'? '&' type-primary type-suffix* ;         (* a reference (01): &Enemy, mutable &[Float], &any Drawable;
                                                                      '?' binds tighter than '&', so &T? refers to an optional, and (&T)? is an optional reference *)
              | '@c' 'noalloc'? c-stack? '(' (fn-param-type (',' fn-param-type)* ','?)? ')' '->' type
                                                                   (* C function pointer (08); 'noalloc': its calls allocate nothing (05) *)
              | 'unsafe'? ('mutating' | 'consuming')? '@sendable'? '@noalloc'? '(' (fn-param-type (',' fn-param-type)* ','?)? ')' '->' type ;
                                                                   (* function type; 'unsafe' calls need 'unsafe' (05);
                                                                      'mutating' may write its captures, 'consuming' is call-once;
                                                                      '@sendable' holds only closures with Sendable captures (07);
                                                                      '@noalloc' holds only functions whose calls can't allocate (05) *)
composition   = type-primary ('&' type-primary)* ;                 (* any P & Sendable; any P? is (any P)?; &any P & Sendable is &(any P & Sendable);
                                                                      after a cast operator, the type takes every '&' that follows *)
type-name     = identifier generic-args? ('.' identifier generic-args?)* ;   (* Enemy, gameplay.Enemy, T.Element, List<gameplay.Enemy>, Text *)
fn-param-type = 'keep'? type ('|' type)* ;                         (* some (mutable &Context) -> Bool; mutating (keep &Text) -> Void; (IoError | ParseError) -> Void;
                                                                     'keep' only on a T or &T parameter, never a mutable &T one (05) *)
type-suffix   = '?' ;                                              (* '*' binds to the name, '?' applies after *)
generic-args  = '<' generic-arg (',' generic-arg)* ','? '>' ;
generic-arg   = type | expression | '_' ;                          (* '_' only in a declaration's annotation or after 'as': filled from the initializer, as in List<_> (04) *)
tuple-type-elems = (identifier ':')? type (',' (identifier ':')? type)* ','? ;   (* (Int,) is a one-element tuple; (Int) is Int *)
```

## Statements

```ebnf
block         = '{' statement* '}' ;
statement     = declaration | ref-decl | expression | assignment | guard-stmt
              | for-stmt | while-stmt | repeat-stmt | do-stmt                (* 'if' and 'when' are expressions *)
              | 'return' expression? | 'throw' expression | 'break' label? | 'continue' label?
              | 'defer' block | 'unsafe' block | 'unchecked' block
              | attribute+ do-stmt                                      (* only @checks(…) applies to a block (10) *)
              | rebind-stmt | static-if-stmt | static-for-stmt
              | 'discard' 'self'                                        (* only in a consuming method of the type's own module (01) *)
              | '_' '=' expression                                      (* drops a value on purpose, which an unused one would otherwise make an error (05) *)
              | static-error
              | label ':' (for-stmt | while-stmt | repeat-stmt) ;

assignment    = expression assign-op expression ;                (* an optional chain on the left ends in '.member' or '[index]': 'x? = v' is an error (04) *)
assign-op     = '=' | '+=' | '-=' | '*=' | '/=' | '%=' | '&=' | '|=' | '^=' | '<<=' | '>>=' | '&+=' | '&-=' | '&*=' | '+|=' | '-|=' | '*|=' | '&<<=' | '&>>=' ;
                                                                   (* a ⊕= b is a = a ⊕ b, with a's place worked out once (05) *)
rebind-stmt   = 'rebind' identifier 'to' expression ;                   (* rebind cur to &cur.children[i].value: '&' first for a ref var, nothing for a ref let (02) *)

if-expr       = 'if' condition (',' condition)* block ('else' (if-expr | block))? ;   (* has a value only with 'else' (04) *)
guard-stmt    = 'guard' condition (',' condition)* 'else' block ;
condition     = expression                                         (* a Bool test *)
              | ('let' | 'var' | 'ref' 'let' | 'ref' 'var') pattern '=' expression ;
                                                                   (* an optional binding: the expression is an optional, whose payload the pattern binds;
                                                                      each word means what it means in a declaration, so 'ref var' takes a mutable reference
                                                                      to an optional, such as 'mutable &p' (01) *)
when-expr     = 'when' expression? '{' when-arm+ '}' ;             (* 'when &s': payload names are ref lets of s's parts; 'when mutable &s': ref vars;
                                                                      'when consume s': they own them (01) *)
when-arm      = (match-pattern (',' match-pattern)* ('where' expression)? | 'else') block ;
                                                                   (* with no subject, an arm's test is one Bool expression, with no ',' list and no 'where' *)
                                                                   (* an arm ends with its block's '}', so arms need no separator *)
for-stmt      = 'for' pattern 'in' expression ('where' expression)? block ;
                                                                   (* 'for x in mutable &s' names each element for change (04); the subject says what each name is (01) *)
while-stmt    = 'while' condition (',' condition)* block ;
repeat-stmt   = 'repeat' block 'while' expression ;
do-stmt       = 'do' block catch-clause* ;
catch-clause  = 'catch' catch-pattern? ('where' expression)? block ;

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
| 8 | prefix `- ! ~ & ..< ... try try? try! await consume copy unsafe` and `mutable &`, then `alloc` and `a.alloc` |
| 9 | postfix `?` `!` `...` `.member` `(args)` `[index]` `{trailing-closure}` |

```ebnf
expression    = operand (binary-op operand | cast-op type)* ;
operand       = prefix-op* allocation? postfix-expr ;
allocation    = (postfix-expr '.')? 'alloc' ;                     (* alloc List<Int>(), level.alloc Box(v), try alloc x.clone(), alloc [1, 2], alloc "hp \(hp)":
                                                                     the allocator, then what is allocated with it (06) *)
binary-op     = '??' | '||' | '&&' | '==' | '!=' | '<' | '<=' | '>' | '>=' | '..<' | '...'
              | '+' | '-' | '&+' | '&-' | '+|' | '-|' | '|' | '^' | '*' | '/' | '%' | '&*' | '*|' | '&' | '<<' | '>>' | '&<<' | '&>>' ;   (* levels in the table above *)
cast-op       = 'as' ;                                             (* level 4; the right-hand side is a type, not an expression (05) *)
literal       = int-literal | float-literal | string-lit | 'true' | 'false' ;
prefix-op     = '-' | '!' | '~' | '&' | 'mutable' '&' | '..<' | '...' | 'try' | 'try?' | 'try!' | 'await' | 'consume' | 'copy' | 'unsafe' ;
                                                                   (* '&p' makes a shared reference, 'mutable &p' a mutable one (01) *)
postfix-expr  = primary postfix* ;
postfix       = '.' (identifier generic-args? | keyword | int-literal)  (* keywords other than 'alloc' allowed after '.': T.self, .init(…); alloc gameplay.Box<Int>(x) *)
              | '?' | '!' | '...' | call-suffix | '[' argument-list ']' ;
call-suffix   = '(' argument-list? ')' trailing-closures? | trailing-closures ;
trailing-closures = trailing-closure (identifier ':' trailing-closure)* ;   (* catchPanic { … } recover: { … }; labels are identifiers *)
argument-list = argument (',' argument)* ','? ;
argument      = (arg-label ':')? (expression | operator) ;         (* show(&boss), heal(mutable &boss); combine: + passes the operator as a function value *)
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
pattern       = '_' | identifier | tuple-pattern ;                 (* a declaration's, a condition's or a for loop's (01) *)
tuple-pattern = '(' pattern (',' pattern)* ','? ')' ;
match-pattern = enum-pattern | type-pattern | expression-pattern ;   (* a when arm's top level: it compares, or matches a case or a type *)
catch-pattern = identifier | enum-pattern | type-pattern ;         (* a catch clause's: a bare name binds the whole error (10) *)
enum-pattern  = type? '.' identifier ('(' payload-elem (',' payload-elem)* ','? ')')? ;
payload-elem  = (identifier ':')? payload-pattern ;
payload-pattern = '_' | identifier | literal | '-' (int-literal | float-literal) | 'nil' | enum-pattern | type-pattern
              | '(' payload-pattern (',' payload-pattern)* ','? ')' ;   (* inside a payload (04) *)
type-pattern  = 'is' type | identifier 'as' type ;                 (* is ParseError; e as ParseError binds e *)
expression-pattern = expression ;                                  (* 0..<10, maxHp, "jump" *)
```

**Each position in a pattern reads a bare identifier one way:**

- **In a declaration, a condition or a `for` loop** it binds a new name ([01](../01-values-and-ownership/bindings.md#conditions-and-patterns)).
- **At a `when` arm's top level** it is an expression pattern, except as the name of a type pattern ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)).
- **Inside an enum pattern's payload** it binds a new name ([04](../04-types/enums.md#matching-with-when-and-choosing-with-if)).
- **In a `catch` clause** it binds the whole error ([10](../10-errors-and-safety/typed-errors.md#handling-errors-with-do-and-catch)).

**Two forms need a rule to tell them from an expression:**

- **`.name` and `T.name` in a match pattern** are enum patterns. Where the subject's type, or `T`, has no case `name`, `.name` or `T.name` without a payload is an expression pattern of that member, compared with `==`, as `Int.max` is. Inside a payload, `.name` and `T.name` name a case.
- **`as` in a pattern.** `e as E` is always a type pattern, and a cast inside an expression pattern is parenthesized: `(0 as Int32) { … }`.
