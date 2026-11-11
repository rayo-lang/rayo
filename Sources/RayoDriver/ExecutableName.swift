/// The file name of the host's executable `name`: on Windows with `.exe`, which it needs to run, and elsewhere
/// `name` itself.
func executableName(_ name: String) -> String {
    #if os(Windows)
    name + ".exe"
    #else
    name
    #endif
}
