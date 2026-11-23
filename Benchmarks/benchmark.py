"""Measures a release `rayoc` from outside, as a user runs it, over generated programs at several sizes: the
instructions it retires and its peak memory, which the system reports for the process, and its wall-clock time.

    python3 Benchmarks/benchmark.py                                    # builds rayoc, measures it, prints the results
    python3 Benchmarks/benchmark.py --save --code 'main, as merged'    # saves the results as the commit's baseline
    python3 Benchmarks/benchmark.py --compare 2042c3c1                 # fails where a measure rose past its threshold

Each benchmark runs `rayoc` to one of the points it stops at. `--check` runs every check, from parsing through
lowering and the ownership checks to verifying the IR, and prints nothing; `--emit=checked` and `--emit=ir` run the same
and print the checked program or the IR; and a debug and a release compile go on to object code. A stage past checking
costs the difference from `--check`, and a check whose cost grows faster than the program shows in how `--check` grows;
a profiler then finds which check it is.

A baseline is named by the commit it measured, and records what the code there is, the machine, the build and how each
measure was taken. A comparison fails where the median instructions of a benchmark rose more than 5% over the
baseline's, or its median peak memory more than 20%, since peak memory varies between runs of one rayoc by up to 11%.
Wall-clock time varies with the machine's load, so it is reported and never compared.
It runs on macOS, where `/usr/bin/time -l` gives the measures, and on Linux, where `perf stat` and `/usr/bin/time`
give them.
"""

import argparse
import datetime
import json
import os
import platform
import re
import statistics
import subprocess
import sys
import tempfile
import time

BASELINES = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'baselines')
DEFAULT_SIZES = '200,400,800,1600'
DEFAULT_RUNS = 3
DEFAULT_INSTRUCTIONS_THRESHOLD = 5.0
# A run's peak memory varies with where its allocator lands, up to 11% between runs of one rayoc on one machine.
DEFAULT_MEMORY_THRESHOLD = 20.0
UNCOUNTED = "This machine didn't count the instructions rayoc retired, so only its peak memory was compared."

# The points rayoc stops at, each with the arguments that stop it there. A dump is written to /dev/null.
STOP_POINTS = [
    ('check', ['--check']),
    ('emit-checked', ['--emit=checked']),
    ('emit-ir', ['--emit=ir']),
    ('compile-debug', ['--debug', '-o', '{object}']),
    ('compile-release', ['--release', '-o', '{object}']),
]

# What each stage costs: the stop point after it, less the stop point before it. Every stop point runs every check
# first, so each stage past them is measured from `--check`.
STAGES = [
    ('printing the checked program', 'emit-checked', 'check'),
    ('printing the IR', 'emit-ir', 'check'),
    ('debug emitting', 'compile-debug', 'check'),
    ('release emitting', 'compile-release', 'check'),
]

PROGRAM_DESCRIPTIONS = [
    'loops-M: a main of M copies of a block of two loops over an array of eight structs, each copy with names of its '
    'own: 16 M + 5 lines',
    'ref-let-loops-M: a main of M copies of a block that borrows a var with a ref let, which stays in scope to the end '
    'of main, and loops three times reading it: 7 M + 2 lines',
    'straight-line-N: a main of one block of N turns, each lending s to a call and storing in it a new value worked '
    'out from the result through a let of its own: 2 N + 6 lines',
]


def loops(copies):
    """A `main` of `copies` copies of a block that fills an array of eight `Pair`s in one loop, and sums it in a second
    with an `if` and a `let` copy, each copy with names of its own."""
    blocks = []
    for n in range(copies):
        element = f'table{n}[j{n}]'
        blocks.append(f'''    var table{n}: [8 of Pair] = .init(repeating: Pair(a: 0, b: 0))
    var i{n}: UInt = 0
    while i{n} < table{n}.count {{
        table{n}[i{n}].a = seed + Int(i{n}) * 3
        table{n}[i{n}].b = table{n}[i{n}].a % 7
        i{n} += 1
    }}
    var total{n} = 0
    var j{n}: UInt = 0
    while j{n} < table{n}.count {{
        if {element}.a > 5 {{ total{n} += {element}.b }} else {{ total{n} -= 1 }}
        let snapshot{n} = copy {element}
        total{n} += snapshot{n}.a - snapshot{n}.b
        j{n} += 1
    }}
    print(total{n})''')
    return 'func main() {\n    let seed = 3\n' + '\n'.join(blocks) + '\n}\n\nstruct Pair(var a: Int, var b: Int)\n'


