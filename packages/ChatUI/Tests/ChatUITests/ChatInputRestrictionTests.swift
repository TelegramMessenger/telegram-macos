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

    private func file(mimeType: String = "application/octet-stream", attributes: [TelegramMediaFileAttribute] = []) -> TelegramMediaFile {
        return TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.CloudFile, id: 1), partialReference: nil, resource: LocalFileMediaResource(fileId: 1), previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: mimeType, size: 1, attributes: attributes, alternativeRepresentations: [])
    }

    private func message(media: [Media] = []) -> Message {
        return Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 0, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: nil, text: "Existing message", attributes: [], media: media, peers: SimpleDictionary(), associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
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

    func testTextLockOffersBoostWhileMediaRemainsAvailable() {
        let peer = channel(defaults: [.banSendText])
        for applied: Int32? in [nil, 0, 1] {
            let presentation = state(peer, required: 2, applied: applied)
            XCTAssertEqual(presentation.state, .normal)
            XCTAssertEqual(presentation.textRestrictionBoostsRequired, 2)
            XCTAssertTrue(presentation.canAttachFiles)
            XCTAssertTrue(peer.canSendMessage(media: photo(), cachedData: presentation.cachedData))
        }
        let personalMediaBan = state(channel(defaults: [.banSendText], personal: [.banSendFiles]), required: 2)
        XCTAssertEqual(personalMediaBan.textRestrictionBoostsRequired, 2)
        XCTAssertFalse(personalMediaBan.canAttachFiles)
    }

    func testTextLockDoesNotOfferBoostForNonRemovableTextBans() {
        for required: Int32? in [nil, 0, -1] {
            XCTAssertNil(state(channel(defaults: [.banSendText]), required: required).textRestrictionBoostsRequired)
        }
        XCTAssertNil(state(channel(personal: [.banSendText]), required: 2).textRestrictionBoostsRequired)
        XCTAssertNil(state(channel(defaults: [.banSendText], personal: [.banSendText]), required: 2).textRestrictionBoostsRequired)
        XCTAssertNil(state(group(defaults: [.banSendText]), required: 2).textRestrictionBoostsRequired)
        XCTAssertNil(state(channel(), required: 2).textRestrictionBoostsRequired)
        XCTAssertNil(state(channel(defaults: [.banSendText], admin: true), required: 2).textRestrictionBoostsRequired)
    }

    func testTextLockBoostActionUpdatesWithPermissionsAndBoosts() {
        let original = state(channel(defaults: [.banSendText]), required: 2, applied: 1)
        let personalBan = original.updatedPeer { _ in self.channel(defaults: [.banSendText], personal: [.banSendText]) }
        XCTAssertEqual(original.textRestriction, personalBan.textRestriction)
        XCTAssertEqual(original.textRestrictionBoostsRequired, 2)
        XCTAssertNil(personalBan.textRestrictionBoostsRequired)
        let boosted = original.withUpdatedCachedData(cached(required: 2, applied: 2))
        XCTAssertNil(boosted.textRestriction)
        XCTAssertNil(boosted.textRestrictionBoostsRequired)
        let raisedThreshold = boosted.withUpdatedCachedData(cached(required: 3, applied: 2))
        XCTAssertEqual(raisedThreshold.textRestrictionBoostsRequired, 3)
        let disabledBoosts = raisedThreshold.withUpdatedCachedData(cached(required: 0, applied: 2))
        XCTAssertNotNil(disabledBoosts.textRestriction)
        XCTAssertNil(disabledBoosts.textRestrictionBoostsRequired)
        XCTAssertTrue(disabledBoosts.canAttachFiles)
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

    func testCombinedDefaultAndPersonalBansOfferBoost() {
        for defaultFlags: TelegramChatBannedRightsFlags in [[.banSendText], allSendingRights.subtracting([.banSendVoice])] {
            let peer = channel(defaults: defaultFlags, personal: allSendingRights.subtracting(defaultFlags))
            XCTAssertFalse(peer.canSendSomething())
            XCTAssertTrue(peer.canSendSomething(ignoreDefault: true))
            guard case .action = state(peer, required: 2, applied: 1).state else {
                return XCTFail("Expected boost action for combined restrictions")
            }
            let boosted = state(peer, required: 2, applied: 2)
            XCTAssertEqual(boosted.state, .normal)
            for required: Int32? in [nil, 0] {
                guard case .restricted = state(peer, required: required).state else {
                    return XCTFail("Expected full combined restriction")
                }
            }
        }
    }

    func testCombinedRestrictionsUpdateWhenBoostsChange() {
        let peer = channel(defaults: [.banSendText], personal: allSendingRights.subtracting([.banSendText]))
        let original = state(peer, required: 2, applied: 1)
        let boosted = original.withUpdatedCachedData(cached(required: 2, applied: 2))
        XCTAssertEqual(boosted.state, .normal)
        XCTAssertNil(boosted.textRestriction)
        XCTAssertTrue(peer.canSendMessage(cachedData: boosted.cachedData))
        XCTAssertFalse(peer.canSendMessage(media: photo(), cachedData: boosted.cachedData))
        guard case .action = boosted.withUpdatedCachedData(cached(required: 2, applied: 1)).state else {
            return XCTFail("Expected boost action after losing the bypass")
        }
    }

    func testStickerFormatsUseStickerPermissions() {
        let sticker = TelegramMediaFileAttribute.Sticker(displayText: "", packReference: nil, maskData: nil)
        let video = TelegramMediaFileAttribute.Video(duration: 1, size: PixelDimensions(width: 64, height: 64), flags: [], preloadSize: nil, coverTime: nil, videoCodec: nil)
        let stickers = [
            file(mimeType: "image/webp", attributes: [sticker]),
            file(mimeType: "application/x-tgsticker", attributes: [.FileName(fileName: "sticker.tgs"), sticker]),
            file(mimeType: "video/webm", attributes: [sticker, video, .Animated])
        ]
        let fileRestrictedPeers: [Peer] = [group(defaults: [.banSendFiles, .banSendVideos, .banSendGifs]), channel(defaults: [.banSendFiles, .banSendVideos, .banSendGifs])]
        for peer in fileRestrictedPeers {
            for sticker in stickers {
                XCTAssertNil(checkMediaPermission(sticker, for: peer))
                XCTAssertTrue(peer.canSendMessage(media: sticker))
            }
            XCTAssertNotNil(checkMediaPermission(file(), for: peer))
        }
        let stickerRestrictedPeers: [Peer] = [group(defaults: [.banSendStickers]), channel(defaults: [.banSendStickers])]
        for peer in stickerRestrictedPeers {
            for sticker in stickers {
                XCTAssertNotNil(checkMediaPermission(sticker, for: peer))
                XCTAssertFalse(peer.canSendMessage(media: sticker))
            }
            XCTAssertNil(checkMediaPermission(file(), for: peer))
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

    func testRestrictedDraftStaysStoredWhileVoiceIsAvailable() {
        let draft = ChatTextInputState(inputText: "Saved draft")
        let presentation = state(channel(defaults: [.banSendText]), required: 2)
            .updatedInterfaceState { $0.withUpdatedInputState(draft) }
        XCTAssertFalse(presentation.abilityToSend)
        for hasRichDraft in [false, true] {
            let button = ChatInputView.sendButtonState(from: presentation, hasRichDraft: hasRichDraft)
            XCTAssertEqual(button.kind, .voice)
            XCTAssertTrue(button.isSendEnabled)
        }
        XCTAssertTrue(presentation.inputForSending.inputText.isEmpty)
        XCTAssertEqual(presentation.effectiveInput, draft)
        let boosted = presentation.withUpdatedCachedData(cached(required: 2, applied: 2))
        XCTAssertTrue(boosted.abilityToSend)
        XCTAssertTrue(ChatInputView.sendButtonState(from: boosted, hasRichDraft: true).isSendEnabled)
        XCTAssertEqual(ChatInputView.sendButtonState(from: boosted, hasRichDraft: true).kind, .send)
        XCTAssertEqual(boosted.inputForSending, draft)
        XCTAssertEqual(boosted.effectiveInput, draft)
    }

    func testRestrictedRichDraftDoesNotHideVoice() {
        let presentation = state(channel(defaults: [.banSendText]))
        let button = ChatInputView.sendButtonState(from: presentation, hasRichDraft: true)
        XCTAssertEqual(button.kind, .voice)
        XCTAssertTrue(button.isSendEnabled)
        XCTAssertFalse(presentation.abilityToSend)
        XCTAssertTrue(presentation.canAttachFiles)
    }

    func testHiddenDraftDoesNotBlockForwardingAllowedMedia() {
        let forwarded = message(media: [photo()])
        for draft in [ChatTextInputState(), ChatTextInputState(inputText: "Saved draft")] {
            let presentation = state(channel(defaults: [.banSendText]))
                .updatedInterfaceState {
                    $0.withUpdatedInputState(draft)
                        .withUpdatedForwardMessageIds([forwarded.id])
                        .withUpdatedForwardMessages([forwarded])
                }
            for hasRichDraft in [false, true] {
                let button = ChatInputView.sendButtonState(from: presentation, hasRichDraft: hasRichDraft)
                XCTAssertEqual(button.kind, .send)
                XCTAssertTrue(button.isSendEnabled)
            }
            XCTAssertTrue(presentation.abilityToSend)
            XCTAssertTrue(presentation.inputForSending.inputText.isEmpty)
            XCTAssertEqual(presentation.effectiveInput, draft)
            XCTAssertNil(checkMediaPermission(photo(), for: presentation.peer))
        }
    }

    func testHiddenDraftDoesNotTriggerSlowModeCommentRestriction() {
        let forwarded = message(media: [photo()])
        let presentation = state(channel(defaults: [.banSendText]))
            .updatedInterfaceState {
                $0.withUpdatedInputState(ChatTextInputState(inputText: String(repeating: "a", count: 5000)))
                    .withUpdatedForwardMessageIds([forwarded.id])
                    .withUpdatedForwardMessages([forwarded])
            }
            .updateSlowMode { _ in SlowMode() }
        XCTAssertFalse(presentation.slowModeMultipleLocked)
        XCTAssertNil(presentation.slowModeErrorText)
        XCTAssertTrue(presentation.abilityToSend)
    }

    func testHiddenDraftIsNotCountedAsAPaidMessage() {
        let forwarded = message(media: [photo()])
        let presentation = state(channel(defaults: [.banSendText]))
            .updatedInterfaceState {
                $0.withUpdatedInputState(ChatTextInputState(inputText: "Saved draft"))
                    .withUpdatedForwardMessageIds([forwarded.id])
                    .withUpdatedForwardMessages([forwarded])
            }
            .withUpdatedSendPaidMessageStars(StarsAmount(value: 5, nanos: 0))
        XCTAssertEqual(ChatInputView.sendButtonState(from: presentation, hasRichDraft: true).kind, .paidStars(amount: 5))
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
        let message = self.message()
        let presentation = state(peer).withEditMessage(message)
        XCTAssertEqual(presentation.state, .editing)
        XCTAssertNil(presentation.textRestriction)
        XCTAssertNil(presentation.textRestrictionBoostsRequired)
        XCTAssertTrue(presentation.abilityToSend)
    }
}
