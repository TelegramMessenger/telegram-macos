import Foundation
import XCTest
import InAppSettings
import InputDataUI
@testable import SettingsUI

final class SettingsSearchRegistryTests: XCTestCase {
    private let environment = SettingsSearchEnvironment()

    override func setUp() {
        var hooks = FeatureNavigationHooks.shared
        hooks.fullExportRowTitle = { "Export Telegram Data" }
        FeatureNavigationHooks.install(hooks)
    }

    private func allEntries() -> [(String, [(id: SettingsSearchableItemId, title: String, alternate: [String], breadcrumbs: [String])])] {
        func entries<T: SettingsSearchTag>(_ type: T.Type) -> (String, [(id: SettingsSearchableItemId, title: String, alternate: [String], breadcrumbs: [String])]) {
            return ("\(T.self)", searchEntries(type, environment: environment).map { ($0.id, $0.title, $0.alternate, $0.breadcrumbs) })
        }
        return [
            entries(GeneralSettingsEntryTag.self),
            entries(PowerSavingSearchTag.self),
            entries(SettingsDataAndStorageTag.self),
            entries(PrivacySearchTag.self),
            entries(AppearanceSearchTag.self),
            entries(NotificationSearchTag.self),
            entries(StickersSearchTag.self),
            entries(ProfileSearchTag.self),
            entries(ProxySearchTag.self),
            entries(LanguageSearchTag.self),
            entries(SupportSearchTag.self),
            entries(FaqSearchTag.self),
            entries(SettingsRootSearchTag.self)
        ]
    }

    func testEveryEntryHasATitle() {
        for (name, entries) in allEntries() {
            XCTAssertFalse(entries.isEmpty, "\(name): no entries")
            for entry in entries {
                XCTAssertFalse(entry.title.trimmingCharacters(in: .whitespaces).isEmpty, "\(name) \(entry.id): empty title")
            }
        }
    }

    func testItemIdsAreUniqueAcrossAllSections() {
        var seen: [SettingsSearchableItemId: String] = [:]
        for (name, entries) in allEntries() {
            for entry in entries {
                if let other = seen[entry.id] {
                    XCTFail("\(entry.id) used by \(other) and \(name)")
                }
                seen[entry.id] = name
            }
        }
    }

    func testEveryEntryIsFoundByItsOwnTitle() {
        for (name, entries) in allEntries() {
            for entry in entries {
                XCTAssertTrue(settingsSearchMatches(title: entry.title, alternate: entry.alternate, breadcrumbs: entry.breadcrumbs, query: entry.title), "\(name): \"\(entry.title)\" not found by its own title")
            }
        }
    }

    func testCallSettingsIsIndexed() {
        let ids = searchEntries(GeneralSettingsEntryTag.self, environment: environment).map { $0.id }
        XCTAssertTrue(ids.contains(.general(GeneralSettingsEntryTag.callSettings.rawValue)))
    }

    func testRecentItemIdsRoundTrip() {
        for (name, entries) in allEntries() {
            for entry in entries {
                XCTAssertEqual(SettingsSearchableItemId(index: entry.id.index), entry.id, "\(name) \(entry.id): id does not round trip")
            }
        }
    }

    func testConditionalEntriesAreHiddenWhenTheirScreenHidesThem() {
        let hidden = SettingsSearchEnvironment(
            privacySettings: nil,
            canAddAccount: false,
            hasSocksProxy: false,
            hasMultipleAccounts: false,
            predictEmojiVisible: false,
            canAdjustSensitiveContent: false,
            passkeysAvailable: false,
            loginEmailAvailable: false,
            hasWebSessions: false,
            secretChatWebPreviewAvailable: false,
            chatBackgroundAvailable: false,
            dockIconAvailable: false,
            liquidGlassAvailable: false,
            premiumAvailable: false,
            starsAvailable: false,
            passportAvailable: false
        )
        let visible = SettingsSearchEnvironment()

        func ids<T: SettingsSearchTag>(_ type: T.Type, _ environment: SettingsSearchEnvironment) -> Set<SettingsSearchableItemId> {
            return Set(searchEntries(type, environment: environment).map { $0.id })
        }

        let conditional: [SettingsSearchableItemId] = [
            .general(GeneralSettingsEntryTag.predictEmoji.rawValue),
            .data(SettingsDataAndStorageTag.sensitiveContent.rawValue),
            .privacy(PrivacySearchTag.passkeys.rawValue),
            .privacy(PrivacySearchTag.loginEmail.rawValue),
            .privacy(PrivacySearchTag.webSessions.rawValue),
            .privacy(PrivacySearchTag.secretChatWebPreview.rawValue),
            .privacy(PrivacySearchTag.sensitiveContent.rawValue),
            .appearance(AppearanceSearchTag.chatBackground.rawValue),
            .appearance(AppearanceSearchTag.dockIcon.rawValue),
            .general(100 + PowerSavingSearchTag.liquidGlass.rawValue),
            .settings(SettingsRootSearchTag.passport.rawValue),
            .settings(SettingsRootSearchTag.premium.rawValue),
            .settings(SettingsRootSearchTag.business.rawValue),
            .settings(SettingsRootSearchTag.sendGift.rawValue),
            .settings(SettingsRootSearchTag.stars.rawValue),
            .profile(ProfileSearchTag.addAccount.rawValue),
            .proxy(ProxySearchTag.useForCalls.rawValue)
        ]

        var visibleIds = Set<SettingsSearchableItemId>()
        var hiddenIds = Set<SettingsSearchableItemId>()
        for (environment, target) in [(visible, 0), (hidden, 1)] {
            var all = Set<SettingsSearchableItemId>()
            all.formUnion(ids(GeneralSettingsEntryTag.self, environment))
            all.formUnion(ids(SettingsDataAndStorageTag.self, environment))
            all.formUnion(ids(PrivacySearchTag.self, environment))
            all.formUnion(ids(AppearanceSearchTag.self, environment))
            all.formUnion(ids(PowerSavingSearchTag.self, environment))
            all.formUnion(ids(SettingsRootSearchTag.self, environment))
            all.formUnion(ids(ProfileSearchTag.self, environment))
            all.formUnion(ids(ProxySearchTag.self, environment))
            all.formUnion(ids(NotificationSearchTag.self, environment))
            if target == 0 {
                visibleIds = all
            } else {
                hiddenIds = all
            }
        }

        for id in conditional {
            XCTAssertTrue(visibleIds.contains(id), "\(id) should be searchable when its row is shown")
            XCTAssertFalse(hiddenIds.contains(id), "\(id) should not be searchable when its row is hidden")
        }
        XCTAssertFalse(hiddenIds.contains(.notifications(23)), "All Accounts should be hidden with a single account")
        XCTAssertTrue(visibleIds.contains(.notifications(23)))
    }
}
