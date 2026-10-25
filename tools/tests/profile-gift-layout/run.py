from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
fixtures = Path(__file__).parent
source = (root / 'packages/PeerInfoUI/Sources/PeerInfoUI/PeerInfoSpawnEmojiView.swift').read_text()
start = source.index('public struct PositionGenerator')
end = source.index('\nextension PeerInfoSpawnEmojiView', start)
implementation = 'import Foundation\n' + source[start:end]
head = (root / 'packages/PeerInfoUI/Sources/PeerInfoUI/PeerInfoHeadItem.swift').read_text()
start = head.index('    func startAnimations(index: Int)')
end = head.index('\n}\n', start)
motion = 'import Cocoa\nimport QuartzCore\nclass GiftAnimationProbe: CALayer {\nlet animationLayer = CALayer()\nlet shadowLayer = CALayer()\n' + head[start:end] + '\n}\n'
with tempfile.TemporaryDirectory(prefix='profile-gift-layout-') as directory:
    workspace = Path(directory)
    (workspace / 'Layout.swift').write_text(implementation)
    (workspace / 'Motion.swift').write_text(motion)
    (workspace / 'main.swift').write_text((fixtures / 'LayoutTests.swift').read_text())
    executable = workspace / 'tests'
    subprocess.run(['xcrun', 'swiftc', '-O', str(workspace / 'Layout.swift'), str(workspace / 'Motion.swift'), str(workspace / 'main.swift'), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True)
    fingerprints = [subprocess.check_output([str(executable), '--fingerprint']) for _ in range(5)]
    assert len(set(fingerprints)) == 1, 'Process relaunch changes gift positions'
    print('PASS: identical positions in five fresh processes')
