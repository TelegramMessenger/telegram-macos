from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[3]
flags = ['-lbz2', '-liconv']
for directory in [
    'libvpx/build/libvpx/lib', 'ffmpeg/build/ffmpeg/lib', 'libopus/build/libopus/lib',
    'libwebp/build/libwebp/lib', 'Mozjpeg/build', 'openssl/build/openssl/lib',
    'webrtc/build/webrtc', 'OpenH264/build/output/lib', 'dav1d/build/dav1d/lib',
    'tde2e/build/tde2e/lib',
]:
    libraries = sorted((root / 'core-xprojects' / directory).glob('*.a'))
    if not libraries:
        raise SystemExit('Missing native libraries: ' + directory)
    flags.extend(str(library) for library in libraries)

raise SystemExit(subprocess.run([
    'xcodebuild', 'test', '-workspace', str(root / 'Telegram-Mac.xcworkspace'),
    '-scheme', 'PeerModerationUITests', '-destination', 'platform=macOS,arch=arm64',
    'OTHER_LDFLAGS=$(inherited) ' + ' '.join(flags),
    '-only-testing:PeerModerationUITests/ChannelParticipantModerationMenuTests',
    '-only-testing:ChatUITests/ChatAvatarMenuBindingTests',
    *sys.argv[1:],
], cwd=root).returncode)
