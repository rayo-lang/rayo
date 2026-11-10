/// What the arguments ask `rayoc` to do.
struct Invocation {
    var command: Command
    var mode: BuildMode
    var linker: Linker
    /// The source file the command works on.
    var path: String

    /// The invocation that `arguments`, which exclude the program's name, ask for. Throws when they don't make a
    /// command `rayoc` can run.
    init(_ arguments: [String]) throws(CommandLineError) {
        // Arguments that start with no command `rayoc` has are wrong whatever follows.
        guard let command = arguments.first.flatMap(Command.init(rawValue:)) else { throw .usage }

        // Read the options before the file, each at most once; `check` takes none.
        var operands = arguments.dropFirst()
        var mode: BuildMode?
        var linker: Linker?
        while command != .check, operands.count > 1, let option = operands.first {
            if let newMode = BuildMode(rawValue: option), mode == nil {
                // The first build mode named is the build's.
                mode = newMode
            } else if let name = Self.value(of: option, named: "--linker"), linker == nil {
                // The first `--linker=` names the linker, which has to be one `rayoc` knows.
                guard let newLinker = Linker(rawValue: name) else { throw .unknownLinker(name) }
                linker = newLinker
            } else {
                // An option `rayoc` doesn't have, or one named twice, makes the arguments wrong.
                throw .usage
            }
            operands = operands.dropFirst()
        }

        // The options have to leave exactly one file.
        guard operands.count == 1, let path = operands.first, !Self.isOption(path) else { throw .usage }

        // A build that names no mode is a release build, and one that names no linker links with LLD.
        self.command = command
        self.mode = mode ?? .release
        self.linker = linker ?? .lld
        self.path = path
    }

    /// Whether `operand` is spelled as one of `rayoc`'s options, a bare `--linker` among them.
    private static func isOption(_ operand: String) -> Bool {
        BuildMode(rawValue: operand) != nil || operand == "--linker" || value(of: operand, named: "--linker") != nil
    }

    /// The value that `option` gives when it is spelled `name=value`, and otherwise nil.
    private static func value(of option: String, named name: String) -> String? {
        option.hasPrefix(name + "=") ? String(option.dropFirst(name.count + 1)) : nil
    }

    /// What `rayoc` does with the file.
    enum Command: String {
        case check, build, run
    }

    /// A build's mode, which turns the diagnostic checks on and optimisation off in a debug build, and the other way
    /// round in a release one.
    enum BuildMode: String {
        case debug = "--debug"
        case release = "--release"
    }
}
