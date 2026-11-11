from pathlib import Path
import json
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
editor = (root / 'packages/AvatarEditorUI/Sources/AvatarEditorUI/EditImageModalController.swift').read_text()
hooks = (root / 'packages/ChatUI/Sources/ChatUI/ChatNavigationHooks.swift').read_text()
context = (root / 'packages/AppAnalytics/Sources/AppAnalytics/AnalyticsContext.swift').read_text()

def section(source, start, end):
    offset = source.index(start)
    return source[offset:source.index(end, offset)]

parts = {
    '__EDITOR_CLOSE__': section(editor, '    public override func close(animationType:', '    public override func returnKeyAction()'),
    '__EDITOR_CONFIRM__': section(editor, '        let invoke = { [weak self] in', '        if let confirm = self.confirm'),
    '__EDITOR_HOOK__': section(hooks, '    public var editImage:', '    public var setPeerPhoto:'),
    '__CONTEXT_SIGNAL__': section(context, '    public func preservingPresentation<', '\n}\n\npublic final class AnalyticsPresentation'),
}
fixture = Path(__file__).with_name('EditorLifecycleTests.swift').read_text()
for name, body in parts.items():
    fixture = fixture.replace(name, body)
with tempfile.TemporaryDirectory(prefix='image-editor-lifecycle-') as directory:
    directory = Path(directory)
    dependency = json.dumps(str(root / 'submodules/telegram-ios/submodules/SSignalKit'))
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "ImageEditorLifecycle", platforms: [.macOS(.v10_13)], dependencies: [.package(path: ''' + dependency + ''')], targets: [.testTarget(name: "ImageEditorLifecycleTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/EditorLifecycleTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
