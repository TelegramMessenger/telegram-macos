from pathlib import Path
import argparse
import json
import subprocess
import sys
import time

sys.dont_write_bytecode = True

from manual import ROOT, find_app

CLICK = '''
import CoreGraphics
import Foundation
let a = CommandLine.arguments.dropFirst().map { Double($0)! }
Thread.sleep(forTimeInterval: a[2])
let p = CGPoint(x: a[0], y: a[1])
for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.06)
}
'''

SCROLL = '''
import CoreGraphics
import Foundation
let a = CommandLine.arguments.dropFirst().map { Double($0)! }
let p = CGPoint(x: a[0], y: a[1])
let steps = Int(abs(a[2]) / 10)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
func post(_ dy: Int32, _ phase: Int64) {
    guard let e = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0) else { return }
    e.location = p
    e.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
    e.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
    e.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: Int64(dy))
    e.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.016)
}
post(0, 1)
for _ in 0..<steps { post(a[2] > 0 ? 10 : -10, 2) }
post(0, 4)
'''

SCREEN = '''
import AppKit
let s = NSScreen.screens[0]
print(Int(s.frame.width), Int(s.frame.height), Int(s.backingScaleFactor))
'''

RED = (255, 0, 0)
BLUE = (0, 0, 255)
GREEN = (26, 143, 58)


def probe(anchor, timer):
    controls = '<div class="pad"><b>%s anchor</b><br><button id="add">Add 3 rows</button><button id="remove">Remove 3 rows</button></div>' % anchor
    rows = '<div id="rows"></div>'
    body = controls + rows if anchor == 'bottom' else rows + controls
    auto = "var grow=true;setInterval(function(){if(grow)add();else remove();grow=!grow;},1500);" if timer else ''
    return ('<html><head><style>body{margin:0;font:14px system-ui}.edge{height:12px}#top{background:#ff0000}#bottom{background:#0000ff}'
            '.pad{padding:8px 12px}button{font:15px system-ui;padding:10px 14px;margin:4px 6px 4px 0;border:0;border-radius:8px;color:#fff;background:#1a8f3a}'
            '.row{height:28px;line-height:28px;padding:0 12px;border-bottom:1px solid #888;background:#e8e8e8;color:#222}</style></head>'
            '<body><div class="edge" id="top"></div>' + body + '<div class="edge" id="bottom"></div><script>'
            "var rows=document.getElementById('rows');TelegramWidget.setResizeAnchor('" + anchor + "');"
            "function add(){for(var i=0;i<3;i++){var r=document.createElement('div');r.className='row';r.textContent='Row '+(rows.children.length+1);rows.appendChild(r);}}"
            "function remove(){for(var i=0;i<3&&rows.lastChild;i++)rows.removeChild(rows.lastChild);}"
            "add();document.getElementById('add').onclick=add;document.getElementById('remove').onclick=remove;" + auto + '</script></body></html>')


def near(pixel, color):
    return all(abs(a - b) < 60 for a, b in zip(pixel, color))


def raw(path, width=None):
    scale = [] if width is None else ['-vf', 'scale=%d:-1' % width]
    info = json.loads(subprocess.check_output(['ffprobe', '-v', 'error', '-select_streams', 'v:0', '-show_entries', 'stream=width,height', '-of', 'json', path]))['streams'][0]
    w, h = info['width'], info['height']
    if width is not None:
        h = h * width // w
        w = width
    data = subprocess.check_output(['ffmpeg', '-v', 'error', '-i', path, *scale, '-fps_mode', 'passthrough', '-f', 'rawvideo', '-pix_fmt', 'rgb24', '-'])
    return w, h, data


def runs(column, color):
    found, start = [], None
    for y, pixel in enumerate(column + [(255, 255, 255)]):
        if near(pixel, color):
            start = y if start is None else start
        elif start is not None:
            if y - start >= 4:
                found.append((start, y))
            start = None
    return found


def locate(work, points):
    shot = str(work / 'screen.png')
    subprocess.run(['screencapture', '-x', shot], check=True)
    w, h, data = raw(shot, points[0])
    pixel = lambda x, y: tuple(data[(y * w + x) * 3:(y * w + x) * 3 + 3])
    for x in range(0, w, 8):
        column = [pixel(x, y) for y in range(h)]
        top, bottom = runs(column, RED), runs(column, BLUE)
        if top and bottom and bottom[0][0] > top[0][0]:
            y0, y1 = top[0][0], bottom[0][1]
            buttons = []
            for y in range(y0, y1):
                row = [pixel(xx, y) for xx in range(w)]
                spans = [(s, e) for s, e in runs(row, GREEN) if e - s > 30]
                if len(spans) >= 2:
                    buttons = [((s + e) / 2, y) for s, e in spans[:2]]
                    break
            if buttons:
                return x + 20, buttons, (y0, y1)
    raise RuntimeError('No anchor probe on screen: keep the widget chat open and the probe visible')


