import Foundation
import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import AvatarUI
import GeneralRows
import InputDataUI
import TGModernGrowingTextView
import AlertsUI
import PremiumUI
import AppAnalytics

private struct UsernameCheck: Equatable {
    let username: String
    let isPremium: Bool
    let status: CreateBotUsernameStatus
}

private struct State: Equatable {
    var managerUsername: String
    var managerPeer: PeerEquatable?
    var botTitle: String
    var botUsername: String
    var isPremium: Bool
    var usernameCheck: UsernameCheck?
}

private struct Arguments {
    let context: any AccountContextProtocol
    let endings: CreateBotUsernameEndings
    let dismiss: () -> Void
    let updateUsername: (String) -> Void
    let openPremium: () -> Void
}

private let _id_header = InputDataIdentifier("_id_header")
private let _id_bot_name = InputDataIdentifier("_id_bot_name")
private let _id_bot_username = InputDataIdentifier("_id_bot_username")

private func usernameStatus(_ state: State, username: CreateBotUsername) -> CreateBotUsernameStatus? {
    guard let check = state.usernameCheck, check.username == username.username.lowercased() else {
        return nil
    }
    return check.status
}

private func canCreateBot(_ state: State, endings: CreateBotUsernameEndings) -> Bool {
    guard state.managerPeer != nil else {
        return false
    }
    let resolvedUsername = CreateBotUsername(typedText: state.botUsername, endings: endings)
    return createBotCanCreate(name: state.botTitle, username: resolvedUsername, status: usernameStatus(state, username: resolvedUsername))
}

private final class CreateBotUsernameRowItem: InputDataRowItem {
    fileprivate let endings: CreateBotUsernameEndings

    init(_ initialSize: NSSize, stableId: AnyHashable, text: String, endings: CreateBotUsernameEndings, updated: @escaping (String) -> Void) {
        self.endings = endings
        super.init(initialSize, stableId: stableId, mode: .plain, error: nil, viewType: .singleItem, currentText: text, placeholder: nil, inputPlaceholder: "", defaultText: "@", filter: { $0 }, updated: updated, limit: Int32(CreateBotUsername.maxLength + 1))
    }

    fileprivate var appendedSuffix: String? {
        return CreateBotUsername(typedText: self.currentText.string, endings: self.endings).appendedSuffix
    }

    override func viewClass() -> AnyClass {
        return CreateBotUsernameRowView.self
    }
}

private final class CreateBotUsernameRowView: InputDataRowView {
    private let suffixView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        suffixView.userInteractionEnabled = false
        suffixView.isSelectable = false
        containerView.addSubview(suffixView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        updateSuffix()
    }

    override func textViewTextDidChange(_ string: String) {
        super.textViewTextDidChange(string)
        updateSuffix()
    }

    override func layout() {
        super.layout()
        layoutSuffix()
    }

    private func updateSuffix() {
        guard let item = item as? CreateBotUsernameRowItem else {
            return
        }
        if let suffix = item.appendedSuffix {
            let layout = TextViewLayout(.initialize(string: suffix, color: theme.colors.grayText, font: .normal(.text)))
            layout.measure(width: .greatestFiniteMagnitude)
            suffixView.update(layout)
            suffixView.isHidden = false
        } else {
            suffixView.isHidden = true
        }
        layoutSuffix()
    }

    private func layoutSuffix() {
        let inputView = textView.inputView
        guard let layoutManager = inputView.layoutManager, let textContainer = inputView.textContainer else {
            return
        }
        let glyphRange = layoutManager.glyphRange(for: textContainer)
        let textRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer).offsetBy(dx: inputView.textContainerOrigin.x, dy: inputView.textContainerOrigin.y)
        let rect = containerView.convert(textRect, from: inputView)
        suffixView.setFrameOrigin(NSMakePoint(rect.maxX, floorToScreenPixels(backingScaleFactor, rect.midY - suffixView.frame.height / 2)))
    }
}

