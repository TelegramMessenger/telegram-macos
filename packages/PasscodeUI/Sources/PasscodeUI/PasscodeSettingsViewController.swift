import Cocoa
import TGUIKit
import TelegramCore
import InAppSettings
import SwiftSignalKit
import Postbox
import LocalAuthentication
import Localization
import GeneralRows
import TelegramUtils
import TelegramTheme
import TelegramContext

private enum PasscodeEntry : Comparable, Identifiable {
    case turnOn(sectionId:Int, viewType: GeneralViewType)
    case turnOff(sectionId:Int, viewType: GeneralViewType)
    case turnOnDescription(sectionId:Int, viewType: GeneralViewType)
    case turnOffDescription(sectionId:Int, viewType: GeneralViewType)
    case change(sectionId:Int, viewType: GeneralViewType)
    case autoLock(sectionId:Int, time:Int32?, viewType: GeneralViewType)
    case turnTouchId(sectionId:Int, enabled: Bool, viewType: GeneralViewType)
    case lockTelegramHeader(sectionId:Int, viewType: GeneralViewType)
    case lockWalletHeader(sectionId:Int, viewType: GeneralViewType)
    case walletPasscode(sectionId:Int, enabled: Bool, available: Bool, viewType: GeneralViewType)
    case walletBiometrics(sectionId:Int, enabled: Bool, available: Bool, viewType: GeneralViewType)
    case walletInfo(sectionId:Int, viewType: GeneralViewType)
    case section(sectionId:Int)
    
    public var stableId:Int {
        switch self {
        case .turnOn:
            return 0
        case .turnOff:
            return 1
        case .turnOnDescription:
            return 2
        case .turnOffDescription:
            return 3
        case .change:
            return 4
        case .autoLock:
            return 5
        case .turnTouchId:
            return 6
        case .lockTelegramHeader:
            return 7
        case .lockWalletHeader:
            return 8
        case .walletPasscode:
            return 9
        case .walletBiometrics:
            return 10
        case .walletInfo:
            return 11
        case let .section(sectionId):
            return (sectionId + 1) * 1000 - sectionId
        }
    }
    
