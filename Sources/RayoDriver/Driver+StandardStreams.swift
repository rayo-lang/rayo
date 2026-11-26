#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Darwin)
import Darwin
#endif

extension Driver {
    /// Opens the null device onto each of standard input, output and error that `rayo` started without, so that the
    /// processes it runs get the null device for that stream. It runs before anything else opens a file.
    public static func openMissingStandardStreams() {
        #if !os(Windows)
        // Each file opened takes the lowest free descriptor, so a file opened later would take a missing stream's,
        // and a process run on that stream would get the file. Windows numbers no handle in a missing one's place.
        for stream: Int32 in 0...2 where fcntl(stream, F_GETFD) == -1 && errno == EBADF {
            let nullDevice = open("/dev/null", O_RDWR)
            guard nullDevice != -1 else { continue }
            if nullDevice != stream {
                dup2(nullDevice, stream)
                close(nullDevice)
            }
        }
        #endif
    }
}
