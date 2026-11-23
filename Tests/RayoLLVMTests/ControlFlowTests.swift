import RayoLLVM
import Testing

@Suite("Running the terminators that pass control between a function's blocks")
struct ControlFlowTests {
    @Test func `a goto goes on in its target block, skipping the blocks between`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
            bb0:
              _ = call builtin "print(_: Int)"(1) @1:1-1:2
              goto bb2
            bb1:
              _ = call builtin "print(_: Int)"(2) @1:1-1:2
              return
            bb2:
              _ = call builtin "print(_: Int)"(3) @1:1-1:2
              return
            }
            """
        #expect(try run(text) == .init(printed: "1\n3\n"))
    }

    @Test(arguments: [(true, "1\n"), (false, "2\n")])
    func `a branch goes on in its first target where its Bool is true, and in its second where it is false`(
        condition: Bool, printed: String,
    ) throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 b: Bool @1:1-1:1
            bb0:
              %0 @1:1-1:2 = operand \(condition) @1:1-1:2
              branch read %0 @1:1-1:2, bb1, bb2
            bb1:
              _ = call builtin "print(_: Int)"(1) @1:1-1:2
              return
            bb2:
              _ = call builtin "print(_: Int)"(2) @1:1-1:2
              return
            }
            """
        #expect(try run(text) == .init(printed: printed))
    }

    @Test(arguments: [Build.debug, .release])
    func `a loop runs its body until its condition is false, in every build`(build: Build) throws {
        // The header tests whether the count is below 3, and the body prints it and adds 1.
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 i: Int @1:1-1:1
              temp %1: Bool
            bb0:
              %0 @1:1-1:2 = operand 0 @1:1-1:2
              goto bb1
            bb1:
              %1 @1:1-1:2 = less read %0 @1:1-1:2, 3 @1:1-1:2
              branch read %1 @1:1-1:2, bb2, bb3
            bb2:
              \(printInt("%0"))
              %0 @1:1-1:2 = add checked read %0 @1:1-1:2, 1 @1:1-1:2
              goto bb1
            bb3:
              return
            }
            """
        #expect(try run(text, in: build) == .init(printed: "0\n1\n2\n"))
    }

    @Test(arguments: [Build.debug, .release])
    func `a branch on a constant goes on in the block the constant picks`(build: Build) throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
            bb0:
              branch false, bb1, bb2
            bb1:
              _ = call builtin "print(_: Int)"(1) @1:1-1:2
              return
            bb2:
              _ = call builtin "print(_: Int)"(2) @1:1-1:2
              return
            }
            """
        #expect(try run(text, in: build) == .init(printed: "2\n"))
    }

    @Test(arguments: [Build.debug, .release])
    func `a block that no path reaches ends in unreachable, which the program never reaches`(build: Build) throws {
        // `seven`'s second block follows its return, and `main`'s second lies between the blocks of a jump that skips
        // it.
        let text = """
            main "main()"
            func "main()"() -> Void {
              temp %0: Int
            bb0:
              %0 @1:1-1:2 = call "seven()"() @1:1-1:2
              goto bb2
            bb1:
              unreachable
            bb2:
              \(printInt("%0"))
              return
            }
            func "seven()"() -> Int {
              let %0 x: Int @1:1-1:1
            bb0:
              %0 @1:1-1:2 = operand 7 @1:1-1:2
              return move %0 @1:1-1:2
            bb1:
              unreachable
            }
            """
        #expect(try run(text, in: build) == .init(printed: "7\n"))
    }
}

@Suite("Running a return from a function")
struct ReturnTests {
    @Test func `a return with no value goes back to the caller, which goes on after the call`() throws {
        // `say` prints 1 and returns before it prints 2.
        let text = """
            main "main()"
            func "main()"() -> Void {
            bb0:
              _ = call "say()"() @1:1-1:2
              _ = call builtin "print(_: Int)"(3) @1:1-1:2
              return
            }
            func "say()"() -> Void {
            bb0:
              _ = call builtin "print(_: Int)"(1) @1:1-1:2
              return
            bb1:
              _ = call builtin "print(_: Int)"(2) @1:1-1:2
              return
            }
            """
        #expect(try run(text) == .init(printed: "1\n3\n"))
    }

