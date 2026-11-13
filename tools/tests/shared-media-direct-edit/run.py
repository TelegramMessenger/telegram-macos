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
CONTROL = Path('packages/TGUIKit/Sources/Control.swift')


def block(source, marker):
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]


def extract(source, base, stories, modes, control, fixture):
    source = source[source.index('public class PeerMediaController<'):]
    methods = []
    for marker in (
        'private var supportsMessageSelection:',
        'private var supportsEditing:',
        'private func updateMembersEditingAvailability(',

        'public override func menuItems()',
        'private var directEditItem:',
    ):
        if marker in source:
            methods.append(block(source, marker))
    for marker in (
        'public override var state:',
        'public override func requestUpdateRightBar()',
        'public override func updateEditStateTitles()',
        'public override func loadView()',
        'public override func viewDidResized(',
        'public override func updateLocalizationAndTheme(',

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
    press = block(control, 'open override func accessibilityPerformPress()').replace('open override ', '')
    story_transition = block(stories, 'actionsDisposable.add(transition.start(next:') + '))'
    return fixture.replace('__SOURCE__', text).replace('__BASE__', base_methods).replace('__MODES__', mode_enum).replace('__STORY_MENU__', block(stories, 'public override func menuItems()').replace('public ', '')).replace('__ACCESSIBILITY_PRESS__', press).replace('__STORY_TRANSITION__', story_transition)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, default=ROOT)
    baseline_group = parser.add_mutually_exclusive_group()
    baseline_group.add_argument('--baseline-source', type=Path)
    baseline_group.add_argument('--baseline-ref')
    parser.add_argument('--baseline-story-source', type=Path)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.output is not None and (args.output.exists() or args.output.is_symlink()):
        parser.error('--output must not exist or be a symlink')
    with tempfile.TemporaryDirectory(prefix='shared-media-direct-results-') as directory:
        args.output = args.output or Path(directory) / 'results'
        run(args)


def run(args):
    env = {key: value for key, value in os.environ.items() if not key.startswith('GIT_')}
    source_root = args.source_root.resolve()
    fixed = (source_root / SOURCE).read_text()
    baseline = None
    if args.baseline_source:
        baseline = args.baseline_source.read_text()
    elif args.baseline_ref:
        baseline = subprocess.check_output(['git', '-C', str(source_root), 'show', f'{args.baseline_ref}:{SOURCE.as_posix()}'], env=env, text=True)
    if baseline is not None and 'private var supportsEditing:' not in baseline:
        raise SystemExit('Baseline must contain the availability prerequisite')
    base = (source_root / BASE).read_text()
    stories = (source_root / STORIES).read_text()
    baseline_stories = None
    if baseline is not None:
        baseline_stories = args.baseline_story_source.read_text() if args.baseline_story_source else subprocess.check_output(['git', '-C', str(source_root), 'show', f'{args.baseline_ref or "HEAD"}:{STORIES.as_posix()}'], env=env, text=True)
    modes = (source_root / MODES).read_text()
    control = (source_root / CONTROL).read_text()
    fixture = Path(__file__).with_name('SharedMediaDirectEditTests.swift.in').read_text()
    args.output.mkdir(parents=True)
    results = {}
    platform = Path(subprocess.check_output(['xcrun', '--show-sdk-platform-path'], env=env, text=True).strip())
    frameworks = platform / 'Developer/Library/Frameworks'
    libraries = platform / 'Developer/usr/lib'
    with tempfile.TemporaryDirectory(prefix='shared-media-direct-edit-') as directory:
        directory = Path(directory)
        sources = [('fixed', fixed)]
        if baseline is not None:
            sources.append(('baseline', baseline))
        for name, source in sources:
            swift = directory / f'{name}.swift'
            story_source = stories if name == 'fixed' else baseline_stories
            swift.write_text(extract(source, base, story_source, modes, control, fixture))
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
            results[name] = {'source_sha256': hashlib.sha256(source.encode()).hexdigest(), 'story_sha256': hashlib.sha256(story_source.encode()).hexdigest(), 'tests': tests, 'failures': failures, 'exit_code': run.returncode}
            print(f'{name}: {tests} tests, {failures} failures, exit {run.returncode}', flush=True)
    (args.output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    if results['fixed']['exit_code'] != 0 or results['fixed']['failures'] != 0:
        raise SystemExit('Fixed source failed')
    if 'baseline' in results and (results['baseline']['exit_code'] == 0 or results['baseline']['failures'] == 0):
        raise SystemExit('Baseline did not reproduce assertion failures')


if __name__ == '__main__':
    main()
