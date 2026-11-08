# Lexical

[12 · Grammar](../12-grammar.md)

The lexical grammar determines which tokens the parser receives. It covers names, literals, operators and the punctuation that separates or groups them.

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

**A source file is UTF-8, and one that isn't is a compile error.**

**A `\u{…}` escape stands for the UTF-8 encoding of the Unicode scalar value it names**, since a string is UTF-8 bytes ([04](../04-types/collections.md#strings)). It holds one to eight hex digits, naming a value from 0 to D7FF or from E000 to 10FFFF. Any other value is a compile error.

**A `-` is always an operator.** 04 says when a prefix one is checked with its literal as one value, so that `-128` fits an `Int8` ([04](../04-types/collections.md#literals)).

**`any-keyword` is any keyword or contextual keyword below**, so either kind, written in backticks, is an identifier.

**A multi-line string holds the lines between its delimiters**, each with the closing `"""` line's indentation removed, and joined by `\n`. The newlines after the opening `"""` and before the closing one aren't part of it:

```swift
let banner = """
    Wave 3
      Boss incoming
    """                         // "Wave 3\n  Boss incoming"
```

**After `.` in a member access, an integer literal ends before the next `.`**, so `t.0.1` is two element accesses, not one with the float literal `0.1`.

**The keywords are these:** `let var const func task struct enum protocol extension typealias import public private
init deinit self Self if else guard when case for in while repeat break continue return
throw throws try catch do defer static mutable owned consuming copy consume borrow mutating any some
where with await yield unsafe unchecked using extern as is nil true false
associatedtype subscript`.

**Contextual keywords are keywords only in the positions below, and can be used as identifiers anywhere else.** They are `read`, `modify`, `get`, `set`, `c`, `allocator`, `move`, `of`, `error`, `prefix`, `noalloc`, `stack`, `union`, `keep`, `borrows`, `outlives`, `rebind`, `to` and `discard`. Some of those positions are narrow:

- **`union`** is a keyword only after a declaration's attributes and modifiers, or at the start of an import config rule, when an identifier follows it, so `a.union(b)` stays a method call;
- **`keep`** only at the start of a function type's parameter, when a convention or a type follows it, so a parameter whose type is named `keep` still parses;
- **`error`** only after `static`;
- **`prefix`** only in an `import c … where` clause;
- **`noalloc`** only at the start of a rule inside an import config, or after `extern c`;
- **`stack`** only at the start of such a rule, after `extern c` or its `noalloc`, or after `@c` in a type;
- **`borrows`** and **`outlives`** only in a `where` clause, right after an item's subject. A requirement starts with a type, and a dotted path such as `out.items` parses as a type too, so the token after it tells a `borrows-item` from a constraint;
- **`rebind`** only at the start of a statement when an identifier follows it, so a call `rebind(x)` still parses, and **`to`** only after `rebind` and that identifier;
- **`discard`** only at the start of a statement when `self` follows it.

**Argument labels may be keywords.** A parameter's external label, and the label of an argument, can be any keyword:

```swift
func index<T: Equatable>(of x: T, in s: Span<T>) -> Int?    // 'of' and 'in' as external labels
let i = index(of: h, in: handles.span)                      // and as argument labels
```

**A keyword label is never ambiguous.** An argument's label is always followed by `:`, and a parameter's external label by its internal name and then `:`, with the convention after the `:`.
