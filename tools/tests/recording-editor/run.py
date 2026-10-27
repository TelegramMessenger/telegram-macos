from pathlib import Path
import argparse
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--derived-data', type=Path, required=True)
    parser.add_argument('--log', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[3]
    flags = ['-lbz2', '-liconv']
    for name in ['libvpx/build/libvpx/lib', 'ffmpeg/build/ffmpeg/lib', 'libopus/build/libopus/lib', 'libwebp/build/libwebp/lib', 'Mozjpeg/build', 'openssl/build/openssl/lib', 'webrtc/build/webrtc', 'OpenH264/build/output/lib', 'dav1d/build/dav1d/lib', 'tde2e/build/tde2e/lib']:
        flags += ['"' + str(path) + '"' for path in sorted((root / 'core-xprojects' / name).glob('*.a'))]
    command = ['xcodebuild', 'test', '-workspace', 'Telegram-Mac.xcworkspace', '-scheme', 'ChatUITests', '-destination', 'platform=macOS,arch=arm64', '-derivedDataPath', str(args.derived_data.resolve()), '-jobs', '4', '-only-testing:ChatUITests/RecordingTrimScrubberInteractionTests', '-only-testing:ChatUITests/RecordingVideoPreviewTests', '-only-testing:ChatUITests/RecordingOverlayLifecycleTests', '-only-testing:ChatUITests/RecordingCameraLifecycleTests', 'OTHER_LDFLAGS=$(inherited) ' + ' '.join(flags), 'MACOSX_DEPLOYMENT_TARGET=12.0', 'CODE_SIGNING_ALLOWED=NO', 'CODE_SIGNING_REQUIRED=NO', 'DEVELOPMENT_TEAM=']
    args.log.parent.mkdir(parents=True, exist_ok=True)
    target = root / 'packages/ChatUI/Tests/ChatUITests'
    generated = target / 'RecordingCameraLifecycleController.swift'
    tests = target / 'RecordingCameraLifecycleTests.swift'
    if generated.exists() or tests.exists():
        raise RuntimeError('Camera lifecycle fixture paths already exist')
    controller = (root / 'packages/MediaRecorderUI/Sources/MediaRecorderUI/VideoRecorderModalController.swift').read_text()
    controller = controller.replace('public class VideoRecorderModalController:', 'final class RecordingCameraLifecycleController:')
    controller = controller.replace('VideoRecorderPipeline', 'RecordingCapturePipelineProbe').replace('VideoRecorderModalView', 'RecordingCaptureViewProbe')
    controller = 'import MediaRecorderUI\n' + controller
    try:
        generated.write_text(controller)
        tests.write_bytes((Path(__file__).parent / 'CameraLifecycleTests.swift').read_bytes())
        with args.log.open('w') as log:
            result = subprocess.run(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, timeout=1800)
    finally:
        generated.unlink(missing_ok=True)
        tests.unlink(missing_ok=True)
    print(args.log.resolve())
    raise SystemExit(result.returncode)


if __name__ == '__main__':
    main()
