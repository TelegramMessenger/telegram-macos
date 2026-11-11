import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/ChatExportUI/Sources/ChatExportUI/ChatExportHtmlWriter.swift')
parser.add_argument('--evidence', type=Path, required=True)
args = parser.parse_args()
source = args.source.read_text()
methods = []
for name in ['begin', 'pageFileName', 'openPage', 'closePage', 'finish', 'rolloverIfNeeded', 'insertDateDividerIfNeeded', 'appendService', 'writeServiceBlock', 'write']:
    prefix = '    public func ' if name in ['begin', 'finish', 'appendService'] else '    private func '
    start = source.index(prefix + name + '(')
    end = source.index('\n    }', start) + len('\n    }')
    methods.append(source[start:end])
fixture = Path(__file__).with_name('WriterTests.swift').read_text().replace('__METHODS__', '\n'.join(methods))
args.evidence.mkdir(parents=True, exist_ok=True)
(args.evidence / 'main.swift').write_text(fixture)
cases = ['normal', 'empty', 'pagination', 'create-failure', 'message-failure', 'footer-failure', 'rollover-failure', 'full-file']
output = []
with tempfile.TemporaryDirectory(prefix='chat-export-io-') as temp:
    binary = str(Path(temp) / 'tests')
    command = ['swiftc', '-module-cache-path', '/tmp/chat-export-io-cache', str(args.evidence / 'main.swift'), '-o', binary]
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
