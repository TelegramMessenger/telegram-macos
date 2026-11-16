import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
import WebKit
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import FoundationUtils
import AlertsUI
import InAppSettings
import AvatarUI
import ShortPeerRow
import LocalAnimations
import AppAnalytics

private struct LogoutControllerState : Equatable {
    
}

private final class LogoutControllerArguments  {
    public let addAccount: ()->Void
    public let setPasscode: ()->Void
    public let clearCache: ()->Void
    public let changePhoneNumber: ()->Void
    public let contactSupport: ()->Void
    public let logout: ()->Void
    public init(addAccount: @escaping()-> Void, setPasscode: @escaping()->Void, clearCache: @escaping()->Void, changePhoneNumber: @escaping()->Void, contactSupport: @escaping()->Void, logout: @escaping()->Void) {
        self.addAccount = addAccount
        self.setPasscode = setPasscode
        self.clearCache = clearCache
        self.changePhoneNumber = changePhoneNumber
        self.contactSupport = contactSupport
        self.logout = logout
    }
}

private let _id_add_account: InputDataIdentifier = InputDataIdentifier("_id_add_account")
private let _id_set_a_passcode: InputDataIdentifier = InputDataIdentifier("_id_set_a_passcode")
private let _id_clear_cache: InputDataIdentifier = InputDataIdentifier("_id_clear_cache")
private let _id_change_phone_number: InputDataIdentifier = InputDataIdentifier("_id_change_phone_number")
private let _id_contact_support: InputDataIdentifier = InputDataIdentifier("_id_contact_support")

private let _id_log_out: InputDataIdentifier = InputDataIdentifier("_id_log_out")


private func logoutEntries(state: LogoutControllerState, activeAccounts: [AccountWithInfo], arguments: LogoutControllerArguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    
    var sectionId: Int32 = 0
    var index: Int32 = 0
    
    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1
    
    
    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().logoutOptionsAlternativeOptionsSection), data: InputDataGeneralTextData(viewType: .textTopItem)))
    index += 1
    
    if activeAccounts.count < 3 {
        entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_add_account, data: InputDataGeneralData(name: strings().logoutOptionsAddAccountTitle, color: theme.colors.text, icon: theme.icons.logoutOptionAddAccount, type: .next, viewType: .firstItem, description: strings().logoutOptionsAddAccountText, action: arguments.addAccount)))
        index += 1
    }

    
    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_set_a_passcode, data: InputDataGeneralData(name: strings().logoutOptionsSetPasscodeTitle, color: theme.colors.text, icon: theme.icons.logoutOptionSetPasscode, type: .next, viewType: activeAccounts.count < 3 ? .innerItem : .firstItem, description: strings().logoutOptionsSetPasscodeText, action: arguments.setPasscode)))
    index += 1
    
    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_clear_cache, data: InputDataGeneralData(name: strings().logoutOptionsClearCacheTitle, color: theme.colors.text, icon: theme.icons.logoutOptionClearCache, type: .next, viewType: .innerItem, description: strings().logoutOptionsClearCacheText, action: arguments.clearCache)))
    index += 1
    
    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_change_phone_number, data: InputDataGeneralData(name: strings().logoutOptionsChangePhoneNumberTitle, color: theme.colors.text, icon: theme.icons.logoutOptionChangePhoneNumber, type: .next, viewType: .innerItem, description: strings().logoutOptionsChangePhoneNumberText, action: arguments.changePhoneNumber)))
    index += 1
    
    entries.append(InputDataEntry.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_contact_support, data: InputDataGeneralData(name: strings().logoutOptionsContactSupportTitle, color: theme.colors.text, icon: theme.icons.logoutOptionContactSupport, type: .next, viewType: .lastItem, description: strings().logoutOptionsContactSupportText, action: arguments.contactSupport)))
    index += 1
    
    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1
    
    
    return entries
}

public func LogoutViewController<Context: AccountContextProtocol>(context: Context, f: @escaping((ViewController)) -> Void) -> InputDataModalController {
    
    let state: ValuePromise<LogoutControllerState> = ValuePromise(LogoutControllerState())
    let stateValue: Atomic<LogoutControllerState> = Atomic(value: LogoutControllerState())
    
    let _:((LogoutControllerState)->LogoutControllerState) -> Void = { f in
        state.set(stateValue.modify(f))
    }
    
    
    
    let logoutConfirmationDisposable = MetaDisposable()

    let arguments = LogoutControllerArguments(addAccount: {
        let testingEnvironment = NSApp.currentEvent?.modifierFlags.contains(.command) == true
        context.sharedContext.beginNewAuth(testingEnvironment: testingEnvironment)
    }, setPasscode: {
        closeAllModals()
        f(SettingsNavigationHooks.shared.makePasscodeSettingsController(context))
    }, clearCache: {
        closeAllModals()
        f(LogoutHooks.shared.makeStorageUsageController(context))
    }, changePhoneNumber: {
        closeAllModals()
        let phoneNumberController = SettingsNavigationHooks.shared.makePhoneNumberIntroController(context)
        let navigation = MajorNavigationController(type(of: phoneNumberController), phoneNumberController, context.window)
        navigation.alwaysAnimate = true
        navigation._frameRect = NSMakeRect(0, 0, 350, 400)
        navigation.readyOnce()
        showModal(with: navigation, for: context.window)
    }, contactSupport: {
        verifyAlert_button(for: context.window, information: strings().accountConfirmAskQuestion, option: strings().accountConfirmGoToFaq, successHandler: {  result in
            closeAllModals()
            switch result {
            case .basic:
                
                _ = showModalProgress(signal: context.engine.peers.supportPeerId(), for: context.window).start(next: { peerId in
                    if let peerId = peerId {
                        f(LogoutHooks.shared.makeChatController(context, peerId))
                    }
                })
            case .thrid:
                LogoutHooks.shared.openFaq(context)
            }
        })
    }, logout: {
        logoutConfirmationDisposable.set((LogoutHooks.shared.logoutConfirmationText(context) |> deliverOnMainQueue).start(next: { text in
            verifyAlert_button(for: context.window, header: strings().accountConfirmLogout, information: text, successHandler: { _ in
                closeAllModals()
                _ = logoutFromAccount(id: context.account.id, accountManager: context.sharedContext.accountManager, alreadyLoggedOutRemotely: false).start()
                FastSettings.clear_uuid(context.account.id.int64)
            })
        }))
    })
    
    let signal = combineLatest(state.get() |> distinctUntilChanged, context.sharedContext.activeAccountsWithInfo |> map {$0.accounts}) |> map { state, activeAccounts in
        return logoutEntries(state: state, activeAccounts: activeAccounts, arguments: arguments)
    }
    
    let controller = InputDataController(dataSignal: signal |> map { InputDataSignalValue(entries: $0) }, title: strings().logoutOptionsTitle, hasDone: false)
    controller.analyticsScreen = .settingsLogout

    controller.onDeinit = {
        logoutConfirmationDisposable.dispose()
    }
    
    
    let modalController = InputDataModalController(controller, modalInteractions: ModalInteractions(acceptTitle: strings().logoutOptionsLogOut, accept: {
        arguments.logout()
    }, singleButton: true))
    
    controller.afterTransaction = { [weak modalController] controller in
        modalController?.modalInteractions?.updateDone { button in
            button.set(background: theme.colors.redUI, for: .Normal)
        }
    }
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
           modalController?.close()
    })
    
    return modalController
}
