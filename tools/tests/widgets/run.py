from pathlib import Path
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
import platform
import re
import shlex
import signal
import socket
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[3]
SANDBOX = ROOT / 'third-party/widget-sandbox'
RENDERER = ROOT / 'third-party/twidget'
HOST = ROOT / 'packages/HTMLBubbles'
SUITES = ('fast', 'core', 'native', 'host', 'conformance', 'stress', 'web')


def audit_conformance(run, manifest, expectations=None):
    expected = {
        (test['id'], theme, 390)
        for test in manifest['tests'] if test['set'] == 'auto'
        for theme in test.get('themes', ['light'])
    }
    rows = run.get('runs', [])
    actual = Counter((row.get('id'), row.get('theme'), row.get('width')) for row in rows)
    issues = []
    for key in sorted(expected - actual.keys()):
        issues.append(f'Missing run: {key}')
    for key, count in actual.items():
        if key not in expected or count != 1:
            issues.append(f'Unexpected or duplicate run: {key}, count {count}')
    tests = {test['id']: test for test in manifest['tests']}
    for row in rows:
        label = f"{row.get('id')} {row.get('theme')}"
        test = tests.get(row.get('id'), {})
        stop = test.get('stops')
        if stop:
            reason = row.get('dead')
            if not isinstance(reason, str) or not reason.startswith(stop):
                issues.append(f'{label}: expected stop {stop!r}, got {reason!r}')
        elif not row.get('loaded') or row.get('dead') or row.get('status') != 'done':
            issues.append(f"{label}: loaded={row.get('loaded')}, dead={row.get('dead')}, status={row.get('status')}")
        if row.get('errors'):
            issues.append(f"{label}: errors {row['errors']}")
        if row.get('skippedActions'):
            issues.append(f"{label}: undelivered actions {row['skippedActions']}")
        if stop:
            continue
        checks = row.get('checks', [])
        test = tests.get(row.get('id'), {})
        if not checks and ('self' in test.get('kind', ['self']) or test.get('checks')):
            issues.append(f'{label}: no self checks')
        allowed_skips = (expectations or {}).get(row.get('id'), {}).get('allowedSkips', [])
        for check in checks:
            allowed_skip = len(check) >= 4 and check[2] == 'skip' and [check[0], check[1], check[3]] in allowed_skips
            if len(check) < 3 or check[2] not in ('pass', 'xfail') and not allowed_skip:
                issues.append(f'{label}: {check}')
        if 'checks' in (expectations or {}).get(row.get('id'), {}):
            expected_checks = Counter(tuple(check) for check in expectations[row['id']]['checks'])
        else:
            expected_checks = Counter((check['id'], check['name']) for check in test.get('checks', []))
        actual_checks = Counter(tuple(check[:2]) for check in checks if len(check) >= 3)
        for check, count in (expected_checks - actual_checks).items():
            issues.append(f'{label}: missing check {check}, count {count}')
        for stage in tests.get(row.get('id'), {}).get('stages', []):
            if row.get('theme') not in stage.get('themes', ['light']):
                continue
            given = next((s for s in row.get('stages', []) if s.get('name') == stage['name']), None)
            if not given or given.get('status') == 'skip' or not (given.get('crop') or given.get('diff') is not None):
                issues.append(f"{label}: missing pixel stage {stage['name']}")
    return issues



def audit_stress(run, manifest):
    expected = {widget['id'] for widget in manifest['widgets']}
    rows = run.get('runs', [])
    actual = Counter(row.get('id') for row in rows)
    issues = [f'Missing stress widget: {name}' for name in sorted(expected - actual.keys())]
    for name, count in actual.items():
        if name not in expected or count != 1:
            issues.append(f'Unexpected or duplicate stress widget: {name}, count {count}')
    for row in rows:
        name = row.get('id')
        if not row.get('loaded') and not row.get('dead'):
            issues.append(f'{name}: neither loaded nor stopped')
        for key in ('frames', 'host', 'widget'):
            if not isinstance(row.get(key), dict):
                issues.append(f'{name}: missing {key} metrics')
        widget = row.get('widget')
        last = widget.get('last') if isinstance(widget, dict) else None
        if not row.get('dead') and (not isinstance(last, dict) or last.get('id') != name):
            issues.append(f'{name}: absent or stale data-stress publication')
    return issues

