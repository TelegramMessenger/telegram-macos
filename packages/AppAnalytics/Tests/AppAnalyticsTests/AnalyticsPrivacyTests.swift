import Foundation
import XCTest
import TelegramCore
import TGUIKit
@testable import AppAnalytics

final class AnalyticsPrivacyTests: XCTestCase {
    private let owner = NSObject()
    private var sent: [(String, JSON)] = []
    private var logged: [String] = []

    private func hub(enabled: Bool = true) -> Analytics {
        let hub = Analytics(clock: { 1 })
        hub.setSink({ [unowned self] in sent.append(($0, $1)) }, owner: owner)
        hub.log = { [unowned self] in logged.append($0) }
        hub.isEnabled = enabled
        return hub
    }

    private func scope(_ hub: Analytics) -> AnalyticsScope? {
        return hub.policy.makeScope(owner: owner, privacy: .ordinary)
    }

    func testDefaultDisabledAndUnscopedProducersDoNotBuildPayloads() {
        let hub = Analytics()
        XCTAssertFalse(hub.isEnabled)
        hub.setSink({ [unowned self] in sent.append(($0, $1)) }, owner: owner)
        XCTAssertNil(scope(hub))
        hub.isEnabled = true
        var constructed = false
        func event() -> AnalyticsEvent {
            constructed = true
            return AnalyticsEvents.appForeground()
        }
        func data() -> JSON {
            constructed = true
            return .dictionary([:])
        }
        hub.send(event())
        hub.sendRaw(type: "app.foreground", data: data())
        XCTAssertFalse(constructed)
        XCTAssertTrue(sent.isEmpty)
    }

    func testUnknownExcludedAndWrongAccountScopesAreDenied() {
        let hub = hub()
        XCTAssertNil(hub.policy.makeScope(owner: owner, privacy: .excluded))
        XCTAssertNil(hub.policy.makeScope(owner: owner, privacy: .unresolved))
        XCTAssertNil(hub.policy.makeScope(owner: NSObject(), privacy: .ordinary))
        let other = self.hub()
        hub.send(AnalyticsEvents.appForeground(), scope: scope(other))
        XCTAssertTrue(sent.isEmpty)
    }

    func testDisablePermanentlyRevokesScopeAndClearsVisibility() {
        let hub = hub()
        let scope = scope(hub)
        let screen = NSObject()
        hub.screens.showStandalone(.chat, owner: screen, scope: scope)
        hub.isEnabled = false
        XCTAssertFalse(scope?.isValid ?? true)
        XCTAssertNil(hub.screens.current)
        hub.isEnabled = true
        hub.screens.hideStandalone(owner: screen)
        hub.send(AnalyticsEvents.appForeground(), scope: scope)
        XCTAssertEqual(sent.count, 1)
        hub.send(AnalyticsEvents.appForeground(), scope: self.scope(hub))
        XCTAssertEqual(sent.count, 2)
        guard case let .dictionary(values) = sent[1].1 else { return XCTFail() }
        XCTAssertEqual(values["seq"], .number(0))
    }

    func testAccountReplacementDoesNotRedirectDelayedEvents() {
        let hub = hub()
        let oldScope = scope(hub)
        let nextOwner = NSObject()
        hub.setSink({ [unowned self] in sent.append(($0, $1)) }, owner: nextOwner)
        hub.send(AnalyticsEvents.appForeground(), scope: oldScope)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertNil(scope(hub))
        let nextScope = hub.policy.makeScope(owner: nextOwner, privacy: .ordinary)
        hub.send(AnalyticsEvents.appForeground(), scope: nextScope)
        XCTAssertEqual(sent.count, 1)
        hub.setSink(nil, owner: nil)
        XCTAssertFalse(nextScope?.isValid ?? true)
    }

