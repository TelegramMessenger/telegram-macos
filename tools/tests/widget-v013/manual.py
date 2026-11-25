from pathlib import Path
import argparse
import gzip
import hashlib
import json
import plistlib
import subprocess
import sys
import zlib

ROOT = Path(__file__).resolve().parents[3]
STYLE = '''
body { margin:0; padding:12px; font-family:system-ui; color:var(--tg-theme-text-color); background:var(--tg-theme-bg-color); }
h3 { margin:0 0 8px; font-size:17px; }
p { margin:6px 0; font-size:14px; line-height:1.4; }
button { padding:9px 12px; margin:6px 6px 0 0; border:0; border-radius:8px; color:var(--tg-theme-button-text-color); background:var(--tg-theme-button-color); }
.ok { color:#168246; font-weight:600; }
.bad { color:#c83838; font-weight:600; }
.row { height:30px; line-height:30px; border-bottom:1px solid #999; }
'''


def card(title, body, script):
    return f'<html><head><style>{STYLE}</style></head><body><h3>{title}</h3>{body}<script>{script}</script></body></html>'


def resize_card(anchor):
    direction = 'downward' if anchor == 'top' else 'upward'
    controls = '<button id="add">Add row</button><button id="remove">Remove row</button>'
    content = '<div id="rows"></div>'
    layout = content + controls if anchor == 'top' else controls + content
    return card(
        f'{"3" if anchor == "top" else "4"}. {anchor.capitalize()} edge stays still',
        f'<p>Click Add row, then Remove row. The card should grow {direction}. Its {anchor} edge should stay in the same place.</p>'
        '<p id="sdk"></p>' + layout,
        '''
var rows=document.getElementById('rows');
var sdk=document.getElementById('sdk');
var supported=typeof TelegramWidget.setResizeAnchor==='function';
sdk.textContent=supported?'Resize API available':'FAIL: resize API missing';
sdk.className=supported?'ok':'bad';
''' + f"if(supported) TelegramWidget.setResizeAnchor('{anchor}');" + '''
function add(){if(rows.children.length>=6)return;var row=document.createElement('div');row.className='row';row.textContent='Row '+(rows.children.length+1);rows.appendChild(row);}
add();add();
document.getElementById('add').onclick=add;
document.getElementById('remove').onclick=function(){if(rows.lastChild)rows.removeChild(rows.lastChild);};
''')


def make_fixtures(output):
    fixtures = output / 'fixtures'
    fixtures.mkdir(parents=True, exist_ok=True)
    specs = []
    for name, number, encoding in [('01-new-zlib.zlib', 1, 'zlib'), ('02-legacy-gzip.gzip', 2, 'gzip')]:
        html = card(
            f'{number}. {"New zlib" if encoding == "zlib" else "Older gzip"} message loaded',
            '<p class="ok">PASS: you can see this card.</p><p>Click the button. The counter should increase.</p><button id="clicks">Clicks: 0</button>',
            "var n=0;document.getElementById('clicks').onclick=function(){this.textContent='Clicks: '+(++n);};")
        specs.append((name, encoding, html))
    specs.extend([
        ('03-top-resize.gzip', 'gzip', resize_card('top')),
        ('04-bottom-resize.gzip', 'gzip', resize_card('bottom')),
        ('05-slider.gzip', 'gzip', card(
            '5. Drag sideways; scroll vertically',
            '<p>Drag the blue track left/right: the number should change. With your pointer over it, scroll up/down: the chat should move.</p>'
            '<p>Value: <b id="value">50</b></p><div id="track" style="height:64px;background:#2878d8;border-radius:10px;touch-action:none;user-select:none;position:relative">'
            '<div id="thumb" style="position:absolute;left:50%;top:18px;width:8px;height:28px;background:white;pointer-events:none"></div></div>'
            '<p>Also scroll away from these cards and back. Watch for jumps or flickering.</p>',
            '''
var track=document.getElementById('track'),active=false;
function move(e){var r=track.getBoundingClientRect();var v=Math.max(0,Math.min(100,Math.round((e.clientX-r.left)/Math.max(1,r.width)*100)));document.getElementById('value').textContent=String(v);document.getElementById('thumb').style.left=v+'%';}
track.addEventListener('pointerdown',function(e){active=true;try{track.setPointerCapture(e.pointerId);}catch(_){}move(e);});
track.addEventListener('pointermove',function(e){if(active)move(e);});
track.addEventListener('pointerup',function(){active=false;});
track.addEventListener('pointercancel',function(){active=false;});
''')),
    ])
    manifest = []
    for old_name in ['03-top-resize.zlib', '04-bottom-resize.zlib', '05-slider.zlib']:
        (fixtures / old_name).unlink(missing_ok=True)
    for name, encoding, html in specs:
        raw = html.encode()
        payload = zlib.compress(raw, 9) if encoding == 'zlib' else gzip.compress(raw, compresslevel=9, mtime=0)
        if len(raw) > 32768 or len(payload) > 4096:
            raise ValueError(f'{name}: fixture exceeds widget size limits')
        if zlib.decompress(payload, 47) != raw:
            raise ValueError(f'{name}: invalid payload')
        (fixtures / name).write_bytes(payload)
        manifest.append({'file': name, 'encoding': encoding, 'bytes': len(payload), 'htmlBytes': len(raw), 'sha256': hashlib.sha256(payload).hexdigest()})
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    return fixtures


