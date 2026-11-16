import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import InputDataUI
import Localization
import Postbox
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import WalletContext
import AppAnalytics

public enum WalletInfoMode {
    case wallet
    case gram
    case firstGrams
    case recovery
}

struct WalletInfoItem: Equatable {
    let id: String
    let title: String?
    let text: String
    let iconName: String
    var textIconName: String? = nil
}

enum WalletInfoLogo: Equatable {
    case diamond
    case animation(WalletUIAnimation)
}

struct WalletInfoContent: Equatable {
    let logo: WalletInfoLogo
    let logoSize: NSSize
    let title: String
    let text: String
    let items: [WalletInfoItem]
    let buttonTitle: String
    var terms: String? = nil
}

func walletInfoContent(mode: WalletInfoMode, fiatRateText: String?, gaslessDailyTransfers: Int32) -> WalletInfoContent {
    switch mode {
    case .wallet:
        let title = strings().walletInfoControllerHowItWorks
        let text = strings().walletInfoControllerHowItWorksInfo
        let instantTransfersTitle = strings().walletInfoControllerInstantTransfers
        let instantTransfersText = strings().walletInfoControllerInstantTransfersInfo
        let zeroFeesTitle = strings().walletInfoControllerZeroFees
        let zeroFeesText = strings().walletInfoControllerZeroFeesInfoOther(Int(gaslessDailyTransfers))
        let blockchainVerifiedTitle = strings().walletInfoControllerBlockchainVerified
        let blockchainVerifiedText = strings().walletInfoControllerBlockchainVerifiedInfo
        let buttonTitle = strings().walletInfoControllerGotIt

        return WalletInfoContent(
            logo: .diamond,
            logoSize: NSMakeSize(100, 100),
            title: title,
            text: text,
            items: [
                WalletInfoItem(
                    id: "instantTransfers",
                    title: instantTransfersTitle,
                    text: instantTransfersText,
                    iconName: "Wallet_InfoFast"
                ),
                WalletInfoItem(
                    id: "zeroFees",
                    title: zeroFeesTitle,
                    text: zeroFeesText,
                    iconName: "Wallet_InfoCheap"
                ),
                WalletInfoItem(
                    id: "blockchainVerified",
                    title: blockchainVerifiedTitle,
                    text: blockchainVerifiedText,
                    iconName: "Wallet_InfoVerified"
                )
            ],
            buttonTitle: buttonTitle,
            terms: walletTermsText
        )
    case .firstGrams:
        let title = strings().walletInfoControllerFirstGrams
        let text: String
        if let fiatRateText {
            text = strings().walletInfoControllerFirstGramsRateInfo(fiatRateText)
        } else {
            text = strings().walletInfoControllerFirstGramsInfo
        }
        let sendTitle = strings().walletInfoControllerSend
        let sendText = strings().walletInfoControllerSendInfo
        let tradeTitle = strings().walletInfoControllerTrade
        let tradeText = strings().walletInfoControllerTradeInfo
        let storeTitle = strings().walletInfoControllerStore
        let storeText = strings().walletInfoControllerStoreInfo
        let buttonTitle = strings().walletInfoControllerGotIt
        return WalletInfoContent(
            logo: .diamond,
            logoSize: NSMakeSize(120, 120),
            title: title,
            text: text,
            items: [
                WalletInfoItem(id: "send", title: sendTitle, text: sendText, iconName: "Wallet_InfoSend", textIconName: "Wallet_InfoAttach"),
                WalletInfoItem(id: "trade", title: tradeTitle, text: tradeText, iconName: "Wallet_InfoTrade"),
                WalletInfoItem(id: "store", title: storeTitle, text: storeText, iconName: "Wallet_InfoStore", textIconName: "Wallet_InfoSettings")
            ],
            buttonTitle: buttonTitle
        )
    case .gram:
        let title = strings().walletInfoControllerGram
        let text: String
        if let fiatRateText {
            text = strings().walletInfoControllerGramRateInfo(fiatRateText)
        } else {
            text = strings().walletInfoControllerGramInfo
        }
        let fastTitle = strings().walletInfoControllerFast
        let fastText = strings().walletInfoControllerFastInfo
        let cheapTitle = strings().walletInfoControllerCheap
        let cheapText = strings().walletInfoControllerCheapInfo
        let usefulTitle = strings().walletInfoControllerUseful
        let usefulText = strings().walletInfoControllerUsefulInfo
        let buttonTitle = strings().walletInfoControllerGotIt

        return WalletInfoContent(
            logo: .diamond,
            logoSize: NSMakeSize(120, 120),
            title: title,
            text: text,
            items: [
                WalletInfoItem(
                    id: "fast",
                    title: fastTitle,
                    text: fastText,
                    iconName: "Wallet_InfoFast"
                ),
                WalletInfoItem(
                    id: "cheap",
                    title: cheapTitle,
                    text: cheapText,
                    iconName: "Wallet_InfoCheap"
                ),
                WalletInfoItem(
                    id: "useful",
                    title: usefulTitle,
                    text: usefulText,
                    iconName: "Wallet_InfoUseful"
                )
            ],
            buttonTitle: buttonTitle
        )
    case .recovery:
        let title = strings().walletInfoControllerSecretPhrase
        let text = strings().walletInfoControllerSecretPhraseInfo
        let neverShareText = strings().walletInfoControllerNeverShare
        let canStealText = strings().walletInfoControllerCanSteal
        let supportText = strings().walletInfoControllerSupportNeverAsks
        let buttonTitle = strings().walletInfoControllerShowSecretPhrase

        return WalletInfoContent(
            logo: .animation(.wallet_word_list),
            logoSize: NSMakeSize(100, 100),
            title: title,
            text: text,
            items: [
                WalletInfoItem(
                    id: "neverShare",
                    title: nil,
                    text: neverShareText,
                    iconName: "Wallet_InfoHidden"
                ),
                WalletInfoItem(
                    id: "canSteal",
                    title: nil,
                    text: canStealText,
                    iconName: "Wallet_InfoWarning"
                ),
                WalletInfoItem(
                    id: "support",
                    title: nil,
                    text: supportText,
                    iconName: "Wallet_InfoShield"
                )
            ],
            buttonTitle: buttonTitle
        )
    }
}