    @Test func `a return gives the caller a scalar, or both scalars of a small struct`() throws {
        let text = programStructs + """
            main "main()"
            func "main()"() -> Void {
              temp %0: Bool
              temp %1: Pair
            bb0:
              %0 @1:1-1:2 = call "yes()"() @1:1-1:2
              %1 @1:1-1:2 = call "pair()"() @1:1-1:2
              \(printBool("%0"))
              \(printInt("%1.0"))
              \(printInt("%1.1"))
              return
            }
            func "yes()"() -> Bool {
            bb0:
              return true
            }
            func "pair()"() -> Pair {
              temp %0: Pair
            bb0:
              %0 @1:1-1:2 = call "Pair(a: Int, b: Int)"(1, 2) @1:1-1:2
              return read %0 @1:1-1:2
            }
            """
        #expect(try run(text) == .init(printed: "true\n1\n2\n"))
    }

    @Test(arguments: [Build.debug, .release])
    func `a large result is copied into the caller's slot, whichever value each return gives`(build: Build) throws {
        // `pick` returns one of its two arguments, so no local of its own is the result.
        let text = programStructs + """
            main "main()"
            func "main()"() -> Void {
              var %0 t: Trio @1:1-1:1
              var %1 u: Trio @1:1-1:1
              temp %2: Trio
            bb0:
              %0 @1:1-1:2 = call "Trio(a: Int, b: Int, c: Bool)"(1, 2, true) @1:1-1:2
              %1 @1:1-1:2 = call "Trio(a: Int, b: Int, c: Bool)"(3, 4, false) @1:1-1:2
              %2 @1:1-1:2 = call "pick(_: Bool, _: Trio, _: Trio)"(false, read %0 @1:1-1:2, read %1 @1:1-1:2) @1:1-1:2
              \(printInt("%2.0"))
              \(printInt("%2.1"))
              \(printBool("%2.2"))
              return
            }
            func "pick(_: Bool, _: Trio, _: Trio)"(_: &Bool, _: &Trio, _: &Trio) -> Trio {
              param %0 first: &Bool @1:1-1:1
              param %1 t: &Trio @1:1-1:1
              param %2 u: &Trio @1:1-1:1
            bb0:
              branch read %0 @1:1-1:2, bb1, bb2
            bb1:
              return read %1 @1:1-1:2
            bb2:
              return read %2 @1:1-1:2
            }
            """
        #expect(try run(text, in: build) == .init(printed: "3\n4\nfalse\n"))
    }

    @Test(arguments: [Build.debug, .release])
    func `a large result built in the local every return gives reaches the caller whole`(build: Build) throws {
        // `make` builds its Trio one field at a time, in the caller's slot, and returns it on either path.
        let text = programStructs + """
            main "main()"
            func "main()"() -> Void {
              temp %0: Trio
            bb0:
              %0 @1:1-1:2 = call "make(_: Bool)"(true) @1:1-1:2
              \(printInt("%0.0"))
              \(printInt("%0.1"))
              \(printBool("%0.2"))
              return
            }
            func "make(_: Bool)"(_: &Bool) -> Trio {
              param %0 flag: &Bool @1:1-1:1
              var %1 t: Trio @1:1-1:1
            bb0:
              %1.0 @1:1-1:2 = operand 5 @1:1-1:2
              %1.1 @1:1-1:2 = operand 6 @1:1-1:2
              %1.2 @1:1-1:2 = operand read %0 @1:1-1:2 @1:1-1:2
              branch read %0 @1:1-1:2, bb1, bb2
            bb1:
              return move %1 @1:1-1:2
            bb2:
              %1.0 @1:1-1:2 = operand 0 @1:1-1:2
              return move %1 @1:1-1:2
            }
            """
        #expect(try run(text, in: build) == .init(printed: "5\n6\ntrue\n"))
    }
}