def find(work, points, timeout=10):
    deadline = time.time() + timeout
    while True:
        try:
            return locate(work, points)
        except RuntimeError:
            if time.time() > deadline:
                raise
            time.sleep(0.5)


def measure(work, column_x, points, click, delay=0.8, seconds=3):
    video = work / 'run.mov'
    video.unlink(missing_ok=True)
    capture = subprocess.Popen(['screencapture', '-x', '-v', '-V', str(seconds), '-R', '%d,0,24,%d' % (column_x, points[1]), str(video)])
    if click:
        subprocess.run([str(work / 'click'), str(click[0]), str(click[1]), str(delay)], check=True)
    capture.wait()
    w, h, data = raw(str(video))
    frames = []
    size = w * h * 3
    for offset in range(0, len(data) - size + 1, size):
        frame = data[offset:offset + size]
        column = [tuple(frame[(y * w + w // 2) * 3:(y * w + w // 2) * 3 + 3]) for y in range(h)]
        frames.append((runs(column, RED), runs(column, BLUE)))
    return frames


def verdict(frames, anchor):
    edge = [f[1] if anchor == 'bottom' else f[0] for f in frames]
    other = [f[0] if anchor == 'bottom' else f[1] for f in frames]
    positions = {e[0] for e in edge if e}
    missing = sum(1 for e in edge if not e)
    moved = {o[0] for o in other if o}
    return len(positions) == 1, len(positions), missing, len(moved) > 1


def main():
    parser = argparse.ArgumentParser(description='Check that a widget bubble keeps its resize-anchor edge still on screen.')
    parser.add_argument('--anchor', choices=['top', 'bottom'], required=True)
    parser.add_argument('--timer', action='store_true', help='resize from the widget itself instead of a click')
    parser.add_argument('--repeat', type=int, default=3)
    parser.add_argument('--app')
    parser.add_argument('--no-launch', action='store_true')
    parser.add_argument('--output', type=Path, default=ROOT / '.build/widget-v013-anchors')
    args = parser.parse_args()
    work = args.output.expanduser().resolve()
    fixtures = work / 'fixtures'
    fixtures.mkdir(parents=True, exist_ok=True)
    for old in fixtures.glob('*'):
        old.unlink()
    (fixtures / 'probe.html').write_text(probe(args.anchor, args.timer))
    for name, source in [('click', CLICK), ('scroll', SCROLL), ('screen', SCREEN)]:
        (work / (name + '.swift')).write_text(source)
        subprocess.run(['xcrun', 'swiftc', str(work / (name + '.swift')), '-o', str(work / name)], check=True, capture_output=True)
    points = [int(v) for v in subprocess.check_output([str(work / 'screen')], text=True).split()]
    if not args.no_launch:
        app = find_app(args.app)
        binary = str(app / 'Contents/MacOS/Telegram')
        subprocess.run(['osascript', '-e', 'tell application id "uz.keepcoder.Telegram" to quit'], capture_output=True)
        deadline = time.time() + 15
        while subprocess.run(['pgrep', '-f', binary], capture_output=True).returncode == 0:
            if time.time() > deadline:
                raise RuntimeError('Debug Telegram did not quit')
            time.sleep(0.25)
        subprocess.run(['/usr/bin/open', '-n', str(app), '--args', '-PerfLab', 'chat-navigation', '-PerfLabLabel', 'widget-v013-anchors',
                        '-PerfLabOutput', str(work / 'reports'), '-PerfLabSynthetic', '40', '-PerfLabSyntheticWidgets', str(fixtures),
                        '-PerfLabWidgetEvery', '30', '-PerfLabSyntheticTitle', 'Widget anchors', '-PerfLabScenarios', 'manual',
                        '-PerfLabStartDelay', '1', '-PerfLabOpenWait', '2'], check=True)
    column_x, _, (top, bottom) = find(work, points, 60)
    subprocess.run([str(work / 'scroll'), str(column_x), str((top + bottom) / 2), str(points[1] / 2 - (top + bottom) / 2)], check=True)
    time.sleep(1.5)
    column_x, _, _ = find(work, points)
    failures = 0
    for run in range(args.repeat):
        if args.timer:
            results = [('timer', measure(work, column_x, points, None, seconds=4))]
        else:
            results = []
            for name, index in [('add', 0), ('remove', 1)]:
                column_x, buttons, _ = find(work, points)
                results.append((name, measure(work, column_x, points, buttons[index])))
        for name, frames in results:
            still, positions, missing, resized = verdict(frames, args.anchor)
            ok = still and resized
            failures += 0 if ok else 1
            print('%s %s run %d: %d frames, %s edge %s, %d frame(s) without it, bubble %s' % (
                'PASS' if ok else 'FAIL', name, run + 1, len(frames), args.anchor,
                'still' if still else 'moved (%d positions)' % positions, missing, 'resized' if resized else 'did not resize'))
    sys.exit(1 if failures else 0)


if __name__ == '__main__':
    main()
