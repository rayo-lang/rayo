import RayoLLVM
import Testing

@Suite("Running a call of a function the program declares")
struct CallTests {
    @Test func `a call stores the scalar its function returns in the destination`() throws {
        // `double` prints the Int it is passed, then `main` prints what it returns.
        let text = """
            main "main()"
            func "main()"() -> Void {
              temp %0: Int
            bb0:
              %0 @1:1-1:2 = call "double(_: Int)"(21) @1:1-1:2
              \(printInt("%0"))
              return
            }
            """
        #expect(try run(programStructs + text + functions) == .init(printed: "21\n42\n"))
    }

    @Test func `a call stores both scalars of a small struct its function returns in the destination`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 p: Pair
              temp %1: Pair
            bb0:
              %0 @1:1-1:2 = call "Pair(a: Int, b: Int)"(1, 2) @1:1-1:2
              %1 @1:1-1:2 = call "swapped(_: Pair)"(read %0 @1:1-1:2) @1:1-1:2
              \(printInt("%1.0"))
              \(printInt("%1.1"))
              return
            }
            """
        #expect(try run(programStructs + text + functions) == .init(printed: "2\n1\n"))
    }

    @Test func `a call writes a large struct its function returns into the destination, through its slot`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 t: Trio
            bb0:
              %0 @1:1-1:2 = call "trio(_: Int)"(5) @1:1-1:2
              \(printInt("%0.0"))
              \(printInt("%0.1"))
              \(printBool("%0.2"))
              return
            }
            """
        #expect(try run(programStructs + text + functions) == .init(printed: "5\n6\ntrue\n"))
    }

    @Test func `a large argument passes the place it is read from, and the place an access reaches`() throws {
        // `sum` reads the Trio's two Ints through the pointer it is passed.
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 t: Trio
              temp %1: Int
              temp %2: Int
            bb0:
              %0 @1:1-1:2 = call "Trio(a: Int, b: Int, c: Bool)"(3, 4, false) @1:1-1:2
              %1 @1:1-1:2 = call "sum(_: Trio)"(read %0 @1:1-1:2) @1:1-1:2
              begin a0 read static %0 @1:1-1:2
              %2 @1:1-1:2 = call "sum(_: Trio)"(a0) @1:1-1:2
              end a0
              \(printInt("%1"))
              \(printInt("%2"))
              return
            }
            """
        #expect(try run(programStructs + text + functions) == .init(printed: "7\n7\n"))
    }

    @Test(arguments: [Build.debug, .release])
    func `a large result whose argument reads the destination is built from the argument as it was`(
        build: Build,
    ) throws {
        // `swapped` writes its result's first Int before it reads the argument's first, so a result written straight
        // into the Trio it reads would read the Int it just wrote.
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 t: Trio
            bb0:
              %0 @1:1-1:2 = call "Trio(a: Int, b: Int, c: Bool)"(1, 2, true) @1:1-1:2
              %0 @1:1-1:2 = call "swapped(_: Trio)"(read %0 @1:1-1:2) @1:1-1:2
              \(printInt("%0.0"))
              \(printInt("%0.1"))
              \(printBool("%0.2"))
              return
            }
            """
        #expect(try run(programStructs + text + functions, in: build) == .init(printed: "2\n1\nfalse\n"))
    }

    @Test func `a call with no destination still runs its function, whatever its result`() throws {
        // `double` prints the Int it is passed, and `trio` adds 1 to the one it is passed, which overflows.
        let text = """
            main "main()"
            func "main()"() -> Void {
            bb0:
              _ = call "double(_: Int)"(1) @1:1-1:2
              _ = call "trio(_: Int)"(9223372036854775807) @1:1-1:2
              return
            }
            """
        let panic = "main.rayo:7:3: panic: integer overflow\n"
        #expect(try run(programStructs + text + functions) == .init(printed: "1\n", panic: panic))
    }

    /// The functions that `main` calls: `double`, which prints an Int and returns twice it; `swapped`, which returns a
    /// Pair with its Ints swapped, or a Trio with its Ints swapped and its Bool false; `trio`, which returns a Trio of
    /// an Int, the next Int and true; and `sum`, which returns the sum of a Trio's Ints.
    private let functions = """

        func "double(_: Int)"(Int) -> Int {
          param %0 x: Int
          temp %1: Int
        bb0:
          \(printInt("%0"))
          %1 @1:1-1:2 = add checked read %0 @1:1-1:2, read %0 @1:1-1:2 @1:1-1:2
          return read %1 @1:1-1:2
        }
        func "swapped(_: Pair)"(Pair) -> Pair {
          param %0 p: Pair
          temp %1: Pair
        bb0:
          %1 @1:1-1:2 = call "Pair(a: Int, b: Int)"(read %0.1 @1:1-1:2, read %0.0 @1:1-1:2) @1:1-1:2
          return move %1 @1:1-1:2
        }
        func "trio(_: Int)"(Int) -> Trio {
          param %0 x: Int
          temp %1: Int
          temp %2: Trio
        bb0:
          %1 @1:1-1:2 = add checked read %0 @1:1-1:2, 1 @7:3-7:8
          %2 @1:1-1:2 = call "Trio(a: Int, b: Int, c: Bool)"(read %0 @1:1-1:2, read %1 @1:1-1:2, true) @1:1-1:2
          return move %2 @1:1-1:2
        }
        func "sum(_: Trio)"(Trio) -> Int {
          param %0 t: Trio
          temp %1: Int
        bb0:
          %1 @1:1-1:2 = add checked read %0.0 @1:1-1:2, read %0.1 @1:1-1:2 @1:1-1:2
          return read %1 @1:1-1:2
        }
        func "swapped(_: Trio)"(Trio) -> Trio {
          param %0 t: Trio
          temp %1: Trio
        bb0:
          %1 @1:1-1:2 = call "Trio(a: Int, b: Int, c: Bool)"(read %0.1 @1:1-1:2, read %0.0 @1:1-1:2, false) @1:1-1:2
          return move %1 @1:1-1:2
        }
        """
}

