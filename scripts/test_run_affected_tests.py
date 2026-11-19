import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

from run_affected_tests import main


def target(name, kind, dependencies):
    return {'name': name, 'type': kind, 'path': None, 'dependencies': [{'byName': [d, None]} for d in dependencies]}


# What `swift package dump-package` prints for a chain of modules, with a test target for each and one for nothing.
PACKAGE = {'targets': [
    target('Source', 'regular', []),
    target('Syntax', 'regular', ['Source']),
    target('Sema', 'regular', ['Syntax']),
    target('SourceTests', 'test', ['Source']),
    target('SyntaxTests', 'test', ['Syntax']),
    target('SemaTests', 'test', ['Sema']),
    target('ToolTests', 'test', []),
]}

# A stand-in for `swift`: it prints the package for `swift package dump-package`, and otherwise writes the
# arguments it was run with to the log, one run a line, and exits with the status the test asks for.
SWIFT = '''#!{python}
import json, os, sys
if sys.argv[1:] == ['package', 'dump-package']:
    print(open(os.environ['STAND_IN_PACKAGE']).read())
    sys.exit(0)
with open(os.environ['STAND_IN_LOG'], 'a') as log:
    log.write(json.dumps({{'arguments': sys.argv[1:], 'directory': os.getcwd()}}) + '\\n')
sys.exit(int(os.environ.get('STAND_IN_STATUS', '0')))
'''


