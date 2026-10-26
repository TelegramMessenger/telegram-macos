import argparse
from pathlib import Path
import subprocess
import tempfile


root = Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument("--postbox-source", type=Path, default=root / "submodules/telegram-ios/submodules/Postbox/Sources")
args = parser.parse_args()
postbox = args.postbox_source
chat_list = (postbox / "ChatListView.swift").read_text()
predicate = chat_list[chat_list.index("public struct ChatListFilterPredicate {"):chat_list.index("\nstruct MutableChatListAdditionalItemEntry:")]
seed = (postbox / "SeedConfiguration.swift").read_text()
summaries = seed[seed.index("public struct ChatListMessageTagSummaryResultComponent {"):seed.index("\nfunc resolveChatListMessageTagSummaryResultCalculation(")]
notification_settings = (postbox / "PeerNotificationSettings.swift").read_text()
notification_settings = notification_settings[notification_settings.index("public final class PostboxGlobalNotificationSettings {"):]
mapper = (root / "packages/TelegramUtils/Sources/TelegramUtils/ChatListFilterPredicate.swift").read_text()
mapper = mapper[mapper.index("public func chatListFilterPredicate("):mapper.index("\npublic enum ChatListControllerLocation")]
adapter = (root / "Telegram-Mac/account/FocusFilterCoordinator.swift").read_text()
adapter = adapter[adapter.index("private func focusNotificationFolderIncludes("):adapter.index("\nfunc focusNotificationPolicy(account:")]
fixture = Path(__file__).with_name("FocusNotificationMembershipTests.swift").read_text()
fixture = fixture.replace("__PEER_GROUP__", (postbox / "PeerGroup.swift").read_text().replace("import Foundation", ""))
fixture = fixture.replace("__SUMMARY_TYPES__", summaries).replace("__POSTBOX_PREDICATE__", predicate)
fixture = fixture.replace("__NOTIFICATION_SETTINGS__", notification_settings).replace("__CANONICAL_FOLDER_MAPPER__", mapper).replace("__LIVE_NOTIFICATION_ADAPTER__", adapter)

with tempfile.TemporaryDirectory(prefix="telegram-focus-notifications-") as directory:
    directory = Path(directory)
    source = directory / "Tests.swift"
    source.write_text(fixture)
    executable = directory / "tests"
    subprocess.run([
        "xcrun", "swiftc", "-parse-as-library", "-module-cache-path", str(directory / "ModuleCache"),
        str(root / "packages/FocusFilterCore/Sources/FocusFilterCore/FocusFilterPolicy.swift"),
        str(source), "-o", str(executable),
    ], check=True)
    raise SystemExit(subprocess.run([str(executable)]).returncode)
