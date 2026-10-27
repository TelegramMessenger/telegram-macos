import Cocoa
import TGUIKit
import Postbox
import TelegramCore
import ApiCredentials
import SwiftSignalKit
import ThemeSettings
import OpenSSLEncryption
import BuildConfig
import Localization
import FoundationUtils
import RLottie
import PasscodeCore

class ShareViewController: NSViewController {
    private static var requestLogger: Logger?

    override var nibName: NSNib.Name? {
        return "ShareViewController"
    }
    
    
    
    private var contextValue: AuthorizedApplicationContext?
    private let context = Promise<AuthorizedApplicationContext?>()
    private var passlock: SEPasslockController? = nil
    private let sessionDisposable = MetaDisposable()
    private let readyDisposable = MetaDisposable()
    private var sessionDisposables: DisposableSet?
    private var requestIsActive = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        beginSharingRequest()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        if !requestIsActive {
            beginSharingRequest()
        }
    }

    override func viewDidDisappear() {
        super.viewDidDisappear()
        finishSharingRequest()
    }

    private func beginSharingRequest() {
        guard !requestIsActive else {
            return
        }
        requestIsActive = true
        let disposables = DisposableSet()
        sessionDisposables = disposables
        sessionDisposable.set(disposables)

        installTelegramThemeHooks()
        
        System.legacyMenu = false
        System.updateScaleFactor(NSScreen.main?.backingScaleFactor ?? 1)
        

        guard let containerUrl = ApiEnvironment.containerURL else {
            return
        }
        if ShareViewController.requestLogger == nil {
            let logger = Logger(rootPath: containerUrl.path, basePath: containerUrl.path + "/logs")
            logger.logToConsole = false
            logger.logToFile = false
            ShareViewController.requestLogger = logger
            Logger.setSharedLogger(logger)
        }
        try! PasscodeEnvironment.shared.configure(PasscodeConfiguration(appGroupIdentifier: ApiEnvironment.group, processRole: .appExtension, keychainScope: ApiEnvironment.prefix == "debug" ? "debug" : nil))
        initializeAccountManagement()
        let rootPath = containerUrl.path
        let accountManager = AccountManager<TelegramAccountManagerTypes>(basePath: rootPath + "/accounts-metadata", isTemporary: false, isReadOnly: true, useCaches: true, removeDatabaseOnError: true, accessChallenge: makeAccountManagerAccessChallenge(basePath: rootPath + "/accounts-metadata", isTemporary: false, isReadOnly: true))
        let localization = accountManager.transaction { transaction in
            return transaction.getSharedData(SharedDataKeys.localizationSettings)?.get(LocalizationSettings.self)
        }
        disposables.add((combineLatest(themeSettingsView(accountManager: accountManager) |> take(1), localization)
        |> deliverOnMainQueue).start(next: { [weak self] settings, localization in
            guard let self, self.requestIsActive else { return }
            self.prepareSharingRequest(accountManager: accountManager, rootPath: rootPath, themeSettings: settings, localization: localization)
        }))
    }

    private func prepareSharingRequest(accountManager: AccountManager<TelegramAccountManagerTypes>, rootPath: String, themeSettings: ThemePaletteSettings, localization: LocalizationSettings?) {
        if let localization = localization {
            applyUILocalization(localization)
        }
        
        telegramUpdateTheme(updateTheme(with: themeSettings), window: nil, animated: false)

        
        let appEncryption = AppEncryptionParameters(path: rootPath)
        
        if let deviceSpecificEncryptionParameters = appEncryption.decrypt() {
            let parameters = ValueBoxEncryptionParameters(forceEncryptionIfNoSet: true, key: ValueBoxEncryptionParameters.Key(data: deviceSpecificEncryptionParameters.key)!, salt: ValueBoxEncryptionParameters.Salt(data: deviceSpecificEncryptionParameters.salt)!)
            launchExtension(accountManager: accountManager, encryptionParameters: parameters, appEncryption: appEncryption)
        } else {
            let extensionContext = self.extensionContext!
            
            self.passlock = SEPasslockController(checkNextValue: { passcode in
                appEncryption.applyPasscode(passcode)
                if let params = appEncryption.decrypt() {
                    let parameters = ValueBoxEncryptionParameters(forceEncryptionIfNoSet: true, key: ValueBoxEncryptionParameters.Key(data: params.key)!, salt: ValueBoxEncryptionParameters.Salt(data: params.salt)!)
                    self.launchExtension(accountManager: accountManager, encryptionParameters: parameters, appEncryption: appEncryption)
                    return true
                } else {
                    return false
                }
            }, cancelImpl: { [weak self] in
                self?.finishSharingRequest()
                let cancelError = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError, userInfo: nil)
                extensionContext.cancelRequest(withError: cancelError)
            })
            
            self.passlock!.view.frame = self.view.bounds
            self.view.addSubview(self.passlock!.view)
        }
    }

    
    private func launchExtension(accountManager: AccountManager<TelegramAccountManagerTypes>, encryptionParameters: ValueBoxEncryptionParameters, appEncryption: AppEncryptionParameters) {
        
        
        let extensionContext = self.extensionContext!

        let containerUrl = ApiEnvironment.containerURL!
        
        let rootPath = containerUrl.path

        let appData: Signal<Data?, NoError> = Signal { subscriber in
            subscriber.putNext(ApiEnvironment.appData)
            subscriber.putCompletion()
            return EmptyDisposable
        } |> runOn(.concurrentBackgroundQueue())
        
        var useBetaFeatures: Bool = false
        #if BETA || DEBUG
        useBetaFeatures = false
        #endif
        
        let networkArguments = NetworkInitializationArguments(apiId: ApiEnvironment.apiId, apiHash: ApiEnvironment.apiHash, languagesCategory: ApiEnvironment.language, appVersion: ApiEnvironment.version, voipMaxLayer: 90, voipVersions: [], appData: appData, externalRequestVerificationStream: .single([:]), externalRecaptchaRequestVerification: { _, _ in return .complete() }, autolockDeadine: .single(nil), encryptionProvider: OpenSSLEncryptionProvider(), deviceModelName: deviceModelPretty(), useBetaFeatures: useBetaFeatures, isICloudEnabled: false)
        
        let sharedContext = SharedAccountContext(accountManager: accountManager, networkArguments: networkArguments, rootPath: rootPath, encryptionParameters: encryptionParameters, appEncryption: appEncryption, displayUpgradeProgress: { _ in })
        
      

        
        let rawAccounts = sharedContext.activeAccounts
            |> map { _, accounts, _ -> [Account] in
                return accounts.map({ $0.1 })
        }
        sessionDisposables?.add((sharedAccountInfos(accountManager: sharedContext.accountManager, accounts: rawAccounts)
            |> deliverOn(Queue())).start(next: { infos in
                storeAccountsData(rootPath: rootPath, accounts: infos)
            }))
        
        
        
        sessionDisposables?.add((self.context.get() |> mapToSignal { context -> Signal<AuthorizedApplicationContext?, NoError> in
            return .single(context)
            
            } |> deliverOnMainQueue).start(next: { [weak self] context in
                guard let self, self.requestIsActive else { return }
                assert(Queue.mainQueue().isCurrent())
                
                if let context = context {
                    context.rootController.view.frame = self.view.bounds
                    
                    self.readyDisposable.set((context.rootController.ready.get() |> take(1)).start(next: { [weak self, weak context] _ in
                        guard let self, self.requestIsActive, let context else { return }
                        if let contextValue = self.contextValue {
                            performSubviewRemoval(contextValue.rootController.view, animated: false)
                        }
                        let hasPrevious = self.contextValue != nil
                        self.contextValue = context
                        if let passlock = self.passlock, passlock.isLoaded() {
                            performSubviewRemoval(passlock.view, animated: true)
                            self.passlock = nil
                        }
                        self.view.addSubview(context.rootController.view, positioned: .below, relativeTo: self.view.subviews.first)
                        if hasPrevious {
                            context.rootController.view.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                        }
                        
                    }))
                }
            }))
        
        
        self.context.set(sharedContext.activeAccounts
            |> map { primary, _, _ -> Account? in
                return primary
            }
            |> distinctUntilChanged(isEqual: { lhs, rhs in
                if lhs !== rhs {
                    return false
                }
                return true
            })
            |> map { [weak self] account in
                if let account = account {
                    let context = AccountContext(sharedContext: sharedContext, window: Window(contentRect: NSZeroRect, styleMask: [], backing: NSWindow.BackingStoreType.buffered, defer: true), account: account)
                    return AuthorizedApplicationContext(context: context, shareContext: extensionContext, requestFinished: { [weak self] in
                        self?.finishSharingRequest()
                    })
                    
                } else {
                    return nil
                }
            })
    }

    private func finishSharingRequest() {
        guard requestIsActive else {
            return
        }
        requestIsActive = false
        sessionDisposable.set(nil)
        sessionDisposables = nil
        readyDisposable.set(nil)
        context.set(.single(nil))
        contextValue?.context.account.network.shouldKeepConnection.set(.single(false))
        contextValue?.rootController.view.removeFromSuperview()
        contextValue = nil
        passlock?.view.removeFromSuperview()
        passlock = nil
    }

    deinit {
        sessionDisposable.dispose()
        readyDisposable.dispose()
    }

}

