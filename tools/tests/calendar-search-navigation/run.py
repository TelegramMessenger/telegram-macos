import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import time

assert sys.flags.isolated
parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--lock', required=True, type=Path)
parser.add_argument('--baseline', default='861aefaaada199e0ddf93547437cd64c81181eb5')
args = parser.parse_args()
work = Path(__file__).resolve().parents[3]
out = args.output.resolve()
assert not out.is_relative_to(work)
out.mkdir(parents=True, exist_ok=False)
source = work / 'packages/CalendarUI/Sources/CalendarUI'
compiler = subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip()
sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
records = []


def run(name, command):
    with args.lock.open('a') as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        assert shutil.disk_usage(out).free >= 8 * 1024 ** 3
        with (out / (name + '.log')).open('x') as log:
            p = subprocess.Popen(command, cwd=work, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            started = time.monotonic()
            abort = None
            while True:
                if shutil.disk_usage(out).free < 4 * 1024 ** 3 or time.monotonic() - started > 540:
                    abort = 'disk_or_timeout'
                    os.killpg(p.pid, signal.SIGTERM)
                try:
                    code = p.wait(timeout=1)
                    break
                except subprocess.TimeoutExpired:
                    pass
        records.append({'name': name, 'command': command, 'exit': code, 'abort': abort})
        if code:
            print((out / (name + '.log')).read_text()[-10000:])
            raise SystemExit(code)


subprocess.run([sys.executable, '-I', str(Path(__file__).with_name('generate-regression-checks.py')), '--output', str(out / 'extracted'), '--baseline', args.baseline], check=True)
flags = [compiler, '-j1', '-swift-version', '5', '-sdk', sdk, '-target', 'arm64-apple-macos12.0', '-module-cache-path', str(out / 'cache')]
actual = [str(source / 'CalendarSearchSelection.swift'), str(source / 'CalendarSearchDayAccessibilityElement.swift')]
for name, fixture in [('native', Path(__file__).with_name('CalendarSearchNativeTests.swift')), ('regression', out / 'extracted/CalendarSearchRegressionTests.swift')]:
    run(name + '-compile', flags + actual + [str(fixture), '-o', str(out / (name + '-tests'))])
    run(name, [str(out / (name + '-tests'))])
result = {'records': records, 'baseline': args.baseline, 'production_sha256': {p: hashlib.sha256(Path(p).read_bytes()).hexdigest() for p in actual}, 'boundary': 'Real Foundation calendar model and AppKit AX object tests; source-projected controller/keyboard/geometry controls. No NSApplication/window/GUI/VoiceOver execution. Full CalendarUI real-module check is separate.'}
(out / 'verification.json').write_text(json.dumps(result, indent=2) + '\n')
print('Calendar native and baseline-projection regressions passed')