    public var stableIndex:Int {
        switch self {
        case let .turnOn(sectionId, _):
            return (sectionId * 1000) + stableId
        case let .turnOff(sectionId, _):
            return (sectionId * 1000) + stableId
        case let .turnOnDescription(sectionId, _):
            return (sectionId * 1000) + stableId
        case let .turnOffDescription(sectionId, _):
            return (sectionId * 1000) + stableId
        case let .change(sectionId, _):
            return (sectionId * 1000) + stableId
        case let .autoLock(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .turnTouchId(sectionId, _, _):
            return (sectionId * 1000) + stableId
        case let .lockTelegramHeader(sectionId, _):
            return (sectionId * 1000) + stableId
        case let .lockWalletHeader(sectionId, _):
            return (sectionId * 1000) + stableId
        case let .walletPasscode(sectionId, _, _, _):
            return (sectionId * 1000) + stableId
        case let .walletBiometrics(sectionId, _, _, _):
            return (sectionId * 1000) + stableId
        case let .walletInfo(sectionId, _):
            return (sectionId * 1000) + stableId
        case let .section(sectionId):
            return (sectionId + 1) * 1000 - sectionId
        }
    }
}

private func <(lhs:PasscodeEntry, rhs:PasscodeEntry) -> Bool {
    return lhs.stableIndex < rhs.stableIndex
}



private func passcodeSettinsEntry(_ passcode: PostboxAccessChallengeData, passcodeSettings: PasscodeSettings, _ additional: AdditionalSettings, walletProtection: PasscodeWalletProtection?, walletAvailable: Bool) -> [PasscodeEntry] {
    var entries:[PasscodeEntry] = []
    
    var sectionId:Int = 1
    entries.append(.section(sectionId: sectionId))
    sectionId += 1
    
    switch passcode {
    case .none:
        entries.append(.turnOn(sectionId: sectionId, viewType: .singleItem))
        entries.append(.turnOnDescription(sectionId: sectionId, viewType: .textBottomItem))
    case .plaintextPassword, .numericalPassword, .secured:
        entries.append(.turnOff(sectionId: sectionId, viewType: .firstItem))
        entries.append(.change(sectionId: sectionId, viewType: .lastItem))
        entries.append(.turnOffDescription(sectionId: sectionId, viewType: .textBottomItem))
        
        entries.append(.section(sectionId: sectionId))
        sectionId += 1
        
        let context = LAContext()
        entries.append(.lockTelegramHeader(sectionId: sectionId, viewType: .textTopItem))
        entries.append(.autoLock(sectionId: sectionId, time: passcodeSettings.timeout, viewType: context.canUseBiometric ? .firstItem : .singleItem))
        if context.canUseBiometric {
            entries.append(.turnTouchId(sectionId: sectionId, enabled: additional.useTouchId, viewType: .lastItem))
        }

        if walletAvailable {
            entries.append(.section(sectionId: sectionId))
            sectionId += 1

            let available = walletProtection != nil
            let protectionEnabled = walletProtection?.enabled == true
            let biometricsEnabled = walletProtection?.biometricsEnabled == true
            let canUseBiometrics = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
            let showBiometrics = protectionEnabled && (canUseBiometrics || biometricsEnabled)
            entries.append(.lockWalletHeader(sectionId: sectionId, viewType: .textTopItem))
            entries.append(.walletPasscode(sectionId: sectionId, enabled: protectionEnabled, available: available, viewType: showBiometrics ? .firstItem : .singleItem))
            if showBiometrics {
                entries.append(.walletBiometrics(sectionId: sectionId, enabled: biometricsEnabled, available: available, viewType: .lastItem))
            }
            entries.append(.walletInfo(sectionId: sectionId, viewType: .textBottomItem))
        }
    }
    
    entries.append(.section(sectionId: sectionId))
    sectionId += 1

    
    return entries
}

private let actionStyle:ControlStyle = blueActionButton

fileprivate func prepareTransition(left:[AppearanceWrapperEntry<PasscodeEntry>], right: [AppearanceWrapperEntry<PasscodeEntry>], initialSize:NSSize, arguments:PasscodeSettingsArguments) -> TableUpdateTransition {
    
    func passcodeItem(_ entry: AppearanceWrapperEntry<PasscodeEntry>, initialSize: NSSize, arguments: PasscodeSettingsArguments) -> TableRowItem {
        switch entry.entry {
        case .section:
            return GeneralRowItem(initialSize, height: 20, stableId: entry.stableId, viewType: .separator)
        case let .turnOn(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: entry.stableId, name: strings().passcodeTurnOn, nameStyle: actionStyle, type: .none, viewType: viewType, action: {
                arguments.turnOn()
            })
        case let .turnOff(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: entry.stableId, name: strings().passcodeTurnOff, nameStyle: actionStyle, type: .none, viewType: viewType, action: {
                arguments.turnOff()
            })
        case let .change(_, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: entry.stableId, name: strings().passcodeChange, nameStyle: actionStyle, type: .none, viewType: viewType, action: {
                arguments.change()
            })
        case let .turnOnDescription(_, viewType), let .turnOffDescription(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: entry.stableId, text: strings().passcodeControllerText, viewType: viewType)
        case let .lockTelegramHeader(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: entry.stableId, text: strings().passcodeSettingsViewControllerLockTelegram, viewType: viewType)
        case let .lockWalletHeader(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: entry.stableId, text: strings().passcodeSettingsViewControllerLockWallet, viewType: viewType)
        case let .walletInfo(_, viewType):
            return GeneralTextRowItem(initialSize, stableId: entry.stableId, text: strings().passcodeSettingsViewControllerWalletInfo, viewType: viewType)
        case let .walletPasscode(_, enabled, available, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: entry.stableId, name: strings().passcodeSettingsViewControllerConfirmWithPasscode, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleWalletProtection(!enabled)
            }, enabled: available, autoswitch: false)
        case let .walletBiometrics(_, enabled, available, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: entry.stableId, name: strings().passcodeSettingsViewControllerConfirmWithTouchId, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleWalletBiometrics(!enabled)
            }, enabled: available, autoswitch: false)
        case let .turnTouchId(_, enabled, viewType):
            return GeneralInteractedRowItem(initialSize, stableId: entry.stableId, name: strings().passcodeUseTouchId, type: .switchable(enabled), viewType: viewType, action: {
                arguments.toggleTouchId(!enabled)
            })
        case let .autoLock(sectionId: _, time, viewType):
            
            var text:String
            if let time = time {
                if time < 60 {
                    text = strings().timerSecondsOther(Int(time))
                } else if time < 60 * 60  {
                    text = strings().timerMinutesOther(Int(time / 60))
                } else if time < 60 * 60 * 24  {
                    text = strings().timerHoursOther(Int(time / 60) / 60)
                } else {
                    text = strings().timerDaysOther(Int(time / 60) / 60 / 24)
                }
                text = strings().passcodeAutoLockIfAway(text)
            } else {
                text = strings().passcodeAutoLockDisabled
            }
            return GeneralInteractedRowItem(initialSize, stableId: entry.stableId, name: strings().passcodeAutolock, type: .context(text), viewType: viewType, action: {
                arguments.ifAway()
            })
        }
    }

    let (removed, inserted, updated) = proccessEntriesWithoutReverse(left, right: right) { entry -> TableRowItem in
        return passcodeItem(entry, initialSize: initialSize, arguments: arguments).settingsRow()
    }
    
    return TableUpdateTransition(deleted: removed, inserted: inserted, updated: updated, animated: true)
}


