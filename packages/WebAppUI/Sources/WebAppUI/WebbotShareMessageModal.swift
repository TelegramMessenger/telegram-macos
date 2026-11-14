
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AppAnalytics



private final class Arguments {
    let context: any AccountContextProtocol
    weak var modalController: InputDataModalController?

    init(context: any AccountContextProtocol) {
        self.context = context
    }
}

private struct State : Equatable {
    var message: EngineMessage
    var peer: EnginePeer
}

private final class HeaderItem : GeneralRowItem {
    private let arguments: Arguments
    fileprivate let message: Message
    fileprivate lazy var messageItem = BrowserHooks.shared.makeSharePreviewMessageItem(initialSize, arguments.context, message) { [weak self] in
        guard let self, self.table?.item(stableId: self.stableId) === self else { return }
        self.noteHeightOfRow()
        self.arguments.modalController?.updateSize(false)
    }

    init(_ initialSize: NSSize, stableId: AnyHashable, arguments: Arguments, message: Message) {
        self.arguments = arguments
        self.message = message
        super.init(initialSize, stableId: stableId, viewType: .singleItem)
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        _ = messageItem.makeSize(max(1, width - inset.left - inset.right))
        
        return true
    }
    
    override var height: CGFloat {
        return  messageItem.height + 20
    }
    
    override func viewClass() -> AnyClass {
        return HeaderRowView.self
    }

    override var accessibilityLabel: String? {
        return messageItem.accessibilityLabel ?? message.text
    }
}


private final class HeaderRowView: GeneralContainableRowView {
    private let backgroundView = BackgroundView(frame: .zero)
    private let tableView: TableView
    required init(frame frameRect: NSRect) {
        tableView = TableView(frame: frameRect.size.bounds, isFlipped: false)
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(tableView)
        tableView.getBackgroundColor = {
            return .clear
        }
        
        
    }
    
     required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        
        self.layout()
        
        backgroundView.backgroundMode = theme.backgroundMode
        
        guard let item = item as? HeaderItem else {
            return
        }
        if tableView.count == 3, tableView.item(at: 1) === item.messageItem {
            return
        }
        tableView.removeAll()
        _ = tableView.addItem(item: GeneralRowItem(containerView.frame.size, height: 10, stableId: arc4random64(), backgroundColor: .clear))
        _ = tableView.addItem(item: item.messageItem)
        _ = tableView.addItem(item: GeneralRowItem(containerView.frame.size, height: 10, stableId: arc4random64(), backgroundColor: .clear))
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        if hit != nil, (item as? HeaderItem)?.message.media.first is TelegramMediaWidget {
            return self
        }
        return hit
    }

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        transition.updateFrame(view: backgroundView, frame: containerView.bounds)
        transition.updateFrame(view: tableView, frame: containerView.bounds)
    }
}

private let _id_custom = InputDataIdentifier("_id_custom")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().webappShareMessagePreview), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_custom, equatable: nil, comparable: nil, item: { initialSize, stableId in
        return HeaderItem(initialSize, stableId: stableId, arguments: arguments, message: state.message._asMessage())
    }))
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().webappShareMessageBotInfo(state.peer._asPeer().displayTitle)), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))

    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    
    return entries
}

public enum WebbotShareMessageStatus {
    case success
    case failed
}

public func WebbotShareMessageModal(context: any AccountContextProtocol, bot: EnginePeer, preparedMessage: PreparedInlineMessage, window: Window, callback: @escaping(WebbotShareMessageStatus)->Void) -> InputDataModalController {
    return WebbotShareMessageModal(context: context, bot: bot, preparedMessage: preparedMessage, window: window, analyticsContext: nil, callback: callback)
}

public func WebbotShareMessageModal(context: any AccountContextProtocol, bot: EnginePeer, preparedMessage: PreparedInlineMessage, window: Window, analyticsContext: AnalyticsContext?, callback: @escaping(WebbotShareMessageStatus)->Void) -> InputDataModalController {
    return WebbotShareMessageModal(context: context, bot: bot, preparedMessage: preparedMessage, window: window, analyticsContext: analyticsContext, analyticsJourney: nil, callback: callback)
}

