import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import GeneralRows
import InputDataUI
import Localization
import StarsUI
import TelegramContext
import TelegramTheme
import TelegramUtils
import AppAnalytics

private final class HeaderItem : GeneralRowItem {
    
    struct ActionInfo {
        let title: TextViewLayout
        let info: TextViewLayout
        
    }
    
    fileprivate let state: State
    fileprivate let arguments: Arguments
    fileprivate let maxValue: Int64
    
    fileprivate let infoLayout: TextViewLayout
    
    fileprivate let actions: [ActionInfo]
    
    init(_ initialSize: NSSize, stableId: AnyHashable, state: State, arguments: Arguments) {
        self.state = state
        self.arguments = arguments
        self.maxValue = 10000
        self.infoLayout = .init(
            .initialize(
                string: strings().storyLiveStreamStarMessageHighlightInfo(state.storyPeer?._asPeer().displayTitle ?? ""),
                color: arguments.presentation.colors.text,
                font: .normal(.text)
            ).detectBold(with: .medium(.text)),
            alignment: .center
        )

        let colors = arguments.presentation.colors
        let config = getEffectiveStarConfig(for: Int64(state.amount.realValue))

        self.actions = [
            .init(
                title: .init(.initialize(string: "\(config.period / 60)m", color: colors.text, font: .avatar(.header))),
                info: .init(.initialize(string: strings().storyLiveStreamStarMessagePinInChat, color: colors.text, font: .normal(.text)))
            ),
            .init(
                title: .init(.initialize(string: "\(config.length)", color: colors.text, font: .avatar(.header))),
                info: .init(.initialize(string: strings().storyLiveStreamStarMessageCharacters, color: colors.text, font: .normal(.text)))
            ),
            .init(
                title: .init(.initialize(string: "\(config.emojis)", color: colors.text, font: .avatar(.header))),
                info: .init(.initialize(string: strings().storyLiveStreamStarMessageEmoji, color: colors.text, font: .normal(.text)))
            )
        ]


        for action in actions {
            action.title.measure(width: .greatestFiniteMagnitude)
            action.info.measure(width: .greatestFiniteMagnitude)
        }
        
        super.init(initialSize, stableId: stableId)
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        infoLayout.measure(width: width - 40)
        
        return true
    }
    
    override func viewClass() -> AnyClass {
        return HeaderView.self
    }

    override var accessibilityLabel: String? {
        return "\(state.amount.realValue) " + strings().voiceOverCommonStars
    }
    
    override var height: CGFloat {
        return 110 + 15 + infoLayout.layoutSize.height + 15 + 60
    }
}

private final class HeaderView: GeneralRowView {
    let badgeView = Star_BadgeView(frame: NSMakeRect(0, 0, 100, 48))
    let sliderView = Star_SliderView(frame: NSMakeRect(0, 0, 100, 30))
    let infoView = TextView()
    
    
    let actionsView: ActionInfoView
    
    class ActionInfoView : View {
        
        class ActionView : View {
            
            let titleView = TextView()
            let infoView = TextView()
            
            required init(frame frameRect: NSRect) {
                super.init(frame: frameRect)
                addSubview(titleView)
                addSubview(infoView)
                
                titleView.isSelectable = false
                titleView.userInteractionEnabled = false
                
                infoView.isSelectable = false
                infoView.userInteractionEnabled = false
                
            }
            
            required init?(coder: NSCoder) {
                fatalError("init(coder:) has not been implemented")
            }
            
