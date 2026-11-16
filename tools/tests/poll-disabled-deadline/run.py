import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

assert sys.flags.isolated
parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[3])
parser.add_argument('--output', type=Path)
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
root = args.source_root.resolve()
env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
relative = 'packages/PollResultsUI/Sources/PollResultsUI/NewPollController.swift'
repository = Path(__file__).resolve().parents[3]
source = subprocess.check_output(['git', '-C', str(repository), 'show', '246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5:' + relative], env=env, text=True) if args.baseline else (root / relative).read_text()
start = source.index('        var computedDeadlineTimeout: Int32? = nil')
end = source.index('\n        var pollAttachedMedia:', start)
timeout = source[start:end]
constructor = next(line for line in source.splitlines() if 'return TelegramMediaPoll(pollId:' in line)
def field(name, following):
    return constructor.split(name + ': ', 1)[1].split(', ' + following + ':', 1)[0]
deadline = field('deadlineDate', 'pollHash')
hidden = field('hideResultsUntilClose', 'attachedMedia')
limit_method = source[source.index('    public func withUpdatedLimitDuration('):source.index('    public func withUpdatedDeadlineTimeout(')]
assert 'return copy(limitDuration: limitDuration)' in limit_method
assert 'deadlineDate: deadlineDate ?? self.deadlineDate' in source
assert 'hideResults: hideResults ?? self.hideResults' in source
body = (Path(__file__).parent / 'Checks.swift.in').read_text()
body = body.replace('__TIMEOUT__', timeout).replace('__DEADLINE__', deadline).replace('__HIDDEN__', hidden).replace('__LIMIT_METHOD__', limit_method)

def run(output):
    output.mkdir(parents=True, exist_ok=True)
    cache = output / 'module-cache'
    cache.mkdir(exist_ok=True)
    temporary = output / 'tmp'
    temporary.mkdir(exist_ok=True)
    generated = output / 'Checks.swift'
    generated.write_text(body)
    executable = output / 'checks'
    local_env = {**env, 'TMPDIR': str(temporary), 'CLANG_MODULE_CACHE_PATH': str(cache), 'SWIFTPM_MODULECACHE_OVERRIDE': str(cache)}
    sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True, env=local_env).strip()
    command = ['xcrun', 'swiftc', '-j1', '-sdk', sdk, '-module-cache-path', str(cache), str(generated), '-o', str(executable)]
    compile_result = subprocess.run(command, text=True, capture_output=True, env=local_env)
    (output / 'compile.log').write_text(compile_result.stdout + compile_result.stderr)
    if compile_result.returncode:
        print(compile_result.stdout + compile_result.stderr)
        raise SystemExit(compile_result.returncode)
    result = subprocess.run([str(executable)], text=True, capture_output=True, env=local_env)
    (output / 'checks.log').write_text(result.stdout + result.stderr)
    print(result.stdout + result.stderr, end='')
    manifest = {'baseline': args.baseline, 'source_root': str(root), 'source_sha256': hashlib.sha256(source.encode()).hexdigest(), 'compile_exit': compile_result.returncode, 'execution_exit': result.returncode, 'command': command, 'boundary': 'Extracted production timeout block, exact outgoing deadline/hide expressions and duration mutator; fixture retains only relevant state and substitutes poll wire tuple. No server/app integration is claimed.'}
    (output / 'result.json').write_text(json.dumps(manifest, indent=2) + '\n')
    raise SystemExit(result.returncode)

if args.output:
    run(args.output.resolve())
else:
    with tempfile.TemporaryDirectory(prefix='poll-disabled-deadline-') as directory:
        run(Path(directory))
