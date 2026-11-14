import LLVM
@testable import RayoLLVM
import Testing

@Suite("The LLVM types a program is emitted with")
struct EmittedTypeTests {
    @Test(arguments: [("Int", "i64"), ("Bool", "i1")])
    func `a function's signature holds its parameters and result in their types`(
        result: String, resultText: String,
    ) throws {
        // The emitted signature takes an i64 and an i1, and returns the LLVM type of `result`.
        try withEmitted(executable(emptyMain + pick(returning: result))) { module in
            let signature = try signature(of: "pick(_: Int, _: Bool)", in: module)
            #expect(signature.parameters.map(\.text) == ["i64", "i1"])
            #expect(signature.result.text == resultText)
        }
    }

    @Test func `a function that returns nothing is declared returning void`() throws {
        try withEmitted(executable(emptyMain)) { module in
            let signature = try signature(of: "rayo.main", in: module)
            #expect(signature.parameters.map(\.text) == [])
            #expect(signature.result.text == "void")
        }
    }

    @Test func `each local's slot, a parameter's too, holds the type of its value`() throws {
        let pick = pick(returning: "Int", temporaries: ["Bool", "Int"])

        // The emitted function allocates a slot of each local's LLVM type, its parameters' first.
        try withEmitted(executable(emptyMain + pick)) { module in
            let llvmFunction = try function(named: "pick(_: Int, _: Bool)", in: module)
            let slotTypes = instructions(.allocate, in: llvmFunction).map(\.allocatedType?.text)
            #expect(slotTypes == ["i64", "i1", "i1", "i64"])
        }
    }

    @Test func `each local's slot is aligned as its type is, a struct's as its most-aligned field`() throws {
        let main = """
            main "main()"
            func "main()"() -> Void {
              temp %0: Bool
              temp %1: Pair
              temp %2: Int
            bb0:
              return
            }
            """

        // The emitted `main` aligns the Bool's slot to 1, and the Pair's and the Int's to 8.
        try withEmitted(executable(pair + main)) { module in
            let slots = instructions(.allocate, in: try function(named: "rayo.main", in: module))
            #expect(slots.map(\.alignment) == [1, 8, 8])
        }
    }

    @Test func `a load and a store of a struct are aligned as the struct is`() throws {
        // `main` copies one Pair into another, so it loads the first and stores the second.
        let main = """
            main "main()"
            func "main()"() -> Void {
              temp %0: Pair
              temp %1: Pair
            bb0:
              %1 @1:1-1:2 = use read %0 @1:1-1:2 @1:1-1:2
              return
            }
            """

        // The emitted copy reads and writes 8-byte-aligned memory.
        try withEmitted(executable(pair + main)) { module in
            let llvmMain = try function(named: "rayo.main", in: module)
            #expect(instructions(.load, in: llvmMain).map(\.alignment) == [8])
            #expect(instructions(.store, in: llvmMain).map(\.alignment) == [8])
        }
    }

