import RayoIR
import RayoStageThread
import Testing

/// The first violation of the IR's rules in `program`, which `stage` gave, that the verifier finds on the stage
/// thread, or nil where it finds none.
func verify(_ program: IRProgram, from stage: IRStage) throws -> IRViolation? {
    try #require(StageThread.run { thread in IRVerifier.verify(program, from: stage, on: thread) })
}

/// The first violation of a rule the emitter takes as given in `program`, which the ownership stage gave, that the
/// verifier finds on the stage thread, or nil where it finds none.
func verifyEmitterRules(_ program: IRProgram) throws -> IRViolation? {
    try #require(StageThread.run { thread in IRVerifier.verifyEmitterRules(program, on: thread) })
}

/// `program` as text, as the printer writes it on the stage thread.
func irText(of program: IRProgram) throws -> String {
    try #require(StageThread.run { thread in IRPrinter.text(of: program, on: thread) })
}
