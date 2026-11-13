import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[3]
BASE = '246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5'
APP = 'Telegram-Mac/app/MainViewController.swift'
BAR = 'packages/TGUIKit/Sources/TabBarView.swift'


def declaration(source, marker):
    assert source.count(marker) == 1, marker
    start = source.index(marker)
    opening = source.index('{', start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--source-root', type=Path, default=ROOT)
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    if not sys.flags.isolated:
        parser.error('Use python3 -I')
    if args.output:
        if args.output.exists() or any(p.is_symlink() for p in [args.output, *args.output.parents]):
            parser.error('--output must be new and have no symlink components')
    env = {k:v for k,v in os.environ.items() if not k.startswith('GIT_')}
    root = args.source_root.resolve()
    fixed = (root / APP).read_text()
    baseline = subprocess.check_output(['git','-C',str(root),'show',BASE+':'+APP],env=env,text=True)
    gesture = subprocess.check_output(['git','-C',str(root),'show',BASE+':'+BAR],env=env,text=True)
    chunks = {
        '__LAYOUT__': declaration(gesture, 'struct FloatingTabBarLayout {'),
        '__GESTURE__': declaration(gesture, 'private struct SelectionGesture {').replace('private struct', 'struct'),
        '__UPDATE__': declaration(gesture, 'func updateSelection(at point:'),
        '__END__': declaration(gesture, 'func endSelection(at point:'),
        '__END_REORDER__': declaration(gesture, 'private func endReorder(at point:').replace('private func', 'func'),
        '__FRAMES__': declaration(gesture, 'private func updateItemFrames(transition:').replace('private func', 'func'),
    }
    fixture = Path(__file__).with_name('BottomTabbarHoldPolicyTests.swift.in').read_text()
    for key,value in chunks.items():
        assert fixture.count(key) == 1
        fixture = fixture.replace(key,value)
    results = {}
    with tempfile.TemporaryDirectory(prefix='tabbar-hold-policy-') as temporary:
        temp=Path(temporary)
        (temp/'tmp').mkdir()
        output=args.output or temp/'results'
        output.mkdir(parents=True)
        env={**env,'TMPDIR':str(temp/'tmp')+'/','CLANG_MODULE_CACHE_PATH':str(temp/'cache')}
        for label, app in [('fixed',fixed),('baseline',baseline)]:
            values=re.findall(r'tabController\.allowsTabReordering = (true|false)',app)
            assert len(values)==1
            swift=fixture.replace('__APP_POLICY__',values[0])
            source=temp/(label+'.swift')
            source.write_text(swift)
            binary=temp/label
            compiled=subprocess.run(['xcrun','swiftc','-j','2','-module-cache-path',str(temp/'cache'),str(source),'-o',str(binary)],env=env,cwd=temp,capture_output=True,text=True)
            (output/(label+'-compile.log')).write_text(compiled.stdout+compiled.stderr)
            if compiled.returncode:
                print(compiled.stdout+compiled.stderr)
                raise SystemExit(2)
            tested=subprocess.run([str(binary)],env=env,cwd=temp,capture_output=True,text=True)
            (output/(label+'-test.log')).write_text(tested.stdout+tested.stderr)
            report=json.loads(tested.stdout)
            assert (report['cases'],report['scenarios'],report['assertions'])==(6,46,236)
            assert tested.returncode==(0 if label=='fixed' else 1)
            assert report['failures']==(0 if label=='fixed' else 138)
            results[label]={**report,'compile_exit':0,'test_exit':tested.returncode,'app_source_sha256':hashlib.sha256(app.encode()).hexdigest(),'gesture_source_sha256':hashlib.sha256(gesture.encode()).hexdigest(),'gesture_revision':BASE,'generated_sha256':hashlib.sha256(swift.encode()).hexdigest()}
            print(json.dumps({'variant':label,**report}),flush=True)
        (output/'results.json').write_text(json.dumps(results,indent=2)+'\n')


if __name__=='__main__':
    main()
