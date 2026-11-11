import Foundation
import LLVMImportCheck
import PackageGraph
import Testing

/// A package laid out as `swift package dump-package` describes one: `Binding` imports LLVM's C API, `Emitter`
/// depends on `Binding`, `Emitter`'s tests depend on `Emitter` alone, and `Direct` names `CLLVM` in its own
/// dependencies.
private let package = try! JSONDecoder().decode(PackageTargets.self, from: Data("""
    {"targets": [
        {"name": "CLLVM", "type": "system-target", "dependencies": []},
        {"name": "Binding", "type": "regular", "dependencies": [{"byName": ["CLLVM", null]}]},
        {"name": "Emitter", "type": "regular", "dependencies": [{"byName": ["Binding", null]}]},
        {"name": "EmitterTests", "type": "test", "dependencies": [{"byName": ["Emitter", null]}]},
        {"name": "Direct", "type": "regular", "dependencies": [{"byName": ["CLLVM", null]}]}
    ]}
    """.utf8))

/// The check that lets only `Binding` import LLVM's C modules.
private let check = LLVMImportCheck(allowedModules: ["Binding"])

/// A violation by the import of `imported` at `line` of `path`, a file of `module`.
private func violation(
    _ kind: ImportViolation.Kind, at path: String, line: Int, of module: String, importing imported: String = "CLLVM",
) -> ImportViolation {
    ImportViolation(kind: kind, path: path, line: line, module: module, imported: imported)
}

struct LLVMImportCheckTests {
    @Test("a module allowed to import LLVM's C modules may import them")
    func allowed() {
        let files = ["Sources/Binding/Context.swift": "import CLLVM\nimport CLLVMJIT\n"]
        #expect(check.violations(in: files, of: package) == [])
    }

    @Test("""
        a module that reaches LLVM's C API only through another dependency may not import it, and the file and \
        line are named
        """)
    func reachedThroughDependency() {
        let files = ["Sources/Emitter/Emitter.swift": "import Foundation\nimport Binding\nimport CLLVM\n"]
        #expect(check.violations(in: files, of: package) ==
            [violation(.notAllowed, at: "Sources/Emitter/Emitter.swift", line: 3, of: "Emitter")])
    }

    @Test("a module that names LLVM's C API in its manifest's dependencies still may not import it")
    func namedInManifest() {
        let files = ["Sources/Direct/Direct.swift": "import CLLVM\n"]
        #expect(check.violations(in: files, of: package) ==
            [violation(.notAllowed, at: "Sources/Direct/Direct.swift", line: 1, of: "Direct")])
    }

    @Test("an import of LLVM's C modules counts in every form Swift writes one", arguments: [
        "import CLLVMJIT",
        "@preconcurrency import CLLVM",
        "@_implementationOnly import CLLVM",
        "internal import CLLVM",
        "import struct CLLVM.LLVMOpaqueValue",
        "import CLLVM.Core",
        "#if canImport(CLLVM)\nimport CLLVM\n#endif",
    ])
    func importForms(source: String) {
        let files = ["Tests/EmitterTests/EmitterTests.swift": source]
        #expect(check.violations(in: files, of: package).map(\.module) == ["EmitterTests"])
    }

    @Test("a mention of LLVM's C modules that imports nothing is no import", arguments: [
        "// import CLLVM",
        "/*\nimport CLLVM\n*/",
        "let text = \"import CLLVM\"",
        "#if canImport(CLLVM)\n#endif",
        "import CLLVMExtras",
    ])
    func mentions(source: String) {
        let files = ["Sources/Emitter/Emitter.swift": source]
        #expect(check.violations(in: files, of: package) == [])
    }

    @Test("a module, allowed or not, may not re-export LLVM's C modules to the modules that import it")
    func reexported() {
        let files = [
            "Sources/Binding/Context.swift": "@_exported import CLLVM\n",
            "Sources/Emitter/Emitter.swift": "@_exported import CLLVMJIT\n",
        ]
        #expect(check.violations(in: files, of: package) == [
            violation(.reexported, at: "Sources/Binding/Context.swift", line: 1, of: "Binding"),
            violation(.reexported, at: "Sources/Emitter/Emitter.swift", line: 1, of: "Emitter",
                      importing: "CLLVMJIT"),
        ])
    }

    @Test("the imports of several files are each reported, in order of path")
    func severalFiles() {
        let files = [
            "Tests/EmitterTests/EmitterTests.swift": "import CLLVMJIT\n",
            "Sources/Emitter/Emitter.swift": "import CLLVM\n",
        ]
        #expect(check.violations(in: files, of: package) == [
            violation(.notAllowed, at: "Sources/Emitter/Emitter.swift", line: 1, of: "Emitter"),
            violation(.notAllowed, at: "Tests/EmitterTests/EmitterTests.swift", line: 1, of: "EmitterTests",
                      importing: "CLLVMJIT"),
        ])
    }

    @Test("a violation is described by its file, its line and its import, with the modules that may make it")
    func describesViolation() {
        let notAllowed = violation(.notAllowed, at: "Sources/Emitter/Emitter.swift", line: 3, of: "Emitter")
        #expect(LLVMImportCheck(allowedModules: ["Binding", "BindingTests"]).description(of: notAllowed) ==
            "Sources/Emitter/Emitter.swift:3: Emitter imports CLLVM, which only Binding and BindingTests may import")
        #expect(LLVMImportCheck(allowedModules: ["Binding"]).description(of: notAllowed) ==
            "Sources/Emitter/Emitter.swift:3: Emitter imports CLLVM, which only Binding may import")
        #expect(LLVMImportCheck(allowedModules: ["A", "B", "C"]).description(of: notAllowed) ==
            "Sources/Emitter/Emitter.swift:3: Emitter imports CLLVM, which only A, B and C may import")

        let reexported = violation(.reexported, at: "Sources/Binding/Context.swift", line: 1, of: "Binding")
        #expect(check.description(of: reexported) == """
            Sources/Binding/Context.swift:1: Binding re-exports CLLVM, which hands it to every module that imports \
            Binding
            """)
    }

    @Test("a file in no target's directory is compiled into no module, so its imports aren't checked")
    func outsideTargets() {
        let files = ["Scripts/generate.swift": "import CLLVM\n"]
        #expect(check.violations(in: files, of: package) == [])
    }
}
