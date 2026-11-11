from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
analytics = root / 'packages/AppAnalytics/Sources/AppAnalytics'
fixture = Path(__file__).with_name('SubmissionContextTests.swift').read_text()
fixture = fixture.replace('__POLICY__', (analytics / 'AnalyticsScope.swift').read_text().replace('public ', ''))
context = (analytics / 'AnalyticsContext.swift').read_text()
start = context.index('public final class AnalyticsContext {')
end = context.index('    public func beginPresentation()', start)
fixture = fixture.replace('__CONTEXT__', (context[start:end] + '}').replace('public ', ''))
start = context.index('    func captureContext(owner:')
end = context.index('\n    func excludedContext()', start)
fixture = fixture.replace('__CAPTURE__', context[start:end])
journey = (analytics / 'AnalyticsMediaJourney.swift').read_text()
start = journey.index('    fileprivate var submissionContext:')
end = journey.index('    public func discard()', start)
fixture = fixture.replace('__SUBMISSION_CONTEXT__', journey[start:end])
with tempfile.TemporaryDirectory(prefix='media-submission-context-') as directory:
    directory = Path(directory)
    (directory / 'Package.swift').write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "MediaSubmissionContext", targets: [.testTarget(name: "MediaSubmissionContextTests", path: "Tests")])
''')
    (directory / 'Tests').mkdir()
    (directory / 'Tests/SubmissionContextTests.swift').write_text(fixture)
    raise SystemExit(subprocess.run(['swift', 'test', '--package-path', str(directory), '--disable-sandbox', '--jobs', '4']).returncode)
