import AppAnalytics
import Foundation
import ObjectiveC
import SwiftSignalKit
import TelegramContext
import TGUIKit

private var browserAnalyticsOriginKey: UInt8 = 0

final class BrowserAnalyticsOrigin {
    private(set) var context: AnalyticsContext
    private var presentation: AnalyticsPresentation?

    init(account: any AccountContextProtocol, data: BrowserTabData.Data, inherited: AnalyticsContext?) {
        var context = Analytics.shared.captureContext(engine: account.engine, peerId: account.peerId, inherited: inherited ?? Analytics.shared.unresolvedContext())
        if let peer = data.peer { context = context.restricting(peerId: peer.id) }
        switch data {
        case let .webapp(_, peerId, _, _, _, _, replyTo, _):
            context = context.restricting(peerId: peerId)
            if let replyTo { context = context.restricting(peerId: replyTo.peerId) }
        case let .straight(_, peerId, _, _):
            context = context.restricting(peerId: peerId)
        case let .game(_, peerId, messageId):
            context = context.restricting(peerId: peerId).restricting(peerId: messageId.peerId)
        case .mainapp, .simple, .tonsite, .instantView:
            break
        }
        self.context = context
        self.presentation = context.beginPresentation()
    }

    func inherit(_ incoming: BrowserAnalyticsOrigin) {
        let context = self.context.isExcluded || !incoming.context.isExcluded ? self.context : incoming.context
        let presentation = context.beginPresentation()
        self.context = context
        self.presentation = presentation
    }

    func bind(_ controller: ViewController) {
        objc_setAssociatedObject(controller, &browserAnalyticsOriginKey, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        controller.analyticsContext = context
    }

    func perform<T>(_ action: () -> T) -> T {
        let delivery = context.beginPresentation()
        defer { delivery.end() }
        return action()
    }

    func preserving<Value, Failure>(_ signal: Signal<Value, Failure>) -> Signal<Value, Failure> {
        return context.preservingPresentation(signal)
    }

    func end() {
        presentation?.end()
        presentation = nil
    }
}

final class BrowserDecision {
    let origin: BrowserAnalyticsOrigin
    private var resolved = false
    private var dismissalScheduled = false

    init(origin: BrowserAnalyticsOrigin) {
        self.origin = origin
    }

    func resolve(_ action: () -> Void) {
        guard !resolved else { return }
        resolved = true
        defer { origin.end() }
        origin.perform(action)
    }

    func dismissed() {
        guard !dismissalScheduled else { return }
        dismissalScheduled = true
        DispatchQueue.main.async {
            self.resolved = true
            self.origin.end()
        }
    }
}
