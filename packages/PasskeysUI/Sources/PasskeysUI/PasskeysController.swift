import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import AuthenticationServices
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
import Postbox
import InlineStickerLayer
import AppAnalytics


private final class PasskeyRowItem : GeneralRowItem {
    fileprivate let passkey: TelegramPasskey
    fileprivate let context: any AccountContextProtocol
    fileprivate let titleLayout: TextViewLayout
    fileprivate let dateLayout: TextViewLayout
    fileprivate let arguments: Arguments

    public init(_ initialSize: NSSize, stableId: AnyHashable, passkey: TelegramPasskey, context: any AccountContextProtocol, viewType: GeneralViewType, arguments: Arguments) {
        self.passkey = passkey
        self.context = context
        self.arguments = arguments

        self.titleLayout = TextViewLayout(
            .initialize(
                string: passkey.name,
                color: theme.colors.text,
                font: .medium(.text)
            ),
            maximumNumberOfLines: 1
        )

        self.dateLayout = TextViewLayout(
            .initialize(
                string: stringForFullDate(timestamp: passkey.date),
                color: theme.colors.grayText,
                font: .normal(.short)
            ),
            maximumNumberOfLines: 1
        )

        super.init(initialSize, stableId: stableId, viewType: viewType)
    }
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        return .single([
            ContextMenuItem(strings().passkeysDelete, handler: { [weak self] in
                if let passkey = self?.passkey {
                    self?.arguments.delete(passkey)
                }
            }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value)
        ])
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)

        let contentWidth = blockWidth - viewType.innerInset.left - viewType.innerInset.right - 30 - 10
        titleLayout.measure(width: contentWidth)
        dateLayout.measure(width: contentWidth)

        return true
    }

    public override func viewClass() -> AnyClass {
        return PasskeyRowView.self
    }

    public override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return dateLayout.attributedString.string
    }

    public override var height: CGFloat {
        return 50
    }
}

private final class PasskeyRowView : GeneralContainableRowView {
    private let titleView = TextView()
    private let dateView = TextView()
    private var emojiView: InlineStickerView?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleView)
        addSubview(dateView)

        titleView.userInteractionEnabled = false
        titleView.isSelectable = false

        dateView.userInteractionEnabled = false
        dateView.isSelectable = false
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func layout() {
        super.layout()

        guard let item = item as? PasskeyRowItem else {
            return
        }

        let emojiSize: CGFloat = 30
        let leftInset = item.viewType.innerInset.left

        if let emojiView = emojiView {
            emojiView.setFrameOrigin(NSMakePoint(leftInset, (containerView.frame.height - emojiSize) / 2))
        }

        let textX = leftInset + emojiSize + 10
        let totalTextHeight = item.titleLayout.layoutSize.height + 2 + item.dateLayout.layoutSize.height
        let textY = (containerView.frame.height - totalTextHeight) / 2

        titleView.setFrameOrigin(NSMakePoint(textX, textY))
        dateView.setFrameOrigin(NSMakePoint(textX, titleView.frame.maxY + 2))
    }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? PasskeyRowItem else {
            return
        }

        titleView.update(item.titleLayout)
        dateView.update(item.dateLayout)

        let emojiSize = NSMakeSize(30, 30)

        if let emojiId = item.passkey.emojiId {
            if emojiView == nil || emojiView?.animateLayer.fileId != emojiId {
                emojiView?.removeFromSuperview()
                let view = InlineStickerView(
                    account: item.context.account,
                    inlinePacksContext: item.context.inlinePacksContext,
                    emoji: .init(fileId: emojiId, file: nil, emoji: ""),
                    size: emojiSize
                )
                containerView.addSubview(view)
                self.emojiView = view
            }
        } else {
            emojiView?.removeFromSuperview()
            emojiView = nil
        }

        needsLayout = true
    }
}

private let encodeBase64URL: (Data) -> String = { data in
    var string = data.base64EncodedString()
    string = string
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
    string = string.replacingOccurrences(of: "=", with: "")
    return string
}

private final class EmptyRowItem : GeneralRowItem {
    
    public let context: any AccountContextProtocol
    public let headerLayout: TextViewLayout
    
