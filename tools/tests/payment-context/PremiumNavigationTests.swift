import Foundation
import XCTest
import SwiftSignalKit

final class PremiumBindings {
    let navigation = PremiumNavigation()
    func rootNavigation() -> PremiumNavigation { navigation }
}
final class PremiumNavigation {
    var controllers: [ViewController] = []
    var onPush: ((ViewController) -> Void)?
    func push(_ controller: ViewController) { onPush?(controller); controllers.append(controller) }
}
public struct TelegramMediaFile {}
public struct MessageTextEntity {}
public enum ChatInitialAction {}
public class NSColor {}
public struct ContainedViewLayoutTransition {}
__PREMIUM_HOOKS__
func emptyPremiumHooks(showStickerPackPreview: @escaping (any AccountContextProtocol, String) -> Void = { _, _ in }, openBusinessFeature: @escaping (any AccountContextProtocol, PremiumValue) -> Void = { _, _ in }, openLink: @escaping (any AccountContextProtocol, String, @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> Void = { _, _, _ in }) -> PremiumHooks {
    PremiumHooks(openChat: { _, _, _ in }, makeStickerView: { _ in NSView() }, applyMessageEntities: { _, _, _, _, _, _, _, _ in NSAttributedString(string: "") }, showStickerPackPreview: showStickerPackPreview, openBusinessFeature: openBusinessFeature, preloadVideo: { _, _ in .complete() }, openLink: openLink)
}
extension String { var nsstring: NSString { self as NSString } }
struct LinkRequest {
    let url: String
    let callback: (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void
}
enum LinkUI {
    static var received: LinkRequest?
    static var origin: AnalyticsContext?
}
func inApp(for url: NSString, context: AccountContext, openInfo: @escaping (PeerId, Bool, MessageId?, ChatInitialAction?) -> Void) -> LinkRequest {
    return LinkRequest(url: url as String, callback: openInfo)
}
func execute(inapp: LinkRequest, analyticsContext: AnalyticsContext) {
    XCTAssertGreaterThan(analyticsContext.depth, 0)
    LinkUI.received = inapp
    LinkUI.origin = analyticsContext
}
func installLinkHook() -> PremiumHooks {
    var hooks = emptyPremiumHooks()
__LINK_INSTALL__
    return hooks
}
func installNavigationHooks(_ initial: PremiumHooks = emptyPremiumHooks()) -> PremiumHooks {
    var hooks = initial
__NAVIGATION_INSTALL__
    return hooks
}
__NAVIGATION_CHILD__
enum StickerPackReference { case name(String) }
enum StickerPackPreviewSource { case emoji(StickerPackReference) }
enum BusinessMessageType { case greetings, away }
final class BusinessChild: ViewController {
    let kind: String
    init(_ kind: String) { self.kind = kind; super.init(); NavigationUI.created?(self) }
}
enum NavigationUI {
    static var created: ((ViewController) -> Void)?
    static var shortNames: [String] = []
}
func StickerPackPreviewModalController(_ context: AccountContext, peerId: PeerId?, references: [StickerPackPreviewSource], analyticsContext: AnalyticsContext? = nil) -> InputDataModalController {
    if case let .emoji(.name(value))? = references.first { NavigationUI.shortNames.append(value) }
    let controller = InputDataModalController()
    controller.analyticsContext = analyticsContext
    NavigationUI.created?(controller)
    return controller
}
func BusinessLocationController(context: AccountContext) -> ViewController { BusinessChild("location") }
func BusinessHoursController(context: AccountContext) -> ViewController { BusinessChild("hours") }
func BusinessQuickReplyController(context: AccountContext) -> ViewController { BusinessChild("quick_replies") }
func BusinessMessageController(context: AccountContext, type: BusinessMessageType) -> ViewController { BusinessChild(type == .greetings ? "greeting" : "away") }
func BusinessChatbotController(context: AccountContext) -> ViewController { BusinessChild("chatbot") }
func BusinessIntroController(context: AccountContext) -> ViewController { BusinessChild("intro") }
func BusinessLinksController(context: AccountContext) -> ViewController { BusinessChild("links") }
func makeHeaderAction(context: any AccountContextProtocol, analyticsContext: AnalyticsContext, shortName: String) -> () -> Void {
    struct Info { let shortName: String }
    let info = Info(shortName: shortName)
    return {
__HEADER_ACTION__
    }
}
func openBusinessFromPremium(context: any AccountContextProtocol, analyticsContext: AnalyticsContext, value: PremiumValue) {
__BUSINESS_ACTION__
}

final class PremiumNavigationTests: XCTestCase {
    override func setUp() {
        installPremiumHooks(installNavigationHooks())
        PremiumUI.modals = []
        NavigationUI.created = nil
        NavigationUI.shortNames = []
    }
    override func tearDown() { PremiumUI.modals = []; NavigationUI.created = nil; installPremiumHooks(emptyPremiumHooks()) }
    func testLegacyLinkFallbackProtectsInvocationAndDelayedCallback() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        var delayed: ((PeerId, Bool, MessageId?, ChatInitialAction?) -> Void)?
        let hooks = emptyPremiumHooks(openLink: { _, url, callback in
            XCTAssertEqual(url, "synthetic")
            XCTAssertGreaterThan(origin.depth, 0)
            delayed = callback
        })
        var delivered = false
        hooks.openLinkObserved(context, "synthetic", { _, _, _, _ in
            delivered = true
            XCTAssertGreaterThan(origin.depth, 0)
        }, analyticsContext: origin)
        XCTAssertEqual(origin.depth, 0)
        delayed?(PeerId(), true, nil, nil)
        XCTAssertTrue(delivered)
        XCTAssertEqual(origin.depth, 0)
        delayed = nil
    }
    func testLinkCompanionPassesOriginalContextAndDelayedCallbackProtectsDelivery() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        let hooks = installLinkHook()
        var callbacks = 0
        hooks.openLinkObserved(context, "synthetic", { _, isChat, _, _ in
            callbacks += 1
            XCTAssertTrue(isChat)
            XCTAssertGreaterThan(origin.depth, 0)
        }, analyticsContext: origin)
        XCTAssertTrue(LinkUI.origin === origin)
        XCTAssertEqual(LinkUI.received?.url, "synthetic")
        XCTAssertEqual(origin.depth, 0)
        LinkUI.received?.callback(PeerId(), true, nil, nil)
        XCTAssertEqual(callbacks, 1)
        XCTAssertEqual(origin.depth, 0)
        LinkUI.received = nil; LinkUI.origin = nil
    }
    func testHeaderActionRetainsOriginForModalAndContentAfterParentEnds() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        let parent = origin.beginPresentation()
        let open = makeHeaderAction(context: context, analyticsContext: origin, shortName: "synthetic")
        parent.end()
        NavigationUI.created = { _ in XCTAssertGreaterThan(origin.depth, 0) }
        open()
        XCTAssertEqual(NavigationUI.shortNames, ["synthetic"])
        XCTAssertEqual(PremiumUI.modals.count, 1)
        XCTAssertTrue(PremiumUI.modals[0].analyticsContext === origin)
        XCTAssertTrue((PremiumUI.modals[0] as? InputDataModalController)?.current.analyticsContext === origin)
        XCTAssertEqual(origin.depth, 1)
        PremiumUI.modals = []
        XCTAssertEqual(origin.depth, 0)
    }
    func testRepeatedHeaderClicksKeepIndependentChildLifetimes() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        let open = makeHeaderAction(context: context, analyticsContext: origin, shortName: "synthetic")
        open(); open()
        XCTAssertEqual(origin.depth, 2)
        PremiumUI.modals.removeFirst()
        XCTAssertEqual(origin.depth, 1)
        PremiumUI.modals = []
        XCTAssertEqual(origin.depth, 0)
    }
    func testEveryBusinessRouteIsConstructedAndBoundBeforePush() {
        let cases: [(PremiumValue, String)] = [(.business_location, "location"), (.business_hours, "hours"), (.quick_replies, "quick_replies"), (.greeting_message, "greeting"), (.away_message, "away"), (.business_bots, "chatbot"), (.business_intro, "intro"), (.business_links, "links")]
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        NavigationUI.created = { _ in XCTAssertGreaterThan(origin.depth, 0) }
        context.bindings.navigation.onPush = { controller in
            XCTAssertTrue(controller.analyticsContext === origin)
            XCTAssertGreaterThan(origin.depth, 0)
        }
        for (value, kind) in cases {
            openBusinessFromPremium(context: context, analyticsContext: origin, value: value)
            XCTAssertEqual((context.bindings.navigation.controllers.last as? BusinessChild)?.kind, kind)
        }
        XCTAssertEqual(context.bindings.navigation.controllers.count, cases.count)
        XCTAssertEqual(origin.depth, cases.count)
        context.bindings.navigation.controllers = []
        XCTAssertEqual(origin.depth, 0)
    }
    func testChildRetainsOriginUntilItsOwnCleanupAndChainsPreviousDeinit() {
        let origin = AnalyticsContext(excluded: true)
        let parent = origin.beginPresentation()
        var cleaned = 0
        var child: ViewController? = premiumNavigationChild(analyticsContext: origin, create: {
            XCTAssertEqual(origin.depth, 2)
            let controller = ViewController()
            controller.onDeinit = { cleaned += 1; XCTAssertEqual(origin.depth, 1) }
            return controller
        })
        parent.end()
        XCTAssertEqual(origin.depth, 1)
        XCTAssertTrue(child?.analyticsContext === origin)
        child = nil
        XCTAssertEqual(cleaned, 1)
        XCTAssertEqual(origin.depth, 0)
    }
    func testNilFactoryAndUnsupportedBusinessRouteReleaseOriginWithoutPresentation() {
        let origin = AnalyticsContext(excluded: true)
        let child: ViewController? = premiumNavigationChild(analyticsContext: origin, create: {
            XCTAssertEqual(origin.depth, 1)
            return nil
        })
        XCTAssertNil(child)
        XCTAssertEqual(origin.depth, 0)
        let context = AccountContext()
        openBusinessFromPremium(context: context, analyticsContext: origin, value: .stories)
        XCTAssertTrue(context.bindings.navigation.controllers.isEmpty)
        XCTAssertEqual(origin.depth, 0)
    }
    func testLegacyFallbackInvokesUnderOriginWithoutClaimingDetachedLifetime() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: true)
        var calls = 0
        let hooks = emptyPremiumHooks(showStickerPackPreview: { _, name in
            XCTAssertEqual(name, "synthetic")
            XCTAssertEqual(origin.depth, 1)
            calls += 1
        }, openBusinessFeature: { _, value in
            XCTAssertEqual(value, .business_hours)
            XCTAssertEqual(origin.depth, 1)
            calls += 1
        })
        hooks.showStickerPackPreviewObserved(context, "synthetic", analyticsContext: origin)
        hooks.openBusinessFeatureObserved(context, .business_hours, analyticsContext: origin)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(origin.depth, 0)
    }
    func testContextCompanionsTakePrecedenceOverLegacyClosures() {
        let context = AccountContext()
        let origin = AnalyticsContext(excluded: false)
        let hooks = installNavigationHooks(emptyPremiumHooks(showStickerPackPreview: { _, _ in XCTFail("Legacy fallback") }, openBusinessFeature: { _, _ in XCTFail("Legacy fallback") }))
        hooks.showStickerPackPreviewObserved(context, "synthetic", analyticsContext: origin)
        hooks.openBusinessFeatureObserved(context, .business_intro, analyticsContext: origin)
        XCTAssertTrue(PremiumUI.modals.first?.analyticsContext === origin)
        XCTAssertTrue(context.bindings.navigation.controllers.first?.analyticsContext === origin)
        PremiumUI.modals = []
        context.bindings.navigation.controllers = []
        XCTAssertEqual(origin.depth, 0)
    }
}
