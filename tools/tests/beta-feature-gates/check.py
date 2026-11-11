from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[3]
voice = (root / 'packages/ChatUI/Sources/ChatUI/ChatVoiceTranscription.swift').read_text()
start = voice.index('    static var isLiveDictationSupported: Bool {')
end = voice.index('    static func canTranscribeClip(', start)
availability = voice[start:end]
assert 'Self.canTranscribeClip(isSecretChat: isSecretChat)' in voice
source = '''import Foundation
''' + '\nenum VoiceAvailability {\n' + availability + '''\n}
#if EXPECT_ENABLED
precondition(VoiceAvailability.isLiveDictationSupported)
#else
precondition(!VoiceAvailability.isLiveDictationSupported)
#endif
'''
with tempfile.TemporaryDirectory(prefix='beta-feature-gates-') as temporary:
    directory = Path(temporary)
    path = directory / 'main.swift'
    path.write_text(source)
    for name, flags in [('debug', ['DEBUG', 'EXPECT_ENABLED']), ('release', ['EXPECT_ENABLED']), ('beta', ['BETA', 'EXPECT_ENABLED']), ('debug-beta', ['DEBUG', 'BETA', 'EXPECT_ENABLED'])]:
        binary = directory / name
        command = ['swiftc', '-module-cache-path', str(directory / 'cache'), str(path), '-o', str(binary)]
        for flag in flags:
            command.extend(['-D', flag])
        subprocess.run(command, check=True)
        subprocess.run([str(binary)], check=True)
        print(f'{name}: passed', flush=True)
