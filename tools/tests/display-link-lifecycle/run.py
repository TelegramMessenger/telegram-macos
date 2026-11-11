import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/TGUIKit/Sources/DisplayLinkAnimator.swift')
parser.add_argument('--evidence', type=Path, required=True)
args = parser.parse_args()
source = args.source.read_text()
source = source[source.index('final class DisplayLinkGate'):source.index('public protocol SharedDisplayLinkDriverLink')]
fixture = Path(__file__).with_name('LifecycleTests.swift').read_text().replace('__SOURCE__', source)
args.evidence.mkdir(parents=True, exist_ok=True)
(args.evidence / 'main.swift').write_text(fixture)
cases = ['create-failure', 'display-failure', 'callback-failure', 'never-started', 'cancel-before-start', 'start-failure', 'normal', 'cancel']
output = []
with tempfile.TemporaryDirectory(prefix='display-link-lifecycle-') as temp:
    binary = str(Path(temp) / 'tests')
    command = ['swiftc', '-module-cache-path', '/tmp/display-link-lifecycle-cache', str(args.evidence / 'main.swift'), '-o', binary]
    result = subprocess.run(command, capture_output=True, text=True)
    output.append('$ ' + ' '.join(command) + '\n' + result.stdout + result.stderr)
    if result.returncode:
        print(output[-1])
        raise SystemExit(result.returncode)
    failed = 0
    for case in cases:
        result = subprocess.run([binary, case], capture_output=True, text=True)
        failed += result.returncode != 0
        output.append(f'{case}: exit {result.returncode}\n{result.stdout}{result.stderr}')
        print(f'{case}: exit {result.returncode}', flush=True)
    output.append(f'{len(cases) - failed}/{len(cases)} passed')
    print(output[-1])
    (args.evidence / 'results.log').write_text('\n'.join(output))
    raise SystemExit(bool(failed))
