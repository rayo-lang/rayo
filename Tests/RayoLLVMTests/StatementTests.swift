import RayoLLVM
import Testing

@Suite("Running a computation that stores its value in a place")
struct ComputeTests {
    @Test func `a value computed into a local is what a later read of the local gives`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 x: Int @1:1-1:1
            bb0:
              %0 @1:1-1:2 = operand 5 @1:1-1:2
              \(printInt("%0"))
              %0 @1:1-1:2 = operand 6 @1:1-1:2
              \(printInt("%0"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "5\n6\n"))
    }

    @Test func `a value computed into a field changes that field and leaves the other`() throws {
        let text = programStructs + """
            main "main()"
            func "main()"() -> Void {
              var %0 p: Pair @1:1-1:1
            bb0:
              %0 @1:1-1:2 = call "Pair(a: Int, b: Int)"(1, 2) @1:1-1:2
              %0.1 @1:1-1:2 = operand 7 @1:1-1:2
              \(printInt("%0.0"))
              \(printInt("%0.1"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "1\n7\n"))
    }

    @Test func `a value computed into an element at a constant index changes that element alone`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 a: [3 of Int] @1:1-1:1
            bb0:
              %0 @1:1-1:2 = array of Int(1, 2, 3) @1:1-1:2
              %0[1] @1:1-1:2 = operand 9 @1:1-1:2
              \(printInt("%0[0]"))
              \(printInt("%0[1]"))
              \(printInt("%0[2]"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "1\n9\n3\n"))
    }

    @Test func `a value computed into an element at an index a local holds changes that element alone`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 a: [3 of Int] @1:1-1:1
              temp %1: UInt
            bb0:
              %0 @1:1-1:2 = array of Int(1, 2, 3) @1:1-1:2
              %1 @1:1-1:2 = index UInt 2 below 3 @1:1-1:2
              %0[%1] @1:1-1:2 = operand 9 @1:1-1:2
              \(printInt("%0[0]"))
              \(printInt("%0[1]"))
              \(printInt("%0[2]"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "1\n2\n9\n"))
    }

    @Test func `a value computed into a place of several steps reaches the field or element they lead to`() throws {
        // A Box's Pair's second Int, and the last of its Ints.
        let text = programStructs + """
            main "main()"
            func "main()"() -> Void {
              var %0 box: Box @1:1-1:1
            bb0:
              %0.0 @1:1-1:2 = call "Pair(a: Int, b: Int)"(1, 2) @1:1-1:2
              %0.1 @1:1-1:2 = array of Int(3, 4, 5) @1:1-1:2
              %0.0.1 @1:1-1:2 = operand 7 @1:1-1:2
              %0.1[2] @1:1-1:2 = operand 8 @1:1-1:2
              \(printInt("%0.0.0"))
              \(printInt("%0.0.1"))
              \(printInt("%0.1[1]"))
              \(printInt("%0.1[2]"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "1\n7\n4\n8\n"))
    }
}

@Suite("Running a computation whose value no place takes")
struct DroppedValueTests {
    @Test func `a dropped operand, array or struct changes nothing, and the program goes on`() throws {
        let text = programStructs + """
            main "main()"
            func "main()"() -> Void {
              var %0 x: Int @1:1-1:1
            bb0:
              %0 @1:1-1:2 = operand 5 @1:1-1:2
              _ = operand read %0 @1:1-1:2 @1:1-1:2
              _ = array of Int(read %0 @1:1-1:2, 6) @1:1-1:2
              _ = fill 2 of read %0 @1:1-1:2 @1:1-1:2
              _ = call "Pair(a: Int, b: Int)"(read %0 @1:1-1:2, 6) @1:1-1:2
              \(printInt("%0"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "5\n"))
    }

    @Test(arguments: [Build.debug, .release])
    func `a dropped index is still checked, so one outside the array panics, in every build`(build: Build) throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 i: UInt @1:1-1:1
            bb0:
              %0 @1:1-1:2 = operand UInt 5 @1:1-1:2
              _ = index read %0 @1:1-1:2 below 3 @2:3-2:4
              _ = call builtin "print(_: Int)"(1) @1:1-1:2
              return
            }
            """
        #expect(try run(text, in: build) == .init(printed: "", panic: "main.rayo:2:3: panic: index out of range\n"))
    }

