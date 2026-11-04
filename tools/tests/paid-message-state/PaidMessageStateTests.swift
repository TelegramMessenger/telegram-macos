import XCTest

struct StarsAmount: Equatable {
    let value: Int64
}

typealias PeerId = Int64

class Peer {
    let id: PeerId

    init(id: PeerId) {
        self.id = id
    }
}

final class TelegramChannel: Peer {
    let isAdmin: Bool
    let sendPaidMessageStars: StarsAmount?

    init(id: PeerId = 1, price: Int64?, isAdmin: Bool = false) {
        self.isAdmin = isAdmin
        self.sendPaidMessageStars = price.map(StarsAmount.init)
        super.init(id: id)
    }
}

class CachedPeerData {}

final class CachedUserData: CachedPeerData {
    let sendPaidMessageStars: StarsAmount?

    init(price: Int64?) {
        self.sendPaidMessageStars = price.map(StarsAmount.init)
    }
}

final class CachedChannelData: CachedPeerData {
    let sendPaidMessageStars: StarsAmount? = nil
}

enum FastSettings {
    static var confirmedPrices: [PeerId: Set<Int>] = [:]

    static func needConfirmPaid(_ peerId: PeerId, price: Int) -> Bool {
        return confirmedPrices[peerId]?.contains(price) == true
    }
}

final class ChatPresentationInterfaceState {
    let peer: Peer?
    let cachedData: CachedPeerData?
    let alwaysPaidMessage: Bool
    let _sendPaidMessageStars: StarsAmount?

    init(peer: Peer? = nil, cachedData: CachedPeerData? = nil, alwaysPaidMessage: Bool = false, sendPaidMessageStars: StarsAmount? = nil) {
        self.peer = peer
        self.cachedData = cachedData
        self.alwaysPaidMessage = alwaysPaidMessage
        self._sendPaidMessageStars = sendPaidMessageStars
    }

    __GETTER__
    __METHODS__

    func copiedPrices() -> [StarsAmount?] {
        let copies: [() -> StarsAmount?] = [__COPIES__]
        return copies.map { $0() }
    }
}

final class Window {}

final class InteractionContext {
    let window = Window()
}

struct Strings {
    let chatPayStarsPriceChangedTitle = "Price Changed"
    let chatPayStarsPriceChangedText = "Not sent"
}

func strings() -> Strings {
    return Strings()
}

var shownAlerts: [String] = []

func alert(for window: Window, header: String, info: String) {
    shownAlerts.append(header)
}

final class ChatInteraction {
    let peerId: PeerId
    let interactionContext = InteractionContext()
    private var _presentation: Swapper

    final class Swapper {
        var value: ChatPresentationInterfaceState
        init(_ value: ChatPresentationInterfaceState) { self.value = value }
        func swap(_ value: ChatPresentationInterfaceState) -> ChatPresentationInterfaceState {
            let previous = self.value
            self.value = value
            return previous
        }
    }

    var presentation: ChatPresentationInterfaceState { _presentation.value }

    init(peerId: PeerId, presentation: ChatPresentationInterfaceState) {
        self.peerId = peerId
        self._presentation = Swapper(presentation)
    }

    func update(_ f: (ChatPresentationInterfaceState) -> ChatPresentationInterfaceState) {
__UPDATE__
    }
}

__PRICE_GUARD__

final class Composer {
    var placeholderUpdates = 0

    func updatePlaceholder() {
        placeholderUpdates += 1
    }

    func notify(value: ChatPresentationInterfaceState, oldValue: ChatPresentationInterfaceState) {
        __REFRESH__
    }
}

final class PaidMessageStateTests: XCTestCase {
    func testChannelFeeRemovalAfterUnrelatedStateCopy() {
        let paid = ChatPresentationInterfaceState(peer: TelegramChannel(price: 400))
        let copied = paid.withUpdatedAlwaysPaidMessage(true)
        let free = copied.updatedPeer { _ in TelegramChannel(price: nil) }
        XCTAssertNil(free.sendPaidMessageStars)
        XCTAssertEqual(paid.sendPaidMessageStars?.value, 400)
    }

    func testChannelFeeChangesAndZero() {
        let state = ChatPresentationInterfaceState(peer: TelegramChannel(price: 400))
            .withUpdatedAlwaysPaidMessage(true)
        XCTAssertEqual(state.updatedPeer { _ in TelegramChannel(price: 200) }.sendPaidMessageStars?.value, 200)
        XCTAssertNil(state.updatedPeer { _ in TelegramChannel(price: 0) }.sendPaidMessageStars)
        XCTAssertNil(state.updatedPeer { _ in TelegramChannel(price: 400, isAdmin: true) }.sendPaidMessageStars)
    }

    func testUserFeeRemovalAndReinstatement() {
        let paid = ChatPresentationInterfaceState(cachedData: CachedUserData(price: 400))
            .withUpdatedAlwaysPaidMessage(true)
        let free = paid.withUpdatedCachedData(CachedUserData(price: nil))
        XCTAssertNil(free.sendPaidMessageStars)
        XCTAssertNil(paid.withUpdatedCachedData(CachedUserData(price: 0)).sendPaidMessageStars)
        XCTAssertEqual(free.withUpdatedCachedData(CachedUserData(price: 250)).sendPaidMessageStars?.value, 250)
    }

