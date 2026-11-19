"""Runs the tests of the test targets that a change reaches through the package manifest's dependencies, and skips
the rest:

    python3 scripts/run_affected_tests.py [--base <branch>] [-- <swift test arguments>]

The change is every commit since the branch left its base, `origin/main` unless `--base` names another, with every
change not yet committed, staged or not, and every untracked file. A change to a file the tests read outside every
target, such as the manifest, CI's workflow or a proof program, tests every test target, and a change that no test
reaches only builds the tests. The arguments after `--` go to `swift test`, beside the filter that picks the tests.

CI names the paths a pull request changes in a JSON array instead, which `--changed-paths <file>` reads in place of
asking git.
"""

import argparse
import json
import os
import subprocess
import sys

from select_tests import selection, test_targets


def arguments_parser():
    parser = argparse.ArgumentParser(prog='run_affected_tests.py', usage='%(prog)s [--base <branch> | '
                                     '--changed-paths <file>] [-- <swift test arguments>]')
    source = parser.add_mutually_exclusive_group()
    source.add_argument('--base', default='origin/main', help='the branch the change is made on')
    source.add_argument('--changed-paths', help='a JSON array of the changed paths, to test in place of the change')
    return parser


def split_at_double_dash(arguments):
    """The arguments before the first `--`, and those after it."""
    if '--' not in arguments:
        return arguments, []
    end = arguments.index('--')
    return arguments[:end], arguments[end + 1:]


class Failure(Exception):
    """A step that stops the run before any test does: what to tell the user, if the tool that failed hasn't told
    them already, and the status to exit with."""

    def __init__(self, message, status=2):
        super().__init__(message)
        self.message = message
        self.status = status


def git(root, *arguments):
    """What git prints for the arguments. Git failing stops the run, with what git says."""
    result = subprocess.run(['git', *arguments], cwd=root, capture_output=True)
    if result.returncode != 0:
        said = result.stderr.decode('utf-8').strip()
        raise Failure(said or f"'git {' '.join(arguments)}' failed with status {result.returncode}")
    return result.stdout.decode('utf-8')


def fork_point(root, base):
    """The commit where the branch left `base`."""
    # Asked quietly, git fails with status 1, and says nothing, only where it can't find the commit.
    found = subprocess.run(['git', 'rev-parse', '--verify', '--quiet', base + '^{commit}'], cwd=root,
                           capture_output=True)
    if found.returncode == 1:
        raise Failure(f"can't find the branch '{base}' that the change is made on; name it with --base")
    return git(root, 'merge-base', base, 'HEAD').strip()


def changed_since(root, base):
    """The paths the change touches since the branch left `base`."""
    fork = fork_point(root, base)

    # Comparing the fork with the working tree takes in what's committed and what isn't, staged or not; an untracked
    # file is new, and git names it apart. A rename counts as its old path and its new one, so a file moved out of a
    # target still tests that target. Paths end in a NUL, so git writes each as it is, unquoted.
    changed = git(root, 'diff', '--name-only', '--no-renames', '-z', fork)
    untracked = git(root, 'ls-files', '--others', '--exclude-standard', '-z')
    return [path for path in (changed + untracked).split('\0') if path]


def read_changed_paths(file):
    # Windows reads a file in its own code page unless told otherwise.
    with open(file, encoding='utf-8') as paths:
        return json.load(paths)


def dump_package(root):
    """The package's manifest, as `swift package dump-package` prints it."""
    package = subprocess.run(['swift', 'package', 'dump-package'], cwd=root, stdout=subprocess.PIPE)
    # SwiftPM says itself what stops it reading the manifest.
    if package.returncode != 0:
        raise Failure(None, package.returncode)
    return json.loads(package.stdout)


def plan(selected, every, swift_arguments):
    """What to tell the user, and the `swift` command that tests the selected test targets, of every one the package
    has."""
    if not selected:
        return 'No test target depends on the change, so the tests are only built', ['swift', 'build', '--build-tests']
    if selected == every:
        return 'Testing every test target', ['swift', 'test', *swift_arguments]
    test_filter = '^(' + '|'.join(selected) + r')\.'
    return 'Testing ' + ', '.join(selected), ['swift', 'test', *swift_arguments, '--filter', test_filter]


def run(root, arguments):
    own_arguments, swift_arguments = split_at_double_dash(arguments)
    options = arguments_parser().parse_args(own_arguments)

    if options.changed_paths:
        changed = read_changed_paths(options.changed_paths)
    else:
        changed = changed_since(root, options.base)
    manifest = dump_package(root)

    message, command = plan(selection(manifest, changed), test_targets(manifest), swift_arguments)
    print(message, flush=True)
    return subprocess.run(command, cwd=root).returncode


def main(root, arguments):
    try:
        return run(root, arguments)
    except Failure as failure:
        if failure.message:
            print(f'run_affected_tests.py: {failure.message}', file=sys.stderr)
        return failure.status


if __name__ == '__main__':
    sys.exit(main(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), sys.argv[1:]))
