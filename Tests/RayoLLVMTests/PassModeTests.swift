import LLVM
@testable import RayoLLVM
import RayoSema
import Testing

@Suite("How a function's arguments and result are passed")
struct PassModeTests {
    @Test func `a value of at most two scalars passes split into them, and returns in a struct of them`() throws {
        // A Pair's Bool and Int are two LLVM parameters, in the order the Pair declares them.
        try withEmitted(executable(structs + emptyMain + relaying("Pair"))) { module in
            let type = try function(named: "relay(_: Pair)", in: module).type
            #expect(type.parameters.map(\.text) == ["i1", "i64"])
            #expect(type.result.text == "{ i1, i64 }")
        }
    }

    @Test func `a struct splits into the scalars of its fields, those of a struct inside it too`() throws {
        // A Nested holds a Bool, then a Flags of two Bools, which is more than two scalars in all.
        try withEmitted(executable(structs + emptyMain + relaying("Nested"))) { module in
            let type = try function(named: "relay(_: Nested)", in: module).type
            #expect(type.parameters.map(\.text) == ["ptr", "ptr"])
            #expect(type.result.text == "void")
        }
    }

    @Test func `a large borrowed argument passes as the caller's place, and a large result in its slot`() throws {
        // The result's slot comes first, and the argument's place after it, each marked with what holds of it.
        try withEmitted(executable(structs + emptyMain + relaying("Trio"))) { module in
            let text = try function(named: "relay(_: Trio)", in: module).text
            #expect(text.contains("(\(resultSlot) %0, \(borrowedPlace) %1)"))
        }
    }

    @Test func `a call of a large borrowed argument passes a pointer to its place, with no copy`() throws {
        // `main` passes its Trio to `first`, which reads the Trio's first Int.
        let functions = """
            main "main()"
            func "main()"() -> Void {
              temp %0: Trio
              temp %1: Int
            bb0:
              %1 @1:1-1:2 = call "first(_: Trio)"(read %0 @1:1-1:2) @1:1-1:2
              return
            }
            func "first(_: Trio)"(Trio) -> Int {
              param %0 t: Trio
              temp %1: Int
            bb0:
              %1 @1:1-1:2 = use read %0.0 @1:1-1:2 @1:1-1:2
              return read %1 @1:1-1:2
            }
            """

        // `main` passes the Trio's slot itself, and `first` reads the Int through the pointer, copying nothing.
        try withEmitted(executable(structs + functions)) { module in
            let llvmMain = try function(named: "rayo.main", in: module)
            #expect(llvmMain.text.contains("call i64 @\"first(_: Trio)\"(\(borrowedPlace) %0)"))
            let llvmFirst = try function(named: "first(_: Trio)", in: module)
            #expect(instructions(.allocate, in: llvmFirst).map(\.allocatedType?.text) == ["i64"])
            #expect(llvmFirst.text.contains("getelementptr inbounds nuw %Trio, ptr %0, i32 0, i32 0"))
            #expect(!llvmFirst.text.contains("memcpy"))
        }
    }

    @Test func `a large result that starts a new local is written straight into the local's place`() throws {
        // `main` takes what `make` returns as its Trio.
        let main = """
            main "main()"
            func "main()"() -> Void {
              temp %0: Trio
            bb0:
              %0 @1:1-1:2 = call "make()"() @1:1-1:2
              return
            }
            """

        // The call is passed the Trio's slot, and nothing is copied after it.
        try withEmitted(executable(structs + main + making)) { module in
            let llvmMain = try function(named: "rayo.main", in: module)
            #expect(llvmMain.text.contains("call void @\"make()\"(\(resultSlot) %0)"))
            #expect(!llvmMain.text.contains("memcpy"))
        }
    }

    @Test func `a function that returns the local it builds its result in builds it in the caller's slot`() throws {
        // `make` builds its Trio through the slot's pointer, holding nothing of its own.
        try withEmitted(executable(structs + emptyMain + making)) { module in
            let llvmMake = try function(named: "make()", in: module)
            #expect(instructions(.allocate, in: llvmMake).isEmpty)
            #expect(llvmMake.text.contains("getelementptr inbounds nuw %Trio, ptr %0, i32 0, i32 0"))
            #expect(!llvmMake.text.contains("memcpy"))
        }
    }

