import XCTest
import TelegramCore
import Postbox
import TGUIKit
@testable import AppAnalytics

private final class ModalPrivacyContent: ViewController {
    var onWillAppear: (() -> Void)?
    var onDidDisappear: (() -> Void)?

    override var redirectUserInterfaceCalls: Bool { true }

    override func viewWillAppear(_ animated: Bool) {
        onWillAppear?()
        super.viewWillAppear(animated)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        onDidDisappear?()
    }
}

private final class ModalPrivacyNavigation: NavigationViewController {
    override var window: Window? { nil }
}

final class AnalyticsContextTests: XCTestCase {
    func testUnadmittedOrdinaryPresentationsCannotCreateFreshDescendantScopes() {
        let analytics = hub()
        let original = analytics.captureContext(owner: owner, privacy: .ordinary)
        let foreign = analytics.captureContext(owner: NSObject(), privacy: .ordinary, inherited: original)
        let unscoped = analytics.privacyContext(peerId: peer(Namespaces.Peer.CloudUser))
        analytics.isEnabled = false
        let disabled = analytics.captureContext(owner: owner, privacy: .ordinary)
        analytics.isEnabled = true
        for context in [original, foreign, unscoped, disabled] {
            XCTAssertFalse(context.isExcluded)
            let presentation = context.beginPresentation()
            XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
            analytics.send(AnalyticsEvents.appForeground(), scope: context.scope)
            presentation.end()
            XCTAssertTrue(analytics.captureContext(owner: owner, privacy: .ordinary).scope?.isValid == true)
        }
        XCTAssertTrue(sent.isEmpty)
    }

    func testAdmittedOrdinaryPresentationStillAllowsOrdinaryDescendants() {
        let analytics = hub()
        let context = analytics.captureContext(owner: owner, privacy: .ordinary)
        let presentation = context.beginPresentation()
        XCTAssertTrue(context.scope?.isValid == true)
        XCTAssertTrue(analytics.captureContext(owner: owner, privacy: .ordinary).scope?.isValid == true)
        analytics.send(AnalyticsEvents.appForeground(), scope: context.scope)
        XCTAssertEqual(sent, ["app.foreground"])
        presentation.end()
    }

