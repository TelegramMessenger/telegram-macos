import Foundation
import XCTest

struct InputState {
    var inputText = "draft"
    var attributes: [Int] = []
    var selectionRange = 0..<0
}
struct ReplyMessage {
    var threadId: Int64?
}
struct InterfaceState {
    var editState: Int?
    var replyMessageId: Int?
    var replyMessage: ReplyMessage?
    var forwardMessageIds: [Int] = []
    var hideSendersName = false
    var hideCaptions = false
    var composeDisableUrlPreview: String?
    var linkBelowMessage = false
    var largeMedia: Bool?
    var messageEffect: Int?
    var suggestPost: Int?
    var scrollPosition = 0
}
struct SlowMode {
    var hasLocked = false
    var countdown = 0
}
struct ChatPresentationInterfaceState {
    var chatLocation = 0
    var chatMode = 0
    var state = 0
    var currentSendAsPeerId: Int?
    var sendPaidMessageStars: Int?
    var isMonoforum = false
    var threadedBot = false
    var slowMode: SlowMode? = SlowMode()
    var slowModeMultipleLocked = false
    var effectiveInput = InputState()
    var interfaceState = InterfaceState()
    var presence = 0
}

__DEFERRED_SOURCE__

__RICH_STORE__

private typealias InstantPage = Int
private struct DraftAccountId { let int64: Int64 }
private struct DraftAccount { let id: DraftAccountId }
private struct DraftContext { let account: DraftAccount }
private struct DraftPeerId {
    let value: Int64
    func toInt64() -> Int64 { value }
}
private struct DraftLocation { let threadId: Int64? }
private enum DraftKind { case welcomeMessages }
private struct DraftContents { let kind: DraftKind }
private struct DraftMode { let customChatContents: DraftContents?; var customChatLink: DraftContents? = nil }
private final class ComposerPreparationFixture { var resets = 0; func reset() { resets += 1 } }
private final class ChatInteraction {
    let composerForwardPreparation = ComposerPreparationFixture()
    private static var nextAccountId: Int64 = 100
    private var deferredSendRevision = UUID()
    var presentation = ChatPresentationInterfaceState()
    let context: DraftContext
    let peerId: DraftPeerId
    let chatLocation: DraftLocation
    let mode: DraftMode
    init(accountId: Int64? = nil, peerId: Int64 = 1, threadId: Int64? = nil, isWelcome: Bool = false) {
        Self.nextAccountId += 1
        context = DraftContext(account: DraftAccount(id: DraftAccountId(int64: accountId ?? Self.nextAccountId)))
        self.peerId = DraftPeerId(value: peerId)
        chatLocation = DraftLocation(threadId: threadId)
        mode = DraftMode(customChatContents: isWelcome ? DraftContents(kind: .welcomeMessages) : nil)
    }
__RICH_KEY__
    var richTextDraft: Int? { Self.globalRichTextDrafts.value(for: richTextDraftKey) }
__DEFERRED_METHODS__
    func update(_ change: (inout ChatPresentationInterfaceState) -> Void) {
        let oldValue = presentation
        change(&presentation)
__UPDATE_INVALIDATION__
    }
    func setRichTextDraft(_ page: Int?) {
__RICH_INVALIDATION__
    }
}

private typealias InteractionFixture = ChatInteraction

final class DeferredSendTests: XCTestCase {
    func testEachSendRelevantChangeInvalidatesPendingAction() {
        let changes: [(String, (inout ChatPresentationInterfaceState) -> Void)] = [
            ("location", { $0.chatLocation = 1 }),
            ("mode", { $0.chatMode = 1 }),
            ("state", { $0.state = 1 }),
            ("send as", { $0.currentSendAsPeerId = 1 }),
            ("price", { $0.sendPaidMessageStars = 1 }),
            ("monoforum", { $0.isMonoforum = true }),
            ("bot thread", { $0.threadedBot = true }),
            ("slow mode", { $0.slowMode?.hasLocked = true }),
            ("multiple locked", { $0.slowModeMultipleLocked = true }),
            ("text", { $0.effectiveInput.inputText = "changed" }),
            ("format", { $0.effectiveInput.attributes = [1] }),
            ("edit session", { $0.interfaceState.editState = 1 }),
            ("reply", { $0.interfaceState.replyMessageId = 1 }),
            ("reply thread", { $0.interfaceState.replyMessage = ReplyMessage(threadId: 1) }),
            ("forwards", { $0.interfaceState.forwardMessageIds = [1] }),
            ("sender visibility", { $0.interfaceState.hideSendersName = true }),
            ("caption visibility", { $0.interfaceState.hideCaptions = true }),
            ("preview", { $0.interfaceState.composeDisableUrlPreview = "link" }),
            ("preview position", { $0.interfaceState.linkBelowMessage = true }),
            ("preview size", { $0.interfaceState.largeMedia = true }),
            ("effect", { $0.interfaceState.messageEffect = 1 }),
            ("suggestion", { $0.interfaceState.suggestPost = 1 })
        ]
        for (name, change) in changes {
            let fixture = InteractionFixture()
            let action = fixture.captureDeferredSendAction()
            fixture.update(change)
            XCTAssertFalse(action.takeIfCurrent(), name)
        }
    }

