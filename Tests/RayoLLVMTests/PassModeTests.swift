import LLVM
import RayoIR
@testable import RayoLLVM
import RayoSema
import Testing

@Suite("How a function's arguments and result are passed")
struct PassModeTests {
    @Test func `a value of at most two scalars passes split into them, and returns in a struct of them`() throws {
        let relay = relaying(pairType)

        // A Pair's Bool and Int are two LLVM parameters, in the order the Pair declares them.
        try withEmitted(program(of: [emptyMain, relay], types: table)) { module in
            let type = try function(named: relay.name, in: module).type
            #expect(type.parameters.map(\.text) == ["i1", "i64"])
            #expect(type.result.text == "{ i1, i64 }")
        }
    }

    @Test func `a struct splits into the scalars of its fields, those of a struct inside it too`() throws {
        let relay = relaying(nestedType)

        // A Nested holds a Bool, then a Flags of two Bools, which is more than two scalars in all.
        try withEmitted(program(of: [emptyMain, relay], types: table)) { module in
            let type = try function(named: relay.name, in: module).type
            #expect(type.parameters.map(\.text) == ["ptr", "ptr"])
            #expect(type.result.text == "void")
        }
    }

    @Test func `a large borrowed argument passes as the caller's place, and a large result in its slot`() throws {
        let relay = relaying(trioType)

        // The result's slot comes first, and the argument's place after it, each marked with what holds of it.
        try withEmitted(program(of: [emptyMain, relay], types: table)) { module in
            let text = try function(named: relay.name, in: module).text
            #expect(text.contains("(\(resultSlot) %0, \(borrowedPlace) %1)"))
        }
    }

    @Test func `a call of a large borrowed argument passes a pointer to its place, with no copy`() throws {
        // `main` passes its Trio to `first`, which reads the Trio's first Int.
        let main = mainFunction(locals: [trioType, .int], [
            BasicBlock(
                statements: [statement(storingIn: 1, .call(.function(FunctionID(index: 1)), arguments: [read(0)]))],
                terminator: .return(nil),
            ),
        ])
        let first = IRFunction(
            name: "first(_: Trio)", parameterCount: 1, result: .int,
            locals: [.source(name: "t", kind: .parameter, type: trioType), .temporary(.int)],
            blocks: [BasicBlock(
                statements: [statement(storingIn: 1, .use(.read(Place(local: LocalID(index: 0), fields: [0],
                                                                      range: nowhere))))],
                terminator: .return(read(1)),
            )],
        )

        // `main` passes the Trio's slot itself, and `first` reads the Int through the pointer, copying nothing.
        try withEmitted(program(of: [main, first], types: table)) { module in
            let llvmMain = try function(named: "rayo.main", in: module)
            #expect(llvmMain.text.contains("call i64 @\"first(_: Trio)\"(\(borrowedPlace) %0)"))
            let llvmFirst = try function(named: first.name, in: module)
            #expect(instructions(.allocate, in: llvmFirst).map(\.allocatedType?.text) == ["i64"])
            #expect(llvmFirst.text.contains("getelementptr inbounds nuw %Trio, ptr %0, i32 0, i32 0"))
            #expect(!llvmFirst.text.contains("memcpy"))
        }
    }

    @Test func `a large result that starts a new local is written straight into the local's place`() throws {
        // `main` takes what `make` returns as its Trio.
        let main = mainFunction(locals: [trioType], [
            BasicBlock(
                statements: [statement(storingIn: 0, .call(.function(FunctionID(index: 1)), arguments: []))],
                terminator: .return(nil),
            ),
        ])

        // The call is passed the Trio's slot, and nothing is copied after it.
        try withEmitted(program(of: [main, making], types: table)) { module in
            let llvmMain = try function(named: "rayo.main", in: module)
            #expect(llvmMain.text.contains("call void @\"make()\"(\(resultSlot) %0)"))
            #expect(!llvmMain.text.contains("memcpy"))
        }
    }

    @Test func `a function that returns the local it builds its result in builds it in the caller's slot`() throws {
        // `make` builds its Trio through the slot's pointer, holding nothing of its own.
        try withEmitted(program(of: [emptyMain, making], types: table)) { module in
            let llvmMake = try function(named: making.name, in: module)
            #expect(instructions(.allocate, in: llvmMake).isEmpty)
            #expect(llvmMake.text.contains("getelementptr inbounds nuw %Trio, ptr %0, i32 0, i32 0"))
            #expect(!llvmMake.text.contains("memcpy"))
        }
    }

