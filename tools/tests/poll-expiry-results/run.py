#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys

BASE = "246e3e957ae5cea1ecff6d7a6a6db3e47be69bb5"
CORE = "24638bc69bd083981b178dd1e7f921eebbf7fc46"
ITEM = "packages/ChatUI/Sources/ChatUI/ChatPollItem.swift"
CONTROLLER = "packages/ChatUI/Sources/ChatUI/ChatController.swift"
SIGNALS = "submodules/SSignalKit/SwiftSignalKit/Source/"
REPO = Path(__file__).resolve().parents[3]


def block(text, marker):
    start = text.index(marker)
    line_start = text.rfind("\n", 0, start) + 1
    prefix = text[line_start:start]
    if prefix.strip() in ("private", "fileprivate", "public"):
        start = line_start + len(prefix) - len(prefix.lstrip())
    brace = text.index("{", start)
    level = 1
    index = brace + 1
    state = "code"
    while level:
        pair = text[index:index + 2]
        char = text[index]
        if state == "line":
            if char == "\n":
                state = "code"
        elif state == "comment":
            if pair == "*/":
                state = "code"
                index += 1
        elif state == "string":
            if char == "\\":
                index += 1
            elif char == '"':
                state = "code"
        elif pair == "//":
            state = "line"
            index += 1
        elif pair == "/*":
            state = "comment"
            index += 1
        elif char == '"':
            state = "string"
        elif char == "{":
            level += 1
        elif char == "}":
            level -= 1
        index += 1
    return text[start:index]


def between(text, first, last):
    start = text.index(first)
    return text[start:text.index(last, start)]


