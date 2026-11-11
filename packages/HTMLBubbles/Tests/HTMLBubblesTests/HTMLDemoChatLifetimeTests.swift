import Cocoa
import XCTest
import Postbox
import TelegramCore
import SwiftSignalKit
import WidgetSandbox
import TwidgetRenderer
@testable import HTMLBubbles

final class HTMLDemoChatLifetimeTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        DemoFixtures.install()
    }

    private final class Weak<Value: AnyObject> {
        weak var value: Value?
        init(_ value: Value) { self.value = value }
    }

    private let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(987654))

    private func states(_ contents: HTMLDemoChatContents) -> [HTMLBubbleState] {
        var states: [HTMLBubbleState] = []
        let disposable = contents.historyView.start(next: { view, _ in
            states = view.entries.compactMap { entry in
                entry.message.attributes.compactMap { ($0 as? HTMLMessageAttribute)?.state }.first
            }
        })
        disposable.dispose()
        return states
    }

    private func pump(_ seconds: TimeInterval, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline, !condition() {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
    }

    @MainActor
    func testClosedGalleriesReleaseAllStatesWhileChatListCacheRemainsAlive() throws {
        let cache = HTMLDemoChatCache()
        for id in ["html-all-widgets", "html-all-widgets-webkit"] {
            let chat = try XCTUnwrap(HTMLDemoCatalog.chat(id))
            weak var closed: HTMLDemoChatContents?
            var released: [Weak<HTMLBubbleState>] = []
            autoreleasepool {
                let contents = cache.contents(chat: chat, accountPeerId: peerId)
                closed = contents
                released = states(contents).map(Weak.init)
                XCTAssertEqual(released.count, HTMLDemoCatalog.widgetFiles(.allWidgets).count)
                XCTAssertFalse(released.isEmpty)
            }
            pump(2) { closed == nil && released.allSatisfy { $0.value == nil } }
            withExtendedLifetime(cache) {
                XCTAssertNil(closed, id)
                XCTAssertTrue(released.allSatisfy { $0.value == nil }, id)
            }
        }
    }

    @MainActor
    func testGallerySharesOpenContentsAndReopensWithTheSameCorpus() throws {
        let cache = HTMLDemoChatCache()
        for id in ["html-all-widgets", "html-all-widgets-webkit"] {
            let chat = try XCTUnwrap(HTMLDemoCatalog.chat(id))
            var first: HTMLDemoChatContents? = cache.contents(chat: chat, accountPeerId: peerId)
            let previous = Weak(try XCTUnwrap(first))
            var sources: [String] = []
            autoreleasepool {
                let second = cache.contents(chat: chat, accountPeerId: peerId)
                XCTAssertTrue(first === second)
                sources = states(second).map { $0.source }
                first = nil
                XCTAssertTrue(previous.value === second)
            }
            XCTAssertNil(previous.value)
            let reopened = cache.contents(chat: chat, accountPeerId: peerId)
            XCTAssertEqual(states(reopened).map { $0.source }, sources)
            XCTAssertTrue(states(reopened).allSatisfy { $0.engine == chat.engine })
        }
    }

    @MainActor
    func testConversationAndGameHistorySurviveClosingWithoutCrossingAccounts() throws {
        let cache = HTMLDemoChatCache()
        let otherPeerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(987655))
        for preset in [nil, HTMLDemoPreset.voxelClash] {
            let chat = HTMLDemoChat(id: "lifetime-\(String(describing: preset))", title: "Lifetime", status: "", peer: HTMLDemoCatalog.makeUser(id: peerId, name: "Demo", isBot: true), engine: .litehtml, preset: preset)
            weak var previous: HTMLDemoChatContents?
            var previousStates: [Weak<HTMLBubbleState>] = []
            autoreleasepool {
                let contents = cache.contents(chat: chat, accountPeerId: peerId)
                previous = contents
                previousStates = states(contents).map(Weak.init)
            }
            XCTAssertNotNil(previous)
            XCTAssertFalse(previousStates.isEmpty)
            XCTAssertTrue(previousStates.allSatisfy { $0.value != nil })
            XCTAssertTrue(cache.contents(chat: chat, accountPeerId: peerId) === previous)
            XCTAssertFalse(cache.contents(chat: chat, accountPeerId: otherPeerId) === previous)
        }
    }

    @MainActor
    func testRepeatedGalleryCloseReleasesRenderedHostsSnapshotsAndPendingPreparation() throws {
        let cache = HTMLDemoChatCache()
        let chat = try XCTUnwrap(HTMLDemoCatalog.chat("html-all-widgets"))
        let files = HTMLDemoCatalog.widgetFiles(.allWidgets)
        let liveIndex = try XCTUnwrap(files.firstIndex { $0.name == "showcase/life/06-music-player.html" })
        let pendingIndex = try XCTUnwrap(files.firstIndex { $0.name == "showcase/commerce/02-product-configurator.html" })
        let appearance = HTMLBubbleAppearance(key: "gallery-lifetime", css: "", dark: false, incoming: true)
        let feed = HTMLTwidgetTableSpace.feed(for: .twidget)
        let liveBefore = feed.liveCount
        let snapshotsBefore = feed.snapshotBytes
        let preparedBefore = WidgetPreparer.outstandingCount
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 440, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.orderFrontRegardless()
        defer { window.close() }

        for cycle in 0..<10 {
            weak var closed: HTMLDemoChatContents?
            weak var live: WidgetHost?
            weak var renderer: LiteHTMLWidgetRenderer?
            weak var pending: WidgetPrepared?
            weak var pendingHost: WidgetHost?
            weak var pendingRenderer: LiteHTMLWidgetRenderer?
            weak var snapshot: AnyObject?
            var released: [Weak<HTMLBubbleState>] = []
            try autoreleasepool {
                let contents = cache.contents(chat: chat, accountPeerId: peerId)
                closed = contents
                let states = states(contents)
                released = states.map(Weak.init)
                let bubble = states[liveIndex].twidgetBubble(appearance: appearance, width: 440)
                let host = try XCTUnwrap(bubble.ensureHost())
                live = host
                renderer = try XCTUnwrap(host.rendererObject as? LiteHTMLWidgetRenderer)
                host.view.frame = window.contentView!.bounds
                window.contentView?.addSubview(host.view)
                defer { host.view.removeFromSuperview() }
                pump(10) { host.diagnostics.loaded && bubble.hostHasContent }
                XCTAssertTrue(host.diagnostics.loaded)
                XCTAssertTrue(bubble.hostHasContent)
                XCTAssertNil(host.diagnostics.dead)
                pump(2) {
                    bubble.takeSnapshot()
                    return bubble.snapshot != nil
                }
                snapshot = try XCTUnwrap(bubble.snapshot)
                XCTAssertGreaterThan(feed.snapshotBytes, snapshotsBefore)

                var prepared: WidgetPrepared?
                pump(5) {
                    prepared = states[pendingIndex].startTwidgetPrepare(appearance: appearance, width: 440)
                    return prepared != nil
                }
                let preparation = try XCTUnwrap(prepared)
                pending = preparation
                pendingHost = preparation.host
                pendingRenderer = try XCTUnwrap(preparation.host.rendererObject as? LiteHTMLWidgetRenderer)
                XCTAssertGreaterThan(WidgetPreparer.outstandingCount, preparedBefore)
            }
            pump(10) {
                closed == nil && live == nil && renderer == nil && pending == nil && pendingHost == nil && pendingRenderer == nil && snapshot == nil && released.allSatisfy { $0.value == nil }
            }
            withExtendedLifetime(cache) {
                XCTAssertNil(closed, "cycle \(cycle)")
                XCTAssertTrue(released.allSatisfy { $0.value == nil }, "cycle \(cycle)")
                XCTAssertNil(live, "cycle \(cycle)")
                XCTAssertNil(renderer, "cycle \(cycle)")
                XCTAssertNil(pending, "cycle \(cycle)")
                XCTAssertNil(pendingHost, "cycle \(cycle)")
                XCTAssertNil(pendingRenderer, "cycle \(cycle)")
                XCTAssertNil(snapshot, "cycle \(cycle)")
                XCTAssertEqual(feed.liveCount, liveBefore)
                XCTAssertEqual(feed.snapshotBytes, snapshotsBefore)
                XCTAssertEqual(WidgetPreparer.outstandingCount, preparedBefore)
            }
        }
    }
}
