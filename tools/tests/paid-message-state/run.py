import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile

parser = argparse.ArgumentParser()
parser.add_argument("--baseline", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parents[3]


def read(name):
    path = f"packages/ChatUI/Sources/ChatUI/{name}.swift"
    if args.baseline:
        return subprocess.check_output(["git", "-C", str(root), "show", f"HEAD:{path}"], text=True)
    return (root / path).read_text()


def block(source, marker):
    start = source.index(marker)
    end = source.index("{", start) + 1
    depth = 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


state = read("ChatPresentationInterfaceState")
getter = block(state, "    public var sendPaidMessageStars:").replace("public ", "")
methods = []
for name in ["withUpdatedCachedData", "withUpdatedAlwaysPaidMessage", "withUpdatedSendPaidMessageStars", "updatedPeer"]:
    method = block(state, f"    public func {name}(").replace("public ", "")
    constructor = re.search(r"return ChatPresentationInterfaceState\(([^\n]+)\)", method).group(1)
    arguments = dict(re.findall(r"(\w+):\s*([^,]+)", constructor))
    reduced = ", ".join(f"{key}: {arguments[key]}" for key in ["peer", "cachedData", "alwaysPaidMessage", "sendPaidMessageStars"])
    signature = method[:method.index("{")]
    setup = "let peer = f(self.peer)\n" if name == "updatedPeer" else ""
    methods.append(signature + "{\n" + setup + "return ChatPresentationInterfaceState(" + reduced + ")\n}")

copies = re.findall(r"sendPaidMessageStars: (self\.\w+)", state)
assert len(copies) >= 60
copy_expressions = ", ".join("{ " + expression + " }" for expression in copies)
refresh_marker = "            if value.sendPaidMessageStars != oldValue.sendPaidMessageStars {"
input_view = read("ChatInputView")
refresh = block(input_view, refresh_marker) if refresh_marker in input_view else ""
interaction = read("ChatInterfaceInteraction")
update_start = interaction.index("        let oldValue = self.presentation\n", interaction.index("    public func update(animated:Bool = true"))
update_end = interaction.index("\n", interaction.index("        _ = _presentation.swap(", update_start)) + 1
update = interaction[update_start:update_end]
confirmation = read("ChatSendPaymentConfirmation")
price_guard_marker = "public func chatPaidMessagePriceIsCurrent("
price_guard = block(confirmation, price_guard_marker).replace("public ", "") if price_guard_marker in confirmation else ""
fixture = Path(__file__).with_name("PaidMessageStateTests.swift").read_text()
fixture = fixture.replace("__UPDATE__", update).replace("__PRICE_GUARD__", price_guard)
fixture = fixture.replace("__GETTER__", getter).replace("__METHODS__", "\n".join(methods))
fixture = fixture.replace("__COPIES__", copy_expressions).replace("__REFRESH__", refresh)
with tempfile.TemporaryDirectory(prefix="paid-message-state-") as directory:
    directory = Path(directory)
    (directory / "Package.swift").write_text('''// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "PaidMessageState", targets: [.testTarget(name: "PaidMessageStateTests", path: "Tests")])
''')
    (directory / "Tests").mkdir()
    (directory / "Tests/PaidMessageStateTests.swift").write_text(fixture)
    print(f"Testing {'HEAD' if args.baseline else 'working tree'} paid-message state and placeholder refresh", flush=True)
    environment = os.environ.copy()
    environment["CLANG_MODULE_CACHE_PATH"] = str(directory / "ModuleCache")
    environment["SWIFTPM_MODULECACHE_OVERRIDE"] = str(directory / "ModuleCache")
    raise SystemExit(subprocess.run(["swift", "test", "--package-path", str(directory), "--disable-sandbox", "--jobs", "2"], env=environment).returncode)
