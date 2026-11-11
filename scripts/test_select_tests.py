import contextlib
import io
import json
import os
import tempfile
import unittest

from select_tests import main, selection


def target(name, kind, dependencies, path=None):
    # `swift package dump-package` writes every key of a target, with `null` for a path the manifest leaves out.
    return {'name': name, 'type': kind, 'path': path, 'dependencies': dependencies}


# A chain of source targets, test targets that depend on links of it, and a target at a path of its own.
PACKAGE = {'targets': [
    target('Source', 'regular', []),
    target('Syntax', 'regular', [{'byName': ['Source', None]}]),
    target('Sema', 'regular', [{'target': ['Syntax', None]}]),
    target('Tool', 'executable', [], path='Tests/tool'),
    target('SyntaxTests', 'test', [{'byName': ['Syntax', None]}]),
    target('SemaTests', 'test', [{'byName': ['Sema', None]}, {'product': ['Parser', 'other-package', None, None]}]),
    target('ToolTests', 'test', [{'byName': ['Tool', None]}]),
    target('Unused', 'regular', []),
]}


class SelectTestsTests(unittest.TestCase):
    def test_a_change_to_a_test_target_selects_that_test_target(self):
        self.assertEqual(selection(PACKAGE, ['Tests/SyntaxTests/LexerTests.swift']), r'^(SyntaxTests)\.')

    def test_a_change_to_a_source_target_selects_the_test_targets_that_depend_on_it_directly(self):
        self.assertEqual(selection(PACKAGE, ['Sources/Sema/Checker.swift']), r'^(SemaTests)\.')

    def test_a_change_to_a_source_target_selects_the_test_targets_that_depend_on_it_through_others(self):
        self.assertEqual(selection(PACKAGE, ['Sources/Source/File.swift']), r'^(SemaTests|SyntaxTests)\.')

    def test_a_target_at_a_path_of_its_own_is_changed_by_a_change_under_that_path(self):
        self.assertEqual(selection(PACKAGE, ['Tests/tool/main.swift']), r'^(ToolTests)\.')

    def test_the_changes_to_several_targets_select_the_test_targets_each_selects(self):
        changed = ['Tests/tool/main.swift', 'Sources/Sema/Checker.swift']
        self.assertEqual(selection(PACKAGE, changed), r'^(SemaTests|ToolTests)\.')

    def test_a_change_outside_every_target_selects_every_test_target(self):
        for path in ['Package.swift', '.github/workflows/ci.yml', 'Tests/Shared.swift', 'Sources/SyntaxExtra/A.swift']:
            with self.subTest(path=path):
                self.assertEqual(selection(PACKAGE, ['Sources/Sema/Checker.swift', path]), 'all')

    def test_a_dependency_on_a_condition_or_under_module_aliases_is_a_dependency_all_the_same(self):
        package = {'targets': [
            target('Source', 'regular', []),
            target('Syntax', 'regular', [
                {'target': ['Source', {'platformNames': ['linux']}]},
                {'product': ['Parser', 'other-package', {'Parser': 'OtherParser'}, {'platformNames': ['macos']}]},
            ]),
            target('SyntaxTests', 'test', [{'byName': ['Syntax', {'platformNames': ['windows']}]}]),
        ]}

        self.assertEqual(selection(package, ['Sources/Source/File.swift']), r'^(SyntaxTests)\.')

    def test_a_change_that_no_test_target_depends_on_selects_none(self):
        self.assertEqual(selection(PACKAGE, ['Sources/Unused/File.swift']), 'none')

    def test_no_changed_paths_select_none(self):
        self.assertEqual(selection(PACKAGE, []), 'none')


class SelectTestsMainTests(unittest.TestCase):
    def run_main(self, arguments):
        output, errors = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = main(arguments)
        return status, output.getvalue(), errors.getvalue()

    def write_json(self, directory, name, value):
        path = os.path.join(directory, name)
        with open(path, 'w', encoding='utf-8') as f:
            json.dump(value, f)
        return path

    def test_the_selection_for_the_files_named_is_written_to_standard_output(self):
        directory = tempfile.mkdtemp()
        package = self.write_json(directory, 'package.json', PACKAGE)
        paths = self.write_json(directory, 'changed-paths.json', ['Sources/Sema/Checker.swift'])

        self.assertEqual(self.run_main([package, paths]), (0, '^(SemaTests)\\.\n', ''))

    def test_any_other_number_of_arguments_is_a_misuse(self):
        for arguments in [[], ['package.json'], ['package.json', 'changed-paths.json', 'extra']]:
            with self.subTest(arguments=arguments):
                status, output, errors = self.run_main(arguments)

                self.assertEqual((status, output), (2, ''))
                self.assertIn('usage: select_tests.py', errors)


if __name__ == '__main__':
    unittest.main()