private final class Arguments {
    let context: any AccountContextProtocol
    let environment: WalletUIEnvironment
    init(context: any AccountContextProtocol, environment: WalletUIEnvironment) {
        self.context = context
        self.environment = environment
    }
}

private let _id_header = InputDataIdentifier("_id_header")
private func _id_item(_ id: String) -> InputDataIdentifier {
    return InputDataIdentifier("_id_item_\(id)")
}

private func entries(_ content: WalletInfoContent, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(content), comparable: nil, item: { initialSize, stableId in
        let title = NSMutableAttributedString()
        title.append(string: content.title, color: theme.colors.text, font: .medium(18))
        let info = NSMutableAttributedString()
        info.append(string: content.text, color: theme.colors.text, font: .normal(.text))
        info.detectBoldColorInString(with: .medium(.text))
        switch content.logo {
        case .diamond:
            return WalletInfoHeaderRowItem(initialSize, stableId: stableId, diamondSize: content.logoSize, title: title, text: info)
        case let .animation(animation):
            return arguments.environment.makeAnimatedHeader(
                initialSize,
                stableId: stableId,
                sticker: animation,
                text: title,
                infoText: info,
                stickerSize: content.logoSize,
                image: nil,
                viewType: .singleItem
            )
        }
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(30)))
    sectionId += 1

    for item in content.items {
        let emphasizesText = item.title == nil
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_item(item.id), equatable: .init(content), comparable: nil, item: { initialSize, stableId in
            return WalletInfoParagraphRowItem(
                initialSize,
                stableId: stableId,
                icon: NSImage(named: item.iconName)?.precomposed(walletClassicAccent),
                title: item.title,
                text: item.text,
                viewType: .singleItem,
                textColor: emphasizesText ? theme.colors.text : nil,
                inlineTextIcon: item.textIconName.flatMap { NSImage(named: $0) },
                detectBold: emphasizesText
            )
        }))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    return entries
}

