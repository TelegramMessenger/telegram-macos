import argparse
import json
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
args = parser.parse_args()
def read(name, module):
    return (Path('/tmp')/(name+'-before-recording-send.swift') if args.baseline else root/'packages'/module/'Sources'/module/(name+'.swift')).read_text()
def block(source, marker):
    a = source.index(marker); b = source.index('{', a) + 1; depth = 1
    while depth:
        depth += (source[b] == '{') - (source[b] == '}'); b += 1
    return source[a:b]
core = read('ChatRecordingState', 'MediaRecorderUI')
ui = read('ChatInputRecordingView', 'ChatUI')
methods = ['public func updateTrimRange', 'public var isTrimmed', 'public var pendingTrimRange', 'public final func applyTrimAndResume', 'public final func send', 'public final func cancel']
if not args.baseline: methods.append('private func completeSubmission')
core_methods = '\n'.join(block(core, x).replace('public ', '').replace('private ', '').replace('final ', '') for x in methods)
fixture = Path(__file__).with_name('RecordingSendTests.swift').read_text().replace('__CORE__', core_methods)
audio = core[core.index('public final class ChatRecordingAudioState'):]
fixture = fixture.replace('__AUDIO__', block(audio, 'public override var data').replace('public override ', ''))
video = block(core, 'private func trimmedVideoFile').replace('private ', '')
if args.baseline: video = video.replace('Signal<(String, Double), NoError>', 'Signal<(String, Double)?, NoError>')
fixture = fixture.replace('__VIDEO__', video)
input_methods = ['private func stopAndSend', 'private func setResuming']
if not args.baseline: input_methods.append('private func updateSubmissionState')
ui_methods = '\n'.join(block(ui, x).replace('private ', '') for x in input_methods)
if args.baseline: ui_methods += '\nfunc updateSubmissionState(_ state: ChatRecordingSubmissionState) {}'
fixture = fixture.replace('__UI__', ui_methods)
controller = read('ChatController', 'ChatUI'); controller = controller[controller.index('        let sendMediaWithAnalytics:'):]
fixture = fixture.replace('__EMPTY__', block(controller, 'if media.isEmpty'))
fixture = fixture.replace('__BASELINE__', str(args.baseline).lower())
with tempfile.TemporaryDirectory(prefix='recording-send-') as directory:
    directory = Path(directory)
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "RecordingSend", platforms: [.macOS(.v10_13)], dependencies: [.package(path: '''+json.dumps(str(root/'submodules/telegram-ios/submodules/SSignalKit'))+''')], targets: [.testTarget(name: "RecordingSendTests", dependencies: [.product(name: "SwiftSignalKit", package: "SSignalKit")], path: "Tests")])
''')
    (directory/'Tests').mkdir()
    (directory/'Tests/RecordingSendTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
