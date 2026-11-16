import Foundation
import Cocoa
import TelegramCore
import Postbox
import TGUIKit
import SwiftSignalKit
import Localization
import TelegramTheme
import TelegramIconsTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import ChatModeTypes
import AppAnalytics

private final class Arguments {
    let context: any AccountContextProtocol
    let dismiss: ()->Void
    init(context: any AccountContextProtocol, dismiss: @escaping()->Void) {
        self.context = context
        self.dismiss = dismiss
    }
}

private struct State : Equatable {

}

private enum Mode {
    case fragment
    case searchAd
}


private final class RowItem : GeneralRowItem {
    
    let context: any AccountContextProtocol
    let headerLayout: TextViewLayout
    let infoLayout: TextViewLayout
    let infoHeaderLayout: TextViewLayout
    
    let options: [OptionsListView.Option]
    let dismiss:()->Void
    let parent: Message?
    let interactions: (any ChatInteractionProtocol)?
    let mode: Mode
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, parent: Message?, interactions: (any ChatInteractionProtocol)?, mode: Mode, dismiss:@escaping()->Void) {
        self.context = context
        self.dismiss = dismiss
        self.interactions = interactions
        self.parent = parent
        self.mode = mode
        
        let headerText = NSAttributedString.initialize(string: strings().fragmentAdsInfoTitle, color: theme.colors.text, font: .medium(.title)).mutableCopy() as! NSMutableAttributedString
        
        headerText.append(string: "\n")
        headerText.append(string: strings().fragmentAdsInfoText, color: theme.colors.grayText, font: .normal(.text))
        
        let infoHeaderAttr = NSAttributedString.initialize(string: strings().fragmentAdsInfoBlockTitle, color: theme.colors.text, font: .medium(.title)).mutableCopy() as! NSMutableAttributedString
        
        
        let infoText = strings().fragmentAdsInfoBlockText
        
        let infoAttr = parseMarkdownIntoAttributedString(infoText, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(.text), textColor: theme.colors.text), bold: MarkdownAttributeSet(font: .normal(.text), textColor: theme.colors.text), link: MarkdownAttributeSet(font: .medium(.title), textColor: theme.colors.link), linkAttribute: { contents in
            return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.externalLink(contents, false))
        })).mutableCopy() as! NSMutableAttributedString
                                                                                            
                                                                                    
        self.headerLayout = .init(headerText, alignment: .center)
        self.headerLayout.measure(width: initialSize.width - 40)
        
        self.infoHeaderLayout = .init(infoHeaderAttr, alignment: .center)
        self.infoHeaderLayout.measure(width: initialSize.width - 80)

        self.infoLayout = .init(infoAttr, alignment: .center)
        self.infoLayout.measure(width: initialSize.width - 80)
        
        self.infoLayout.interactions = LinkHooks.shared.globalLinkExecutor()
        
        var options:[OptionsListView.Option] = []
        
        options.append(.init(image: MonetizationHooks.shared.iconFragmentLock().precomposed(theme.colors.accent), header: .init(.initialize(string: strings().fragmentAdsInfoOption1Title, color: theme.colors.text, font: .medium(.text))), text: .init(.initialize(string: strings().fragmentAdsInfoOption1Info, color: theme.colors.grayText, font: .normal(.text))), width: initialSize.width - 40))
        
        if mode == .fragment {
            options.append(.init(image: MonetizationHooks.shared.iconFragmentSplitRevenue().precomposed(theme.colors.accent), header: .init(.initialize(string: strings().fragmentAdsInfoOption2Title, color: theme.colors.text, font: .medium(.text))), text: .init(.initialize(string: strings().fragmentAdsInfoOption2Info("%"), color: theme.colors.grayText, font: .normal(.text))), width: initialSize.width - 40))
        }

        let removeText = mode == .fragment ? strings().fragmentAdsInfoOption3Info : strings().searchAdAboutRemove
        options.append(.init(image: TelegramThemeHooks.shared.image(.iconFragmentNoAds).precomposed(theme.colors.accent), header: .init(.initialize(string:  strings().fragmentAdsInfoOption3Title, color: theme.colors.text, font: .medium(.text))), text: .init(.initialize(string: removeText, color: theme.colors.grayText, font: .normal(.text))), width: initialSize.width - 40))

        
        self.options = options

        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }
    
    override var height: CGFloat {
        var height: CGFloat = 80
        height += 20
        height += headerLayout.layoutSize.height
        height += 20
        height += OptionsListView.height(options: options, spacing: 20) + 20
        //block
        height += 20
        height += infoHeaderLayout.layoutSize.height
        height += 10
        height += infoLayout.layoutSize.height
        height += 10
        
        return height
    }
    override func viewClass() -> AnyClass {
        return RowView.self
    }

    override var accessibilityLabel: String? {
        return strings().fragmentAdsInfoTitle
    }
}

private final class RowView: GeneralContainableRowView {
    
    
    private let moreActions: ImageButton = ImageButton()
    
    private let iconView = View(frame: NSMakeRect(0, 0, 80, 80))
    private let gradient = SimpleGradientLayer()
    private let stickerView = ImageView()
    private let headerView = TextView()
    
