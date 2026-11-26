import RayoCheckedProgram
import RayoDiagnostics
import Testing

/// A struct's type, which isn't implicitly copyable.
private let enemy = RayoType.named(.structure(StructID(index: 0, name: "Enemy")))

/// An array's type, which isn't implicitly copyable either.
private let pair = RayoType.array(count: 2, element: .int)

/// The place `boss`, of `type`, in a local of `kind`, or in a temporary where `kind` is nil, as a position is given it.
private func boss(_ type: RayoType, in kind: LocalKind? = .let, liesInElement: Bool = false) -> GivenPlace {
    GivenPlace(type: type, source: MoveSource(local: kind, liesInElement: liesInElement),
               spelling: { "boss" }, typeName: { TypeName(stringLiteral: "\(type)") })
}

/// The argument of a parameter of `convention`, which `kind` declares, of a function the call names `keep`. The flag
/// says whether another function of that name, which the call's arguments fit, borrows the argument.
private func argument(_ convention: ParameterConvention, of kind: ParameterKind = .function,
                      lendable: Bool = false) -> Position {
    .argument(ArgumentParameter(callee: "keep", convention: convention, kind: kind, borrowsTemporaries: false,
                                isBorrowedByOverload: lendable))
}

/// What `position` does with a value that no local holds, which lies in the temporary `makeBoss()`.
private func takingValue(by position: Position) -> ValueTaking {
    position.takingValue(heldBy: { "makeBoss()" })
}

/// Every position: the argument of each kind of parameter with each convention, and each other case once for each
/// payload it takes.
private let everyPosition: [Position] = ParameterKind.allCases.flatMap { kind in
    ParameterConvention.allCases.map { argument($0, of: kind) }
} + [
    .ownerDeclaration(keyword: "let"), .ownerDeclaration(keyword: "var"), .referenceDeclaration,
    .mutableReferenceDeclaration, .unnamedDeclaration, .assignment, .drop, .returned, .arrayElement, .statement,
    .operand,
]

/// A position's case, without its payload. The switch names every case of `Position`, so a case added to it fails to
/// compile here until it is named, and a test then checks that `everyPosition` lists it.
private enum PositionCase: CaseIterable {
    case argument, ownerDeclaration, referenceDeclaration, mutableReferenceDeclaration, unnamedDeclaration
    case assignment, drop, returned, arrayElement, statement, operand

    init(_ position: Position) {
        self = switch position {
        case .argument: .argument
        case .ownerDeclaration: .ownerDeclaration
        case .referenceDeclaration: .referenceDeclaration
        case .mutableReferenceDeclaration: .mutableReferenceDeclaration
        case .unnamedDeclaration: .unnamedDeclaration
        case .assignment: .assignment
        case .drop: .drop
        case .returned: .returned
        case .arrayElement: .arrayElement
        case .statement: .statement
        case .operand: .operand
        }
    }
}

@Suite struct `Every position` {
    @Test func `is among those the tests give a place to`() {
        #expect(Set(everyPosition.map(PositionCase.init)) == Set(PositionCase.allCases))
    }
}

@Suite struct `A place of an implicitly copyable type` {
    @Test(arguments: [
        argument(.owned), argument(.owned, of: .repeatedElement),
        .ownerDeclaration(keyword: "let"), .ownerDeclaration(keyword: "var"), .unnamedDeclaration, .assignment, .drop,
        .returned, .arrayElement, .statement, .operand,
    ] as [Position])
    func `is copied where a position takes or reads its value`(_ position: Position) {
        #expect(position.taking(boss(.int)) == PlaceTaking(use: .copy))
        #expect(position.taking(boss(.bool, in: .parameter(.borrowed))) == PlaceTaking(use: .copy))
    }

    @Test func `is lent to a borrowing parameter`() {
        #expect(argument(.borrowed).taking(boss(.int)) == PlaceTaking(use: .lend))
    }

    @Test func `is reported where a parameter borrows it for change`() {
        let error = PlaceError(.unmarkedMutableLend(name: "keep", type: "mutable &Int", place: "boss"))
        #expect(argument(.mutable).taking(boss(.int)) == PlaceTaking(use: nil, error: error))
    }

    @Test func `is borrowed by a 'ref let', which reports its missing '&' and keeps its meaning`() {
        let error = PlaceError(.unreferencedPlace(place: "boss"), keepsMeaning: true)
        #expect(Position.referenceDeclaration.taking(boss(.int)) == PlaceTaking(use: .borrow, error: error))
    }

    @Test func `is borrowed by a 'ref var'`() {
        #expect(Position.mutableReferenceDeclaration.taking(boss(.int)) == PlaceTaking(use: .borrow))
    }
}

@Suite struct `A place of a struct or an array type` {
    @Test(arguments: [enemy, pair])
    func `is lent to a borrowing parameter`(_ type: RayoType) {
        #expect(argument(.borrowed).taking(boss(type)) == PlaceTaking(use: .lend))
    }

