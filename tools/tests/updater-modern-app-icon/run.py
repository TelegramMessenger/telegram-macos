import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys

BASE = 'fce013fd1af560d9074f75270f8695aabaa143f1'
SOURCE = 'Sparkle/SUApplicationInfo.m'


def method(text):
    start = text.index('+ (NSImage *)bestIconForHost:')
    opening = text.index('{', start)
    depth = 0
    for end in range(opening, len(text)):
        depth += (text[end] == '{') - (text[end] == '}')
        if depth == 0:
            return text[start:end + 1]
    raise ValueError('method')


def main():
    assert sys.flags.isolated
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compiler-lock', type=Path)
    args = parser.parse_args()
    root = args.source_root.resolve()
    sparkle = root / 'submodules/Sparkle'
    repo = Path(__file__).resolve().parents[3]
    output = args.output.resolve()
    assert all(output != p and p not in output.parents for p in (root, repo))
    output.mkdir(parents=True, exist_ok=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    template = Path(__file__).with_name('Regression.m.in').read_text()
    report = {'sparkle_base': BASE, 'variants': {}}
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
    lock_path = args.compiler_lock or output / 'compiler.lock'
    for variant in ('fixed', 'baseline'):
        folder = output / variant
        folder.mkdir(exist_ok=True)
        text = (sparkle / SOURCE).read_text() if variant == 'fixed' else subprocess.check_output(['git', '-C', str(repo / 'submodules/Sparkle'), 'show', BASE + ':' + SOURCE], text=True, env=env)
        generated = template.replace('@@METHOD@@', method(text))
        path = folder / 'main.m'
        path.write_text(generated)
        binary = folder / 'regression'
        command = ['xcrun', 'clang', '-fobjc-arc', '-isysroot', sdk, '-mmacosx-version-min=10.13', '-framework', 'AppKit', '-framework', 'CoreServices', str(path), '-o', str(binary)]
        with lock_path.open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            result = subprocess.run(command, cwd=folder, env=env, text=True, capture_output=True)
        (folder / 'compile.log').write_text(result.stdout + result.stderr)
        assert result.returncode == 0, str(folder / 'compile.log')
        result = subprocess.run([str(binary), str(folder)], cwd=folder, env=env, text=True, capture_output=True)
        (folder / 'run.log').write_text(result.stdout + result.stderr)
        passed = sum(x.startswith('PASS ') for x in result.stdout.splitlines())
        failed = sum(x.startswith('FAIL ') for x in result.stdout.splitlines())
        report['variants'][variant] = {'compiled': True, 'passed': passed, 'failed': failed, 'exit': result.returncode, 'source_sha256': hashlib.sha256(text.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(generated.encode()).hexdigest(), 'command': command}
        print(variant, passed, 'passed', failed, 'failed', flush=True)
        assert (result.returncode == 0 and passed and failed == 0) if variant == 'fixed' else (result.returncode == 1 and failed > 0)
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