def ref_let_loops(copies):
    """A `main` of `copies` copies of a block that borrows a `var` with a `ref let`, which stays in scope to the end of
    `main`, and loops three times printing the borrowed value plus the count."""
    blocks = []
    for n in range(copies):
        blocks.append(f'''    var x{n} = {n}
    ref let r{n} = &x{n}
    var i{n} = 0
    while i{n} < 3 {{
        print(r{n} + i{n})
        i{n} += 1
    }}''')
    return 'func main() {\n' + '\n'.join(blocks) + '\n}\n'


def straight_line(turns):
    """A `main` of one block of `turns` turns, each lending `s` to a call and storing in it a new value worked out from
    the result through a `let` of its own."""
    lines = [f'    let x{n} = double(&s) + {n}\n    s = consume x{n}' for n in range(turns)]
    return ('func main() {\n    var s = 0\n' + '\n'.join(lines) + '\n    print(s)\n}\n\n'
            'func double(_ n: &Int) -> Int { n * 2 }\n')


def programs(sizes):
    """Each program a benchmark compiles at each of `sizes`, by name, in order of size within each kind. A straight
    line has five turns for each copy of a loop, since a turn is far smaller than a copy."""
    made = [(f'loops-{size}', loops(size)) for size in sizes]
    made += [(f'ref-let-loops-{size}', ref_let_loops(size)) for size in sizes]
    made += [(f'straight-line-{5 * size}', straight_line(5 * size)) for size in sizes]
    return made


def counted(instructions):
    # A process can't run without retiring instructions, so a count of none, which a virtual machine may give, means
    # the system didn't count them.
    return instructions or None


def macos_measures(output):
    """The instructions retired, or None where the system didn't count them, and the peak memory footprint, in bytes,
    that `/usr/bin/time -l` wrote."""
    def count(label):
        found = re.search(r'^\s*(\d+)\s+' + label + r'$', output, re.MULTILINE)
        return int(found.group(1)) if found else None
    return {'instructions': counted(count('instructions retired')),
            'peak_memory_bytes': count('peak memory footprint')}


def linux_measures(perf_output, time_output):
    """The instructions that `perf stat -x,` counted, or None where it couldn't, and the largest resident set, in
    bytes, that `/usr/bin/time -f %M` wrote in kilobytes."""
    instructions = None
    for line in perf_output.splitlines():
        fields = line.split(',')
        if len(fields) > 2 and fields[2].startswith('instructions') and fields[0].isdigit():
            instructions = int(fields[0])
    return {'instructions': counted(instructions), 'peak_memory_bytes': int(time_output.split()[-1]) * 1024}


