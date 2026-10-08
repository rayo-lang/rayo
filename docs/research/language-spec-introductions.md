# How language specifications introduce themselves

The official references below put an introduction before their first technical topic. They use that space to identify the language, describe what the document covers, or tell readers how to use it. The introduction need not be a numbered chapter.

| Reference | What comes before the first technical topic |
| --- | --- |
| [Rust Reference](https://doc.rust-lang.org/reference/) | A standalone, unnumbered **Introduction** identifies the book as Rust's primary reference, distinguishes it from the teaching book and library documentation, and explains how to look up rules. |
| [Go specification](https://go.dev/ref/spec) | **Introduction** appears directly under the specification title. It describes Go in a few sentences; **Notation** and then **Source code representation** follow. Go keeps these sections on one page rather than using a separate introduction chapter. |
| [Kotlin specification](https://kotlinlang.org/spec/introduction.html) | **Introduction** is the first item under Kotlin/Core, before **Syntax and grammar**. It sketches the language and states that this part of the specification covers common, platform-independent behavior. |
| [C# specification contents](https://learn.microsoft.com/en-us/dotnet/csharp/specification/) | The standard has **Introduction**, **Scope**, and **General description** before the language specification begins with **Lexical structure**. The [general description](https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/language-specification/general-description) names implementers, academics, and application programmers as readers and explains its use of examples and informative text. |

## Implication for Rayo

An introduction belongs before “01 Values and ownership,” because ownership is already a technical topic. It can be a short, unnumbered page rather than a numbered chapter. It should say what Rayo is, what this specification defines, who it serves, how to use it alongside the guide, and where its boundaries lie. Chapter 01 can then begin with the value model instead of reintroducing the language. The precedents support this placement; the choice to keep Rayo's introduction brief is an editorial judgment, not a requirement imposed by another specification.
