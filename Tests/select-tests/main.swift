import Foundation
import PackageGraph
import TestSelection

// The first argument names a file of `swift package dump-package`'s output, and the second a file that holds the
// changed paths as a JSON array; any other arguments are a misuse, which exits with 2.
let arguments = CommandLine.arguments.dropFirst()
guard arguments.count == 2, let packageFile = arguments.first, let pathsFile = arguments.last else {
    FileHandle.standardError.write(Data("usage: select-tests <package.json> <changed-paths.json>\n".utf8))
    exit(2)
}

// Read the package's targets and the changed paths, and write the selection to standard output.
do {
    let packageJSON = try Data(contentsOf: URL(fileURLWithPath: packageFile))
    let package = try JSONDecoder().decode(PackageTargets.self, from: packageJSON)
    let paths = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: pathsFile)))
    print(TestSelection(changedPaths: paths, in: package))
} catch {
    // A file that can't be read or decoded fails the run, and says why.
    FileHandle.standardError.write(Data("select-tests: \(error)\n".utf8))
    exit(1)
}
