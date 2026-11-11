import argparse
import datetime
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def measurements(output):
    result = {}
    patterns = [
        (r'steady: own ([\d.]+)% helpers ([\d.]+)% total ([\d.]+)% windowserver ([\d.]+)% over ([\d.]+)s ops (\d+) fps ([\d.]+) cpu/frame ([\d.]+) ms',
         ['own_cpu_percent', 'helpers_cpu_percent', 'cpu_percent', 'windowserver_cpu_percent', 'measured_seconds', 'ops', 'host_callbacks_per_second', 'cpu_ms_per_callback']),
        (r'gpu: own ([\d.]+)% helpers ([\d.]+)% windowserver ([\d.]+)%',
         ['own_gpu_percent', 'helpers_gpu_percent', 'windowserver_gpu_percent']),
        (r'layouts=(\d+) total=([\d.]+) ms mean=([\d.]+) ms',
         ['layout_count', 'layout_total_ms', 'layout_mean_ms']),
        (r'draws=(\d+) mean=([\d.]+) ms \| max layout ([\d.]+) draw ([\d.]+)',
         ['draw_count', 'draw_mean_ms', 'layout_max_ms', 'draw_max_ms']),
        (r'end own ([\d.]+) helpers ([\d.]+) \((\d+) procs\)',
         ['own_footprint_mb', 'helpers_footprint_mb', 'helper_count']),
        (r'height=([\d.]+) rendered=(true|false) dead=(\S+) error=(.*?) first=(\S+) ready=(\S+) loaded=(\S+) renderedAt=(\S+)',
         ['height', 'rendered', 'dead', 'error', 'first_content_ms', 'ready_ms', 'loaded_ms', 'rendered_ms']),
        (r'surface: ([\d.]+) fps, gpu ([\d.]+) ms/frame, encode cpu ([\d.]+) ms/frame',
         ['surface_fps', 'surface_gpu_ms_per_frame', 'surface_encode_ms_per_frame']),
        (r'steady-layout: count (\d+) pipeline-total ([\d.]+) ms pure-total ([\d.]+) ms draws (\d+) draw-total ([\d.]+) ms',
         ['steady_layout_count', 'steady_pipeline_total_ms', 'steady_pure_layout_total_ms', 'steady_draw_count', 'steady_draw_total_ms']),
        (r'canvas: fast=(\d+) gpu-batches=(\d+) cg-batches=(\d+) gpu-buffers=(\d+) gpu-ms=([\d.]+)/buffer',
         ['canvas_fast', 'canvas_gpu_batches', 'canvas_cg_batches', 'canvas_gpu_buffers', 'canvas_gpu_ms_per_buffer']),
    ]
    for pattern, keys in patterns:
        found = re.search(pattern, output)
        if found:
            for key, value in zip(keys, found.groups()):
                try:
                    result[key] = float(value)
                except ValueError:
                    result[key] = None if value == '-' else value
    result['errors'] = re.findall(r'^log error: (.*)$', output, re.M)
    result['warnings'] = re.findall(r'^log warn(?:ing)?: (.*)$', output, re.M)
    result['diagnostics'] = re.findall(r'^diag .*$', output, re.M)
    result['pressure'] = re.findall(r'^renderer pressure: .*$', output, re.M)
    if 'own_footprint_mb' in result:
        result['footprint_mb'] = result['own_footprint_mb'] + result['helpers_footprint_mb']
    if 'own_gpu_percent' in result:
        result['gpu_ms_per_second'] = 10 * (result['own_gpu_percent'] + result['helpers_gpu_percent'])
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--lab', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--seconds', type=float, default=4)
    parser.add_argument('--warmup', type=float, default=1)
    parser.add_argument('--rounds', type=int, default=1)
    parser.add_argument('--match', default='')
    parser.add_argument('--resume', action='store_true')
    parser.add_argument('--timeline-seconds', type=float, default=0)
    args = parser.parse_args()
    if args.seconds <= args.warmup or args.warmup < 0 or args.rounds < 1:
        parser.error('Require seconds > warmup >= 0 and rounds >= 1')
    root = Path(__file__).resolve().parents[3]
    resources = root / 'packages/HTMLBubbles/Tests/HTMLBubblesTests/Fixtures'
    groups = [(resources / 'ported', 'ported/')] + [
        (resources / 'widget-sandbox' / group, group + '/')
        for group in ['showcase', 'generated', 'common', 'compat']
    ]
    fixtures = [(prefix + str(path.relative_to(folder)), path)
                for folder, prefix in groups for path in sorted(folder.rglob('*.html'))]
    fixtures.sort(key=lambda entry: '/stress/' in entry[0])
    fixtures = [entry for entry in fixtures if re.search(args.match, entry[0])]
    args.out.mkdir(parents=True, exist_ok=True)
    method = dict(
        timestamp=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        lab=str(args.lab.resolve()), binary_sha256=digest(args.lab),
        seconds=args.seconds, warmup=args.warmup, rounds=args.rounds,
        width_css=480, maximum_height_css=6000, theme='dark', visible=True,
        timeline_seconds=args.timeline_seconds,
        comparison='Native and sandbox-backed WKWebView, identical QuickJS sandbox and HTML',
        coverage='All Widgets catalog: ported plus showcase, generated, common, compat',
        order='Serial; renderer order alternates between widgets and rounds',
        limitations=[
            'Autonomous startup and idle/animation smoke test; no user interactions',
            'Host callbacks are not presented frames; CPU/callback is not frame latency',
            'Native layout/draw timers include startup and measure renderer work, not scanout',
            'GPU work uses accumulated AGX counters; it is not per-frame GPU latency',
            'WindowServer is system-wide and cannot be attributed to one widget',
            'WebKit timeline is a separate later interval with Inspector attached; profiling adds overhead',
            'Widget scanout percentiles and full GPU frame latency are unavailable',
            'A single short run is screening evidence, not a statistically stable performance ranking',
        ],
        fixtures=[dict(name=name, path=str(path), sha256=digest(path)) for name, path in fixtures],
        versions={name: subprocess.check_output(command, text=True).strip() for name, command in {
            'macos': ['sw_vers', '-productVersion'],
            'repository': ['git', '-C', str(root), 'rev-parse', 'HEAD'],
            'twidget': ['git', '-C', str(root / 'third-party/twidget'), 'rev-parse', 'HEAD'],
            'sandbox': ['git', '-C', str(root / 'third-party/widget-sandbox'), 'rev-parse', 'HEAD'],
        }.items()},
    )
    method_path = args.out / 'method.json'
    if args.resume and method_path.exists():
        previous = json.loads(method_path.read_text())
        for key in ['binary_sha256', 'seconds', 'warmup', 'rounds', 'fixtures', 'timeline_seconds']:
            if previous[key] != method[key]:
                raise SystemExit('Cannot resume with changed ' + key)
    else:
        method_path.write_text(json.dumps(method, indent=2) + '\n')
    records_path = args.out / 'runs.jsonl'
    records = [json.loads(line) for line in records_path.read_text().splitlines()] if args.resume and records_path.exists() else []
    done = {(r['fixture'], r['renderer'], r['round']) for r in records}
    with records_path.open('a' if args.resume else 'w') as stream:
        for run in range(1, args.rounds + 1):
            for index, (name, fixture) in enumerate(fixtures):
                for renderer in (['lite', 'web'] if (index + run) % 2 else ['web', 'lite']):
                    if (name, renderer, run) in done:
                        continue
                    key = f'{index + 1:03d}-{renderer}-{run}'
                    target = args.out / key
                    command = [str(args.lab.resolve()), 'capture', str(fixture), '--renderer', renderer,
                               '--out', str(target), '--width', '480', '--max-height', '6000',
                               '--theme', 'dark', '--seconds', str(args.seconds), '--warmup', str(args.warmup),
                               '--cpu', '--memory', '--logs', '--debug', '--visible']
                    if renderer == 'web' and args.timeline_seconds > 0:
                        command += ['--timeline-out', str(args.out / (key + '.timeline.json')),
                                    '--timeline-seconds', str(args.timeline_seconds)]
                    started = time.monotonic()
                    try:
                        completed = subprocess.run(command, capture_output=True, text=True, timeout=args.seconds + args.timeline_seconds + 35)
                        output = completed.stdout + completed.stderr
                        returncode = completed.returncode
                    except subprocess.TimeoutExpired as error:
                        output = (error.stdout or b'').decode(errors='replace') + (error.stderr or b'').decode(errors='replace')
                        returncode = 'timeout'
                    (args.out / (key + '.log')).write_text(output)
                    record = dict(fixture=name, renderer=renderer, round=run, key=key,
                                  returncode=returncode, wall_seconds=time.monotonic() - started,
                                  timestamp=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                                  command=command, **measurements(output))
                    record['snapshot'] = any(target.glob('*.png'))
                    record['pass'] = (returncode == 0 and record.get('rendered') == 'true'
                                      and record.get('dead') is None and record.get('error') is None
                                      and not record['errors'] and record['snapshot']
                                      and 'measured_seconds' in record)
                    stream.write(json.dumps(record) + '\n')
                    stream.flush()
                    records.append(record)
                    print(f"{len(records)}/{len(fixtures) * 2 * args.rounds} {key} {'PASS' if record['pass'] else 'FAIL'} {name}", flush=True)
    print(f"Finished: {sum(r['pass'] for r in records)}/{len(records)} passed", flush=True)


if __name__ == '__main__':
    main()