def audit_expectations(expectations, manifest, root):
    tests = {test['id']: test for test in manifest['tests']}
    issues = []
    for name, expected in expectations.items():
        test = tests.get(name)
        if not test or hashlib.sha256((root / test['file']).read_bytes()).hexdigest() != expected['htmlSha256']:
            issues.append(f'Sandbox expectations are stale for {name}; review the changed fixture assertions')
    return issues


def audit_xctest(log):
    counts = re.findall(r'Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures?', log)
    if not any(int(total) > int(skipped or 0) for total, skipped, failures in counts):
        return ['XCTest executed no non-skipped tests']
    return []


def audit_node_tests(log):
    counts = re.findall(r'(?:ℹ|#)\s+tests\s+(\d+)', log)
    if not counts or not any(int(count) > 0 for count in counts):
        return ['Node executed no tests; check whether optional renderer WASM assets are built']
    return []


def audit_playwright(report, files):
    issues = []
    seen = set()
    def visit(suite):
        for spec in suite.get('specs', []):
            seen.add(Path(spec.get('file', suite.get('file', ''))).name)
            if not spec.get('tests'):
                issues.append(f"{spec.get('title')}: no test cases executed")
            for test in spec.get('tests', []):
                results = test.get('results', [])
                if test.get('expectedStatus') != 'passed' or not results or any(result.get('status') != 'passed' for result in results):
                    issues.append(f"{spec.get('title')}: {test.get('expectedStatus')}, {[result.get('status') for result in results]}")
        for child in suite.get('suites', []):
            visit(child)
    for suite in report.get('suites', []):
        visit(suite)
    for file in set(files) - seen:
        issues.append(f'No tests executed from {file}')
    if report.get('errors'):
        issues.append(f"Playwright errors: {report['errors']}")
    return issues


def stop_process_group(process):
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
    process.wait()


