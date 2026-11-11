import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import TelegramMedia
import Postbox
import InputView
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import AlertsUI
import ChatHistoryModel
import InlineStickerLayer
import AppAnalytics


private final class NewStyleIconRowItem : GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let selectedFileId: Int64?
    fileprivate let selectedFile: TelegramMediaFile?
    fileprivate let pickEmoji: (Control)->Void
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, selectedFileId: Int64?, selectedFile: TelegramMediaFile?, pickEmoji: @escaping(Control)->Void) {
        self.context = context
        self.selectedFileId = selectedFileId
        self.selectedFile = selectedFile
        self.pickEmoji = pickEmoji
        super.init(initialSize, stableId: stableId)
    }
    override var height: CGFloat {
        return 100
    }
    override var accessibilityLabel: String? {
        return strings().voiceOverCommonEmoji
    }
    override func viewClass() -> AnyClass {
        return NewStyleIconRowView.self
    }
}

private final class NewStyleIconRowView : TableRowView {
    private let circle = Control()
    private let iconView = ImageView()
    private var emojiView: InlineStickerView?
    private var currentEmojiFileId: Int64?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        circle.addSubview(iconView)
        addSubview(circle)
        iconView.isAccessibilityDecorative = true
        circle.setAccessibilityLabel(strings().voiceOverCommonChooseIcon)

        circle.scaleOnClick = true
        circle.set(handler: { [weak self] control in
            if let item = self?.item as? NewStyleIconRowItem {
                item.pickEmoji(control)
            }
        }, for: .Click)
    }


    override func shakeView() {
        circle.shake(beep: true)
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return theme.colors.listBackground
    }

    override func updateColors() {
        super.updateColors()
        backgroundColor = backdorColor
        circle.backgroundColor = theme.colors.background
        circle.layer?.cornerRadius = 40
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? NewStyleIconRowItem else { return }

        circle.setFrameSize(NSMakeSize(80, 80))
        updateColors()

        if let fileId = item.selectedFileId {
            if emojiView == nil || currentEmojiFileId != fileId {
                emojiView?.removeFromSuperview()
                let size = NSMakeSize(56, 56)
                let emoji = ChatTextCustomEmojiAttribute(fileId: fileId, file: item.selectedFile, emoji: "⭐️")
                let view = InlineStickerView(account: item.context.account, inlinePacksContext: item.context.inlinePacksContext, emoji: emoji, size: size, playPolicy: .loop)
                circle.addSubview(view)
                self.emojiView = view
                self.currentEmojiFileId = fileId
            }
            iconView.isHidden = true
        } else {
            emojiView?.removeFromSuperview()
            emojiView = nil
            currentEmojiFileId = nil
            iconView.image = NSImage(named: "Icon_NewStyle_Ai")?.precomposed(theme.colors.grayIcon)
            iconView.sizeToFit()
            iconView.isHidden = false
        }

        needsLayout = true
    }

    override func layout() {
        super.layout()
        circle.center()
        iconView.center()
        emojiView?.center()
    }
}


private final class Arguments {
    let context: any AccountContextProtocol
    let updateName: (String)->Void
    let updateInstructions: (Updated_ChatTextInputState)->Void
    let toggleDisplayAuthor: ()->Void
    let pickEmoji: (Control)->Void
    let deleteStyle: (()->Void)?
    let titleMax: Int32
    let promptMax: Int32
    init(context: any AccountContextProtocol, titleMax: Int32, promptMax: Int32, updateName: @escaping(String)->Void, updateInstructions: @escaping(Updated_ChatTextInputState)->Void, toggleDisplayAuthor: @escaping()->Void, pickEmoji: @escaping(Control)->Void, deleteStyle: (()->Void)? = nil) {
        self.context = context
        self.titleMax = titleMax
        self.promptMax = promptMax
        self.updateName = updateName
        self.updateInstructions = updateInstructions
        self.toggleDisplayAuthor = toggleDisplayAuthor
        self.pickEmoji = pickEmoji
        self.deleteStyle = deleteStyle
    }
}

private struct State : Equatable {
    var name: String = ""
    var instructions: Updated_ChatTextInputState = .init(inputText: .init())
    var displayAuthor: Bool = false
    var emojiFileId: Int64?
    var emojiFile: TelegramMediaFile?
    var emojiPackReference: StickerPackReference?
}

private let _id_icon = InputDataIdentifier("_id_icon")
private let _id_name = InputDataIdentifier("_id_name")
private let _id_instructions = InputDataIdentifier("_id_instructions")
private let _id_display_author = InputDataIdentifier("_id_display_author")
private let _id_delete_style = InputDataIdentifier("_id_delete_style")


private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0