    @Test(arguments: [enemy, pair])
    func `is reported where a parameter borrows it for change`(_ type: RayoType) {
        let error = PlaceError(.unmarkedMutableLend(name: "keep", type: "mutable &\(type)", place: "boss"))
        #expect(argument(.mutable).taking(boss(type)) == PlaceTaking(use: nil, error: error))
    }

    @Test(arguments: [enemy, pair])
    func `given to an owning parameter names 'consume' and 'copy' where code may move out of it`(_ type: RayoType) {
        let marks = PlaceMarks("boss", mayMove: true, mayLend: false)
        let error = PlaceError(.unmarkedOwnedArgument(name: "keep", type: .named("\(type)"), marks: marks))
        #expect(argument(.owned).taking(boss(type, in: .var)) == PlaceTaking(use: .move, error: error))
    }

    @Test func `given to an owning parameter names 'copy' alone where code can't move out of it`() {
        let marks = PlaceMarks("boss", mayMove: false, mayLend: false)
        let error = PlaceError(.unmarkedOwnedArgument(name: "keep", type: "Enemy", marks: marks))
        let taking = PlaceTaking(use: .move, error: error)
        #expect(argument(.owned).taking(boss(enemy, in: .parameter(.borrowed))) == taking)
        #expect(argument(.owned).taking(boss(enemy, liesInElement: true)) == taking)
    }

    @Test func `given to an owning parameter names '&' where another function of its name borrows it`() {
        let marks = PlaceMarks("boss", mayMove: true, mayLend: true)
        let error = PlaceError(.unmarkedOwnedArgument(name: "keep", type: "Enemy", marks: marks))
        #expect(argument(.owned, lendable: true).taking(boss(enemy)) == PlaceTaking(use: .move, error: error))
    }

    @Test(arguments: [enemy, pair])
    func `is lent to '.init(repeating:)', which copies it into each element`(_ type: RayoType) {
        #expect(argument(.owned, of: .repeatedElement).taking(boss(type)) == PlaceTaking(use: .lend))
    }

    @Test(arguments: ["let", "var"])
    func `given to a 'let' or a 'var' is reported`(_ keyword: String) {
        let taking = PlaceTaking(use: .move, error: PlaceError(.ownerBorrowsPlace(keyword: keyword, place: "boss")))
        #expect(Position.ownerDeclaration(keyword: keyword).taking(boss(enemy)) == taking)
        #expect(Position.ownerDeclaration(keyword: keyword).taking(boss(pair)) == taking)
    }

    @Test(arguments: [enemy, pair])
    func `is borrowed by a 'ref let', which reports its missing '&' and keeps its meaning`(_ type: RayoType) {
        let error = PlaceError(.unreferencedPlace(place: "boss"), keepsMeaning: true)
        #expect(Position.referenceDeclaration.taking(boss(type)) == PlaceTaking(use: .borrow, error: error))
    }

    @Test(arguments: [enemy, pair])
    func `is borrowed by a 'ref var'`(_ type: RayoType) {
        #expect(Position.mutableReferenceDeclaration.taking(boss(type)) == PlaceTaking(use: .borrow))
    }

    @Test(arguments: [Position.assignment, .drop])
    func `given to '=' or '_ =' names the marks that fit`(_ position: Position) {
        let movable = PlaceError(.assignmentBorrowsPlace(marks: PlaceMarks("boss", mayMove: true, mayLend: false)))
        let unmovable = PlaceError(.assignmentBorrowsPlace(marks: PlaceMarks("boss", mayMove: false, mayLend: false)))
        #expect(position.taking(boss(enemy)) == PlaceTaking(use: .move, error: movable))
        #expect(position.taking(boss(pair, in: .refLet)) == PlaceTaking(use: .move, error: unmovable))
    }

    @Test(arguments: [enemy, pair])
    func `given to 'return' names 'consume' and 'copy' where code may move out of it`(_ type: RayoType) {
        let marks = PlaceMarks("boss", mayMove: true, mayLend: false)
        let error = PlaceError(.unmarkedReturnedPlace(type: .named("\(type)"), marks: marks))
        #expect(Position.returned.taking(boss(type, in: .parameter(.owned))) == PlaceTaking(use: .move, error: error))
    }

    @Test func `given to 'return' names 'copy' alone where code can't move out of it`() {
        let marks = PlaceMarks("boss", mayMove: false, mayLend: false)
        let error = PlaceError(.unmarkedReturnedPlace(type: "Enemy", marks: marks))
        let taking = PlaceTaking(use: .move, error: error)
        #expect(Position.returned.taking(boss(enemy, in: .parameter(.borrowed))) == taking)
    }

