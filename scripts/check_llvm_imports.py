"""Checks that only the directories in `ALLOWED` import LLVM's C modules, `CLLVM` and `CLLVMJIT`, and that no file
re-exports them. A target can import a module it reaches only through another dependency, so the package manifest
can't enforce this.

    python3 scripts/check_llvm_imports.py   # writes each import that breaks the rule, and fails if there is any
"""

import os
import re
import sys

# The directories whose Swift files may import LLVM's C modules.
ALLOWED = ['Sources/LLVM', 'Sources/RayoLLVMInstall', 'Tests/RayoLLVMTests']

# An import declaration of one of the C modules, or of a submodule or a declaration of one, where a statement starts:
# at the start of a line or after a `;`, behind any attributes and access level. Its groups are the attributes, the
# `import` keyword and the module.
IMPORT = re.compile(r'(?:^|;)\s*((?:@\w+(?:\([^)]*\))?\s+)*)(?:(?:public|package|internal|fileprivate|private)\s+)?'
                    r'(import)\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?(CLLVM|CLLVMJIT)\b',
                    re.MULTILINE)
# The opening of a string literal: a raw string's `#`s, then one quote or three.
STRING_OPENING = re.compile(r'(#*)("""|")')


def swift_files(root):
    for top in ('Sources', 'Tests'):
        for directory, subdirectories, files in os.walk(os.path.join(root, top)):
            subdirectories.sort()
            for name in sorted(files):
                if name.endswith('.swift'):
                    yield os.path.relpath(os.path.join(directory, name), root).replace(os.sep, '/')


def code(text):
    """`text` with every comment and string literal blanked out, keeping its newlines, so what matches in the result
    is code, on the line it was written on."""
    blanked = list(text)
    position = 0
    while position < len(text):
        end = literal_end(text, position)
        # Code is kept as it is.
        if end is None:
            position += 1
            continue
        # A comment or a string becomes spaces, but for its newlines.
        for index in range(position, end):
            if blanked[index] != '\n':
                blanked[index] = ' '
        position = end
    return ''.join(blanked)


def literal_end(text, start):
    """Where the comment or string literal that starts at `start` ends, or None when none starts there."""
    # A line comment runs to the end of its line.
    if text.startswith('//', start):
        end = text.find('\n', start)
        return len(text) if end == -1 else end

    # A block comment runs to the `*/` that closes it.
    if text.startswith('/*', start):
        return block_comment_end(text, start)

    # A string runs to the quotes, and as many `#`s as it opened with, that close it.
    opening = STRING_OPENING.match(text, start)
    if opening:
        return string_end(text, opening.end(), hashes=opening.group(1), quote=opening.group(2))

    # Anything else is code.
    return None


def block_comment_end(text, start):
    """Where the block comment that starts at `start` ends, after the comments it holds."""
    depth = 0
    position = start
    while position < len(text):
        # A `/*` opens a comment inside the one around it, which its own `*/` closes.
        if text.startswith('/*', position):
            depth += 1
            position += 2
        # A `*/` closes the innermost comment, and the last one closes the whole.
        elif text.startswith('*/', position):
            depth -= 1
            position += 2
            if depth == 0:
                return position
        # Anything else is part of the comment.
        else:
            position += 1
    # An unclosed comment runs to the end of the file.
    return len(text)


def string_end(text, start, hashes, quote):
    """Where the string literal whose contents start at `start` ends, given the `#`s and quote it opened with."""
    escape = '\\' + hashes
    closing = quote + hashes
    position = start
    while position < len(text):
        # An interpolation is code, up to the `)` that closes it, and may hold strings and comments of its own.
        if text.startswith(escape + '(', position):
            position = interpolation_end(text, position + len(escape) + 1)
        # Any other escape takes the character after it, which may be a quote.
        elif text.startswith(escape, position):
            position += len(escape) + 1
        # The closing quote ends the string.
        elif text.startswith(closing, position):
            return position + len(closing)
        # A one-line string ends at its line's end even when nothing closes it.
        elif quote == '"' and text[position] == '\n':
            return position
        # Anything else is part of the string.
        else:
            position += 1
    # An unclosed string runs to the end of the file.
    return len(text)


def interpolation_end(text, start):
    """Where the interpolation whose code starts at `start`, after its `(`, ends: just past its `)`."""
    depth = 1
    position = start
    while position < len(text):
        # A comment or a string inside the interpolation is skipped whole, so its brackets count for nothing.
        end = literal_end(text, position)
        if end is not None:
            position = end
            continue
        # A `(` opens a bracket inside the interpolation, and a `)` closes the innermost, the last one the whole.
        if text[position] == '(':
            depth += 1
        elif text[position] == ')':
            depth -= 1
            if depth == 0:
                return position + 1
        position += 1
    # An unclosed interpolation runs to the end of the file.
    return len(text)


def listed(names):
    return names[0] if len(names) == 1 else ', '.join(names[:-1]) + ' and ' + names[-1]


def file_findings(path, text, allowed):
    is_allowed = any(path.startswith(directory + '/') for directory in allowed)
    found = []
    for match in IMPORT.finditer(code(text)):
        attributes, module = match.group(1), match.group(3)
        number = text.count('\n', 0, match.start(2)) + 1
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


def main(root):
    found = findings(root)
    # Each finding goes to standard error, and any fails the check.
    if found:
        print('\n'.join(found), file=sys.stderr)
        return 1
    print('checked')
    return 0


if __name__ == '__main__':
    sys.exit(main(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
