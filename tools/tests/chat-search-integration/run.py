import argparse
import json
import plistlib
import shutil
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--revision')
parser.add_argument('--expect-regression', action='store_true')
parser.add_argument('--prepare-app', action='store_true')
parser.add_argument('--fade-preview', action='store_true')
parser.add_argument('--scratch-path', type=Path, required=True)
parser.add_argument("--dependency-root", type=Path, default=root)
args = parser.parse_args()
if args.fade_preview and not args.prepare_app:
    parser.error("--fade-preview requires --prepare-app")
dependency_root = args.dependency_root.resolve()


def source(name):
    path = 'packages/ChatUI/Sources/ChatUI/' + name + '.swift'
    return subprocess.check_output(['git', 'show', args.revision + ':' + path], cwd=root, text=True) if args.revision else (root / path).read_text()


def block(text, marker):
    start = text.index(marker)
    end = text.index('{', start) + 1
    depth = 1
    while depth:
        depth += (text[end] == '{') - (text[end] == '}')
        end += 1
    return text[start:end]


has_updated_helper = 'public func updateLayout(animated: Bool)' in source('InputContextHelper')
has_result_counter = 'private final class ChatSearchCountContainer:' in source('ChatSearchHeader')
flags = (['UPDATED_SEARCH_POPUP_LAYOUT'] if has_updated_helper else []) + (['UPSTREAM_SEARCH_RESULT_COUNTER'] if has_result_counter else [])
if 'case .pinned, .restartTopic,' in source('ChatHeaderController'):
    flags.append('INLINE_UTILITY_HEADERS')