    func testRestoringOriginalDraftOrLocationDoesNotReviveAction() {
        for location in [false, true] {
            let fixture = InteractionFixture()
            let action = fixture.captureDeferredSendAction()
            let original = fixture.presentation
            fixture.update {
                if location { $0.chatLocation += 1 } else { $0.effectiveInput.inputText = "changed" }
            }
            fixture.update { $0 = original }
            XCTAssertFalse(action.takeIfCurrent())
        }
    }

    func testUnrelatedUiUpdatesAndCursorMovementKeepActionValid() {
        let fixture = InteractionFixture()
        let action = fixture.captureDeferredSendAction()
        fixture.update {
            $0.presence += 1
            $0.interfaceState.scrollPosition += 1
            $0.effectiveInput.selectionRange = 1..<1
            $0.slowMode?.countdown += 1
        }
        XCTAssertTrue(action.takeIfCurrent())
        XCTAssertFalse(action.takeIfCurrent())
    }

    func testRichDraftChangeAndRestoreInvalidatesAction() {
        let fixture = InteractionFixture()
        fixture.setRichTextDraft(1)
        let action = fixture.captureDeferredSendAction()
        fixture.setRichTextDraft(2)
        fixture.setRichTextDraft(1)
        XCTAssertFalse(action.takeIfCurrent())
    }

    func testEquivalentRichDraftRefreshKeepsActionValid() {
        let fixture = InteractionFixture()
        fixture.setRichTextDraft(1)
        let action = fixture.captureDeferredSendAction()
        fixture.setRichTextDraft(1)
        XCTAssertTrue(action.takeIfCurrent())
    }

    func testExternalRichDraftChangeIsCheckedAtDelivery() {
        let fixture = InteractionFixture()
        let action = fixture.captureDeferredSendAction()
        let otherWindow = InteractionFixture(accountId: fixture.context.account.id.int64)
        otherWindow.setRichTextDraft(3)
        XCTAssertFalse(action.takeIfCurrent())
    }

    func testCleanupInvalidatesEvenAnUnchangedDraft() {
        let fixture = InteractionFixture()
        let action = fixture.captureDeferredSendAction()
        fixture.invalidateDeferredSendActions()
        XCTAssertFalse(action.takeIfCurrent())
    }

    func testActionDoesNotKeepItsOwnerAlive() {
        var fixture: InteractionFixture? = InteractionFixture()
        weak var owner = fixture
        let action = fixture!.captureDeferredSendAction()
        fixture = nil
        XCTAssertNil(owner)
        XCTAssertFalse(action.takeIfCurrent())
    }

    func testInvalidatedCallbackRunsOnceAndCannotReviveOldAction() {
        var current = false
        var invalidations = 0
        let action = ChatDeferredSendAction { current }
        XCTAssertFalse(action.takeIfCurrent(onInvalidated: { invalidations += 1 }))
        current = true
        XCTAssertFalse(action.takeIfCurrent(onInvalidated: { invalidations += 1 }))
        XCTAssertEqual(invalidations, 1)
    }

    func testDuplicateAcceptedCallbackDoesNotDiscardSubmission() {
        var current = true
        var discards = 0
        let action = ChatDeferredSendAction { current }
        XCTAssertTrue(action.takeIfCurrent(onInvalidated: { discards += 1 }))
        current = false
        XCTAssertFalse(action.takeIfCurrent(onInvalidated: { discards += 1 }))
        XCTAssertEqual(discards, 0)
    }

    func testFreshActionAfterDraftChangeCanStillSend() {
        let fixture = InteractionFixture()
        let old = fixture.captureDeferredSendAction()
        fixture.update { $0.effectiveInput.inputText = "new draft" }
        let fresh = fixture.captureDeferredSendAction()
        XCTAssertFalse(old.takeIfCurrent())
        XCTAssertTrue(fresh.takeIfCurrent())
    }

