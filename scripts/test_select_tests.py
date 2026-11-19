import contextlib
import io
import json
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

EVERY_TEST_TARGET = ['SemaTests', 'SyntaxTests', 'ToolTests']


class SelectionTests(unittest.TestCase):
    def test_a_change_to_a_test_target_selects_that_test_target(self):
        self.assertEqual(selection(PACKAGE, ['Tests/SyntaxTests/LexerTests.swift']), ['SyntaxTests'])

    def test_a_change_to_a_source_target_selects_the_test_targets_that_depend_on_it_directly(self):
        self.assertEqual(selection(PACKAGE, ['Sources/Sema/Checker.swift']), ['SemaTests'])

    def test_a_change_to_a_source_target_selects_the_test_targets_that_depend_on_it_through_others(self):
        self.assertEqual(selection(PACKAGE, ['Sources/Source/File.swift']), ['SemaTests', 'SyntaxTests'])

    def test_a_target_at_a_path_of_its_own_is_changed_by_a_change_under_that_path(self):
        self.assertEqual(selection(PACKAGE, ['Tests/tool/main.swift']), ['ToolTests'])

    def test_the_changes_to_several_targets_select_the_test_targets_each_selects(self):
        changed = ['Tests/tool/main.swift', 'Sources/Sema/Checker.swift']
        self.assertEqual(selection(PACKAGE, changed), ['SemaTests', 'ToolTests'])

    def test_a_change_that_can_change_a_test_outside_every_target_selects_every_test_target(self):
        paths = [
            'Package.swift', 'Package.resolved', '.github/workflows/ci.yml', '.github/actions/swift-test/action.yml',
            'examples/v0.1/hello.rayo', '.gitattributes', 'Tests/Shared.swift', 'Sources/SyntaxExtra/A.swift',
        ]
        for path in paths:
            with self.subTest(path=path):
                self.assertEqual(selection(PACKAGE, ['Sources/Sema/Checker.swift', path]), EVERY_TEST_TARGET)

    def test_a_change_that_no_test_reads_selects_nothing_more(self):
        paths = [
            'README.md', 'docs/spec/types.md', 'scripts/select_tests.py', '.github/workflows/other.yml',
            'examples/README.md', 'Package.swift.orig', 'SourcesExtra/A.swift',
        ]
        for path in paths:
            with self.subTest(path=path):
                self.assertEqual(selection(PACKAGE, ['Sources/Sema/Checker.swift', path]), ['SemaTests'])

    def test_a_dependency_on_a_condition_or_under_module_aliases_is_a_dependency_all_the_same(self):
        package = {'targets': [
            target('Source', 'regular', []),
            target('Syntax', 'regular', [
                {'target': ['Source', {'platformNames': ['linux']}]},
                {'product': ['Parser', 'other-package', {'Parser': 'OtherParser'}, {'platformNames': ['macos']}]},
            ]),
            target('SyntaxTests', 'test', [{'byName': ['Syntax', {'platformNames': ['windows']}]}]),
        ]}

        self.assertEqual(selection(package, ['Sources/Source/File.swift']), ['SyntaxTests'])

    def test_a_change_that_no_test_target_depends_on_selects_none(self):
        self.assertEqual(selection(PACKAGE, ['Sources/Unused/File.swift']), [])

    def test_no_changed_paths_select_none(self):
        self.assertEqual(selection(PACKAGE, []), [])


class SelectTestsMainTests(unittest.TestCase):
    def run_main(self, arguments, standard_input):
        output, errors = io.StringIO(), io.StringIO()
        with (contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors)):
            status = main(arguments, io.StringIO(standard_input))
        return status, output.getvalue(), errors.getvalue()

    def test_the_changed_paths_that_can_change_a_test_are_written_as_a_json_array(self):
        changed = 'README.md\nSources/Sema/Checker.swift\nscripts/check_docs.py\nPackage.swift\n'

        status, output, errors = self.run_main([], changed)

        self.assertEqual((status, json.loads(output), errors), (0, ['Sources/Sema/Checker.swift', 'Package.swift'], ''))

    def test_no_changed_paths_that_can_change_a_test_are_written_as_an_empty_array(self):
        for changed in ['', '\n', 'README.md\n']:
            with self.subTest(changed=changed):
                self.assertEqual(self.run_main([], changed), (0, '[]\n', ''))

    def test_any_argument_is_a_misuse(self):
        status, output, errors = self.run_main(['package.json'], '')

        self.assertEqual((status, output), (2, ''))
        self.assertIn('usage: select_tests.py', errors)


if __name__ == '__main__':
    unittest.main()