    func testExplicitOverrideSurvivesCopiesAndCanBeCleared() {
        let state = ChatPresentationInterfaceState(peer: TelegramChannel(price: 400))
            .withUpdatedSendPaidMessageStars(StarsAmount(value: 100))
            .withUpdatedAlwaysPaidMessage(true)
        XCTAssertEqual(state.sendPaidMessageStars?.value, 100)
        XCTAssertEqual(state.withUpdatedSendPaidMessageStars(nil).sendPaidMessageStars?.value, 400)
        let free = state.withUpdatedSendPaidMessageStars(StarsAmount(value: 0))
            .withUpdatedAlwaysPaidMessage(true)
        XCTAssertNil(free.sendPaidMessageStars)
    }

    func testEveryStateCopyPreservesOnlyExplicitOverride() {
        let paid = ChatPresentationInterfaceState(peer: TelegramChannel(price: 400))
        XCTAssertTrue(paid.copiedPrices().allSatisfy { $0 == nil })
        let explicit = paid.withUpdatedSendPaidMessageStars(StarsAmount(value: 100))
        XCTAssertTrue(explicit.copiedPrices().allSatisfy { $0?.value == 100 })
    }

    func testDontAskAgainDoesNotCarryOverToANewPrice() {
        FastSettings.confirmedPrices = [1: [400]]
        let interaction = ChatInteraction(peerId: 1, presentation: ChatPresentationInterfaceState(peer: TelegramChannel(price: 400)))
        interaction.update { $0.withUpdatedAlwaysPaidMessage(true) }
        XCTAssertTrue(interaction.presentation.alwaysPaidMessage)
        interaction.update { $0.updatedPeer { _ in TelegramChannel(price: 800) } }
        XCTAssertFalse(interaction.presentation.alwaysPaidMessage)
        interaction.update { $0.updatedPeer { _ in TelegramChannel(price: nil) } }
        XCTAssertFalse(interaction.presentation.alwaysPaidMessage)
        interaction.update { $0.updatedPeer { _ in TelegramChannel(price: 400) } }
        XCTAssertTrue(interaction.presentation.alwaysPaidMessage)
    }

    func testUnrelatedUpdateKeepsSessionDontAskAgain() {
        FastSettings.confirmedPrices = [:]
        let interaction = ChatInteraction(peerId: 1, presentation: ChatPresentationInterfaceState(peer: TelegramChannel(price: 400)))
        interaction.update { $0.withUpdatedAlwaysPaidMessage(true) }
        interaction.update { $0.withUpdatedCachedData(nil) }
        XCTAssertTrue(interaction.presentation.alwaysPaidMessage)
    }

    func testDontAskAgainUsesTheStatePeerWhenTheInteractionHasNoPeer() {
        FastSettings.confirmedPrices = [7: [400]]
        let interaction = ChatInteraction(peerId: 0, presentation: ChatPresentationInterfaceState())
        interaction.update { $0.updatedPeer { _ in TelegramChannel(id: 7, price: 400) }.withUpdatedAlwaysPaidMessage(true) }
        XCTAssertTrue(interaction.presentation.alwaysPaidMessage)
        interaction.update { $0.updatedPeer { _ in TelegramChannel(id: 8, price: 400) } }
        XCTAssertFalse(interaction.presentation.alwaysPaidMessage)
    }

    func testConfirmationForAStalePriceIsRejectedWithAnAlert() {
        shownAlerts = []
        let interaction = ChatInteraction(peerId: 1, presentation: ChatPresentationInterfaceState(peer: TelegramChannel(price: 400)))
        XCTAssertTrue(chatPaidMessagePriceIsCurrent(interaction, StarsAmount(value: 400)))
        XCTAssertTrue(shownAlerts.isEmpty)
        interaction.update { $0.updatedPeer { _ in TelegramChannel(price: 800) } }
        XCTAssertFalse(chatPaidMessagePriceIsCurrent(interaction, StarsAmount(value: 400)))
        interaction.update { $0.updatedPeer { _ in TelegramChannel(price: nil) } }
        XCTAssertFalse(chatPaidMessagePriceIsCurrent(interaction, StarsAmount(value: 400)))
        XCTAssertEqual(shownAlerts, ["Price Changed", "Price Changed"])
    }

    func testComposerRefreshesOnFeeRemovalChangeAndReinstatement() {
        let composer = Composer()
        let paid = ChatPresentationInterfaceState(peer: TelegramChannel(price: 400))
        let free = ChatPresentationInterfaceState(peer: TelegramChannel(price: nil))
        let changed = ChatPresentationInterfaceState(peer: TelegramChannel(price: 200))
        composer.notify(value: free, oldValue: paid)
        composer.notify(value: changed, oldValue: free)
        composer.notify(value: paid, oldValue: changed)
        XCTAssertEqual(composer.placeholderUpdates, 3)
        composer.notify(value: paid, oldValue: paid)
        XCTAssertEqual(composer.placeholderUpdates, 3)
    }
}
