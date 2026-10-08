# Introduction

Rayo is a language for programs that need control over memory and performance without leaving everyday code open to memory bugs. Game code makes that need easy to see. An enemy has a position and health, but it may also hold a target, share data with other systems, or be removed while the game is running. The more those pieces interact, the harder it is to tell which data is still safe to use.

This guide starts small and adds those situations one at a time. First you'll change an enemy's health in a complete program. Then you'll see what happens when values move between parts of a program, when a function borrows a value, and when a link needs to stay around longer than a function call. Each new idea grows out of code you've already seen.

If you know C++, Rust, Swift or C#, much of Rayo will look familiar. Some familiar-looking code behaves differently, especially when it copies a value or keeps a link to one. The chapters point out those differences where they matter, so you can learn Rayo on its own terms.

Read the chapters in order, starting with [1 · Basics](01-basics.md). You can follow the examples without learning the whole memory model first. When you need every condition and exception behind an example, the [specification](../spec/README.md) has the full rule. Rayo is still in design. Its compiler currently parses only part of the language and cannot run programs yet, so the examples show what the language is intended to do.