@unittest.skipIf(os.name == 'nt', "the stand-in for swift is a script with a #! line, which Windows doesn't run")
class RunAffectedTestsTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = os.path.realpath(directory.name)
        self.repository = os.path.join(self.directory, 'package')
        self.log = os.path.join(self.directory, 'swift.log')
        self.environment = self.stand_in_environment()

        # The package's main branch, which origin's main is level with, and a branch for the change.
        os.mkdir(self.repository)
        self.git('init', '-q', '-b', 'main')
        for path in ['Package.swift', 'README.md', 'Sources/Source/File.swift', 'Sources/Syntax/Lexer.swift',
                     'Sources/Sema/Checker.swift', 'Tests/SyntaxTests/LexerTests.swift']:
            self.write(path)
        self.commit('start the package')
        self.git('update-ref', 'refs/remotes/origin/main', 'main')
        self.git('checkout', '-q', '-b', 'change')

    def stand_in_environment(self):
        # A `swift` of the test's own comes first on the search path, and git reads none of the user's settings.
        bin = os.path.join(self.directory, 'bin')
        os.mkdir(bin)
        swift = os.path.join(bin, 'swift')
        with open(swift, 'w', encoding='utf-8') as f:
            f.write(SWIFT.format(python=sys.executable))
        os.chmod(swift, 0o755)
        package = os.path.join(self.directory, 'package.json')
        with open(package, 'w', encoding='utf-8') as f:
            json.dump(PACKAGE, f)
        return dict(
            os.environ, PATH=bin + os.pathsep + os.environ['PATH'], STAND_IN_PACKAGE=package, STAND_IN_LOG=self.log,
            GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_NOSYSTEM='1', GIT_AUTHOR_NAME='Test', GIT_AUTHOR_EMAIL='test@test',
            GIT_COMMITTER_NAME='Test', GIT_COMMITTER_EMAIL='test@test',
        )

    def git(self, *arguments):
        subprocess.run(['git', *arguments], cwd=self.repository, env=self.environment, check=True)

    def write(self, path, text='// a change\n'):
        full = os.path.join(self.repository, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, 'a', encoding='utf-8') as f:
            f.write(text)

    def commit(self, message):
        self.git('add', '-A')
        self.git('commit', '-q', '-m', message)

    def run_script(self, *arguments, status=0):
        environment = dict(self.environment, STAND_IN_STATUS=str(status))
        output, errors = io.StringIO(), io.StringIO()
        with (mock.patch.dict(os.environ, environment, clear=True),
              contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors)):
            status = main(self.repository, list(arguments))
        return status, output.getvalue(), errors.getvalue()

    def swift_runs(self):
        if not os.path.exists(self.log):
            return []
        with open(self.log, encoding='utf-8') as log:
            return [json.loads(line)['arguments'] for line in log]

    def test_a_committed_change_to_one_module_tests_only_the_test_targets_that_depend_on_it(self):
        self.write('Sources/Sema/Checker.swift')
        self.commit('change the checker')

        self.assertEqual(self.run_script(), (0, 'Testing SemaTests\n', ''))
        self.assertEqual(self.swift_runs(), [['test', '--filter', r'^(SemaTests)\.']])

    def test_a_change_to_a_module_that_others_depend_on_tests_theirs_too(self):
        self.write('Sources/Syntax/Lexer.swift')
        self.commit('change the lexer')

        self.run_script()

        self.assertEqual(self.swift_runs(), [['test', '--filter', r'^(SemaTests|SyntaxTests)\.']])

    def test_changes_not_yet_committed_count_whether_staged_unstaged_or_untracked(self):
        self.write('Sources/Sema/Checker.swift')
        self.write('Tests/SyntaxTests/ParserTests.swift')
        self.git('add', 'Tests/SyntaxTests/ParserTests.swift')
        self.write('Tests/ToolTests/ToolTests.swift')

        self.run_script()

        self.assertEqual(self.swift_runs(), [['test', '--filter', r'^(SemaTests|SyntaxTests|ToolTests)\.']])

    def test_changes_made_on_the_base_after_the_branch_left_it_are_not_the_change(self):
        self.git('checkout', '-q', 'main')
        self.write('Sources/Source/File.swift')
        self.commit('change the source files on main')
        self.git('update-ref', 'refs/remotes/origin/main', 'main')
        self.git('checkout', '-q', 'change')
        self.write('Sources/Sema/Checker.swift')
        self.commit('change the checker')

        self.run_script()

        self.assertEqual(self.swift_runs(), [['test', '--filter', r'^(SemaTests)\.']])

    def test_a_change_to_the_manifest_or_ci_tests_everything(self):
        for path in ['Package.swift', '.github/workflows/ci.yml']:
            with self.subTest(path=path):
                self.git('reset', '-q', '--hard', 'main')
                self.git('clean', '-q', '-f', '-d')
                if os.path.exists(self.log):
                    os.remove(self.log)
                self.write(path)

                self.assertEqual(self.run_script(), (0, 'Testing every test target\n', ''))
                self.assertEqual(self.swift_runs(), [['test']])

    def test_a_change_no_test_reaches_only_builds_the_tests(self):
        self.write('README.md')

        output = 'No test target depends on the change, so the tests are only built\n'
        self.assertEqual(self.run_script(), (0, output, ''))
        self.assertEqual(self.swift_runs(), [['build', '--build-tests']])

    def test_the_arguments_after_a_double_dash_go_to_swift_test(self):
        self.write('Sources/Sema/Checker.swift')

        self.run_script('--', '--parallel', '--skip', 'Slow')

        self.assertEqual(self.swift_runs(), [['test', '--parallel', '--skip', 'Slow', '--filter', r'^(SemaTests)\.']])

    def test_a_base_other_than_origins_main_can_be_named(self):
        self.write('Sources/Sema/Checker.swift')
        self.commit('change the checker, in a branch below')
        self.git('checkout', '-q', '-b', 'above')
        self.write('Tests/SyntaxTests/LexerTests.swift')
        self.commit('change the lexer tests')

        self.run_script('--base', 'change')

        self.assertEqual(self.swift_runs(), [['test', '--filter', r'^(SyntaxTests)\.']])

    def test_the_changed_paths_can_be_given_in_a_file_in_place_of_git(self):
        paths = os.path.join(self.directory, 'changed-paths.json')
        with open(paths, 'w', encoding='utf-8') as f:
            json.dump(['Tests/ToolTests/ToolTests.swift'], f)
        self.write('Sources/Sema/Checker.swift')

        self.run_script('--changed-paths', paths)

        self.assertEqual(self.swift_runs(), [['test', '--filter', r'^(ToolTests)\.']])

    def test_it_tests_the_package_in_the_package_directory_wherever_it_runs_from(self):
        self.write('Sources/Sema/Checker.swift')
        self.assertNotEqual(os.getcwd(), self.repository)

        self.run_script()

        with open(self.log, encoding='utf-8') as log:
            self.assertEqual([json.loads(line)['directory'] for line in log], [self.repository])

    def test_it_exits_with_the_status_swift_exits_with(self):
        self.write('Sources/Sema/Checker.swift')

        self.assertEqual(self.run_script(status=1)[0], 1)

    def test_a_base_git_does_not_know_is_reported_and_nothing_runs(self):
        status, output, errors = self.run_script('--base', 'missing')

        self.assertEqual((status, output), (2, ''))
        self.assertIn("can't find the branch 'missing'", errors)
        self.assertEqual(self.swift_runs(), [])


if __name__ == '__main__':
    unittest.main()