settings = '[' + ', '.join('.define(' + json.dumps(flag) + ')' for flag in flags) + ']'
imports = 'import Cocoa\nimport TGUIKit\nimport ColorPalette\nimport SwiftSignalKit\n'
with tempfile.TemporaryDirectory(prefix='telegram-search-integration-') as directory:
    directory = Path(directory)
    sources = directory / 'Sources'
    sources.mkdir()
    packages = ['.package(path: ' + json.dumps(str(dependency_root / 'packages' / name)) + ')' for name in ['TGUIKit', 'ColorPalette']]
    packages.append('.package(path: ' + json.dumps(str(dependency_root / 'submodules/telegram-ios/submodules/SSignalKit')) + ')')
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "SearchIntegration", platforms: [.macOS(.v12)], dependencies: [DEPENDENCIES], targets: [.executableTarget(name: "SearchIntegration", dependencies: ["TGUIKit", "ColorPalette", .product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Sources", swiftSettings: SETTINGS)])
'''.replace('DEPENDENCIES', ', '.join(packages)).replace('SETTINGS', settings))
    header = source('ChatSearchHeader')
    header = imports + header[header.index('private final class CSearchContextState'):header.index('private final class ChatSearchTagsView')] + header[header.index('private final class ChatSearchCountContainer:' if has_result_counter else 'class ChatSearchHeader :'):]
    header += '''
extension ChatSearchHeader {
 var testSearchView: ChatSearchView { searchView }
 var testContext: InputContextHelper { inputContextHelper }
 var testTagsView: NSView? { tagsView }
__COUNTER_PROPERTIES__
 var testPeerId: PeerId? { inputInteraction.state.peerId }
 var testButtons: [ImageButton] { [prev, next, from, calendar, cancel] }
}
'''
    header = header.replace('__COUNTER_PROPERTIES__', ' var testCount: (current: Int, total: Int) { countState }\n var testCountIsHidden: Bool { countContainer.isHidden }' if has_result_counter else '')
    (sources / 'Header.swift').write_text(header)
    search = source('ChatSearchView')
    (sources / 'SearchView.swift').write_text(imports + '\n'.join(line for line in search.splitlines() if not line.startswith('import ')))
    helper = source('InputContextHelper')
    view = helper[helper.index('public class InputContextView :'):helper.index('public class InputContextViewController :')]
    (sources / 'ResultView.swift').write_text(imports + view)
    start = helper.index('        controller._frameRect =', helper.index('public func context(with'))
    end = helper.index('        var currentResult = result', start)
    attach_start = helper.index('            if show, let relativeView = relativeView, let view = view {')
    attach_end = helper.index('\n\n        }))', attach_start)
    parts = {
        '__CONTEXT_LAYOUT__': block(helper, 'public func layout(_ animated:Bool)'),
        '__ANCHOR_FRAME__': block(helper, 'func anchorFrame(for relativeView:') if 'func anchorFrame(for relativeView:' in helper else 'func anchorFrame(for relativeView: NSView, in view: NSView) -> NSRect { relativeView.convert(relativeView.bounds, to: view) }',
        '__LAYOUT_CONTAINER__': block(helper, 'fileprivate func layoutAccessoryContainer()'),
        '__HELPER_LAYOUT__': block(helper, 'public func updateLayout(animated: Bool)') if 'public func updateLayout(animated: Bool)' in helper else '',
        '__CONTEXT_PREPARE__': helper[start:end],
        '__CONTEXT_ATTACH__': helper[attach_start:attach_end],
    }
    results = (fixtures / 'Results.swift').read_text()
    for marker, value in parts.items():
        results = results.replace(marker, value)
    (sources / 'Results.swift').write_text(results)
    (sources / 'InlineLayout.swift').write_text(source('ChatHeaderInlineLayout'))
    lifecycle = source('ChatHeaderController')
    slot_start = lifecycle.index('        let layoutSlot:')
    root_layout_start = source('ChatController').index('\n', source('ChatController').index('            header.measure(headerFrame.width)'))
    lifecycle_parts = {
        '__SLOT_FIELDS__': lifecycle[lifecycle.index('    private var primaryInited'):lifecycle.index('    var state:ChatHeaderState')].replace('private ', ''),
        '__SLOT_LAYOUT__': lifecycle[slot_start:lifecycle.index('        layoutSeparators(', slot_start)],
        '__ROOT_LAYOUT__': source('ChatController')[root_layout_start:source('ChatController').index('\n        }', root_layout_start)],
        '__HEADER_REMOVAL__': block(lifecycle[lifecycle.rindex('                if let currentView = currentView {'):], 'if let currentView = currentView {'),
    }
    layout_tests = (fixtures / 'HeaderLayout.swift').read_text()
    for marker, value in lifecycle_parts.items():
        layout_tests = layout_tests.replace(marker, value)
    (sources / 'HeaderLayout.swift').write_text(layout_tests)
    geometry = '''import AppKit
struct HeaderFixture { var state: ChatHeaderState }
struct BubbleGeometry {
 func inlineHeaderFrame(for width: CGFloat) -> NSRect? {
  ChatHeaderInlineLayout.accessoryFrame(in: NSMakeRect(12, 12, width - 122, 40), preferredTitleWidth: 260, spacing: 10)
 }
}
struct ControllerGeometry {
 let header: HeaderFixture
 let bubblesView = BubbleGeometry()
 __INLINE_FRAME__
}
'''
    (sources / 'Geometry.swift').write_text(geometry.replace('__INLINE_FRAME__', block(source('ChatController'), 'private func inlineHeaderFrame(for width:').replace('private ', '')))
    images = {}
    for name in ['Icon_SearchField', 'Icon_SearchClear', 'Icon_Quote', 'Icon_Quote_Collapse', 'Icon_Quote_Expand', 'Icon_SearchArrow', 'Icon_Calendar', 'Icon_Pip_Close', 'Icon_ChatSearchFrom']:
        image_set = dependency_root / 'Telegram-Mac/Assets.xcassets' / (name + '.imageset')
        variants = json.loads((image_set / 'Contents.json').read_text())['images']
        filename = next(image['filename'] for image in variants if image.get('filename') and image.get('scale') == '1x')
        images[name] = str(image_set / filename)
    (sources / 'Assets.swift').write_text('let imagePaths: [String: String] = [' + ', '.join(json.dumps(name) + ': ' + json.dumps(path) for name, path in images.items()) + ']')
    for name in ['Models.swift', 'EmptySearchState.swift', 'StorySuggestions.swift', 'main.swift']:
        content = (fixtures / name).read_text()
        if args.fade_preview and name == 'main.swift':
            content = content.replace('  NSApp.run()', '  showFadePreview()\n  NSApp.run()')
        (sources / name).write_text(content)
    if args.fade_preview:
        shutil.copy2(fixtures / 'FadePreview.swift', sources / 'FadePreview.swift')
    command = ['swift', 'run', '--package-path', str(directory), '--scratch-path', str(args.scratch_path.resolve()), '--disable-sandbox', '--jobs', '2', 'SearchIntegration']
    if args.expect_regression:
        command.append('--expect-regression')
    if args.prepare_app:
        build = ['swift', 'build', '--package-path', str(directory), '--scratch-path', str(args.scratch_path.resolve()), '--disable-sandbox', '--jobs', '2', '--product', 'SearchIntegration']
        subprocess.run(build, check=True)
        binary_dir = subprocess.check_output(['swift', 'build', '--package-path', str(directory), '--scratch-path', str(args.scratch_path.resolve()), '--show-bin-path'], text=True).strip()
        bundle = args.scratch_path.resolve() / 'SearchIntegration.app'
        (bundle / 'Contents/MacOS').mkdir(parents=True, exist_ok=True)
        shutil.copy2(Path(binary_dir) / 'SearchIntegration', bundle / 'Contents/MacOS/SearchIntegration')
        (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': 'local.codex.telegram.SearchIntegration', 'CFBundleName': 'Telegram Search Validation', 'CFBundleExecutable': 'SearchIntegration', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '1'}))
        print('Native fixture app: ' + str(bundle))
    else:
        raise SystemExit(subprocess.run(command).returncode)
