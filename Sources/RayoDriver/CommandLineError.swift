/// Why the arguments don't make a command `rayoc` can run.
enum CommandLineError: Error {
    case usage
    case unknownLinker(String)

    /// What `rayoc` writes to its standard error for the error.
    var errors: String {
        switch self {
        case .usage: return Self.usageMessage
        case .unknownLinker(let name):
            return "rayoc: unknown linker '\(name)': use --linker=lld or --linker=platform\n"
        }
    }

    private static let usageMessage = """
        usage: rayoc <command> <file>
               rayoc build|run [--debug | --release] [--linker=lld | --linker=platform] <file>

        commands:
          check    check the file and report its errors
          build    compile the file to an executable beside it, named without '.rayo'
          run      compile the file and run it

        build modes:
          --debug    integer overflow panics, and the program isn't optimised
          --release  integer overflow wraps, and the program is optimised; a build that names no mode is a
                     release build

        linkers:
          --linker=lld       LLD, from the LLVM that rayoc was built with; the linker when none is named
          --linker=platform  the platform's own linker

        """
}
