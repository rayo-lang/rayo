/// A program whose `main` assigns its Int local `%0` and then runs `blocks`, and which declares `f(_: &Int)`, which
/// borrows its one Int.
func borrowing(_ blocks: String) -> String {
    """
    main "main()"
    func "main()"() -> Void {
      var %0 x: Int @1:1-1:2
    bb0:
      %0 @1:1-1:2 = operand 1 @1:1-1:2
    \(blocks)
    }
    func "f(_: &Int)"(_: &Int) -> Void
    """
}
