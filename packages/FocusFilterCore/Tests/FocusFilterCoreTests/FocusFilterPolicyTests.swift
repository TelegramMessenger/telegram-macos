import XCTest
@testable import FocusFilterCore

final class FocusFilterPolicyTests: XCTestCase {
    private let workAccount: Int64 = 10
    private let personalAccount: Int64 = 100
    private let groupPeer: Int64 = 0x10000002a
    private let channelPeer: Int64 = 0x20000002a
    func testAllowListTargetsOnlyConfiguredAccountsAndFullPeerIdentifiers() {
        let selected = FocusChatIdentifier(accountId: workAccount, peerId: groupPeer)
        let policy = FocusFilterPolicy(configuration: .init(accountIds: [workAccount], chatIds: [selected], effect: .both))

        XCTAssertTrue(policy.includes(accountId: workAccount, peerId: groupPeer, effect: .notifications))
        XCTAssertFalse(policy.includes(accountId: workAccount, peerId: channelPeer, effect: .notifications))
        XCTAssertFalse(policy.includes(accountId: workAccount, peerId: 42, effect: .notifications))
        XCTAssertTrue(policy.includes(accountId: personalAccount, peerId: channelPeer, effect: .notifications))
        XCTAssertNil(policy.selection(accountId: personalAccount, effect: .chatList))
    }

    func testExclusionListLeavesOtherChatsAndAccountsUnchanged() {
        let selected = FocusChatIdentifier(accountId: workAccount, peerId: groupPeer)
        let policy = FocusFilterPolicy(configuration: .init(accountIds: [workAccount], chatIds: [selected], mode: .excludeSelected, effect: .both))

        XCTAssertFalse(policy.includes(accountId: workAccount, peerId: groupPeer, effect: .notifications))
        XCTAssertTrue(policy.includes(accountId: workAccount, peerId: channelPeer, effect: .notifications))
        XCTAssertTrue(policy.includes(accountId: personalAccount, peerId: groupPeer, effect: .notifications))
        XCTAssertFalse(policy.includes(accountId: workAccount, peerId: groupPeer, effect: .chatList))
    }

    func testFoldersAndExplicitChatsFormAUnionWithinEachAccount() {
        let workFolder = FocusFolderIdentifier(accountId: workAccount, folderId: 7)
        let personalFolder = FocusFolderIdentifier(accountId: personalAccount, folderId: 7)
        let catalog = FocusFilterCatalog(folders: [
            .init(id: workFolder, title: "Work", peerIds: [groupPeer, 55]),
            .init(id: personalFolder, title: "Personal", peerIds: [channelPeer])
        ])
        let configuration = FocusFilterConfiguration(
            accountIds: [workAccount, personalAccount],
            chatIds: [.init(accountId: workAccount, peerId: 55), .init(accountId: workAccount, peerId: 66)],
            folderIds: [workFolder], effect: .both
        )
        let policy = FocusFilterPolicy(configuration: configuration, catalog: catalog)

        XCTAssertEqual(policy.selection(accountId: workAccount, effect: .chatList)?.peerIds, [groupPeer, 55, 66])
        XCTAssertEqual(policy.selection(accountId: personalAccount, effect: .chatList)?.peerIds, [])
        XCTAssertFalse(policy.includes(accountId: personalAccount, peerId: channelPeer, effect: .notifications))
    }

    func testMalformedEntityIdentifiersAreRejected() {
        for invalid in ["", ":", "1", "1:2:3", "1:", ":2", "abc:2", "1:abc", "9223372036854775808:2", "1:-9223372036854775809"] {
            XCTAssertNil(FocusChatIdentifier(rawValue: invalid), invalid)
        }
        for invalid in ["", "1:2:3", "abc:2", "1:2147483648", "1:-2147483649"] {
            XCTAssertNil(FocusFolderIdentifier(rawValue: invalid), invalid)
        }
    }
}
