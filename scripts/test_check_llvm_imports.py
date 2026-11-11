import os
import tempfile
import unittest

from check_llvm_imports import findings


class CheckLLVMImportsTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()

    def write(self, path, text):
        full = os.path.join(self.root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, 'w') as f:
            f.write(text)

    def test_an_allowed_directory_may_import_llvms_c_modules(self):
        self.write('Sources/LLVM/Context.swift', 'import CLLVM\nimport CLLVMJIT\n')

        self.assertEqual(findings(self.root, allowed=['Sources/LLVM']), [])

    def test_an_import_outside_the_allowed_directories_is_reported_by_file_and_line(self):
        self.write('Sources/RayoIR/Lowering.swift', 'import Foundation\nimport RayoSema\nimport CLLVM\n')

        self.assertEqual(findings(self.root, allowed=['Sources/LLVM']), [
            'Sources/RayoIR/Lowering.swift:3: imports CLLVM, which only Sources/LLVM may import',
        ])

    def test_an_import_counts_in_every_form_swift_writes_one(self):
        for source in ['import CLLVMJIT', '@preconcurrency import CLLVM', '@_implementationOnly import CLLVM',
                       'internal import CLLVM', '    package import CLLVM', 'import struct CLLVM.LLVMOpaqueValue',
                       'import CLLVM.Core', '#if canImport(CLLVM)\nimport CLLVM\n#endif']:
            with self.subTest(source=source):
                self.write('Tests/RayoIRTests/Lowered.swift', source + '\n')

                self.assertEqual(len(findings(self.root, allowed=['Sources/LLVM'])), 1)

    def test_a_mention_that_imports_nothing_is_no_import(self):
        for source in ['// import CLLVM', '/*\nimport CLLVM\n*/', 'let text = "import CLLVM"',
                       '#if canImport(CLLVM)\n#endif', 'import CLLVMExtras']:
            with self.subTest(source=source):
                self.write('Sources/RayoIR/Lowering.swift', source + '\n')

                self.assertEqual(findings(self.root, allowed=['Sources/LLVM']), [])

    def test_a_reexport_is_reported_even_from_an_allowed_directory(self):
        self.write('Sources/LLVM/Context.swift', '@_exported import CLLVM\n')

        self.assertEqual(findings(self.root, allowed=['Sources/LLVM']), [
            'Sources/LLVM/Context.swift:1: re-exports CLLVM, which hands it to every module that imports this one',
        ])

    def test_the_findings_of_several_files_come_in_order_of_path(self):
        self.write('Tests/RayoIRTests/Lowered.swift', 'import CLLVMJIT\n')
        self.write('Sources/RayoIR/Lowering.swift', '\nimport CLLVM\n')

        self.assertEqual(findings(self.root, allowed=['Sources/LLVM', 'Sources/RayoLLVM']), [
            'Sources/RayoIR/Lowering.swift:2: imports CLLVM, which only Sources/LLVM and Sources/RayoLLVM may import',
            'Tests/RayoIRTests/Lowered.swift:1: imports CLLVMJIT, which only Sources/LLVM and Sources/RayoLLVM may '
            'import',
        ])

    def test_a_directory_named_like_an_allowed_one_is_not_allowed(self):
        self.write('Sources/LLVMExtras/A.swift', 'import CLLVM\n')

        self.assertEqual(len(findings(self.root, allowed=['Sources/LLVM'])), 1)

    def test_files_outside_sources_and_tests_are_not_checked(self):
        self.write('scripts/generate.swift', 'import CLLVM\n')

        self.assertEqual(findings(self.root, allowed=['Sources/LLVM']), [])


if __name__ == '__main__':
    unittest.main()
