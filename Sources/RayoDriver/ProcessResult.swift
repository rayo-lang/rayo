/// How a process that ran to its end exited, and what it wrote to its standard output and error.
struct ProcessResult {
    var exitCode: Int32
    var output: String
    var errors: String
}