    @Test func `a struct is built in its place, each field stored in the element its layout puts it in`() throws {
        // `main` makes a Pair of its Bool and its Int, which the Pair declares in that order.
        let main = """
            main "main()"
            func "main()"() -> Void {
              temp %0: Bool
              temp %1: Int
              temp %2: Pair
            bb0:
              %2 @1:1-1:2 = call "Pair(flag: Bool, count: Int)"(read %0 @1:1-1:2, read %1 @1:1-1:2) @1:1-1:2
              return
            }
            """

        // The Bool goes in the second element and the Int in the first, each stored in the Pair's slot.
        try withEmitted(executable(pair + main)) { module in
            let text = try function(named: "rayo.main", in: module).text
            #expect(text.contains("""
                  %3 = getelementptr inbounds nuw %Pair, ptr %2, i32 0, i32 1
                  %4 = load i1, ptr %0, align 1
                  store i1 %4, ptr %3, align 1
                  %5 = getelementptr inbounds nuw %Pair, ptr %2, i32 0, i32 0
                  %6 = load i64, ptr %1, align 8
                  store i64 %6, ptr %5, align 8
                """))
        }
    }

    @Test func `a field is read from the element that its struct's layout puts it in, aligned as its type is`() throws {
        // `main` reads the Pair's Bool, which it declares first.
        let main = """
            main "main()"
            func "main()"() -> Void {
              temp %0: Pair
              temp %1: Bool
            bb0:
              %1 @1:1-1:2 = use read %0.0 @1:1-1:2 @1:1-1:2
              return
            }
            """

        // The read loads one byte from the Pair's second element.
        try withEmitted(executable(pair + main)) { module in
            let text = try function(named: "rayo.main", in: module).text
            #expect(text.contains("""
                  %2 = getelementptr inbounds nuw %Pair, ptr %0, i32 0, i32 1
                  %3 = load i1, ptr %2, align 1
                """))
        }
    }

    @Test func `a field inside a field is read by stepping into each struct's element that holds the next`() throws {
        // `main` reads the Bool of the Pair that a Holder declares second.
        let main = """
            main "main()"
            func "main()"() -> Void {
              temp %0: Holder
              temp %1: Bool
            bb0:
              %1 @1:1-1:2 = use read %0.1.0 @1:1-1:2 @1:1-1:2
              return
            }
            """

        // The Holder lays its Pair out first, and the Pair its Bool second, so the read steps into the first element
        // of the one and the second of the other.
        try withEmitted(executable(pair + holder + main)) { module in
            let text = try function(named: "rayo.main", in: module).text
            #expect(text.contains("""
                  %2 = getelementptr inbounds nuw %Holder, ptr %0, i32 0, i32 0
                  %3 = getelementptr inbounds nuw %Pair, ptr %2, i32 0, i32 1
                  %4 = load i1, ptr %3, align 1
                """))
        }
    }

    @Test func `a field is stored in the element that its struct's layout puts it in, aligned as its type is`() throws {
        // `main` stores its Bool in the Pair's Bool, which the Pair declares first.
        let main = """
            main "main()"
            func "main()"() -> Void {
              temp %0: Pair
              temp %1: Bool
            bb0:
              %0.0 @1:1-1:2 = use read %1 @1:1-1:2 @1:1-1:2
              return
            }
            """

        // The store writes one byte to the Pair's second element.
        try withEmitted(executable(pair + main)) { module in
            let text = try function(named: "rayo.main", in: module).text
            #expect(text.contains("""
                  %2 = getelementptr inbounds nuw %Pair, ptr %0, i32 0, i32 1
                  %3 = load i1, ptr %1, align 1
                  store i1 %3, ptr %2, align 1
                """))
        }
    }

    @Test func `a field inside a field is stored by stepping into each struct's element that holds the next`() throws {
        // `main` stores its Int in the Int of the Pair that a Holder declares second.
        let main = """
            main "main()"
            func "main()"() -> Void {
              temp %0: Holder
              temp %1: Int
            bb0:
              %0.1.1 @1:1-1:2 = use read %1 @1:1-1:2 @1:1-1:2
              return
            }
            """

        // The Holder lays its Pair out first, and the Pair its Int first too, so the store steps into the first
        // element of each.
        try withEmitted(executable(pair + holder + main)) { module in
            let text = try function(named: "rayo.main", in: module).text
            #expect(text.contains("""
                  %2 = getelementptr inbounds nuw %Holder, ptr %0, i32 0, i32 0
                  %3 = getelementptr inbounds nuw %Pair, ptr %2, i32 0, i32 0
                  %4 = load i64, ptr %1, align 8
                  store i64 %4, ptr %3, align 8
                """))
        }
    }

    /// A struct of a Bool and an Int, which lies as the Int, then the Bool, then 7 bytes of padding, with its
    /// primary initializer.
    private let pair = """
        struct Pair {
          flag: Bool
          count: Int
        }
        init "Pair(flag: Bool, count: Int)"(Bool, Int) -> Pair

        """

    /// A struct of a Bool and a Pair, which lies as the Pair, then the Bool.
    private let holder = """
        struct Holder {
          flag: Bool
          pair: Pair
        }

        """

    /// `pick(_: Int, _: Bool)`, which holds temporaries of the types `temporaries` names besides its parameters, and
    /// returns the parameter of the type `result` names.
    private func pick(returning result: String, temporaries: [String] = []) -> String {
        let locals = temporaries.enumerated().map { "  temp %\($0 + 2): \($1)\n" }.joined()
        return """

            func "pick(_: Int, _: Bool)"(Int, Bool) -> \(result) {
              param %0 n: Int
              param %1 b: Bool
            \(locals)bb0:
              return read %\(result == "Int" ? 0 : 1) @1:1-1:2
            }
            """
    }

    /// The type of the function named `name` in `module`: its parameters and its result.
    private func signature(of name: String, in module: borrowing Module) throws -> FunctionType {
        try function(named: name, in: module).type
    }
}
