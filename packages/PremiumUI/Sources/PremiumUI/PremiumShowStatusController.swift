import Cocoa
import Foundation
import TGUIKit
import TelegramMedia
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
import LocalAnimations
import CurrencyFormat
import SceneEffects
import InAppPurchaseManager
import InlineStickers
import ObjcUtils

private final class HeaderItem : GeneralRowItem {
    fileprivate let source: PremiumShowStatusSource
    fileprivate let arguments: Arguments
    fileprivate let info1: TextViewLayout
    fileprivate let premiumHeader: TextViewLayout
    fileprivate let premiumInfo: TextViewLayout
    public init(_ initialSize: NSSize, stableId: AnyHashable, source: PremiumShowStatusSource, peer: EnginePeer, arguments: Arguments) {
        self.arguments = arguments
        self.source = source
        
        self.info1 = .init(.initialize(string: source.info(peer), color: theme.colors.text, font: .normal(.text)).detectBold(with: .medium(.text)), alignment: .center)
        self.premiumHeader = .init(.initialize(string: source.titlePremium, color: theme.colors.text, font: .medium(.header)).detectBold(with: .medium(.header)), alignment: .center)
        self.premiumInfo = .init(.initialize(string: source.infoPremium(peer), color: theme.colors.text, font: .normal(.text)).detectBold(with: .medium(.text)), alignment: .center)

        super.init(initialSize, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        info1.measure(width: width - 40)
        premiumHeader.measure(width: width - 40)
        premiumInfo.measure(width: width - 40)

        return true
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 70
        height += 10 // inset from lottie to text
        height += info1.layoutSize.height // status height
        height += 10  // inset from info to button
        height += 40 // button height
        
        height += 40 // separator "or" height
        
        height += premiumHeader.layoutSize.height
        height += 10 // header to info
        height += premiumInfo.layoutSize.height
        height += 10  // inset from info to button
        height += 40 // button height

        return height
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderItemView.self
    }
}
private final class HeaderItemView : GeneralRowView {
    
    private let animation = View(frame: NSMakeRect(0, 0, 70, 70))
    private let sticker = PremiumHooks.shared.makeStickerView(NSMakeRect(0, 0, 70, 70))
    private let info = TextView()
    private let button = TextButton()
    private let premiumHeader = TextView()
    private let premiumInfo = TextView()
    private let premiumButton = TextButton()
    private let separator = SeparatorView(frame: .zero, text: strings().premiumShowStatusOr)
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(animation)
        animation.addSubview(sticker)
        
        button.scaleOnClick = true
        premiumButton.scaleOnClick = true
        
        info.userInteractionEnabled = false
        info.isSelectable = false
        
        premiumHeader.userInteractionEnabled = false
        premiumHeader.isSelectable = false
        
        premiumInfo.userInteractionEnabled = false
        premiumInfo.isSelectable = false
        
        addSubview(info)
        addSubview(button)
        addSubview(separator)
        addSubview(premiumHeader)
        addSubview(premiumInfo)
        addSubview(premiumButton)
        animation.layer?.cornerRadius = animation.frame.height * 0.5
        
        button.layer?.cornerRadius = 20
        premiumButton.layer?.cornerRadius = 20
        
        button.set(handler: { [weak self] _ in
            if let arguments = (self?.item as? HeaderItem)?.arguments {
                arguments.updatePrivacy()
            }
        }, for: .Click)
        
        
        premiumButton.set(handler: { [weak self] _ in
            if let arguments = (self?.item as? HeaderItem)?.arguments {
                arguments.premium()
            }
        }, for: .Click)
        
        let shimmer = ShimmerEffectView()
        shimmer.isStatic = true
        self.premiumButton.addSubview(shimmer)
        
    }
    