    func testOtherWindowChangingAndClearingEmptyDraftInvalidatesOriginalAction() {
        let fixture = InteractionFixture()
        let otherWindow = InteractionFixture(accountId: fixture.context.account.id.int64)
        let action = fixture.captureDeferredSendAction()
        otherWindow.setRichTextDraft(1)
        otherWindow.setRichTextDraft(nil)
        XCTAssertNil(fixture.richTextDraft)
        XCTAssertFalse(action.takeIfCurrent())
    }

    func testDifferentAccountCannotReadClearOrInvalidateDraft() {
        let first = InteractionFixture()
        let second = InteractionFixture()
        first.setRichTextDraft(11)
        second.setRichTextDraft(22)
        let action = first.captureDeferredSendAction()
        second.setRichTextDraft(nil)
        XCTAssertEqual(first.richTextDraft, 11)
        XCTAssertNil(second.richTextDraft)
        XCTAssertTrue(action.takeIfCurrent())
    }

    func testRecreatedInteractionSharesOnlyMatchingAccountPeerThreadAndKind() {
        let original = InteractionFixture(peerId: 7, threadId: 8, isWelcome: true)
        original.setRichTextDraft(11)
        let accountId = original.context.account.id.int64
        let matching = InteractionFixture(accountId: accountId, peerId: 7, threadId: 8, isWelcome: true)
        let otherPeer = InteractionFixture(accountId: accountId, peerId: 9, threadId: 8, isWelcome: true)
        let otherThread = InteractionFixture(accountId: accountId, peerId: 7, threadId: 9, isWelcome: true)
        let ordinary = InteractionFixture(accountId: accountId, peerId: 7, threadId: 8)
        XCTAssertEqual(matching.richTextDraft, 11)
        XCTAssertNil(otherPeer.richTextDraft)
        XCTAssertNil(otherThread.richTextDraft)
        XCTAssertNil(ordinary.richTextDraft)
    }

    func testEquivalentWriteFromOtherWindowKeepsPendingActionValid() {
        let fixture = InteractionFixture()
        fixture.setRichTextDraft(1)
        let otherWindow = InteractionFixture(accountId: fixture.context.account.id.int64)
        let action = fixture.captureDeferredSendAction()
        otherWindow.setRichTextDraft(1)
        XCTAssertTrue(action.takeIfCurrent())
    }

    func testValidationCannotReenterAndConsumeActionTwice() {
        var action: ChatDeferredSendAction!
        var validations = 0
        action = ChatDeferredSendAction {
            validations += 1
            XCTAssertFalse(action.takeIfCurrent())
            return true
        }
        XCTAssertTrue(action.takeIfCurrent())
        XCTAssertFalse(action.takeIfCurrent())
        XCTAssertEqual(validations, 1)
        action = nil
    }
}


private final class SendCallbackFixture {
    var sends = 0
    func dateSelected(_ deferredSendAction: ChatDeferredSendAction?) {
        __DATE_CALLBACK_GUARD__
        sends += 1
    }
    func confirmed(_ confirmationAction: ChatDeferredSendAction) {
        __CONFIRMATION_GUARD__
        sends += 1
    }
}

final class DeferredSendCallbackTests: XCTestCase {
    func testStaleDateCannotSend() {
        let interaction = InteractionFixture()
        let callback = SendCallbackFixture()
        let action = interaction.captureDeferredSendAction()
        interaction.update { $0.interfaceState.replyMessageId = 9 }
        callback.dateSelected(action)
        callback.dateSelected(action)
        XCTAssertEqual(callback.sends, 0)
    }

    func testDuplicateDateDoesNotSendAgain() {
        let interaction = InteractionFixture()
        let callback = SendCallbackFixture()
        let action = interaction.captureDeferredSendAction()
        callback.dateSelected(action)
        interaction.update { $0.effectiveInput.inputText = "next message" }
        callback.dateSelected(action)
        XCTAssertEqual(callback.sends, 1)
    }

    func testDraftChangedDuringConfirmationCannotSend() {
        let interaction = InteractionFixture()
        let callback = SendCallbackFixture()
        let action = interaction.captureDeferredSendAction()
        interaction.update { $0.effectiveInput.inputText = "changed after date selection" }
        callback.confirmed(action)
        XCTAssertEqual(callback.sends, 0)
    }

    func testDuplicateConfirmationDoesNotSendAgain() {
        let interaction = InteractionFixture()
        let callback = SendCallbackFixture()
        let action = interaction.captureDeferredSendAction()
        callback.confirmed(action)
        callback.confirmed(action)
        XCTAssertEqual(callback.sends, 1)
    }
}
