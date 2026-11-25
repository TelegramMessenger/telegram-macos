import Foundation

import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import AlertsUI
import InAppSettings
import AvatarUI
import ShortPeerRow
import PremiumUI
import TelegramMedia
import AppAnalytics

private final class Arguments {
    public let context: any AccountContextProtocol
    public let openInfo:(PeerId)->Void
    public let premium:()->Void
    public init(context: any AccountContextProtocol, openInfo:@escaping(PeerId)->Void, premium:@escaping()->Void) {
        self.context = context
        self.openInfo = openInfo
        self.premium = premium
    }
}

private struct State : Equatable {
    public var channels: RecommendedChannels?
    public var isPremium: Bool
}

private func _id_channel(_ id: PeerId) -> InputDataIdentifier {
    return .init("_id_channel_\(id.toInt64())")
}
private let _id_more = InputDataIdentifier("_id_more")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index: Int32 = 0
        
    if let channels = state.channels {
        
        struct Tuple : Equatable {
            let channel: RecommendedChannels.Channel
            let viewType: GeneralViewType
            let status: String
        }
        var items: [Tuple] = []
        for (i, channel) in channels.channels.enumerated() {
            var viewType: GeneralViewType = bestGeneralViewType(channels.channels, for: i)
            viewType = .innerItem
            var status = strings().peerMediaStatusSubscribersOther(Int(channel.subscribers))
            status = status.replacingOccurrences(of: "\(channel.subscribers)", with: Int(channel.subscribers).prettyNumber)
            items.append(.init(channel: channel, viewType: viewType, status: status))
        }
        
        for item in items {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_channel(item.channel.peer.id), equatable: .init(item), comparable: nil, item: { initialSize, stableId in
                return ShortPeerRowItem(initialSize, peer: item.channel.peer._asPeer(), account: arguments.context.account, context: arguments.context, status: item.status, inset: .init(), viewType: item.viewType, action: {
                    arguments.openInfo(item.channel.peer.id)
                }, highlightVerified: true)
            }))
        }
       
        let limit = arguments.context.appConfiguration.getGeneralValue("recommended_channels_limit_premium", orElse: 0)
        
        if !state.isPremium {
            
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_more, equatable: .init(state.isPremium), comparable: nil, item: { initialSize, stableId in
                return GeneralBlockTextRowItem(initialSize, stableId: stableId, viewType: .innerItem, text: strings().channelSimilarPremium(Int(limit)), font: .normal(.text), insets: .init(), centerViewAlignment: true, linkCallback: { _ in
                    arguments.premium()
                })
            }))
//            entries.append(.sectionId(sectionId, type: .normal))
//            sectionId += 1
        }
    }
    
    
    
    return entries
}

public func SimilarChannelsController(context: any AccountContextProtocol, peerId: PeerId, recommendedChannels: RecommendedChannels?, analyticsContext: AnalyticsContext? = nil) -> InputDataController {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let presentation = origin.beginPresentation()
    defer { presentation.end() }

    let actionsDisposable = DisposableSet()
    

    let initialState = State(channels: recommendedChannels, isPremium: context.isPremium)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    let isPremium = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: context.account.peerId))
    |> map { peer -> Bool in
        return peer?.isPremium ?? false
    }


    actionsDisposable.add(combineLatest(context.engine.peers.recommendedChannels(peerId: peerId), isPremium).start(next: { channels, isPremium in
        updateState { current in
            var current = current
            current.channels = channels
            current.isPremium = isPremium
            return current
        }
    }))
    

    let arguments = Arguments(context: context, openInfo: { selectedPeerId in
        let targetOrigin = Analytics.shared.captureContext(engine: context.engine, peerId: selectedPeerId, inherited: origin)
        let presentation = targetOrigin.beginPresentation()
        defer { presentation.end() }
        Analytics.shared.send(AnalyticsEvents.peerInfoRecommendationSelect(kind: .channel, selection: .peer), scope: targetOrigin.scope)
        SimilarPeersHooks.shared.openChatObserved(context, selectedPeerId, analyticsContext: targetOrigin)
    }, premium: {
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        Analytics.shared.send(AnalyticsEvents.peerInfoRecommendationSelect(kind: .channel, selection: .premium), scope: origin.scope)
        prem(with: PremiumBoardingController(context: context, source: .recommended_channels, analyticsContext: origin), for: context.window)
    })

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().peerMediaSimilarChannels)
    controller.analyticsContext = origin
    controller.analyticsScreen = .peerInfoMediaSimilarChannels
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    return controller
    
}