public func WebbotShareMessageModal(context: any AccountContextProtocol, bot: EnginePeer, preparedMessage: PreparedInlineMessage, window: Window, analyticsContext: AnalyticsContext?, analyticsJourney: AnalyticsPreparedShareJourney?, callback: @escaping(WebbotShareMessageStatus)->Void) -> InputDataModalController {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext()).restricting(peerId: bot.id).restricting(peerId: preparedMessage.botId)
    let presentation = origin.beginPresentation()
    defer { presentation.end() }

    let actionsDisposable = DisposableSet()
    
    
    var text: String = ""
    var entities: TextEntitiesMessageAttribute?
    var media: [Media] = []
    
    switch preparedMessage.result.message {
    case let .auto(textValue, entitiesValue, _):
        text = textValue
        entities = entitiesValue
        switch preparedMessage.result {
        case let .internalReference(reference):
            if let file = reference.file {
                media = [file]
            } else if let image = reference.image {
                media = [image]
            }
        case let .externalReference(reference):
            if let content = reference.content {
                media = [content]
            }
        }
    case let .text(textValue, entitiesValue, _, _, _, _):
        text = textValue
        entities = entitiesValue
    case let .contact(contact, _):
        media = [contact]
    case let .mapLocation(map, _):
        media = [map]
    case let .invoice(invoice, _):
        media = [invoice]
    case let .widget(widget, caption, captionEntities, _):
        text = caption
        entities = captionEntities
        media = [widget]
    default:
        break
    }

    var attributes: [MessageAttribute] = []
    
    attributes.append(InlineBotMessageAttribute.init(peerId: bot.id, title: bot._asPeer().displayTitle))
    if let entities {
        attributes.append(entities)
    }
    
    
    let firstMessage = Message(stableId: 0, stableVersion: 0, id: MessageId(peerId: bot.id, namespace: 0, id: 1), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: context.timestamp, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: bot._asPeer(), text: text, attributes: attributes, media: media, peers:SimpleDictionary([bot.id : bot._asPeer()]) , associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])



    let initialState = State(message: .init(firstMessage), peer: bot)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let _: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let arguments = Arguments(context: context)
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    let controller = InputDataController(dataSignal: origin.preservingPresentation(signal), title: strings().webappShareMessageShare)
    controller.analyticsScreen = .botMiniAppShareMessage
    
    
    controller.analyticsContext = origin
    let action = PreparedSharePreviewAction()
    weak var childPicker: ModalViewController?
    var closePreview: (() -> Void)?
    let complete: (WebbotShareMessageStatus) -> Void = { status in
        let delivery = origin.beginPresentation()
        defer { delivery.end() }
        callback(status)
    }

    controller.onDeinit = {
        analyticsJourney?.discard()
        actionsDisposable.dispose()
        if action.cancel() { complete(.failed) }
        childPicker?.close()
    }

    controller.validateData = { [weak window] _ in
        guard let window else {
            analyticsJourney?.discard()
            if action.cancel() { complete(.failed) }
            closePreview?()
            return .none
        }
        guard let attempt = action.begin() else { return .none }
        analyticsJourney?.pickerOpened()
        let picker = BrowserHooks.shared.makeShareChatContextResultModalObservedResult(context, preparedMessage, analyticsContext: origin, completion: { value in
            guard action.finish(attempt) else { return }
            switch value {
            case .accepted: analyticsJourney?.pickerFinished(result: .accepted)
            case .partiallyAccepted: analyticsJourney?.pickerFinished(result: .partiallyAccepted)
            case .rejected: analyticsJourney?.pickerFinished(result: .rejected)
            case .unknown: analyticsJourney?.pickerFinished(result: .unknown)
            case .cancelled: analyticsJourney?.pickerFinished(result: .cancelled)
            case .notAccepted: analyticsJourney?.pickerFinished(result: .notAccepted)
            }
            if case .accepted = value { complete(.success) } else { complete(.failed) }
            closePreview?()
        })
        guard action.isCurrent(attempt) else { return .none }
        childPicker = picker
        showModal(with: picker, for: window)
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: "Share With...", accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, closeHandler: { close in
        guard action.beginClose() else { return }
        if action.cancel() {
            analyticsJourney?.cancelPreview()
            complete(.failed)
        }
        childPicker?.close()
        close()
    })
    arguments.modalController = modalController
    modalController.analyticsContext = origin
    closePreview = { [weak modalController] in modalController?.close() }
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    return modalController
}


/*
 
 */