private final class PasscodeSettingsArguments {
    public let context: any AccountContextProtocol
    public let turnOn:()->Void
    public let turnOff:()->Void
    public let change:()->Void
    public let ifAway:()->Void
    public let toggleTouchId:(Bool)->Void
    public let toggleWalletProtection:(Bool)->Void
    public let toggleWalletBiometrics:(Bool)->Void
    public init(_ context: any AccountContextProtocol, turnOn: @escaping()->Void, turnOff: @escaping()->Void, change:@escaping()->Void, ifAway: @escaping()-> Void, toggleTouchId:@escaping(Bool)->Void, toggleWalletProtection:@escaping(Bool)->Void, toggleWalletBiometrics:@escaping(Bool)->Void) {
        self.context = context
        self.turnOn = turnOn
        self.turnOff = turnOff
        self.change = change
        self.ifAway = ifAway
        self.toggleTouchId = toggleTouchId
        self.toggleWalletProtection = toggleWalletProtection
        self.toggleWalletBiometrics = toggleWalletBiometrics
    }
}

open class PasscodeSettingsViewController<Context: AccountContextProtocol>: TableViewController<Context> {

    open override var defaultBarTitle: String {
        return strings().telegramPasscodeSettingsViewController
    }
    
    public var installsForWallet = false

    private let disposable = MetaDisposable()
    private func show(mode: PasscodeMode) {
        self.navigationController?.push(PasscodeController(sharedContext: context.sharedContext, mode: mode, installsForWallet: installsForWallet))
    }
    
    deinit {
        disposable.dispose()
    }
    
    public func updateAwayTimeout(_ timeout:Int32?) {
        disposable.set(updatePasscodeSettings(context.sharedContext.accountManager, {
            $0.withUpdatedTimeout(timeout)
        }).start())
    }
    
    public func showIfAwayOptions() {
        if let item = genericView.item(stableId: Int(5)), let view = (genericView.viewNecessary(at: item.index) as? GeneralInteractedRowView)?.textView {
            
            var items:[ContextMenuItem] = []
            
            items.append(ContextMenuItem(strings().passcodeAutoLockDisabled, handler: { [weak self] in
                self?.updateAwayTimeout(nil)
            }))
            
            
            
            items.append(ContextMenuItem(strings().passcodeAutoLockIfAway(strings().timerMinutesOther(1)), handler: { [weak self] in
                self?.updateAwayTimeout(60)
            }))
            items.append(ContextMenuItem(strings().passcodeAutoLockIfAway(strings().timerMinutesOther(5)), handler: { [weak self] in
                self?.updateAwayTimeout(60 * 5)
            }))
            items.append(ContextMenuItem(strings().passcodeAutoLockIfAway(strings().timerHoursOther(1)), handler: { [weak self] in
                self?.updateAwayTimeout(60 * 60)
            }))
            items.append(ContextMenuItem(strings().passcodeAutoLockIfAway(strings().timerHoursOther(5)), handler: { [weak self] in
                self?.updateAwayTimeout(60 * 60 * 5)
            }))
            
            if let event = NSApp.currentEvent {
                let menu = ContextMenu()
                for item in items {
                    menu.addItem(item)
                }
                let value = AppMenu(menu: menu)
                value.show(event: event, view: view)
            }            
        }
        
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        let context = self.context
        let arguments = PasscodeSettingsArguments(context, turnOn: { [weak self] in
            self?.show(mode: .install)
        }, turnOff: { [weak self] in
            self?.show(mode: .disable)
        }, change: { [weak self] in
            self?.show(mode: .change)
        }, ifAway: { [weak self] in
            self?.showIfAwayOptions()
        }, toggleTouchId: { enabled in
            _ = updateAdditionalSettingsInteractively(accountManager: context.sharedContext.accountManager, { current -> AdditionalSettings in
                return current.withUpdatedTouchId(enabled)
            }).start()
        }, toggleWalletProtection: { [weak self] enabled in
            self?.show(mode: .walletProtection(enabled: enabled))
        }, toggleWalletBiometrics: { [weak self] enabled in
            self?.show(mode: .walletBiometrics(enabled: enabled))
        })
        
        let initialSize = self.atomicSize.modify({$0})
        
       
        let previous:Atomic<[AppearanceWrapperEntry<PasscodeEntry>]> = Atomic(value: [])

        let walletProtection = PasscodeCredentialHooks.shared.walletProtection()
        let walletAvailable = context.appConfiguration.getBoolValue("wallet_available", orElse: false)

        genericView.merge(with: combineLatest(queue: prepareQueue, context.sharedContext.accountManager.accessChallengeData(), passcodeSettingsView(context.sharedContext.accountManager), appearanceSignal, additionalSettings(accountManager: context.sharedContext.accountManager), walletProtection) |> map { passcode, passcodeSettings, appearance, additional, walletProtection in
            let entries = passcodeSettinsEntry(passcode.data, passcodeSettings: passcodeSettings, additional, walletProtection: walletProtection, walletAvailable: walletAvailable).map{AppearanceWrapperEntry(entry: $0, appearance: appearance)}
            return prepareTransition(left: previous.swap(entries), right: entries, initialSize: initialSize, arguments: arguments)
        } |> deliverOnMainQueue)
        
        readyOnce()
    }
    
    
}
