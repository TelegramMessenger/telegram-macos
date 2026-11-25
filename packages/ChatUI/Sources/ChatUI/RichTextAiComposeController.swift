import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import InputView
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import ChatHistoryModel
import AlertsUI
import GeneralRows
import InputDataUI
import InstantPageUI
import AppAnalytics

private final class Arguments {
    let context: any AccountContextProtocol
    let updatePrompt: (Updated_ChatTextInputState) -> Void
    init(context: any AccountContextProtocol, updatePrompt: @escaping (Updated_ChatTextInputState) -> Void) {
        self.context = context
        self.updatePrompt = updatePrompt
    }
}

private struct State: Equatable {
    var prompt: Updated_ChatTextInputState = .init(inputText: .init())
    var isProcessing: Bool = false
    var result: InstantPage?
    /// Bumped each time a fresh result arrives so the preview row re-renders (InstantPage isn't Equatable).
    var resultToken: Int32 = 0

    static func == (lhs: State, rhs: State) -> Bool {
        return lhs.prompt == rhs.prompt
            && lhs.isProcessing == rhs.isProcessing
            && lhs.resultToken == rhs.resultToken
            && (lhs.result == nil) == (rhs.result == nil)
    }
}

private let _id_prompt = InputDataIdentifier("_id_prompt")
private let _id_result = InputDataIdentifier("_id_result")

// MARK: - Read-only rendered preview of the generated InstantPage

private final class AiResultRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate private(set) var richLayout: InstantPageV2Layout?
    fileprivate private(set) var richTheme: InstantPageTheme?
    fileprivate private(set) var richContentHeight: CGFloat = 0
    private let instantPage: InstantPage

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, instantPage: InstantPage, viewType: GeneralViewType) {
        self.context = context
        self.instantPage = instantPage
        super.init(initialSize, stableId: stableId, viewType: viewType)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        let availableWidth = self.blockWidth - viewType.innerInset.left - viewType.innerInset.right
        let webpage = TelegramMediaWebpage(
            webpageId: MediaId(namespace: 0, id: 0),
            content: .Loaded(TelegramMediaWebpageLoadedContent(
                url: "", displayUrl: "", hash: 0, type: nil,
                websiteName: nil, title: nil, text: nil,
                embedUrl: nil, embedType: nil, embedSize: nil, duration: nil,
                author: nil, isMediaLargeByDefault: nil, imageIsVideoCover: false,
                image: nil, file: nil, story: nil, attributes: [],
                instantPage: instantPage
            ))
        )
        let ipTheme = ChatRichTextRowItem.buildInstantPageTheme(for: theme, isIncoming: true, isBubbled: false)
        let layout = layoutInstantPageV2(webpage: webpage, instantPage: instantPage, boundingWidth: max(40, availableWidth), horizontalInset: 0, theme: ipTheme)
        self.richLayout = layout
        self.richTheme = ipTheme
        self.richContentHeight = (layout.items.map { $0.frame.maxY }.max() ?? layout.contentSize.height)
        return result
    }

    override var height: CGFloat {
        return richContentHeight + viewType.innerInset.top + viewType.innerInset.bottom
    }

    override func viewClass() -> AnyClass { return AiResultRowView.self }

    override var accessibilityLabel: String? {
        return strings().richTextAiComposeResult
    }
}

private final class AiResultRowView: GeneralContainableRowView {
    private var richView: InstantPageV2View? = nil

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? AiResultRowItem else { return }
        if let richLayout = item.richLayout, let richTheme = item.richTheme {
            let current: InstantPageV2View
            if let view = self.richView {
                current = view
            } else {
                current = InstantPageV2View(frame: .zero)
                addSubview(current)
                self.richView = current
            }
            current.context = item.context
            current.update(layout: richLayout, theme: richTheme)
        } else if let view = self.richView {
            view.removeFromSuperview()
            self.richView = nil
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? AiResultRowItem else { return }
        if let richView = richView {
            let availableWidth = item.blockWidth - item.viewType.innerInset.left - item.viewType.innerInset.right
            richView.frame = CGRect(origin: CGPoint(x: item.viewType.innerInset.left, y: item.viewType.innerInset.top), size: NSMakeSize(max(40, availableWidth), item.richContentHeight))
        }
    }
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_prompt, equatable: .init(state.prompt), comparable: nil, item: { initialSize, stableId in
        return InputTextDataRowItem(initialSize, stableId: stableId, context: arguments.context, state: state.prompt, viewType: .singleItem, placeholder: nil, inputPlaceholder: strings().richTextAiComposePromptPlaceholder, filter: { $0 }, updateState: arguments.updatePrompt, limit: 1024, hasEmoji: false, fitPlaceholderHeight: true)
    }))
    index += 1

    if let result = state.result {
        entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().richTextAiComposeResult), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_result, equatable: .init(state.resultToken), comparable: nil, item: { initialSize, stableId in
            return AiResultRowItem(initialSize, stableId: stableId, context: arguments.context, instantPage: result, viewType: .singleItem)
        }))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1
    return entries
}

