import Cocoa
import TGUIKit
import TelegramCore
import InputView
import SwiftSignalKit
import Postbox
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import ChatHistoryModel
import ChatUI
import AppAnalytics

private final class Arguments {
    let context: any AccountContextProtocol
    let updateNotes:(Updated_ChatTextInputState)->Void
    init(context: any AccountContextProtocol, updateNotes:@escaping(Updated_ChatTextInputState)->Void) {
        self.context = context
        self.updateNotes = updateNotes
    }
}

private struct AddContactState : Equatable {
    let firstName: String
    let lastName: String
    let phoneNumber: String
    let notes: Updated_ChatTextInputState
    
    let errors: [InputDataIdentifier : InputDataValueError]
    
    init(firstName: String, lastName: String, phoneNumber: String, errors: [InputDataIdentifier : InputDataValueError], notes: Updated_ChatTextInputState) {
        self.firstName = firstName
        self.lastName = lastName
        self.phoneNumber = phoneNumber
        self.errors = errors
        self.notes = notes
    }
    
    func withUpdatedError(_ error: InputDataValueError?, for key: InputDataIdentifier) -> AddContactState {
        var errors = self.errors
        if let error = error {
            errors[key] = error
        } else {
            errors.removeValue(forKey: key)
        }
        return AddContactState(firstName: self.firstName, lastName: self.lastName, phoneNumber: self.phoneNumber, errors: errors, notes: self.notes)
    }
    
    func withUpdatedFirstName(_ firstName: String) -> AddContactState {
        return AddContactState(firstName: firstName, lastName: self.lastName, phoneNumber: self.phoneNumber, errors: self.errors, notes: self.notes)
    }
    func withUpdatedLastName(_ lastName: String) -> AddContactState {
        return AddContactState(firstName: self.firstName, lastName: lastName, phoneNumber: self.phoneNumber, errors: self.errors, notes: self.notes)
    }
    func withUpdatedPhoneNumber(_ phoneNumber: String) -> AddContactState {
        return AddContactState(firstName: self.firstName, lastName: self.lastName, phoneNumber: phoneNumber, errors: self.errors, notes: self.notes)
    }
    func withUpdatedNotes(_ notes: Updated_ChatTextInputState) -> AddContactState {
        return AddContactState(firstName: self.firstName, lastName: self.lastName, phoneNumber: self.phoneNumber, errors: self.errors, notes: notes)
    }
}

private let _id_input_first_name = InputDataIdentifier("_id_input_first_name")
private let _id_input_last_name = InputDataIdentifier("_id_input_last_name")
private let _id_input_phone_number = InputDataIdentifier("_id_input_phone_number")
private let _id_notes = InputDataIdentifier("_id_notes")

private func addContactEntries(state: AddContactState, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    
    var sectionId: Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    entries.append(InputDataEntry.input(sectionId: sectionId, index: index, value: .string(state.firstName), error: state.errors[_id_input_first_name], identifier: _id_input_first_name, mode: .plain, data: InputDataRowData(viewType: .firstItem), placeholder: nil, inputPlaceholder: strings().contactsFirstNamePlaceholder, filter: { $0 }, limit: 255))
    index += 1

    entries.append(InputDataEntry.input(sectionId: sectionId, index: index, value: .string(state.lastName), error: state.errors[_id_input_last_name], identifier: _id_input_last_name, mode: .plain, data: InputDataRowData(viewType: .innerItem), placeholder: nil, inputPlaceholder: strings().contactsLastNamePlaceholder, filter: { $0 }, limit: 255))
    index += 1
    
    entries.append(InputDataEntry.input(sectionId: sectionId, index: index, value: .string(state.phoneNumber), error: state.errors[_id_input_phone_number], identifier: _id_input_phone_number, mode: .plain, data: InputDataRowData(viewType: .lastItem), placeholder: nil, inputPlaceholder: strings().contactsPhoneNumberPlaceholder, filter: { text in
        return text.trimmingCharacters(in: CharacterSet(charactersIn: "0987654321+ ").inverted)
    }, limit: 30))
    index += 1
    
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_notes, equatable: .init(state.notes), comparable: nil, item: { initialSize, stableId in
        return InputTextDataRowItem(
            initialSize,
            stableId: stableId,
            context: arguments.context,
            state: state.notes,
            viewType: .singleItem,
            placeholder: nil,
            inputPlaceholder: strings().addContactAddNotesPlaceholder,
            canMakeTransformations: true,
            filter: { $0 },
            updateState: { updated in
                arguments.updateNotes(updated)
            },
            limit: 128,
            hasEmoji: true
        )

    }))
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    return entries
}

