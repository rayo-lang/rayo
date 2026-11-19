"""Selects the test targets that a change reaches through the package manifest's dependencies, so that a run tests
only those. `run_affected_tests.py` runs the tests it selects.

Run on its own, it reads changed paths, relative to the package's root, one a line, and prints the ones that can
change what a test does, as a JSON array, for CI to pass to its test jobs:

    git diff --name-only main HEAD | python3 scripts/select_tests.py
"""

import json
import re
import sys

# The paths whose change can change what a test does. The build reads only the package's sources, its tests and its
# manifest, and CI runs the tests through its workflow and its actions. The driver's tests also run each version's
# proof program, in `examples/v<version>/`, and compare what it prints with its expected output, whose line endings
# `.gitattributes` keeps.
TEST_PATHS = re.compile(r'''
    ^(Sources|Tests)/
    | ^Package\.(swift|resolved)$
    | ^\.github/(workflows/ci\.yml$|actions/)
    | ^examples/v[0-9.]+/
    | ^\.gitattributes$
''', re.VERBOSE)

# The kinds of dependency that name a target of the package; a product is another package's.
TARGET_DEPENDENCIES = ('byName', 'target')


def can_change_tests(path):
    return TEST_PATHS.search(path) is not None


def directory(target):
    # A target's sources are where the manifest says, or else in SwiftPM's default directory for its kind.
    return target.get('path') or ('Tests/' if target['type'] == 'test' else 'Sources/') + target['name']


def target_holding(targets, path):
    return next((target['name'] for target in targets if path.startswith(directory(target) + '/')), None)


def dependency_names(target):
    # Each dependency is an object with one key, its kind, whose value is a list that starts with the name.
    return [values[0] for dependency in target['dependencies']
            for kind, values in dependency.items() if kind in TARGET_DEPENDENCIES]


def reaches(name, changed, by_name):
    # A changed target reaches itself, and any other target reaches what one of its dependencies reaches.
    if name in changed:
        return True
    return any(reaches(dependency, changed, by_name)
               for dependency in dependency_names(by_name[name]) if dependency in by_name)


def test_targets(package):
    """The names of the package's test targets, sorted."""
    return sorted(target['name'] for target in package['targets'] if target['type'] == 'test')


def selection(package, changed_paths):
    """The names of the test targets that the changed paths reach, sorted. A path no test reads selects none."""
    targets = package['targets']
    changed = {target_holding(targets, path) for path in changed_paths if can_change_tests(path)}

    # A path that a test reads but no target holds, such as the manifest or CI's, can change what any test does.
    if None in changed:
        return test_targets(package)

    by_name = {target['name']: target for target in targets}
    return [name for name in test_targets(package) if reaches(name, changed, by_name)]


def main(arguments, standard_input):
    if arguments:
        print('usage: select_tests.py < changed-paths', file=sys.stderr)
        return 2
    paths = [line for line in standard_input.read().splitlines() if line]
    print(json.dumps([path for path in paths if can_change_tests(path)]))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:], sys.stdin))