    @Test(arguments: [enemy, pair])
    func `given to an array literal's element names 'consume' and 'copy' where code may move out of it`(
        _ type: RayoType,
    ) {
        let marks = PlaceMarks("boss", mayMove: true, mayLend: false)
        let error = PlaceError(.unmarkedArrayElement(type: .named("\(type)"), marks: marks))
        #expect(Position.arrayElement.taking(boss(type, in: .var)) == PlaceTaking(use: .move, error: error))
    }

    @Test func `given to an array literal's element names 'copy' alone where code can't move out of it`() {
        let marks = PlaceMarks("boss", mayMove: false, mayLend: false)
        let error = PlaceError(.unmarkedArrayElement(type: "Enemy", marks: marks))
        #expect(Position.arrayElement.taking(boss(enemy, liesInElement: true)) == PlaceTaking(use: .move, error: error))
    }

    @Test(arguments: [enemy, pair])
    func `is lent where a position only reads its value`(_ type: RayoType) {
        #expect(Position.statement.taking(boss(type)) == PlaceTaking(use: .lend))
        #expect(Position.operand.taking(boss(type)) == PlaceTaking(use: .lend))
    }

    @Test(arguments: [enemy, pair])
    func `given to a declaration of '_' is lent, since nothing takes it`(_ type: RayoType) {
        #expect(Position.unnamedDeclaration.taking(boss(type)) == PlaceTaking(use: .lend))
    }

    @Test(arguments: everyPosition)
    func `is never moved without a mark`(_ position: Position) {
        let taking = position.taking(boss(enemy))
        #expect(taking.use != .move || taking.error != nil)
    }
}

@Suite struct `A place in a temporary` {
    @Test(arguments: everyPosition)
    func `reports no mark, since it is a value that dies with its statement`(_ position: Position) {
        #expect(position.taking(boss(enemy, in: nil)).error == nil)
        #expect(position.taking(boss(.int, in: nil)).error == nil)
    }

    @Test func `is taken as the position takes a value`() {
        #expect(argument(.owned).taking(boss(enemy, in: nil)) == PlaceTaking(use: .move))
        #expect(Position.ownerDeclaration(keyword: "let").taking(boss(enemy, in: nil)) == PlaceTaking(use: .move))
        #expect(Position.assignment.taking(boss(enemy, in: nil)) == PlaceTaking(use: .move))
        #expect(argument(.borrowed).taking(boss(enemy, in: nil)) == PlaceTaking(use: .lend))
        #expect(Position.drop.taking(boss(.int, in: nil)) == PlaceTaking(use: .copy))
    }

    @Test func `is refused where a parameter borrows it for change`() {
        #expect(argument(.mutable).taking(boss(enemy, in: nil)) == PlaceTaking(use: nil))
    }
}

@Suite struct `A value that no local holds` {
    @Test(arguments: ParameterKind.allCases)
    func `is refused by a parameter that borrows it for change, which would change only its temporary`(
        _ kind: ParameterKind,
    ) {
        #expect(takingValue(by: argument(.mutable, of: kind)) == .refused(.assignToTemporary(temporary: "makeBoss()")))
    }

    @Test func `is reported where a parameter that borrows it isn't lent temporaries`() {
        #expect(takingValue(by: argument(.borrowed)) == .takes(reporting: .unsupportedLentValue))
    }

    @Test func `is lent to a parameter that borrows temporaries, as a built-in's does`() {
        let builtin = ArgumentParameter(callee: "print", convention: .borrowed, kind: .function,
                                        borrowsTemporaries: true, isBorrowedByOverload: false)
        #expect(takingValue(by: .argument(builtin)) == .takes(reporting: nil))
    }

    @Test func `is reported by a 'ref let', which has no place to refer to`() {
        #expect(takingValue(by: .referenceDeclaration) == .takes(reporting: .referenceToValue))
    }

    @Test(arguments: everyPosition.filter {
        switch $0 {
        case .argument(let parameter): parameter.convention == .owned
        case .referenceDeclaration: false
        default: true
        }
    })
    func `is taken as it stands by any other position`(_ position: Position) {
        #expect(takingValue(by: position) == .takes(reporting: nil))
    }
}

@Suite struct `The mark that drops a place` {
    @Test func `is '_ =' alone for a place of an implicitly copyable type`() {
        #expect(boss(.int).dropMark == .bare)
        #expect(boss(.uint, in: .parameter(.borrowed)).dropMark == .bare)
    }

    @Test(arguments: [enemy, pair])
    func `is '_ = consume' where code may move out of the place`(_ type: RayoType) {
        #expect(boss(type).dropMark == .consume)
        #expect(boss(type, in: .parameter(.owned)).dropMark == .consume)
    }

    @Test(arguments: [enemy, pair])
    func `is '_ = copy' where code can't move out of the place`(_ type: RayoType) {
        #expect(boss(type, in: .parameter(.borrowed)).dropMark == .copy)
        #expect(boss(type, liesInElement: true).dropMark == .copy)
    }

    @Test func `is '_ =' alone for a place in a temporary`() {
        #expect(boss(enemy, in: nil).dropMark == .bare)
    }
}