    func testExcludedPeerAndScreenPayloadsNeverReachLogOrSink() {
        let hub = hub()
        let scope = scope(hub)
        hub.send(AnalyticsEvents.chatMessageSend(kind: .photo, peerType: .secretChat), scope: scope)
        hub.send(AnalyticsEvents.screenShow(screen: .createSecretChat), scope: scope)
        hub.send(AnalyticsEvents.screenShow(screen: .chat, source: .peerInfoEncryptionKey), scope: scope)
        hub.sendRaw(type: "screen.hide", data: .dictionary(["screen": .string("peer_info.encryption_key")]), scope: scope)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logged.isEmpty)
    }

    func testSecretScreenRevokesAllWindowsWithoutHideOrSourceReplay() {
        let hub = hub()
        let ordinary = NSObject()
        let secret = NSObject()
        let oldScope = scope(hub)
        hub.screens.showStandalone(.chatList, owner: ordinary, scope: oldScope)
        hub.screens.show(ObjectIdentifier(secret), screen: .chat, peerType: .secretChat)
        XCTAssertNil(scope(hub))
        XCTAssertNil(hub.screens.current)
        hub.send(AnalyticsEvents.appForeground(), scope: oldScope)
        hub.screens.hideStandalone(owner: secret)
        hub.screens.hideStandalone(owner: ordinary)
        XCTAssertEqual(sent.count, 1)
        hub.screens.showStandalone(.chatList, owner: ordinary, scope: scope(hub))
        XCTAssertEqual(sent.count, 2)
        guard case let .dictionary(values) = sent[1].1 else { return XCTFail() }
        XCTAssertNil(values["source"])
        XCTAssertEqual(values["seq"], .number(0))
    }

    func testMultipleExclusionsMustAllEndBeforeNewScope() {
        let hub = hub()
        let first = NSObject()
        let second = NSObject()
        hub.setExcluded(true, owner: first)
        hub.setExcluded(true, owner: second)
        hub.setExcluded(false, owner: first)
        XCTAssertNil(scope(hub))
        hub.isEnabled = false
        hub.isEnabled = true
        XCTAssertNil(scope(hub))
        hub.setExcluded(false, owner: second)
        XCTAssertNotNil(scope(hub))
    }

    func testUnknownChildAndStandalonePanelDoNotInheritCurrentScreenImplicitly() {
        let hub = hub()
        let ordinary = NSObject()
        hub.screens.showStandalone(.chat, owner: ordinary, scope: scope(hub))
        let child = ViewController().analytics(.appAlert)
        hub.screens.didAppear(child)
        hub.screens.showStandalone(.systemFilePicker, owner: child)
        hub.screens.didDisappear(child)
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(hub.screens.current, .chat)
    }

    func testUnmappedSecretControllerStillBlocksOtherProducers() {
        let hub = hub()
        let controller = ViewController()
        controller.analyticsPeer = .secretChat
        hub.screens.didAppear(controller)
        XCTAssertNil(scope(hub))
        hub.screens.didDisappear(controller)
        XCTAssertNotNil(scope(hub))
        XCTAssertTrue(sent.isEmpty)
    }

    func testSecretFlowSourceAndLatePeerResolutionDiscardRecorderState() {
        let hub = hub()
        let scope = scope(hub)
        let excluded = AnalyticsFlow<AnalyticsFlows.PeerInfoVisibility>(analytics: hub, scope: scope, source: .peerInfoEncryptionKey)
        excluded.step(.selectPublic)
        XCTAssertEqual(excluded.recordedStepCount, 0)
        excluded.finish(.success)
        let unresolved = AnalyticsFlow<AnalyticsFlows.PeerInfoVisibility>(analytics: hub, scope: scope)
        unresolved.step(.selectPublic)
        unresolved.set(peerType: .secretChat)
        XCTAssertEqual(unresolved.recordedStepCount, 0)
        unresolved.step(.save)
        unresolved.finish(.success)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logged.isEmpty)
    }

    func testFlowsNeverRecordWithoutAnEligibleScopeOrReviveAfterEnable() {
        let hub = hub(enabled: false)
        var flow: AnalyticsFlow<AnalyticsFlows.PeerInfoVisibility>? = AnalyticsFlow(analytics: hub)
        var constructed = false
        func value() -> JSON {
            constructed = true
            return .string("edit")
        }
        flow?.step(.selectPublic)
        flow?.setValue(.entry, value())
        flow?.setValueIfAbsent(.entry, value())
        XCTAssertEqual(flow?.recordedStepCount, 0)
        XCTAssertFalse(constructed)
        hub.isEnabled = true
        flow?.finish(.success)
        flow = nil
        XCTAssertTrue(sent.isEmpty)
    }

    func testRevocationErasesFlowStateAndSuppressesDelayedFinishAndDeinit() {
        let hub = hub()
        var flow: AnalyticsFlow<AnalyticsFlows.PeerInfoVisibility>? = AnalyticsFlow(analytics: hub, scope: scope(hub))
        flow?.step(.selectPublic)
        flow?.set(entry: .edit)
        XCTAssertEqual(flow?.recordedStepCount, 1)
        let secret = NSObject()
        hub.setExcluded(true, owner: secret)
        XCTAssertEqual(flow?.recordedStepCount, 0)
        hub.setExcluded(false, owner: secret)
        flow?.step(.save)
        flow?.finish(.success)
        flow = nil
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logged.isEmpty)
    }

    func testInvalidPayloadIsDroppedInProductionPath() {
        let hub = hub()
        let scope = scope(hub)
        hub.sendRaw(type: "unknown.event", data: .dictionary([:]), scope: scope)
        hub.sendRaw(type: "chat.message.send", data: .dictionary(["text": .string("forbidden")]), scope: scope)
        hub.sendRaw(type: "app.foreground", data: .array([]), scope: scope)
        XCTAssertTrue(sent.isEmpty)
        XCTAssertTrue(logged.isEmpty)
    }

    func testReentrantRevocationFromLoggerPreventsSinkAdmission() {
        #if DEBUG
        let hub = hub()
        hub.log = { [weak hub] _ in hub?.isEnabled = false }
        hub.send(AnalyticsEvents.appForeground(), scope: scope(hub))
        XCTAssertTrue(sent.isEmpty)
        #endif
    }

    func testRevocationWhileBuildingRawPayloadPreventsDebugOutput() {
        let hub = hub()
        let scope = scope(hub)
        func data() -> JSON {
            hub.isEnabled = false
            return .dictionary([:])
        }
        hub.sendRaw(type: "app.foreground", data: data(), scope: scope)
        XCTAssertTrue(logged.isEmpty)
        XCTAssertTrue(sent.isEmpty)
    }

    func testRevocationInsideClockCannotRestoreScreenOrFlowState() {
        var onClock: (() -> Void)?
        let hub = Analytics(clock: {
            onClock?()
            return 1
        })
        hub.setSink({ [unowned self] in sent.append(($0, $1)) }, owner: owner)
        hub.isEnabled = true
        let flow = AnalyticsFlow<AnalyticsFlows.PeerInfoVisibility>(analytics: hub, scope: scope(hub))
        onClock = { hub.isEnabled = false }
        flow.step(.selectPublic)
        XCTAssertEqual(flow.recordedStepCount, 0)
        hub.isEnabled = true
        let screen = NSObject()
        hub.screens.showStandalone(.chat, owner: screen, scope: scope(hub))
        XCTAssertNil(hub.screens.current)
        XCTAssertTrue(sent.isEmpty)
        onClock = nil
    }

    func testConcurrentFlowCompletionProducesOneTerminalEvent() {
        let hub = hub()
        let flow = AnalyticsFlow<AnalyticsFlows.PeerInfoVisibility>(analytics: hub, scope: scope(hub))
        flow.step(.selectPublic)
        DispatchQueue.concurrentPerform(iterations: 64) { _ in
            flow.finish(.success)
        }
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(flow.recordedStepCount, 0)
    }

    func testDisableSerializesWithAnAlreadyAdmittedSink() {
        let hub = hub()
        let scope = scope(hub)
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        let finished = expectation(description: "send finished")
        let disabled = expectation(description: "disabled")
        hub.setSink({ _, _ in
            entered.signal()
            XCTAssertEqual(release.wait(timeout: .now() + 5), .success)
        }, owner: owner)
        DispatchQueue.global().async {
            hub.send(AnalyticsEvents.appForeground(), scope: scope)
            finished.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 5), .success)
        DispatchQueue.global().async {
            hub.isEnabled = false
            disabled.fulfill()
        }
        release.signal()
        wait(for: [finished, disabled], timeout: 5)
        XCTAssertFalse(scope?.isValid ?? true)
        hub.isEnabled = true
        hub.setSink({ [unowned self] in sent.append(($0, $1)) }, owner: owner)
        hub.send(AnalyticsEvents.appForeground(), scope: scope)
        XCTAssertTrue(sent.isEmpty)
    }
}
