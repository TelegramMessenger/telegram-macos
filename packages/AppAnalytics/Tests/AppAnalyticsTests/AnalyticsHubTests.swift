import XCTest
import TelegramCore
import TGUIKit
@testable import AppAnalytics

private final class SampleController: ViewController {
}

private final class TaggedController: ViewController {
}

final class AnalyticsHubTests: XCTestCase {
    private let owner = NSObject()
    private var now: TimeInterval = 0
    private var sent: [(String, [String: JSON])] = []

    private func makeHub() -> Analytics {
        let hub = Analytics(clock: { [unowned self] in self.now })
        hub.setSink({ [unowned self] type, data in
            if case let .dictionary(values) = data {
                self.sent.append((type, values))
            }
        }, owner: owner)
        hub.isEnabled = true
        return hub
    }

    private func scope(_ hub: Analytics) -> AnalyticsScope? {
        return hub.policy.makeScope(owner: owner, privacy: .ordinary)
    }

    override func setUp() {
        super.setUp()
        now = 0
        sent = []
    }

    func testDisabledHubSendsNothing() {
        let hub = makeHub()
        hub.isEnabled = false
        hub.send(AnalyticsEvents.appForeground(), scope: scope(hub))
        hub.screens.didAppear(SampleController().analytics(.chatList))
        XCTAssertTrue(sent.isEmpty)
        hub.isEnabled = true
        hub.send(AnalyticsEvents.appForeground(), scope: scope(hub))
        XCTAssertEqual(sent.map { $0.0 }, ["app.foreground"])
    }

    func testEventsCarryCommonParamsAndOrderedSeq() {
        let hub = makeHub()
        hub.setLayout(.wide)
        hub.send(AnalyticsEvents.appForeground(), scope: scope(hub))
        hub.send(AnalyticsEvents.chatMessageSend(kind: .text, peerType: .user, hasReply: true), scope: scope(hub))
        XCTAssertEqual(sent.map { $0.0 }, ["app.foreground", "chat.message.send"])
        XCTAssertEqual(sent[0].1["seq"], .number(0))
        XCTAssertEqual(sent[1].1["seq"], .number(1))
        XCTAssertEqual(sent[1].1["layout"], .string("wide"))
        XCTAssertEqual(sent[1].1["platform"], .string("macos"))
        XCTAssertEqual(sent[1].1["kind"], .string("text"))
        XCTAssertEqual(sent[1].1["has_reply"], .bool(true))
        XCTAssertNil(sent[1].1["scheduled"])
        XCTAssertEqual(sent[0].1["session_id"], sent[1].1["session_id"])
    }

    func testNewSessionResetsSeqAndId() {
        let hub = makeHub()
        hub.send(AnalyticsEvents.appForeground(), scope: scope(hub))
        hub.startSession()
        hub.send(AnalyticsEvents.appForeground(), scope: scope(hub))
        XCTAssertEqual(sent[1].1["seq"], .number(0))
        XCTAssertNotEqual(sent[0].1["session_id"], sent[1].1["session_id"])
    }

    func testRecommendationSelectionsContainOnlyReviewedCategories() {
        let hub = makeHub()
        let grant = scope(hub)
        for kind in [AnalyticsEvents.PeerInfoRecommendationSelectKind.channel, .bot] {
            for selection in [AnalyticsEvents.PeerInfoRecommendationSelectSelection.peer, .premium] {
                let event = AnalyticsEvents.peerInfoRecommendationSelect(kind: kind, selection: selection)
                XCTAssertEqual(event.params, ["kind": .string(kind.rawValue), "selection": .string(selection.rawValue)])
                hub.send(event, scope: grant)
            }
        }
        XCTAssertEqual(sent.count, 4)
        XCTAssertTrue(sent.allSatisfy { $0.0 == "peer_info.recommendation.select" })
    }

    func testRecommendationSelectionsRejectIdentifiersAndInvalidCategories() {
        let hub = makeHub()
        let grant = scope(hub)
        let valid = AnalyticsEvents.peerInfoRecommendationSelect(kind: .channel, selection: .peer)
        for key in ["ref_channel_id", "open_channel_id", "ref_bot_id", "open_bot_id", "username", "rank"] {
            var params = valid.params
            params[key] = .string("123")
            hub.sendRaw(type: valid.name.rawValue, data: .dictionary(params), scope: grant)
        }
        for params: [String: JSON] in [[:], ["kind": .string("channel")], ["kind": .string("group"), "selection": .string("peer")], ["kind": .string("bot"), "selection": .string("purchase")]] {
            hub.sendRaw(type: valid.name.rawValue, data: .dictionary(params), scope: grant)
        }
        XCTAssertTrue(sent.isEmpty)
    }

