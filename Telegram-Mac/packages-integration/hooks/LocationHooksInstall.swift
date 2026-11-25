import Cocoa
import MapKit
import TGUIKit
import Postbox
import TelegramCore
import SwiftSignalKit
import LocationUI
import AppAnalytics

func installLocationUIHooks() {
    let confirmSend: (any LocationChatInteraction, AnalyticsContext, @escaping () -> Void) -> Void = { interaction, analyticsContext, invoke in
        let accountContext = interaction.locationContext
        let getAnalyticsContext = {
            Analytics.shared.captureContext(engine: accountContext.engine, peerId: interaction.locationPeerId, inherited: analyticsContext)
        }
        let analyticsPresentation = getAnalyticsContext().beginPresentation()
        defer { analyticsPresentation.end() }
        guard let chatInteraction = interaction as? ChatInteraction else {
            invoke()
            return
        }
        let presentation = chatInteraction.presentation
        let context = chatInteraction.context

        let messagesCount = 1

        guard let payStars = presentation.sendPaidMessageStars, let peer = presentation.peer, let starsState = presentation.starsState else {
            invoke()
            return
        }
        let starsPrice = Int(payStars.value * Int64(messagesCount))
        let amount = strings().starListItemCountOther(starsPrice)

        let buyMore:()->Void = {
            let presentation = getAnalyticsContext().beginPresentation()
            defer { presentation.end() }
            showModal(with: Star_ListScreen(context: context, source: .buy(suffix: nil, amount: Int64(starsPrice)), analyticsContext: getAnalyticsContext()), for: context.window)
        }

        if !presentation.alwaysPaidMessage {
            let messageCountText = strings().chatPayStarsConfirmMessagesOther(messagesCount)
            let confirmationPresentation = getAnalyticsContext().beginPresentation()
            verifyAlert(for: context.window, header: strings().chatPayStarsConfirmTitle, information: strings().chatPayStarsConfirmText(peer.displayTitle, amount, amount, messageCountText), ok: strings().chatPayStarsConfirmPayOther(messagesCount), option: strings().chatPayStarsConfirmCheckbox, optionIsSelected: false, successHandler: { result in
                let presentation = getAnalyticsContext().beginPresentation()
                defer { presentation.end() }
                if starsState.balance.value > starsPrice {
                    chatInteraction.update({ current in
                        return current
                            .withUpdatedAlwaysPaidMessage(result == .thrid)
                    })
                    if result == .thrid {
                        FastSettings.toggleCofirmPaid(peer.id, price: starsPrice)
                    }
                    invoke()
                } else {
                    buyMore()
                }
            }, onDeinit: { confirmationPresentation.end() })
        } else {
            if starsState.balance.value > starsPrice {
                invoke()
            } else {
                buyMore()
            }
        }
    }
    var hooks = LocationHooks(confirmSend: { interaction, invoke in
        confirmSend(interaction, Analytics.shared.unresolvedContext(), invoke)
    })
    hooks.confirmSendWithContext = confirmSend
    installLocationHooks(hooks)
}

