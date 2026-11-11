import Foundation
import ObjectiveC
import TelegramCore
import Postbox
import TGUIKit

public final class Analytics {
    public typealias Sink = (_ type: String, _ data: JSON) -> Void

    public static let shared = Analytics()
    public let screens: AnalyticsScreenTracker

    let policy = AnalyticsCollectionPolicy()
    private var sink: Sink?
    private var appLogContext: AppLogEventContext?
    private var logger: ((String) -> Void)?
    private var sessionId = UUID().uuidString
    private var seq = 0
    private var currentLayout: AnalyticsValues.Layout = .regular
    private let clock: () -> TimeInterval

    public init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
        self.screens = AnalyticsScreenTracker(clock: clock)
        self.screens.analytics = self
        policy.didRevoke = { [weak self] in
            self?.appLogContext?.invalidate()
            self?.appLogContext = nil
            self?.screens.reset()
            self?.startSession()
        }
    }

    public var now: TimeInterval {
        return clock()
    }

    public var log: ((String) -> Void)? {
        get { policy.sync { logger } }
        set { policy.sync { logger = newValue } }
    }

    public func setEngine(_ engine: TelegramEngine?) {
        if let engine = engine {
            setSink({ [weak self] type, data in
                guard let self = self else { return }
                if self.appLogContext == nil {
                    self.appLogContext = engine.accountData.createAppLogEventContext()
                }
                if let context = self.appLogContext {
                    engine.accountData.addAppLogEvent(type: type, data: data, context: context)
                }
            }, owner: engine.account)
        } else {
            setSink(nil, owner: nil)
        }
    }

    public var isEnabled: Bool {
        get { policy.isEnabled }
        set { policy.isEnabled = newValue }
    }

    func setSink(_ sink: Sink?, owner: AnyObject?) {
        policy.sync {
            self.sink = sink
            policy.setOwner(sink == nil ? nil : owner)
        }
    }

    public func makeScope(engine: TelegramEngine, privacy: AnalyticsPrivacy) -> AnalyticsScope? {
        return policy.makeScope(owner: engine.account, privacy: privacy)
    }

    public func makeScope(engine: TelegramEngine, peerId: PeerId) -> AnalyticsScope? {
        return makeScope(engine: engine, privacy: AnalyticsPrivacy(peerId: peerId))
    }

    public func setExcluded(_ excluded: Bool, owner: AnyObject) {
        policy.setExcluded(excluded, owner: ObjectIdentifier(owner))
    }

    public func setLayout(_ layout: AnalyticsValues.Layout) {
        policy.sync { currentLayout = layout }
    }

    public func startSession() {
        policy.sync {
            sessionId = UUID().uuidString
            seq = 0
        }
    }

    public func send(_ event: @autoclosure () -> AnalyticsEvent, scope: AnalyticsScope? = nil) {
        policy.sync {
            guard policy.accepts(scope) else { return }
            let event = event()
            sendRaw(type: event.name.rawValue, data: .dictionary(event.params), scope: scope)
        }
    }

    public func sendRaw(type: String, data: @autoclosure () -> JSON, scope: AnalyticsScope? = nil) {
        policy.sync {
            guard policy.accepts(scope), let sink = sink, case let .dictionary(params) = data() else { return }
            guard policy.accepts(scope), !Self.containsExcludedContext(params), Self.validate(type: type, params: params).isEmpty else { return }
            var values = params
            for (key, value) in AnalyticsCommon.params() {
                values[key] = value
            }
            values["session_id"] = .string(sessionId)
            values["seq"] = .number(Double(seq))
            values["layout"] = .string(currentLayout.rawValue)
            guard Self.validate(type: type, params: values).isEmpty else { return }
            #if DEBUG
            logger?("\(type) \(JSON.dictionary(values).string ?? "")")
            #endif
            guard policy.accepts(scope) else { return }
            seq += 1
            sink(type, .dictionary(values))
        }
    }

    private static func containsExcludedContext(_ params: [String: JSON]) -> Bool {
        if params["peer_type"] == .string(AnalyticsValues.PeerType.secretChat.rawValue) {
            return true
        }
        for key in ["screen", "source"] {
            if case let .string(value)? = params[key], let screen = AnalyticsScreen(rawValue: value), screen.isAnalyticsExcluded {
                return true
            }
        }
        return false
    }

    public static func validate(type: String, params: [String: JSON]) -> [String] {
        return AnalyticsValidation.validate(type: type, params: params)
    }
}

