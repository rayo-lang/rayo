import RayoIR
import RayoSema
import Testing

/// The struct the tests make and read, whose fields are `hp` and then `armor`.
private let enemy = StructID(index: 0, name: "Enemy")

/// The IR of a `main` that runs `body`, in a program that declares `Enemy` after it.
private func loweredMain(withEnemy body: String) throws(RejectedSource) -> IRBody {
    // `main` is the program's one function.
    try lowered("func main() {\n\(body)\n}\nstruct Enemy(var hp: Int, let armor: Int)").body(at: 0)
}

@Suite("Lowering structs")
struct StructLoweringTests {
    @Test func `a struct's value is made of its fields' values, and a local given as one is moved`()
        throws(RejectedSource) {
        let main = try loweredMain(withEnemy: "let hp = 1\nlet e = Enemy(hp: hp, armor: 2)")
        let expected = mainFunction(
            locals: [letLocal("hp", .int), letLocal("e", .structure(enemy))],
            block(
                declare(0), compute(0, .use(int(1))),
                declare(1), compute(1, .structure(enemy, fields: [move(0), int(2)])),
                then: .return(nil),
            ),
        )
        #expect(main == expected)
    }

    @Test func `a field used as an operand is read where it lies in its local`() throws(RejectedSource) {
        let main = try loweredMain(withEnemy: "let e = Enemy(hp: 1, armor: 2)\nprint(-e.armor)\nprint(e.hp)")
        let expected = mainFunction(
            locals: [letLocal("e", .structure(enemy)), .temporary(.int)],
            block(
                declare(0), compute(0, .structure(enemy, fields: [int(1), int(2)])),
                compute(1, .unary(.negate, read(0, fields: 1))),
                compute(nil, .call(.builtin(.printInt), arguments: [read(1)])),
                compute(nil, .call(.builtin(.printInt), arguments: [read(0, fields: 0)])),
                then: .return(nil),
            ),
        )
        #expect(main == expected)
    }

    @Test func `a copy of a field reads it where it lies, and leaves its struct whole`() throws(RejectedSource) {
        let main = try loweredMain(withEnemy: "let e = Enemy(hp: 1, armor: 2)\nlet a = copy e.armor\nprint(a + e.hp)")
        let expected = mainFunction(
            locals: [letLocal("e", .structure(enemy)), letLocal("a", .int), .temporary(.int)],
            block(
                declare(0), compute(0, .structure(enemy, fields: [int(1), int(2)])),
                declare(1), compute(1, .use(read(0, fields: 1))),
                compute(2, .binary(.add, read(1), read(0, fields: 0))),
                compute(nil, .call(.builtin(.printInt), arguments: [read(2)])),
                then: .return(nil),
            ),
        )
        #expect(main == expected)
    }

    @Test func `a field that a statement takes is moved out of where it lies, in its local or in a temporary`()
        throws(RejectedSource) {
        let body = "let e = Enemy(hp: 1, armor: 2)\nlet a = e.armor\n_ = Enemy(hp: 3, armor: 4).hp"
        let main = try loweredMain(withEnemy: body)
        let expected = mainFunction(
            locals: [letLocal("e", .structure(enemy)), letLocal("a", .int), .temporary(.structure(enemy))],
            block(
                declare(0), compute(0, .structure(enemy, fields: [int(1), int(2)])),
                declare(1), compute(1, .use(move(0, fields: 1))),
                compute(2, .structure(enemy, fields: [int(3), int(4)])),
                compute(nil, .use(move(2, fields: 0))),
                then: .return(nil),
            ),
        )
        #expect(main == expected)
    }

    @Test func `a field of a value that no local holds is read from a temporary that holds the value`()
        throws(RejectedSource) {
        let main = try loweredMain(withEnemy: "print(Enemy(hp: 1, armor: 2).hp)")
        let expected = mainFunction(
            locals: [.temporary(.structure(enemy))],
            block(
                compute(0, .structure(enemy, fields: [int(1), int(2)])),
                compute(nil, .call(.builtin(.printInt), arguments: [read(0, fields: 0)])),
                then: .return(nil),
            ),
        )
        #expect(main == expected)
    }

    @Test func `an assignment to a field computes its value into the field's place, and a compound one reads it there`()
        throws(RejectedSource) {
        let main = try loweredMain(withEnemy: "var e = Enemy(hp: 1, armor: 2)\ne.hp = 3\ne.hp -= e.armor\nprint(e.hp)")
        let expected = mainFunction(
            locals: [varLocal("e", .structure(enemy))],
            block(
                declare(0), compute(0, .structure(enemy, fields: [int(1), int(2)])),
                compute(0, fields: 0, value: .use(int(3))),
                compute(0, fields: 0, value: .binary(.subtract, read(0, fields: 0), read(0, fields: 1))),
                compute(nil, .call(.builtin(.printInt), arguments: [read(0, fields: 0)])),
                then: .return(nil),
            ),
        )
        #expect(main == expected)
    }

    @Test func `an assignment to a field inside a field computes its value into the place its fields lead to`()
        throws(RejectedSource) {
        let source = """
            func main() {
                var s = Shot(range: 4, hit: Hit(damage: 7))
                s.hit.damage = 9
                print(s.range)
                print(s.hit.damage)
            }
            struct Shot(let range: Int, var hit: Hit)
            struct Hit(var damage: Int)
            """
        let main = try lowered(source).body(at: 0)

        let shot = StructID(index: 0, name: "Shot")
        let hit = StructID(index: 1, name: "Hit")
        let expected = mainFunction(
            locals: [varLocal("s", .structure(shot)), .temporary(.structure(hit))],
            block(
                declare(0),
                compute(1, .structure(hit, fields: [int(7)])),
                compute(0, .structure(shot, fields: [int(4), read(1)])),
                // `Shot` declares its `Hit` second, and `Hit` its `damage` first.
                compute(0, fields: 1, 0, value: .use(int(9))),
                compute(nil, .call(.builtin(.printInt), arguments: [read(0, fields: 0)])),
                compute(nil, .call(.builtin(.printInt), arguments: [read(0, fields: 1, 0)])),
                then: .return(nil),
            ),
        )
        #expect(main == expected)
    }

    @Test func `a struct made inside another is computed into a temporary, and a field is read through its fields`()
        throws(RejectedSource) {
        let source = """
            func main() {
                let s = Shot(range: 4, hit: Hit(damage: 7))
                print(s.hit.damage)
            }
            struct Shot(let range: Int, var hit: Hit)
            struct Hit(var damage: Int)
            """
        let main = try lowered(source).body(at: 0)

        let shot = StructID(index: 0, name: "Shot")
        let hit = StructID(index: 1, name: "Hit")
        let expected = mainFunction(
            locals: [letLocal("s", .structure(shot)), .temporary(.structure(hit))],
            block(
                declare(0),
                compute(1, .structure(hit, fields: [int(7)])),
                compute(0, .structure(shot, fields: [int(4), read(1)])),
                // `Shot` declares its `Hit` second, and `Hit` its `damage` first.
                compute(nil, .call(.builtin(.printInt), arguments: [read(0, fields: 1, 0)])),
                then: .return(nil),
            ),
        )
        #expect(main == expected)
    }
}
