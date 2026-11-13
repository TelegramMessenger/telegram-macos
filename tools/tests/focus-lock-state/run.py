import argparse
import pathlib
import shutil
import subprocess
import tempfile


ROOT = pathlib.Path(__file__).resolve().parents[3]
SOURCE = ROOT / "Telegram-Mac/account/SharedNotificationManager.swift"


def declaration(source, marker):
    start = source.index(marker)
    opening = source.index("{", start)
    depth = 1
    index = opening + 1
    while depth:
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
        index += 1
    return source[start:index].replace("private(set) ", "").replace("private ", "")


def harness(source):
    types = [declaration(source, marker) for marker in (
        "struct LockNotificationsData", "private struct PasscodeLockRequest"
    )]
    methods = [declaration(source, marker) for marker in (
        "private(set) var _lockedValue:",
        "private func publishCatalogAccess()",
        "private func updateLocked(",
        "private func beginPasscodeLockRequest()",
        "private func isCurrentPasscodeLockRequest(",
        "private func receivePasscodeLockRequest(",
        "private func completePasscodeLockRequest(",
        "private func revokeCatalogAccess()",
    )]
    return "\n".join([
        "import Foundation",
        *types,
        """
struct Signal<Value> {
    static func single(_ value: Value) -> Self { Self() }
}
final class Promise<Value> {
    func set(_ signal: Signal<Value>) {}
}
enum PasscodeSession {
    static func setApplicationAvailable(_ available: Bool) {}
}
final class LockStateHarness {
    let screenLocked = Promise<LockNotificationsData>()
    var didUpdateLocked: ((LockNotificationsData) -> Void)?
    var passcodeLockRequestId = UUID()
    var isPasscodeLockRequestPending = false
    var hasVerifiedUnlock: Bool
    let catalogAccessUpdated: (Bool) -> Void

    init(initialUnlockVerified: Bool, catalogAccessUpdated: @escaping (Bool) -> Void) {
        self.hasVerifiedUnlock = initialUnlockVerified
        self.catalogAccessUpdated = catalogAccessUpdated
        catalogAccessUpdated(false)
        publishCatalogAccess()
    }
""",
        *methods,
        "}",
    ])


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--swiftc", default=shutil.which("swiftc"))
    args = parser.parse_args()
    if not args.swiftc:
        parser.error("swiftc is required")
    with tempfile.TemporaryDirectory(prefix="focus-lock-state-") as directory:
        directory = pathlib.Path(directory)
        production = directory / "LockState.swift"
        production.write_text(harness(SOURCE.read_text()))
        tests = directory / "main.swift"
        tests.write_text(pathlib.Path(__file__).with_name("FocusLockStateTests.swift").read_text())
        executable = directory / "focus-lock-state"
        subprocess.run([args.swiftc, str(production), str(tests), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True)


if __name__ == "__main__":
    main()
