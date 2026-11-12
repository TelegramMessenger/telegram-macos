import Cocoa
import TelegramCore
import InputView
import Postbox
import SwiftSignalKit
import TGUIKit
import ChatHistoryModel
import GeneralRows
import InputDataUI
import Localization
import PhoneNumberUtils
import TelegramContext
import TelegramUtils
import TelegramTheme
import AppAnalytics

private final class NewContactArguments {
    let context: any AccountContextProtocol
    let updateText:(String, String)->Void
    let toggleAddToException:(Bool)->Void
    let updateNotes:(Updated_ChatTextInputState)->Void
    init(context: any AccountContextProtocol, updateText:@escaping(String, String)->Void, toggleAddToException:@escaping(Bool)->Void, updateNotes:@escaping(Updated_ChatTextInputState)->Void) {
        self.context = context
        self.updateText = updateText
        self.toggleAddToException = toggleAddToException
        self.updateNotes = updateNotes
    }
}

private let _id_contact_info = InputDataIdentifier("_id_contact_info")
private let _id_phone_number = InputDataIdentifier("_id_phone_number")
private let _id_add_exception = InputDataIdentifier("_id_add_exception")
private let _id_notes = InputDataIdentifier("_id_notes")
private func newContactEntries(state: ChatNewContactState, arguments: NewContactArguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_contact_info, equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
        return ChatNavigationHooks.shared.makeEditAccountInfoItem(initialSize, stableId, arguments.context.account, state, arguments.updateText)
    }))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_phone_number, equatable: InputDataEquatable(state.phone), comparable: nil, item: { initialSize, stableId in
        return GeneralInteractedRowItem(initialSize, stableId: stableId, name: strings().newContactPhone, description: state.phone == nil ? strings().newContactPhoneHidden : formatPhoneNumber(state.phone!), descTextColor: theme.colors.accent, type: .none, viewType: .singleItem, action: {
            
        })
    }))
    index += 1

    if state.phone == nil {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().newContactPhoneHiddenText(state.firstName)), data: InputDataGeneralTextData(viewType: .textBottomItem)))
        index += 1
    }
    
    
    if let peerStatusSettings = state.peerStatusSettings, peerStatusSettings.contains(.addExceptionWhenAddingContact) {
        
        entries.append(.sectionId(sectionId, type: .customModern(20)))
        sectionId += 1

        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_add_exception, data: InputDataGeneralData(name: strings().newContactExceptionShareMyPhoneNumber, color: theme.colors.text, type: .switchable(state.addToException), viewType: .singleItem, action: {
            arguments.toggleAddToException(!state.addToException)
        })))
        index += 1
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().newContactExceptionShareMyPhoneNumberDesc(state.firstName)), data: InputDataGeneralTextData(viewType: .textBottomItem)))
        index += 1

    }
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_notes, equatable: .init(state.note), comparable: nil, item: { initialSize, stableId in
        return InputTextDataRowItem(initialSize, stableId: stableId, context: arguments.context, state: state.note, viewType: .singleItem, placeholder: nil, inputPlaceholder: strings().addContactAddNotesPlaceholder, canMakeTransformations: true, filter: { $0 }, updateState: { updated in
            arguments.updateNotes(updated)
        }, limit: 128, hasEmoji: true)
    }))

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    return entries
}

public func NewContactController(context: any AccountContextProtocol, peerId: PeerId) -> InputDataModalController {

    let initialState: ChatNewContactState = ChatNewContactState()
    let stateValue: Atomic<ChatNewContactState> = Atomic(value: initialState)
    let statePromise: ValuePromise<ChatNewContactState> = ValuePromise(initialState, ignoreRepeated: true)
    
    let updateState: (_ f:(ChatNewContactState)->ChatNewContactState)->Void = { f in
        statePromise.set(stateValue.modify(f))
    }
    
    let arguments = NewContactArguments(context: context, updateText: { firstName, lastName in
        updateState {
            return $0.withUpdatedFirstName(firstName).withUpdatedLastName(lastName)
        }
    }, toggleAddToException: { value in
        updateState {
            return $0.withUpdatedAddToException(value)
        }
    }, updateNotes: { updated in
        updateState {
            $0.withUpdatedNotes(updated)
        }
    })
    
    let actionsDisposable = DisposableSet()
    
    let dataSignal = statePromise.get() |> mapToSignal { state in
        if state.peer == nil {
            return .never()
        } else {
            return .single(newContactEntries(state: state, arguments: arguments))
        }
    } |> map { entries in
        return InputDataSignalValue(entries: entries)
    }
    
    actionsDisposable.add((context.account.postbox.peerView(id: peerId) |> deliverOnMainQueue).start(next: { pv in
        updateState { current in
            return current.withUpdatedPeerView(pv)
        }
    }))
    
    var dismiss:(()->Void)?
    
    let addContact:()->Void = {
        let state = stateValue.with { $0 }
        _ = showModalProgress(signal: context.engine.contacts.addContactInteractively(peerId: peerId, firstName: state.firstName, lastName: state.lastName, phoneNumber: state.phone ?? "", noteText: state.note.string, noteEntities: state.note.textInputState().messageTextEntities(), addToPrivacyExceptions: state.addToException), for: context.window).start(completed: {
            _ = showModalSuccess(for: context.window, icon: theme.icons.successModalProgress, delay: 2.0).start()
        })
        dismiss?()
    }
    
    let controller = InputDataController(dataSignal: dataSignal, title: strings().newContactTitle, validateData: { data in
        
        let firstName = stateValue.with { $0.firstName }
        if firstName.isEmpty {
            return .fail(.fields([_id_contact_info : .shake]))
        }
        addContact()
        
        return .fail(.none)
    }, afterDisappear: {
        actionsDisposable.dispose()
    })
    controller.analyticsScreen = .contactsAddKnownUser
    
    let modalInteractions: ModalInteractions = ModalInteractions(acceptTitle: strings().navigationDone, accept: { [weak controller] in
        controller?.validateInputValues()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(300, 300))
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    dismiss = { [weak modalController] in
        modalController?.close()
    }
    
    return modalController
}
