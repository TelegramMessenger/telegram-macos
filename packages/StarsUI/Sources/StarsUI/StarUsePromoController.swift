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
import AppAnalytics

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public let dismiss: ()->Void
    public init(context: (any AccountContextProtocol), dismiss: @escaping()->Void) {
        self.context = context
        self.dismiss = dismiss
    }
}

private struct State : Equatable {

}


private final class RowItem : GeneralRowItem {
    
    public let context: (any AccountContextProtocol)
    public let headerLayout: TextViewLayout
    
    public let options: [OptionsListView.Option]
    public let dismiss:()->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), dismiss:@escaping()->Void) {
        self.context = context
        self.dismiss = dismiss
        
        let headerText = NSAttributedString.initialize(string: strings().starsPromoHeader, color: theme.colors.text, font: .medium(.title)).mutableCopy() as! NSMutableAttributedString
        
        headerText.append(string: "\n\n")
        headerText.append(string: strings().starsPromoHeaderInfo, color: theme.colors.grayText, font: .normal(.text))
        
                                                                                    
        self.headerLayout = .init(headerText, alignment: .center)
        self.headerLayout.measure(width: initialSize.width - 40)
        
        var options:[OptionsListView.Option] = []
        
        options.append(.init(image: TelegramThemeHooks.shared.image(.iconStarInfoGift).precomposed(theme.colors.text), header: .init(.initialize(string: strings().starsPromoOption1Title, color: theme.colors.text, font: .medium(.text))), text: .init(.initialize(string: strings().starsPromoOption1Info, color: theme.colors.grayText, font: .normal(.text))), width: initialSize.width - 40))
        
        
        let option2Info = parseMarkdownIntoAttributedString(strings().starsPromoOption2Info, attributes: .init(body: .init(font: .medium(.text), textColor: theme.colors.grayText), link: .init(font: .normal(.text), textColor: theme.colors.link), linkAttribute: { contents in
            return (NSAttributedString.Key.link.rawValue, contents)
        }))
        
        let option2InfoLayout = TextViewLayout(option2Info)
        
        option2InfoLayout.interactions.processURL = { _ in
            showModal(with: Star_AppExamples(context: context), for: context.window)
        }
        
        options.append(.init(image: TelegramThemeHooks.shared.image(.iconStarInfoBot).precomposed(theme.colors.text), header: .init(.initialize(string: strings().starsPromoOption2Title, color: theme.colors.text, font: .medium(.text))), text: option2InfoLayout, width: initialSize.width - 40))

        
        options.append(.init(image: TelegramThemeHooks.shared.image(.iconStarInfoLock).precomposed(theme.colors.text), header: .init(.initialize(string:  strings().starsPromoOption3Title, color: theme.colors.text, font: .medium(.text))), text: .init(.initialize(string: strings().starsPromoOption3Info, color: theme.colors.grayText, font: .normal(.text))), width: initialSize.width - 40))

        options.append(.init(image: TelegramThemeHooks.shared.image(.iconStarInfoCash).precomposed(theme.colors.text), header: .init(.initialize(string:  strings().starsPromoOption4Title, color: theme.colors.text, font: .medium(.text))), text: .init(.initialize(string: strings().starsPromoOption4Info, color: theme.colors.grayText, font: .normal(.text))), width: initialSize.width - 40))

        
        self.options = options

        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 150
        height += headerLayout.layoutSize.height
        height += 20
        height += OptionsListView.height(options: options, spacing: 20) + 20
        
        return height
    }
    
    override var accessibilityLabel: String? {
        return strings().starsPromoHeader
    }
    
    public override func viewClass() -> AnyClass {
        return RowView.self
    }
}

private final class RowView: GeneralContainableRowView {
    
    
    private let starScene: GoldenStarSceneView
    private let headerView = TextView()
        
    
    private let optionsView = OptionsListView(frame: .zero)
    public required init(frame frameRect: NSRect) {
        starScene = GoldenStarSceneView(frame: NSMakeRect(0, 0, frameRect.width, 150))
        super.init(frame: frameRect)
        addSubview(starScene)
        addSubview(headerView)

       
        addSubview(optionsView)
        headerView.isSelectable = false

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        starScene.centerX(y: 0)
        
        
        headerView.centerX(y: starScene.frame.maxY)
        
        optionsView.centerX(y: headerView.frame.maxY + 20)
                
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? RowItem else {
            return
        }
        
        headerView.update(item.headerLayout)
        self.starScene.sceneBackground = theme.colors.background
     
    
        
        optionsView.spacing = 20
        optionsView.update(options: item.options)
        
        
        needsLayout = true
    }
}


private let _id_header = InputDataIdentifier("_id_header")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
  
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return RowItem(initialSize, stableId: stableId, context: arguments.context, dismiss: arguments.dismiss)
    }))
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    return entries
}
public func StarUsePromoController(context: (any AccountContextProtocol)) -> InputDataModalController {

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
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .starsAbout
    
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