private final class CreateBotHeaderItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let peer: Peer?
    fileprivate let titleLayout: TextViewLayout
    fileprivate let infoLayout: TextViewLayout
    fileprivate let dismiss: (() -> Void)?
    let photoSize = NSMakeSize(70, 70)

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, peer: Peer?, managerUsername: String, dismiss: (() -> Void)? = nil) {
        self.context = context
        self.peer = peer
        self.dismiss = dismiss

        self.titleLayout = TextViewLayout(.initialize(string: strings().createBotTitle, color: theme.colors.text, font: .medium(.header)), alignment: .center)

        let text = NSMutableAttributedString()
        _ = text.append(string: strings().createBotDescription(managerUsername), color: theme.colors.text, font: .normal(.text))
        text.detectBoldColorInString(with: .bold(.text), color: theme.colors.accent)
        self.infoLayout = TextViewLayout(text, alignment: .center)

        super.init(initialSize, stableId: stableId)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        titleLayout.measure(width: width - 40)
        infoLayout.measure(width: width - 40)
        return true
    }

    override var height: CGFloat {
        return 10 + photoSize.height + 10 + titleLayout.layoutSize.height + 10 + infoLayout.layoutSize.height + 10
    }

    override func viewClass() -> AnyClass {
        return CreateBotHeaderView.self
    }

    override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    override var accessibilityValue: String? {
        return infoLayout.attributedString.string
    }
}

private final class CreateBotHeaderView: TableRowView {
    private let avatar = AvatarControl(font: .avatar(20))
    private let titleView = TextView()
    private let infoView = TextView()
    private var dismissButton: ImageButton?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.setFrameSize(NSMakeSize(70, 70))
        addSubview(avatar)
        addSubview(titleView)
        addSubview(infoView)

