import argparse
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, default=ROOT)
parser.add_argument('--baseline')
parser.add_argument('--output', type=Path)
parser.add_argument('--compiler-lock', type=Path)
args = parser.parse_args()


def read(path):
    if args.baseline:
        return subprocess.check_output(['git', '-C', str(ROOT), 'show', args.baseline + ':' + path], text=True)
    return (args.source_root / path).read_text()


def block(source, marker):
    assert source.count(marker) == 1, marker
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end], source[opening + 1:end - 1]


base = 'packages/GalleryUI/Sources/GalleryUI/'
controller = read(base + 'SVideoController.swift')
view = read(base + 'SVideoView.swift')
fixture = Path(__file__).with_name('FrameStepTests.swift.in').read_text()
methods = [block(controller, marker)[0] for marker in [
    '    public func stepFrameBackward()',
    '    public func stepFrameForward()',
    '    public func rewindBackward()',
    '    public func rewindForward()',
    '    public func pause()',
    '    public func playOrPause()',
    '    public func play(_ startTime:',
    '    public func play()'
]]
rewind = block(controller, 'rewind: { [weak self] timestamp in')[0].removeprefix('rewind: ')
callbacks = {
    '__REWIND__': rewind,
    '__TIMELINE__': block(view, 'controls.progress.onUserChanged = {')[0].split(' = ', 1)[1],
    '__PIP_TIMELINE__': block(view, 'current.progress.onUserChanged = {')[0].split(' = ', 1)[1],
    '__FORWARD__': block(view, 'controls.rewindForward.set(handler:')[0].split('handler: ', 1)[1],
    '__BACKWARD__': block(view, 'controls.rewindBackward.set(handler:')[0].split('handler: ', 1)[1],
    '__SCRUB_PAUSE__': block(controller, '}, pause: { [weak self] in')[0].split('pause: ', 1)[1],
    '__SCRUB_PLAY__': block(controller, '}, play: { [weak self] in')[0].split('play: ', 1)[1],
    '__METHODS__': '\n\n'.join(methods)
}
for key, value in callbacks.items():
    assert fixture.count(key) == 1, key
    fixture = fixture.replace(key, value)
assert not re.search(r'__[A-Z_]+__', fixture)
with tempfile.TemporaryDirectory(prefix='video-frame-step-') as temporary:
    output = args.output.resolve() if args.output else Path(temporary)
    if args.output:
        output.mkdir(parents=True, exist_ok=False)
    source = output / 'main.swift'
    source.write_text(fixture)
    binary = output / 'tests'
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    lock = args.compiler_lock.open('a') if args.compiler_lock else contextlib.nullcontext()
    with lock as handle:
        if args.compiler_lock:
            fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        compile_command = ['xcrun', 'swiftc', '-module-cache-path', str(output / 'module-cache'), str(source), '-o', str(binary)]
        compiled = subprocess.run(compile_command, capture_output=True, text=True, env=env)
        (output / 'compile.log').write_text(compiled.stdout + compiled.stderr)
        if compiled.returncode:
            print(compiled.stdout + compiled.stderr)
            raise SystemExit(2)
        executed = subprocess.run([str(binary)], capture_output=True, text=True, env=env)
    (output / 'run.log').write_text(executed.stdout + executed.stderr)
    results = {
        'baseline': args.baseline,
        'source_root': str(args.source_root),
        'source_sha256': {base + 'SVideoController.swift': hashlib.sha256(controller.encode()).hexdigest(), base + 'SVideoView.swift': hashlib.sha256(view.encode()).hexdigest()},
        'compile_command': compile_command,
        'compile_exit': compiled.returncode,
        'run_exit': executed.returncode,
        'output': executed.stdout,
        'boundary': 'Extracted controller methods and real view callbacks with synchronous player/status/disposable fixtures. No Telegram GUI, decoder, network, Core timing or real SignalKit cancellation is exercised.'
    }
    (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(executed.stdout + executed.stderr, end='')
    raise SystemExit(executed.returncode)