class Runner:
    def __init__(self, output, cache, timeout):
        self.output = output
        self.cache = cache
        self.timeout = timeout
        self.steps = []
        self.scope = {}
        self.environment = dict(os.environ)
        module_cache = cache / 'modules'
        module_cache.mkdir(parents=True, exist_ok=True)
        self.environment.setdefault('CLANG_MODULE_CACHE_PATH', str(module_cache))
        self.environment.setdefault('SWIFTPM_MODULECACHE_OVERRIDE', str(module_cache))

    def step(self, name, command, cwd=ROOT, env=None, verify=None, timeout=None):
        log = self.output / f'{len(self.steps) + 1:02}-{name}.log'
        environment = self.environment | (env or {})
        start = time.monotonic()
        display = shlex.join(map(str, command))
        print(f'RUN {name}: {display[:240]}{"…" if len(display) > 240 else ""}', flush=True)
        record = {'name': name, 'command': list(map(str, command)), 'cwd': str(cwd), 'log': str(log)}
        try:
            with log.open('w') as handle:
                process = subprocess.Popen(command, cwd=cwd, env=environment, stdout=handle, stderr=subprocess.STDOUT, start_new_session=True)
                try:
                    code = process.wait(timeout=self.timeout if timeout is None else timeout)
                except (subprocess.TimeoutExpired, KeyboardInterrupt):
                    stop_process_group(process)
                    raise
            record.update(exitCode=code, status='pass' if code == 0 else 'fail')
            if code == 0 and command[:3] == ['xcrun', 'swift', 'test']:
                issues = audit_xctest(log.read_text(errors='replace'))
                if issues:
                    record.update(status='fail', issues=issues)
            if code == 0 and command[0] == 'node' and '--test' in command:
                issues = audit_node_tests(log.read_text(errors='replace'))
                if issues:
                    record.update(status='fail', issues=issues)
            if code == 0 and verify:
                issues = verify()
                if issues:
                    record.update(status='fail', issues=issues)
                    with log.open('a') as handle:
                        handle.write('\n' + '\n'.join(issues) + '\n')
        except (OSError, ValueError, subprocess.TimeoutExpired) as error:
            record.update(status='error', detail=str(error))
        except KeyboardInterrupt:
            record.update(status='interrupted', detail='Interrupted by user')
            raise
        finally:
            record['seconds'] = round(time.monotonic() - start, 3)
            self.steps.append(record)
            self.save()
            if record.get('status') == 'interrupted':
                self.finish(interrupted=True)
        print(f"{record['status'].upper()} {name} ({record['seconds']:.1f}s) — {log}", flush=True)
        if record['status'] != 'pass' and log.exists():
            print('\n'.join(log.read_text(errors='replace').splitlines()[-12:]), flush=True)
        return record['status'] == 'pass'

    def save(self):
        (self.output / 'steps.json').write_text(json.dumps(self.steps, indent=2) + '\n')

    def finish(self, interrupted=False):
        failed = sum(step['status'] != 'pass' for step in self.steps)
        summary = {'status': 'interrupted' if interrupted else 'fail' if failed else 'pass', 'seconds': round(sum(step['seconds'] for step in self.steps), 3), 'steps': len(self.steps), 'failed': failed, 'output': str(self.output), 'scope': self.scope}
        (self.output / 'summary.json').write_text(json.dumps(summary, indent=2) + '\n')
        return summary

    def swift(self, package, scratch, test_filter=None):
        command = ['xcrun', 'swift', 'test', '--package-path', str(package), '--scratch-path', str(scratch), '--disable-sandbox', '--enable-xctest', '--disable-swift-testing', '-j', '4']
        if package == RENDERER:
            command += ['-Xlinker', '-framework', '-Xlinker', 'QuartzCore']
        if package == HOST:
            command += ['-Xlinker', str(ROOT / 'core-xprojects/Mozjpeg/build/arm64/libjpeg.a')]
        if test_filter:
            command += ['--filter', test_filter]
        return command


def git_state(path):
    def read(*args):
        return subprocess.check_output(['git', '-C', str(path), *args], text=True).strip()
    return {'path': str(path), 'commit': read('rev-parse', 'HEAD'), 'status': read('status', '--short')}


