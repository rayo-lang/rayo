"""Runs the tests of the test targets that a change reaches through the package manifest's dependencies, and skips
the rest:

    python3 scripts/run_affected_tests.py [--base <branch>] [-- <swift test arguments>]

The change is every commit since the branch left its base, `origin/main` unless `--base` names another, with every
change not yet committed, staged or not, and every untracked file. A change to the manifest or to CI tests every test
target, and a change that no test reaches only builds the tests. The arguments after `--` go to `swift test`.

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


def git(root, *arguments):
    """What git prints for the arguments, or None when it fails."""
    result = subprocess.run(['git', *arguments], cwd=root, capture_output=True)
    return result.stdout.decode('utf-8') if result.returncode == 0 else None


def changed_since(root, base):
    """The paths the change touches since the branch left `base`, or None when git can't find `base`."""
    fork = git(root, 'merge-base', base, 'HEAD')
    if fork is None:
        return None

    # Comparing the fork with the working tree takes in what's committed and what isn't, staged or not; an untracked
    # file is new, and git names it apart. A rename counts as its old path and its new one, so a file moved out of a
    # target still tests that target. Paths end in a NUL, so git writes each as it is, unquoted.
    changed = git(root, 'diff', '--name-only', '--no-renames', '-z', fork.strip())
    untracked = git(root, 'ls-files', '--others', '--exclude-standard', '-z')
    return [path for path in (changed + untracked).split('\0') if path]


def read_changed_paths(file):
    # Windows reads a file in its own code page unless told otherwise.
    with open(file, encoding='utf-8') as paths:
        return json.load(paths)


def swift_command(selected, every, swift_arguments):
    """The `swift` command that tests the selected test targets, of every one the package has."""
    if not selected:
        return ['swift', 'build', '--build-tests']
    if selected == every:
        return ['swift', 'test', *swift_arguments]
    return ['swift', 'test', *swift_arguments, '--filter', '^(' + '|'.join(selected) + r')\.']


def description(selected, every):
    if not selected:
        return 'No test target depends on the change, so the tests are only built'
    if selected == every:
        return 'Testing every test target'
    return 'Testing ' + ', '.join(selected)


def main(root, arguments):
    own_arguments, swift_arguments = split_at_double_dash(arguments)
    options = arguments_parser().parse_args(own_arguments)

    if options.changed_paths:
        changed = read_changed_paths(options.changed_paths)
    else:
        changed = changed_since(root, options.base)
    if changed is None:
        print(f"run_affected_tests.py: can't find the branch '{options.base}' that the change is made on; "
              'name it with --base', file=sys.stderr)
        return 2

    # SwiftPM reads the manifest, and says itself what stops it.
    package = subprocess.run(['swift', 'package', 'dump-package'], cwd=root, stdout=subprocess.PIPE)
    if package.returncode != 0:
        return package.returncode

    manifest = json.loads(package.stdout)
    every = test_targets(manifest)
    selected = selection(manifest, changed)
    print(description(selected, every), flush=True)
    return subprocess.run(swift_command(selected, every, swift_arguments), cwd=root).returncode


if __name__ == '__main__':
    sys.exit(main(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), sys.argv[1:]))