        avatar.userInteractionEnabled = false
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        infoView.userInteractionEnabled = false
        infoView.isSelectable = false
    }

    override var backdorColor: NSColor {
        return .clear
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? CreateBotHeaderItem else { return }

        if let peer = item.peer {
            avatar.setPeer(account: item.context.account, peer: peer)
        }

        titleView.update(item.titleLayout)
        infoView.update(item.infoLayout)

        if let dismiss = item.dismiss {
            let current: ImageButton
            if let view = self.dismissButton {
                current = view
            } else {
                current = ImageButton()
                current.scaleOnClick = true
                current.autohighlight = false
                current.setAccessibilityLabel(strings().voiceOverCommonClose)
                self.dismissButton = current
                addSubview(current)
            }
            current.set(image: theme.icons.glass_close, for: .Normal)
            current.setGlassEffect(size: NSMakeSize(36, 36))
            current.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
            current.removeAllHandlers()
            current.set(handler: { _ in
                dismiss()
            }, for: .Click)
        } else {
            if let view = self.dismissButton {
                performSubviewRemoval(view, animated: animated)
                self.dismissButton = nil
            }
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()
        avatar.centerX(y: 15)
        titleView.centerX(y: avatar.frame.maxY + 10)
        infoView.centerX(y: titleView.frame.maxY + 10)
        dismissButton?.setFrameOrigin(NSMakePoint(10, 10))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state.managerPeer), comparable: nil, item: { initialSize, stableId in
        return CreateBotHeaderItem(initialSize, stableId: stableId, context: arguments.context, peer: state.managerPeer?.peer, managerUsername: state.managerUsername, dismiss: arguments.dismiss)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().createBotBotNameHeader), data: InputDataGeneralTextData(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.botTitle), error: nil, identifier: _id_bot_name, mode: .plain, data: InputDataRowData(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().createBotBotNamePlaceholder, filter: { $0 }, limit: 64))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(20)))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().createBotBotUsernameHeader), data: InputDataGeneralTextData(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let initialUsername = state.botUsername
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_bot_username, equatable: .init(arguments.endings), comparable: nil, item: { initialSize, stableId in
        return CreateBotUsernameRowItem(initialSize, stableId: stableId, text: initialUsername, endings: arguments.endings, updated: arguments.updateUsername)
    }))
    index += 1

    let resolvedUsername = CreateBotUsername(typedText: state.botUsername, endings: arguments.endings)
    let premiumHint = createBotUsernamePremiumHint(endings: arguments.endings, premiumLink: true)
    let footerText: String
    let footerHasLink: Bool
    var footerColor = theme.colors.redUI
    switch CreateBotUsernameFooter(username: resolvedUsername, status: usernameStatus(state, username: resolvedUsername)) {
    case .hint:
        footerText = premiumHint ?? strings().createBotUsernameHint
        footerHasLink = premiumHint != nil
        footerColor = theme.colors.listGrayText
    case .hintError:
        footerText = premiumHint ?? strings().createBotUsernameHint
        footerHasLink = premiumHint != nil
    case let .validationError(validationError):
        switch validationError {
        case .tooShort:
            footerText = strings().errorUsernameMinimumLength
        case .tooLong:
            footerText = strings().createBotModalControllerUsernameTooLongOther(CreateBotUsername.maxLength)
        case .startsWithNumber:
            footerText = strings().errorUsernameNumberStart
        case .unsupportedCharacters:
            footerText = strings().errorUsernameInvalid
        }
        footerHasLink = false
    case .invalid:
        footerText = strings().errorUsernameInvalid
        footerHasLink = false
    case .taken:
        footerText = strings().errorUsernameAlreadyTaken
        footerHasLink = false
    case let .premiumRequired(ending):
        footerText = strings().createBotModalControllerPremiumRequiredSubscribe(createBotUsernamePremiumRequiredText(ending: ending))
        footerHasLink = true
    case let .suffixLimitExceeded(limit):
        footerText = createBotUsernameSuffixLimitText(limit: limit, endings: arguments.endings)
        footerHasLink = false
    }
    let footer: GeneralRowTextType
    if footerHasLink {
        footer = .markdown(footerText, linkHandler: { _ in
            arguments.openPremium()
        })
    } else {
        footer = .plain(footerText)
    }
    entries.append(.desc(sectionId: sectionId, index: index, text: footer, data: InputDataGeneralTextData(color: footerColor, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public func CreateBotModalController(context: any AccountContextProtocol, managerUsername: String, botUsername: String, botTitle: String?, openAutomatically: Bool = true, viaDeeplink: Bool = false, completion: @escaping (PeerId?) -> Void = { _ in }) -> InputDataModalController {

    let actionsDisposable = DisposableSet()
    let availabilityDisposable = MetaDisposable()
    actionsDisposable.add(availabilityDisposable)

    let endings = CreateBotUsernameEndings(appConfiguration: context.appConfiguration)

    let initialState = State(managerUsername: managerUsername, botTitle: botTitle ?? "", botUsername: botUsername, isPremium: context.isPremium, usernameCheck: nil)

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    let checkUsername: () -> Void = {
        let state = stateValue.with { $0 }
        let resolvedUsername = CreateBotUsername(typedText: state.botUsername, endings: endings)
        let username = resolvedUsername.username.lowercased()
        let isPremium = state.isPremium
        if let check = state.usernameCheck, check.username == username, check.isPremium == isPremium {
            return
        }
        availabilityDisposable.set(nil)
        let setStatus: (CreateBotUsernameStatus) -> Void = { status in
            updateState { current in
                var current = current
                current.usernameCheck = UsernameCheck(username: username, isPremium: isPremium, status: status)
                return current
            }
        }
        if let status = CreateBotUsernameStatus.decidedLocally(for: resolvedUsername, isPremium: isPremium) {
            setStatus(status)
            return
        }
        setStatus(.checking)
        availabilityDisposable.set((context.engine.peers.checkBotUsername(username) |> delay(0.3, queue: .concurrentDefaultQueue()) |> deliverOnMainQueue).start(next: { result in
            setStatus(CreateBotUsernameStatus(result))
        }))
    }

    var close: (() -> Void)?
    var cancel: (() -> Void)?
    var closesWithoutConfirmation = false
    var isCompleted = false

    let complete: (PeerId?) -> Void = { peerId in
        guard !isCompleted else {
            return
        }
        isCompleted = true
        completion(peerId)
    }

    let arguments = Arguments(context: context, endings: endings, dismiss: {
        cancel?()
    }, updateUsername: { username in
        updateState { current in
            var current = current
            current.botUsername = username
            return current
        }
        checkUsername()
    }, openPremium: {
        prem(with: PremiumBoardingController(context: context, source: .settings), for: context.window)
    })

    actionsDisposable.add((context.engine.peers.resolvePeerByName(name: managerUsername, referrer: nil)
        |> filter { $0 != .progress }
        |> map { $0.result }
        |> deliverOnMainQueue).start(next: { peer in
            if let peer = peer {
                updateState { current in
                    var current = current
                    current.managerPeer = .init(peer._asPeer())
                    return current
                }
            }
        }))

    actionsDisposable.add((context.engine.data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: context.peerId))
        |> map { peer -> Bool in
            return peer?.isPremium ?? false
        }
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { isPremium in
            updateState { current in
                var current = current
                current.isPremium = isPremium
                return current
            }
            checkUsername()
        }))

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsScreen = .createBot

    controller.onDeinit = {
        actionsDisposable.dispose()
        complete(nil)
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().createBotCreate, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, cancelTitle: strings().modalCancel, cancel: {
        cancel?()
    })
    modalInteractions.glassButtons = true

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, closeHandler: { closeModal in
        guard !closesWithoutConfirmation else {
            complete(nil)
            closeModal()
            return
        }
        verifyAlert(for: context.window, header: strings().createBotModalControllerUnsavedChangesHeader, information: strings().createBotModalControllerUnsavedChangesInfo, ok: strings().createBotModalControllerUnsavedChangesDiscard, successHandler: { _ in
            complete(nil)
            closeModal()
        })
    })

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: {
        cancel?()
    })

    controller.afterTransaction = { [weak modalInteractions] _ in
        modalInteractions?.updateDone { button in
            button.isEnabled = canCreateBot(stateValue.with { $0 }, endings: endings)
        }
    }

    controller.updateDatas = { data in
        if let title = data[_id_bot_name]?.stringValue {
            updateState { current in
                var current = current
                current.botTitle = title
                return current
            }
        }
        return .fail(.none)
    }

    controller.validateData = { _ in
        let state = stateValue.with { $0 }
        guard canCreateBot(state, endings: endings), let managerPeer = state.managerPeer else {
            return .fail(.none)
        }
        let resolvedUsername = CreateBotUsername(typedText: state.botUsername, endings: endings)
        return .fail(.doSomething(next: { f in
            let signal = context.engine.peers.createBot(name: state.botTitle, username: resolvedUsername.username, managerPeerId: managerPeer.peer.id, viaDeeplink: viaDeeplink)
            _ = showModalProgress(signal: signal, for: context.window).start(next: { peer in
                close?()
                showModalText(for: context.window, text: strings().createBotSuccessInfo(state.managerUsername), title: strings().createBotSuccessTitle(state.botTitle))
                if openAutomatically {
                    ComposeUIHooks.shared.navigateToChat(context.bindings.rootNavigation(), context, .peer(peer.id))
                }
                complete(peer.id)
                f(.none)
            }, error: { error in
                switch error {
                case .limitExceeded:
                    let defaultLimit = context.appConfiguration.getGeneralValue("bots_create_limit_default", orElse: 20)
                    let premiumLimit = context.appConfiguration.getGeneralValue("bots_create_limit_premium", orElse: 40)
                    if context.isPremium {
                        showModalText(for: context.window, text: strings().createBotLimitReachedPremium(Int(premiumLimit)))
                    } else {
                        showModalText(for: context.window, text: strings().createBotLimitReached(Int(defaultLimit), Int(premiumLimit)), button: strings().premiumLimitIncrease, callback: { _ in
                            prem(with: PremiumBoardingController(context: context, source: .double_limits(.channels)), for: context.window)
                        })
                    }
                case .occupied:
                    alert(for: context.window, info: strings().errorUsernameAlreadyTaken)
                case .suffixNotAllowed:
                    alert(for: context.window, info: createBotUsernamePremiumHint(endings: endings, premiumLink: false) ?? strings().createBotUsernameHint)
                case .premiumRequired:
                    alert(for: context.window, info: createBotUsernamePremiumRequiredText(ending: resolvedUsername.ending))
                case let .suffixLimitExceeded(limit):
                    alert(for: context.window, info: createBotUsernameSuffixLimitText(limit: limit, endings: endings))
                case .generic:
                    alert(for: context.window, info: strings().unknownError)
                }
                f(.none)
            })
        }))
    }

    close = { [weak modalController] in
        closesWithoutConfirmation = true
        modalController?.modal?.close()
    }

    cancel = {
        complete(nil)
        close?()
    }

    checkUsername()

    return modalController
}