public final class AnalyticsScreenTracker {
    private struct Visible {
        let screen: AnalyticsScreen
        let start: TimeInterval
        let scope: AnalyticsScope
    }

    weak var analytics: Analytics?
    private let clock: () -> TimeInterval
    private var visible: [ObjectIdentifier: Visible] = [:]
    private var order: [ObjectIdentifier] = []
    private var presenting = Set<ObjectIdentifier>()
    private var contexts: [ObjectIdentifier: AnalyticsContext] = [:]

    init(clock: @escaping () -> TimeInterval) {
        self.clock = clock
    }

    public var current: AnalyticsScreen? {
        return analytics?.policy.sync {
            order.last.flatMap { visible[$0]?.screen }
        }
    }

    public static func screen(for controller: ViewController) -> AnalyticsScreen? {
        if let id = controller.analyticsScreenId {
            return AnalyticsScreen(rawValue: id)
        }
        var name = String(describing: type(of: controller))
        if let generic = name.firstIndex(of: "<") {
            name = String(name[..<generic])
        }
        return AnalyticsCoverage.screenForClass[name]
    }

    public func willAppear(_ controller: ViewController) {
        guard let analytics = analytics else { return }
        analytics.policy.sync {
            prepareContext(controller)
            presenting.insert(ObjectIdentifier(controller))
        }
    }

    func contextChanged(_ controller: ViewController) {
        guard let analytics = analytics else { return }
        analytics.policy.sync {
            let id = ObjectIdentifier(controller)
            guard presenting.contains(id) else { return }
            prepareContext(controller)
            visible.removeValue(forKey: id)
            order.removeAll { $0 == id }
        }
    }

    private func prepareContext(_ controller: ViewController) {
        guard let analytics = analytics else { return }
        if controller.analyticsContext == nil, controller.analyticsScope == nil, analytics.policy.hasExclusions {
            controller.analyticsContext = analytics.excludedContext()
        }
        let id = ObjectIdentifier(controller)
        let context = controller.analyticsContext
        contexts[id] = context
        let excluded = context.map { $0.isExcluded || $0.policy !== analytics.policy } ?? false
        analytics.policy.setExcluded(excluded || controller.analyticsPeer == .secretChat || Self.screen(for: controller)?.isAnalyticsExcluded == true, owner: id)
    }

    public func didAppear(_ controller: ViewController) {
        willAppear(controller)
        let peerType = controller.analyticsPeerType.flatMap(AnalyticsValues.PeerType.init(rawValue:))
        if peerType == .secretChat {
            analytics?.setExcluded(true, owner: controller)
            return
        }
        guard let screen = AnalyticsScreenTracker.screen(for: controller) else { return }
        show(ObjectIdentifier(controller), screen: screen, peerType: peerType, scope: controller.analyticsScope, context: controller.analyticsContext)
    }

    public func didDisappear(_ controller: ViewController) {
        hide(ObjectIdentifier(controller))
    }

    public func didDeinit(_ id: ObjectIdentifier) {
        hide(id)
    }

    public func show(_ id: ObjectIdentifier, screen: AnalyticsScreen, peerType: AnalyticsValues.PeerType? = nil) {
        show(id, screen: screen, peerType: peerType, scope: nil, context: nil)
    }

    public func show(_ id: ObjectIdentifier, screen: AnalyticsScreen, peerType: AnalyticsValues.PeerType? = nil, scope: AnalyticsScope?) {
        show(id, screen: screen, peerType: peerType, scope: scope, context: nil)
    }

    public func show(_ id: ObjectIdentifier, screen: AnalyticsScreen, peerType: AnalyticsValues.PeerType? = nil, scope: AnalyticsScope? = nil, context: AnalyticsContext?) {
        guard let analytics = analytics else { return }
        analytics.policy.sync {
            let context = context ?? contexts[id] ?? (scope == nil && analytics.policy.hasExclusions ? analytics.excludedContext() : nil)
            contexts[id] = context
            presenting.insert(id)
            let excluded = context.map { $0.isExcluded || $0.policy !== analytics.policy } ?? false
            analytics.policy.setExcluded(excluded || screen.isAnalyticsExcluded || peerType == .secretChat, owner: id)
            let scope = context == nil ? scope : context?.scope
            guard analytics.policy.accepts(scope), let scope = scope else { return }
            if let existing = visible[id] {
                if existing.screen == screen && existing.scope === scope {
                    return
                }
                hide(id)
                contexts[id] = context
                presenting.insert(id)
            }
            let source = order.last.flatMap { visible[$0]?.screen }
            let start = clock()
            guard analytics.policy.accepts(scope), start.isFinite else { return }
            visible[id] = Visible(screen: screen, start: start, scope: scope)
            order.append(id)
            analytics.send(AnalyticsEvents.screenShow(screen: screen, source: source, peerType: peerType), scope: scope)
        }
    }

