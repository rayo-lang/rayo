import unittest

from benchmark import (UNCOUNTED, linux_measures, loops, macos_measures, programs, ref_let_loops, regressions,
                       stage_costs, straight_line, summary)

MACOS_TIME = '''        0.31 real         0.27 user         0.03 sys
            52183040  maximum resident set size
                   0  average shared memory size
                  14  involuntary context switches
          2647118212  instructions retired
           961339027  cycles elapsed
            40322368  peak memory footprint
'''


def measures(instructions, memory, seconds=1.0):
    return {'instructions': instructions, 'peak_memory_bytes': memory, 'wall_seconds': seconds}


class MeasuresTests(unittest.TestCase):
    def test_macos_time_gives_the_instructions_retired_and_the_peak_memory_footprint(self):
        self.assertEqual(macos_measures(MACOS_TIME), {'instructions': 2647118212, 'peak_memory_bytes': 40322368})

    def test_linux_perf_gives_the_instructions_and_time_the_largest_resident_set_in_kilobytes(self):
        perf = '2647118212,,instructions:u,1203000,100.00,,\n'
        self.assertEqual(linux_measures(perf, '51000\n'), {'instructions': 2647118212, 'peak_memory_bytes': 52224000})

    def test_an_instruction_count_the_system_doesnt_give_is_none(self):
        perf = '<not supported>,,instructions:u,0,100.00,,\n'
        self.assertEqual(linux_measures(perf, '51000\n')['instructions'], None)

    def test_a_count_of_no_instructions_which_a_virtual_machine_gives_is_none(self):
        self.assertEqual(macos_measures(MACOS_TIME.replace('2647118212', '0'))['instructions'], None)
        self.assertEqual(linux_measures('0,,instructions:u,0,100.00,,\n', '51000\n')['instructions'], None)


class RegressionTests(unittest.TestCase):
    def test_a_rise_in_instructions_or_memory_past_the_threshold_is_a_regression(self):
        baseline = {'check/loops-200': measures(1000, 1000), 'check/loops-400': measures(2000, 2000)}
        current = {'check/loops-200': measures(1051, 1000), 'check/loops-400': measures(2000, 2102)}

        self.assertEqual(regressions(baseline, current, threshold=5.0), [
            'check/loops-200: instructions rose 5.1%, past 5.0%',
            'check/loops-400: peak memory rose 5.1%, past 5.0%',
        ])

    def test_wall_time_falls_within_any_rise_and_a_rise_to_the_threshold_does_too(self):
        baseline = {'check/loops-200': measures(1000, 1000, seconds=1.0)}
        current = {'check/loops-200': measures(1050, 1000, seconds=9.0)}

        self.assertEqual(regressions(baseline, current, threshold=5.0), [])

    def test_a_measure_either_run_lacks_and_a_benchmark_either_run_lacks_are_not_compared(self):
        baseline = {'check/loops-200': measures(None, 1000), 'check/loops-400': measures(1000, 1000)}
        current = {'check/loops-200': measures(9000, 1000), 'check/loops-800': measures(9000, 9000)}

        self.assertEqual(regressions(baseline, current, threshold=5.0), [])


class StageCostTests(unittest.TestCase):
    def test_what_each_run_does_past_checking_costs_the_difference_from_checking(self):
        current = {
            'check/loops-200': measures(280, 28),
            'emit-checked/loops-200': measures(300, 30),
            'emit-ir/loops-200': measures(330, 30),
            'compile-debug/loops-200': measures(900, 50),
            'compile-release/loops-200': measures(2000, 60),
        }

        self.assertEqual(stage_costs(current, 'loops-200'), {
            'printing the checked program': 20, 'printing the IR': 50, 'debug emitting': 620,
            'release emitting': 1720,
        })

    def test_a_stage_whose_runs_lack_a_count_has_no_cost(self):
        current = {'check/loops-200': measures(None, 28), 'emit-ir/loops-200': measures(330, 30)}

        self.assertEqual(stage_costs(current, 'loops-200'), {})


def baseline_of(results):
    return {'commit': '2042c3c1', 'code': 'main', 'date': '2026-11-23T10:00:00+00:00',
            'machine': {'processor': 'Apple M3 Pro'}, 'results': results}


class SummaryTests(unittest.TestCase):
    def test_a_summary_tables_each_benchmark(self):
        results = {'check/loops-200': measures(2647118212, 40322368, seconds=0.152)}

        self.assertEqual(summary(results, 'rayoc at 1a2b3c4d'), '''\
### Benchmarks of rayoc at 1a2b3c4d

| Benchmark | Instructions | Peak memory | Wall time |
| --- | ---: | ---: | ---: |
| check/loops-200 | 2,647 M | 38.5 MiB | 152 ms |
''')

    def test_a_summary_with_a_baseline_gives_each_change_from_it_and_lists_each_measure_that_rose(self):
        baseline = baseline_of({'check/loops-200': measures(1000, 2000, seconds=0.2)})
        results = {'check/loops-200': measures(1100, 1990, seconds=0.3), 'check/loops-400': measures(2000, 4000)}

        self.assertEqual(summary(results, 'rayoc at 1a2b3c4d', baseline, ['check/loops-200: rose']), '''\
### Benchmarks of rayoc at 1a2b3c4d

Compared with the baseline 2042c3c1 (main), measured 2026-11-23T10:00:00+00:00 on Apple M3 Pro.

| Benchmark | Instructions | Change | Peak memory | Change | Wall time | Wall time of the baseline |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| check/loops-200 | 0 M | +10.0% | 0.0 MiB | -0.5% | 300 ms | 200 ms |
| check/loops-400 | 0 M | - | 0.0 MiB | - | 1,000 ms | - |

These rose past the threshold:

- check/loops-200: rose
''')

    def test_a_summary_with_a_baseline_says_where_nothing_rose(self):
        baseline = baseline_of({'check/loops-200': measures(1000, 1000)})

        self.assertIn('\nNothing rose past the threshold.\n', summary({'check/loops-200': measures(1000, 1000)},
                                                                      'rayoc', baseline, []))

    def test_a_summary_of_results_with_no_instruction_count_says_only_memory_was_compared(self):
        results = {'check/loops-200': measures(None, 1000)}

        self.assertIn('| check/loops-200 | - |', summary(results, 'rayoc'))
        self.assertIn(UNCOUNTED, summary(results, 'rayoc'))
        self.assertNotIn(UNCOUNTED, summary({'check/loops-200': measures(1000, 1000)}, 'rayoc'))


class ProgramTests(unittest.TestCase):
    def test_each_program_has_the_lines_its_description_gives(self):
        self.assertEqual(len(loops(10).splitlines()), 16 * 10 + 5)
        self.assertEqual(len(ref_let_loops(10).splitlines()), 7 * 10 + 2)
        self.assertEqual(len(straight_line(10).splitlines()), 2 * 10 + 6)

    def test_each_size_makes_each_program_with_five_turns_of_the_straight_line_for_each_copy_of_a_loop(self):
        self.assertEqual([name for name, _ in programs([200, 400])], [
            'loops-200', 'loops-400', 'ref-let-loops-200', 'ref-let-loops-400', 'straight-line-1000',
            'straight-line-2000',
        ])


if __name__ == '__main__':
    unittest.main()
