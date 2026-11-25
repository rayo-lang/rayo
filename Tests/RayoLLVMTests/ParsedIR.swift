import RayoIR
import RayoStageThread
import Testing

/// The executable that `text` writes as Rayo IR. Throws where the text isn't Rayo IR or breaks the IR's types, and
/// fails the test where it names no function a run starts at.
func executable(_ text: String) throws -> IRExecutable {
    let program = try IRParser.program(from: text)
    let violation = try #require(StageThread.run { thread in IRVerifier.verify(program, from: .ownership, on: thread) })
    if let violation { throw violation }
    return try #require(IRExecutable(program))
}

/// The executable whose `main` computes `value`, an Int, into a temporary and prints it.
func printing(_ value: String) throws -> IRExecutable {
    try executable("""
        main "main()"
        func "main()"() -> Void {
          temp %0: Int
        bb0:
          %0 @1:1-1:2 = \(value) @1:1-1:2
          begin a0 read %0 @1:1-1:2
          _ = call builtin "print(_: &Int)"(a0) @1:1-1:2
          end a0
          return
        }
        """)
}

/// A `main` that takes nothing, returns nothing and does nothing, named as the function a run starts at.
let emptyMain = """
    main "main()"
    func "main()"() -> Void {
    bb0:
      return
    }
    """
