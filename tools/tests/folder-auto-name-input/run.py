import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

BASE = '246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5'
SOURCE = 'packages/SidebarUI/Sources/SidebarUI/ChatListFilterController.swift'


def block(text, marker):
    start = text.index(marker)
    opening = text.index('{', start)
    depth = 0
    for end in range(opening, len(text)):
        depth += (text[end] == '{') - (text[end] == '}')
        if depth == 0:
            return text[start:end + 1]
    raise ValueError(marker)


def main():
    assert sys.flags.isolated
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--compiler-lock', type=Path)
    args = parser.parse_args()
    source = args.source_root.resolve()
    repo = Path(__file__).resolve().parents[3]
    output = args.output.resolve()
    assert all(output != p and p not in output.parents for p in (source, repo))
    output.mkdir(parents=True, exist_ok=True)
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    env['CLANG_MODULE_CACHE_PATH'] = str(output / 'modules')
    template = Path(__file__).with_name('Regression.swift.in').read_text()
    report = {'base': BASE, 'variants': {}}
    for variant in ('fixed', 'baseline'):
        folder = output / variant
        folder.mkdir(exist_ok=True)
        production = (source / SOURCE).read_text() if variant == 'fixed' else subprocess.check_output(['git', '-C', str(repo), 'show', BASE + ':' + SOURCE], text=True, env=env)
        code = template.replace('@@AFTER_TRANSACTION@@', block(production, '    controller.afterTransaction ='))
        main_file = folder / 'main.swift'
        main_file.write_text(code)
        binary = folder / 'regression'
        command = [shutil.which('swiftc'), '-j1', '-module-cache-path', str(output / 'modules'), str(main_file), '-o', str(binary)]
        lock_path = args.compiler_lock or output / 'compiler.lock'
        with lock_path.open('a') as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            result = subprocess.run(command, cwd=folder, env=env, text=True, capture_output=True)
        (folder / 'compile.log').write_text(result.stdout + result.stderr)
        assert result.returncode == 0, str(folder / 'compile.log')
        result = subprocess.run([str(binary)], cwd=folder, env=env, text=True, capture_output=True)
        (folder / 'run.log').write_text(result.stdout + result.stderr)
        passed = sum(x.startswith('PASS ') for x in result.stdout.splitlines())
        failed = sum(x.startswith('FAIL ') for x in result.stdout.splitlines())
        report['variants'][variant] = {'compiled': True, 'passed': passed, 'failed': failed, 'exit': result.returncode, 'source_sha256': hashlib.sha256(production.encode()).hexdigest(), 'generated_sha256': hashlib.sha256(code.encode()).hexdigest(), 'command': command}
        print(variant, passed, 'passed', failed, 'failed', flush=True)
        assert (result.returncode == 0 and passed and failed == 0) if variant == 'fixed' else (result.returncode == 1 and failed > 0)
    (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


if __name__ == '__main__':
    main()
