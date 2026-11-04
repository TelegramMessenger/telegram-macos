import XCTest
import Postbox
import TelegramCore
import TelegramUtils
import ChatModeTypes
import Localization
import InputView
@testable import ChatUI

final class ChatInputRestrictionTests: XCTestCase {
    private let peerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(3))
    private let allSendingRights: TelegramChatBannedRightsFlags = [.banSendText, .banSendInstantVideos, .banSendVoice, .banSendPhotos, .banSendVideos, .banSendStickers, .banSendPolls, .banSendFiles, .banSendInline, .banSendMusic]

    override func setUp() {
        super.setUp()
        UITestBootstrap.install()
        applyMacEnglishStrings()
        ChatInterfaceHooks.install(ChatInterfaceHooks(
            freezeAlert: { _ in },
            resolveUsername: { _, _ in .single(nil) },
            makeGroupCallPanelData: { _, _, _, _ in .single(nil) },
            setChatInterfaceTempState: { _, _, _ in },
            inputSource: { _ in fatalError() },
            executeUrl: { _, _ in },
            executeConfirmedUrl: { _, _ in },
            shareSwitchInlineQuery: { _, _, _ in },
            showLoginWidgetConfirmation: { _, _, _, _, _, _, _, _ in },
            makeNewPollController: { _, _ in fatalError() },
            makeTopicIconFile: { _, _, _ in fatalError() },
            peerIsForum: { ($0 as? TelegramChannel)?.flags.contains(.isForum) == true },
            urlPreviewInAppLink: { _, _ in .other }))
    }

    private func rights(_ flags: TelegramChatBannedRightsFlags, until: Int32 = Int32.max) -> TelegramChatBannedRights? {
        return flags.isEmpty ? nil : TelegramChatBannedRights(flags: flags, untilDate: until)
    }

    private func channel(defaults: TelegramChatBannedRightsFlags = [], personal: TelegramChatBannedRightsFlags = [], until: Int32 = Int32.max, admin: Bool = false, status: TelegramChannelParticipationStatus = .member) -> TelegramChannel {
        return TelegramChannel(id: peerId, accessHash: nil, title: "Group", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: status, info: .group(.init(flags: [])), flags: [], restrictionInfo: nil, adminRights: admin ? TelegramChatAdminRights(rights: [.canBanUsers]) : nil, bannedRights: rights(personal, until: until), defaultBannedRights: rights(defaults), usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func group(defaults: TelegramChatBannedRightsFlags) -> TelegramGroup {
        return TelegramGroup(id: PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(3)), title: "Group", photo: [], participantCount: 10, role: .member, membership: .Member, flags: [], defaultBannedRights: rights(defaults), migrationReference: nil, creationDate: 0, version: 0)
    }

    private func cached(required: Int32?, applied: Int32? = nil) -> CachedChannelData {
        return CachedChannelData().withUpdatedBoostsToUnrestrict(required).withUpdatedAppliedBoosts(applied)
    }

    private func state(_ peer: Peer, required: Int32? = nil, applied: Int32? = nil, mode: ChatMode = .history) -> ChatPresentationInterfaceState {
        return ChatPresentationInterfaceState(chatLocation: .peer(peer.id), chatMode: mode)
            .updatedPeer { _ in peer }
            .withUpdatedCachedData(cached(required: required, applied: applied))
    }

    private func photo() -> TelegramMediaImage {
        return TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.CloudImage, id: 1), representations: [], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
    }

    private func file() -> TelegramMediaFile {
        return TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.CloudFile, id: 1), partialReference: nil, resource: LocalFileMediaResource(fileId: 1), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "application/octet-stream", size: 1, attributes: [], alternativeRepresentations: [])
    }

    private func thread(closed: Bool, owned: Bool = false) -> MessageHistoryThreadData {
        return MessageHistoryThreadData(creationDate: 0, isOwnedByMe: owned, author: peerId, info: EngineMessageHistoryThread.Info(title: "Topic", icon: nil, iconColor: 0), incomingUnreadCount: 0, isMarkedUnread: false, maxIncomingReadId: 0, maxKnownMessageId: 0, maxOutgoingReadId: 0, isClosed: closed, isHidden: false, notificationSettings: .defaultSettings, isMessageFeeRemoved: false)
    }

    func testTextOnlyBanKeepsComposerAndMediaAvailable() {
        let peer = channel(defaults: [.banSendText])
        for required: Int32? in [nil, 0, 2] {
            let presentation = state(peer, required: required, applied: 0)
            XCTAssertEqual(presentation.state, .normal)
            XCTAssertNotNil(presentation.textRestriction)
            XCTAssertTrue(presentation.canAttachFiles)
            XCTAssertFalse(peer.canSendMessage(cachedData: presentation.cachedData))
            XCTAssertTrue(peer.canSendMessage(media: photo(), cachedData: presentation.cachedData))
            XCTAssertTrue(peer.canSendMessage(media: file(), cachedData: presentation.cachedData))
        }
        XCTAssertEqual(strings().channelPersmissionMessageBlock, "Text is not Allowed")
    }

    func testFullDefaultBanOffersBoostOnlyWhenEnabled() {
        let peer = channel(defaults: allSendingRights)
        let boostable = state(peer, required: 2, applied: 1)
        guard case let .action(text, _, _, _, _) = boostable.state else {
            return XCTFail("Expected boost action")
        }
        XCTAssertEqual(text, strings().boostGroupChatInputAction)
        for required: Int32? in [nil, 0] {
            guard case .restricted = state(peer, required: required).state else {
                return XCTFail("Expected full restriction")
            }
        }
    }

    func testSufficientBoostsBypassDefaultBans() {
        let peer = channel(defaults: allSendingRights)
        let presentation = state(peer, required: 2, applied: 2)
        XCTAssertEqual(presentation.state, .normal)
        XCTAssertNil(presentation.textRestriction)
        XCTAssertTrue(presentation.canAttachFiles)
        XCTAssertTrue(peer.canSendMessage(cachedData: presentation.cachedData))
        XCTAssertTrue(peer.canSendMessage(media: photo(), cachedData: presentation.cachedData))
        XCTAssertNil(checkMediaPermission(file(), for: peer, cachedData: presentation.cachedData))
    }

    func testBoostsNeverBypassPersonalTextOrMediaBans() {
        let peer = channel(defaults: allSendingRights, personal: [.banSendText, .banSendFiles])
        let presentation = state(peer, required: 2, applied: 2)
        XCTAssertEqual(presentation.state, .normal)
        XCTAssertNotNil(presentation.textRestriction)
        XCTAssertFalse(presentation.canAttachFiles)
        XCTAssertFalse(peer.canSendMessage(cachedData: presentation.cachedData))
        XCTAssertFalse(peer.canSendMessage(media: file(), cachedData: presentation.cachedData))
        XCTAssertTrue(peer.canSendMessage(media: photo(), cachedData: presentation.cachedData))
        XCTAssertNotNil(checkMediaPermission(file(), for: peer, cachedData: presentation.cachedData))
    }

    func testFullPersonalBanDoesNotOfferBoost() {
        for applied: Int32 in [0, 2] {
            let presentation = state(channel(personal: allSendingRights), required: 2, applied: applied)
            guard case .restricted = presentation.state else {
                return XCTFail("Personal restrictions cannot be removed by boosts")
            }
        }
    }

    func testMissingOrZeroThresholdNeverBypassesRestrictions() {
        let peer = channel(defaults: allSendingRights)
        for required: Int32? in [nil, 0] {
            let data = cached(required: required, applied: 5)
            XCTAssertFalse(canBypassChatRestrictions(data))
            XCTAssertNotNil(permissionText(from: peer, for: .banSendText, cachedData: data))
            XCTAssertFalse(peer.canSendMessage(cachedData: data))
            XCTAssertFalse(peer.canSendMessage(media: photo(), cachedData: data))
        }
        XCTAssertFalse(canBypassChatRestrictions(cached(required: 2)))
    }

    func testBasicGroupsDistinguishTextAndFullRestrictions() {
        let peer = group(defaults: [.banSendText])
        let presentation = state(peer)
        XCTAssertEqual(presentation.state, .normal)
        XCTAssertNotNil(presentation.textRestriction)
        XCTAssertTrue(presentation.canAttachFiles)
        XCTAssertFalse(peer.canSendMessage())
        XCTAssertTrue(peer.canSendMessage(media: photo()))
        XCTAssertTrue(peer.canSendMessage(media: file()))
        guard case .restricted = state(group(defaults: allSendingRights)).state else {
            return XCTFail("Expected full basic-group restriction")
        }
    }

    func testLivePermissionAndBoostUpdatesRestoreComposer() {
        let original = state(channel(defaults: [.banSendText]), required: 2, applied: 0)
        let boosted = original.withUpdatedCachedData(cached(required: 2, applied: 2))
        XCTAssertNotNil(original.textRestriction)
        XCTAssertNil(boosted.textRestriction)
        XCTAssertEqual(boosted.state, .normal)
        let personallyRestricted = boosted.updatedPeer { _ in self.channel(defaults: [.banSendText], personal: [.banSendText]) }
        XCTAssertNotNil(personallyRestricted.textRestriction)
        let unrestricted = personallyRestricted.updatedPeer { _ in self.channel() }
        XCTAssertNil(unrestricted.textRestriction)
    }

    func testRestrictedDraftStaysStoredAndCannotSend() {
        let draft = ChatTextInputState(inputText: "Saved draft")
        let presentation = state(channel(defaults: [.banSendText]), required: 2)
            .updatedInterfaceState { $0.withUpdatedInputState(draft) }
        XCTAssertFalse(presentation.abilityToSend)
        XCTAssertFalse(ChatInputView.sendButtonState(from: presentation).isSendEnabled)
        XCTAssertFalse(ChatInputView.sendButtonState(from: presentation, hasRichDraft: true).isSendEnabled)
        XCTAssertEqual(presentation.effectiveInput, draft)
        let boosted = presentation.withUpdatedCachedData(cached(required: 2, applied: 2))
        XCTAssertTrue(boosted.abilityToSend)
        XCTAssertTrue(ChatInputView.sendButtonState(from: boosted, hasRichDraft: true).isSendEnabled)
        XCTAssertEqual(boosted.effectiveInput, draft)
    }

    func testRichDraftWithoutPlainTextCannotSendWhenRestricted() {
        let presentation = state(channel(defaults: [.banSendText]))
        XCTAssertFalse(ChatInputView.sendButtonState(from: presentation, hasRichDraft: true).isSendEnabled)
        XCTAssertTrue(presentation.canAttachFiles)
    }

    func testClosedTopicsRetainPrecedenceOverBoosts() {
        let peer = channel(defaults: allSendingRights)
        let mode = ChatMode.thread(mode: .topic(origin: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: 1)))
        let presentation = state(peer, required: 2, applied: 2, mode: mode).withUpdatedThreadInfo(thread(closed: true))
        guard case let .restricted(text) = presentation.state else {
            return XCTFail("Expected closed-topic restriction")
        }
        XCTAssertEqual(text, strings().chatInputTopicClosed)
        XCTAssertFalse(presentation.canAttachFiles)
        XCTAssertFalse(peer.canSendMessage(true, media: photo(), threadData: thread(closed: true), cachedData: presentation.cachedData))
        XCTAssertEqual(presentation.withUpdatedThreadInfo(thread(closed: true, owned: true)).state, .normal)
    }

    func testThreadComposerUsesTheSameRestrictionRules() {
        let mode = ChatMode.thread(mode: .topic(origin: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: 1)))
        XCTAssertEqual(state(channel(defaults: [.banSendText]), required: 2, mode: mode).state, .normal)
        guard case .action = state(channel(defaults: allSendingRights), required: 2, mode: mode).state else {
            return XCTFail("Expected boost action in topic")
        }
    }

    func testBoostsDoNotBypassMembership() {
        for status: TelegramChannelParticipationStatus in [.left, .kicked] {
            let peer = channel(defaults: allSendingRights, status: status)
            let presentation = state(peer, required: 2, applied: 2)
            XCTAssertNotEqual(presentation.state, .normal)
            XCTAssertFalse(presentation.canAttachFiles)
            XCTAssertFalse(peer.canSendMessage(cachedData: presentation.cachedData))
            XCTAssertFalse(peer.canSendMessage(media: photo(), cachedData: presentation.cachedData))
        }
    }

    func testAdministratorsRemainUnrestricted() {
        let peer = channel(defaults: allSendingRights, personal: allSendingRights, admin: true)
        let presentation = state(peer, required: 2)
        XCTAssertEqual(presentation.state, .normal)
        XCTAssertNil(presentation.textRestriction)
        XCTAssertTrue(presentation.canAttachFiles)
        XCTAssertTrue(peer.canSendMessage())
    }

    func testEditingRetainsItsExistingPermissionBehavior() {
        let peer = channel(defaults: allSendingRights)
        let message = Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: "Existing message", attributes: [], media: [], peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
        let presentation = state(peer).withEditMessage(message)
        XCTAssertEqual(presentation.state, .editing)
        XCTAssertNil(presentation.textRestriction)
        XCTAssertTrue(presentation.abilityToSend)
    }
}
