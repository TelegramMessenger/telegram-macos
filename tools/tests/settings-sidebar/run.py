import argparse
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument('--baseline', action='store_true')
parser.add_argument('--baseline-ref', default='e18830989542a063dd66c5bdc4dbe6a70cbbd175')
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
path = 'Telegram-Mac/app/MainViewController.swift'
source = subprocess.check_output(['git', 'show', args.baseline_ref + ':' + path], cwd=root, text=True) if args.baseline else (root / path).read_text()
start = source.index('    private var previousIndex: Int? = nil')
end = source.index('    override func focusSearch(', start)
methods = source[start:end]
fixture = Path(__file__).with_name('NavigationTests.swift').read_text().replace('__METHODS__', methods)
with tempfile.TemporaryDirectory(prefix='settings-sidebar-') as temp:
    temp = Path(temp)
    swift = temp / 'main.swift'
    swift.write_text(fixture)
    binary = temp / 'navigation-tests'
    subprocess.run(['swiftc', str(swift), '-o', str(binary)], check=True)
    result = subprocess.run([str(binary)])
    registered = 'context.bindings.rootNavigation().add(listener: WeakReference(value: self))' in source
    print(('PASS' if registered else 'FAIL') + ': MainViewController registers the root-navigation listener', flush=True)
    raise SystemExit(result.returncode or (0 if registered else 1))