def measure_once(command, directory):
    """The measures of one run of `command`, which must succeed: its instructions, its peak memory and its wall time."""
    report = os.path.join(directory, 'measures.txt')
    if sys.platform == 'darwin':
        wrapped = ['/usr/bin/time', '-l', '-o', report, *command]
    else:
        counts = os.path.join(directory, 'counts.txt')
        wrapped = ['perf', 'stat', '-x,', '-e', 'instructions:u', '-o', counts,
                   '/usr/bin/time', '-f', '%M', '-o', report, *command]

    start = time.perf_counter()
    result = subprocess.run(wrapped, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    seconds = time.perf_counter() - start
    if result.returncode != 0:
        raise RuntimeError(f"'{' '.join(command)}' failed: {result.stderr.decode('utf-8', 'replace')}")

    with open(report, encoding='utf-8') as f:
        reported = f.read()
    if sys.platform == 'darwin':
        found = macos_measures(reported)
    else:
        with open(counts, encoding='utf-8') as f:
            found = linux_measures(f.read(), reported)
    return {**found, 'wall_seconds': seconds}


def median_measures(runs):
    """The median of each measure over `runs`, or None for a measure some run lacks."""
    def median(key):
        values = [run[key] for run in runs]
        return None if None in values else statistics.median(values)
    return {key: median(key) for key in ('instructions', 'peak_memory_bytes', 'wall_seconds')}


def measure_all(rayoc, sources, wanted, runs):
    """The median measures of each benchmark over `sources` whose name holds `wanted`, over `runs` runs of `rayoc`
    each, printing each as it is measured."""
    results = {}
    with tempfile.TemporaryDirectory() as directory:
        for program, source in sources:
            path = os.path.join(directory, program + '.rayo')
            with open(path, 'w', encoding='utf-8') as f:
                f.write(source)
            for stop, arguments in STOP_POINTS:
                name = f'{stop}/{program}'
                if wanted and wanted not in name:
                    continue
                filled = [argument.format(object=os.path.join(directory, 'out.o')) for argument in arguments]
                measured = [measure_once([rayoc, *filled, path], directory) for _ in range(runs)]
                results[name] = median_measures(measured)
                print(row(name, results[name]), flush=True)
    return results


def stage_costs(results, program):
    """The instructions each stage takes over `program`, as the difference between the stop points around it, for each
    stage whose stop points both have a count."""
    costs = {}
    for stage, after, before in STAGES:
        later = results.get(f'{after}/{program}', {}).get('instructions')
        earlier = results.get(f'{before}/{program}', {}).get('instructions')
        if later is not None and earlier is not None:
            costs[stage] = later - earlier
    return costs


def regressions(baseline, current, instructions_threshold, memory_threshold):
    """A line for each measure of a benchmark in both runs whose instructions or peak memory rose more than its
    threshold, in percent, over the baseline's. Wall time is never compared."""
    found = []
    measures = (('instructions', 'instructions', instructions_threshold),
                ('peak_memory_bytes', 'peak memory', memory_threshold))
    for name in sorted(set(baseline) & set(current)):
        for key, label, threshold in measures:
            old, new = baseline[name].get(key), current[name].get(key)
            # Compared in whole counts, since a rise to exactly the threshold may come out a hair past it as a ratio.
            if old and new is not None and (new - old) * 100 > old * threshold:
                found.append(f'{name}: {label} rose {(new - old) * 100 / old:.1f}%, past {threshold:.1f}%')
    return found


def shown(measures):
    """`measures` as people read them: instructions in millions, peak memory in mebibytes, wall time in milliseconds."""
    instructions = measures['instructions']
    return ('-' if instructions is None else f'{instructions / 1e6:,.0f} M',
            f"{measures['peak_memory_bytes'] / 2**20:,.1f} MiB", f"{measures['wall_seconds'] * 1000:,.0f} ms")


def row(name, measures):
    instructions, memory, seconds = shown(measures)
    return f'{name:<36} {instructions:>14} {memory:>12} {seconds:>10}'


def described(baseline):
    """The baseline as a comparison names it: its commit, what the code there is, and when and where it was measured."""
    return (f"the baseline {baseline['commit']} ({baseline['code']}), measured {baseline['date']} on "
            f"{baseline['machine']['processor']}")


def change(old, new):
    """The change from `old` to `new` as a signed percentage, or `-` where either is missing."""
    return '-' if not old or new is None else f'{(new - old) * 100 / old:+.1f}%'


def summary(results, measured, baseline=None, found=()):
    """A Markdown report of `results`, the measures of `measured`, with each change from `baseline` and each measure
    in `found` that rose past its threshold over it, if there is a baseline."""
    lines = [f'### Benchmarks of {measured}', '']
    if baseline is None:
        lines += ['| Benchmark | Instructions | Peak memory | Wall time |', '| --- | ---: | ---: | ---: |']
        lines += [f"| {name} | {' | '.join(shown(measures))} |" for name, measures in results.items()]
    else:
        lines += [f'Compared with {described(baseline)}.', '',
                  '| Benchmark | Instructions | Change | Peak memory | Change | Wall time | '
                  'Wall time of the baseline |', '| --- | ---: | ---: | ---: | ---: | ---: | ---: |']
        for name, measures in results.items():
            old = baseline['results'].get(name, {})
            instructions, memory, seconds = shown(measures)
            before = shown(old)[2] if old else '-'
            lines.append(f"| {name} | {instructions} | {change(old.get('instructions'), measures['instructions'])} | "
                         f"{memory} | {change(old.get('peak_memory_bytes'), measures['peak_memory_bytes'])} | "
                         f'{seconds} | {before} |')
        if found:
            lines += ['', 'These rose past their thresholds:', '', *(f'- {line}' for line in found)]
        else:
            lines += ['', 'Nothing rose past its threshold.']
    if all(measures['instructions'] is None for measures in results.values()):
        lines += ['', UNCOUNTED]
    return '\n'.join(lines) + '\n'


def git(package, *arguments):
    return subprocess.run(['git', *arguments], cwd=package, capture_output=True, text=True, check=True).stdout.strip()


def commit_name(package):
    """The short name of the commit `package` is at, with `-dirty` where its tracked files differ from it."""
    commit = git(package, 'rev-parse', '--short=8', 'HEAD')
    return commit + '-dirty' if git(package, 'status', '--porcelain', '--untracked-files=no') else commit


def machine():
    """The machine and toolchain the measures were taken on, since measures from two machines don't compare."""
    if sys.platform == 'darwin':
        processor = subprocess.run(['sysctl', '-n', 'machdep.cpu.brand_string'], capture_output=True, text=True)
        name = processor.stdout.strip()
    else:
        with open('/proc/cpuinfo', encoding='utf-8') as f:
            name = next((line.split(':', 1)[1].strip() for line in f if line.startswith('model name')), 'unknown')
    swift = subprocess.run(['swift', '--version'], capture_output=True, text=True).stdout.splitlines()
    return {'processor': name, 'cores': os.cpu_count(), 'system': platform.platform(),
            'swift': swift[0] if swift else 'unknown'}


def built_rayoc(package):
    """The release `rayoc` built from `package`, which this builds as users build it."""
    subprocess.run(['swift', 'build', '-c', 'release', '--product', 'rayoc'], cwd=package, check=True)
    directory = subprocess.run(['swift', 'build', '-c', 'release', '--show-bin-path'], cwd=package, check=True,
                               capture_output=True, text=True).stdout.strip()
    return os.path.join(directory, 'rayoc')


def arguments_parser():
    parser = argparse.ArgumentParser(prog='benchmark.py')
    parser.add_argument('--package', default=os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                        help="the checkout of the compiler's package to build and measure; this one unless named")
    parser.add_argument('--filter', help='measure only the benchmarks whose names hold this text, such as check/')
    parser.add_argument('--sizes', default=DEFAULT_SIZES,
                        help='the copies of a loop each program is made with, separated by commas')
    parser.add_argument('--runs', type=int, default=DEFAULT_RUNS, help='the runs to take the median of')
    parser.add_argument('--save', action='store_true', help="save the results as the baseline of the package's commit")
    parser.add_argument('--code', help='what the code at the commit is, which a saved baseline and a summary record')
    parser.add_argument('--compare', metavar='COMMIT', help='compare with the baseline of this commit')
    parser.add_argument('--threshold', type=float, default=DEFAULT_INSTRUCTIONS_THRESHOLD,
                        help='the percentage rise in instructions a comparison fails past')
    parser.add_argument('--memory-threshold', type=float, default=DEFAULT_MEMORY_THRESHOLD,
                        help='the percentage rise in peak memory a comparison fails past')
    parser.add_argument('--summary', metavar='FILE', help='add a Markdown report of the results to this file')
    return parser


def main(arguments):
    options = arguments_parser().parse_args(arguments)
    if options.save and not options.code:
        print('benchmark.py: --save needs --code, to say what the code at the commit is', file=sys.stderr)
        return 2
    baseline = None
    if options.compare:
        # Read before measuring, so a missing baseline fails at once rather than after every run.
        with open(os.path.join(BASELINES, options.compare + '.json'), encoding='utf-8') as f:
            baseline = json.load(f)

    name = commit_name(options.package)
    rayoc = built_rayoc(options.package)
    sources = programs([int(size) for size in options.sizes.split(',')])
    results = measure_all(rayoc, sources, options.filter, options.runs)
    for program, _ in sources:
        costs = stage_costs(results, program)
        if costs:
            print(f'{program}: ' + ', '.join(f'{stage} {cost / 1e6:,.0f} M' for stage, cost in costs.items()))

    if options.save:
        saved = {
            'commit': name, 'code': options.code, 'machine': machine(),
            'build': "rayoc built with 'swift build -c release'",
            'measured': f'median of {options.runs} runs of each benchmark, with no warm-up run; instructions retired '
                        'and peak memory as the system reports them for the process, and wall-clock time',
            'programs': PROGRAM_DESCRIPTIONS,
            'date': datetime.datetime.now(datetime.timezone.utc).isoformat(timespec='seconds'),
            'results': results,
        }
        os.makedirs(BASELINES, exist_ok=True)
        with open(os.path.join(BASELINES, name + '.json'), 'w', encoding='utf-8') as f:
            json.dump(saved, f, indent=2, sort_keys=True)
        print(f'Saved the baseline {name}')

    found = []
    if baseline:
        found = regressions(baseline['results'], results, options.threshold, options.memory_threshold)
        print(f'Compared with {described(baseline)}:', *(found or ['nothing rose past its threshold']), sep='\n')
    if all(measures['instructions'] is None for measures in results.values()):
        # GitHub Actions shows a line that starts so as a warning on the run.
        print(('::warning::' if os.environ.get('GITHUB_ACTIONS') == 'true' else 'warning: ') + UNCOUNTED)
    if options.summary:
        measured = f'rayoc at {name}' + (f' ({options.code})' if options.code else '')
        with open(options.summary, 'a', encoding='utf-8') as f:
            f.write(summary(results, measured, baseline, found))
    return 1 if found else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
