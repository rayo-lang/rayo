"""Checks the repository's Markdown: every relative link and heading anchor resolves, and the docs follow the
spec's style guide in their layout, their punctuation, the fences of their Rayo code and the length of their
sentences and paragraphs.

    python3 scripts/check_docs.py                     # prints each finding, and fails if there is any
    python3 scripts/check_docs.py --update-baseline   # records each file's long sentences and paragraphs

Long sentences and paragraphs are held to a baseline, since chapters written before the style guide break the
limits: a file may never get worse, and a file that gets better lowers its baseline.
"""

import json
import os
import re
import sys

LINK = re.compile(r'\]\(([^)\s]+)\)')
CODE_SPAN = re.compile(r'`[^`]*`')
FENCE = re.compile(r'(?P<indent> *)(?P<backticks>`{3,})(?P<info>.*)')
SENTENCE_LIMIT = 40
PARAGRAPH_LIMIT = 120
BASELINE = 'scripts/readability-baseline.json'


def without_code_spans(text):
    # Each span becomes one word, so a link whose text is code, such as [`when`](…), stays a link.
    return CODE_SPAN.sub('code', text)


def markdown_files(root):
    for directory, subdirectories, files in os.walk(root):
        subdirectories[:] = sorted(d for d in subdirectories if not d.startswith('.'))
        for name in sorted(files):
            if name.endswith('.md'):
                yield os.path.relpath(os.path.join(directory, name), root)


def lines_and_opening_fences(lines):
    # Pairs each line with whether it is code (a fence line, or a line between an opening fence and its close) and with
    # the fence it opens, if it opens a code block.
    opener = None
    for line in lines:
        fence = FENCE.fullmatch(line)
        if opener is None:
            opener = fence
            yield line, fence is not None, fence
        else:
            if closes(fence, opener):
                opener = None
            yield line, True, None


def lines_marked_as_code(lines):
    for line, is_code, _ in lines_and_opening_fences(lines):
        yield line, is_code


def opening_fences(text):
    for number, (_, _, opener) in enumerate(lines_and_opening_fences(text.splitlines()), 1):
        if opener:
            yield number, opener


def closes(fence, opener):
    # As in CommonMark: no info string, at least the opener's backticks, and at most three spaces more indented.
    return (fence is not None and not fence['info'].strip()
            and len(fence['backticks']) >= len(opener['backticks'])
            and len(fence['indent']) <= len(opener['indent']) + 3)


def prose_lines(text):
    for number, (line, is_code) in enumerate(lines_marked_as_code(text.splitlines()), 1):
        if not is_code:
            yield number, line


def anchor(heading):
    # GitHub's slug: lowercase, punctuation dropped, spaces turned into hyphens.
    slug = re.sub(r'[^\w\- ]', '', heading.strip().lower())
    return slug.replace(' ', '-')


def anchors(text):
    return {anchor(m.group(1)) for _, line in prose_lines(text) for m in [re.match(r'#+\s+(.*)', line)] if m}


def link_findings(texts, path, text):
    for number, line in prose_lines(text):
        for match in LINK.finditer(without_code_spans(line)):
            if re.match(r'[a-z]+:', match.group(1)):
                continue
            target, _, heading = match.group(1).partition('#')
            target_path = os.path.normpath(os.path.join(os.path.dirname(path), target)) if target else path
            if target_path not in texts and not os.path.exists(os.path.join(texts.root, target_path)):
                yield f'{path}:{number}: missing file {match.group(1)}'
            elif heading and target_path in texts and heading not in texts.anchors(target_path):
                yield f'{path}:{number}: missing heading {match.group(1)}'


def follows_the_style_guide(path):
    # The agent docs are instructions to agents, written to their own conventions.
    return path not in ('AGENTS.md', 'CLAUDE.md') and not path.startswith('docs/agents/')


def dash_findings(path, text):
    for number, line in prose_lines(text):
        if '—' in line:
            yield f'{path}:{number}: dash: use a colon, a comma or a new sentence'


def fence_findings(path, text):
    # Swift, the compiler's language, appears only in the skills, so a swift block here is Rayo code; each block names
    # its language, so Rayo code is never left unmarked.
    for number, opener in opening_fences(text):
        language = opener['info'].lower().split()[:1]
        if language == ['swift']:
            yield f'{path}:{number}: swift fence: fence Rayo code as rayo'
        elif not language:
            yield f"{path}:{number}: fence with no language: name the block's language, such as rayo"


