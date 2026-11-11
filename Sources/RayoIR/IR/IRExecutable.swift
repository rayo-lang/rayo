import RayoSema

/// A program that an executable can be built from: Rayo IR with the function a run of it starts at.
public struct IRExecutable: Equatable, Sendable {
    public let program: IRProgram
    public let main: FunctionID

    /// Returns `program` as an executable, or nil for a library, which has no `main` to start at.
    public init?(_ program: IRProgram) {
        guard let main = program.main else { return nil }
        self.program = program
        self.main = main
    }
}
