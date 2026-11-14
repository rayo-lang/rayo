import Testing

/// Lowers a `main` that runs `body`, in a program that declares `Enemy`, of a `hp` and then an `armor`, after it, and
/// expects the IR's text to be the snapshot `name.ir`.
private func expectLowering(withEnemy body: String, toMatch name: String) throws {
    try expectLowering(of: "func main() {\n\(body)\n}\nstruct Enemy(var hp: Int, let armor: Int)", toMatch: name)
}

/// Lowers a `main` that runs `body`, in a program that declares a `Shot` of a `range` and a `Hit`, and the `Hit` of a
/// `damage`, after it, and expects the IR's text to be the snapshot `name.ir`.
private func expectLowering(withShot body: String, toMatch name: String) throws {
    let structs = "struct Shot(let range: Int, var hit: Hit)\nstruct Hit(var damage: Int)"
    try expectLowering(of: "func main() {\n\(body)\n}\n\(structs)", toMatch: name)
}

@Suite("Lowering structs")
struct StructLoweringTests {
    @Test func `a struct's value is a call of its primary initializer, which moves a local given bare`() throws {
        try expectLowering(withEnemy: "let hp = 1\nlet e = Enemy(hp: hp, armor: 2)", toMatch: "struct-value")
    }

    @Test func `a field used as an operand is read where it lies in its local`() throws {
        let body = "let e = Enemy(hp: 1, armor: 2)\nprint(-e.armor)\nprint(e.hp)"
        try expectLowering(withEnemy: body, toMatch: "field-read")
    }

    @Test func `a copy of a field reads it where it lies, and leaves its struct whole`() throws {
        let body = "let e = Enemy(hp: 1, armor: 2)\nlet a = copy e.armor\nprint(a + e.hp)"
        try expectLowering(withEnemy: body, toMatch: "field-copy")
    }

    @Test func `a field that a statement takes is moved out of where it lies, in its local or in a temporary`() throws {
        let body = "let e = Enemy(hp: 1, armor: 2)\nlet a = e.armor\n_ = Enemy(hp: 3, armor: 4).hp"
        try expectLowering(withEnemy: body, toMatch: "field-move")
    }

    @Test func `a field of a value that no local holds is read from a temporary that holds the value`() throws {
        try expectLowering(withEnemy: "print(Enemy(hp: 1, armor: 2).hp)", toMatch: "field-of-temporary")
    }

    @Test func `an assignment to a field computes its value into the field's place, and a compound one reads it there`()
        throws {
        let body = "var e = Enemy(hp: 1, armor: 2)\ne.hp = 3\ne.hp -= e.armor\nprint(e.hp)"
        try expectLowering(withEnemy: body, toMatch: "field-assignment")
    }

    @Test func `an assignment to a field inside a field computes its value into the place its fields lead to`() throws {
        let body = "var s = Shot(range: 4, hit: Hit(damage: 7))\ns.hit.damage = 9\nprint(s.range)\nprint(s.hit.damage)"
        try expectLowering(withShot: body, toMatch: "nested-field-assignment")
    }

    @Test func `an array literal makes an array of its elements, in order, each moved where a local is given bare`()
        throws {
        let body = "let e = Enemy(hp: 1, armor: 2)\nlet a = [e, Enemy(hp: 3, armor: 4)]\nlet b = [[1], [2]]"
        try expectLowering(withEnemy: body, toMatch: "array-literal")
    }

    @Test func `.init(all:) fills an array with copies of a value it reads, so a local it names keeps its value`()
        throws {
        let body = "let e = Enemy(hp: 1, armor: 2)\nlet a: [3 of Enemy] = .init(all: e)\n"
            + "let b: [2 of [1 of Int]] = .init(all: .init(all: 5))\nlet c: [0 of Enemy] = .init(all: e)"
        try expectLowering(withEnemy: body, toMatch: "filled-array")
    }

    @Test func `a struct made inside another is computed into a temporary, and a field is read through its fields`()
        throws {
        try expectLowering(withShot: "let s = Shot(range: 4, hit: Hit(damage: 7))\nprint(s.hit.damage)",
                           toMatch: "nested-struct")
    }
}