            func update(_ item: HeaderItem.ActionInfo) {
                titleView.update(item.title)
                infoView.update(item.info)
            }
            
            
            override func layout() {
                super.layout()
                titleView.centerX(y: 8)
                infoView.centerX(y: frame.height - infoView.frame.height - 8)
            }
            
        }
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func update(items: [HeaderItem.ActionInfo], item tableItem: HeaderItem) {
            while subviews.count > items.count {
                subviews.last?.removeFromSuperview()
            }
            while subviews.count < items.count {
                addSubview(ActionView(frame: NSMakeRect(0, 0, 100, frame.height)))
            }
            
            let itemWidth: CGFloat = (frame.width - CGFloat(items.count + 1) * 10) / CGFloat(items.count)
            
            var x: CGFloat = 10
            
            for (i, item) in items.enumerated() {
                let view = self.subviews[i] as! ActionView
                view.update(item)
                view.backgroundColor = tableItem.arguments.presentation.colors.listBackground
                view.layer?.cornerRadius = 10
                view.frame = CGRect(origin: CGPoint(x: x, y: 0), size: NSMakeSize(itemWidth, 50))
                x += view.frame.width + 10
            }
            
            needsLayout = true
        }
        
        override func layout() {
            super.layout()
        }
    }
    

    
    required init(frame frameRect: NSRect) {
        actionsView = ActionInfoView(frame: NSMakeRect(0, 0, frameRect.width, 50))
        super.init(frame: frameRect)
        
        addSubview(badgeView)
        addSubview(sliderView)
        
        addSubview(actionsView)
        
        addSubview(infoView)
        
        infoView.userInteractionEnabled = false
        infoView.isSelectable = false
        
        sliderView.updateProgress = { [weak self] progress, maybeToBalance in
            if let item = self?.item as? HeaderItem {
                
                var value = progress * CGFloat(item.maxValue)
                let myBalance = CGFloat(item.state.myBalance)
                if maybeToBalance, item.state.amount.realValue < item.state.myBalance, value > myBalance {
                    value = Double(item.state.amount.withRealValue(Int(myBalance + 1)).sliderValue)
                }
                item.arguments.updateValue(Int64(ceil(value)))
            }
        }

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? HeaderItem else {
            return
        }
        
        let color = getStarAmountColorMapping(value: Int64(item.state.amount.realValue))
        
        sliderView.updateColors([color, color], effect: .white)
        badgeView.updateColors([color, color], effect: .white)

        actionsView.update(items: item.actions, item: item)
        
        let transition: ContainedViewLayoutTransition = .immediate
        
        
        let size = badgeView.update(sliderValue: Int64(item.state.amount.sliderValue), realValue: Int64(item.state.amount.realValue), max: item.maxValue, context: item.arguments.context)
        
        sliderView.dotLayer.backgroundColor = item.arguments.presentation.colors.background
        sliderView.emptyLayer.backgroundColor = item.arguments.presentation.colors.listBackground.cgColor

        
        transition.updateFrame(view: self.badgeView, frame: self.focus(size))
        badgeView.updateLayout(size: size, transition: transition)

        sliderView.update(count: Int64(item.state.amount.sliderValue), minValue: 1, maxValue: item.maxValue)

        infoView.update(item.infoLayout)
        
        
    }
    
    override var backdorColor: NSColor {
        guard let item = item as? HeaderItem else {
            return theme.colors.background
        }
        return item.arguments.presentation.colors.background
    }
    
    override func layout() {
        super.layout()
        sliderView.frame = NSMakeRect(20, badgeView.frame.height + 20, frame.width - 40, 30)
        sliderView.layout()
        
        badgeView.centerX(y: 50)
        
        badgeView.setFrameOrigin(NSMakePoint(10 + sliderView.dotLayer.frame.midX - badgeView.frame.width * badgeView.tailPosition, 10))
        
        actionsView.centerX(y: sliderView.frame.maxY + 15)
        
        infoView.centerX(y: actionsView.frame.maxY + 25)
        
    }
}


private final class Arguments {
    let context: any AccountContextProtocol
    let presentation: TelegramPresentationTheme
    let updateValue:(Int64)->Void
    init(context: any AccountContextProtocol, presentation: TelegramPresentationTheme, updateValue:@escaping(Int64)->Void) {
        self.context = context
        self.presentation = presentation
        self.updateValue = updateValue
    }
}


private struct State : Equatable {
    
    var amount: Star_SliderAmount = Star_SliderAmount(realValue: 10, maxRealValue: 10000, maxSliderValue: 10000, isLogarithmic: true)
    var storyPeer: EnginePeer?