def main():
    parser = argparse.ArgumentParser(description='Repeatable widget review: cached builds, timed logs, strict conformance verdicts.')
    parser.add_argument('--suite', action='append', choices=(*SUITES, 'all'), help='Repeat to select layers; default: fast')
    parser.add_argument('--output', type=Path)
    parser.add_argument('--cache', type=Path, default=ROOT / '.build/widget-review/cache')
    parser.add_argument('--renderer-scratch', type=Path)
    parser.add_argument('--sandbox-scratch', type=Path)
    parser.add_argument('--host-scratch', type=Path)
    parser.add_argument('--timeout', type=float, default=1800, help='Seconds per command')
    parser.add_argument('--stress-timeout', type=float, default=7200, help='Seconds allowed for the full two-pass stress kit')
    parser.add_argument('--stress-smoke', action='store_true', help='Use 100 ms warmup and 1100 ms measurement; not a benchmark')
    args = parser.parse_args()
    if args.timeout <= 0 or args.stress_timeout <= 0:
        parser.error('--timeout must be positive')
    suites = set(args.suite or ['fast'])
    if 'all' in suites:
        suites = set(SUITES)
    stamp = datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    output = (args.output or ROOT / '.build/widget-review/runs' / stamp).expanduser().resolve()
    output.mkdir(parents=True, exist_ok=False)
    cache = args.cache.expanduser().resolve()
    runner = Runner(output, cache, args.timeout)
    metadata = {
        'started': stamp, 'platform': platform.platform(), 'python': sys.version,
        'suites': sorted(suites), 'repositories': [git_state(p) for p in (ROOT, RENDERER, SANDBOX)],
        'notCovered': ['Live bot/server delivery', 'Manual macOS visual and accessibility checks', 'Other platforms'],
    }
    (output / 'environment.json').write_text(json.dumps(metadata, indent=2) + '\n')
    runner.scope = metadata
    renderer_scratch = (args.renderer_scratch or cache / 'twidget').resolve()
    sandbox_scratch = (args.sandbox_scratch or cache / 'sandbox').resolve()
    native_env = {'TW_STRESS': '0', 'TW_CONFORMANCE': '0', 'TW_CONFORMANCE_SET': '', 'TWIDGET_WIDGET_SANDBOX': str(SANDBOX)}
    if 'fast' in suites:
        runner.step('harness-tests', [sys.executable, '-m', 'unittest', 'test_harness.py'], cwd=Path(__file__).parent)
        runner.step('payload-resize', [sys.executable, str(ROOT / 'tools/tests/widget-v013/run.py'), '--cache', str(cache / 'payload'), '--debug-only'])
        runner.step('pack-review-widget', [sys.executable, str(Path(__file__).with_name('pack.py')), str(Path(__file__).parent / 'fixtures/review.html'), '--output', str(output / 'review.tgw')])
        runner.step('manual-fixtures', [sys.executable, str(ROOT / 'tools/tests/widget-v013/manual.py'), '--prepare-only', '--output', str(output / 'manual')])
    if 'core' in suites:
        tsc = SANDBOX / 'node_modules/typescript/bin/tsc'
        for name, path in [('core', 'packages/core'), ('web', 'apps/web'), ('tools', '.')]:
            runner.step(f'typecheck-{name}', ['node', str(tsc), '--noEmit', '-p', path], cwd=SANDBOX)
        for name, path in [('core', 'packages/core/tests/unit'), ('web', 'apps/web/tests/unit')]:
            files = sorted((SANDBOX / path).glob('*.test.ts'))
            if not files:
                raise RuntimeError(f'No unit tests at {path}')
            runner.step(f'unit-{name}', ['node', '--import', 'tsx', '--test', '--test-concurrency=1', *map(str, files)], cwd=SANDBOX)
        runner.step('conformance-payload-sizes', ['node', '--import', 'tsx', 'scripts/conformance/build.ts', '--sizes'], cwd=SANDBOX)
        runner.step('probe-runtime', ['node', '--import', 'tsx', str(Path(__file__).with_name('probe.mts'))], cwd=SANDBOX)
    if 'native' in suites:
        runner.step('sandbox-native', runner.swift(SANDBOX, sandbox_scratch), env=native_env)
        runner.step('renderer-native', runner.swift(RENDERER, renderer_scratch) + ['--skip', 'ArenaSlabTests'], env=native_env)
        runner.step('arena-native', runner.swift(RENDERER, renderer_scratch, 'ArenaSlabTests'), env=native_env)
    if 'host' in suites:
        host_scratch = (args.host_scratch or cache / 'host').resolve()
        host_filter = 'WidgetStorageTests|WidgetDataTests|WidgetThemeMappingTests|WidgetResizePresentationTests|ContentLinkTests|UserActionGateTests'
        runner.step('host-integration', runner.swift(HOST, host_scratch, host_filter), env=native_env | {'HTMLBUBBLES_UI_TESTS': '0'})
    if 'conformance' in suites:
        conformance = output / 'conformance'
        env = native_env | {'TW_CONFORMANCE': '1', 'TW_CONFORMANCE_OUT': str(conformance), 'TW_CONFORMANCE_FEATURES': 'binaryOps,canvasWords,webAnimations,morphUpdates'}
        env['TW_CONFORMANCE_ONLY'] = ','.join(test['id'] for test in json.loads((SANDBOX / 'packages/conformance/manifest.json').read_text())['tests'] if test['set'] == 'auto')
        raw = conformance / 'macos-twidget-litehtml.run.json'
        def verify():
            root = SANDBOX / 'packages/conformance'
            manifest = json.loads((root / 'manifest.json').read_text())
            expectations = json.loads(Path(__file__).with_name('sandbox-checks.json').read_text())
            return audit_expectations(expectations, manifest, root) + audit_conformance(json.loads(raw.read_text()), manifest, expectations)
        runner.step('conformance-run', runner.swift(RENDERER, renderer_scratch, 'ConformanceRunnerTests/testAutomaticSet'), env=env, verify=verify)
        if raw.exists():
            runner.step('conformance-judge', ['node', str(SANDBOX / 'packages/conformance/tools/report.mjs'), '--out', str(conformance / 'judged'), '--fail-on', 'in', str(raw)], cwd=SANDBOX)
    if 'stress' in suites:
        stress = output / 'stress'
        env = native_env | {'TW_STRESS': '1', 'TW_STRESS_OUT': str(stress)}
        if args.stress_smoke:
            env.update(TW_STRESS_WARMUP_MS='100', TW_STRESS_MEASURE_MS='1100', TW_STRESS_COOLDOWN_MS='0')
        def verify_stress():
            manifest = json.loads((SANDBOX / 'packages/stress/manifest.json').read_text())
            issues = []
            for name in ('measure', 'production'):
                path = stress / f'macos-{name}.run.json'
                if not path.exists():
                    issues.append(f'Missing stress pass: {name}')
                else:
                    run = json.loads(path.read_text())
                    if run.get('pass') != name:
                        issues.append(f'Wrong stress pass in {path.name}')
                    issues.extend(audit_stress(run, manifest))
            return issues
        runner.step('stress-run', runner.swift(RENDERER, renderer_scratch, 'StressRunnerTests/testStressKit'), env=env, verify=verify_stress, timeout=args.timeout if args.stress_smoke else args.stress_timeout)
        runs = sorted(stress.glob('*.run.json'))
        if runs:
            runner.step('stress-report', ['node', str(SANDBOX / 'packages/stress/tools/report.mjs'), '--out', str(stress / 'report'), *map(str, runs)], cwd=SANDBOX)
            summary = stress / 'report/summary.md'
            if args.stress_smoke and summary.exists():
                (stress / 'report/SMOKE.md').write_text('This is a Debug integration smoke run: 100 ms warmup and 1100 ms measurement per widget, with shortened cooldowns. It is not an optimized-device or full-duration benchmark. Unavailable metrics are null in the raw run files.\n\n' + summary.read_text())
    if 'web' in suites:
        files = ['attacks.spec.ts', 'activation.spec.ts', 'sdk.spec.ts', 'lifecycle.spec.ts', 'gestures.spec.ts']
        for renderer in ('iframe', 'shadow'):
            with socket.socket() as listener:
                listener.bind(('127.0.0.1', 0))
                port = listener.getsockname()[1]
            config = output / f'playwright-{renderer}.config.mts'
            config.write_text('import config from ' + json.dumps(str(SANDBOX / 'playwright.config.ts')) + ';\nexport default { ...config, testDir: ' + json.dumps(str(SANDBOX / 'tests')) + ', globalSetup: ' + json.dumps(str(SANDBOX / 'tests/global-setup.ts')) + ', webServer: config.webServer.map(server => ({ ...server, cwd: ' + json.dumps(str(SANDBOX)) + ', reuseExistingServer: false })) };\n')
            report = output / f'web-{renderer}.json'
            runner.step(f'web-{renderer}', ['node', '--import', 'tsx', 'node_modules/@playwright/test/cli.js', 'test', *['tests/' + file for file in files], '--config', str(config), '--reporter=json', '--output', str(output / f'web-{renderer}-artifacts')], cwd=SANDBOX, env={'TW_RENDERER': renderer, 'TW_PORT': str(port), 'VITE_TW_POLICY': 'strict', 'PLAYWRIGHT_JSON_OUTPUT_NAME': str(report)}, verify=lambda: audit_playwright(json.loads(report.read_text()), files))
    summary = runner.finish()
    print(f"{summary['status'].upper()}: {len(runner.steps) - summary['failed']}/{len(runner.steps)} steps, {summary['seconds']:.1f}s. Report: {output / 'summary.json'}")
    return 1 if summary['failed'] else 0


if __name__ == '__main__':
    sys.exit(main())