    func testRecommendationSelectionsStaySilentForExcludedRevokedAndForeignOrigins() {
        let hub = makeHub()
        var constructed = 0
        func event() -> AnalyticsEvent {
            constructed += 1
            return AnalyticsEvents.peerInfoRecommendationSelect(kind: .bot, selection: .peer)
        }
        for privacy in [AnalyticsPrivacy.excluded, .unresolved] {
            let origin = hub.captureContext(owner: owner, privacy: privacy)
            hub.send(event(), scope: origin.scope)
        }
        let grant = scope(hub)
        hub.isEnabled = false
        hub.send(event(), scope: grant)
        hub.isEnabled = true
        hub.send(event(), scope: grant)
        let current = scope(hub)
        let other = NSObject()
        let foreign = hub.captureContext(owner: other, privacy: .ordinary, inherited: hub.captureContext(owner: owner, privacy: .ordinary))
        hub.send(event(), scope: foreign.scope)
        current?.exclude()
        hub.send(event(), scope: current)
        XCTAssertEqual(constructed, 0)
        XCTAssertTrue(sent.isEmpty)
    }

    func testSavedTagEditSelectionContainsOnlyItsEntryCategory() {
        let hub = makeHub()
        let grant = scope(hub)
        for entry in [AnalyticsEvents.ChatSavedTagEditSelectEntry.reactionMenu, .searchTagMenu, .accessibility] {
            let event = AnalyticsEvents.chatSavedTagEditSelect(entry: entry)
            XCTAssertEqual(event.params, ["entry": .string(entry.rawValue)])
            hub.send(event, scope: grant)
        }
        XCTAssertEqual(sent.count, 3)
        XCTAssertTrue(sent.allSatisfy { $0.0 == "chat.saved_tag.edit.select" })
    }

    func testSavedTagEditSelectionRejectsContentIdentityAndOutcomes() {
        let hub = makeHub()
        let grant = scope(hub)
        let valid = AnalyticsEvents.chatSavedTagEditSelect(entry: .reactionMenu)
        for key in ["label", "title", "reaction", "custom_emoji_id", "message_id", "peer_id", "result", "success", "is_bot"] {
            var params = valid.params
            params[key] = .string("value")
            hub.sendRaw(type: valid.name.rawValue, data: .dictionary(params), scope: grant)
        }
        for params: [String: JSON] in [[:], ["entry": .string("keyboard")], ["entry": .string("save")], ["entry": .bool(true)]] {
            hub.sendRaw(type: valid.name.rawValue, data: .dictionary(params), scope: grant)
        }
        XCTAssertTrue(sent.isEmpty)
    }

    func testSavedTagEditSelectionDeniesPayloadConstructionWithoutEligibleOrigin() {
        let hub = makeHub()
        var constructed = 0
        func event() -> AnalyticsEvent {
            constructed += 1
            return AnalyticsEvents.chatSavedTagEditSelect(entry: .accessibility)
        }
        hub.send(event(), scope: nil)
        for privacy in [AnalyticsPrivacy.excluded, .unresolved] {
            hub.send(event(), scope: hub.captureContext(owner: owner, privacy: privacy).scope)
        }
        let grant = scope(hub)
        hub.isEnabled = false
        hub.send(event(), scope: grant)
        hub.isEnabled = true
        hub.send(event(), scope: grant)
        let current = scope(hub)
        let other = NSObject()
        let foreign = hub.captureContext(owner: other, privacy: .ordinary, inherited: hub.captureContext(owner: owner, privacy: .ordinary))
        hub.send(event(), scope: foreign.scope)
        current?.exclude()
        hub.send(event(), scope: current)
        let publicContext = hub.captureContext(owner: owner, privacy: .ordinary)
        let privatePresentation = hub.captureContext(owner: owner, privacy: .excluded).beginPresentation()
        hub.send(event(), scope: publicContext.scope)
        privatePresentation.end()
        XCTAssertEqual(constructed, 0)
        XCTAssertTrue(sent.isEmpty)
    }

    func testNothingIsSentWithoutASink() {
        let hub = Analytics(clock: { 0 })
        hub.send(AnalyticsEvents.appForeground(), scope: scope(hub))
        hub.setSink({ [unowned self] type, _ in self.sent.append((type, [:])) }, owner: owner)
        hub.isEnabled = true
        hub.send(AnalyticsEvents.appBackground(durationMs: 10), scope: scope(hub))
        XCTAssertEqual(sent.map { $0.0 }, ["app.background"])
    }

