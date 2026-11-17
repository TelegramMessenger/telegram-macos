import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[3])
parser.add_argument('--reference', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--compiler-lock', type=Path, required=True)
parser.add_argument('--baseline')
parser.add_argument('--shared-only', action='store_true')
parser.add_argument('--accessibility', action='store_true')
args = parser.parse_args()
args.output.mkdir(exist_ok=False, parents=True)

def read(relative):
    if args.baseline:
        return subprocess.check_output(['git', '-C', str(args.root), 'show', args.baseline + ':' + relative]).decode()
    return (args.root / relative).read_text()

def block(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

def clean(source):
    return '\n'.join(line for line in source.splitlines() if not line.startswith('import ')).replace('public ', '').replace('open ', '').replace('fileprivate ', '').replace('private ', '')

month = read('packages/CalendarUI/Sources/CalendarUI/CalendarMonthController.swift')
controller = read('packages/CalendarUI/Sources/CalendarUI/CalendarController.swift')
fixtures = Path(__file__).parent
fixture = (fixtures / 'Boundary.swift.in').read_text()
if args.shared_only or args.baseline:
    fixture = fixture[:fixture.index('var emitted: [Date] = []')] + (fixtures / 'Baseline.swift.in').read_text()
month_controller = month[month.index('open class CalendarMonthController:'):month.index('    open override func getCenterBarViewOnce()')]
for marker in ['    open var isNextEnabled:', '    open var isPrevEnabled:', '    open override func viewDidLoad()', '    open override func viewWillAppear(', '    open override func viewDidAppear(', '    open override func viewWillDisappear(']:
    if marker in month[month.index('open class CalendarMonthController:'):]:
        month_controller += '\n' + block(month[month.index('open class CalendarMonthController:'):], marker)
month_controller += '\n}'
if args.baseline:
    navigation = ''
    activate = '''func activate(day: Int) -> Bool {
        guard userInteractionEnabled, let month, month.isDayEnabled(day) else { return false }
        let current = day
        let callback: (Any) -> Void = ''' + block(month, 'day.set(handler:').split('handler: ', 1)[1] + '''
        callback(0)
        return true
    }'''
    focused = 'func activateFocusedDay() {}'
else:
    navigation = read('packages/CalendarUI/Sources/CalendarUI/CalendarDayNavigation.swift')
    activate = block(month, '    fileprivate func activate(day:')
    focused = block(month, '    func activateFocusedDay()')
for token, source in {
    '__INTERACTIONS__': block(month, 'public struct CalendarMonthInteractions'),
    '__MONTH__': block(month, 'public final class CalendarMonthStruct'),
    '__NAVIGATION__': navigation,
    '__MONTH_CONTROLLER__': month_controller,
    '__CONTROLLER__': controller,
    '__ACTIVATE__': activate,
    '__ACTIVATE_FOCUSED__': focused,
}.items():
    fixture = fixture.replace(token, clean(source).replace('Date()', 'clockNow'))
if args.accessibility:
    assert not args.baseline
    fixture = (fixtures / 'Accessibility.swift.in').read_text()
    for token, source in {
        '__MONTH__': block(month, 'public final class CalendarMonthStruct'),
        '__BUTTON__': block(month, 'private final class CalendarDayButton'),
        '__VIEW__': block(month, 'open class CalendarMonthView'),
    }.items():
        fixture = fixture.replace(token, clean(source))
(args.output / 'main.swift').write_text(fixture)
(args.output / 'extraction.json').write_text(json.dumps({'baseline': args.baseline, 'shared_only': args.shared_only, 'source_sha256': {'CalendarMonthController.swift': hashlib.sha256(month.encode()).hexdigest(), 'CalendarController.swift': hashlib.sha256(controller.encode()).hexdigest(), 'CalendarDayNavigation.swift': hashlib.sha256(navigation.encode()).hexdigest()}, 'boundary': 'Actual controller/ordinary selection/activation method bodies with controlled navigation/view dependencies; not full window/VoiceOver runtime.'}, indent=2)+'\n')
calendar_utils = args.reference / 'packages/CalendarUtils/Sources/CalendarUtils'
modulemap = args.output / 'module.modulemap'
modulemap.write_text('module CalendarUtils { header ' + json.dumps(str(calendar_utils/'CalendarUtils.h')) + ' export * }\n')
sdk = subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
clang = subprocess.check_output(['xcrun','--find','clang'],text=True).strip()
swiftc = subprocess.check_output(['xcrun','--find','swiftc'],text=True).strip()

def free():
    value=os.statvfs(args.output)
    return value.f_bavail*value.f_frsize

def run(name, command):
    (args.output/(name+'-command.json')).write_text(json.dumps(command,indent=2)+'\n')
    if free()<8*1024**3: raise RuntimeError('Insufficient disk before compiler')
    minimum=free(); start=time.monotonic(); abort=False
    with (args.output/(name+'.log')).open('wb') as log:
        process=subprocess.Popen(command, cwd=args.root, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        while process.poll() is None:
            minimum=min(minimum,free())
            if minimum<4*1024**3:
                abort=True; os.killpg(process.pid,signal.SIGTERM); break
            time.sleep(0.25)
        try: code=process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid,signal.SIGKILL); code=process.wait()
    result={'exit':code,'disk_abort':abort,'minimum_free_bytes':minimum,'seconds':time.monotonic()-start}
    (args.output/(name+'-result.json')).write_text(json.dumps(result,indent=2)+'\n')
    print(name,json.dumps(result))
    if code: print((args.output/(name+'.log')).read_text()[-14000:])
    return code

with args.compiler_lock.open('a') as lock:
    fcntl.flock(lock,fcntl.LOCK_EX)
    code=run('clang',[clang,'-fobjc-arc','-fmodules','-isysroot',sdk,'-target','arm64-apple-macos12.0','-fmodules-cache-path='+str(args.output/'clang-cache'),'-c',str(calendar_utils/'CalendarUtils.m'),'-o',str(args.output/'CalendarUtils.o')])
    if not code:
        code=run('compile',[swiftc,'-j1','-sdk',sdk,'-target','arm64-apple-macos12.0','-module-cache-path',str(args.output/'swift-cache'),'-Xcc','-fmodule-map-file='+str(modulemap),str(args.output/'main.swift'),str(args.output/'CalendarUtils.o'),'-o',str(args.output/'tests')])
    if not code:
        code=run('tests',[str(args.output/'tests')])
raise SystemExit(code)
