# Files and declarations

[12 · Grammar](../12-grammar.md)

A source file consists of imports and declarations, including declarations selected or generated at compile time. These productions define how those file-level forms and the members of a type are written.

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
let-decl      = 'let' binding (',' binding)* ;                      (* let lo = 0, hi = 10 *)
var-decl      = 'var' binding (',' binding)* | 'var' identifier ':' type where-clause? accessor-block ;
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
primary-init  = (modifier* 'init')? '(' (field (',' field)* ','?)? ')' ;   (* the stored fields, in declaration order: struct Fraction private init(let num: Int, let den: Int) *)
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

**A computed name, `\(expression)`, lets generated code name declarations with a `const` string** ([09](../09-compile-time/declaration-generation.md#computed-names)). It may stand for an identifier only in these places:

- where a declaration is named: a type, function, variable, constant or enum case, or a parameter's name, never its argument label;
- after `.` in a member access or an implicit member expression;
- as a primary expression that names a declaration in scope, such as a generated function it calls.

**Anywhere else, such as a type annotation, a pattern or an argument label, a computed name is an error.** Inside a string literal, `\(` keeps its meaning of interpolation.
