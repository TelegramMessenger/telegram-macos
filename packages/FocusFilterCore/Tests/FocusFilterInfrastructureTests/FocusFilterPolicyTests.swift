import Foundation
import XCTest
import FocusFilterCore
@testable import FocusFilterInfrastructure

final class FocusFilterPolicyTests: XCTestCase {
    private let workAccount: Int64 = 10
    private let personalAccount: Int64 = 100
    private let groupPeer: Int64 = 0x10000002a
    private let channelPeer: Int64 = 0x20000002a





    func testEachEffectFiltersOnlyItsSelectedSurface() {
        let cases: [(FocusFilterEffect, Bool, Bool)] = [
            (.notifications, false, true),
            (.chatList, true, false),
            (.both, false, false)
        ]
        for (effect, notificationsAllowed, chatListAllowed) in cases {
            let policy = FocusFilterPolicy(configuration: .init(accountIds: [workAccount], effect: effect))
            XCTAssertEqual(policy.includes(accountId: workAccount, peerId: groupPeer, effect: .notifications), notificationsAllowed, "\(effect)")
            XCTAssertEqual(policy.includes(accountId: workAccount, peerId: groupPeer, effect: .chatList), chatListAllowed, "\(effect)")
            XCTAssertEqual(notificationFilter(policy).predicate.evaluate(with: notificationCriteria(FocusChatIdentifier(accountId: workAccount, peerId: groupPeer))), notificationsAllowed, "\(effect)")
        }
    }



    func testFolderChangesUseTheSameSystemPredicateAndCurrentMembership() {
        let folder = FocusFolderIdentifier(accountId: workAccount, folderId: 7)
        for mode in [FocusFilterMode.allowSelected, .excludeSelected] {
            let configuration = FocusFilterConfiguration(accountIds: [workAccount], folderIds: [folder], mode: mode, effect: .both)
            let before = FocusFilterPolicy(configuration: configuration, catalog: .init(folders: [.init(id: folder, title: "Projects", peerIds: [groupPeer])]))
            let after = FocusFilterPolicy(configuration: configuration, catalog: .init(folders: [.init(id: folder, title: "Renamed", peerIds: [channelPeer])]))
            let predicate = notificationFilter(before).predicate

            for peer in [groupPeer, channelPeer, 42] {
                let chat = FocusChatIdentifier(accountId: workAccount, peerId: peer)
                XCTAssertEqual(predicate.evaluate(with: notificationFilter(before).criteria(for: chat, catalog: before.catalog)), before.includes(accountId: workAccount, peerId: peer, effect: .notifications))
                XCTAssertEqual(predicate.evaluate(with: notificationFilter(after).criteria(for: chat, catalog: after.catalog)), after.includes(accountId: workAccount, peerId: peer, effect: .notifications))
            }
            XCTAssertNotEqual(before.includes(accountId: workAccount, peerId: groupPeer, effect: .chatList), after.includes(accountId: workAccount, peerId: groupPeer, effect: .chatList))
        }
    }

    func testDeletedFoldersAndLoggedOutAccountsCannotMatchAnotherAccount() {
        let oldAccount: Int64 = -100
        let newAccount: Int64 = -10
        let oldFolder = FocusFolderIdentifier(accountId: oldAccount, folderId: 9)
        let configuration = FocusFilterConfiguration(accountIds: [oldAccount], folderIds: [oldFolder], effect: .both)
        let before = FocusFilterPolicy(configuration: configuration, catalog: .init(
            accounts: [.init(id: oldAccount, title: "Old")],
            folders: [.init(id: oldFolder, title: "Old folder", peerIds: [groupPeer])]
        ))
        let after = FocusFilterPolicy(configuration: configuration, catalog: .init(
            accounts: [.init(id: newAccount, title: "New")],
            folders: [.init(id: .init(accountId: newAccount, folderId: 9), title: "New folder", peerIds: [groupPeer])]
        ))

        XCTAssertTrue(before.includes(accountId: oldAccount, peerId: groupPeer, effect: .chatList))
        XCTAssertFalse(after.includes(accountId: oldAccount, peerId: groupPeer, effect: .chatList))
        XCTAssertTrue(after.includes(accountId: newAccount, peerId: groupPeer, effect: .chatList))
        let oldChat = FocusChatIdentifier(accountId: oldAccount, peerId: groupPeer)
        let newChat = FocusChatIdentifier(accountId: newAccount, peerId: groupPeer)
        XCTAssertFalse(notificationFilter(before).predicate.evaluate(with: notificationFilter(after).criteria(for: oldChat, catalog: after.catalog)))
        XCTAssertTrue(notificationFilter(before).predicate.evaluate(with: notificationFilter(after).criteria(for: newChat, catalog: after.catalog)))
    }

    func testEmptySelectionAndResetHaveDistinctBehavior() {
        let chat = FocusChatIdentifier(accountId: workAccount, peerId: groupPeer)
        let allowNone = FocusFilterPolicy(configuration: .init(accountIds: [workAccount], effect: .both))
        let excludeNone = FocusFilterPolicy(configuration: .init(accountIds: [workAccount], mode: .excludeSelected, effect: .both))
        let reset = FocusFilterPolicy()

        for effect in [FocusFilterEffect.notifications, .chatList] {
            XCTAssertFalse(allowNone.includes(accountId: workAccount, peerId: groupPeer, effect: effect))
            XCTAssertTrue(excludeNone.includes(accountId: workAccount, peerId: groupPeer, effect: effect))
            XCTAssertTrue(reset.includes(accountId: workAccount, peerId: groupPeer, effect: effect))
            XCTAssertNil(reset.selection(accountId: workAccount, effect: effect))
        }
        XCTAssertFalse(notificationFilter(allowNone).predicate.evaluate(with: notificationCriteria(chat)))
        XCTAssertTrue(notificationFilter(excludeNone).predicate.evaluate(with: notificationCriteria(chat)))
        XCTAssertTrue(notificationFilter(reset).predicate.evaluate(with: notificationCriteria(chat)))
    }