    var myPeer: EnginePeer
    var myBalance: Int64 = 1000
    var countUpdated: Bool = false
    var showMeInTop: Bool = true
    
    
    var text: String
    var entities: [MessageTextEntity]
}


private let _id_header = InputDataIdentifier("_id_header")
private let _id_message = InputDataIdentifier("_id_message")
private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    let index: Int32 = 0
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("h1"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 10, stableId: stableId, backgroundColor: arguments.presentation.colors.background)
    }))
    sectionId += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, state: state, arguments: arguments)
    }))
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_message, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return StoryMessageItemRow(initialSize, stableId: stableId, message: .init(id: .init(space: .local, id: 0), stableId: 0, isIncoming: false, author: state.myPeer, isFromAdmin: false, text: state.text, entities: state.entities, date: 0, lifetime: 10, paidStars: Int64(state.amount.realValue)), reactions: nil, arguments: .init(context: arguments.context, contextMenuItems: { _, _,_  in return [] }, focusMessage: { _ in }), preview: true)
    }))
  
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: .init("h2"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return GeneralRowItem(initialSize, height: 15, stableId: stableId, backgroundColor: arguments.presentation.colors.background)
    }))
    sectionId += 1
    
    return entries
}

func StoryStreamStarMessageController(context: any AccountContextProtocol, story: StoryContentItem, currentValue: Int64?, minValue: Int64?, text: String, entities: [MessageTextEntity], presentation: TelegramPresentationTheme, callback: @escaping(Int64)->Void) -> InputDataModalController {
    
    
    var close:(()->Void)? = nil

    let actionsDisposable = DisposableSet()

    let initialState = State(amount: Star_SliderAmount(realValue: Int(currentValue ?? 10), maxRealValue: 10000, maxSliderValue: 10000, isLogarithmic: true, minValue: Int(minValue ?? 0) + 1), storyPeer: story.peer, myPeer: .init(context.myPeer!), text: text, entities: entities)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    var getController:(()->ViewController?)? = nil
    
    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }
    
    let starsContext = context.starsContext
    
    starsContext.load(force: true)
    
    actionsDisposable.add(starsContext.state.startStrict(next: { starsState in
        updateState { current in
            var current = current
            current.myBalance = starsState?.balance.value ?? 0
            return current
        }
    }))

    let arguments = Arguments(context: context, presentation: presentation, updateValue: { value in
        updateState { current in
            var current = current
            current.amount = current.amount.withSliderValue(Int(value))
            current.countUpdated = true
            return current
        }
        let current = stateValue.with { $0.amount.realValue }
        let myBalance = stateValue.with { $0.myBalance }
        if current == myBalance {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
        }
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(
        dataSignal: signal,
        title: strings().storyLiveStreamStarMessageHighlightAndPin
    )
    controller.analyticsScreen = .storiesLiveStarMessage

    controller.validateData = { _ in
        
        let state = stateValue.with { $0 }
        
        let value = stateValue.with { Int64($0.amount.realValue) }
        
        if value > state.myBalance {
            showStarsTopup(context: context, source: .purchase(state.myPeer, value), for: context.window)
        } else {
            callback(value)
        }
        
        close?()
        return .none
    }
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: "Add", accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true, customTheme: {
        .init(text: presentation.colors.text, background: presentation.colors.background, grayForeground: presentation.colors.background, activeBackground: presentation.colors.background, listBackground: presentation.colors.background)
    })
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(380, 300), presentation: presentation)
    
    controller.leftModalHeader = ModalHeaderData(image: presentation.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    controller.getBackgroundColor = {
        presentation.colors.background
    }
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    controller.afterTransaction = { [weak modalInteractions, weak modalController] controller in
        let realValue: Int = stateValue.with { $0.amount.realValue }
        modalInteractions?.updateDone { button in
            button.set(text: strings().storyLiveStreamStarMessageAdd(strings().starListItemCountOther(realValue)), for: .Normal)
        }
        modalController?.updateLocalizationAndTheme(theme: presentation)
    }
    
    return modalController
    
}