//    entries.append(.sectionId(sectionId, type: .customModern(10)))
//    sectionId += 1

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_icon, equatable: InputDataEquatable(state.emojiFileId), comparable: nil, item: { initialSize, stableId in
        return NewStyleIconRowItem(initialSize, stableId: stableId, context: arguments.context, selectedFileId: state.emojiFileId, selectedFile: state.emojiFile, pickEmoji: arguments.pickEmoji)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.input(sectionId: sectionId, index: index, value: .string(state.name), error: nil, identifier: _id_name, mode: .plain, data: .init(viewType: .singleItem), placeholder: nil, inputPlaceholder: strings().aiStyleModalNamePlaceholder, filter: { $0 }, limit: arguments.titleMax))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    let instructionsPlaceholder = strings().aiStyleModalInstructionsPlaceholder
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_instructions, equatable: .init(state.instructions), comparable: nil, item: { initialSize, stableId in
        return InputTextDataRowItem(initialSize, stableId: stableId, context: arguments.context, state: state.instructions, viewType: .singleItem, placeholder: nil, inputPlaceholder: instructionsPlaceholder, filter: { $0 }, updateState: arguments.updateInstructions, limit: arguments.promptMax, hasEmoji: false, fitPlaceholderHeight: true)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_display_author, data: InputDataGeneralData(name: strings().aiStyleModalAddAuthorLink, color: theme.colors.text, type: .switchable(state.displayAuthor), viewType: .singleItem, action: {
        arguments.toggleDisplayAuthor()
    })))
    index += 1

    if let deleteStyle = arguments.deleteStyle {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_delete_style, data: InputDataGeneralData(name: strings().aiStyleModalDeleteStyle, color: theme.colors.redUI, viewType: .singleItem, action: {
            deleteStyle()
        })))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}