    public let options: [OptionsListView.Option]

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol) {
        self.context = context
        
        let headerText = NSMutableAttributedString()
        headerText.append(
            string: "Protect your account",
            color: theme.colors.text,
            font: .medium(.header)
        )
        headerText.append(string: "\n")
        headerText.append(
            string: "Log in safely and keep your account secure.",
            color: theme.colors.grayText,
            font: .normal(.text)
        )

        self.headerLayout = .init(headerText, alignment: .center)
        self.headerLayout.measure(width: initialSize.width - 40)

        var options: [OptionsListView.Option] = []


        options.append(
            .init(
                image: NSImage(named: "Icon_Auction_Info_Option1")!.precomposed(theme.colors.accent),
                header: .init(
                    .initialize(
                        string: "Create a Passkey",
                        color: theme.colors.text,
                        font: .medium(.text)
                    )
                ),
                text: .init(
                    .initialize(
                        string: "Make a passkey to sign in easily and safely.",
                        color: theme.colors.grayText,
                        font: .normal(.text)
                    )
                ),
                width: initialSize.width - 40
            )
        )

        options.append(
            .init(
                image: NSImage(named: "Icon_Auction_Info_Option2")!.precomposed(theme.colors.accent),
                header: .init(
                    .initialize(
                        string: "Log in with Touch ID",
                        color: theme.colors.text,
                        font: .medium(.text)
                    )
                ),
                text: .init(
                    .initialize(
                        string: "Use Touch ID, or your passcode to sign in.",
                        color: theme.colors.grayText,
                        font: .normal(.text)
                    )
                ),
                width: initialSize.width - 40
            )
        )

        options.append(
            .init(
                image: NSImage(named: "Icon_Auction_Info_Option3")!.precomposed(theme.colors.accent),
                header: .init(
                    .initialize(
                        string: "Store Passkey Securely",
                        color: theme.colors.text,
                        font: .medium(.text)
                    )
                ),
                text: .init(
                    .initialize(
                        string: "Your passkey is safely kept in your iCloud Keychain.",
                        color: theme.colors.grayText,
                        font: .normal(.text)
                    )
                ),
                width: initialSize.width - 40
            )
        )

        self.options = options

        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }
    
    public override var height: CGFloat {
        var height: CGFloat = 100
        height += 20
        height += headerLayout.layoutSize.height
        height += 20
        height += OptionsListView.height(options: options, spacing: 20) + 20
        
        return height
    }
    public override func viewClass() -> AnyClass {
        return EmptyRowView.self
    }

    public override var accessibilityLabel: String? {
        return headerLayout.attributedString.string
    }
}

private final class EmptyRowView: GeneralContainableRowView {
    
    
    private let stickerView: PasskeysStickerView = PasskeysHooks.shared.makeStickerView()
    private let headerView = TextView()
    
    
    private let optionsView = OptionsListView(frame: .zero)
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(headerView)
        self.addSubview(stickerView)
        
        addSubview(optionsView)
        
        headerView.isSelectable = false
        
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func layout() {
        super.layout()
        stickerView.centerX(y: 0)
        headerView.centerX(y: stickerView.frame.maxY + 20)
        
        optionsView.centerX(y: headerView.frame.maxY + 20)
                
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? EmptyRowItem else {
            return
        }
        
        headerView.update(item.headerLayout)
        
        stickerView.updateSticker(animation: LocalAnimatedSticker.keychain, size: NSMakeSize(100, 100), context: item.context, table: item.table, animated: animated)
        
        
        
        optionsView.spacing = 20
        optionsView.update(options: item.options)
        
        
        needsLayout = true
    }
}



private enum PasskeyCreationError: Error {
    case cancelled
    case generic
}

private final class Arguments {
    public let context: any AccountContextProtocol
    public let requestCreatePasskey: (Data, String, Data)->Void
    public let delete: (TelegramPasskey)->Void
    public let creationFailed: (PasskeyCreationError)->Void
    public init(context: any AccountContextProtocol, requestCreatePasskey: @escaping(Data, String, Data)->Void, delete: @escaping(TelegramPasskey)->Void, creationFailed: @escaping(PasskeyCreationError)->Void) {
        self.context = context
        self.requestCreatePasskey = requestCreatePasskey
        self.delete = delete
        self.creationFailed = creationFailed
    }
}