    @Test func `a large value moves between places with memcpy, and is never loaded or stored whole`() throws {
        // `main` copies one Trio into another, then builds a Holder of the second, and `relay` returns its argument.
        let main = """
            main "main()"
            func "main()"() -> Void {
              temp %0: Trio
              temp %1: Trio
              temp %2: Holder
            bb0:
              %1 @1:1-1:2 = use read %0 @1:1-1:2 @1:1-1:2
              %2 @1:1-1:2 = struct Holder(move %1 @1:1-1:2, true) @1:1-1:2
              return
            }
            """

        // Each copy is a memcpy of the Trio's 24 bytes, and no load or store is of a Trio or a Holder.
        try withEmitted(executable(structs + main + relaying("Trio"))) { module in
            let functions = try [
                function(named: "rayo.main", in: module), function(named: "relay(_: Trio)", in: module),
            ]
            let copy = "call void @llvm.memcpy.p0.p0.i64(ptr align 8 %0, ptr align 8 %1, i64 24, i1 false)"
            #expect(functions[1].text.contains(copy))
            #expect(functions[0].text.components(separatedBy: "@llvm.memcpy").count == 3)
            let accessed = functions.flatMap { instructions(.load, in: $0).map(\.anyValue.type.text) }
                + functions.flatMap { instructions(.store, in: $0).map { $0.operand(at: 0).type.text } }
            #expect(!accessed.contains { $0.hasPrefix("%Trio") || $0.hasPrefix("%Holder") })
        }
    }