private struct WalletInfoModalLayout {
    static let width: CGFloat = 360
    private static let buttonSideInset: CGFloat = 20
    private static let buttonHeight: CGFloat = 40
    private static let buttonBottomInset: CGFloat = 20
    private static let termsVerticalInset: CGFloat = 15

    let terms: TextViewLayout?
    let interactionsHeight: CGFloat

    init(terms text: String?, openURL: @escaping (String) -> Void) {
        let terms = text.map { Self.makeTermsLayout($0, openURL: openURL) }
        let belowButton = terms.map { $0.layoutSize.height + Self.termsVerticalInset * 2 } ?? Self.buttonBottomInset
        self.terms = terms
        self.interactionsHeight = Self.buttonHeight + belowButton
    }

    private static func makeTermsLayout(_ text: String, openURL: @escaping (String) -> Void) -> TextViewLayout {
        let attributed = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes(
            body: MarkdownAttributeSet(font: .normal(.short), textColor: theme.colors.grayText),
            link: MarkdownAttributeSet(font: .normal(.short), textColor: walletClassicAccent),
            linkAttribute: { contents in
                return (NSAttributedString.Key.link.rawValue, contents)
            }
        ))
        let layout = TextViewLayout(attributed, alignment: .center)
        layout.measure(width: width - buttonSideInset * 2)
        layout.interactions.processURL = { link in
            if let url = link as? String {
                openURL(url)
            }
        }
        return layout
    }
}

@available(macOS 10.15, *)
public func WalletInfoController(context: any AccountContextProtocol, environment: WalletUIEnvironment, walletContext: WalletContext, mode: WalletInfoMode, completion: (() -> Void)? = nil) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let fiat = walletContext.stateValue.fiat
    let fiatRateText: String?
    if let rate = fiat.selectedRate, rate.unitsPerGram.isFinite, rate.unitsPerGram > 0.0 {
        fiatRateText = formatFiatValue(rate.unitsPerGram, currencySymbol: fiat.selectedCurrency.symbol)
    } else {
        fiatRateText = nil
    }
    let content = walletInfoContent(mode: mode, fiatRateText: fiatRateText, gaslessDailyTransfers: WalletConfiguration.with(appConfiguration: context.appConfiguration).transferGaslessDailyLimit)

    let arguments = Arguments(context: context, environment: environment)

    let statePromise = ValuePromise(content, ignoreRepeated: true)

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { content in
        return InputDataSignalValue(entries: entries(content, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: "", hasDone: false, getBackgroundColor: {
        theme.colors.background
    })
    controller.analyticsScreen = mode == .recovery ? AnalyticsScreen.walletRecoveryPhraseWarning : AnalyticsScreen.walletInfo

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    var close: (() -> Void)? = nil
    var isCompleting = false

    let complete: () -> Void = {
        guard !isCompleting else {
            return
        }
        isCompleting = true
        close?()
        completion?()
    }

    controller.validateData = { _ in
        complete()
        return .none
    }

    let modalLayout = WalletInfoModalLayout(terms: content.terms, openURL: environment.openExternalURL)

    let modalInteractions = ModalInteractions(acceptTitle: content.buttonTitle, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, height: modalLayout.interactionsHeight, singleButton: true, bottomText: modalLayout.terms, customTheme: { walletModalTheme })

    let modalController = WalletModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(WalletInfoModalLayout.width, 0))

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    close = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}
