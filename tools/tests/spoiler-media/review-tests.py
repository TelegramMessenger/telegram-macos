from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[3]
source = (root/'packages/ChatUI/Sources/ChatUI/ChatInteractiveContentView.swift').read_text()
line = next(line.strip() for line in source.splitlines() if 'let bypassSharedPreviewCache =' in line)
fixture = '''import Foundation
struct Parent { var containsSecretMedia = false }
class TelegramMediaImage {}
func bypass(_ parent: Parent?, _ isSensitive: Bool, _ isSpoiler: Bool, _ media: Any) -> Bool {
__POLICY__
return bypassSharedPreviewCache
}
let image = TelegramMediaImage()
let cases: [(String, Bool, Bool)] = [
("real spoiler photo bypasses shared sharp cache", bypass(Parent(), false, true, image), true),
("revealed photo uses ordinary cache", bypass(Parent(), false, false, image), false),
("send preview without parent keeps ordinary cache", bypass(nil, false, true, image), false),
("secret-media recycling retains original cache behavior", bypass(Parent(containsSecretMedia: true), false, true, image), false),
("concealed message video bypasses shared preview cache", bypass(Parent(), false, true, "video"), true),
("concealed sensitive photo bypasses shared preview cache", bypass(Parent(), true, true, image), true)]
var failures = 0
for (name, actual, expected) in cases { print("\\(actual == expected ? "PASS" : "FAIL"): \\(name)"); if actual != expected { failures += 1 } }
exit(failures == 0 ? 0 : 1)
'''.replace('__POLICY__', line)
assert source.count('!bypassSharedPreviewCache') == 2
assert 'signal: bypassSharedPreviewCache ? .single(nil)' in source
with tempfile.TemporaryDirectory() as temp:
    temp = Path(temp); (temp/'main.swift').write_text(fixture)
    subprocess.run(['swiftc', str(temp/'main.swift'), '-o', str(temp/'tests')], check=True)
    raise SystemExit(subprocess.run([str(temp/'tests')]).returncode)
