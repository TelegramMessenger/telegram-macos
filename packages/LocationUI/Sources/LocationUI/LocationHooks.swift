import Cocoa
import MapKit
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import TelegramContext
import AppAnalytics

public protocol LocationChatInteraction: AnyObject {
    var locationContext: (any AccountContextProtocol) { get }
    var locationPeerId: PeerId { get }
    func sendPickedLocation(_ coordinate: CLLocationCoordinate2D, _ venue: MapVenue?)
}

public struct LocationHooks {
    public let confirmSend: (any LocationChatInteraction, @escaping () -> Void) -> Void

    public var confirmSendWithContext: ((any LocationChatInteraction, AnalyticsContext, @escaping () -> Void) -> Void)?

    public func confirmSendObserved(_ interaction: any LocationChatInteraction, analyticsContext: AnalyticsContext, invoke: @escaping () -> Void) {
        let context = interaction.locationContext
        let origin = Analytics.shared.captureContext(engine: context.engine, peerId: interaction.locationPeerId, inherited: analyticsContext)
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        let confirmed = {
            let current = Analytics.shared.captureContext(engine: context.engine, peerId: interaction.locationPeerId, inherited: origin)
            let presentation = current.beginPresentation()
            defer { presentation.end() }
            invoke()
        }
        if let confirmSendWithContext {
            confirmSendWithContext(interaction, origin, confirmed)
        } else {
            origin.scope?.exclude()
            let fallback = Analytics.shared.unresolvedContext().beginPresentation()
            confirmSend(interaction) {
                withExtendedLifetime(fallback) { confirmed() }
            }
        }
    }

    public init(confirmSend: @escaping (any LocationChatInteraction, @escaping () -> Void) -> Void) {
        self.confirmSend = confirmSend
    }

    private static var value: LocationHooks?

    public static var shared: LocationHooks {
        guard let value = value else {
            preconditionFailure("LocationHooks not installed")
        }
        return value
    }

    public static func install(_ hooks: LocationHooks) {
        self.value = hooks
    }
}

public func installLocationHooks(_ hooks: LocationHooks) {
    LocationHooks.install(hooks)
}
