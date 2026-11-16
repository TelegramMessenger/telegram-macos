import XCTest
import Postbox
import TelegramCore
import InputDataUI
@testable import FolderSharingUI

final class FolderSharingUITests: XCTestCase {
    private func group(_ value: Int64, creator: Bool = true) -> TelegramGroup {
        return TelegramGroup(id: PeerId(namespace: Namespaces.Peer.CloudGroup, id: ._internalFromInt64Value(value)), title: "Group \(value)", photo: [], participantCount: 3, role: creator ? .creator(rank: nil) : .member, membership: .Member, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
    }

    private func channel(_ value: Int64, username: String? = nil, flags: TelegramChannelFlags = [], member: Bool = true) -> TelegramChannel {
        return TelegramChannel(id: PeerId(namespace: Namespaces.Peer.CloudChannel, id: ._internalFromInt64Value(value)), accessHash: nil, title: "Channel", username: username, photo: [], creationDate: 0, version: 0, participationStatus: member ? .member : .left, info: .broadcast(.init(flags: [])), flags: flags, restrictionInfo: nil, adminRights: nil, bannedRights: nil, defaultBannedRights: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
    }

    private func filter(hasLinks: Bool = false) -> ChatListFilter {
        var includes = ChatListFilterIncludePeers()
        includes.setPeers([group(1).id, group(2).id])
        return .filter(id: 10, title: .init(text: "QA", entities: [.init(range: 0..<2, type: .Bold)], enableAnimations: false), emoticon: "📁", data: ChatListFilterData(isShared: true, hasSharedLinks: hasLinks, categories: [], excludeMuted: false, excludeRead: false, excludeArchived: false, includePeers: includes, excludePeers: [], color: nil))
    }

    private func link(_ slug: String = "first", title: String = "Original", ids: [PeerId]? = nil) -> ExportedChatFolderLink {
        return ExportedChatFolderLink(title: title, link: "https://t.me/addlist/\(slug)", peerIds: ids ?? [group(1).id], isRevoked: false)
    }

    private func closureState(localId: Int32? = nil) -> FolderSharingClosureState {
        return FolderSharingClosureState(title: "QA", peers: [group(3), group(1), group(2)].map(FolderSharingPeer.init), selected: [group(1).id, group(2).id, group(3).id], alreadyMemberPeerIds: [group(1).id], localFolderId: localId, inviteLinks: nil)
    }

    func testFolderMetadataAndAllChatsIdentity() {
        let value = filter()
        XCTAssertEqual(value.folderSharingId, 10)
        XCTAssertEqual(value.title, "QA")
        XCTAssertEqual(value.entities, [.init(range: 0..<2, type: .Bold)])
        XCTAssertTrue(value.data!.isShared)
        XCTAssertEqual(ChatListFilter.allChats.folderSharingId, -1)
        XCTAssertEqual(ChatListFilter.allChats.id, 0)
        XCTAssertNil(ChatListFilter.allChats.data)
    }

    func testSharingEligibilityUsesAccessAndRejectsRequestToJoin() {
        XCTAssertTrue(peerCanBeSharedInFolder(group(1)))
        XCTAssertFalse(peerCanBeSharedInFolder(group(1, creator: false)))
        XCTAssertTrue(peerCanBeSharedInFolder(channel(1, username: "public")))
        XCTAssertFalse(peerCanBeSharedInFolder(channel(1)))
        XCTAssertFalse(peerCanBeSharedInFolder(channel(1, flags: [.isCreator])))
        XCTAssertFalse(peerCanBeSharedInFolder(channel(1, username: "public", flags: [.isCreator, .requestToJoin])))
    }

    func testPeerEqualityIncludesChangesBeyondIdentity() {
        XCTAssertEqual(FolderSharingPeer(group(1)), FolderSharingPeer(group(1)))
        XCTAssertNotEqual(FolderSharingPeer(group(1)), FolderSharingPeer(group(1, creator: false)))
        XCTAssertNil(FolderSharingPeer(nil))
    }

    func testInvitationModePreservesContentMetadataAndPeerOrder() {
        let contents = ChatFolderLinkContents(localFilterId: 10, title: .init(text: "Invite", entities: [.init(range: 0..<6, type: .Italic)], enableAnimations: true), peers: [.legacyGroup(group(2)), .legacyGroup(group(1))], alreadyMemberPeerIds: [group(1).id], memberCounts: [:])
        let mode = JoinCloudFolderMode.join(slug: "first", content: contents)
        XCTAssertEqual(mode.peers.map { $0.id }, [group(2).id, group(1).id])
        XCTAssertEqual(mode.title, "Invite")
        XCTAssertEqual(mode.titleEntities, contents.title!.entities)
        XCTAssertEqual(mode.alreadyMemberPeerIds, [group(1).id])
        XCTAssertEqual(mode.localFilterId, 10)
        XCTAssertNil(mode.initialSelection)
        XCTAssertNil(mode.inviteLinks)
    }

    func testInvitationWithoutMetadataAndLinkManagementMode() {
        let invitation = JoinCloudFolderMode.join(slug: "empty", content: ChatFolderLinkContents(localFilterId: nil, title: nil, peers: [], alreadyMemberPeerIds: [], memberCounts: [:]))
        XCTAssertEqual(invitation.title, "")
        XCTAssertEqual(invitation.titleEntities, [])
        XCTAssertNil(invitation.localFilterId)
        let mode = JoinCloudFolderMode.sharedLinks(filter: filter(), links: [link("second"), link()])
        XCTAssertEqual(mode.inviteLinks, [link("second"), link()])
        XCTAssertTrue(mode.peers.isEmpty)
        XCTAssertEqual(mode.title, "QA")
        XCTAssertEqual(mode.titleEntities, filter().entities)
        XCTAssertEqual(mode.localFilterId, 10)
        XCTAssertTrue(mode.alreadyMemberPeerIds.isEmpty)
    }

    func testRemovalSelectsOnlySuggestedPeersInOriginalOrder() {
        let mode = JoinCloudFolderMode.remove(filter: filter(hasLinks: true), peers: [group(2), group(1)], default: [group(1).id, group(99).id])
        let selection = Selection()
        folderSharingInitializeSelection(mode.peers, selectedIds: mode.initialSelection, selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, [group(1).id])
        XCTAssertEqual(selection.toggled, [group(1).id])
        XCTAssertEqual(mode.peers.map { $0.id }, [group(2).id, group(1).id])
        XCTAssertEqual(mode.titleEntities, filter().entities)
        XCTAssertTrue(mode.alreadyMemberPeerIds.isEmpty)
    }

    func testDefaultSelectionInitializationIsIdempotent() {
        let selection = Selection()
        let peers: [Peer] = [group(2), group(1)]
        folderSharingInitializeSelection(peers, selectedIds: nil, selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, Set(peers.map { $0.id }))
        XCTAssertEqual(selection.toggled, peers.map { $0.id })
        folderSharingInitializeSelection(peers, selectedIds: nil, selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, Set(peers.map { $0.id }))
        XCTAssertEqual(selection.toggled, peers.map { $0.id })
    }

    func testExistingLinkRefreshPreservesSelectionAndBaseline() {
        let selection = Selection()
        var refresh = FolderSharingLinkSelection()
        let peers: [Peer] = [group(1), group(2)]
        refresh.update(peers, selectedIds: [group(1).id], selection: selection)
        for _ in 0..<3 {
            refresh.update([group(2), group(1)], selectedIds: [group(1).id], selection: selection)
            XCTAssertEqual(selection.selectedPeerIds, [group(1).id])
            XCTAssertEqual(refresh.initialSelected, [group(1).id])
        }
        XCTAssertEqual(selection.toggled, [group(1).id])
    }

    func testRefreshPreservesUnsavedRowChoicesAndDiscardConfirmation() {
        let selection = Selection()
        var refresh = FolderSharingLinkSelection()
        let original = link()
        let peers: [Peer] = [group(1), group(2)]
        refresh.update(peers, selectedIds: Set(original.peerIds), selection: selection)
        selection.toggleFromRow(group(1))
        selection.toggleFromRow(group(2))
        refresh.update(peers, selectedIds: Set(original.peerIds), selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, [group(2).id])
        XCTAssertEqual(refresh.initialSelected, [group(1).id])
        let state = FolderSharingLinkState(filter: filter(), link: original, selected: selection.selectedPeerIds)
        XCTAssertTrue(state.needsDiscardConfirmation(original: original, initialSelected: refresh.initialSelected))
    }

    func testRefreshPreservesSelectAllAndDeselectAll() {
        let selection = Selection()
        var refresh = FolderSharingLinkSelection()
        let peers: [Peer] = [group(1), group(2)]
        refresh.update(peers, selectedIds: [group(1).id], selection: selection)
        folderSharingToggleAll(peers, selected: selection.selectedPeerIds, selection: selection)
        refresh.update(peers, selectedIds: [group(1).id], selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, Set(peers.map { $0.id }))
        folderSharingToggleAll(peers, selected: selection.selectedPeerIds, selection: selection)
        refresh.update(peers, selectedIds: [group(1).id], selection: selection)
        XCTAssertTrue(selection.selectedPeerIds.isEmpty)
        XCTAssertEqual(refresh.initialSelected, [group(1).id])
    }

    func testNewLinkRefreshPreservesChoicesAndSelectsLatePeers() {
        let selection = Selection()
        var refresh = FolderSharingLinkSelection()
        refresh.update([], selectedIds: nil, selection: selection)
        refresh.update([group(1)], selectedIds: nil, selection: selection)
        selection.toggleFromRow(group(1))
        refresh.update([group(1), group(2)], selectedIds: nil, selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, [group(2).id])
        XCTAssertEqual(refresh.initialSelected, [group(1).id, group(2).id])
        refresh.update([group(2), group(1)], selectedIds: nil, selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, [group(2).id])
    }

    func testExistingLinkInitializesOnlyLateLinkedPeers() {
        let selection = Selection()
        var refresh = FolderSharingLinkSelection()
        let linked: Set<PeerId> = [group(1).id, group(2).id]
        refresh.update([group(1)], selectedIds: linked, selection: selection)
        selection.toggleFromRow(group(1))
        refresh.update([group(1), group(2), group(3)], selectedIds: linked, selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, [group(2).id])
        XCTAssertEqual(refresh.initialSelected, linked)
    }

    func testUnavailablePeerRestoresUnsavedChoiceWithoutResettingBaseline() {
        let selection = Selection()
        var refresh = FolderSharingLinkSelection()
        let peers: [Peer] = [group(1), group(2)]
        refresh.update(peers, selectedIds: [group(1).id], selection: selection)
        selection.toggleFromRow(group(1))
        selection.toggleFromRow(group(2))
        refresh.update([], selectedIds: [group(1).id], selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, [group(2).id])
        XCTAssertEqual(refresh.initialSelected, [group(1).id])
        refresh.update(peers, selectedIds: [group(1).id], selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, [group(2).id])
        XCTAssertEqual(refresh.initialSelected, [group(1).id])
    }

    func testEligibilityLossDoesNotClearOtherChoicesOrBecomeBaseline() {
        let selection = Selection()
        var refresh = FolderSharingLinkSelection()
        let linked: Set<PeerId> = [group(1).id, group(2).id]
        refresh.update([group(1), group(2)], selectedIds: linked, selection: selection)
        refresh.update([group(2)], selectedIds: linked, selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, linked)
        XCTAssertEqual(refresh.initialSelected, linked)
        refresh.update([group(2)], selectedIds: linked, selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, linked)
        refresh.update([group(1), group(2)], selectedIds: linked, selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, linked)
    }

    func testOnlyLinkedPeerEligibilityLossPreservesDoneAndClose() {
        let selection = Selection()
        let original = link()
        var refresh = FolderSharingLinkSelection(selectedIds: Set(original.peerIds))
        refresh.update([group(1)], selectedIds: Set(original.peerIds), selection: selection)
        refresh.update([], selectedIds: Set(original.peerIds), selection: selection)
        let state = FolderSharingLinkState(filter: filter(), link: original, selected: refresh.selectedPeerIds(selection))
        XCTAssertEqual(state.selected, Set(original.peerIds))
        XCTAssertFalse(state.needsDiscardConfirmation(original: original, initialSelected: refresh.initialSelected))
        var events: [String] = []
        folderSharingSaveLink(state: state, original: original, edit: { _, _, _, _ in events.append("edit") }, updated: { _, _ in XCTFail() }, success: { XCTFail() }, failure: { XCTFail() }, delete: { events.append("delete") }, close: { events.append("close") })
        XCTAssertEqual(events, ["close"])
        XCTAssertEqual(selection.toggled, original.peerIds)
    }

    func testUnresolvedLinkedIdsSurviveRowsAndBulkChanges() {
        let selection = Selection()
        let ids: Set<PeerId> = [group(1).id]
        var refresh = FolderSharingLinkSelection(selectedIds: ids)
        XCTAssertEqual(refresh.selectedPeerIds(selection), ids)
        refresh.update([group(2)], selectedIds: ids, selection: selection)
        XCTAssertEqual(refresh.selectedPeerIds(selection), ids)
        folderSharingToggleAll([group(2)], selected: refresh.selectedPeerIds(selection), selection: selection)
        XCTAssertEqual(refresh.selectedPeerIds(selection), [group(1).id, group(2).id])
        folderSharingToggleAll([group(2)], selected: refresh.selectedPeerIds(selection), selection: selection)
        XCTAssertEqual(refresh.selectedPeerIds(selection), ids)
        refresh.update([group(1), group(2)], selectedIds: ids, selection: selection)
        selection.toggleFromRow(group(1))
        XCTAssertTrue(refresh.selectedPeerIds(selection).isEmpty)
        refresh.update([], selectedIds: ids, selection: selection)
        refresh.update([group(1), group(2)], selectedIds: ids, selection: selection)
        XCTAssertTrue(refresh.selectedPeerIds(selection).isEmpty)
    }

    func testMissingSelectionDoesNotConsumeInitialization() {
        var refresh = FolderSharingLinkSelection()
        refresh.update([group(1)], selectedIds: nil, selection: nil)
        XCTAssertTrue(refresh.initialSelected.isEmpty)
        let selection = Selection()
        refresh.update([group(1)], selectedIds: nil, selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, [group(1).id])
        XCTAssertEqual(refresh.initialSelected, [group(1).id])
    }

    func testSelectAllPreservesDisabledAndAlreadyJoinedSelection() {
        let selection = Selection()
        selection.selectedPeerIds = [group(1).id, group(3).id]
        let pending: [Peer] = [group(3), group(2)]
        folderSharingToggleAll(pending, selected: selection.selectedPeerIds, selection: selection)
        XCTAssertEqual(selection.toggled, [group(2).id])
        XCTAssertEqual(selection.selectedPeerIds, [group(1).id, group(2).id, group(3).id])
        folderSharingToggleAll(pending, selected: selection.selectedPeerIds, selection: selection)
        XCTAssertEqual(selection.selectedPeerIds, [group(1).id])
        XCTAssertEqual(selection.toggled, [group(2).id, group(3).id, group(2).id])
    }

    func testPendingAndJoinedEntryIdentityAndOrder() {
        let state = closureState()
        XCTAssertEqual(state.pendingPeers.map { $0.peer.id }, [group(3).id, group(2).id])
        XCTAssertEqual(state.joinedPeers.map { $0.peer.id }, [group(1).id])
        XCTAssertEqual(folderSharingClosurePeerIdentifier(group(3).id), InputDataIdentifier("_id_peer_\(group(3).id.toInt64())"))
        XCTAssertEqual(folderSharingLinkPeerIdentifier(group(3).id), folderSharingClosurePeerIdentifier(group(3).id))
        XCTAssertNotEqual(folderSharingClosurePeerIdentifier(group(2).id), folderSharingClosurePeerIdentifier(group(3).id))
        XCTAssertEqual(folderSharingInviteIdentifier(link().slug), InputDataIdentifier("_id_invite_linkfirst"))
        XCTAssertNotEqual(folderSharingInviteIdentifier(link().slug), folderSharingInviteIdentifier(link("second").slug))
    }

    func testAddedChatsRecognizesOnlyJoinedChannels() {
        let peers: [EnginePeer] = [.channel(channel(1)), .channel(channel(2, member: false)), .legacyGroup(group(1))]
        XCTAssertEqual(folderSharingJoinedChannelIds(peers), [channel(1).id])
    }

    func testJoinDecisionsExcludeAlreadyJoinedPeers() {
        var state = closureState(localId: 10)
        XCTAssertTrue(folderSharingShouldJoin(state))
        state.selected = [group(1).id]
        XCTAssertFalse(state.hasSelectedToJoin)
        XCTAssertTrue(state.isAlreadyInFolder)
        XCTAssertFalse(folderSharingShouldJoin(state))
        state.localFolderId = nil
        XCTAssertTrue(folderSharingShouldJoin(state))
        state.selected = []
        XCTAssertFalse(folderSharingShouldJoin(state))
    }

    func testLinkNamingAndDiscardConfirmation() {
        let original = link()
        var state = FolderSharingLinkState(filter: filter(), link: original, selected: Set(original.peerIds))
        XCTAssertFalse(state.needsDiscardConfirmation(original: original, initialSelected: state.selected))
        state.link?.title = String(repeating: "a", count: 32)
        XCTAssertEqual(state.link?.title.count, 32)
        XCTAssertTrue(state.needsDiscardConfirmation(original: original, initialSelected: state.selected))
        XCTAssertFalse(state.needsDiscardConfirmation(original: nil, initialSelected: []))
        state.link = original
        state.selected = []
        XCTAssertTrue(state.needsDiscardConfirmation(original: original, initialSelected: Set(original.peerIds)))
    }

    func testEditedLinkClosesBeforeAsyncUpdateAndSuccess() {
        let original = link()
        let state = FolderSharingLinkState(filter: filter(), link: link(title: "Renamed"), selected: [group(2).id])
        var events: [String] = []
        var completion: ((ExportedChatFolderLink) -> Void)?
        folderSharingSaveLink(state: state, original: original, edit: { current, selected, success, _ in
            XCTAssertEqual(current.title, "Renamed")
            XCTAssertEqual(selected, [self.group(2).id])
            events.append("request")
            completion = success
        }, updated: { old, new in
            XCTAssertEqual(old, state.link)
            XCTAssertEqual(new?.peerIds, [self.group(2).id])
            events.append("updated")
        }, success: { events.append("success") }, failure: { XCTFail() }, delete: { XCTFail() }, close: { events.append("close") })
        XCTAssertEqual(events, ["request", "close"])
        completion?(link(title: "Renamed", ids: [group(2).id]))
        XCTAssertEqual(events, ["request", "close", "updated", "success"])
    }

    func testLinkSaveFailureArrivesAfterClose() {
        var events: [String] = []
        var failure: (() -> Void)?
        folderSharingSaveLink(state: FolderSharingLinkState(filter: filter(), link: link(title: "Changed"), selected: [group(1).id]), original: link(), edit: { _, _, _, error in failure = error }, updated: { _, _ in XCTFail() }, success: { XCTFail() }, failure: { events.append("error") }, delete: { XCTFail() }, close: { events.append("close") })
        XCTAssertEqual(events, ["close"])
        failure?()
        XCTAssertEqual(events, ["close", "error"])
    }

    func testUnchangedEmptyAndAbsentLinksChooseCorrectCallbacks() {
        var events: [String] = []
        for (current, selected) in [(link(), Set([group(1).id])), (link(), Set<PeerId>()), (nil, Set<PeerId>())] as [(ExportedChatFolderLink?, Set<PeerId>)] {
            folderSharingSaveLink(state: FolderSharingLinkState(filter: filter(), link: current, selected: selected), original: link(), edit: { _, _, _, _ in XCTFail() }, updated: { _, _ in XCTFail() }, success: { XCTFail() }, failure: { XCTFail() }, delete: { events.append("delete") }, close: { events.append("close") })
        }
        XCTAssertEqual(events, ["close", "delete"])
    }

    func testDeleteNotifiesParentBeforeClosing() {
        var events: [String] = []
        folderSharingDeletedLink(link(), updated: { original, updated in
            XCTAssertEqual(original, self.link())
            XCTAssertNil(updated)
            events.append("updated")
        }, close: { events.append("close") })
        XCTAssertEqual(events, ["updated", "close"])
    }

    func testLinkUpdateAndDeleteRetainListPositionAndMetadata() {
        var state = closureState()
        state.inviteLinks = [link("first"), link("second"), link("third")]
        state.creatingLink = true
        var replacement = link("second", title: "Renamed")
        replacement.isRevoked = true
        state.updateLink(link("second"), updated: replacement)
        XCTAssertEqual(state.inviteLinks, [link("first"), replacement, link("third")])
        XCTAssertFalse(state.creatingLink)
        state.updateLink(replacement, updated: nil)
        XCTAssertEqual(state.inviteLinks, [link("first"), link("third")])
        state.updateLink(link("missing"), updated: replacement)
        XCTAssertEqual(state.inviteLinks, [link("first"), link("third")])
    }

    func testJoinCompletionClosesThenNotifiesThenNavigates() {
        var events: [String] = []
        folderSharingJoinCompleted(close: { events.append("close") }, notify: { events.append("notify") }, navigate: { events.append("navigate") })
        XCTAssertEqual(events, ["close", "notify", "navigate"])
    }

    func testUpdatesJoinWaitsForRequestAndDismissClosesImmediately() {
        var events: [String] = []
        folderSharingApplyUpdates(hasSelectedToJoin: true, join: { events.append("join") }, dismiss: { XCTFail() }, close: { XCTFail() })
        XCTAssertEqual(events, ["join"])
        folderSharingApplyUpdates(hasSelectedToJoin: false, join: { XCTFail() }, dismiss: { events.append("dismiss") }, close: { events.append("close") })
        XCTAssertEqual(events, ["join", "dismiss", "close"])
    }

    func testRemovalRequiresConfirmationOnlyForSharedLinks() {
        var events: [String] = []
        var confirmed: (() -> Void)?
        folderSharingRemove(hasSharedLinks: true, confirm: { confirmed = $0; events.append("confirm") }, invoke: { events.append("remove") })
        XCTAssertEqual(events, ["confirm"])
        confirmed?()
        XCTAssertEqual(events, ["confirm", "remove"])
        folderSharingRemove(hasSharedLinks: false, confirm: { _ in XCTFail() }, invoke: { events.append("remove") })
        XCTAssertEqual(events, ["confirm", "remove", "remove"])
    }

    func testJoinErrorDispatchPreservesPremiumAndInactiveChannelBranches() {
        var events: [String] = []
        let errors: [JoinChatFolderLinkError] = [.dialogFilterLimitExceeded(limit: 10, premiumLimit: 20), .sharedFolderLimitExceeded(limit: 2, premiumLimit: 10), .tooManyChannels(limit: 100, premiumLimit: 200), .tooManyChannelsInAccount(limit: 500, premiumLimit: 1000), .generic]
        for error in errors {
            folderSharingProcessJoinError(error, premium: { events.append(String(describing: $0)) }, inactiveChannels: { events.append("inactive") }, unknown: { events.append("error") })
        }
        XCTAssertEqual(events, ["folders", "sharedFolders", "inactive", "channels", "error"])
    }
}

private final class Selection: FolderSharingPeerSelection {
    var selectedPeerIds: Set<PeerId> = []
    var toggled: [PeerId] = []
    var action: (PeerId, Int64?) -> Void = { _, _ in }

    func toggleSelection(_ peer: Peer) {
        toggled.append(peer.id)
        if !selectedPeerIds.insert(peer.id).inserted {
            selectedPeerIds.remove(peer.id)
        }
    }

    func toggleFromRow(_ peer: Peer) {
        toggleSelection(peer)
    }
}
