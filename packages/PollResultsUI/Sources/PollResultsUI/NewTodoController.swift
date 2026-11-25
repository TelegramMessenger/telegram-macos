
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import InputView
import ChatHistoryModel
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import InAppSettings
import FoundationUtils
import Strings
import AppAnalytics



private class Arguments {
    public let context: any AccountContextProtocol
    public let deleteOption:(InputDataIdentifier) -> Void
    public let updateState:(Updated_ChatTextInputState)->Void
    public let updateOptionState:(InputDataIdentifier, Updated_ChatTextInputState)->Void
    public let toggleCanAdd:()->Void
    public let toggleCanComplete:()->Void
    public init(context: any AccountContextProtocol, deleteOption: @escaping (InputDataIdentifier) -> Void, updateState: @escaping (Updated_ChatTextInputState) -> Void, updateOptionState:@escaping(InputDataIdentifier, Updated_ChatTextInputState)->Void, toggleCanAdd:@escaping()->Void, toggleCanComplete:@escaping()->Void) {
        self.context = context
        self.deleteOption = deleteOption
        self.updateState = updateState
        self.updateOptionState = updateOptionState
        self.toggleCanAdd = toggleCanAdd
        self.toggleCanComplete = toggleCanComplete
    }
}



private struct TodoOption : Equatable {
    public let identifier: InputDataIdentifier
    public let textState: Updated_ChatTextInputState
    public let selected: Bool
    public let enabled: Bool
    public let taskId: Int32?
    public init(identifier: InputDataIdentifier, textState: Updated_ChatTextInputState, selected: Bool, enabled: Bool, taskId: Int32?) {
        self.identifier = identifier
        self.textState = textState
        self.selected = selected
        self.enabled = enabled
        self.taskId = taskId
    }
    
    public var text: String {
        return textState.inputText.string
    }
    
    public func withUpdatedText(_ textState: Updated_ChatTextInputState) -> TodoOption {
        return TodoOption(identifier: self.identifier, textState: textState, selected: self.selected, enabled: self.enabled, taskId: self.taskId)
    }
    public func withUpdatedSelected(_ selected: Bool) -> TodoOption {
        return TodoOption(identifier: self.identifier, textState: self.textState, selected: selected, enabled: self.enabled, taskId: self.taskId)
    }
}

private struct State : Equatable {
    public var options: [TodoOption]
    public var textState: Updated_ChatTextInputState

    public var othersCanAdd: Bool = false
    public var othersCanComplete: Bool = false
    
    public var source: NewTodoSourceType
    
    public var maxTextLength:Int32 = 32
    public var maxOptionLength: Int32 = 64

    
    
    public func withUpdatedTitle(_ title: String) -> State {
        return State(options: self.options, textState: self.textState, source: self.source)
    }
    public func withDeleteOption(_ identifier: InputDataIdentifier) -> State {
        var options = self.options
        options.removeAll(where: {$0.identifier == identifier})
        return State(options: options, textState: self.textState, source: self.source)
    }
    
    public func withUnselectItems() -> State {
        return State(options: self.options.map { $0.withUpdatedSelected(false) }, textState: self.textState, source: self.source)
    }
    
    public func withUpdatedOption(_ f:(TodoOption) -> TodoOption, forKey identifier: InputDataIdentifier) -> State {
        var options = self.options
        if let index = options.firstIndex(where: {$0.identifier == identifier}) {
            options[index] = f(options[index])
        }
        return State(options: options, textState: self.textState, source: self.source)
    }
    
    public func withAddedOption(_ option: TodoOption) -> State {
        var options = self.options
        options.append(option)
        return State(options: options, textState: self.textState, source: self.source)
    }
    public func withUpdatedPos(_ previous: Int, _ current: Int) -> State {
        var options = self.options
        options.move(at: previous, to: current)
        return State(options: options, textState: self.textState, source: self.source)
    }
    
