from pathlib import Path
import argparse
import os
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--derived-data', type=Path, required=True)
    parser.add_argument('--baseline-ref', default='272d85dd7cc78864549b1d5510a177db79059fc7')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    timeline_path = 'packages/ChatUI/Sources/ChatUI/RecordingTrimScrubberView.swift'
    timeline = root / timeline_path
    current = timeline.read_bytes()
    baseline = subprocess.check_output(['git', 'show', args.baseline_ref + ':' + timeline_path], cwd=root)
    fixture = root / 'packages/ChatUI/Tests/ChatUITests/RecordingEditorReviewSnapshotTests.swift'
    assert not fixture.exists()
    flags = ['-lbz2', '-liconv']
    for name in ['libvpx/build/libvpx/lib', 'ffmpeg/build/ffmpeg/lib', 'libopus/build/libopus/lib', 'libwebp/build/libwebp/lib', 'Mozjpeg/build', 'openssl/build/openssl/lib', 'webrtc/build/webrtc', 'OpenH264/build/output/lib', 'dav1d/build/dav1d/lib', 'tde2e/build/tde2e/lib']:
        flags += ['"' + str(path) + '"' for path in sorted((root / 'core-xprojects' / name).glob('*.a'))]
    command = ['xcodebuild', 'test', '-workspace', 'Telegram-Mac.xcworkspace', '-scheme', 'ChatUITests', '-destination', 'platform=macOS,arch=arm64', '-derivedDataPath', str(args.derived_data.resolve()), '-jobs', '4', '-only-testing:ChatUITests/RecordingEditorReviewSnapshotTests/testCaptureTimeline', 'OTHER_LDFLAGS=$(inherited) ' + ' '.join(flags), 'MACOSX_DEPLOYMENT_TARGET=12.0', 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'DEVELOPMENT_TEAM=']
    fixture.write_bytes(Path(__file__).with_name('ReviewSnapshot.swift').read_bytes())
    try:
        for name, source in [('before', baseline), ('after', current)]:
            timeline.write_bytes(source)
            environment = dict(os.environ, RECORDING_REVIEW_IMAGE=str(output / (name + '.png')), RECORDING_REVIEW_BEFORE='1' if name == 'before' else '0')
            environment['TEST_RUNNER_RECORDING_REVIEW_IMAGE'] = environment['RECORDING_REVIEW_IMAGE']
            environment['TEST_RUNNER_RECORDING_REVIEW_BEFORE'] = environment['RECORDING_REVIEW_BEFORE']
            with (output / (name + '.log')).open('w') as log:
                result = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, env=environment, timeout=900)
            assert result.returncode == 0, 'See ' + str(output / (name + '.log'))
            assert (output / (name + '.png')).exists()
            print(name, output / (name + '.png'), flush=True)
    finally:
        assert timeline.read_bytes() in (baseline, current)
        timeline.write_bytes(current)
        fixture.unlink()


if __name__ == '__main__':
    main()
