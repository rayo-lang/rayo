"""Prints the test targets that a change reaches through the package manifest's dependencies, for CI to run only
those:

    swift package dump-package > package.json
    python3 scripts/select_tests.py package.json changed-paths.json

`changed-paths.json` holds the changed paths, relative to the package's root, as a JSON array. The script prints
`all`, `none`, or the regular expression that `swift test --filter` takes to run only the selected targets' tests.
"""

import json
import sys

# The kinds of dependency that name a target of the package; a product is another package's.
TARGET_DEPENDENCIES = ('byName', 'target')


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


def selection(package, changed_paths):
    targets = package['targets']
    changed = {target_holding(targets, path) for path in changed_paths}

    # A path in no target's directory, such as the manifest or CI's, can change what any test target does.
    if None in changed:
        return 'all'

    by_name = {target['name']: target for target in targets}
    selected = sorted(target['name'] for target in targets
                      if target['type'] == 'test' and reaches(target['name'], changed, by_name))
    # A change that reaches no test target still has to build, which `none` asks for.
    return '^(' + '|'.join(selected) + r')\.' if selected else 'none'


def main(arguments):
    if len(arguments) != 2:
        print('usage: select_tests.py <package.json> <changed-paths.json>', file=sys.stderr)
        return 2
    # Windows reads a file in its own code page unless told otherwise.
    with open(arguments[0], encoding='utf-8') as package, open(arguments[1], encoding='utf-8') as paths:
        print(selection(json.load(package), json.load(paths)))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