    @Test(arguments: [Build.debug, .release])
    func `a dropped conversion that overflows still panics where overflow is checked, and goes on where it isn't`(
        build: Build,
    ) throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 x: Int @1:1-1:1
            bb0:
              %0 @1:1-1:2 = operand -1 @1:1-1:2
              _ = call builtin "UInt(_: Int)"(read %0 @1:1-1:2) @2:3-2:4
              _ = call builtin "print(_: Int)"(1) @1:1-1:2
              return
            }
            """
        let expected: InProcessJIT.Run = build == .debug
            ? .init(printed: "", panic: "main.rayo:2:3: panic: integer overflow\n")
            : .init(printed: "1\n")
        #expect(try run(text, in: build) == expected)
    }

    @Test(arguments: [
        (Build.debug, "divide checked 1", 0, "division by zero"),
        (.release, "divide checked 1", 0, "division by zero"),
        (.release, "remainder 1", 0, "remainder by zero"),
        (.debug, "add checked 1", 9_223_372_036_854_775_807, "integer overflow"),
    ])
    func `a dropped operator is still computed, so one that panics panics, in the builds where it panics`(
        build: Build, operation: String, operand: Int64, reason: String,
    ) throws {
        // The right operand is a local's, so the operator is computed when the program runs.
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 x: Int @1:1-1:1
            bb0:
              %0 @1:1-1:2 = operand \(operand) @1:1-1:2
              _ = \(operation), read %0 @1:1-1:2 @3:7-3:12
              _ = call builtin "print(_: Int)"(1) @1:1-1:2
              return
            }
            """
        #expect(try run(text, in: build) == .init(printed: "", panic: "main.rayo:3:7: panic: \(reason)\n"))
    }
}

@Suite("Running the statements that only the ownership stage looks at")
struct OwnershipStatementTests {
    @Test func `a declared local holds the value a later statement stores in it`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              let %0 x: Int @1:1-1:1
            bb0:
              declare %0
              %0 @1:1-1:2 = operand 4 @1:1-1:2
              \(printInt("%0"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "4\n"))
    }

    @Test func `a static read or modify access passed to a call passes the value of the place it reaches`() throws {
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 x: Int @1:1-1:1
            bb0:
              %0 @1:1-1:2 = operand 4 @1:1-1:2
              begin a0 read static %0 @1:1-1:2
              _ = call builtin "print(_: Int)"(a0) @1:1-1:2
              end a0
              %0 @1:1-1:2 = operand 5 @1:1-1:2
              begin a1 modify static %0 @1:1-1:2
              _ = call "show(_: Int)"(a1) @1:1-1:2
              end a1
              return
            }
            func "show(_: Int)"(_: mutable Int) -> Void {
              param %0 n: mutable Int @1:1-1:1
            bb0:
              begin a0 read static %0 @1:1-1:2
              _ = call builtin "print(_: Int)"(a0) @1:1-1:2
              end a0
              return
            }
            """
        #expect(try run(text) == .init(printed: "4\n5\n"))
    }

    @Test func `a dependence on an access changes nothing the program prints`() throws {
        // `%1` depends on the access that reads `%0`, as a value computed from a borrow would.
        let text = """
            main "main()"
            func "main()"() -> Void {
              var %0 x: Int @1:1-1:1
              temp %1: Int
            bb0:
              %0 @1:1-1:2 = operand 4 @1:1-1:2
              begin a0 read static %0 @1:1-1:2
              %1 @1:1-1:2 = operand read %0 @1:1-1:2 @1:1-1:2
              depend %1 on a0
              end a0
              \(printInt("%1"))
              return
            }
            """
        #expect(try run(text) == .init(printed: "4\n"))
    }
}
