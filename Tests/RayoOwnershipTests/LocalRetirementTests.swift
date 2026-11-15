import RayoIR
import RayoSema
import Testing

@Suite("Where locals retire")
struct LocalRetirementTests {
    @Test func `a local retires after its last use`() throws {
        let blocks = """
            bb0:
              declare %0
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              declare %1
              %1 @1:1-1:1 = add checked read %0 @1:1-1:1, 2 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %1 @1:1-1:1) @1:1-1:1
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              declare %0
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              declare %1
              %1 @1:1-1:1 = add checked read %0 @1:1-1:1, 2 @1:1-1:1
              retire %0
              _ = call builtin "print(_: Int)"(read %1 @1:1-1:1) @1:1-1:1
              retire %1
              return
            """))
    }

    @Test func `a local declared in a loop retires on each pass, and one the loop uses retires as it leaves`() throws {
        // As `var x = 0; while x < 3 { x += 1 }; print(x)` lowers: the condition's temporary is declared in the header.
        let blocks = """
            bb0:
              declare %0
              %0 @1:1-1:1 = operand 0 @1:1-1:1
              goto bb1
            bb1:
              declare %6
              %6 @1:1-1:1 = less read %0 @1:1-1:1, 3 @1:1-1:1
              branch read %6 @1:1-1:1, bb2, bb3
            bb2:
              %0 @1:1-1:1 = add checked read %0 @1:1-1:1, 1 @1:1-1:1
              goto bb1
            bb3:
              _ = call builtin "print(_: Int)"(read %0 @1:1-1:1) @1:1-1:1
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              declare %0
              %0 @1:1-1:1 = operand 0 @1:1-1:1
              goto bb1
            bb1:
              declare %6
              %6 @1:1-1:1 = less read %0 @1:1-1:1, 3 @1:1-1:1
              branch read %6 @1:1-1:1, bb2, bb3
            bb2:
              retire %6
              %0 @1:1-1:1 = add checked read %0 @1:1-1:1, 1 @1:1-1:1
              goto bb1
            bb3:
              retire %6
              _ = call builtin "print(_: Int)"(read %0 @1:1-1:1) @1:1-1:1
              retire %0
              return
            """))
    }

    @Test func `a local left on the way into a block that other paths enter retires in a block on that way`() throws {
        // `bb0` goes on to `bb1`, which uses `x`, or straight to `bb2`, which `bb1` goes on to as well.
        let blocks = """
            bb0:
              declare %6
              %6 @1:1-1:1 = operand true @1:1-1:1
              declare %0
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              branch read %6 @1:1-1:1, bb1, bb2
            bb1:
              _ = call builtin "print(_: Int)"(read %0 @1:1-1:1) @1:1-1:1
              goto bb2
            bb2:
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              declare %6
              %6 @1:1-1:1 = operand true @1:1-1:1
              declare %0
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              branch read %6 @1:1-1:1, bb1, bb3
            bb1:
              retire %6
              _ = call builtin "print(_: Int)"(read %0 @1:1-1:1) @1:1-1:1
              retire %0
              goto bb2
            bb2:
              return
            bb3:
              retire %0
              retire %6
              goto bb2
            """))
    }

    @Test func `a local an access reaches retires once the access ends`() throws {
        let blocks = """
            bb0:
              declare %0
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read %0 @1:1-1:1
              _ = call builtin "print(_: Int)"(a0) @1:1-1:1
              return
            """
        #expect(try ended(blocks) == body(of: """
            bb0:
              declare %0
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              begin a0 read %0 @1:1-1:1
              _ = call builtin "print(_: Int)"(a0) @1:1-1:1
              end a0
              retire %0
              return
            """))
    }

    @Test func `a local that no declaration starts never retires`() throws {
        // `x` holds a value from the start of the function, as a parameter does.
        let blocks = """
            bb0:
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              _ = call builtin "print(_: Int)"(read %0 @1:1-1:1) @1:1-1:1
              return
            """
        #expect(try ended(blocks) == body(of: blocks))
    }

    @Test func `a local that the function's return reads lives until the function returns`() throws {
        let blocks = """
            bb0:
              declare %0
              %0 @1:1-1:1 = operand 1 @1:1-1:1
              return read %0 @1:1-1:1
            """
        let returning = function(blocks, result: "Int")
        let written = try program(of: [returning] + callees).bodies[FunctionID(index: 0)]
        #expect(try checked(returning).body == written)
    }
}
