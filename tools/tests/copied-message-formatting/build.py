import argparse
from pathlib import Path
import subprocess
from isolated_native import isolated_source_root

parser = argparse.ArgumentParser()
parser.add_argument('--source-root', type=Path, default=Path(__file__).resolve().parents[3])
parser.add_argument('--derived-data', type=Path, required=True)
parser.add_argument('--baseline')
args = parser.parse_args()
root = isolated_source_root(args.source_root)
harness = root / 'packages/ChatUI/Sources/ChatUI/CopyFormattingHarness.swift'
controller = root / 'packages/ChatUI/Sources/ChatUI/ChatController.swift'
paths = [controller] + [root / path for path in [
    'packages/ChatUI/Sources/ChatUI/ChatMessageItem.swift',
    'packages/InputView/Sources/InputView/ChatTextInputState.swift',
    'Telegram-Mac/utils/InAppLinks.swift',
    'packages/MessageUtils/Sources/MessageUtils/MessageTextEntityExtensions.swift',
]]
assert not harness.exists()
original = {path: path.read_bytes() for path in paths}
try:
    if args.baseline:
        for path in paths[1:]:
            path.write_bytes(subprocess.check_output(['git', 'show', args.baseline + ':' + str(path.relative_to(root))], cwd=root))
    harness.write_bytes(Path(__file__).with_name('RenderedCopyHarness.swift').read_bytes())
    source = controller.read_text()
    marker = '    public override func viewDidAppear(_ animated: Bool) {\n        super.viewDidAppear(animated)'
    assert source.count(marker) == 1
    controller.write_text(source.replace(marker, marker + '\n        codexInstallCopyEvidence(source: chatInteraction, parent: genericView)'))
    result = subprocess.run(['xcodebuild', '-workspace', 'Telegram-Mac.xcworkspace', '-scheme', 'Telegram', '-configuration', 'Debug', '-destination', 'platform=macOS,arch=arm64', '-derivedDataPath', str(args.derived_data.resolve()), '-jobs', '1', 'CODE_SIGNING_ALLOWED=NO', 'COMPILER_INDEX_STORE_ENABLE=NO', 'build'], cwd=root)
finally:
    for path, data in original.items():
        path.write_bytes(data)
    harness.unlink(missing_ok=True)
raise SystemExit(result.returncode)