    private let infoBlock = View()
    private let infoHeaderView = InteractiveTextView(frame: .zero)
    private let infoView = InteractiveTextView(frame: .zero)
    
    
    private let optionsView = OptionsListView(frame: .zero)
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(headerView)
        addSubview(iconView)
        gradient.frame = iconView.bounds
        iconView.layer?.addSublayer(gradient)
        infoBlock.addSubview(infoHeaderView)
        infoBlock.addSubview(infoView)
        addSubview(infoBlock)
        iconView.addSubview(stickerView)
        stickerView.isAccessibilityDecorative = true
        
       
        
        addSubview(optionsView)
        
        headerView.isSelectable = false
        iconView.layer?.cornerRadius = iconView.frame.height / 2
        
        infoView.textView.userInteractionEnabled = true
        infoView.userInteractionEnabled = false
        
        moreActions.autohighlight = false
        moreActions.scaleOnClick = true
        moreActions.set(image: TelegramThemeHooks.shared.image(.iconChatActionsActive).precomposed(theme.colors.grayIcon), for: .Normal)
        moreActions.sizeToFit()
        moreActions.setAccessibilityLabel(strings().voiceOverCommonMore)
        
        addSubview(moreActions)
        
        moreActions.set(handler: { [weak self] control  in
            
            if let item = self?.item as? RowItem, let parent = item.parent, let interactions = item.interactions {
                let signal = MonetizationHooks.shared.adMenuItems(parent, interactions) |> deliverOnMainQueue
                if let event = NSApp.currentEvent {
                    _ = signal.startStandalone(next: { items in
                        let menu = ContextMenu()
                        menu.items = items
                        AppMenu.show(menu: menu, event: event, for: control)
                    })
                }
            }
            
        }, for: .Click)

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        iconView.centerX(y: 0)
        stickerView.center()
        
        moreActions.setFrameOrigin(NSMakePoint(containerView.frame.width - moreActions.frame.width, 0))
        
        
        headerView.centerX(y: stickerView.frame.maxY + 20)
        
        optionsView.centerX(y: headerView.frame.maxY + 20)

        infoBlock.centerX(y: optionsView.frame.maxY + 20)
        
        infoHeaderView.centerX(y: 10)
        infoView.centerX(y: infoHeaderView.frame.maxY + 10)
        
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? RowItem else {
            return
        }
        infoHeaderView.set(text: item.infoHeaderLayout, context: item.context)
        infoView.set(text: item.infoLayout, context: item.context)
        
        headerView.update(item.headerLayout)
        moreActions.isHidden = item.mode != .fragment
        iconView.backgroundColor = theme.colors.accent
        
        self.gradient.colors = [theme.colors.accent].map { $0.cgColor }
        self.gradient.startPoint = CGPoint(x: 0.5, y: 0)
        self.gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
        self.gradient.type = .radial

        stickerView.image = TelegramThemeHooks.shared.image(.iconFragmentAdsLogo).precomposed(.white)
        stickerView.sizeToFit()
        
        infoBlock.setFrameSize(NSMakeSize(frame.width - 40, 10 + infoHeaderView.frame.height + 10 + infoView.frame.height + 10))
        
        infoBlock.backgroundColor = theme.colors.listBackground
        infoBlock.layer?.cornerRadius = 10
        
     
        
        
        optionsView.spacing = 20
        optionsView.update(options: item.options)
        
        
        needsLayout = true
    }
}


private let _id_header = InputDataIdentifier("_id_header")

private func entries(_ state: State, message: Message?, interactions: (any ChatInteractionProtocol)?, mode: Mode, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
  
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return RowItem(initialSize, stableId: stableId, context: arguments.context, parent: message, interactions: interactions, mode: mode, dismiss: arguments.dismiss)
    }))
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    return entries
}
public func FragmentAdsInfoController(context: any AccountContextProtocol, message: Message?, interactions: (any ChatInteractionProtocol)?) -> InputDataModalController {
    return adsInfoController(context: context, message: message, interactions: interactions, mode: .fragment)
}

public func SearchAdAboutController(context: any AccountContextProtocol) -> InputDataModalController {
    return adsInfoController(context: context, message: nil, interactions: nil, mode: .searchAd)
}

private func adsInfoController(context: any AccountContextProtocol, message: Message?, interactions: (any ChatInteractionProtocol)?, mode: Mode) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State()
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var close:(()->Void)? = nil

    let arguments = Arguments(context: context, dismiss: {
        close?()
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, message: message, interactions: interactions, mode: mode, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    switch mode {
    case .fragment:
        controller.analyticsScreen = AnalyticsScreen.chatSponsoredInfo
    case .searchAd:
        controller.analyticsScreen = AnalyticsScreen.searchAdInfo
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().fragmentAdsInfoOK, accept: { 
        close?()
    }, singleButton: true, customTheme: {
        .init(background: theme.colors.background, grayForeground: theme.colors.background, activeBackground: theme.colors.background, listBackground: theme.colors.background)
    })
    
    
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(370, 0))
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.close()
    }
    
    controller.getBackgroundColor = {
        theme.colors.background
    }
    
    return modalController
}
