/// How a process ended: with an exit code of its own, by a signal, or, on Windows, by an exception.
enum Termination: Equatable, CustomStringConvertible {
    case exited(Int32)
    case signaled(Int32)
    case raisedException(UInt32)

    /// The exception code Windows ends a process by Ctrl-C with.
    static let interruptedCode: UInt32 = 0xC000_013A

    /// How a process ended that Windows reports ended with `code`.
    init(windowsExitCode code: UInt32) {
        switch code >> 28 {
        // A code whose top four bits are an HRESULT failure's (0x8) or an NTSTATUS error's (0xC, 0xE) is the code of
        // the exception that ended the process.
        case 0x8, 0xC, 0xE:
            self = .raisedException(code)
        // Any other code is the process's own, negative where its top bit is set.
        default:
            self = .exited(Int32(bitPattern: code))
        }
    }

    /// The exit code a shell reports for the process: its own, 128 plus the signal that ended it, or the code of the
    /// exception that ended it.
    var exitCode: Int32 {
        switch self {
        case .exited(let exitCode): exitCode
        case .signaled(let signal): 128 + signal
        case .raisedException(let code): Int32(bitPattern: code)
        }
    }

    /// How the process ended, as a phrase that follows its name, such as "was ended by signal 9".
    var description: String {
        switch self {
        case .exited(let exitCode): "exited with \(exitCode)"
        case .signaled(let signal): "was ended by signal \(signal)"
        case .raisedException(Self.interruptedCode): "was interrupted"
        case .raisedException(let code): "crashed with exception 0x" + String(code, radix: 16, uppercase: true)
        }
    }
}