    func testExplicitScopeExclusionTightensDerivedContextsAndActivePresentations() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let child = origin.restricting(peerId: peer(Namespaces.Peer.CloudUser))
        let first = origin.beginPresentation()
        let second = child.beginPresentation()
        origin.scope?.exclude()
        XCTAssertTrue(origin.isExcluded)
        XCTAssertTrue(child.isExcluded)
        XCTAssertFalse(origin.scope?.isValid == true)
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        analytics.send(AnalyticsEvents.appForeground(), scope: child.scope)
        first.end()
        XCTAssertTrue(analytics.policy.hasExclusions)
        second.end()
        XCTAssertFalse(analytics.policy.hasExclusions)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary, inherited: origin).scope)
        XCTAssertTrue(sent.isEmpty)
    }

    func testExplicitExclusionAfterGenerationRevocationStillUpdatesActivePresentation() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let presentation = origin.beginPresentation()
        analytics.isEnabled = false
        analytics.isEnabled = true
        XCTAssertFalse(analytics.policy.hasExclusions)
        origin.scope?.exclude()
        XCTAssertTrue(analytics.policy.hasExclusions)
        presentation.end()
        XCTAssertFalse(analytics.policy.hasExclusions)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
    }

    func testExplicitScopeExclusionUpdatesAlreadyVisibleScreenUntilItCloses() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let controller = ViewController()
        controller.analyticsScreen = .chat
        controller.analyticsContext = origin
        analytics.screens.didAppear(controller)
        let child = ViewController()
        child.analyticsScreen = .appAlert
        child.analyticsContext = origin.restricting(peerId: peer(Namespaces.Peer.CloudUser))
        analytics.screens.didAppear(child)
        sent.removeAll()
        origin.scope?.exclude()
        XCTAssertTrue(analytics.policy.hasExclusions)
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        analytics.screens.didDisappear(controller)
        XCTAssertTrue(analytics.policy.hasExclusions)
        analytics.screens.didDisappear(child)
        XCTAssertFalse(analytics.policy.hasExclusions)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
    }

    func testExplicitScopeExclusionDoesNotPermanentlyExcludeUnrelatedOrigins() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let unrelated = analytics.captureContext(owner: owner, privacy: .ordinary)
        origin.scope?.exclude()
        XCTAssertTrue(origin.isExcluded)
        XCTAssertFalse(unrelated.isExcluded)
        XCTAssertFalse(unrelated.scope?.isValid == true)
        XCTAssertFalse(analytics.policy.hasExclusions)
        let fresh = analytics.captureContext(owner: owner, privacy: .ordinary)
        origin.scope?.exclude()
        XCTAssertTrue(fresh.scope?.isValid == true)
        XCTAssertFalse(fresh.isExcluded)
    }

    func testExcludedPresentationReleaseEndsExclusionWithoutRetainingItsScope() {
        let analytics = hub()
        var origin: AnalyticsContext? = analytics.captureContext(owner: owner, privacy: .ordinary)
        weak var scope = origin?.scope
        var presentation: AnalyticsPresentation? = origin?.beginPresentation()
        origin?.scope?.exclude()
        XCTAssertTrue(analytics.policy.hasExclusions)
        origin = nil
        XCTAssertNotNil(scope)
        presentation = nil
        XCTAssertNil(presentation)
        XCTAssertNil(scope)
        XCTAssertFalse(analytics.policy.hasExclusions)
    }

    func testExplicitScopeExclusionDiscardsRecorderAndSuppressesLazyEventConstruction() {
        let analytics = hub()
        let origin = analytics.captureContext(owner: owner, privacy: .ordinary)
        let flow = AnalyticsFlow<AnalyticsFlows.PeerInfoVisibility>(analytics: analytics, scope: origin.scope)
        flow.step(.selectPublic)
        XCTAssertEqual(flow.recordedStepCount, 1)
        origin.scope?.exclude()
        XCTAssertEqual(flow.recordedStepCount, 0)
        flow.step(.save)
        flow.finish(.success)
        var builds = 0
        func event() -> AnalyticsEvent {
            builds += 1
            return AnalyticsEvents.appForeground()
        }
        analytics.send(event(), scope: origin.scope)
        XCTAssertEqual(builds, 0)
        XCTAssertTrue(sent.isEmpty)
        let fresh = analytics.captureContext(owner: owner, privacy: .ordinary)
        analytics.send(event(), scope: fresh.scope)
        XCTAssertEqual(builds, 1)
        XCTAssertEqual(sent, ["app.foreground"])
    }

    private let owner = NSObject()
    private var sent: [String] = []

    private func hub() -> Analytics {
        let hub = Analytics(clock: { 0 })
        hub.setSink({ [unowned self] type, _ in self.sent.append(type) }, owner: owner)
        hub.isEnabled = true
        return hub
    }

    private func peer(_ namespace: PeerId.Namespace) -> PeerId {
        return PeerId(namespace: namespace, id: ._internalFromInt64Value(1))
    }

    func testSecretNamespaceExcludesBeforePeerDataAndDidAppear() {
        let analytics = hub()
        let ordinary = analytics.captureContext(owner: owner, privacy: .ordinary)
        let controller = ViewController()
        controller.analyticsContext = analytics.privacyContext(peerId: peer(Namespaces.Peer.SecretChat))
        XCTAssertNil(controller.analyticsPeer)
        analytics.screens.willAppear(controller)
        XCTAssertFalse(ordinary.scope?.isValid ?? true)
        analytics.send(AnalyticsEvents.appForeground(), scope: ordinary.scope)
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        XCTAssertTrue(sent.isEmpty)
        analytics.screens.didDisappear(controller)
        XCTAssertTrue(analytics.captureContext(owner: owner, privacy: .ordinary).scope?.isValid == true)
    }

    func testUnresolvedNamespaceCannotAuthorizeOrExposeActivity() {
        let analytics = hub()
        let controller = ViewController()
        controller.analyticsContext = analytics.privacyContext(peerId: peer(.max))
        analytics.screens.willAppear(controller)
        XCTAssertTrue(controller.analyticsContext?.isExcluded == true)
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        analytics.screens.didDeinit(ObjectIdentifier(controller))
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        XCTAssertTrue(sent.isEmpty)
    }

    func testChildRemainsExcludedAfterParentDisappears() {
        let analytics = hub()
        let parent = ViewController()
        parent.analyticsContext = analytics.privacyContext(peerId: peer(Namespaces.Peer.SecretChat))
        analytics.screens.willAppear(parent)
        let captured = analytics.captureContext(owner: owner, privacy: .excluded)
        analytics.screens.didDisappear(parent)
        let child = ViewController()
        child.analyticsContext = captured
        child.analyticsScreen = .systemFilePicker
        analytics.screens.didAppear(child)
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        analytics.screens.didDisappear(child)
        let late = analytics.captureContext(owner: owner, privacy: .ordinary, inherited: captured)
        XCTAssertTrue(late.isExcluded)
        XCTAssertNil(late.scope)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
    }

    func testUnscopedChildAndStandaloneKeepPrivatePresentationExcluded() {
        let analytics = hub()
        let privatePresentation = analytics.excludedContext().beginPresentation()
        let child = ViewController()
        analytics.screens.willAppear(child)
        let panel = NSObject()
        analytics.screens.showStandalone(.systemFilePicker, owner: panel)
        privatePresentation.end()
        XCTAssertTrue(child.analyticsContext?.isExcluded == true)
        analytics.screens.didDisappear(child)
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        analytics.screens.hideStandalone(owner: panel)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        XCTAssertTrue(sent.isEmpty)
        analytics.screens.willAppear(child)
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        analytics.screens.didDeinit(ObjectIdentifier(child))
    }

    func testOverlappingNativePresentationsEndIndependently() {
        let analytics = hub()
        let context = analytics.excludedContext()
        let first = context.beginPresentation()
        var second: AnalyticsPresentation? = context.beginPresentation()
        first.end()
        first.end()
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        withExtendedLifetime(second) {}
        second = nil
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        XCTAssertNil(context.scope)
    }

    func testSecretSourceTightensOrdinaryDestination() {
        let analytics = hub()
        let ordinary = analytics.captureContext(owner: owner, privacy: .ordinary)
        let mixed = ordinary.restricting(peerId: peer(Namespaces.Peer.SecretChat))
        XCTAssertTrue(mixed.isExcluded)
        XCTAssertNil(mixed.scope)
        let changedDestination = mixed.restricting(peerId: peer(Namespaces.Peer.CloudUser))
        XCTAssertTrue(changedDestination.isExcluded)
        XCTAssertNil(changedDestination.scope)
        let unknown = ordinary.restricting(peerId: peer(.max))
        XCTAssertTrue(unknown.isExcluded)
        analytics.send(AnalyticsEvents.appForeground(), scope: ordinary.scope)
        XCTAssertEqual(sent, ["app.foreground"])
    }

    func testDestinationRestrictionCannotRemoveSecretOrigin() {
        let analytics = hub()
        let context = analytics.captureContext(owner: owner, privacy: .ordinary)
        let restricted = context.restricting(peerId: peer(Namespaces.Peer.SecretChat))
        let returned = restricted.restricting(peerId: peer(Namespaces.Peer.CloudUser))
        XCTAssertTrue(restricted.isExcluded)
        XCTAssertTrue(returned.isExcluded)
        XCTAssertNil(returned.scope)
        let presentation = returned.beginPresentation()
        analytics.send(AnalyticsEvents.appForeground(), scope: context.scope)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        presentation.end()
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
    }

    func testLateDestinationRestrictionKeepsOriginalRevokedScope() {
        let analytics = hub()
        let context = analytics.captureContext(owner: owner, privacy: .ordinary)
        let presentation = analytics.excludedContext().beginPresentation()
        presentation.end()
        let restricted = context.restricting(peerId: peer(Namespaces.Peer.CloudChannel))
        XCTAssertTrue(restricted.scope === context.scope)
        XCTAssertFalse(restricted.scope?.isValid ?? true)
        analytics.send(AnalyticsEvents.appForeground(), scope: restricted.scope)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
    }

    func testDestinationResolutionCannotAuthorizeUnresolvedOrigin() {
        let analytics = hub()
        let context = analytics.unresolvedContext().restricting(peerId: peer(Namespaces.Peer.CloudUser))
        XCTAssertTrue(context.isExcluded)
        XCTAssertNil(context.scope)
        let presentation = context.beginPresentation()
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        presentation.end()
        XCTAssertTrue(sent.isEmpty)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
    }

    func testInheritedContextCannotRefreshAfterRevocationOrAccountChange() {
        let analytics = hub()
        let original = analytics.captureContext(owner: owner, privacy: .ordinary)
        analytics.isEnabled = false
        analytics.isEnabled = true
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary, inherited: original).scope)
        let fresh = analytics.captureContext(owner: owner, privacy: .ordinary)
        let otherOwner = NSObject()
        XCTAssertNil(analytics.captureContext(owner: otherOwner, privacy: .ordinary, inherited: fresh).scope)
        analytics.setSink({ _, _ in XCTFail() }, owner: otherOwner)
        XCTAssertNil(analytics.captureContext(owner: otherOwner, privacy: .ordinary, inherited: fresh).scope)
        analytics.setSink({ _, _ in }, owner: owner)
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary, inherited: fresh).scope)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
    }

    func testContextCapturedWhileDisabledCannotAcquireScopeLater() {
        let analytics = hub()
        analytics.isEnabled = false
        let original = analytics.captureContext(owner: owner, privacy: .ordinary)
        analytics.isEnabled = true
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary, inherited: original).scope)
        XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
    }

    func testVisibleContextChangeToSecretSilentlyClearsHistory() {
        let analytics = hub()
        let controller = ViewController()
        controller.analyticsScreen = .chat
        controller.analyticsContext = analytics.captureContext(owner: owner, privacy: .ordinary)
        analytics.screens.didAppear(controller)
        XCTAssertEqual(sent, ["screen.show"])
        controller.analyticsContext = analytics.privacyContext(peerId: peer(Namespaces.Peer.SecretChat))
        XCTAssertNil(analytics.screens.current)
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        analytics.screens.didDisappear(controller)
        XCTAssertEqual(sent, ["screen.show"])
    }

    func testValidContextCarriesScopeThroughChildVisibility() {
        let analytics = hub()
        let captured = analytics.captureContext(owner: owner, privacy: .ordinary)
        let controller = ViewController()
        controller.analyticsContext = captured
        controller.analyticsScreen = .systemFilePicker
        analytics.screens.didAppear(controller)
        analytics.screens.didDisappear(controller)
        XCTAssertEqual(sent, ["screen.show", "screen.hide"])
        XCTAssertTrue(captured.scope?.isValid == true)
        XCTAssertTrue(analytics.captureContext(owner: owner, privacy: .ordinary, inherited: captured).scope === captured.scope)
    }

    func testForeignContextCannotAuthorizeControllerOrChild() {
        let analytics = hub()
        let other = hub()
        let foreign = other.captureContext(owner: owner, privacy: .ordinary)
        XCTAssertTrue(analytics.captureContext(owner: owner, privacy: .ordinary, inherited: foreign).isExcluded)
        let controller = ViewController()
        controller.analyticsContext = foreign
        controller.analyticsScreen = .chat
        analytics.screens.didAppear(controller)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        analytics.screens.didDisappear(controller)
    }

    func testFrameworkWillAppearHookRunsBeforeDidAppear() {
        let analytics = hub()
        let previous = ViewControllerLifecycleHooks.willAppear
        defer { ViewControllerLifecycleHooks.willAppear = previous }
        ViewControllerLifecycleHooks.willAppear = { analytics.screens.willAppear($0) }
        let controller = ViewController()
        controller.analyticsContext = analytics.privacyContext(peerId: peer(Namespaces.Peer.SecretChat))
        controller.viewWillAppear(false)
        XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        XCTAssertTrue(sent.isEmpty)
        analytics.screens.didDeinit(ObjectIdentifier(controller))
    }

    private func withLifecycleHooks(_ analytics: Analytics, body: () -> Void) {
        let willAppear = ViewControllerLifecycleHooks.willAppear
        let didAppear = ViewControllerLifecycleHooks.didAppear
        let didDisappear = ViewControllerLifecycleHooks.didDisappear
        let didDeinit = ViewControllerLifecycleHooks.didDeinit
        defer {
            ViewControllerLifecycleHooks.willAppear = willAppear
            ViewControllerLifecycleHooks.didAppear = didAppear
            ViewControllerLifecycleHooks.didDisappear = didDisappear
            ViewControllerLifecycleHooks.didDeinit = didDeinit
        }
        ViewControllerLifecycleHooks.willAppear = { analytics.screens.willAppear($0) }
        ViewControllerLifecycleHooks.didAppear = { analytics.screens.didAppear($0) }
        ViewControllerLifecycleHooks.didDisappear = { analytics.screens.didDisappear($0) }
        ViewControllerLifecycleHooks.didDeinit = { analytics.screens.didDeinit($0) }
        body()
    }

    func testPrivateModalExcludesBeforeChildCallbackAndChildOutlivesIt() {
        let analytics = hub()
        withLifecycleHooks(analytics) {
            let original = analytics.captureContext(owner: owner, privacy: .ordinary)
            let content = ModalPrivacyContent()
            content.onWillAppear = {
                XCTAssertFalse(original.scope?.isValid ?? true)
                XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
            }
            let navigation = ModalPrivacyNavigation(content, nil)
            navigation.cleanupAfterDeinit = false
            let modal = ModalController(navigation)
            modal.analyticsContext = analytics.privacyContext(peerId: peer(Namespaces.Peer.SecretChat))
            modal.viewWillAppear(false)
            XCTAssertTrue(content.analyticsContext?.isExcluded == true)
            XCTAssertTrue(navigation.analyticsContext?.isExcluded == true)
            modal.viewDidAppear(false)

            let child = ViewController()
            child.viewWillAppear(false)
            modal.viewWillDisappear(false)
            modal.viewDidDisappear(false)
            XCTAssertTrue(child.analyticsContext?.isExcluded == true)
            XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
            child.viewDidDisappear(false)
            XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
            XCTAssertFalse(original.scope?.isValid ?? true)
            child.viewWillAppear(false)
            XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
            child.viewDidDisappear(false)
            XCTAssertTrue(sent.isEmpty)
        }
    }

    func testModalDismissedBeforeDidAppearReleasesItsExclusion() {
        let analytics = hub()
        withLifecycleHooks(analytics) {
            let navigation = ModalPrivacyNavigation(ModalPrivacyContent(), nil)
            navigation.cleanupAfterDeinit = false
            let modal = ModalController(navigation)
            modal.analyticsContext = analytics.unresolvedContext()
            modal.viewWillAppear(false)
            XCTAssertNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
            modal.viewWillDisappear(false)
            modal.viewDidDisappear(false)
            XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
            XCTAssertTrue(sent.isEmpty)
        }
    }

    func testModalRetainsChildExclusionThroughChildDisappearanceCallbacks() {
        let analytics = hub()
        withLifecycleHooks(analytics) {
            let content = ModalPrivacyContent()
            content.analyticsContext = analytics.privacyContext(peerId: peer(Namespaces.Peer.SecretChat))
            content.onDidDisappear = {
                XCTAssertNil(analytics.captureContext(owner: self.owner, privacy: .ordinary).scope)
            }
            let navigation = ModalPrivacyNavigation(content, nil)
            navigation.cleanupAfterDeinit = false
            let modal = ModalController(navigation)
            modal.viewWillAppear(false)
            modal.viewDidAppear(false)
            XCTAssertTrue(modal.analyticsContext?.isExcluded == true)
            modal.viewWillDisappear(false)
            modal.viewDidDisappear(false)
            XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
            XCTAssertTrue(sent.isEmpty)
        }
    }

    func testOrdinaryModalHooksEmitOneShowAndHideWithoutAuthorizingChildren() {
        let analytics = hub()
        withLifecycleHooks(analytics) {
            let content = ModalPrivacyContent()
            content.analyticsScreen = .chat
            let navigation = ModalPrivacyNavigation(content, nil)
            navigation.cleanupAfterDeinit = false
            let modal = ModalController(navigation)
            modal.analyticsContext = analytics.captureContext(owner: owner, privacy: .ordinary)
            modal.analyticsScreen = .systemFilePicker
            modal.viewWillAppear(false)
            modal.viewDidAppear(false)
            modal.viewDidAppear(false)
            modal.viewWillDisappear(false)
            modal.viewDidDisappear(false)
            XCTAssertEqual(sent, ["screen.show", "screen.hide"])
            XCTAssertNil(content.analyticsContext)
            XCTAssertNotNil(analytics.captureContext(owner: owner, privacy: .ordinary).scope)
        }
    }
}
