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
def without_imports(source):
    return "\n".join(line for line in source.splitlines() if not line.startswith("import "))

adapter = without_imports((root / "Telegram-Mac/account/FocusNotificationMembership.swift").read_text())
notification_filter = without_imports((root / "packages/FocusFilterCore/Sources/FocusFilterInfrastructure/FocusNotificationFilter.swift").read_text())
resolver = without_imports((root / "Telegram-Mac/account/FocusNotificationResolver.swift").read_text())
core = sorted((root / "packages/FocusFilterCore/Sources/FocusFilterCore").glob("*.swift"))
fixture = Path(__file__).with_name("FocusNotificationMembershipTests.swift").read_text()
fixture = fixture.replace("__PEER_GROUP__", (postbox / "PeerGroup.swift").read_text().replace("import Foundation", ""))
fixture = fixture.replace("__SUMMARY_TYPES__", summaries).replace("__POSTBOX_PREDICATE__", predicate)
fixture = fixture.replace("__NOTIFICATION_SETTINGS__", notification_settings).replace("__CANONICAL_FOLDER_MAPPER__", mapper).replace("__LIVE_NOTIFICATION_ADAPTER__", adapter)

with tempfile.TemporaryDirectory(prefix="telegram-focus-notifications-") as directory:
    directory = Path(directory)
    source = directory / "Tests.swift"
    source.write_text(fixture + "\n" + notification_filter + "\n" + resolver)
    executable = directory / "tests"
    subprocess.run([
        "xcrun", "swiftc", "-parse-as-library", "-module-cache-path", str(directory / "ModuleCache"),
        *(str(path) for path in core),
        str(Path(__file__).with_name("FocusNotificationResolverTests.swift")),
        str(source), "-o", str(executable),
    ], check=True)
    raise SystemExit(subprocess.run([str(executable)]).returncode)