def find_app(override):
    if override:
        candidates = [Path(override).expanduser().resolve()]
    else:
        candidates = []
        derived = Path.home() / 'Library/Developer/Xcode/DerivedData'
        for info in derived.glob('Telegram-Mac-*/info.plist'):
            with info.open('rb') as handle:
                metadata = plistlib.load(handle)
            if metadata.get('WorkspacePath') == str(ROOT / 'Telegram-Mac.xcworkspace'):
                candidates.append(info.parent / 'Build/Products/Debug/Telegram.app')
    candidates = [app for app in candidates if (app / 'Contents/MacOS/Telegram').is_file()]
    if not candidates:
        raise RuntimeError('Build the Debug app first, or pass --app /path/to/Telegram.app')
    return max(candidates, key=lambda app: (app / 'Contents/MacOS/Telegram').stat().st_mtime)


def main():
    parser = argparse.ArgumentParser(description='Open a local widget test chat in the Debug app.')
    parser.add_argument('--app')
    parser.add_argument('--behavior', choices=['old', 'new'], default='new')
    parser.add_argument('--prepare-only', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT / '.build/widget-v013-manual')
    args = parser.parse_args()
    output = args.output.expanduser().resolve()
    fixtures = make_fixtures(output)
    print(f'Prepared 5 cards: {fixtures}')
    if args.prepare_only:
        return
    app = find_app(args.app)
    binary = str(app / 'Contents/MacOS/Telegram')
    processes = subprocess.check_output(['/bin/ps', '-axo', 'command='], text=True)
    if any(line.strip() == binary or line.strip().startswith(binary + ' ') for line in processes.splitlines()):
        raise RuntimeError('Quit this Debug Telegram with Command-Q, then double-click manual.command again. A fresh launch is needed to open the test chat.')
    subprocess.run([
        '/usr/bin/open', '-n', str(app), '--args',
        '-PerfLab', 'chat-navigation',
        '-PerfLabLabel', 'widget-v013-manual-' + args.behavior,
        '-PerfLabOutput', str(output / 'reports'),
        '-PerfLabSynthetic', '15',
        '-PerfLabSyntheticWidgets', str(fixtures),
        '-PerfLabWidgetEvery', '3',
        '-PerfLabWidgetBehavior', args.behavior,
        '-PerfLabSyntheticTitle', 'Widgets — ' + args.behavior.upper(),
        '-PerfLabSyntheticStatus', 'Previous app integration' if args.behavior == 'old' else 'v0.1.3 app integration',
        '-PerfLabScenarios', 'manual',
        '-PerfLabStartDelay', '1',
        '-PerfLabOpenWait', '2',
    ], check=True)
    print('Telegram will open Widgets — ' + args.behavior.upper() + ' after the account is ready.')
    print('Scroll through its five numbered cards and follow their instructions.')
    print('This is a local test chat; it sends no test messages. Leave it with the Back button.')


if __name__ == '__main__':
    try:
        main()
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f'Widget test: {error}', file=sys.stderr)
        sys.exit(1)
