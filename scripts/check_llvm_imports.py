"""Checks that only the directories in `ALLOWED` import LLVM's C modules, `CLLVM` and `CLLVMJIT`, and that no file
re-exports them. A target can import a module it reaches only through another dependency, so the package manifest
can't enforce this.

    python3 scripts/check_llvm_imports.py   # prints each import that breaks the rule, and fails if there is any
"""

import os
import re
import sys

# The directories whose Swift files may import LLVM's C modules.
ALLOWED = ['Sources/LLVM', 'Sources/RayoLLVM', 'Sources/RayoLLVMInstall', 'Tests/RayoLLVMTests']

# An import declaration of one of the C modules, or of a submodule or a declaration of one, at the start of a line,
# after any attributes and access level. Its groups are the attributes and the module.
IMPORT = re.compile(r'^\s*((?:@\w+(?:\([^)]*\))?\s+)*)(?:(?:public|package|internal|fileprivate|private)\s+)?'
                    r'import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(CLLVM|CLLVMJIT)\b')
BLOCK_COMMENT = re.compile(r'/\*.*?\*/', re.DOTALL)


def swift_files(root):
    for top in ('Sources', 'Tests'):
        for directory, subdirectories, files in os.walk(os.path.join(root, top)):
            subdirectories.sort()
            for name in sorted(files):
                if name.endswith('.swift'):
                    yield os.path.relpath(os.path.join(directory, name), root).replace(os.sep, '/')


def without_block_comments(text):
    # Each comment keeps its newlines, so the lines after it keep their numbers.
    return BLOCK_COMMENT.sub(lambda comment: '\n' * comment.group().count('\n'), text)


def listed(names):
    return names[0] if len(names) == 1 else ', '.join(names[:-1]) + ' and ' + names[-1]


def file_findings(path, text, allowed):
    is_allowed = any(path.startswith(directory + '/') for directory in allowed)
    found = []
    for number, line in enumerate(without_block_comments(text).splitlines(), start=1):
        match = IMPORT.match(line)
        # A line that imports no C module is no finding.
        if not match:
            continue
        attributes, module = match.groups()
        # A re-export hands the C module to every module that imports this one, so no file may make one.
        if '@_exported' in attributes:
            found.append(f'{path}:{number}: re-exports {module}, which hands it to every module that imports this one')
        # Any other import is a finding outside the allowed directories.
        elif not is_allowed:
            found.append(f'{path}:{number}: imports {module}, which only {listed(allowed)} may import')
    return found


def findings(root, allowed=ALLOWED):
    found = []
    for path in sorted(swift_files(root)):
        with open(os.path.join(root, path), encoding='utf-8') as f:
            found += file_findings(path, f.read(), allowed)
    return found


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    found = findings(root)
    print('\n'.join(found) if found else 'checked')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main())