private struct State : Equatable {
    public var passkeys: [TelegramPasskey]
    public var isCreating = false
}

private let _id_empty = InputDataIdentifier("_id_empty")
private let _id_header = InputDataIdentifier("_id_header")

private func _id_passkey(_ id: String) -> InputDataIdentifier {
    return .init("_id_passkey_\(id)")
}
private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId:Int32 = 0
    var index: Int32 = 0

    if state.passkeys.isEmpty {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_empty, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
            return EmptyRowItem(initialSize, stableId: stableId, context: arguments.context)
        }))
    } else {
        let headerText = NSMutableAttributedString()
        headerText.append(string: strings().passkeysTitle, color: theme.colors.text, font: .medium(.huge))
        headerText.append(string: "\n")
        headerText.append(string: strings().passkeysDescription, color: theme.colors.listGrayText, font: .normal(.text))

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: nil, comparable: nil, item: { initialSize, stableId in
            return PasskeysHooks.shared.makeStickerHeaderItem(initialSize, stableId, arguments.context, LocalAnimatedSticker.keychain, headerText, NSMakeSize(80, 80), nil, nil)
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1

        struct Tuple : Equatable {
            var passkey: TelegramPasskey
            var viewTyle: GeneralViewType
        }
        var tuples: [Tuple] = []
        for (i, passkey) in state.passkeys.enumerated() {
            tuples.append(.init(passkey: passkey, viewTyle: bestGeneralViewType(state.passkeys, for: i)))
        }
        for tuple in tuples {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_passkey(tuple.passkey.id), equatable: .init(tuple), comparable: nil, item: { initialSize, stableId in
                return PasskeyRowItem(initialSize, stableId: stableId, passkey: tuple.passkey, context: arguments.context, viewType: tuple.viewTyle, arguments: arguments)
            }))
        }
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

@available(macOS 12.0, *)
private class Delegate : NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    fileprivate let context: any AccountContextProtocol
    fileprivate let arguments: Arguments
    private var activeAuthorization: ASAuthorizationController?
    public init(context: any AccountContextProtocol, arguments: Arguments) {
        self.arguments = arguments
        self.context = context
    }
    
    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard controller === activeAuthorization else {
            return
        }
        activeAuthorization = nil
        guard let credential = authorization.credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration,
              let clientData = String(data: credential.rawClientDataJSON, encoding: .utf8),
              let attestationObject = credential.rawAttestationObject else {
            arguments.creationFailed(.generic)
            return
        }
        arguments.requestCreatePasskey(credential.credentialID, clientData, attestationObject)
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        guard controller === activeAuthorization else {
            return
        }
        activeAuthorization = nil
        if let error = error as? ASAuthorizationError, error.code == .canceled {
            arguments.creationFailed(.cancelled)
        } else {
            arguments.creationFailed(.generic)
        }
    }

    public func cancel() {
        let authorization = activeAuthorization
        activeAuthorization = nil
        if #available(macOS 13.0, *) {
            authorization?.cancel()
        }
    }

    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        return context.window
    }
    
    public func createPasskey(_ registrationData: Data) -> Bool {
        let decodeBase64: (String) -> Data? = { string in
            var string = string.replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            while string.count % 4 != 0 {
                string.append("=")
            }
            return Data(base64Encoded: string)
        }
        
        guard let params = try? JSONSerialization.jsonObject(with: registrationData) as? [String: Any] else {
            return false
        }
        guard let pkDict = params["publicKey"] as? [String: Any] else {
            return false
        }
        guard let rp = pkDict["rp"] as? [String: Any] else {
            return false
        }
        guard let relyingPartyIdentifier = rp["id"] as? String else {
            return false
        }
        guard let challengeBase64 = pkDict["challenge"] as? String else {
            return false
        }
        guard let challengeData = decodeBase64(challengeBase64) else {
            return false
        }
        guard let user = pkDict["user"] as? [String: Any] else {
            return false
        }
        guard let userIdData = user["id"] as? String else {
            return false
        }
        guard let userId = decodeBase64(userIdData) else {
            return false
        }
        guard let userName = user["name"] as? String else {
            return false
        }
        
        let platformProvider = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: relyingPartyIdentifier)
        let platformKeyRequest = platformProvider.createCredentialRegistrationRequest(challenge: challengeData, name: userName, userID: userId)
        let authController = ASAuthorizationController(authorizationRequests: [platformKeyRequest])
        authController.delegate = self
        authController.presentationContextProvider = self
        activeAuthorization = authController
        authController.performRequests()
        return true
    }

}