    public func indexOf(_ identifier: InputDataIdentifier) -> Int? {
        return options.firstIndex(where: { $0.identifier == identifier })
    }
    
    public func withUpdatedState() -> State {
         return State(options: self.options, textState: self.textState, source: self.source)
    }
    
    public var title: String {
        return textState.inputText.string
    }
    
    public var isEnabled: Bool {
        
        var fails: [InputDataIdentifier : InputDataValidationFailAction] = [:]
        if self.textState.string.trimmed.isEmpty || textState.string.trimmed.length > maxTextLength {
            fails[_id_input_title] = .shake
        }
        for value in self.options {
            if value.text.trimmed.isEmpty || value.text.trimmed.length > maxOptionLength {
                fails[value.identifier] = .shake
            }
        }
        
        switch source {
        case .addOption:
            if self.options.filter(\.enabled).isEmpty {
                return false
            }
        default:
            break
        }
        
        return fails.isEmpty
    }
    
    public var media: TelegramMediaTodo {
        
        var items: [TelegramMediaTodo.Item] = []
        
        for (i, item) in options.enumerated() {
            items.append(.init(text: item.text, entities: item.textState.textInputState().messageTextEntities(), id: item.taskId ?? Int32(i + 1)))
        }
        
        var flags: TelegramMediaTodo.Flags = .init()
        if othersCanAdd, othersCanComplete {
            flags.insert(.othersCanAppend)
        }
        if othersCanComplete {
            flags.insert(.othersCanComplete)
        }
        return .init(flags: flags, text: self.title, textEntities: self.textState.textInputState().messageTextEntities(), items: items, completions: [])
    }
    
    public var added: [TelegramMediaTodo.Item] {
        var items: [TelegramMediaTodo.Item] = []
        for (i, item) in options.enumerated() {
            if item.enabled {
                items.append(.init(text: item.text, entities: item.textState.textInputState().messageTextEntities(), id: Int32(i + 1)))
            }
        }
        return items
    }
}


private func _id_input_option() -> InputDataIdentifier {
    return InputDataIdentifier("_id_input_option_\(arc4random())")
}
private let _id_input_title = InputDataIdentifier("_id_input_title")
private let _id_input_add_option = InputDataIdentifier("_id_input_add_option")
private let _id_other_can_complete = InputDataIdentifier("_id_other_can_complete")
private let _id_other_can_add = InputDataIdentifier("_id_other_can_add")