    func testScreensShowAndHideWithSourceAndDuration() {
        let hub = makeHub()
        let list = SampleController()
        list.analyticsScope = scope(hub)
        list.analyticsScreen = .chatList
        let chat = TaggedController()
        chat.analyticsScope = scope(hub)
        chat.analytics(.chat, peer: .group)

        hub.screens.didAppear(list)
        now = 1
        hub.screens.didAppear(chat)
        hub.screens.didAppear(chat)
        now = 3.5
        hub.screens.didDisappear(chat)
        hub.screens.didDeinit(ObjectIdentifier(list))

        XCTAssertEqual(sent.map { $0.0 }, ["screen.show", "screen.show", "screen.hide", "screen.hide"])
        XCTAssertEqual(sent[0].1["screen"], .string("chat_list"))
        XCTAssertNil(sent[0].1["source"])
        XCTAssertEqual(sent[1].1["screen"], .string("chat"))
        XCTAssertEqual(sent[1].1["source"], .string("chat_list"))
        XCTAssertEqual(sent[1].1["peer_type"], .string("group"))
        XCTAssertEqual(sent[2].1["duration_ms"], .number(2500))
        XCTAssertEqual(sent[3].1["screen"], .string("chat_list"))
        XCTAssertNil(hub.screens.current)
    }

    func testRetaggingAVisibleControllerStartsANewScreen() {
        let hub = makeHub()
        let controller = SampleController()
        controller.analyticsScope = scope(hub)
        controller.analyticsScreen = .chat
        hub.screens.didAppear(controller)
        controller.analyticsScreen = .chatThread
        hub.screens.show(ObjectIdentifier(controller), screen: .chatThread, scope: controller.analyticsScope)
        XCTAssertEqual(sent.map { $0.0 }, ["screen.show", "screen.hide", "screen.show"])
        XCTAssertEqual(sent[2].1["screen"], .string("chat.thread"))
    }

    func testUntaggedUnknownControllerIsIgnored() {
        let hub = makeHub()
        hub.screens.didAppear(SampleController())
        XCTAssertTrue(sent.isEmpty)
    }

    func testClassTableResolvesSingleScreenControllers() {
        XCTAssertFalse(AnalyticsCoverage.screenForClass.isEmpty)
        for (_, screen) in AnalyticsCoverage.screenForClass {
            XCTAssertNotNil(AnalyticsScreen(rawValue: screen.rawValue))
        }
    }

    func testBuckets() {
        XCTAssertEqual(AnalyticsValues.Count(bucketing: 1), ._1)
        XCTAssertEqual(AnalyticsValues.Count(bucketing: 5), ._2_5)
        XCTAssertEqual(AnalyticsValues.Count(bucketing: 6), ._6_20)
        XCTAssertEqual(AnalyticsValues.Count(bucketing: 500), ._101_plus)
        XCTAssertEqual(AnalyticsValues.CallDuration(bucketing: 9), .under10s)
        XCTAssertEqual(AnalyticsValues.CallDuration(bucketing: 10), ._10s_1m)
        XCTAssertEqual(AnalyticsValues.CallDuration(bucketing: 60), ._1m_5m)
        XCTAssertEqual(AnalyticsValues.CallDuration(bucketing: 3600), ._30m_plus)
        XCTAssertEqual(AnalyticsEvents.StarsPurchaseSuccessStars(bucketing: 999), ._100_999)
    }

    func testFlowsGoThroughTheHubWithSource() {
        let hub = makeHub()
        let list = SampleController()
        list.analyticsScope = scope(hub)
        list.analyticsScreen = .peerInfo
        hub.screens.didAppear(list)
        let flow = AnalyticsFlow<AnalyticsFlows.PeerInfoVisibility>(analytics: hub, scope: scope(hub), source: .peerInfo)
        flow.step(.selectPublic)
        flow.finish(.success)
        let end = sent.last
        XCTAssertEqual(end?.0, "flow.end")
        XCTAssertEqual(end?.1["source"], .string("peer_info"))
        XCTAssertNotNil(end?.1["session_id"])
        XCTAssertEqual(end?.1["platform"], .string("macos"))
    }

    func testTypedEventsOnlyUseRegistryParams() {
        let events: [AnalyticsEvent] = [
            AnalyticsEvents.menuSelect(chatMessage: .reply, screen: .chat),
            AnalyticsEvents.settingsChange(.notificationsGroups(.disabled)),
            AnalyticsEvents.callEnd(duration: .init(bucketing: 30), video: false, reason: .hangup),
            AnalyticsEvents.screenShow(screen: .chat, source: .chatList, peerType: .user),
        ]
        for event in events {
            let allowed = AnalyticsEventSpec.params[event.name] ?? []
            XCTAssertTrue(Set(event.params.keys).isSubset(of: allowed), event.name.rawValue)
            XCTAssertTrue((AnalyticsEventSpec.required[event.name] ?? []).isSubset(of: Set(event.params.keys)), event.name.rawValue)
        }
    }

    func testValidationFlagsUnknownAndMissingParams() {
        XCTAssertEqual(Analytics.validate(type: "chat.message.send", params: ["kind": .string("text")]), [])
        XCTAssertEqual(Analytics.validate(type: "chat.message.send", params: ["text": .string("hi")]), ["chat.message.send has unknown param text", "chat.message.send is missing kind"])
        XCTAssertEqual(Analytics.validate(type: "nope", params: [:]), ["unknown event nope"])
    }
}
