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

/// What `position` does with `place`, as a test compares it: the use and the error.
private func taking(_ place: GivenPlace, by position: Position) -> (use: PlaceUse?, error: PlaceError?) {
    let taking = position.taking(place)
    return (taking.use, taking.error)
}

/// Every position the compiler builds, each with a name for the test's arguments.
private let everyPosition: [(String, Position)] = [
    ("a borrowing parameter", argument(.borrowed)),
    ("an owning parameter", argument(.owned)),
    ("a parameter that borrows for change", argument(.mutable)),
    ("a struct's primary initializer", argument(.owned, of: .field)),
    ("'.init(repeating:)'", argument(.owned, of: .repeatedElement)),
    ("a 'let'", .ownerDeclaration(keyword: "let")),
    ("a 'var'", .ownerDeclaration(keyword: "var")),
    ("a 'ref let'", .referenceDeclaration),
    ("a 'ref var'", .mutableReferenceDeclaration),
    ("a declaration of '_'", .unnamedDeclaration),
    ("'='", .assignment),
    ("'_ ='", .drop),
    ("'return'", .returned),
    ("an array literal's element", .arrayElement),
    ("an expression statement", .statement),
    ("an operand", .operand),
]

@Suite struct `A place of an implicitly copyable type` {
    @Test(arguments: [
        ("an owning parameter", argument(.owned)),
        ("a struct's primary initializer", argument(.owned, of: .field)),
        ("'.init(repeating:)'", argument(.owned, of: .repeatedElement)),
        ("a 'let'", .ownerDeclaration(keyword: "let")),
        ("a 'var'", .ownerDeclaration(keyword: "var")),
        ("a declaration of '_'", .unnamedDeclaration),
        ("'='", .assignment),
        ("'_ ='", .drop),
        ("'return'", .returned),
        ("an array literal's element", .arrayElement),
        ("an expression statement", .statement),
        ("an operand", .operand),
    ] as [(String, Position)])
    func `is copied where a position takes or reads its value`(_ name: String, _ position: Position) {
        #expect(taking(boss(.int), by: position) == (.copy, nil))
        #expect(taking(boss(.bool, in: .parameter(.borrowed)), by: position) == (.copy, nil))
    }

    @Test func `is lent to a borrowing parameter`() {
        #expect(taking(boss(.int), by: argument(.borrowed)) == (.lend, nil))
    }

    @Test func `is reported where a parameter borrows it for change`() {
        let error = PlaceError(.unmarkedMutableLend(name: "keep", type: "mutable &Int", place: "boss"))
        #expect(taking(boss(.int), by: argument(.mutable)) == (nil, error))
    }

    @Test func `is borrowed by a 'ref let', which reports its missing '&' and keeps its meaning`() {
        let error = PlaceError(.unreferencedPlace(place: "boss"), keepsMeaning: true)
        #expect(taking(boss(.int), by: .referenceDeclaration) == (.borrow, error))
    }

    @Test func `is borrowed by a 'ref var'`() {
        #expect(taking(boss(.int), by: .mutableReferenceDeclaration) == (.borrow, nil))
    }
}

@Suite struct `A place of a struct or an array type` {
    @Test(arguments: [enemy, pair])
    func `is lent to a borrowing parameter`(_ type: RayoType) {
        #expect(taking(boss(type), by: argument(.borrowed)) == (.lend, nil))
    }

    @Test(arguments: [enemy, pair])
    func `is reported where a parameter borrows it for change`(_ type: RayoType) {
        let error = PlaceError(.unmarkedMutableLend(name: "keep", type: "mutable &\(type)", place: "boss"))
        #expect(taking(boss(type), by: argument(.mutable)) == (nil, error))
    }

    @Test(arguments: [enemy, pair])
    func `given to an owning parameter names 'consume' and 'copy' where code may move out of it`(_ type: RayoType) {
        let marks = PlaceMarks("boss", mayMove: true, mayLend: false)
        let error = PlaceError(.unmarkedOwnedArgument(name: "keep", type: .named("\(type)"), marks: marks))
        #expect(taking(boss(type, in: .var), by: argument(.owned)) == (.move, error))
    }

    @Test func `given to an owning parameter names 'copy' alone where code can't move out of it`() {
        let marks = PlaceMarks("boss", mayMove: false, mayLend: false)
        let error = PlaceError(.unmarkedOwnedArgument(name: "keep", type: "Enemy", marks: marks))
        #expect(taking(boss(enemy, in: .parameter(.borrowed)), by: argument(.owned)) == (.move, error))
        #expect(taking(boss(enemy, liesInElement: true), by: argument(.owned)) == (.move, error))
    }

