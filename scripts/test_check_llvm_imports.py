import contextlib
import io
import os
import tempfile
import unittest

from check_llvm_imports import findings, main


class CheckLLVMImportsTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = directory.name

    def write(self, path, text):
        full = os.path.join(self.root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, 'w', encoding='utf-8') as f:
            f.write(text)

    def test_an_allowed_directory_may_import_llvms_c_module(self):
        self.write('Sources/LLVM/Context.swift', 'import CLLVM\n')

        self.assertEqual(findings(self.root, allowed=['Sources/LLVM']), [])

    def test_an_import_outside_the_allowed_directories_is_reported_by_file_and_line(self):
        self.write('Sources/RayoIR/Lowering.swift', 'import Foundation\nimport RayoSema\nimport CLLVM\n')

        self.assertEqual(findings(self.root, allowed=['Sources/LLVM']), [
            'Sources/RayoIR/Lowering.swift:3: imports CLLVM, which only Sources/LLVM may import',
        ])

    def test_an_import_counts_in_every_form_swift_writes_one(self):
        for source in ['import CLLVM', '@preconcurrency import CLLVM', '@_implementationOnly import CLLVM',
                       'internal import CLLVM', '    package import CLLVM', 'import struct CLLVM.LLVMOpaqueValue',
                       'import CLLVM.Core', '#if canImport(CLLVM)\nimport CLLVM\n#endif',
                       '@available(macOS 10.15, *)\n@preconcurrency\nimport CLLVM']:
            with self.subTest(source=source):
                self.write('Tests/RayoIRTests/Lowered.swift', source + '\n')

                self.assertEqual(len(findings(self.root, allowed=['Sources/LLVM'])), 1)

    def test_an_import_after_another_on_the_same_line_is_reported_on_that_line(self):
        self.write('Sources/RayoIR/Lowering.swift', '\nimport Foundation; import CLLVM\n')

        self.assertEqual(findings(self.root, allowed=['Sources/LLVM']), [
            'Sources/RayoIR/Lowering.swift:2: imports CLLVM, which only Sources/LLVM may import',
        ])

    def test_a_mention_that_imports_nothing_is_no_import(self):
        for source in ['// import CLLVM', '/*\nimport CLLVM\n*/', 'let text = "import CLLVM"',
                       '#if canImport(CLLVM)\n#endif', 'import CLLVMExtras',
                       'let text = """\nimport CLLVM\n"""', 'let text = #"""\n"""\nimport CLLVM\n"""#',
                       '/* a /* b */\nimport CLLVM\n*/', 'let text = "\\(a + ";") ; import CLLVM"',
                       'let text = "\\"; import CLLVM"']:
            with self.subTest(source=source):
                self.write('Sources/RayoIR/Lowering.swift', source + '\n')

                self.assertEqual(findings(self.root, allowed=['Sources/LLVM']), [])

    def test_a_comment_marker_inside_a_string_or_a_line_comment_hides_no_import(self):
        for source in ['let pattern = "Sources/*"\nimport CLLVM\nlet end = "*/"',
                       '// reads Sources/*\nimport CLLVM\n// */']:
            with self.subTest(source=source):
                self.write('Sources/RayoIR/Lowering.swift', source + '\n')

                self.assertEqual(findings(self.root, allowed=['Sources/LLVM']), [
                    'Sources/RayoIR/Lowering.swift:2: imports CLLVM, which only Sources/LLVM may import',
                ])

    def test_a_reexport_is_reported_even_from_an_allowed_directory(self):
        self.write('Sources/LLVM/Context.swift', '@_exported import CLLVM\n')

        self.assertEqual(findings(self.root, allowed=['Sources/LLVM']), [
            'Sources/LLVM/Context.swift:1: re-exports CLLVM, which hands it to every module that imports this one',
        ])

    def test_a_reexport_is_reported_with_its_attribute_on_a_line_of_its_own(self):
        self.write('Sources/LLVM/Context.swift', '@_exported\nimport CLLVM\n')

        self.assertEqual(findings(self.root, allowed=['Sources/LLVM']), [
            'Sources/LLVM/Context.swift:2: re-exports CLLVM, which hands it to every module that imports this one',
        ])

    def test_the_findings_of_several_files_come_in_order_of_path(self):
        self.write('Tests/RayoIRTests/Lowered.swift', 'import CLLVM\n')
        self.write('Sources/RayoIR/Lowering.swift', '\nimport CLLVM\n')

        self.assertEqual(findings(self.root, allowed=['Sources/LLVM', 'Sources/RayoLLVM']), [
            'Sources/RayoIR/Lowering.swift:2: imports CLLVM, which only Sources/LLVM and Sources/RayoLLVM may import',
            'Tests/RayoIRTests/Lowered.swift:1: imports CLLVM, which only Sources/LLVM and Sources/RayoLLVM may '
            'import',
        ])

    def test_a_directory_named_like_an_allowed_one_is_not_allowed(self):
        self.write('Sources/LLVMExtras/A.swift', 'import CLLVM\n')

        self.assertEqual(len(findings(self.root, allowed=['Sources/LLVM'])), 1)

    def test_files_outside_sources_and_tests_are_not_checked(self):
        self.write('scripts/generate.swift', 'import CLLVM\n')

        self.assertEqual(findings(self.root, allowed=['Sources/LLVM']), [])


class CheckLLVMImportsMainTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = directory.name
        os.makedirs(os.path.join(self.root, 'Sources/RayoIR'))

    def run_main(self):
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = main(self.root)
        return status, output.getvalue(), errors.getvalue()

    def test_a_package_without_findings_passes_and_says_it_was_checked(self):
        self.assertEqual(self.run_main(), (0, 'checked\n', ''))

    def test_a_package_with_findings_fails_and_writes_each_to_standard_error(self):
        with open(os.path.join(self.root, 'Sources/RayoIR/Lowering.swift'), 'w', encoding='utf-8') as f:
            f.write('import CLLVM\n')

        status, output, errors = self.run_main()

        self.assertEqual((status, output), (1, ''))
        self.assertIn('Sources/RayoIR/Lowering.swift:1: imports CLLVM', errors)


if __name__ == '__main__':
    unittest.main()