private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    let maxTextLength:Int32 = arguments.context.appConfiguration.getGeneralValue("todo_title_length_max", orElse: 32)
    let maxOptionLength: Int32 =  arguments.context.appConfiguration.getGeneralValue("todo_item_length_max", orElse: 64)

        
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_input_title, equatable: .init(state.textState), comparable: nil, item: { initialSize, stableId in
        return InputTextDataRowItem(initialSize, stableId: stableId, context: arguments.context, state: state.textState, viewType: .singleItem, placeholder: nil, inputPlaceholder: strings().newTodoInputTitlePlaceholder, filter: { text in
            var text = text
            while text.contains("\n\n\n") {
                text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            }
            
            if !text.isEmpty {
                while text.range(of: "\n")?.lowerBound == text.startIndex {
                    text = String(text[text.index(after: text.startIndex)...])
                }
            }
            return text
        }, updateState: arguments.updateState, limit: maxTextLength, hasEmoji: arguments.context.isPremium, enabled: state.source.editingEnabled)
    }))
    index += 1
    
    let optionsLimit = Int(arguments.context.appConfiguration.getGeneralValue("todo_items_max", orElse: 30))
    
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().newTodoSectionChecklist), data: InputDataGeneralTextData(detectBold: false, viewType: .textTopItem)))
    index += 1
    
    let sorted = state.options
    
    
    
    for (i, option) in sorted.enumerated() {
        
        var viewType: GeneralViewType = bestGeneralViewType(sorted, for: i)
        if i == sorted.count - 1, state.options.count < optionsLimit {
            if i == 0 {
                viewType = .firstItem
            } else {
                viewType = .innerItem
            }
        }
        let placeholder: InputDataInputPlaceholder = InputDataInputPlaceholder(hasLimitationText: true)
        let rightItem: InputDataRightItem? = InputDataRightItem.action(theme.icons.recentDismiss, .custom({ _, _ in
            arguments.deleteOption(option.identifier)
        }))
        
        struct Tuple : Equatable {
            let option: TodoOption
            let placeholder: InputDataInputPlaceholder?
            let viewType: GeneralViewType
            let rightItem: InputDataRightItem?
        }
        let tuple = Tuple(option: option, placeholder: placeholder, viewType: viewType, rightItem: rightItem)
        
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: option.identifier, equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
            return InputTextDataRowItem(initialSize, stableId: stableId, context: arguments.context, state: tuple.option.textState, viewType: tuple.viewType, placeholder: tuple.placeholder, inputPlaceholder: strings().newTodoInputTaskPlaceholder, rightItem: tuple.rightItem, filter: { text in
                return text.trimmingCharacters(in: CharacterSet.newlines)
            }, updateState: { state in
                arguments.updateOptionState(option.identifier, state)
            }, limit: maxOptionLength, hasEmoji: arguments.context.isPremium, enabled: tuple.option.enabled)
        }))
    }
    if state.options.count < optionsLimit {
        entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .string(nil), error: nil, identifier: _id_input_add_option, data: InputDataGeneralData(name: strings().newTodoOptionAdd, color: theme.colors.accent, icon: theme.icons.pollAddOption, type: .none, viewType: state.options.isEmpty ? .singleItem : .lastItem, action: nil)))
        index += 1
    }
    
    switch state.source {
    case .create, .edit:
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_other_can_complete, data: .init(name: strings().newTodoToggleOthersCanComplete, color: theme.colors.text, type: .switchable(state.othersCanComplete), viewType: state.othersCanComplete ? .firstItem : .singleItem, action: arguments.toggleCanComplete)))

        if state.othersCanComplete {
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_other_can_add, data: .init(name: strings().newTodoToggleOthersCanAppend, color: theme.colors.text, type: .switchable(state.othersCanAdd), viewType: .lastItem, action: arguments.toggleCanAdd)))
        }
    default:
        break
    }
    
  
    // entries
    
    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1
    
    return entries
}

public enum NewTodoSourceType : Equatable {
    case create
    case edit(Message, taskId: Int32?)
    case addOption(Message)
    
    public var editingEnabled: Bool {
        switch self {
        case .addOption:
            return false
        default:
            return true
        }
    }
    
    public var okText: String {
        switch self {
        case .create:
            return strings().newTodoActionSend
        case .edit:
            return strings().newTodoActionEdit
        case .addOption:
            return strings().newTodoActionAdd
        }
    }
    
    public var title: String {
        switch self {
        case .create:
            return strings().newTodoTitleCreate
        case .edit:
            return strings().newTodoTitleEdit
        case .addOption:
            return strings().newTodoTitleAddTask
        }
    }

}