    public func hide(_ id: ObjectIdentifier) {
        guard let analytics = analytics else { return }
        analytics.policy.sync {
            if let entry = visible.removeValue(forKey: id) {
                order.removeAll(where: { $0 == id })
                if let duration = AnalyticsValidation.elapsedMilliseconds(since: entry.start, now: clock()) {
                    analytics.send(AnalyticsEvents.screenHide(screen: entry.screen, durationMs: duration), scope: entry.scope)
                }
            }
            contexts.removeValue(forKey: id)
            presenting.remove(id)
            analytics.policy.setExcluded(false, owner: id)
        }
    }

    public func showStandalone(_ screen: AnalyticsScreen, owner: AnyObject) {
        showStandalone(screen, owner: owner, scope: nil, context: nil)
    }

    public func showStandalone(_ screen: AnalyticsScreen, owner: AnyObject, scope: AnalyticsScope?) {
        showStandalone(screen, owner: owner, scope: scope, context: nil)
    }

    public func showStandalone(_ screen: AnalyticsScreen, owner: AnyObject, scope: AnalyticsScope? = nil, context: AnalyticsContext?) {
        show(ObjectIdentifier(owner), screen: screen, scope: scope, context: context)
    }

    public func hideStandalone(owner: AnyObject) {
        hide(ObjectIdentifier(owner))
    }

    public func reset() {
        analytics?.policy.sync {
            visible.removeAll()
            order.removeAll()
            for (id, context) in contexts where context.isExcluded {
                analytics?.policy.setExcluded(true, owner: id)
            }
        }
    }
}

extension AnalyticsScreen {
    var isAnalyticsExcluded: Bool {
        switch self {
        case .createSecretChat, .peerInfoEncryptionKey:
            return true
        default:
            return false
        }
    }
}

private var analyticsScopeKey: UInt8 = 0

public extension ViewController {
    var analyticsScope: AnalyticsScope? {
        get { objc_getAssociatedObject(self, &analyticsScopeKey) as? AnalyticsScope }
        set { objc_setAssociatedObject(self, &analyticsScopeKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    var analyticsScreen: AnalyticsScreen? {
        get {
            return analyticsScreenId.flatMap(AnalyticsScreen.init(rawValue:))
        }
        set {
            analyticsScreenId = newValue?.rawValue
        }
    }

    var analyticsPeer: AnalyticsValues.PeerType? {
        get {
            return analyticsPeerType.flatMap(AnalyticsValues.PeerType.init(rawValue:))
        }
        set {
            analyticsPeerType = newValue?.rawValue
        }
    }

    @discardableResult
    func analytics(_ screen: AnalyticsScreen, peer: AnalyticsValues.PeerType? = nil) -> Self {
        self.analyticsScreen = screen
        if let peer = peer {
            self.analyticsPeer = peer
        }
        return self
    }
}

public extension AnalyticsValues.PeerType {
    init(peer: Peer, accountPeerId: PeerId? = nil) {
        if let accountPeerId = accountPeerId, peer.id == accountPeerId {
            self = .savedMessages
        } else if peer is TelegramSecretChat {
            self = .secretChat
        } else if let user = peer as? TelegramUser {
            self = user.botInfo != nil ? .bot : .user
        } else if let channel = peer as? TelegramChannel {
            if channel.flags.contains(.isForum) {
                self = .forum
            } else if case .group = channel.info {
                self = .group
            } else {
                self = .channel
            }
        } else {
            self = .group
        }
    }
}

public enum AnalyticsLifecycle {
    public static func install() {
        ViewControllerLifecycleHooks.willAppear = { controller in
            Analytics.shared.screens.willAppear(controller)
        }
        ViewControllerLifecycleHooks.didAppear = { controller in
            Analytics.shared.screens.didAppear(controller)
        }
        ViewControllerLifecycleHooks.didDisappear = { controller in
            Analytics.shared.screens.didDisappear(controller)
        }
        ViewControllerLifecycleHooks.didDeinit = { id in
            Analytics.shared.screens.didDeinit(id)
        }
    }
}
