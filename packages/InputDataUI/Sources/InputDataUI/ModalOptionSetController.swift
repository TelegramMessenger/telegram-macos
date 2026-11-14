import Cocoa
import SwiftSignalKit
import TGUIKit
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import AppAnalytics

private final class ModalOptionsArguments {
    public let context: any AccountContextProtocol
    public let presentation: TelegramPresentationTheme
    public let toggleOption: (Int)->Void
    public init(context: any AccountContextProtocol, presentation: TelegramPresentationTheme, toggleOption:@escaping(Int)->Void) {
        self.context = context
        self.presentation = presentation
        self.toggleOption = toggleOption
    }
}

public struct ModalOptionSet : Equatable {
    public let title: String
    public let selected: Bool
    public let editable: Bool
    public init(title: String, selected: Bool, editable: Bool) {
        self.title = title
        self.selected = selected
        self.editable = editable
    }
    public func withUpdatedSelected(_ selected: Bool) -> ModalOptionSet {
        return ModalOptionSet(title: self.title, selected: selected, editable: self.editable)
    }
}
public enum ModalOptionSetResult {
    case selected
    case none
}

private struct ModalOptionsState: Equatable {
    public let options: [ModalOptionSet]
    public let selectOne: Bool
    public init(options:[ModalOptionSet], selectOne: Bool) {
        self.options = options
        self.selectOne = selectOne
    }
    
    public func withToggledOptionAt(_ index: Int) -> ModalOptionsState {
        var options = self.options
        options[index] = options[index].withUpdatedSelected(!options[index].selected)
        if selectOne {
            for i in 0 ..< options.count {
                options[i] = options[i].withUpdatedSelected(false)
            }
            options[index] = options[index].withUpdatedSelected(true)
        }
        
        return ModalOptionsState(options: options, selectOne: self.selectOne)
    }
}

private let _id_title: InputDataIdentifier = InputDataIdentifier("_id_title")
private let _id_border: InputDataIdentifier = InputDataIdentifier("_id_border")
private func _id_option(_ index: Int)->InputDataIdentifier {
    return InputDataIdentifier("_id_option_\(index)")
}
private func modalOptionsSetEntries(state: ModalOptionsState, desc: String?, header: String?, arguments: ModalOptionsArguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    
    if let header {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(header), data: .init(color: arguments.presentation.colors.listGrayText, viewType: .textTopItem)))
        index += 1
    }
    
    if let desc = desc {
        entries.append(InputDataEntry.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_title, equatable: InputDataEquatable(desc), comparable: nil, item: { initialSize, stableId in
            return GeneralBlockTextRowItem.init(initialSize, stableId: stableId, viewType: .singleItem, text: desc, font: .normal(.text), customTheme: .initialize(arguments.presentation))
        }))
        index += 1
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

    } 
    

    
    
    for (i, option) in state.options.enumerated() {
        entries.append(InputDataEntry.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_option(i), equatable: InputDataEquatable(option), comparable: nil, item: { initialSize, stableId in
            return GeneralInteractedRowItem(initialSize, stableId: stableId, name: option.title, nameStyle: .init(font: .normal(.title), foregroundColor: arguments.presentation.colors.text), type: .selectable(option.selected), viewType: bestGeneralViewType(state.options, for: i), action: {
                arguments.toggleOption(i)
            }, enabled: option.editable, disabledAction: {
                
            }, customTheme: .initialize(arguments.presentation))
        }))
        index += 1
    }
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    return entries
}

public func ModalOptionSetController(context: any AccountContextProtocol, options: [ModalOptionSet], selectOne: Bool = false, actionText: (String, NSColor), desc: String? = nil, header: String? = nil, title: String, result: @escaping ([ModalOptionSetResult])->Void, presentation: TelegramPresentationTheme = theme) -> InputDataModalController {
    
    let initialState: ModalOptionsState = ModalOptionsState(options: options, selectOne: selectOne)
    let stateValue: Atomic<ModalOptionsState> = Atomic(value: initialState)
    let statePromise: ValuePromise<ModalOptionsState> = ValuePromise(initialState, ignoreRepeated: true)
    
    let updateState: (_ f:(ModalOptionsState)->ModalOptionsState)->Void = { f in
        statePromise.set(stateValue.modify(f))
    }
    
    let arguments = ModalOptionsArguments(context: context, presentation: presentation, toggleOption: { index in
        updateState {
            $0.withToggledOptionAt(index)
        }
    })
    
    let actionsDisposable = DisposableSet()
    
    let dataSignal = statePromise.get() |> mapToSignal { state in
        return .single(modalOptionsSetEntries(state: state, desc: desc, header: header, arguments: arguments))
    } |> map { entries in
        return InputDataSignalValue(entries: entries)
    }
    
    
    var dismiss:(()->Void)?
    
    
    let controller = InputDataController(dataSignal: dataSignal, title: title, validateData: { data in
        
        result(stateValue.with { state in
            return state.options.map { option in
                if option.selected {
                    return .selected
                } else {
                    return .none
                }
            }
        })
        
        dismiss?()
        
        return .fail(.none)
    }, afterDisappear: {
        actionsDisposable.dispose()
    })
    controller.analyticsScreen = .appOptionPicker
    
    let modalInteractions: ModalInteractions = ModalInteractions(acceptTitle: actionText.0, accept: { [weak controller] in
        controller?.validateInputValues()
    }, singleButton: true, customTheme: {
        .init(presentation: presentation)
    })
    
    
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(300, 300))
    
    dismiss = { [weak modalController] in
        modalController?.close()
    }
    
    controller.leftModalHeader = ModalHeaderData(image: presentation.icons.modalClose, handler: dismiss)
    
    controller.getBackgroundColor = {
        presentation.colors.listBackground
    }
    
    modalController.getModalTheme = {
        .init(presentation: presentation)
    }
    
    
    return modalController
}
