import argparse
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser(); parser.add_argument('--filter'); args = parser.parse_args()
source = (root/'packages/TelegramMedia/Sources/AudioRecorder.swift').read_text()
def block(marker):
    a = source.index(marker); b = source.index('{', a) + 1; depth = 1
    while depth:
        depth += (source[b] == '{') - (source[b] == '}'); b += 1
    return source[a:b]
converter = source[source.index('private final class CustomAudioConverter'):source.index('private let kOutputBus')].replace('private final class', 'final class')
markers = ['    func processAndDisposeAudioBuffer(_ buffer: AudioBuffer) {', '    private func processAudioData(', '    private func flushAudioConverter(', '    private func tearDownAudioUnit(', '    func stop() {', '    func pause() {', '    func resume() {', '    func takeData() -> RecordedAudioData? {']
methods = '\n'.join(block(marker) for marker in markers if marker in source)
fixture = Path(__file__).with_name('RecordingSampleRateTests.swift').read_text()
fixture = fixture.replace('__CONVERTER__', converter).replace('__FORMAT__', block('public func audioRecorderNativeStreamDescription')).replace('__METHODS__', methods)
with tempfile.TemporaryDirectory(prefix='recording-sample-rate-') as directory:
    directory = Path(directory)
    (directory/'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "RecordingSampleRate", platforms: [.macOS(.v10_13)], targets: [.testTarget(name: "RecordingSampleRateTests", path: "Tests")])
''')
    (directory/'Tests').mkdir()
    (directory/'Tests/RecordingSampleRateTests.swift').write_text(fixture)
    command = ['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']
    if args.filter: command += ['--filter', 'RecordingSampleRateTests.' + args.filter]
    raise SystemExit(subprocess.run(command).returncode)
