import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
SOURCE = Path('packages/PeerInfoUI/Sources/PeerInfoUI/PeerMediaController.swift')
BASE = Path('packages/TelegramUtils/Sources/TelegramUtils/ControllerExtension.swift')
STORIES = Path('packages/StoriesUI/Sources/StoriesUI/StoryMediaController.swift')
MODES = Path('packages/TelegramLinks/Sources/TelegramLinks/PeerMediaCollectionMode.swift')
MEMBERS = Path('packages/PeerInfoUI/Sources/PeerInfoUI/PeerMediaGroupMembersController.swift')
PERMISSIONS = Path('packages/TelegramTheme/Sources/TelegramTheme/PeerInfoUtils.swift')


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]


def extract(source, base, stories, modes, members, permissions, fixture):
    methods = []
    for marker in (
        'private var supportsMessageSelection:',
        'private var supportsEditing:',
        'private func updateMembersEditingAvailability(',

        'private var directEditItem:',
        'public override func menuItems()',
        'public override func changeState()',
    ):
        if marker in source:
            methods.append(block(source, marker))
    for marker in (
        'public override var state:',
        'public override func requestUpdateRightBar()',
        'public override func updateEditStateTitles()',
        'public override func loadView()',
        'private func applyReadyController(',
        'func controller(for mode:',
        'private var currentTagListIndex:',
        'override public func update(with state:',
    ):
        methods.append(block(source, marker))
    methods.append('func selectionDidChange(_ value: ChatPresentationInterfaceState, _ oldValue: ChatPresentationInterfaceState, animated: Bool) {' + block(source, 'if (value.state == .selecting) != (oldValue.state == .selecting)') + '}')
    text = '\n'.join(methods)
    text = re.sub(r'\b(public|private)\s+', '', text)
    base_methods = '\n'.join(block(base, marker) for marker in (
        'open var state:',
        'open func changeState()',
        'open func update(with state:',
    ))
    base_methods = re.sub(r'\b(open|public|override)\s+', '', base_methods)
    mode_enum = modes[modes.index('public enum PeerMediaCollectionMode'):modes.index('    public var tagsValue:')] + '}\n'
    if 'private func updateMembersEditingAvailability(' in source:
        dispatch = 'updateMembersEditingAvailability(value)'
    else:
        dispatch = ''
    rules = block(permissions, 'extension TelegramGroup {\n    public func canRemoveParticipant') + '\n' + block(permissions, 'extension TelegramChannel {\n    public func canRemoveParticipant')
    group_start = members.index('                    let deletable = group.canRemoveParticipant')
    channel_start = members.index('                let deletable = channel.canRemoveParticipant')
    group_decision = members[group_start:members.index('                    let editing:', group_start)]
    channel_decision = members[channel_start:members.index('                let editing:', channel_start)]
    return fixture.replace('__SOURCE__', text).replace('__BASE__', base_methods).replace('__MODES__', mode_enum).replace('__STORY_MENU__', block(stories, 'public override func menuItems()').replace('public ', '')).replace('__MEMBER_UPDATE__', dispatch).replace('__PERMISSIONS__', rules.replace('public ', '')).replace('__GROUP_ELIGIBILITY__', group_decision).replace('__CHANNEL_ELIGIBILITY__', channel_decision)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, default=ROOT)
    baseline_group = parser.add_mutually_exclusive_group()
    baseline_group.add_argument('--baseline-ref', default='c64a3ea77750fa753da0913cf26610df9b237640')
    baseline_group.add_argument('--baseline-source', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.output is not None and (args.output.exists() or args.output.is_symlink()):
        parser.error('--output must not exist or be a symlink')
    with tempfile.TemporaryDirectory(prefix='shared-media-edit-results-') as directory:
        args.output = args.output or Path(directory) / 'results'
        run(args)


def run(args):
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    source_root = args.source_root.resolve()
    fixed = (source_root / SOURCE).read_text()
    baseline = args.baseline_source.read_text() if args.baseline_source else subprocess.check_output(['git', '-C', str(source_root), 'show', f'{args.baseline_ref}:{SOURCE.as_posix()}'], env=env, text=True)
    members = (source_root / MEMBERS).read_text()
    permissions = (source_root / PERMISSIONS).read_text()
    base = (source_root / BASE).read_text()
    stories = (source_root / STORIES).read_text()
    modes = (source_root / MODES).read_text()
    fixture = Path(__file__).with_name('SharedMediaEditAvailabilityTests.swift.in').read_text()
    args.output.mkdir(parents=True)
    results = {}
    platform = Path(subprocess.check_output(['xcrun', '--show-sdk-platform-path'], env=env, text=True).strip())
    frameworks = platform / 'Developer/Library/Frameworks'
    libraries = platform / 'Developer/usr/lib'
    with tempfile.TemporaryDirectory(prefix='shared-media-edit-availability-') as directory:
        directory = Path(directory)
        for name, source in (('fixed', fixed), ('baseline', baseline)):
            swift = directory / f'{name}.swift'
            swift.write_text(extract(source, base, stories, modes, members, permissions, fixture))
            executable = directory / name
            command = ['xcrun', 'swiftc', '-j', '2', '-I', str(libraries), '-L', str(libraries), '-Xlinker', '-rpath', '-Xlinker', str(libraries), '-F', str(frameworks), '-Xlinker', '-rpath', '-Xlinker', str(frameworks), '-module-cache-path', str(directory / 'cache'), str(swift), '-o', str(executable)]
            compiled = subprocess.run(command, cwd=directory, env=env, capture_output=True, text=True)
            (args.output / f'{name}-compile.log').write_text(compiled.stdout + compiled.stderr)
            if compiled.returncode:
                raise RuntimeError(f'{name} failed to compile; not a valid regression result')
            run = subprocess.run([str(executable)], cwd=directory, env=env, capture_output=True, text=True)
            output = run.stdout + run.stderr
            (args.output / f'{name}-tests.log').write_text(output)
            summary = re.findall(r'Executed (\d+) tests?, with (\d+) failures?', output)
            if not summary:
                raise RuntimeError(f'{name} did not complete XCTest')
            tests, failures = map(int, summary[-1])
            results[name] = {'source_sha256': hashlib.sha256(source.encode()).hexdigest(), 'tests': tests, 'failures': failures, 'exit_code': run.returncode}
            print(f'{name}: {tests} tests, {failures} failures, exit {run.returncode}', flush=True)
    (args.output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    if results['fixed']['exit_code'] != 0 or results['fixed']['failures'] != 0:
        raise SystemExit('Fixed source failed')
    if results['baseline']['exit_code'] == 0 or results['baseline']['failures'] == 0:
        raise SystemExit('Baseline did not reproduce assertion failures')


if __name__ == '__main__':
    main()
