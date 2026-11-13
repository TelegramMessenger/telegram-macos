import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

FACTORY = 'packages/ChatUI/Sources/ChatUI/RichTextEditorWindowController.swift'
PHOTO = 'packages/ChatUI/Sources/ChatUI/ChatInteractiveContentView.swift'
BASE_VIEW = 'packages/ChatUI/Sources/ChatUI/ChatMediaContentView.swift'
CANVAS = 'packages/RichTextEditorUI/Sources/RichTextEditorUI/Canvas/DocumentCanvasView+MediaBlocks.swift'
BOX = 'packages/RichTextEditorUI/Sources/RichTextEditorUI/Canvas/MediaBlockBox.swift'
METRICS = 'packages/RichTextEditorUI/Sources/RichTextEditorUI/Canvas/CanvasMetrics.swift'
EXTENSIONS = 'packages/TGUIKit/Sources/Extensions.swift'
DEFAULT_BASE = '246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5'


def declaration(source, marker):
    start = source.index(marker)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        if source[end] == '{':
            depth += 1
        elif source[end] == '}':
            depth -= 1
        end += 1
    return source[start:end]


def extract(sources, fixture):
    photo = sources[PHOTO]
    class_marker = 'private final class RichTextEditorImageContentView:'
    subclass = declaration(sources[FACTORY], class_marker) if class_marker in sources[FACTORY] else ''
    replacements = {
        '__EDITOR_PHOTO_CLASS__': subclass.replace('private final class', 'final class'),
        '__FACTORY__': declaration(sources[FACTORY], 'public static func makeMediaContentView('),
        '__BASE_LAYOUT__': declaration(sources[BASE_VIEW], 'public override func layout()'),
        '__PHOTO_LAYOUT__': declaration(photo, 'public override func updateLayout(size:'),
        '__PHOTO_UPDATE_SIZE__': declaration(photo, 'public override func update(size:'),
        '__BLUR_BACKGROUND__': declaration(photo, 'public var blurBackground:'),
        '__ASPECT_FITTED__': declaration(sources[EXTENSIONS], 'func aspectFitted('),
        '__ASPECT_FILLED__': declaration(sources[EXTENSIONS], 'func aspectFilled('),
        '__HOSTED_MEDIA__': declaration(sources[CANVAS], 'final class HostedMediaBlock {'),
        '__SYNC_MEDIA__': declaration(sources[CANVAS], 'func syncMediaBlockViews()'),
        '__MEDIA_HEIGHT__': declaration(sources[BOX], 'var mediaAreaHeight:'),
    }
    replacements['__MAX_HEIGHT__'] = re.search(r'static let maxMediaHeight: CGFloat = ([0-9.]+)', sources[METRICS]).group(1)
    for key, value in replacements.items():
        assert fixture.count(key) == 1, key
        fixture = fixture.replace(key, value)
    assert not re.search(r'__[A-Z_]+__', fixture)
    return fixture


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[3])
    parser.add_argument('--baseline-ref', default=DEFAULT_BASE)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if args.output is not None and (args.output.exists() or args.output.is_symlink()):
        parser.error('--output must be new and not a symlink')
    env = {k: v for k, v in os.environ.items() if not k.startswith('GIT_')}
    root = args.source_root.resolve()
    files = (FACTORY, PHOTO, BASE_VIEW, CANVAS, BOX, METRICS, EXTENSIONS)
    fixed = {name: (root / name).read_text() for name in files}
    baseline = {name: subprocess.check_output(['git', '-C', str(root), 'show', args.baseline_ref + ':' + name], env=env, text=True) for name in files}
    fixture = Path(__file__).with_name('RichEditorPhotoAspectTests.swift.in').read_text()
    platform = Path(subprocess.check_output(['xcrun', '--show-sdk-platform-path'], env=env, text=True).strip())
    frameworks, libraries = platform / 'Developer/Library/Frameworks', platform / 'Developer/usr/lib'
    results = {}
    with tempfile.TemporaryDirectory(prefix='rich-photo-aspect-') as temporary:
        temp = Path(temporary)
        output = args.output or temp / 'results'
        output.mkdir(parents=True)
        (temp / 'tmp').mkdir()
        local_env = {**env, 'TMPDIR': str(temp / 'tmp') + '/'}
        for label, sources in [('fixed', fixed), ('baseline', baseline)]:
            source = temp / (label + '.swift')
            source.write_text(extract(sources, fixture))
            binary = temp / label
            command = ['xcrun', 'swiftc', '-j', '2', '-F', str(frameworks), '-I', str(libraries), '-L', str(libraries), '-Xlinker', '-rpath', '-Xlinker', str(frameworks), '-Xlinker', '-rpath', '-Xlinker', str(libraries), '-module-cache-path', str(temp / 'cache'), str(source), '-o', str(binary)]
            compiled = subprocess.run(command, cwd=temp, env=local_env, capture_output=True, text=True)
            (output / (label + '-compile.log')).write_text(compiled.stdout + compiled.stderr)
            if compiled.returncode:
                print(compiled.stdout + compiled.stderr)
                raise SystemExit(2)
            tested = subprocess.run([str(binary)], cwd=temp, env=local_env, capture_output=True, text=True)
            text = tested.stdout + tested.stderr
            (output / (label + '-test.log')).write_text(text)
            summaries = re.findall(r'Executed (\d+) tests?, with (\d+) failures?', text)
            assert summaries, text
            cases, failures = map(int, summaries[-1])
            failed_cases = re.findall(r"Test Case '-\[[^ ]+ (test[^\]]+)\]' failed", text)
            assertion_lines = [line for line in text.splitlines() if ' : XCTAssert' in line and 'failed:' in line]
            if label == 'baseline':
                assert set(failed_cases) == {'testLandscapeCapRecomputesTransform', 'testPortraitAndSquareCaps', 'testNativeCanvasSyncKeepsCaptionAndOverlayGeometry', 'testReflowAcrossWidthsAndHeights', 'testPreMediaAndZeroFramesDoNotPoisonLaterLayout', 'testMediaPayloadAndSpoilerRemainUnchanged', 'testDimensionMatrixMatchesFinalFrame'}
                assert len(assertion_lines) == 34 and all('Transform must match actual editor frame' in line or 'Fit natural image into capped frame' in line for line in assertion_lines)
            results[label] = {'cases': cases, 'assertion_failures': failures, 'failed_cases': failed_cases, 'exit_code': tested.returncode, 'compile_exit': 0, 'source_hashes': {name: hashlib.sha256(value.encode()).hexdigest() for name, value in sources.items()}, 'generated_sha256': hashlib.sha256(source.read_bytes()).hexdigest()}
            print(json.dumps({'variant': label, 'cases': cases, 'assertion_failures': failures, 'exit_code': tested.returncode}), flush=True)
        (output / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
        assert results['fixed']['cases'] == results['baseline']['cases'] == 12
        assert results['fixed']['exit_code'] == 0 and results['fixed']['assertion_failures'] == 0
        assert results['baseline']['exit_code'] == 1 and results['baseline']['assertion_failures'] == 34


if __name__ == '__main__':
    main()
