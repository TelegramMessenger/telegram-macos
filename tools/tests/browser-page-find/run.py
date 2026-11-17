import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys

assert sys.flags.isolated
parser = argparse.ArgumentParser()
parser.add_argument('--output', required=True, type=Path)
parser.add_argument('--lock', required=True, type=Path)
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]
out = args.output.resolve()
assert not out.is_relative_to(root)
out.mkdir(parents=True, exist_ok=False)
source_path = root / 'packages/WebAppUI/Sources/WebAppUI/BrowserPageFind.swift'
source = source_path.read_text()
fixture = Path(__file__).with_name('BrowserFindTests.swift')
boundary = Path(__file__).with_name('Boundary.swift.in')
compiler = subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip()
sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
records = []


def run(name, command, compile=False):
    lock = args.lock.open('r+')
    if compile:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
    assert shutil.disk_usage(out).free >= 8 * 1024 ** 3
    with (out / (name + '.log')).open('x') as log:
        p = subprocess.Popen(command, cwd=root, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        abort = False
        while True:
            if shutil.disk_usage(out).free < 4 * 1024 ** 3:
                os.killpg(p.pid, signal.SIGTERM)
                abort = True
            try:
                code = p.wait(timeout=1)
                break
            except subprocess.TimeoutExpired:
                pass
    lock.close()
    records.append({'name': name, 'command': command, 'exit': code, 'disk_abort': abort})
    if code:
        print((out / (name + '.log')).read_text()[-10000:])
        raise SystemExit(code)


harness = out / 'main.swift'
queue_path = root / 'packages/WebAppUI/Sources/WebAppUI/BrowserFindRequestQueue.swift'
harness.write_text(boundary.read_text() + '\n' + source.replace('import WebKit\n', '').replace('import InstantPageUI\n', '') + '\n' + fixture.read_text())
flags = [compiler, '-j1', '-swift-version', '5', '-sdk', sdk, '-target', 'arm64-apple-macos12.0', '-module-cache-path', str(out / 'cache')]
run('compile', flags + ['-Onone', str(queue_path), str(harness), '-o', str(out / 'tests')], compile=True)
run('tests', [str(out / 'tests')])
text = (out / 'tests.log').read_text()
match = re.search(r'BROWSER_FIND_RESULT checks=(\d+) failures=(\d+)', text)
assert match and int(match[2]) == 0
browser = (root / 'packages/WebAppUI/Sources/WebAppUI/WebappBrowser.swift').read_text()
app = (root / 'Telegram-Mac/app/AppDelegate.swift').read_text()
web = (root / 'packages/WebAppUI/Sources/WebAppUI/WebpageModalController.swift').read_text()
site = (root / 'packages/WebAppUI/Sources/WebAppUI/WebsiteController.swift').read_text()
iv = (root / 'packages/WebAppUI/Sources/WebAppUI/InstantViewInBrowser.swift').read_text()
wiring = {
    'browser_menu_bridge': 'browser.performPageFindAction(.showFindInterface)' in app,
    'instant_menu_bridge': 'instantPagePerformFindAction(in: window, action: .showFindInterface)' in app,
    'native_webkit_client': 'finder.client = webView' in source,
    'native_webkit_container': 'finder.findBarContainer = container' in source,
    'active_page_dispatch': 'pageFind.attach(webView: webView, container: genericView)' in browser,
    'webapp_webview': 'public var findWebView: WKWebView?' in web,
    'website_webview': 'public var findWebView: WKWebView?' in site,
    'instant_delegation': 'return page.performFindAction(action)' in iv,
    'find_dismiss_before_page_escape': 'self?.page.dismissFindInterface() == true' in iv,
    'modal_guard': 'guard sheets.isEmpty, !hasModals(self) else { return false }' in browser,
    'menu_key_equivalent': 'public override func performKeyEquivalent(with event: NSEvent)' in browser,
    'tab_switch_dismiss': 'pageFind.dismiss(restoreFocus: false)' in browser,
    'no_javascript_search_injection': 'evaluateJavaScript' not in source,
    'telegram_find_field': 'PageFindBarView(frame:' in source and 'private let searchView = PageFindSearchView' in (root / 'packages/InstantPageUI/Sources/InstantPageUI/PageFindBarView.swift').read_text(),
    'public_webkit_find': 'webView.find(query, configuration: configuration)' in source,
}
assert all(wiring.values()), wiring
result = {'at': datetime.datetime.now().astimezone().isoformat(), 'records': records, 'native_checks': int(match[1]), 'failures': 0, 'source_sha256': hashlib.sha256(source.encode()).hexdigest(), 'fixture_sha256': hashlib.sha256(fixture.read_bytes()).hexdigest(), 'boundary_sha256': hashlib.sha256(boundary.read_bytes()).hexdigest(), 'wiring_checks': wiring, 'queue_sha256': hashlib.sha256(queue_path.read_bytes()).hexdigest(), 'boundary': 'Exact production helper and request queue execute with controlled WebKit/KVO and search-bar boundaries; real AppKit geometry/action enums. Full real InstantPageUI/WebAppUI module compile is separate evidence, not performed by this portable runner. No web content loaded, no Telegram/GUI interaction. Wiring checks are source assertions, not runtime menu delivery or rendering tests.'}
(out / 'verification.json').write_text(json.dumps(result, indent=2) + '\n')
print(json.dumps({'native_checks': int(match[1]), 'wiring_checks': len(wiring), 'real_module_typecheck': 'SEPARATE_VERIFICATION'}))
