import argparse
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--source', type=Path, default=root / 'packages/WebAppUI/Sources/WebAppUI/WebpageModalController.swift')
parser.add_argument('--evidence', type=Path)
args = parser.parse_args()
source = args.source.read_text()
start = source.index('    public func webView(_ webView: WKWebView, runOpenPanelWith')
end = source.index('    public func webView(_ webView: WKWebView, createWebViewWith', start)
fixture = Path(__file__).with_name('CompletionTests.swift').read_text().replace('__METHODS__', source[start:end])
cases = ['confirm-no-window', 'confirm-accept', 'confirm-cancel', 'confirm-dismiss', 'confirm-accept-dismiss', 'confirm-cancel-dismiss', 'open-no-window', 'open-cancel', 'open-files', 'permission-no-window', 'permission-owner-gone', 'permission-dismiss', 'permission-allow-dismiss', 'permission-cancel-dismiss', 'permission-denied', 'permission-cached', 'permission-no-bot', 'permission-unknown', 'permission-microphone', 'permission-combined', 'permission-combined-denied', 'alert-dismiss']
with tempfile.TemporaryDirectory(prefix='webkit-completions-') as temp:
    directory = Path(temp)
    (directory / 'main.swift').write_text(fixture)
    command = ['swiftc', '-module-cache-path', '/tmp/webkit-completions-module-cache', str(directory / 'main.swift'), '-o', str(directory / 'tests')]
    result = subprocess.run(command, capture_output=True, text=True)
    output = ['$ ' + ' '.join(command) + '\n' + result.stdout + result.stderr]
    if result.returncode:
        print(output[0])
        raise SystemExit(result.returncode)
    failed = 0
    for case in cases:
        result = subprocess.run([str(directory / 'tests'), case], capture_output=True, text=True)
        failed += result.returncode != 0
        item = f'{"PASS" if result.returncode == 0 else "FAIL"} {case} exit={result.returncode}\n{result.stdout}{result.stderr}'
        output.append(item)
        print(item, flush=True)
    output.append(f'{len(cases) - failed} passed; {failed} failed')
    print(output[-1])
    if args.evidence:
        args.evidence.mkdir(parents=True, exist_ok=True)
        (args.evidence / 'extracted-main.swift').write_text(fixture)
        (args.evidence / 'results.log').write_text('\n'.join(output) + '\n')
    raise SystemExit(bool(failed))
