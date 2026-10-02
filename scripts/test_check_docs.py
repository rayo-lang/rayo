import json
import os
import tempfile
import unittest

from check_docs import findings, update_baseline


class CheckDocsTests(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.mkdtemp()

    def write(self, path, text):
        full = os.path.join(self.root, path)
        os.makedirs(os.path.dirname(full), exist_ok=True)
        with open(full, 'w') as f:
            f.write(text)

    def test_a_link_to_a_missing_file_is_reported(self):
        self.write('README.md', 'See [the spec](docs/spec/01-values.md).\n')

        self.assertEqual(findings(self.root), ['README.md:1: missing file docs/spec/01-values.md'])

    def test_a_link_to_a_missing_heading_is_reported(self):
        self.write('docs/01-values.md', '# Values\n\n## The law of exclusivity: `&x`\n')
        self.write('README.md', 'See [it](docs/01-values.md#the-law-of-exclusivity-x) and [this](docs/01-values.md#moves).\n')

        self.assertEqual(findings(self.root), ['README.md:1: missing heading docs/01-values.md#moves'])

    def test_web_links_and_links_in_code_blocks_are_not_followed(self):
        self.write('README.md', 'See [Swift](https://swift.org).\n\n```md\n[gone](gone.md)\n```\n')

        self.assertEqual(findings(self.root), [])

    def test_links_in_code_spans_are_not_followed(self):
        self.write('README.md', 'Links read `([06](06-memory.md#anchor))` across chapters.\n')

        self.assertEqual(findings(self.root), [])

    def test_a_dash_in_the_docs_is_reported_but_not_in_the_agent_docs(self):
        self.write('docs/spec/01-values.md', 'A move — a handover.\n')
        self.write('docs/agents/domain.md', 'The glossary — the terms.\n')
        self.write('AGENTS.md', 'Rules — for agents.\n')

        self.assertEqual(findings(self.root), ['docs/spec/01-values.md:1: dash: use a colon, a comma or a new sentence'])

    def test_a_heading_with_no_blank_line_before_it_is_reported(self):
        self.write('README.md', '# Rayo\n\nIntro.\n## Key ideas\n\n```swift\nvar x = 1\n# not a heading\n```\n')

        self.assertEqual(findings(self.root), ['README.md:4: no blank line before this heading'])

    def test_a_table_with_no_blank_line_before_it_is_reported(self):
        self.write('README.md', 'The tiers:\n| Tier | Cost |\n| --- | --- |\n| Static | Zero |\n')

        self.assertEqual(findings(self.root), ['README.md:2: no blank line before this table'])

    def test_two_blank_lines_in_a_row_are_reported(self):
        self.write('README.md', 'One.\n\n\nTwo.\n')

        self.assertEqual(findings(self.root), ['README.md:3: two blank lines in a row'])

    def test_a_list_with_no_blank_line_before_it_is_reported(self):
        self.write('README.md', 'These move:\n- an assignment;\n    - nested\n- a return.\n')

        self.assertEqual(findings(self.root), ['README.md:2: no blank line before this list'])

    def test_a_paragraph_right_after_a_list_item_is_reported(self):
        self.write('README.md', 'These move:\n\n- an assignment;\n- a return.\n`consume` moves too.\n')

        self.assertEqual(findings(self.root), ['README.md:5: no blank line between this paragraph and the list above'])

    def test_a_sentence_over_forty_words_is_counted_against_the_baseline(self):
        forty = ' '.join(['word'] * 39) + ' end.'
        self.write('README.md', f'{forty} Then `a code span` and [a link](https://swift.org) {forty}\n')

        self.assertEqual(findings(self.root), ['README.md: 1 sentence over 40 words, more than the baseline\'s 0'])

    def test_a_paragraph_over_a_hundred_and_twenty_words_is_counted_against_the_baseline(self):
        twenty = 'Start ' + ' '.join(['word'] * 18) + ' end.'
        self.write('README.md', ' '.join([twenty] * 6) + '\n\n- ' + ' '.join([twenty] * 7) + '\n- Short.\n')

        self.assertEqual(findings(self.root), ['README.md: 1 paragraph over 120 words, more than the baseline\'s 0'])

    def test_a_bold_label_ends_its_own_sentence(self):
        thirty = 'Start ' + ' '.join(['word'] * 28) + ' end.'
        self.write('README.md', f'- **A projection access {" ".join(["word"] * 20)}.** {thirty}\n')

        self.assertEqual(findings(self.root), [])

    def test_a_file_at_its_baseline_passes(self):
        self.write('README.md', ' '.join(['word'] * 50) + '.\n')
        self.write('scripts/readability-baseline.json', json.dumps({'README.md': {'sentences': 1, 'paragraphs': 0}}))

        self.assertEqual(findings(self.root), [])

    def test_a_file_below_its_baseline_asks_for_the_baseline_to_be_lowered(self):
        self.write('README.md', 'Short.\n')
        self.write('scripts/readability-baseline.json', json.dumps({'README.md': {'sentences': 3, 'paragraphs': 0}}))

        self.assertEqual(findings(self.root), [
            "README.md: 0 sentences over 40 words, fewer than the baseline's 3: "
            'lower it with scripts/check_docs.py --update-baseline',
        ])

    def test_updating_the_baseline_records_each_file_over_a_limit(self):
        self.write('README.md', ' '.join(['word'] * 50) + '.\n')
        self.write('docs/spec/01-values.md', 'Short.\n')
        self.write('docs/agents/domain.md', ' '.join(['word'] * 50) + '.\n')

        update_baseline(self.root)

        with open(os.path.join(self.root, 'scripts/readability-baseline.json')) as f:
            self.assertEqual(json.load(f), {'README.md': {'sentences': 1, 'paragraphs': 0}})
        self.assertEqual(findings(self.root), [])

    def test_a_baseline_entry_for_a_missing_file_is_reported(self):
        self.write('README.md', 'Short.\n')
        self.write('scripts/readability-baseline.json', json.dumps({'docs/01-values.md': {'sentences': 3, 'paragraphs': 0}}))

        self.assertEqual(findings(self.root), [
            'scripts/readability-baseline.json: docs/01-values.md is not a checked file: '
            'update it with scripts/check_docs.py --update-baseline',
        ])


if __name__ == '__main__':
    unittest.main()
