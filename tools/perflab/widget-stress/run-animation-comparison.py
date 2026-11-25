import argparse
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys

sys.dont_write_bytecode = True


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lab', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--rounds', type=int, default=3)
    args = parser.parse_args()
    folder = Path(__file__).resolve().parent
    runner = module('widget_runner', folder / 'run-all-widgets.py')
    reporter = module('widget_reporter', folder / 'report-all-widgets.py')
    args.out.mkdir(parents=True, exist_ok=True)
    root = folder.parents[2]
    resource = root / 'packages/HTMLBubbles/Tests/HTMLBubblesTests/Fixtures/widget-sandbox/showcase/stress'
    fixtures = ['order-book', 'canvas-market', 'clipped-ticker', 'canvas-atlas', 'reflow-cards', 'orbit-wall']
    method = dict(binary_sha256=runner.digest(args.lab), seconds=8, warmup=2, webkit_timeline_seconds=5,
                  rounds=args.rounds, native_samples='TW_SLOW_MS=0 layout pipeline passes with t >= 2 seconds',
                  webkit_samples='Inspector later interval; union of timed child events within rendering frames',
                  limitations='Native passes and WebKit recorded frames have different scope. Neither is GPU-inclusive presentation latency.',
                  fixtures={name: runner.digest(resource / ('perflab-' + name + '.html')) for name in fixtures})
    (args.out / 'method.json').write_text(json.dumps(method, indent=2) + '\n')
    records = []
    for name in fixtures:
        for run in range(1, args.rounds + 1):
            for renderer in (['lite', 'web'] if run % 2 else ['web', 'lite']):
                key = f'{name}-{renderer}-{run}'
                target = args.out / key
                command = [str(args.lab.resolve()), 'capture', str(resource / ('perflab-' + name + '.html')),
                           '--renderer', renderer, '--out', str(target), '--seconds', '8', '--warmup', '2',
                           '--width', '480', '--max-height', '6000', '--theme', 'dark', '--visible',
                           '--cpu', '--memory', '--logs', '--debug']
                environment = dict(os.environ)
                if renderer == 'lite':
                    environment['TW_SLOW_MS'] = '0'
                else:
                    command += ['--timeline-out', str(args.out / (key + '.timeline.json')), '--timeline-seconds', '5']
                completed = subprocess.run(command, capture_output=True, text=True, timeout=60, env=environment)
                output = completed.stdout + completed.stderr
                (args.out / (key + '.log')).write_text(output)
                record = dict(fixture=name, renderer=renderer, round=run, returncode=completed.returncode,
                              **runner.measurements(output))
                record['pass'] = (completed.returncode == 0 and record.get('rendered') == 'true'
                                  and record.get('dead') is None and not record.get('error') and not record['errors'])
                samples = []
                layouts = []
                for match in re.finditer(r'SLOW layout ([\d.]+) ms t=([\d.]+) (.*)', output):
                    if 2 <= float(match[2]) < 8:
                        samples.append(float(match[1]))
                        pure = re.search(r'(?:^|\s)layout ([\d.]+)(?:\s|$)', match[3])
                        if pure:
                            layouts.append(float(pure[1]))
                record['native_pipeline_samples_ms'] = samples
                record['native_layout_samples_ms'] = layouts
                record['native_pipeline'] = reporter.summary(samples)
                record['native_layout'] = reporter.summary(layouts)
                record['webkit_timeline'] = reporter.timeline(args.out / (key + '.timeline.json'))
                records.append(record)
                (args.out / 'runs.json').write_text(json.dumps(records, indent=2) + '\n')
                print(json.dumps({key: value for key, value in record.items() if key in [
                    'fixture', 'renderer', 'round', 'pass', 'native_pipeline', 'native_layout', 'webkit_timeline',
                    'host_callbacks_per_second', 'gpu_ms_per_second', 'errors', 'dead']}), flush=True)
    print('FINISHED', flush=True)


if __name__ == '__main__':
    main()