def layout_findings(path, text):
    lines = text.splitlines()
    for number, (line, is_code) in enumerate(lines_marked_as_code(lines), 1):
        previous = lines[number - 2] if number > 1 else ''
        if is_code:
            continue
        elif not line and not previous and number > 1:
            yield f'{path}:{number}: two blank lines in a row'
        elif line.startswith('#') and previous:
            yield f'{path}:{number}: no blank line before this heading'
        elif line.startswith('|') and previous and not previous.startswith('|'):
            yield f'{path}:{number}: no blank line before this table'
        elif line.startswith('- ') and previous and not re.match(r' *- | ', previous):
            yield f'{path}:{number}: no blank line before this list'
        elif re.match(r'[A-Za-z`*]', line) and previous.startswith('- '):
            yield f'{path}:{number}: no blank line between this paragraph and the list above'


def prose_blocks(text):
    # Paragraphs and list items, outside code blocks, headings and tables.
    block = []
    for line, is_code in lines_marked_as_code(text.splitlines() + ['']):
        if is_code or line.startswith(('#', '|')) or not line.strip():
            if block:
                yield ' '.join(block)
            block = []
        elif starts_item := re.match(r' *(- |\d+\. )', line):
            if block:
                yield ' '.join(block)
            block = [line[starts_item.end():]]
        else:
            block.append(line.strip())


def words(text):
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', without_code_spans(text))
    return [w for w in text.split() if re.search(r'\w', w)]


def sentences(block):
    # A sentence may end inside bold, as a bullet's label does: `- **Owning values.** These are …`.
    return re.split(r'(?<=[.!?])(?:\*\*)?\s+(?=[A-Z`*\[(])', block)


def long_sentences(text):
    return sum(len(words(s)) > SENTENCE_LIMIT for block in prose_blocks(text) for s in sentences(block))


def long_paragraphs(text):
    return sum(len(words(block)) > PARAGRAPH_LIMIT for block in prose_blocks(text))


MEASURES = [  # baseline key, singular and plural nouns, limit in words, counter
    ('sentences', 'sentence', SENTENCE_LIMIT, long_sentences),
    ('paragraphs', 'paragraph', PARAGRAPH_LIMIT, long_paragraphs),
]


def readability(text):
    return {key: counter(text) for key, _, _, counter in MEASURES}


def readability_findings(baseline, path, text):
    counts = readability(text)
    for key, noun, limit, _ in MEASURES:
        count = counts[key]
        allowed = baseline.get(path, {}).get(key, 0)
        nouns = noun if count == 1 else key
        if count > allowed:
            yield f"{path}: {count} {nouns} over {limit} words, more than the baseline's {allowed}"
        elif count < allowed:
            # A baseline left above the count would let the file grow worse again unnoticed.
            yield (f"{path}: {count} {nouns} over {limit} words, fewer than the baseline's {allowed}: "
                   'lower it with scripts/check_docs.py --update-baseline')


class Texts(dict):
    def __init__(self, root):
        super().__init__()
        self.root = root
        self._anchors = {}
        for path in markdown_files(root):
            with open(os.path.join(root, path)) as f:
                self[path] = f.read()

    def anchors(self, path):
        if path not in self._anchors:
            self._anchors[path] = anchors(self[path])
        return self._anchors[path]

    def checked_for_style(self):
        return {path: text for path, text in self.items() if follows_the_style_guide(path)}


def read_baseline(root):
    path = os.path.join(root, BASELINE)
    if not os.path.exists(path):
        return {}
    with open(path) as f:
        return json.load(f)


def update_baseline(root):
    baseline = {}
    for path, text in Texts(root).checked_for_style().items():
        counts = readability(text)
        if any(counts.values()):
            baseline[path] = counts
    os.makedirs(os.path.join(root, os.path.dirname(BASELINE)), exist_ok=True)
    with open(os.path.join(root, BASELINE), 'w') as f:
        json.dump(baseline, f, indent=2)
        f.write('\n')


def findings(root):
    texts = Texts(root)
    styled = texts.checked_for_style()
    baseline = read_baseline(root)
    found = []
    for path, text in texts.items():
        found += link_findings(texts, path, text)
        if path in styled:
            found += dash_findings(path, text)
            found += fence_findings(path, text)
            found += layout_findings(path, text)
            found += readability_findings(baseline, path, text)
    for path in baseline:
        if path not in styled:
            found.append(f'{BASELINE}: {path} is not a checked file: update it with scripts/check_docs.py --update-baseline')
    return found


def main(arguments):
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if '--update-baseline' in arguments:
        update_baseline(root)
    found = findings(root)
    print('\n'.join(found) if found else 'checked')
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