    func testNotificationPredicateMatchesPolicyAcrossModesEffectsAndIdentifiers() {
        let accounts: [Int64] = [workAccount, personalAccount, -1, -10, Int64.min, Int64.max]
        let peers: [Int64] = [42, groupPeer, channelPeer, -42, Int64.min, Int64.max]
        let folder = FocusFolderIdentifier(accountId: personalAccount, folderId: Int32.max)
        let catalog = FocusFilterCatalog(folders: [.init(id: folder, title: "Folder", peerIds: [Int64.min, channelPeer])])

        for mode in [FocusFilterMode.allowSelected, .excludeSelected] {
            for effect in [FocusFilterEffect.notifications, .chatList, .both] {
                let policy = FocusFilterPolicy(configuration: .init(
                    accountIds: [workAccount, personalAccount, -1, Int64.min],
                    chatIds: [.init(accountId: workAccount, peerId: 42), .init(accountId: -1, peerId: Int64.max), .init(accountId: Int64.min, peerId: groupPeer)],
                    folderIds: [folder], mode: mode, effect: effect
                ), catalog: catalog)
                let predicate = notificationFilter(policy).predicate
                for account in accounts {
                    for peer in peers {
                        let identifier = FocusChatIdentifier(accountId: account, peerId: peer)
                        XCTAssertEqual(predicate.evaluate(with: notificationFilter(policy).criteria(for: identifier, catalog: policy.catalog)), policy.includes(accountId: account, peerId: peer, effect: .notifications), "\(mode) \(effect) \(identifier.rawValue)")
                    }
                }
            }
        }
    }

    func testNotificationTokensAvoidAccountChatAndFolderPrefixCollisions() {
        let folder = FocusFolderIdentifier(accountId: workAccount, folderId: 7)
        let catalog = FocusFilterCatalog(folders: [
            .init(id: folder, title: "Selected", peerIds: [3]),
            .init(id: .init(accountId: workAccount, folderId: 70), title: "Other", peerIds: [4]),
            .init(id: .init(accountId: personalAccount, folderId: 7), title: "Other account", peerIds: [5])
        ])
        for mode in [FocusFilterMode.allowSelected, .excludeSelected] {
            let policy = FocusFilterPolicy(configuration: .init(accountIds: [workAccount], chatIds: [.init(accountId: workAccount, peerId: 42)], folderIds: [folder], mode: mode), catalog: catalog)
            let predicate = notificationFilter(policy).predicate
            for peer: Int64 in [3, 4, 42, 420] {
                let chat = FocusChatIdentifier(accountId: workAccount, peerId: peer)
                XCTAssertEqual(predicate.evaluate(with: notificationFilter(policy).criteria(for: chat, catalog: policy.catalog)), policy.includes(accountId: workAccount, peerId: peer, effect: .notifications))
            }
            XCTAssertTrue(predicate.evaluate(with: notificationFilter(policy).criteria(for: .init(accountId: personalAccount, peerId: 42), catalog: policy.catalog)))
            XCTAssertTrue(predicate.evaluate(with: nil))
            XCTAssertTrue(predicate.evaluate(with: ""))
            XCTAssertTrue(predicate.evaluate(with: "unrelated-notification"))
        }
    }

    func testSignedIdentifiersAndConfigurationRoundTripWithoutPrecisionLoss() throws {
        let identifiers = [
            FocusChatIdentifier(accountId: Int64.min, peerId: Int64.max),
            FocusChatIdentifier(accountId: Int64.max, peerId: Int64.min),
            FocusChatIdentifier(accountId: -1, peerId: groupPeer),
            FocusChatIdentifier(accountId: -1, peerId: channelPeer)
        ]
        for identifier in identifiers {
            XCTAssertEqual(FocusChatIdentifier(rawValue: identifier.rawValue), identifier)
        }
        let folder = FocusFolderIdentifier(accountId: Int64.min, folderId: Int32.min)
        XCTAssertEqual(FocusFolderIdentifier(rawValue: folder.rawValue), folder)
        let configuration = FocusFilterConfiguration(accountIds: [Int64.min, Int64.max, -1], chatIds: Set(identifiers), folderIds: [folder], mode: .excludeSelected, effect: .both)
        XCTAssertEqual(try JSONDecoder().decode(FocusFilterConfiguration.self, from: JSONEncoder().encode(configuration)), configuration)
        let catalog = FocusFilterCatalog(accounts: [.init(id: Int64.min, title: "Работа")], chats: [.init(id: identifiers[0], title: "Личный чат")], folders: [.init(id: folder, title: "Проекты", peerIds: [Int64.min, Int64.max])])
        XCTAssertEqual(try JSONDecoder().decode(FocusFilterCatalog.self, from: JSONEncoder().encode(catalog)), catalog)
    }


}

private func notificationFilter(_ policy: FocusFilterPolicy) -> FocusNotificationFilter {
    FocusNotificationFilter(configuration: policy.configuration)
}

private func notificationCriteria(_ chat: FocusChatIdentifier) -> String {
    FocusNotificationFilter(configuration: .init()).criteria(for: chat, catalog: .init())
}
