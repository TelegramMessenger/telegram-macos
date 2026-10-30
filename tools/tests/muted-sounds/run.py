from pathlib import Path
import subprocess
import tempfile
root=Path(__file__).resolve().parents[3]
source=(root/'packages/ChatUI/Sources/ChatUI/SoundEffects.swift').read_text()
source=source.replace('#if SHARE\nimport TelegramThemeShare\n#else\nimport TelegramTheme\n#endif','')
if '--baseline' in __import__('sys').argv:
    source=subprocess.check_output(['git','show','e18830989542a063dd66c5bdc4dbe6a70cbbd175:packages/ChatUI/Sources/ChatUI/SoundEffects.swift'],cwd=root,text=True).replace('#if SHARE\nimport TelegramThemeShare\n#else\nimport TelegramTheme\n#endif','')
if 'func playSoundEffectBeep()' not in source:
    source += '\nfunc playSoundEffectBeep() { NSSound.beep() }\n'
fixture=(Path(__file__).parent/'SoundTests.swift').read_text()
with tempfile.TemporaryDirectory(prefix='muted-sounds-') as scratch:
    path=Path(scratch)/'main.swift'
    if '--native' in __import__('sys').argv:
        fakeSound=fixture[:fixture.index('var device:')]
        native='''\nfor _ in 0..<10 { playSoundEffect(.sent) }
let suppressed = !soundEffectOutputIsAudible()
print("Real Core Audio gate suppresses playback: \(suppressed)")
print("NSSound allocations: \(NSSound.created); play calls: \(NSSound.played)")
exit(suppressed && NSSound.created == 0 && NSSound.played == 0 ? 0 : 1)
'''
        path.write_text(source+'\n'+fakeSound+native)
    else:
        path.write_text('import CoreAudio\n'+source.replace('AudioObjectGetPropertyData(', 'readTestProperty(')+'\n'+fixture)
    executable=Path(scratch)/'tests'
    subprocess.run(['swiftc',str(path),'-o',str(executable)],check=True)
    raise SystemExit(subprocess.run([str(executable)]).returncode)
