import XCTest
import Cocoa
import Postbox
import TelegramCore
import TGUIKit
import TelegramTheme
import Localization
@testable import StoriesUI

final class StorySharingTests: XCTestCase {
    private let ownerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: ._internalFromInt64Value(100))

    private static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 24, height: 24))
        image.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 2, y: 2, width: 20, height: 20).fill()
        image.unlockFocus()
        return image
    }()

    private static let retainedImages: [NSImage] = {
        return ["Icon_SearchField", "Icon_SearchClear", "Icon_Quote", "Icon_Quote_Collapse", "Icon_Quote_Expand"].map { name in
            if let image = NSImage(named: name) {
                return image
            }
            let image = StorySharingTests.image.copy() as! NSImage
            _ = image.setName(name)
            return image
        }
    }()

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        _ = StorySharingTests.retainedImages
        TelegramThemeHooks.install(TelegramThemeHooks(
            image: { _ in StorySharingTests.image },
            icons: { generateIcons(from: $0, bubbled: $1) },
            sendingFrame: { generateSendingFrame($0) },
            clockMinImage: { generateClockMinImage($0) },
            chatGroupToggleSelected: { generateChatGroupToggleSelected(foregroundColor: $0, backgroundColor: $1) },
            chatGroupToggleUnselected: { generateChatGroupToggleUnselected(foregroundColor: $0, backgroundColor: $1) },
            setDefaultTheme: { _ in },
            liteMode: { .standart },
            darkAppearance: { theme },
            liveStreamBadgeColor: { .systemRed }
        ))
    }

    private func story(isPublic: Bool = true, protected: Bool = false, username: String? = "storyowner", isMy: Bool = false) -> StoryContentItem {
        let peer = TelegramUser(id: ownerId, accessHash: nil, firstName: "Owner", lastName: nil, username: username, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        let media = TelegramMediaImage(imageId: MediaId(namespace: 0, id: 1), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        let item = EngineStoryItem(id: 1, timestamp: 0, expirationTimestamp: 3600, media: EngineMedia(media), alternativeMediaList: [], mediaAreas: [], text: "", entities: [], views: nil, privacy: nil, isPinned: false, isExpired: false, isPublic: isPublic, isPending: false, isCloseFriends: !isPublic, isContacts: false, isSelectedContacts: false, isForwardingDisabled: protected, isEdited: false, isMy: isMy, myReaction: nil, forwardInfo: nil, music: nil, author: nil, folderIds: [])
        return StoryContentItem(position: nil, dayCounters: nil, peer: .user(peer), storyItem: item, entityFiles: [:], itemPeer: nil)
    }

    private func shareButtons(_ view: StoryChannelInputView) -> [ImageButton] {
        return view.subviews.compactMap { $0 as? ImageButton }
    }

    func testForwardingRequiresPublicStoryAndPermission() {
        for isPublic in [false, true] {
            for protected in [false, true] {
                XCTAssertEqual(story(isPublic: isPublic, protected: protected).sharable, isPublic && !protected)
            }
        }
    }

    func testPublicProtectedStoryKeepsItsCopyableLink() {
        let value = story(protected: true)
        XCTAssertFalse(value.sharable)
        XCTAssertTrue(value.canCopyLink)
    }

    func testCopyLinkStillRequiresPublicStoryAndUsername() {
        for isPublic in [false, true] {
            for username: String? in [nil, "storyowner"] {
                for protected in [false, true] {
                    XCTAssertEqual(story(isPublic: isPublic, protected: protected, username: username).canCopyLink, isPublic && username != nil)
                }
            }
        }
    }

    func testOwnStoryDoesNotOverrideForwardingProtection() {
        XCTAssertFalse(story(protected: true, isMy: true).sharable)
        XCTAssertTrue(story(isMy: true).sharable)
    }

    func testChannelForwardAndRepostControlsStartHidden() {
        let view = StoryChannelInputView(frame: NSRect(x: 0, y: 0, width: 320, height: 50))
        let buttons = shareButtons(view)
        XCTAssertEqual(buttons.count, 2)
        XCTAssertTrue(buttons.allSatisfy(\.isHidden))
        XCTAssertNotNil(view.inputReactionsControl)
        XCTAssertFalse(view.inputReactionsControl?.isHidden ?? true)
    }

    func testProtectedChannelStoryHidesForwardAndRepostButKeepsReactions() {
        let view = StoryChannelInputView(frame: NSRect(x: 0, y: 0, width: 320, height: 50))
        view.update(story(protected: true), animated: false)
        XCTAssertTrue(shareButtons(view).allSatisfy(\.isHidden))
        XCTAssertFalse(view.inputReactionsControl?.isHidden ?? true)
    }

    func testPublicUnprotectedChannelStoryShowsBothActions() {
        let view = StoryChannelInputView(frame: NSRect(x: 0, y: 0, width: 320, height: 50))
        view.update(story(), animated: false)
        let buttons = shareButtons(view)
        XCTAssertEqual(buttons.count, 2)
        XCTAssertTrue(buttons.allSatisfy { !$0.isHidden })
        XCTAssertEqual(Set(buttons.compactMap { $0.accessibilityLabel() }), Set([strings().voiceOverCommonShare, strings().voiceOverCommonRepost]))
    }

    func testPrivateChannelStoryDoesNotOfferForwarding() {
        let view = StoryChannelInputView(frame: NSRect(x: 0, y: 0, width: 320, height: 50))
        view.update(story(isPublic: false), animated: false)
        XCTAssertTrue(shareButtons(view).allSatisfy(\.isHidden))
    }

    func testReusedChannelFooterUpdatesProtectionInBothDirections() {
        let view = StoryChannelInputView(frame: NSRect(x: 0, y: 0, width: 320, height: 50))
        for protected in [false, true, false, true] {
            view.update(story(protected: protected), animated: false)
            XCTAssertTrue(shareButtons(view).allSatisfy { $0.isHidden == protected })
        }
    }

    func testFooterUpdatesBeforeArgumentsAreInstalled() {
        let view = StoryChannelInputView(frame: NSRect(x: 0, y: 0, width: 320, height: 50))
        view.setArguments(nil, groupId: nil)
        view.update(story(), animated: false)
        XCTAssertFalse(shareButtons(view).contains(where: \.isHidden))
        view.update(story(protected: true), animated: false)
        XCTAssertTrue(shareButtons(view).allSatisfy(\.isHidden))
    }
}
