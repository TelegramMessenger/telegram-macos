import XCTest

struct StarsAmount: Equatable {
    let value: Int64
}

class Peer {}

final class TelegramChannel: Peer {
    let isAdmin: Bool
    let sendPaidMessageStars: StarsAmount?

    init(price: Int64?, isAdmin: Bool = false) {
        self.isAdmin = isAdmin
        self.sendPaidMessageStars = price.map(StarsAmount.init)
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

final class ChatPresentationInterfaceState {
    let peer: Peer?
    let cachedData: CachedPeerData?
    let _sendPaidMessageStars: StarsAmount?

    init(peer: Peer? = nil, cachedData: CachedPeerData? = nil, sendPaidMessageStars: StarsAmount? = nil) {
        self.peer = peer
        self.cachedData = cachedData
        self._sendPaidMessageStars = sendPaidMessageStars
    }

    __GETTER__
    __METHODS__

    func copiedPrices() -> [StarsAmount?] {
        let copies: [() -> StarsAmount?] = [__COPIES__]
        return copies.map { $0() }
    }
}

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
