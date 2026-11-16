import Foundation
import ObjectiveC
import Postbox
import TelegramCore
import TGUIKit
import SwiftSignalKit

public final class AnalyticsContext {
    public let scope: AnalyticsScope?
    let privacy: AnalyticsPrivacy
    let policy: AnalyticsCollectionPolicy
    weak var analytics: Analytics?

    init(analytics: Analytics, privacy: AnalyticsPrivacy, scope: AnalyticsScope?) {
        self.analytics = analytics
        self.policy = analytics.policy
        self.privacy = privacy
        self.scope = privacy == .ordinary ? scope : nil
    }

    public var isExcluded: Bool {
        return privacy != .ordinary || scope?.isExcluded == true
    }

    public func restricting(peerId: PeerId) -> AnalyticsContext {
        guard let analytics = analytics else { return self }
        let destination = AnalyticsPrivacy(peerId: peerId)
        return AnalyticsContext(analytics: analytics, privacy: isExcluded ? privacy : destination, scope: scope)
    }

    public func beginPresentation() -> AnalyticsPresentation {
        return AnalyticsPresentation(context: self)
    }

    public func preservingPresentation<Value, Failure>(_ signal: Signal<Value, Failure>) -> Signal<Value, Failure> {
        return Signal { subscriber in
            let presentation = self.beginPresentation()
            let disposable = signal.start(next: { value in
                let delivery = self.beginPresentation()
                withExtendedLifetime(delivery) { subscriber.putNext(value) }
            }, error: { error in
                let delivery = self.beginPresentation()
                withExtendedLifetime(delivery) { subscriber.putError(error) }
            }, completed: {
                let delivery = self.beginPresentation()
                withExtendedLifetime(delivery) { subscriber.putCompletion() }
            })
            return ActionDisposable {
                let cleanup = self.beginPresentation()
                defer { cleanup.end() }
                disposable.dispose()
                presentation.end()
            }
        }
    }
}

public final class AnalyticsPresentation: AnalyticsRevocable {
    private let context: AnalyticsContext
    private let owner = NSObject()
    private var active = true

    fileprivate init(context: AnalyticsContext) {
        self.context = context
        context.policy.sync {
            context.policy.setExcluded(context.isExcluded || !context.policy.accepts(context.scope), owner: ObjectIdentifier(owner))
            context.scope?.observePrivacy(self)
        }
    }

    func revokeAnalytics() {
        guard active, context.isExcluded else { return }
        context.policy.setExcluded(true, owner: ObjectIdentifier(owner))
    }

    public func end() {
        context.policy.sync {
            guard active else { return }
            active = false
            context.scope?.removePrivacyObserver(self)
            context.policy.setExcluded(false, owner: ObjectIdentifier(owner))
        }
    }

    deinit {
        end()
    }
}

extension AnalyticsPrivacy {
    init(peerId: PeerId) {
        switch peerId.namespace {
        case Namespaces.Peer.SecretChat:
            self = .excluded
        case Namespaces.Peer.CloudUser, Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudChannel:
            self = .ordinary
        default:
            self = .unresolved
        }
    }
}

public extension Analytics {
    func unresolvedContext() -> AnalyticsContext {
        return AnalyticsContext(analytics: self, privacy: .unresolved, scope: nil)
    }

    func privacyContext(peerId: PeerId) -> AnalyticsContext {
        return AnalyticsContext(analytics: self, privacy: AnalyticsPrivacy(peerId: peerId), scope: nil)
    }

    func captureContext(engine: TelegramEngine, peerId: PeerId, inherited: AnalyticsContext? = nil) -> AnalyticsContext {
        return captureContext(owner: engine.account, privacy: AnalyticsPrivacy(peerId: peerId), inherited: inherited)
    }
}

extension Analytics {
    func captureContext(owner: AnyObject, privacy: AnalyticsPrivacy, inherited: AnalyticsContext? = nil) -> AnalyticsContext {
        return policy.sync {
            if let inherited = inherited {
                guard inherited.policy === policy, !inherited.isExcluded, privacy == .ordinary else {
                    return AnalyticsContext(analytics: self, privacy: .excluded, scope: nil)
                }
                let scope = policy.accepts(inherited.scope, owner: owner) ? inherited.scope : nil
                return AnalyticsContext(analytics: self, privacy: .ordinary, scope: scope)
            }
            if privacy != .ordinary || policy.hasExclusions {
                return AnalyticsContext(analytics: self, privacy: privacy == .unresolved ? .unresolved : .excluded, scope: nil)
            }
            return AnalyticsContext(analytics: self, privacy: .ordinary, scope: policy.makeScope(owner: owner, privacy: privacy))
        }
    }

    func excludedContext() -> AnalyticsContext {
        return AnalyticsContext(analytics: self, privacy: .excluded, scope: nil)
    }
}

private var analyticsContextKey: UInt8 = 0

public extension ViewController {
    var analyticsContext: AnalyticsContext? {
        get { objc_getAssociatedObject(self, &analyticsContextKey) as? AnalyticsContext }
        set {
            let previous = analyticsContext
            objc_setAssociatedObject(self, &analyticsContextKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            previous?.analytics?.screens.contextChanged(self)
            if previous?.analytics !== newValue?.analytics {
                newValue?.analytics?.screens.contextChanged(self)
            }
        }
    }
}