    public override func layout() {
        super.layout()
        animation.centerX(y: 0)
        sticker.center()
        info.centerX(y: animation.frame.maxY + 10)
        button.frame = NSMakeRect(20, info.frame.maxY + 10, frame.width - 40, 40)
        separator.frame = NSMakeRect(0, button.frame.maxY, frame.width, 40)
        premiumHeader.centerX(y: separator.frame.maxY)
        premiumInfo.centerX(y: premiumHeader.frame.maxY + 10)
        premiumButton.frame = NSMakeRect(20, premiumInfo.frame.maxY + 10, frame.width - 40, 40)
        
        for subview in premiumButton.subviews {
            if let shimmer = subview as? ShimmerEffectView {
                subview.frame = premiumButton.bounds
                shimmer.updateAbsoluteRect(premiumButton.bounds, within: premiumButton.frame.size)
                shimmer.update(backgroundColor: .clear, foregroundColor: .clear, shimmeringColor: NSColor.white.withAlphaComponent(0.3), shapes: [.roundedRect(rect: premiumButton.bounds, cornerRadius: premiumButton.frame.height / 2)], horizontal: true, size: premiumButton.frame.size)

            }
        }
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.listBackground
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        
        animation.backgroundColor = theme.colors.accent
        
        info.update(item.info1)
        premiumHeader.update(item.premiumHeader)
        premiumInfo.update(item.premiumInfo)
        
        button.set(font: .medium(.text), for: .Normal)
        button.set(color: theme.colors.underSelectedColor, for: .Normal)
        button.set(background: theme.colors.accent, for: .Normal)
        button.set(text: item.source.action, for: .Normal)
        
        premiumButton.set(font: .medium(.text), for: .Normal)
        
        premiumButton.set(background: premiumGradient[0], for: .Normal)
        premiumButton.set(color: theme.colors.underSelectedColor, for: .Normal)
        premiumButton.set(text: item.source.premiumAction, for: .Normal)
        
        (sticker as? PremiumStickerView)?.updatePremiumSticker(file: item.source.lottie.file, size: NSMakeSize(70, 70), context: item.arguments.context, tint: theme.colors.underSelectedColor, animated: animated)
        
        needsLayout = true
    }
}

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let updatePrivacy:()->Void
    public let premium:()->Void
    public init(context: (any AccountContextProtocol), updatePrivacy:@escaping()->Void, premium:@escaping()->Void) {
        self.context = context
        self.updatePrivacy = updatePrivacy
        self.premium = premium
    }
}

private struct State : Equatable {
    public var source: PremiumShowStatusSource
    public var peer: EnginePeer
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
  
    // entries
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, source: state.source, peer: state.peer, arguments: arguments)
    }))
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public enum PremiumShowStatusSource: Equatable {
    case status
    case read
    
    public var title: String {
        switch self {
        case .status:
            return strings().premiumShowStatusShowYourLastSeen
        case .read:
            return strings().premiumShowStatusShowYourReadDate
        }
    }
    public var titlePremium: String {
        switch self {
        case .status:
            return strings().premiumShowStatusUpgradeToPremium
        case .read:
            return strings().premiumShowStatusUpgradeToPremium
        }
    }
    public func info(_ peer: EnginePeer) -> String {
        switch self {
        case .status:
            return strings().premiumShowStatusShowYourLastSeenInfo(peer._asPeer().compactDisplayTitle)
        case .read:
            return strings().premiumShowStatusShowYourReadDateInfo(peer._asPeer().compactDisplayTitle)
        }
    }
    public func infoPremium(_ peer: EnginePeer) -> String {
        switch self {
        case .status:
            return strings().premiumShowStatusUpgradeToPremiumLastSeenInfo(peer._asPeer().compactDisplayTitle)
        case .read:
            return strings().premiumShowStatusUpgradeToPremiumReadInfo(peer._asPeer().compactDisplayTitle)
        }
    }
    
    public var lottie: LocalAnimatedSticker {
        switch self {
        case .status:
            return LocalAnimatedSticker.show_status_profile
        case .read:
            return LocalAnimatedSticker.show_status_read
        }
    }
    
    public var action: String {
        switch self {
        case .status:
            return strings().premiumShowStatusShowMyStatus
        case .read:
            return strings().premiumShowStatusShowMyReadTime
        }
    }
    public var premiumAction: String {
        return strings().premiumShowStatusSubscribe
    }
}

public func PremiumShowStatusController(context: (any AccountContextProtocol), peer: EnginePeer, source: PremiumShowStatusSource) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State(source: source, peer: peer)
    
    var close:(()->Void)? = nil
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }

    let arguments = Arguments(context: context, updatePrivacy: {
        let privacySignal: Signal<AccountPrivacySettings, NoError>
        privacySignal = context.engine.privacy.requestAccountPrivacySettings() |> deliverOnMainQueue
        
        let _ = privacySignal.startStandalone(next: { info in
            let text: String
            switch source {
            case .status:
                text = strings().premiumShowStatusSuccessLastSeen
                _ = context.engine.privacy.updateSelectiveAccountPrivacySettings(type: .presence, settings: .enableEveryone(disableFor: [:])).start()
            case .read:
                text = strings().premiumShowStatusSuccessReadTime
                var settings = info.globalSettings
                settings.hideReadTime = false
                _ = context.engine.privacy.updateGlobalPrivacySettings(settings: settings).start()

            }
            showModalText(for: context.window, text: text)
        })
        close?()
    }, premium: {
        prem(with: PremiumBoardingController(context: context, source: .last_seen, openFeatures: true), for: context.window)
        close?()
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: source.title)
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalController = InputDataModalController(controller, modalInteractions: nil)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.close()
    }
    
    return modalController
    
}