func AIStyleModalController(context: any AccountContextProtocol, editing: TelegramComposeAIMessageMode.CloudStyle? = nil, onCompleted: ((Int64?) -> Void)? = nil, analyticsContext: AnalyticsContext? = nil) -> InputDataModalController {

    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    let getAnalyticsContext: () -> AnalyticsContext = {
        Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: origin)
    }
    let onCompleted: ((Int64?) -> Void)? = onCompleted.map { callback in
        return { id in
            let presentation = getAnalyticsContext().beginPresentation()
            defer { presentation.end() }
            callback(id)
        }
    }
    let actionsDisposable = DisposableSet()

    let titleMax = context.appConfiguration.getGeneralValue("aicompose_tone_title_length_max", orElse: 12)
    let promptMax = context.appConfiguration.getGeneralValue("aicompose_tone_prompt_length_max", orElse: 1024)
    let savedLimitDefault = context.appConfiguration.getGeneralValue("aicompose_tone_saved_limit_default", orElse: 5)
    let savedLimitPremium = context.appConfiguration.getGeneralValue("aicompose_tone_saved_limit_premium", orElse: 20)
    let savedLimit = context.isPremium ? savedLimitPremium : savedLimitDefault

    var editStyleId: Int64?
    var editAccessHash: Int64?

    var initialState = State()
    if let editing, case let .custom(custom) = editing.content {
        editStyleId = custom.id
        editAccessHash = custom.accessHash
        initialState.name = custom.title
        if let prompt = custom.prompt, !prompt.isEmpty {
            let attributed = NSAttributedString(string: prompt, attributes: [.font: NSFont.normal(.text)])
            initialState.instructions = ChatTextInputState(inputText: prompt, selectionRange: prompt.length..<prompt.length, attributes: chatTextAttributes(from: TextEntitiesMessageAttribute(entities: []), associatedMedia: [:])).textInputState()
            _ = attributed
        }
        initialState.displayAuthor = custom.authorId != nil
        initialState.emojiFileId = custom.emojiFileId
    }

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        statePromise.set(stateValue.modify(f))
    }

    var close:(()->Void)? = nil
    var getController:(()->InputDataController?)? = nil

    let arguments = Arguments(context: context, titleMax: titleMax, promptMax: promptMax, updateName: { name in
        updateState { current in
            var current = current
            current.name = name
            return current
        }
    }, updateInstructions: { state in
        updateState { current in
            var current = current
            current.instructions = state
            return current
        }
    }, toggleDisplayAuthor: {
        updateState { current in
            var current = current
            current.displayAuthor = !current.displayAuthor
            return current
        }
    }, pickEmoji: { control in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        TranslateUIHooks.shared.showStyleEmojiPickerObserved(context, control, analyticsContext: getAnalyticsContext(), selected: { file in
            let presentation = getAnalyticsContext().beginPresentation()
            defer { presentation.end() }
            var packReference: StickerPackReference?
            for attr in file.attributes {
                if case let .CustomEmoji(_, _, _, ref) = attr {
                    packReference = ref
                    break
                }
            }
            updateState { current in
                var current = current
                current.emojiFileId = file.fileId.id
                current.emojiFile = file
                current.emojiPackReference = packReference
                return current
            }
        })
    }, deleteStyle: (editStyleId != nil && editAccessHash != nil) ? {
        guard let editStyleId, let editAccessHash else { return }
        let analyticsContext = getAnalyticsContext()
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        let confirmationPresentation = analyticsContext.beginPresentation()
        verifyAlert(for: context.window, header: strings().aiStyleModalDeleteStyleHeader, information: strings().aiStyleModalDeleteStyleConfirm, ok: strings().modalDelete, option: strings().aiStyleModalDeleteStyleForAll, successHandler: { result in
            let analyticsContext = getAnalyticsContext()
            let presentation = analyticsContext.beginPresentation()
            defer { presentation.end() }
            switch result {
            case .thrid:
                _ = analyticsContext.preservingPresentation(context.engine.messages.deleteAITextStyle(id: editStyleId, accessHash: editAccessHash)).startStandalone()
            case .basic:
                _ = analyticsContext.preservingPresentation(context.engine.messages.unsaveAITextStyle(id: editStyleId, accessHash: editAccessHash)).startStandalone()
            }
            onCompleted?(nil)
            close?()
        }, onDeinit: {
            confirmationPresentation.end()
        })
    } : nil)

    let signal = getAnalyticsContext().preservingPresentation(statePromise.get() |> deliverOnPrepareQueue) |> map { state in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: editing != nil ? strings().aiStyleModalEditStyleTitle : strings().aiStyleModalNewStyleTitle)
    controller.analyticsContext = origin
    controller.analyticsScreen = .chatAiEditorStyle

    controller.onDeinit = {
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        actionsDisposable.dispose()
    }

    controller.updateDatas = { data in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        if let name = data[_id_name]?.stringValue {
            updateState { current in
                var current = current
                current.name = name
                return current
            }
        }
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: editing != nil ? strings().aiStyleModalSave : strings().aiStyleModalCreate, accept: { [weak controller] in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        _ = controller?.returnKeyAction()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(360, 0))

    modalController.analyticsContext = origin

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        modalController?.close()
    })

    controller.validateData = { data in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        let state = stateValue.with { $0 }
        let trimmedName = state.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedPrompt = state.instructions.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            return .fail(.fields([_id_name: .shake]))
        }
        if trimmedPrompt.isEmpty {
            return .fail(.fields([_id_instructions: .shake]))
        }
        guard let fileId = state.emojiFileId else {
            return .fail(.fields([_id_icon: .shake]))
        }

        enum CreateStyleError { case generic, savedLimit }


        let createOrEdit: Signal<Int64?, CreateStyleError>
        if let editStyleId, let editAccessHash {
            createOrEdit = context.engine.messages.editAITextStyle(id: editStyleId, accessHash: editAccessHash, displayAuthor: state.displayAuthor, emojiFileId: fileId, title: trimmedName, prompt: trimmedPrompt)
            |> map { _ -> Int64? in nil }
            |> mapError { _ in CreateStyleError.generic }
        } else {
            createOrEdit = context.engine.messages.composeAIMessageStyles()
            |> take(1)
            |> castError(CreateStyleError.self)
            |> mapToSignal { cloudStyles -> Signal<Int64?, CreateStyleError> in
                let presentation = getAnalyticsContext().beginPresentation()
                defer { presentation.end() }
                let customCount = cloudStyles.reduce(Int32(0)) { acc, style -> Int32 in
                    if case .custom = style.content { return acc + 1 }
                    return acc
                }
                if customCount >= savedLimit {
                    return .fail(.savedLimit)
                }
                return context.engine.messages.createAITextStyle(displayAuthor: state.displayAuthor, emojiFileId: fileId, title: trimmedName, prompt: trimmedPrompt)
                |> map { cloudStyle -> Int64? in
                    if case let .custom(custom) = cloudStyle.content {
                        return custom.id
                    }
                    return nil
                }
                |> mapError { error -> CreateStyleError in
                    switch error {
                    case .premiumRequired:
                        return .savedLimit
                    case .generic:
                        return .generic
                    }
                }
            }
        }

        _ = getAnalyticsContext().preservingPresentation(showModalProgress(signal: getAnalyticsContext().preservingPresentation(createOrEdit), for: context.window)).start(next: { newStyleId in
            onCompleted?(newStyleId)
            close?()
        }, error: { error in
            switch error {
            case .savedLimit:
                if context.isPremium {
                    showModalText(for: context.window, text: strings().aiStyleModalSavedLimitReachedOther(Int(savedLimit)))
                } else {
                    let limitText = strings().aiStyleModalSavedLimitPremiumOther(Int(savedLimit), Int(savedLimitPremium))
                    showModalText(for: context.window, text: limitText, button: strings().premiumLimitIncrease, callback: { _ in
                        let analyticsContext = getAnalyticsContext()
                        let presentation = analyticsContext.beginPresentation()
                        defer { presentation.end() }
                        FeatureNavigationHooks.shared.showPremiumBoardingObserved(context, context.window, nil, false, nil, analyticsContext: analyticsContext)
                    })
                }
            case .generic:
                showModalText(for: context.window, text: strings().unknownError)
            }
        })

        return .none
    }

    close = { [weak modalController] in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        modalController?.modal?.close()
    }
    getController = { [weak controller] in controller }
    _ = getController

    return modalController
}