    @Test func `given to an owning parameter names '&' where another function of its name borrows it`() {
        let marks = PlaceMarks("boss", mayMove: true, mayLend: true)
        let error = PlaceError(.unmarkedOwnedArgument(name: "keep", type: "Enemy", marks: marks))
        #expect(taking(boss(enemy), by: argument(.owned, lendable: true)) == (.move, error))
    }

    @Test(arguments: [enemy, pair])
    func `is moved into a struct's primary initializer`(_ type: RayoType) {
        #expect(taking(boss(type), by: argument(.owned, of: .field)) == (.move, nil))
    }

    @Test(arguments: [enemy, pair])
    func `is lent to '.init(repeating:)', which copies it into each element`(_ type: RayoType) {
        #expect(taking(boss(type), by: argument(.owned, of: .repeatedElement)) == (.lend, nil))
    }

    @Test(arguments: ["let", "var"])
    func `given to a 'let' or a 'var' is reported`(_ keyword: String) {
        let error = PlaceError(.ownerBorrowsPlace(keyword: keyword, place: "boss"))
        #expect(taking(boss(enemy), by: .ownerDeclaration(keyword: keyword)) == (.move, error))
        #expect(taking(boss(pair), by: .ownerDeclaration(keyword: keyword)) == (.move, error))
    }

    @Test(arguments: [enemy, pair])
    func `is borrowed by a 'ref let', which reports its missing '&' and keeps its meaning`(_ type: RayoType) {
        let error = PlaceError(.unreferencedPlace(place: "boss"), keepsMeaning: true)
        #expect(taking(boss(type), by: .referenceDeclaration) == (.borrow, error))
    }

    @Test(arguments: [enemy, pair])
    func `is borrowed by a 'ref var'`(_ type: RayoType) {
        #expect(taking(boss(type), by: .mutableReferenceDeclaration) == (.borrow, nil))
    }

    @Test(arguments: [Position.assignment, .drop])
    func `given to '=' or '_ =' names the marks that fit`(_ position: Position) {
        let movable = PlaceError(.assignmentBorrowsPlace(marks: PlaceMarks("boss", mayMove: true, mayLend: false)))
        let unmovable = PlaceError(.assignmentBorrowsPlace(marks: PlaceMarks("boss", mayMove: false, mayLend: false)))
        #expect(taking(boss(enemy), by: position) == (.move, movable))
        #expect(taking(boss(pair, in: .refLet), by: position) == (.move, unmovable))
    }

    @Test(arguments: [enemy, pair])
    func `is moved by 'return' and by an array literal's element`(_ type: RayoType) {
        #expect(taking(boss(type), by: .returned) == (.move, nil))
        #expect(taking(boss(type), by: .arrayElement) == (.move, nil))
    }

    @Test(arguments: [enemy, pair])
    func `is lent where a position only reads its value`(_ type: RayoType) {
        #expect(taking(boss(type), by: .statement) == (.lend, nil))
        #expect(taking(boss(type), by: .operand) == (.lend, nil))
    }

    @Test(arguments: [enemy, pair])
    func `given to a declaration of '_' is lent, since nothing takes it`(_ type: RayoType) {
        #expect(taking(boss(type), by: .unnamedDeclaration) == (.lend, nil))
    }

    @Test(arguments: everyPosition)
    func `moves unreported only where its position takes the value as its own`(_ name: String, _ position: Position) {
        // A struct's primary initializer, `return` and an array literal's element take the value as their own.
        let takesAsItsOwn = switch position {
        case .argument(let parameter): parameter.kind == .field
        case .returned, .arrayElement: true
        default: false
        }
        let (use, error) = taking(boss(enemy), by: position)
        #expect(use != .move || error != nil || takesAsItsOwn)
    }
}

@Suite struct `A place in a temporary` {
    @Test(arguments: everyPosition)
    func `reports no mark, since it is a value that dies with its statement`(_ name: String, _ position: Position) {
        #expect(taking(boss(enemy, in: nil), by: position).error == nil)
        #expect(taking(boss(.int, in: nil), by: position).error == nil)
    }

    @Test func `is taken as the position takes a value`() {
        #expect(taking(boss(enemy, in: nil), by: argument(.owned)) == (.move, nil))
        #expect(taking(boss(enemy, in: nil), by: .ownerDeclaration(keyword: "let")) == (.move, nil))
        #expect(taking(boss(enemy, in: nil), by: .assignment) == (.move, nil))
        #expect(taking(boss(enemy, in: nil), by: argument(.borrowed)) == (.lend, nil))
        #expect(taking(boss(.int, in: nil), by: .drop) == (.copy, nil))
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

/// Two takings compare by their use and their error.
private func == (left: (use: PlaceUse?, error: PlaceError?), right: (PlaceUse?, PlaceError?)) -> Bool {
    left.use == right.0 && left.error == right.1
}