@Suite("Running a call of a struct's primary initializer")
struct InitializerCallTests {
    @Test func `a primary initializer builds a struct of its arguments, in the order of its fields`() throws {
        let text = programStructs + """
            main "main()"
            func "main()"() -> Void {
              var %0 t: Trio
            bb0:
              %0 @1:1-1:2 = call "Trio(a: Int, b: Int, c: Bool)"(1, 2, true) @1:1-1:2
              \(printInt("%0.0"))
              \(printInt("%0.1"))
              \(printBool("%0.2"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "1\n2\ntrue\n"))
    }

    @Test(arguments: [Build.debug, .release])
    func `a struct whose arguments read its destination's fields is built from the fields as they were`(
        build: Build,
    ) throws {
        // Each struct swaps its two Ints, so one built in its destination would read an Int it had just written.
        let swapTrio = #"call "Trio(a: Int, b: Int, c: Bool)"(read %1.1 @1:1-1:2, read %1.0 @1:1-1:2, false)"#
        let text = programStructs + """
            main "main()"
            func "main()"() -> Void {
              var %0 p: Pair
              var %1 t: Trio
            bb0:
              %0 @1:1-1:2 = call "Pair(a: Int, b: Int)"(1, 2) @1:1-1:2
              %0 @1:1-1:2 = call "Pair(a: Int, b: Int)"(read %0.1 @1:1-1:2, read %0.0 @1:1-1:2) @1:1-1:2
              %1 @1:1-1:2 = call "Trio(a: Int, b: Int, c: Bool)"(3, 4, true) @1:1-1:2
              %1 @1:1-1:2 = \(swapTrio) @1:1-1:2
              \(printInt("%0.0"))
              \(printInt("%0.1"))
              \(printInt("%1.0"))
              \(printInt("%1.1"))
              return
            }
            """
        #expect(try run(text, in: build) == .init(printed: "2\n1\n4\n3\n"))
    }
}
