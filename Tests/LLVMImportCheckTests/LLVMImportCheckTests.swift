import Foundation
import LLVMImportCheck
import PackageGraph
import Testing

/// A package laid out as `swift package dump-package` describes one: `Binding` imports LLVM's C API, `Emitter`
/// depends on `Binding`, and `Emitter`'s tests depend on `Emitter` alone.
private let package = try! JSONDecoder().decode(PackageTargets.self, from: Data("""
    {"targets": [
        {"name": "CLLVM", "type": "system-target", "dependencies": []},
        {"name": "Binding", "type": "regular", "dependencies": [{"byName": ["CLLVM", null]}]},
        {"name": "Emitter", "type": "regular", "dependencies": [{"byName": ["Binding", null]}]},
        {"name": "EmitterTests", "type": "test", "dependencies": [{"byName": ["Emitter", null]}]}
    ]}
    """.utf8))

/// The check that lets only `Binding` import LLVM's C modules.
private let check = LLVMImportCheck(allowedModules: ["Binding"])

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
        #expect(check.violations(in: files, of: package) == [
            ImportViolation(path: "Sources/Emitter/Emitter.swift", line: 3, module: "Emitter", imported: "CLLVM"),
        ])
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

    @Test("the imports of several files are each reported, in order of path")
    func severalFiles() {
        let files = [
            "Tests/EmitterTests/EmitterTests.swift": "import CLLVMJIT\n",
            "Sources/Emitter/Emitter.swift": "import CLLVM\n",
        ]
        #expect(check.violations(in: files, of: package) == [
            ImportViolation(path: "Sources/Emitter/Emitter.swift", line: 1, module: "Emitter", imported: "CLLVM"),
            ImportViolation(path: "Tests/EmitterTests/EmitterTests.swift", line: 1, module: "EmitterTests",
                            imported: "CLLVMJIT"),
        ])
    }

    @Test("a violation names the file, the line, the import, and the modules that may make it")
    func written() {
        let violation = ImportViolation(path: "Sources/Emitter/Emitter.swift", line: 3, module: "Emitter",
                                        imported: "CLLVM")
        #expect(violation.description(allowing: ["Binding", "BindingTests"]) == """
            Sources/Emitter/Emitter.swift:3: Emitter imports CLLVM, which only Binding and BindingTests may import
            """)
        #expect(violation.description(allowing: ["Binding"]) ==
            "Sources/Emitter/Emitter.swift:3: Emitter imports CLLVM, which only Binding may import")
        #expect(violation.description(allowing: ["A", "B", "C"]) ==
            "Sources/Emitter/Emitter.swift:3: Emitter imports CLLVM, which only A, B and C may import")
    }

    @Test("a file in no target's directory is compiled into no module, so its imports aren't checked")
    func outsideTargets() {
        let files = ["Scripts/generate.swift": "import CLLVM\n"]
        #expect(check.violations(in: files, of: package) == [])
    }
}
