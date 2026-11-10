import Foundation
import RayoLLVM

/// The host tools that link object code into an executable, and run the executable they link.
struct Toolchain {
    var tools: LinkTools
    var linker: Linker
    /// Runs clang, the platform's tools and the linked program.
    var processes: ProcessRunner

    /// Links `objectCode` with the C library into an executable at `output`.
    func link(_ objectCode: [UInt8], to output: URL) throws {
        // Without clang there is nothing to link with.
        guard Self.isExecutableFile(tools.clang) else { throw Failure("can't find clang at '\(tools.clang.path)'") }

        // Write the object code to a file of its own, and have clang link it with the linker's arguments.
        let linkerArguments = try linkerArguments()
        let result = try TemporaryDirectory.withNew { directory in
            let object = directory.appendingPathComponent("program.o")
            try Data(objectCode).write(to: object)
            let arguments = linkerArguments + [object.path, "-o", output.path]
            return try processes.runCapturingOutput(tools.clang, arguments: arguments)
        }

        // A failed link reports what clang wrote, less the final newline that `rayoc`'s report ends with anyway.
        guard result.exitCode == 0 else {
            let errors = result.errors.hasSuffix("\n") ? String(result.errors.dropLast()) : result.errors
            throw Failure("clang failed:\n\(errors)")
        }
    }

    /// Links `objectCode` into an executable, runs it with its output sent where `output` says, and removes it.
    func linkAndRun(_ objectCode: [UInt8], output: ProgramOutput) throws -> RunResult {
        try TemporaryDirectory.withNew { directory in
            // Link into a directory that goes, executable and all, once the program ends.
            let executable = directory.appendingPathComponent("program")
            try link(objectCode, to: executable)

            switch output {
            // A captured run returns what the program wrote.
            case .captured:
                let result = try processes.runCapturingOutput(executable)
                return RunResult(exitCode: result.exitCode, output: result.output, errors: result.errors)

            // The program writes straight to `rayoc`'s own streams, so the result holds only its exit code. `rayoc`
            // outlives an interrupt from the terminal that ends the program, so it still removes the executable.
            case .inherited:
                let exitCode = try processes.runAttached(executable)
                return RunResult(exitCode: exitCode, output: "", errors: "")
            }
        }
    }

    /// The arguments that have clang link with `linker`. Throws when that linker can't be found.
    private func linkerArguments() throws(Failure) -> [String] {
        // clang picks the arguments it gives the linker by `-fuse-ld`, and runs the linker that `--ld-path` names.
        switch linker {
        // LLD gets LLD's arguments, and runs from where `tools` says.
        case .lld:
            // Without that LLD, the error says how to get one, or how to link without it.
            guard Self.isExecutableFile(tools.lld) else {
                throw Failure("""
                    can't find LLD at '\(tools.lld.path)': install LLD \(LLVMInstall.majorVersion), run \
                    'swift package purge-cache' and build rayoc again, or link with --linker=platform
                    """)
            }
            return ["-fuse-ld=lld", "--ld-path=\(tools.lld.path)"]

        // The platform's linker gets the arguments of the system `ld`.
        case .platform:
            return ["-fuse-ld=ld", "--ld-path=\(try findPlatformLinker().path)"]
        }
    }

    /// Finds the platform's own linker, at the place the platform keeps it rather than the first `ld` on the search
    /// path. Throws when it isn't there.
    private func findPlatformLinker() throws(Failure) -> URL {
        let linker = locatePlatformLinker()

        // A linker that isn't where the platform keeps it can't be run.
        guard Self.isExecutableFile(linker) else {
            throw Failure("can't find the platform's linker at '\(linker.path)'")
        }

        return linker
    }

    #if canImport(Darwin)
    /// Locates the `ld` of the developer tools that `xcrun` selects, or `/usr/bin/ld` where it selects none.
    private func locatePlatformLinker() -> URL {
        // Ask `xcrun`, which prints the path of the `ld` it finds on a line of its own.
        let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
        let found = try? processes.runCapturingOutput(xcrun, arguments: ["--find", "ld"])

        // Where `xcrun` can't run, or finds no `ld`, the linker is the one macOS keeps in `/usr/bin`.
        guard let found, found.exitCode == 0 else { return URL(fileURLWithPath: "/usr/bin/ld") }

        return URL(fileURLWithPath: found.output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    #else
    /// Locates the system `ld`, at `/usr/bin/ld`.
    private func locatePlatformLinker() -> URL {
        URL(fileURLWithPath: "/usr/bin/ld")
    }
    #endif

    /// Whether `url` names a file, not a directory, that this process may execute.
    private static func isExecutableFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
    }
}