/// "Create with AI": a free-form generation prompt for the rich editor, shown when there's no text
/// selection (editing a selection goes through `TranslateModalController`'s AI editor instead). The
/// prompt is sent as a single-use tone with no text — the server generates a rich message from scratch.
/// After "Generate" the result is previewed in place (rendered via InstantPage V2) and the primary button
/// becomes "Add to Page", which commits it to the editor.
public func RichTextAiComposeController(context: any AccountContextProtocol, analyticsContext: AnalyticsContext? = nil, completion: @escaping (InstantPage) -> Void) -> InputDataModalController {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let getAnalyticsContext: () -> AnalyticsContext = {
        Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: origin)
    }
    let presentation = getAnalyticsContext().beginPresentation()
    defer { presentation.end() }
    let actionsDisposable = DisposableSet()
    let initialState = State()
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        statePromise.set(stateValue.modify(f))
    }

    var close: (() -> Void)? = nil

    let arguments = Arguments(context: context, updatePrompt: { prompt in
        if prompt.textInputState().hasExcludedAnalytics { origin.scope?.exclude() }
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        updateState { var c = $0
            guard !c.isProcessing else { return c }
            // Only editing the actual TEXT invalidates the shown result (it was generated for the old
            // prompt). Moving the cursor / changing the selection updates `prompt` too, but must keep the
            // result so the button stays "Add to Page".
            let textChanged = c.prompt.inputText.string != prompt.inputText.string
            c.prompt = prompt
            if textChanged { c.result = nil }
            return c
        }
    })

    let signal = getAnalyticsContext().preservingPresentation(statePromise.get() |> deliverOnPrepareQueue |> map { state in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    })

    let controller = InputDataController(dataSignal: signal, title: strings().richTextAiComposeTitle, removeAfterDisappear: false, hasDone: false)
    controller.analyticsContext = origin
    controller.analyticsScreen = .chatRichEditorAiCompose
    controller.onDeinit = {
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        actionsDisposable.dispose()
    }

    let generate: () -> Void = {
        let analyticsContext = getAnalyticsContext()
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        let state = stateValue.with { $0 }
        if state.isProcessing { return }

        let prompt = state.prompt.inputText.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }

        updateState { var c = $0; c.isProcessing = true; return c }

        let request = context.engine.messages.composeRichMessageWithAI(instantPage: nil, customPrompt: prompt)
        actionsDisposable.add(analyticsContext.preservingPresentation(request |> deliverOnMainQueue).start(next: { result in
            // Show the result for preview instead of committing immediately; the button becomes "Add to Page".
            updateState { var c = $0; c.isProcessing = false; c.result = result; c.resultToken += 1; return c }
        }, error: { error in
            updateState { var c = $0; c.isProcessing = false; return c }
            let text: String
            switch error {
            case .limitExceeded:
                text = strings().loginFloodWait
            case .textIsEmpty:
                text = strings().richTextAiComposeErrorEmpty
            case .textTooLong:
                text = strings().richTextAiComposeErrorTooLong
            default:
                text = strings().unknownError
            }
            alert(for: context.window, info: text)
        }))
    }

    // Primary action: generate when there's no result yet, otherwise commit the previewed result.
    let performAction: () -> Void = {
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        if let result = stateValue.with({ $0.result }) {
            close?()
            completion(result)
        } else {
            generate()
        }
    }

    controller.validateData = { _ in
        performAction()
        return .none
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().richTextAiComposeGenerate, accept: {
        performAction()
    }, singleButton: true)

    // 0 = idle (Generate), 1 = processing (spinner), 2 = has result (Add to Page).
    actionsDisposable.add(getAnalyticsContext().preservingPresentation(statePromise.get()
        |> map { state -> Int in state.isProcessing ? 1 : (state.result != nil ? 2 : 0) }
        |> distinctUntilChanged
        |> deliverOnMainQueue).start(next: { [weak modalInteractions] phase in
        modalInteractions?.updateDone { button in
            button.subviews.first(where: { $0 is ProgressIndicator })?.removeFromSuperview()
            if phase == 1 {
                button.set(text: "", for: .Normal)
                button.userInteractionEnabled = false
                let indicator = ProgressIndicator(frame: NSMakeRect(0, 0, 20, 20))
                indicator.progressColor = theme.colors.underSelectedColor
                button.addSubview(indicator)
                indicator.center()
            } else {
                button.set(text: phase == 2 ? strings().richTextAiComposeAddToPage : strings().richTextAiComposeGenerate, for: .Normal)
                button.userInteractionEnabled = true
            }
        }
    }))

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(360, 240))
    modalController.analyticsContext = origin

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        modalController?.close()
    })
    controller.centerModalHeader = ModalHeaderData(title: strings().richTextAiComposeTitle)

    close = { [weak modalController] in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        modalController?.close()
    }
    return modalController
}