public func AddContactModalController(_ context: any AccountContextProtocol) -> InputDataModalController {
    
    
    let initialState = AddContactState(firstName: "", lastName: "", phoneNumber: "", errors: [:], notes: .init())
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: false)
    let stateValue = Atomic(value: initialState)
    let updateState: ((AddContactState) -> AddContactState) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let arguments = Arguments(context: context, updateNotes: { updated in
        updateState {
            $0.withUpdatedNotes(updated)
        }
    })
    
    let dataSignal = statePromise.get() |> map { state in
        return addContactEntries(state: state, arguments: arguments)
    }
    
    var close: (() -> Void)?
    
    var shouldMakeNextResponderAfterTransition: InputDataIdentifier? = nil
    
    let controller = InputDataController(dataSignal: dataSignal |> map { InputDataSignalValue(entries: $0) }, title: strings().contactsAddContact, validateData: { data in
        
        return .fail(.doSomething { f in
            let state = stateValue.with {$0}
            
            var fields: [InputDataIdentifier : InputDataValidationFailAction] = [:]
            
            if state.firstName.isEmpty {
                fields[_id_input_first_name] = .shake
                shouldMakeNextResponderAfterTransition = _id_input_first_name
            }
            
            if state.phoneNumber.isEmpty {
                fields[_id_input_phone_number] = .shake
                if shouldMakeNextResponderAfterTransition == nil {
                    shouldMakeNextResponderAfterTransition = _id_input_phone_number
                }
                updateState {
                    $0.withUpdatedError(InputDataValueError(description: strings().contactsPhoneNumberInvalid, target: .data), for: _id_input_phone_number)
                }
            }
            
            if !fields.isEmpty {
                f(.fail(.fields(fields)))
            } else {
                _ = (showModalProgress(signal: context.engine.contacts.importContact(firstName: state.firstName, lastName: state.lastName, phoneNumber: state.phoneNumber, noteText: state.notes.string, noteEntities: state.notes.textInputState().messageTextEntities()), for: context.window) |> deliverOnMainQueue).start(next: { peerId in
                    if let peerId = peerId {
                        ChatUIHooks.shared.navigateToChat(context.bindings.rootNavigation(), context, .peer(peerId))
                        close?()
                    } else {
                        updateState {
                            $0.withUpdatedError(InputDataValueError(description: strings().contactsPhoneNumberNotRegistred, target: .data), for: _id_input_phone_number)
                        }
                    }
                })
            }
            
            updateState {
                $0
            }
        })
        
       
    }, updateDatas: { data in
        updateState { state in
            return state
                .withUpdatedFirstName(data[_id_input_first_name]?.stringValue ?? "")
                .withUpdatedLastName(data[_id_input_last_name]?.stringValue ?? "")
                .withUpdatedPhoneNumber(ChatListUIHooks.shared.formatPhoneNumber(context, data[_id_input_phone_number]?.stringValue ?? ""))
                .withUpdatedError(nil, for: _id_input_first_name)
                .withUpdatedError(nil, for: _id_input_last_name)
                .withUpdatedError(nil, for: _id_input_phone_number)
        }

        return .none
    }, afterDisappear: {
        
    }, afterTransaction: { controller in
        if let identifier = shouldMakeNextResponderAfterTransition {
            controller.makeFirstResponderIfPossible(for: identifier)
        }
        shouldMakeNextResponderAfterTransition = nil
    })
    controller.analyticsScreen = .contactsAdd
    
    
    let modalInteractions = ModalInteractions(acceptTitle: strings().modalCreate, accept: { [weak controller] in
        controller?.validateInputValues()
    }, singleButton: true)
    
    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(300, 300))
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    
    close = { [weak modalController] in
        modalController?.close()
    }
    
    return modalController
}