@available(macOS 12.0, *)
public func PasskeysController(context: any AccountContextProtocol, passkeys: [TelegramPasskey]) -> InputDataModalController {
    
    
    let actionsDisposable = DisposableSet()
    var isClosed = false

    let initialState = State(passkeys: passkeys)
    
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
    
    
    func finishCreation(_ error: PasskeyCreationError? = nil) {
        guard !isClosed else {
            return
        }
        updateState { current in
            var current = current
            current.isCreating = false
            return current
        }
        if case .generic? = error {
            alert(for: window, info: strings().unknownError)
        }
    }

    let arguments = Arguments(context: context, requestCreatePasskey: { credentialID, clientData, attestationObject in
        guard !isClosed else {
            return
        }
        let passkey = context.engine.auth.requestCreatePasskey(id: encodeBase64URL(credentialID), clientData: clientData, attestationObject: attestationObject) |> deliverOnMainQueue

        actionsDisposable.add(passkey.start(next: { value in
            guard !isClosed else {
                return
            }
            if let value {
                updateState { current in
                    var current = current
                    current.passkeys.removeAll(where: { $0.id == value.id })
                    current.passkeys.insert(value, at: 0)
                    return current
                }
                finishCreation()
            } else {
                finishCreation(.generic)
            }
        }))

    }, delete: { passkey in
        verifyAlert(for: window, header: strings().passkeysDeleteTitle, information: strings().passkeysDeleteConfirmation, ok: strings().passkeysDelete, cancel: strings().modalCancel, successHandler: { _ in

            _ = showModalProgress(signal: context.engine.auth.deletePasskey(id: passkey.id), for: window).start(next: { deleted in
                guard deleted else {
                    alert(for: window, info: strings().unknownError)
                    return
                }
                updateState { current in
                    var current = current
                    current.passkeys.removeAll(where: { $0.id == passkey.id })
                    return current
                }
            })
        })
    }, creationFailed: { error in
        finishCreation(error)
    })
    
    let delegate = Delegate(context: context, arguments: arguments)

    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().passkeysTitle)
    controller.analyticsScreen = .settingsPrivacyPasskeys
    
    getController = { [weak controller] in
        return controller
    }
    
    controller.onDeinit = {
        actionsDisposable.dispose()
        delegate.cancel()
    }
    
    controller.contextObject = delegate
    
    controller.validateData = { [delegate] _ in
        
        let maxPasskeys = context.appConfiguration.getGeneralValue("passkeys_account_passkeys_max", orElse: 5)

        let state = stateValue.with { $0 }
        
        guard !isClosed, !state.isCreating else {
            return .none
        }
        if state.passkeys.count >= maxPasskeys {
            alert(for: window, info: strings().passkeysMaxLimitReached(Int(maxPasskeys)))
        } else {
            updateState { current in
                var current = current
                current.isCreating = true
                return current
            }
            let signal = context.engine.auth.requestPasskeyRegistration() |> deliverOnMainQueue
            
            actionsDisposable.add(signal.start(next: { [weak delegate] value in
                guard !isClosed else {
                    return
                }
                guard let value = value?.data(using: .utf8), delegate?.createPasskey(value) == true else {
                    finishCreation(.generic)
                    return
                }
            }))
        }
        
       
        
        return .none
    }
    let modalInteractions = ModalInteractions(acceptTitle: strings().passkeysCreatePasskey, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)
    
    controller.afterTransaction = { [weak modalInteractions] _ in
        modalInteractions?.updateDone { button in
            button.isEnabled = !stateValue.with { $0.isCreating }
        }
    }

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, closeHandler: { close in
        isClosed = true
        actionsDisposable.dispose()
        delegate.cancel()
        close()
    })
    
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
        
    return modalController
    
}





