import Cocoa
import Foundation
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AvatarUI
import AlertsUI
import TelegramMediaUtils
import TelegramMedia
import LocalAnimations
import CurrencyFormat
import PremiumStatusUI
import SceneEffects
import DustLayer
import InAppPurchaseManager
import ObjcUtils
import PremiumUI
import CalendarUtils
import DateUtils
import LokiRng
import FoundationUtils
import InputView
import InputTextView
import InlineStickerLayer
import AppAnalytics


private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let openPeer:(EnginePeer.Id)->Void
    public init(context: (any AccountContextProtocol), openPeer:@escaping(EnginePeer.Id)->Void) {
        self.context = context
        self.openPeer = openPeer
    }
}

private struct State : Equatable {
    public struct Acquired: Equatable {
        public struct Bid : Equatable {
            public var amount: Int64
            public var place: Int32
            public init(amount: Int64, place: Int32) {
                self.amount = amount
                self.place = place
            }
        }
        public var round: Int32
        public var recepient: EnginePeer
        public var date: Int32
        public var acceptedBid: Bid
        public init(round: Int32, recepient: EnginePeer, date: Int32, acceptedBid: Bid) {
            self.round = round
            self.recepient = recepient
            self.date = date
            self.acceptedBid = acceptedBid
        }
    }
    public var gift: StarGift.Gift
    public var list: [Acquired] = []
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
  
    // entries
    
    for item in state.list {

        var rows: [InputDataTableBasedItem.Row] = []

        let roundAttr = NSMutableAttributedString()
        
        let num = item.acceptedBid.place * item.round * (state.gift.auctionGiftsPerRound ?? 0)
        let title = state.gift.title ?? ""
        roundAttr.append(
            string: clown_space + strings().starAuctionAcquiredGiftNumber(title, "\(num)", "\(item.round)"),
            color: theme.colors.text,
            font: .medium(.text)
        )
        roundAttr.insertEmbedded(.embeddedAnimated(state.gift.file), for: clown)

        rows.append(.init(left: nil, right: .init(name: .init(roundAttr))))

        let toPeer: String
        let escaped = escapeMarkdownSpecialCharacters(in: item.recepient._asPeer().compactDisplayTitle)
        toPeer = "[\(escaped)](peer_id_\(item.recepient.id.toInt64()))"

        let to: TextViewLayout = .init(
            parseMarkdownIntoAttributedString(
                toPeer,
                attributes: MarkdownAttributes(
                    body: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.text),
                    bold: MarkdownAttributeSet(font: .bold(.text), textColor: theme.colors.text),
                    link: MarkdownAttributeSet(font: .medium(.text), textColor: theme.colors.accentIcon),
                    linkAttribute: { contents in (NSAttributedString.Key.link.rawValue, contents) }
                )
            ),
            maximumNumberOfLines: 1,
            alwaysStaticItems: true
        )

        to.interactions.processURL = { url in
            if let url = url as? String, url.hasPrefix("peer_id_") {
                arguments.openPeer(item.recepient.id)
            }
        }

        rows.append(
            .init(
                left: .init(.initialize(string: strings().starAuctionAcquiredRecipient, color: theme.colors.text, font: .normal(.text))),
                right: .init(
                    name: to,
                    leftView: { previous in
                        let control: AvatarControl = (previous as? AvatarControl) ?? AvatarControl(font: .avatar(6))
                        control.setFrameSize(NSMakeSize(20, 20))
                        control.setPeer(account: arguments.context.account, peer: item.recepient._asPeer())
                        return control
                    }
                )
            )
        )

        rows.append(
            .init(
                left: .init(.initialize(string: strings().starTransactionDate, color: theme.colors.text, font: .normal(.text))),
                right: .init(
                    name: .init(.initialize(string: stringForFullDate(timestamp: item.date), color: theme.colors.text, font: .normal(.text)))
                )
            )
        )

        rows.append(
            .init(
                left: .init(.initialize(string: strings().starAuctionAcquiredAcceptedBid, color: theme.colors.text, font: .normal(.text))),
                right: InputDataTableBasedItem.Row.Right(
                    name: .init(.initialize(string: item.acceptedBid.amount.formattedWithSeparator, color: theme.colors.text, font: .normal(.text))),
                    leftView: { previous in
                        let imageView = previous as? ImageView ?? ImageView()
                        imageView.image = TelegramThemeHooks.shared.image(.iconStarCurrency).precomposed()
                        imageView.setFrameSize(18, 18)
                        imageView.contentGravity = .resizeAspectFill
                        return imageView
                    },
                    badge: .init(text: strings().starAuctionAcquiredTopRank(Int(item.acceptedBid.place)), callback: { })
                )
            )
        )

        entries.append(
            .custom(
                sectionId: sectionId,
                index: index,
                value: .none,
                identifier: .init("_id_\(item.round)"),
                equatable: .init(state),
                comparable: nil,
                item: { initialSize, stableId in
                    InputDataTableBasedItem(initialSize, stableId: stableId, viewType: .singleItem, rows: rows, context: arguments.context)
                }
            )
        )
        index += 1

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
    }

    return entries
}

public func Star_AuctionAcquiredController(context: (any AccountContextProtocol), gift: StarGift.Gift, gifts: [GiftAuctionAcquiredGift]) -> InputDataModalController {
    
    let actionsDisposable = DisposableSet()
   
    
    let initialState = State(gift: gift, list:  gifts.map {
        .init(round: $0.round, recepient: $0.peer, date: $0.date, acceptedBid: .init(amount: $0.bidAmount, place: $0.position))
    })
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return getController?()?.window ?? context.window
        }
    }

    let arguments = Arguments(context: context, openPeer: { peerId in
        closeAllModals(window: window)
        StarsHooks.shared.openPeerInfo(context, peerId)
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(
        dataSignal: signal,
        title: strings().starAuctionAcquiredItemsBoughtOther(gifts.count)
    )
    controller.analyticsScreen = .giftsAuctionAcquired

    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().modalOK, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.validateData = { [weak modalController] _ in
        modalController?.close()
        return .none
    }

    return modalController
    
}