    @Test func `a large value moves between places with memcpy, and is never loaded or stored whole`() throws {
        // `main` copies one Trio into another, then builds a Holder of the second, and `relay` returns its argument.
        let main = mainFunction(locals: [trioType, trioType, holderType], [
            BasicBlock(statements: [
                statement(storingIn: 1, .use(read(0))),
                statement(storingIn: 2, .structure(holderID, fields: [move(1), .constant(.bool(true))])),
            ], terminator: .return(nil)),
        ])
        let relay = relaying(trioType)

        // Each copy is a memcpy of the Trio's 24 bytes, and no load or store is of a Trio or a Holder.
        try withEmitted(program(of: [main, relay], types: table)) { module in
            let functions = try [function(named: "rayo.main", in: module), function(named: relay.name, in: module)]
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
        let main = mainFunction(locals: [trioType], [
            BasicBlock(
                statements: [statement(storingIn: 0, .call(.function(FunctionID(index: 1)), arguments: [read(0)]))],
                terminator: .return(nil),
            ),
        ])

        // The call writes to a slot of its own, which is copied into the Trio once the call has read it.
        try withEmitted(program(of: [main, relaying(trioType)], types: table)) { module in
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
        let main = mainFunction(locals: [intsType], [
            BasicBlock(statements: [
                statement(storingIn: 0, .structure(intsID, fields: [field(1, of: 0), field(0, of: 0)])),
            ], terminator: .return(nil)),
        ])

        // Both fields are read and stored in a slot of their own, which is then copied into the Ints whole.
        try withEmitted(program(of: [main], types: table)) { module in
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
    private let table = TypeTable(structs: [
        StructType(name: "Pair", fields: [Field(name: "flag", type: .bool), Field(name: "count", type: .int)]),
        StructType(name: "Trio", fields: [
            Field(name: "a", type: .int), Field(name: "b", type: .int), Field(name: "c", type: .bool),
        ]),
        StructType(name: "Holder", fields: [
            Field(name: "trio", type: .structure(StructID(index: 1, name: "Trio"))), Field(name: "flag", type: .bool),
        ]),
        StructType(name: "Flags", fields: [Field(name: "a", type: .bool), Field(name: "b", type: .bool)]),
        StructType(name: "Nested", fields: [
            Field(name: "flag", type: .bool), Field(name: "flags", type: .structure(StructID(index: 3, name: "Flags"))),
        ]),
        StructType(name: "Ints", fields: [Field(name: "a", type: .int), Field(name: "b", type: .int)]),
    ])

    private var pairType: RayoType { .structure(StructID(index: 0, name: "Pair")) }
    private var trioID: StructID { StructID(index: 1, name: "Trio") }
    private var trioType: RayoType { .structure(trioID) }
    private var holderID: StructID { StructID(index: 2, name: "Holder") }
    private var holderType: RayoType { .structure(holderID) }
    private var nestedType: RayoType { .structure(StructID(index: 4, name: "Nested")) }
    private var intsID: StructID { StructID(index: 5, name: "Ints") }
    private var intsType: RayoType { .structure(intsID) }

    /// The attributes of a large result's slot, and of a large borrowed argument's place, as LLVM IR writes them.
    private let resultSlot = "ptr dead_on_unwind noalias writable sret(%Trio) align 8"
    private let borrowedPlace = "ptr noalias noundef nonnull readonly align 8 captures(none) dereferenceable(24)"

    /// A `main` that takes nothing, returns nothing and does nothing.
    private var emptyMain: IRFunction {
        mainFunction(locals: [], [BasicBlock(statements: [], terminator: .return(nil))])
    }

    /// `relay(_:)`, which returns the borrowed argument of `type` it is passed.
    private func relaying(_ type: RayoType) -> IRFunction {
        IRFunction(
            name: "relay(_: \(type))", parameterCount: 1, result: type,
            locals: [.source(name: "value", kind: .parameter, type: type)],
            blocks: [BasicBlock(statements: [], terminator: .return(read(0)))],
        )
    }

    /// `make()`, which builds a Trio in a local and returns it.
    private var making: IRFunction {
        let fields: [Operand] = [.constant(.int(1)), .constant(.int(2)), .constant(.bool(true))]
        return IRFunction(
            name: "make()", parameterCount: 0, result: trioType, locals: [.temporary(trioType)],
            blocks: [BasicBlock(
                statements: [statement(storingIn: 0, .structure(trioID, fields: fields))],
                terminator: .return(move(0)),
            )],
        )
    }

    /// An operand that reads the field at `field` of the local `local`.
    private func field(_ field: Int, of local: Int) -> Operand {
        .read(Place(local: LocalID(index: local), fields: [field], range: nowhere))
    }
}

@Suite("The rules that decide how an argument or a result is passed")
struct SignatureLoweringTests {
    @Test func `a small argument passes directly, but a mutable one, which passes as its place`() throws {
        try withModes { mode in
            #expect(mode(.borrowed, .int) == .direct([Scalar(fields: [], type: .int)]))
            #expect(mode(.owned, .int) == .direct([Scalar(fields: [], type: .int)]))
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
