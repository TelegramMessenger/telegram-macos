import argparse
from pathlib import Path
import re
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--evidence', type=Path)
parser.add_argument('--skip-package-tests', action='store_true')
args = parser.parse_args()
output = []
failed = 0


def run(command, cwd=None):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    output.append('$ ' + ' '.join(map(str, command)) + '\n' + result.stdout + result.stderr)
    return result


if not args.skip_package_tests:
    result = run(['swift', 'test', '--package-path', str(root / 'packages/HLSPlayback'), '-Xswiftc', '-warnings-as-errors'])
    summaries = re.findall(r'Executed (\d+) tests?, with (\d+) failures?', result.stdout + result.stderr)
    total, failures = (int(summaries[-1][0]), int(summaries[-1][1])) if summaries else (0, 0)
    ok = result.returncode == 0 and total > 0 and failures == 0
    failed += not ok
    print(f'{"PASS" if ok else "FAIL"} HLSPlayback package tests: {total} executed, {failures} failed, exit={result.returncode}', flush=True)
    if not ok:
        print(output[-1])

cases = ['normal', 'merged', 'separate', 'past-end', 'straddles-end', 'before-start', 'nan-part', 'empty', 'zero-duration', 'infinite-duration', 'nan-duration', 'negative-duration', 'overflow-duration', 'unknown-duration', 'submillisecond']
with tempfile.TemporaryDirectory(prefix='hls-playback-') as temp:
    directory = Path(temp)
    cache = directory / 'module-cache'
    range_set = sorted((root / 'submodules/telegram-ios/submodules/Utils/RangeSet/Sources').glob('*.swift'))
    playback = sorted((root / 'packages/HLSPlayback/Sources/HLSPlayback').glob('*.swift'))
    commands = [
        ['swiftc', '-module-cache-path', str(cache), '-emit-library', '-emit-module', '-module-name', 'RangeSet', *map(str, range_set), '-o', str(directory / 'libRangeSet.dylib'), '-emit-module-path', str(directory / 'RangeSet.swiftmodule')],
        ['swiftc', '-module-cache-path', str(cache), '-emit-library', '-emit-module', '-module-name', 'HLSPlayback', *map(str, playback), '-o', str(directory / 'libHLSPlayback.dylib'), '-emit-module-path', str(directory / 'HLSPlayback.swiftmodule')],
        ['swiftc', '-module-cache-path', str(cache), '-I', str(directory), '-L', str(directory), '-lRangeSet', '-lHLSPlayback', '-Xlinker', '-rpath', '-Xlinker', str(directory), str(directory / 'main.swift'), str(root / 'packages/TelegramMedia/Sources/HLSNative/HLSBufferingStatus.swift'), '-o', str(directory / 'tests')],
    ]
    (directory / 'main.swift').write_text(Path(__file__).with_name('BufferingStatusTests.swift').read_text())
    for command in commands:
        result = run(command)
        if result.returncode:
            print('\n'.join(output))
            raise SystemExit(result.returncode)
    for case in cases:
        result = run([str(directory / 'tests'), case])
        failed += result.returncode != 0
        print(f'{"PASS" if result.returncode == 0 else "FAIL"} buffering-status {case} exit={result.returncode}\n{result.stdout}{result.stderr}', end='', flush=True)

output.append(f'{failed} failed')
print(output[-1])
if args.evidence:
    args.evidence.mkdir(parents=True, exist_ok=True)
    (args.evidence / 'results.log').write_text('\n'.join(output) + '\n')
raise SystemExit(bool(failed))