public func NewTodoController(chatInteraction: any NewPollChatInteraction, source: NewTodoSourceType = .create) -> InputDataModalController {
    
    let context = chatInteraction.pollContext

    let actionsDisposable = DisposableSet()
    
    let initialTitle: Updated_ChatTextInputState
    var initialOptions: [TodoOption] = []
    let othersCanAdd: Bool
    let othersCanComplete: Bool
    
    switch source {
    case let .edit(message, _), let .addOption(message):
        let media = message.media.first as! TelegramMediaTodo
        initialTitle = ChatTextInputState(inputText: media.text, selectionRange: media.text.length..<media.text.length, attributes: chatTextAttributes(from: TextEntitiesMessageAttribute(entities: media.textEntities), associatedMedia: [:])).textInputState()
        for option in media.items {
            let text = ChatTextInputState(inputText: option.text, selectionRange: option.text.length..<option.text.length, attributes: chatTextAttributes(from: TextEntitiesMessageAttribute(entities: option.entities), associatedMedia: [:])).textInputState()
            initialOptions.append(.init(identifier: _id_input_option(), textState: text, selected: false, enabled: source.editingEnabled, taskId: option.id))
        }
        othersCanAdd = media.flags.contains(.othersCanAppend)
        othersCanComplete = media.flags.contains(.othersCanComplete)
        
        if !source.editingEnabled {
            var disable: Bool = false
            switch source {
            case let .edit(_, taskId):
                disable = taskId != nil
            default:
                break
            }
            if !disable {
                initialOptions.append(.init(identifier: _id_input_option(), textState: .init(), selected: true, enabled: true, taskId: nil))
            }
        }
    case .create:
        initialTitle = .init()
        initialOptions = [TodoOption(identifier: _id_input_option(), textState: .init(), selected: true, enabled: true, taskId: nil)]
        othersCanAdd = true
        othersCanComplete = true
    }
    
    let maxTextLength:Int32 = context.appConfiguration.getGeneralValue("todo_title_length_max", orElse: 32)
    let maxOptionLength: Int32 =  context.appConfiguration.getGeneralValue("todo_item_length_max", orElse: 64)

    let initialState = State(options: initialOptions, textState: initialTitle, othersCanAdd: othersCanAdd, othersCanComplete: othersCanComplete, source: source, maxTextLength: maxTextLength, maxOptionLength: maxOptionLength)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let optionsLimit = Int(context.appConfiguration.getGeneralValue("todo_items_max", orElse: 30))

    var shouldMakeNextResponderAfterTransition: (InputDataIdentifier, Bool, InputDataIdentifier?, Bool)? = nil
    var shouldMakeNearResponderAfterTransition: (InputDataIdentifier, Int)? = nil

    let _: Atomic<Bool> = Atomic(value: false)

    
    var getController:(()->ViewController?)? = nil
    var close:(()->Void)? = nil
    
    var window:Window {
        get {
            return bestWindow(context, getController?())
        }
    }

    //        if let (identifier, checkEmptyCurrent, focusIdentifier, scrollIfNeeded) = shouldMakeNextResponderAfterTransition {

    switch source {
    case let .edit(_, taskId):
        if let taskId {
            let option = initialState.options.first(where: { $0.taskId == taskId })
            if let option {
                shouldMakeNextResponderAfterTransition = (option.identifier, false, option.identifier, true)
            }
        }
    default:
        break
    }
    
    
    let arguments = Arguments(context: context, deleteOption: { identifier in
        let state = stateValue.with { $0 }
        updateState { state in
            return state.withDeleteOption(identifier)
        }
        shouldMakeNearResponderAfterTransition = (identifier, state.indexOf(identifier)!)
    }, updateState: { state in
        updateState { current in
            var current = current
            current.textState = state
            return current
        }
    }, updateOptionState: { identifier, state in
        updateState { current in
            var current = current
            if let index = current.options.firstIndex(where: { $0.identifier == identifier }) {
                current.options[index] = current.options[index].withUpdatedText(state)
            }
            return current
        }
    }, toggleCanAdd: {
        updateState { current in
            var current = current
            current.othersCanAdd = !current.othersCanAdd
            return current
        }
    }, toggleCanComplete: {
        updateState { current in
            var current = current
            current.othersCanComplete = !current.othersCanComplete
            return current
        }
    })
    
    
    let addOption:(Bool)-> InputDataValidation = { byClick in
        let option = TodoOption(identifier: _id_input_option(), textState: .init(), selected: false, enabled: true, taskId: nil)
        updateState { state in
            if state.options.count < optionsLimit {
                return state.withAddedOption(option)
            } else {
                return state
            }
        }
        shouldMakeNextResponderAfterTransition = (option.identifier, false, byClick ? _id_input_add_option : nil, true)
        
        return .none
    }
    
    let checkAndSend:()->Void = {
        let state = stateValue.with { $0 }
    
        if state.isEnabled {
            switch source {
            case let .edit(message, _):
                context.account.pendingUpdateMessageManager.add(messageId: message.id, text: "", media: .update(.message(message: MessageReference(message), media: state.media)), entities: nil, richText: nil, inlineStickers: [:])
                close?()
            case let .addOption(message):
                _ = context.engine.messages.appendTodoMessageItems(messageId: message.id, items: state.added).start()
                close?()
            case .create:
                chatInteraction.sendPollMedias([state.media], ChatTextInputState(), false, nil, false, nil, false, nil, false)
                close?()
            }
        }
    }
    
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let interactions = ModalInteractions(acceptTitle: source.okText, accept: {
        checkAndSend()
    }, singleButton: true)
    
    var firstRun = true

    
    let previousPasteboard = window.pastehandler
   
    
    let controller = InputDataController(dataSignal: signal, title: source.title, validateData: { data -> InputDataValidation in
        
        
        if let _ = data[_id_input_add_option] {
            return addOption(true)
        }
        
        let state = stateValue.with { $0 }
        
        var fails: [InputDataIdentifier : InputDataValidationFailAction] = [:]
        if state.textState.string.trimmed.isEmpty {
            fails[_id_input_title] = .shake
        }
        for value in state.options {
            if value.text.trimmed.isEmpty {
                fails[value.identifier] = .shake
            }
        }
        if !fails.isEmpty {
            
            let state = stateValue.with { $0 }
            
            if fails.contains(where: {$0.key == _id_input_title}) {
                shouldMakeNextResponderAfterTransition = (_id_input_title, true, nil, true)
            } else {
                for option in state.options {
                    if fails.contains(where: {$0.key == option.identifier}) {
                        shouldMakeNextResponderAfterTransition = (option.identifier, true, nil, true)
                        break
                    }
                }
            }
        }
        
        return .fail(.doSomething { f in
            
            f(.fail(.fields(fails)))
            
            var addedOptions: Int? = nil
            updateState { state in
                var state = state
                if fails.isEmpty {
                    if state.options.count < 2 {
                        state = state.withAddedOption(TodoOption(identifier: _id_input_option(), textState: .init(), selected: false, enabled: true, taskId: nil))
                        if addedOptions == nil {
                            addedOptions = state.options.count - 1
                        }
                    }
                }
                return state.withUpdatedState()
            }
            
            if let addedOptions = addedOptions {
                let state = stateValue.with { $0 }
                shouldMakeNextResponderAfterTransition = (state.options[addedOptions].identifier, false, nil, true)
            }
        })
        
    }, updateDatas: { data in
        return .none
    }, afterDisappear: {
        window.pastehandler = previousPasteboard
    }, updateDoneValue: { data in
        return { f in
            f(.disabled(strings().navigationDone))
        }
    }, removeAfterDisappear: true, hasDone: true, identifier: "new-todo", afterTransaction: { controller in
        
        if let (identifier, checkEmptyCurrent, focusIdentifier, scrollIfNeeded) = shouldMakeNextResponderAfterTransition {
            var markResponder: Bool = true
            let state = stateValue.with { $0 }
            if let current = controller.currentFirstResponderIdentifier, checkEmptyCurrent {
                if current == _id_input_title, state.title.trimmed.isEmpty  {
                    markResponder = false
                }
                if let option = state.options.first(where: {$0.identifier == current}), option.text.trimmed.isEmpty {
                    markResponder = false
                }
            }
            if markResponder {
                DispatchQueue.main.async {
                    controller.makeFirstResponderIfPossible(for: identifier, focusIdentifier: focusIdentifier, scrollIfNeeded: scrollIfNeeded)
                }
            }
            shouldMakeNextResponderAfterTransition = nil
        }
        
        if let (_, index) = shouldMakeNearResponderAfterTransition {
            
            let state = stateValue.with { $0 }
            if !state.options.isEmpty {
                if controller.currentFirstResponderIdentifier == nil {
                    if index == 0 {
                        if !state.options.isEmpty {
                            controller.makeFirstResponderIfPossible(for: state.options[0].identifier)
                        }
                    } else {
                        controller.makeFirstResponderIfPossible(for: state.options[index - 1].identifier)
                    }
                }
            } else {
                controller.makeFirstResponderIfPossible(for: _id_input_title)
            }
            shouldMakeNearResponderAfterTransition = nil
        }
        
        var range: NSRange = NSMakeRange(NSNotFound, 0)
        let state = stateValue.with { $0 }
        
        controller.tableView.enumerateItems(with: { item -> Bool in
            if let identifier = (item.stableId.base as? InputDataEntryId)?.identifier {
                if let _ = state.indexOf(identifier) {
                    if range.location == NSNotFound {
                        range.location = item.index
                    }
                    range.length += 1
                }
            }
            
            return true
        })

        interactions.updateDone { done in
            done.isEnabled = state.isEnabled
        }
        
        if firstRun, case .addOption = source {
            delay(0.1, closure: {
                controller.makeFirstResponderIfPossible(for: state.options.last!.identifier)
            })
            firstRun = false
        }
        
    }, returnKeyInvocation: { identifier, event in
        
        if FastSettings.checkSendingAbility(for: event) {
            checkAndSend()
            return .default
        } else {
            let state = stateValue.with { $0 }
            
            
            if identifier == _id_input_title {
                if state.options.isEmpty {
                    _ = addOption(false)
                    return .nothing
                }
                return .invokeEvent
            }
            
            if let identifier = identifier {
                
                let index: Int? = state.indexOf(identifier)
                let isLast = index == state.options.count - 1
                
                if isLast {
                    if state.options.count == optionsLimit {
                        return .nothing
                    } else {
                        _ = addOption(false)
                        return .nothing
                    }
                } else {
                    return .nextResponder
                }
            }
        }
        

        return .nothing
    }, deleteKeyInvocation: { identifier in
        
        let state = stateValue.with { $0 }
        if let index = state.options.firstIndex(where: { $0.identifier == identifier}) {
            if state.options[index].text.isEmpty {
                arguments.deleteOption(state.options[index].identifier)
                return .invoked
            }
        }
        
        return .default
    })
    switch source {
    case .addOption:
        controller.analyticsScreen = .chatChecklistAddTask
    case .create, .edit:
        controller.analyticsScreen = .chatChecklistCreate
    }
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    
    controller.didAppear = { controller in
        window.pastehandler = { [weak controller] in
            guard let controller, let id = controller.currentFirstResponderIdentifier else {
                return false
            }
            
            let options = stateValue.with { $0.options }
            
            let limit = optionsLimit - options.count + 1
            
            if id.identifier.hasPrefix("_id_input_option_") {
                let text = NSPasteboard.general.string(forType: .string) ?? ""
                let texts = text.components(separatedBy: CharacterSet.newlines).prefix(limit).map {
                    String($0.trimmed.fullTrimmed.prefix(Int(maxOptionLength)))
                }.filter { !$0.isEmpty }
                
                let option = options.first(where: { $0.identifier == id })
                
                if let option, let last = options.last, last == option {
                    if option.textState.string.isEmpty {
                        updateState { current in
                            var current = current
                            current.options[current.options.count - 1] = .init(identifier: last.identifier, textState: .init(inputText: .initialize(string: texts[0])), selected: false, enabled: true, taskId: nil)
                            for i in 1 ..< texts.count {
                                current.options.append(.init(identifier: _id_input_option(), textState: .init(inputText: .initialize(string: texts[i])), selected: false, enabled: true, taskId: nil))
                            }
                            //current = current
                            return current
                        }
                        return true
                    }
                }
                
            }
            return false

        }
    }

    
    let modalController = InputDataModalController(controller, modalInteractions: interactions)
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.modal?.close()
    }
    
    return modalController
    
}



