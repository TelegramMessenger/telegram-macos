from pathlib import Path
import subprocess
import sys


root = Path(__file__).resolve().parents[3]
result = subprocess.run([
    'bash', str(root / 'packages/ChatUI/Tests/run-tests.sh'),
    '-only-testing:ChatUITests/ChatAvatarMenuBindingTests',
    *sys.argv[1:],
], cwd=root)
raise SystemExit(result.returncode)
