import unittest

from select_tests import selection

# A package laid out as `swift package dump-package` describes one: a chain of source targets, test targets that
# depend on links of it, and a target at a path of its own.
PACKAGE = {'targets': [
    {'name': 'Source', 'type': 'regular', 'dependencies': []},
    {'name': 'Syntax', 'type': 'regular', 'dependencies': [{'byName': ['Source', None]}]},
    {'name': 'Sema', 'type': 'regular', 'dependencies': [{'target': ['Syntax', None]}]},
    {'name': 'Tool', 'type': 'executable', 'path': 'Tests/tool', 'dependencies': []},
    {'name': 'SyntaxTests', 'type': 'test', 'dependencies': [{'byName': ['Syntax', None]}]},
    {'name': 'SemaTests', 'type': 'test',
     'dependencies': [{'byName': ['Sema', None]}, {'product': ['Parser', 'other-package', None, None]}]},
    {'name': 'ToolTests', 'type': 'test', 'dependencies': [{'byName': ['Tool', None]}]},
    {'name': 'Unused', 'type': 'regular', 'dependencies': []},
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
            {'name': 'Source', 'type': 'regular', 'dependencies': []},
            {'name': 'Syntax', 'type': 'regular', 'dependencies': [
                {'target': ['Source', {'platformNames': ['linux']}]},
                {'product': ['Parser', 'other-package', {'Parser': 'OtherParser'}, {'platformNames': ['macos']}]},
            ]},
            {'name': 'SyntaxTests', 'type': 'test', 'dependencies': [{'byName': ['Syntax', {'platformNames': ['windows']}]}]},
        ]}

        self.assertEqual(selection(package, ['Sources/Source/File.swift']), r'^(SyntaxTests)\.')

    def test_a_change_that_no_test_target_depends_on_selects_none(self):
        self.assertEqual(selection(PACKAGE, ['Sources/Unused/File.swift']), 'none')


if __name__ == '__main__':
    unittest.main()