    @Test func `a call whose argument reads its destination writes its result to a new slot, copied in after`() throws {
        // `main` passes its Trio to `relay`, and keeps what it returns in the same Trio.
        let main = """
            main "main()"
            func "main()"() -> Void {
              temp %0: Trio
            bb0:
              %0 @1:1-1:2 = call "relay(_: Trio)"(read %0 @1:1-1:2) @1:1-1:2
              return
            }
            """

        // The call writes to a slot of its own, which is copied into the Trio once the call has read it.
        try withEmitted(executable(structs + main + relaying("Trio"))) { module in
            let llvmMain = try function(named: "rayo.main", in: module)
            #expect(instructions(.allocate, in: llvmMain).count == 2)
            #expect(llvmMain.text.contains("""
                  call void @"relay(_: Trio)"(\(resultSlot) %1, \(borrowedPlace) %0)
                  call void @llvm.memcpy.p0.p0.i64(ptr align 8 %0, ptr align 8 %1, i64 24, i1 false)
                """))
        }
    }

    @Test func `a struct whose field reads its destination is built in a new slot, copied in after`() throws {
        // `main` swaps its Ints' two fields, building the new Ints from the old one's fields.
        let main = """
            main "main()"
            func "main()"() -> Void {
              temp %0: Ints
            bb0:
              %0 @1:1-1:2 = struct Ints(read %0.1 @1:1-1:2, read %0.0 @1:1-1:2) @1:1-1:2
              return
            }
            """

        // Both fields are read and stored in a slot of their own, which is then copied into the Ints whole.
        try withEmitted(executable(structs + main)) { module in
            let llvmMain = try function(named: "rayo.main", in: module)
            #expect(instructions(.allocate, in: llvmMain).count == 2)
            #expect(llvmMain.text.contains("""
                  %7 = load i64, ptr %3, align 8
                  store i64 %7, ptr %6, align 8
                  %8 = load %Ints, ptr %1, align 8
                  store %Ints %8, ptr %0, align 8
                """))
        }
    }

    /// The structs the tests pass: a Pair of two scalars, a Trio and a Nested of three, a Holder of a Trio, a Flags
    /// of two Bools, and an Ints of two Ints.
    private let structs = """
        struct Pair {
          flag: Bool
          count: Int
        }
        struct Trio {
          a: Int
          b: Int
          c: Bool
        }
        struct Holder {
          trio: Trio
          flag: Bool
        }
        struct Flags {
          a: Bool
          b: Bool
        }
        struct Nested {
          flag: Bool
          flags: Flags
        }
        struct Ints {
          a: Int
          b: Int
        }

        """

    /// The attributes of a large result's slot, and of a large borrowed argument's place, as LLVM IR writes them.
    private let resultSlot = "ptr dead_on_unwind noalias writable sret(%Trio) align 8"
    private let borrowedPlace = "ptr noalias noundef nonnull readonly align 8 captures(none) dereferenceable(24)"

    /// `relay(_:)`, which returns the borrowed argument it is passed, of the type `type` names.
    private func relaying(_ type: String) -> String {
        """

        func "relay(_: \(type))"(\(type)) -> \(type) {
          param %0 value: \(type)
        bb0:
          return read %0 @1:1-1:2
        }
        """
    }

    /// `make()`, which builds a Trio in a local and returns it.
    private let making = """

        func "make()"() -> Trio {
          temp %0: Trio
        bb0:
          %0 @1:1-1:2 = struct Trio(1, 2, true) @1:1-1:2
          return move %0 @1:1-1:2
        }
        """
}

@Suite("The rules that decide how an argument or a result is passed")
struct SignatureLoweringTests {
    @Test func `a small argument passes directly, but a mutable one, which passes as its place`() throws {
        try withModes { mode in
            #expect(mode(.borrowed, .int) == .direct([Scalar(steps: [], type: .int)]))
            #expect(mode(.owned, .int) == .direct([Scalar(steps: [], type: .int)]))
            #expect(mode(.mutable, .int) ==
                .callerPlace([.noAlias, .capturesNone, .noUndef, .nonNull, .dereferenceable(8), .align(8)]))
        }
    }

    @Test func `a large argument passes as a pointer, which a borrowed one never writes through`() throws {
        try withModes { mode in
            let pointer: [Attribute] = [.capturesNone, .noUndef, .nonNull, .dereferenceable(24), .align(8)]
            #expect(mode(.borrowed, trioType) == .callerPlace([.noAlias, .readOnly] + pointer))
            #expect(mode(.owned, trioType) == .filledSlot([.noAlias] + pointer))
            #expect(mode(.mutable, trioType) == .callerPlace([.noAlias] + pointer))
        }
    }

    @Test func `a value that takes no memory passes in no scalars, and a mutable one claims no bytes`() throws {
        try withModes { mode in
            #expect(mode(.owned, emptyType) == .direct([]))
            #expect(mode(.mutable, emptyType) ==
                .callerPlace([.noAlias, .capturesNone, .noUndef, .nonNull, .align(1)]))
        }
    }

    /// A Trio of two Ints and a Bool, which splits into three scalars, and an Empty, which splits into none.
    private let table = TypeTable(structs: [
        StructType(name: "Trio", fields: [
            Field(name: "a", type: .int), Field(name: "b", type: .int), Field(name: "c", type: .bool),
        ]),
        StructType(name: "Empty", fields: []),
    ])

    private var trioType: RayoType { .structure(StructID(index: 0, name: "Trio")) }
    private var emptyType: RayoType { .structure(StructID(index: 1, name: "Empty")) }

    /// Runs `body` with a function that says how a parameter of a convention and a type passes, under Rayo's
    /// convention, in a program whose structs are `table`'s.
    private func withModes(_ body: ((ParameterConvention, RayoType) -> ParameterPassing) throws -> Void) throws {
        try withProgramModule(for: .debug) { programModule in
            let lowering = SignatureLowering(types: LLVMTypes(table, in: programModule.emitter.context))
            try body { convention, type in
                let parameter = FunctionSignature.Parameter(convention: convention, type: type)
                let signature = FunctionSignature(parameters: [parameter], result: .void, convention: .rayo)
                return lowering.lower(signature, in: programModule.emitter.context).parameters[0]
            }
        }
    }
}
