
import Cocoa
import TGUIKit
import SwiftSignalKit
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import AlertsUI
import LocalAnimations
import DateUtils
import TelegramIconsTheme
import TelegramCore
import Postbox
import AppAnalytics

private final class HeaderItem: GeneralRowItem {
    fileprivate let title: TextViewLayout
    fileprivate let context: any AccountContextProtocol
    fileprivate let dismiss: ()->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, dismiss: @escaping()->Void) {
        self.context = context
        self.dismiss = dismiss
        self.title = .init(.initialize(string: strings().freezeAccountTitle, color: theme.colors.text, font: .medium(.title)))
        super.init(initialSize, stableId: stableId)
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        self.title.measure(width: width - 40)
        
        return true
    }
    
    public override var height: CGFloat {
        return 165
    }
    
    public override func viewClass() -> AnyClass {
        return HeaderItemView.self
    }

    public override var accessibilityLabel: String? {
        return title.attributedString.string
    }
}

private final class HeaderItemView : TableRowView {
    private let textView = TextView()
    private let dismiss = ImageButton()
    private let media: PasskeysStickerView = PasskeysHooks.shared.makeStickerView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        addSubview(media)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        
        addSubview(dismiss)
        
        dismiss.scaleOnClick = true
        dismiss.autohighlight = false
        
        dismiss.set(image: theme.icons.glass_close, for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)

    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        textView.update(item.title)
        
        media.updateSticker(animation: LocalAnimatedSticker.freeze_duck, size: media.frame.size, context: item.context, table: item.table, animated: animated)
        
        
        dismiss.setSingle(handler: { [weak item] _ in
            item?.dismiss()
        }, for: .Click)
    }
    
    public override func layout() {
        super.layout()
        dismiss.setFrameOrigin(NSMakePoint(10, 10))

        media.centerX(y: 20)
        textView.centerX(y: media.frame.maxY + 15)
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.listBackground
    }
}


private final class OptionsItem : GeneralRowItem {
    
    public let context: any AccountContextProtocol
    
    public let options: [OptionsListView.Option]
    
    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, appeal: @escaping()->Void) {
        self.context = context
        
        var options:[OptionsListView.Option] = []
        
        _ = context.appConfiguration.getStringValue("freeze_appeal_url", orElse: "https://t.me/spambot")
        let freezeTime = context.appConfiguration.getGeneralValue("freeze_since_date", orElse: 0)

        
        options.append(.init(image: NSImage(named: "Icon_FreezeAccount_Option1")!.precomposed(theme.colors.accent), header: .init(.initialize(string: strings().freezeAccountOption1Title, color: theme.colors.text, font: .medium(.text))), text: .init(.initialize(string: strings().freezeAccountOption1Text, color: theme.colors.grayText, font: .normal(.text))), width: initialSize.width - 40, interactiveText: true))
        
        options.append(.init(image: NSImage(named: "Icon_FreezeAccount_Option2")!.precomposed(theme.colors.accent), header: .init(.initialize(string: strings().freezeAccountOption2Title, color: theme.colors.text, font: .medium(.text))), text: .init(.initialize(string: strings().freezeAccountOption2Text, color: theme.colors.grayText, font: .normal(.text))), width: initialSize.width - 40, interactiveText: true))

        
        let option3Text = parseMarkdownIntoAttributedString(strings().freezeAccountOption3Text(stringForFullDate(timestamp: freezeTime)), attributes: .init(body: .init(font: .normal(.text), textColor: theme.colors.grayText), bold: .init(font: .medium(.text), textColor: theme.colors.grayText), link: .init(font: .normal(.text), textColor: theme.colors.accent), linkAttribute: { link in
            return (NSAttributedString.Key.link.rawValue, PasskeysHooks.shared.callbackLink(link, { value in
                appeal()
            }))
        }))
        
        let option3Layout = TextViewLayout(option3Text)
        option3Layout.interactions = LinkHooks.shared.globalLinkExecutor()
        
        options.append(.init(image: NSImage(named: "Icon_FreezeAccount_Option3")!.precomposed(theme.colors.accent), header: .init(.initialize(string: strings().freezeAccountOption3Title, color: theme.colors.text, font: .medium(.text))), text: option3Layout, width: initialSize.width - 40, interactiveText: true))
        
        self.options = options

        super.init(initialSize, stableId: stableId, viewType: .singleItem)
    }
    
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        for option in options {
            option.makeSize(width: width - 40)
        }
        
        return true
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 0
        height += 15
        height += OptionsListView.height(options: options, spacing: 15) + 15
        return height
    }
    public override func viewClass() -> AnyClass {
        return OptionsItemView.self
    }

    public override var accessibilityLabel: String? {
        return options.map { $0.header.attributedString.string }.joined(separator: ", ")
    }
}


private final class OptionsItemView: GeneralRowView {
    
        
    
    private let optionsView = OptionsListView(frame: .zero)
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        addSubview(optionsView)
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        
        optionsView.centerX(y: 15)
        
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? OptionsItem else {
            return
        }
        

        optionsView.spacing = 15
        optionsView.update(options: item.options)
        
        
        needsLayout = true
    }
}


private final class Arguments {
    public let context: any AccountContextProtocol
    public let dismiss:()->Void
    public let appeal:()->Void
    public init(context: any AccountContextProtocol, dismiss:@escaping()->Void, appeal:@escaping()->Void) {
        self.dismiss = dismiss
        self.context = context
        self.appeal = appeal
    }
}

private struct State : Equatable {

}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index: Int32 = 0
//    
//    entries.append(.sectionId(sectionId, type: .normal))
//    sectionId += 1
  
    // entries
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("header"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, context: arguments.context, dismiss: arguments.dismiss)
    }))
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("options"), equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return OptionsItem(initialSize, stableId: stableId, context: arguments.context, appeal: arguments.appeal)
    }))
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public func FrozenAccountController(context: any AccountContextProtocol) -> InputDataModalController {

    let actionsDisposable = DisposableSet()

    let initialState = State()
    
    var close:(()->Void)? = nil
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }
    
    let appealLink = context.appConfiguration.getStringValue("freeze_appeal_url", orElse: "https://t.me/spambot")

    
    let appeal:()->Void = {
        PasskeysHooks.shared.openAppealLink(context, appealLink)
        close?()
    }

    let arguments = Arguments(context: context, dismiss: {
        close?()
    }, appeal: appeal)
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .appFrozenAccount
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().freezeAccountOK, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    
    controller.validateData = { _ in
        appeal()
        return .none
    }
    
    close = { [weak modalController] in
        modalController?.close()
    }

    
    return modalController
    
}


/*
 
 */