def main():
    if not sys.flags.isolated:
        raise SystemExit("Use python3 -I run.py --source-root ... --output ...")
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=REPO)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    source = args.source_root.resolve()
    env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
    for key, folder in [("TMPDIR", "tmp"), ("CLANG_MODULE_CACHE_PATH", "clang-cache"), ("SWIFT_MODULECACHE_PATH", "swift-cache")]:
        path = output / folder
        path.mkdir(exist_ok=True)
        env[key] = str(path) + "/"

    def run(command, log=None):
        result = subprocess.run(command, cwd=REPO, env=env, capture_output=True, text=True, timeout=180)
        if log:
            (output / log).write_text(result.stdout + result.stderr)
        if result.returncode:
            raise RuntimeError(f"Command failed ({result.returncode}): {' '.join(map(str, command))}\n{result.stdout}\n{result.stderr}")
        return result.stdout

    def git(*arguments):
        return run(["git", "-C", str(REPO), *arguments])

    common = Path(git("rev-parse", "--git-common-dir").strip())
    if not common.is_absolute():
        common = (REPO / common).resolve()
    core_dir = common / "modules/submodules/telegram-ios"

    def core(path):
        return run(["git", f"--git-dir={core_dir}", "show", f"{CORE}:{path}"])

    signatures = {
        "submodules/TelegramCore/Sources/TelegramEngine/Messages/TelegramEngineMessages.swift": [
            "public func getMessagesLoadIfNecessary(_ messageIds: [MessageId], strategy: GetMessagesStrategy = .cloud(skipLocal: false)) -> Signal<GetMessagesResult, GetMessagesError>",
            "public func requestMessageSelectPollOption(messageId: MessageId, opaqueIdentifiers: [Data]) -> Signal<TelegramMediaPoll?, RequestMessageSelectPollOptionError>"
        ],
        "submodules/TelegramCore/Sources/Network/Network.swift": ["public func getApproximateRemoteTimestamp() -> Int32"],
        "submodules/TelegramCore/Sources/SyncCore/SyncCore_TelegramMediaPoll.swift": [
            "public let deadlineDate: Int32?", "public let deadlineTimeout: Int32?", "public let count: Int32?", "public let totalVoters: Int32?"
        ],
        "submodules/TelegramCore/Sources/TelegramEngine/Messages/LoadMessagesIfNecessary.swift": [
            "case cloud(skipLocal: Bool)", "case result([Message])", "case progress", "case privateChannel", "transaction.addMessages(storeMessages, location: .Random)"
        ],
        "submodules/TelegramCore/Sources/TelegramEngine/Messages/Polls.swift": ["case restrictedToSubscribers", 'error.errorDescription == "POLL_MEMBER_RESTRICTED"']
    }
    hashes = {}
    for path, required in signatures.items():
        text = core(path)
        for signature in required:
            if signature not in text:
                raise AssertionError(f"Pinned API mismatch: {path}: {signature}")
        hashes[path] = hashlib.sha256(text.encode()).hexdigest()

    signal_dir = output / "signals"
    signal_dir.mkdir(exist_ok=True)
    signal_paths = run(["git", f"--git-dir={core_dir}", "ls-tree", "-r", "--name-only", CORE, SIGNALS]).splitlines()
    signal_files = []
    for path in signal_paths:
        if path.endswith(".swift"):
            destination = signal_dir / Path(path).name
            destination.write_text(core(path))
            signal_files.append(str(destination))
    swiftc = run(["xcrun", "--find", "swiftc"]).strip()
    sdk = run(["xcrun", "--sdk", "macosx", "--show-sdk-path"]).strip()
    flags = ["-j1", "-swift-version", "5", "-sdk", sdk, "-module-cache-path", str(output / "swift-cache")]
    run([swiftc, *flags, "-emit-library", "-emit-module", "-module-name", "SwiftSignalKit", *signal_files, "-o", str(output / "libSwiftSignalKit.dylib"), "-emit-module-path", str(output / "SwiftSignalKit.swiftmodule")], "signals-compile.log")
    percent = git("show", f"{BASE}:packages/FoundationUtils/Sources/FoundationUtils/PercentCounter.swift")
    restriction = block(git("show", f"{BASE}:packages/ChatUI/Sources/ChatUI/ChatMessageMenuItems.swift"), "public func pollVoteRestrictionText")
    template = Path(__file__).with_name("RuntimeTests.swift.in").read_text()
    results = {}
    for name in ["fixed", "baseline"]:
        item = (source / ITEM).read_text() if name == "fixed" else git("show", f"{BASE}:{ITEM}")
        controller = (source / CONTROLLER).read_text() if name == "fixed" else git("show", f"{BASE}:{CONTROLLER}")
        fixed = "func pollDeadlineTimestamp" in item
        if name == "fixed" and not fixed:
            raise AssertionError("Production source root does not contain runtime fix")
        helpers = block(item, "public func isPollEffectivelyClosed")
        if fixed:
            for marker in ["func pollDeadlineTimestamp", "func isPollVotingClosed", "func visiblePollVoteCounts", "func refreshPollMessage", "func pollVoteErrorText", "func pollNeedsResultsRefresh", "struct PollRefreshState"]:
                helpers += "\n" + block(item, marker)
        properties = "\n".join(block(item, marker) for marker in ["public var isClosed", "public var showResultsIn", "public var deadlineEndDate", "private var canInvokeVote", "public var actionButtonIsEnabled", "fileprivate var canAddOption"])
        if fixed:
            properties += "\n" + block(item, "fileprivate var isVotingClosed")
        aggregate = between(item, "        let voteCounts =" if fixed else "        var votes:[Int]", "            let nameFont:")
        aggregate += "            output.append(Aggregate(percent: percent == nil ? nil : realPercent, count: percent == nil ? nil : votedCount, peers: optionRecentVoters))\n        }\n        return output\n"
        owner = item[item.index("private final class PollView"):]
        owner_methods = "\n".join(block(owner, marker) for marker in ["deinit", "override func viewWillMove", "override func viewDidMoveToWindow", "private func updateDeadlineTimer", "private func updateDeadline()"] if marker in owner)
        owner_fields = "\n".join(line for line in owner.splitlines() if any(token in line for token in ["private var resultsInTimer:", "private let refreshDisposable", "private var refreshState", "private var votingClosed"]))
        owner_bind = "self.currentItem = item\n"
        if fixed:
            owner_bind = between(owner, "        self.currentItem = item", "        if item.showResultsIn")
            owner_bind += "updateDeadlineTimer()\nupdateDeadline()\n"
        error_body = between(controller, "                    let errorText =" if fixed else "                    switch error {\n                    case .generic:", "\n                }), forKey: messageId)")
        if fixed:
            preflight = between(controller, "                let signal = context.account.postbox.transaction { transaction -> Message? in", "                self.selectMessagePollOptionDisposables.set(signal.start")
        else:
            preflight = between(controller, "            let signal:Signal<TelegramMediaPoll?, RequestMessageSelectPollOptionError>", "                self.selectMessagePollOptionDisposables.set(signal.start")
            preflight += "self.selectMessagePollOptionDisposables.set(signal.start(), forKey: messageId)\n}\n"
        generated = template
        replacements = {
            "HELPERS": helpers, "PERCENT": percent, "RESTRICTION": restriction, "PROPERTIES": properties, "AGGREGATE": aggregate,
            "OWNER_FIELDS": owner_fields, "OWNER_METHODS": owner_methods, "OWNER_BIND": owner_bind,
            "PREFLIGHT": preflight, "ERROR_BODY": error_body,
            "PREFLIGHT_START": "selectMessagePollOptionDisposables.set(signal.start(), forKey: messageId)" if fixed else "",
            "OWNER_TICK": "updateDeadline()" if fixed else "currentItem?.copyAndUpdate(animated: true)",
            "OWNER_ATTEMPTS": "refreshState.attempts" if fixed else "0",
            "OWNER_EXHAUST": "for time in [1_000_000_000.0, 1_000_000_005.0, 1_000_000_010.0] { if let generation = refreshState.begin(now: time) { _ = refreshState.finish(generation) } }; updateDeadlineTimer()" if fixed else ""
        }
        for token, value in replacements.items():
            generated = generated.replace("@@" + token + "@@", value)
        if "@@" in generated:
            raise AssertionError("Unexpanded template marker")
        generated_path = output / f"{name}.swift"
        generated_path.write_text(generated)
        executable = output / name
        run([swiftc, *flags, *( ["-D", "FIXED"] if fixed else []), "-I", str(output), "-L", str(output), "-lSwiftSignalKit", "-Xlinker", "-rpath", "-Xlinker", str(output), str(generated_path), "-o", str(executable)], f"{name}-compile.log")
        execution = subprocess.run([str(executable)], cwd=REPO, env=env, capture_output=True, text=True, timeout=90)
        (output / f"{name}-run.log").write_text(execution.stdout + execution.stderr)
        if execution.returncode != (0 if fixed else 1):
            raise AssertionError(f"Unexpected {name} result {execution.returncode}:\n{execution.stdout}\n{execution.stderr}")
        passed = execution.stdout.count("PASS ")
        failed = execution.stdout.count("FAIL ")
        if (fixed and failed) or (not fixed and failed < 3):
            raise AssertionError(f"Expected compiled behavioral baseline negatives: {passed}/{failed}")
        results[name] = {"passed": passed, "failed": failed, "exit": execution.returncode, "source_sha256": hashlib.sha256(item.encode()).hexdigest()}
        print(f"{name}: {passed} passed, {failed} failed")
    strings = (source / "Telegram-Mac/en.lproj/Localizable.strings").read_text(encoding="utf-16")
    accessor = (source / "packages/Localization/Sources/Localization/Localizable.swift").read_text()
    assert strings.count('"ChatPoll.VotingClosed" =') == 1
    assert accessor.count('static var chatPollVotingClosed:') == 1
    assert 'return L10n.tr("Localizable", "ChatPoll.VotingClosed")' in accessor
    (output / "results.json").write_text(json.dumps({"base": BASE, "core": CORE, "source_root": str(source), "authority_repo": str(REPO), "core_api_sha256": hashes, "results": results}, indent=2) + "\n")


if __name__ == "__main__":
    main()
