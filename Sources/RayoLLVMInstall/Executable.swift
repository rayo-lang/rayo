/// How the host names the executables Rayo's tools run.
public enum Executable {
    /// The file name of the executable `name`: on Windows with `.exe`, which it needs to run, and elsewhere `name`
    /// itself.
    public static func fileName(_ name: String) -> String {
        #if os(Windows)
        name + ".exe"
        #else
        name
        #endif
    }
}
