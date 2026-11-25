import Foundation
import XCTest
import SwiftSignalKit

struct PeerId: Equatable {
    let rawValue: Int64
    init(_ rawValue: Int64) { self.rawValue = rawValue }
}
struct MessageId: Equatable {
    typealias Namespace = Int32
    var peerId: PeerId = PeerId(1)
    let namespace: Namespace
    let id: Int
}
struct MessageIndex: Comparable {
    let id: MessageId
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.id.id < rhs.id.id }
}
protocol Peer {}
enum Participation { case member, left, kicked }
struct ChannelFlags: OptionSet {
    let rawValue: Int
    static let isMonoforum = ChannelFlags(rawValue: 1)
}
struct TelegramChannel: Peer {
    let participationStatus: Participation
    var flags: ChannelFlags = []
}
struct User: Peer {}
struct CachedChannelData {
    var boostsToUnrestrict: Int32?
    var appliedBoosts: Int32?
}
class PostboxView: Equatable {
    static func == (lhs: PostboxView, rhs: PostboxView) -> Bool { lhs === rhs }
}
final class PeerView: PostboxView {
    let peers: [Int: Peer]
    init(_ peer: Peer?) { peers = peer.map { [1: $0] } ?? [:] }
}
enum ChatLocation: Equatable {
    case peer(Int)
    case thread(Int)
    var peerId: Int {
        switch self { case let .peer(id), let .thread(id): return id }
    }
}
final class Window { var hasModal = false }
func hasModals(_ window: Window) -> Bool { window.hasModal }
struct ChatUIHooks {
    static let shared = ChatUIHooks()
    func clearNotifies(_ peerId: Int, _ messageId: MessageId) {}
}
final class Context {
    let window = Window()
    var peer: Peer?
    var attempts: [Int] = []
    var reads: [Int] = []
    func applyMaxReadIndex(for location: ChatLocation, contextHolder: Int, messageIndex: MessageIndex) {
        attempts.append(messageIndex.id.id)
        if case .peer = location, let channel = peer as? TelegramChannel,
           channel.participationStatus != .member, !channel.flags.contains(.isMonoforum) {
            return
        }
        reads.append(messageIndex.id.id)
    }
}

__HELPER__

final class Harness {
    let context = Context()
    let maxVisibleIncomingMessageIndex = ValuePromise<MessageIndex>(ignoreRepeated: true)
    let peerView = Promise<PostboxView?>()
    let peerUpdates = ValuePromise<PostboxView?>()
    let location = ValuePromise<ChatLocation>(.peer(1), ignoreRepeated: true)
    let readability = ValuePromise<Bool>(true, ignoreRepeated: true)
    let readHistoryDisposable = MetaDisposable()
    var chatLocationValue: Signal<ChatLocation, NoError> { location.get() }
    init(peer: Peer?, location: ChatLocation = .peer(1), canRead: Bool = true, hasModal: Bool = false) {
        context.peer = peer
        context.window.hasModal = hasModal
        self.location.set(location)
        readability.set(canRead)
        peerUpdates.set(PeerView(peer))
        peerView.set(peerUpdates.get())
        let context = self.context
        let canRead = readability.get()
        let chatLocationContextHolder = 0
__IMPLEMENTATION__
    }
    func show(_ id: Int, peerId: PeerId = PeerId(1)) {
        maxVisibleIncomingMessageIndex.set(MessageIndex(id: MessageId(peerId: peerId, namespace: 0, id: id)))
        settle()
    }
    func update(_ peer: Peer?) {
        context.peer = peer
        peerUpdates.set(PeerView(peer))
        settle()
    }
    func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    deinit { readHistoryDisposable.dispose() }
}

final class ReadHistoryTests: XCTestCase {
    func testNonMemberDoesNotConsumeAReadAttempt() {
        let h = Harness(peer: TelegramChannel(participationStatus: .left))
        h.show(50)
        XCTAssertEqual(h.context.attempts, [])
        XCTAssertEqual(h.context.reads, [])
    }
    func testJoiningReadsTheAlreadyVisiblePostWithoutScrolling() {
        let h = Harness(peer: TelegramChannel(participationStatus: .left))
        h.show(50)
        h.update(TelegramChannel(participationStatus: .member))
        XCTAssertEqual(h.context.reads, [50])
    }
    func testLeavingAndRejoiningRestartsVisibleReading() {
        let h = Harness(peer: TelegramChannel(participationStatus: .member))
        h.show(50)
        h.update(TelegramChannel(participationStatus: .left))
        h.show(60)
        h.update(TelegramChannel(participationStatus: .member))
        XCTAssertEqual(h.context.reads, [50, 60])
    }
    func testJoinedChannelDoesNotRepeatOrMoveBackwards() {
        let h = Harness(peer: TelegramChannel(participationStatus: .member))
        h.show(50)
        h.update(TelegramChannel(participationStatus: .member))
        h.show(40)
        h.show(60)
        XCTAssertEqual(h.context.reads, [50, 60])
    }
    func testCommentThreadStillReadsWhenChannelIsNotJoined() {
        let h = Harness(peer: TelegramChannel(participationStatus: .left), location: .thread(1))
        h.show(50)
        XCTAssertEqual(h.context.reads, [50])
    }
    func testMonoforumStillReadsWhenChannelIsNotJoined() {
        let h = Harness(peer: TelegramChannel(participationStatus: .left, flags: [.isMonoforum]))
        h.show(50)
        XCTAssertEqual(h.context.reads, [50])
    }
    func testEmptyPeerIndexIsNotRead() {
        let h = Harness(peer: TelegramChannel(participationStatus: .member))
        h.show(0, peerId: PeerId(0))
        XCTAssertEqual(h.context.reads, [])
        h.show(50)
        XCTAssertEqual(h.context.reads, [50])
    }
    func testOrdinaryPeerStillReads() {
        let h = Harness(peer: User())
        h.show(50)
        XCTAssertEqual(h.context.reads, [50])
    }
    func testLockOrInactiveWindowDefersReading() {
        let h = Harness(peer: User(), canRead: false)
        h.show(50)
        XCTAssertEqual(h.context.attempts, [])
        h.readability.set(true)
        h.settle()
        XCTAssertEqual(h.context.reads, [50])
    }
    func testModalDoesNotConsumeTheReadBeforeAResumedUpdate() {
        let h = Harness(peer: User(), hasModal: true)
        h.show(50)
        h.context.window.hasModal = false
        h.update(User())
        XCTAssertEqual(h.context.reads, [50])
    }
    func testKickedChannelDoesNotRead() {
        let h = Harness(peer: TelegramChannel(participationStatus: .kicked))
        h.show(50)
        XCTAssertEqual(h.context.attempts, [])
    }
    func testUnknownPeerKeepsExistingCoreBehavior() {
        let h = Harness(peer: nil)
        h.show(50)
        XCTAssertEqual(h.context.reads, [50])
    }
}
