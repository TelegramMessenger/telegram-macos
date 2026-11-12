import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import TelegramMedia
import Postbox
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import InlineStickerLayer
import InputView
import AppAnalytics


public struct StylePreviewInfo: Equatable {
    var title: String
    var description: String
    var emojiFileId: Int64?
    var emojiFile: TelegramMediaFile?
    var authorUsername: String?
}

public func fetchAiStylePreviewInfo(context: any AccountContextProtocol, slug: String, analyticsContext: AnalyticsContext? = nil) -> Signal<StylePreviewInfo?, NoError> {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    let url = context.meUrlPrefix + "addstyle/\(slug)"
    let signal = webpagePreview(account: context.account, urls: [url])
    |> filter { result in
        if case .result = result { return true }
        return false
    }
    |> take(1)
    |> map { result -> StylePreviewInfo? in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        guard case let .result(resolved) = result, let resolved else {
            return nil
        }
        guard case let .Loaded(content) = resolved.webpage.content else {
            return nil
        }
        var info = StylePreviewInfo(
            title: content.title ?? slug,
            description: content.text ?? "",
            emojiFileId: nil,
            emojiFile: nil,
            authorUsername: content.author
        )
        for attr in content.attributes {
            if case let .aiTextStyle(styleAttr) = attr {
                info.emojiFileId = styleAttr.emojiFileId
                break
            }
        }
        return info
    }
    return origin.preservingPresentation(signal)
}

private typealias StyleExample = TelegramAIComposeToneExample


private final class StylePreviewHeaderRowItem : GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let info: StylePreviewInfo
    fileprivate let titleLayout: TextViewLayout
    fileprivate let subtitleLayout: TextViewLayout
    fileprivate let emojiSize: CGFloat = 80
    fileprivate static let topInset: CGFloat = 0
    fileprivate static let emojiTitleSpacing: CGFloat = 10
    fileprivate static let titleSubtitleSpacing: CGFloat = 6
    fileprivate static let bottomInset: CGFloat = 10

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, info: StylePreviewInfo) {
        self.context = context
        self.info = info

        self.titleLayout = TextViewLayout(.initialize(string: info.title, color: theme.colors.text, font: .bold(22)), maximumNumberOfLines: 1)
        self.titleLayout.measure(width: initialSize.width - 40)

        let subtitle = info.description.isEmpty ? strings().aiStylePreviewDefaultDescription : info.description
        self.subtitleLayout = TextViewLayout(.initialize(string: subtitle, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 3, alignment: .center)
        self.subtitleLayout.measure(width: initialSize.width - 40)

        super.init(initialSize, stableId: stableId)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        titleLayout.measure(width: width - 40)
        subtitleLayout.measure(width: width - 40)
        return success
    }

    override var height: CGFloat {
        var h = StylePreviewHeaderRowItem.topInset
        if info.emojiFileId != nil {
            h += emojiSize + StylePreviewHeaderRowItem.emojiTitleSpacing
        }
        h += titleLayout.layoutSize.height + StylePreviewHeaderRowItem.titleSubtitleSpacing
        h += subtitleLayout.layoutSize.height
        h += StylePreviewHeaderRowItem.bottomInset
        return h
    }
    override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }
    override var accessibilityValue: String? {
        return subtitleLayout.attributedString.string
    }
    override var accessibilityIncludesChildren: Bool {
        return false
    }
    override func viewClass() -> AnyClass {
        return StylePreviewHeaderRowView.self
    }
}

private final class StylePreviewHeaderRowView : TableRowView {
    private var emojiView: InlineStickerView?
    private var currentEmojiFileId: Int64?
    private let titleView = TextView()
    private let subtitleView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(titleView)
        addSubview(subtitleView)
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        subtitleView.userInteractionEnabled = false
        subtitleView.isSelectable = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return theme.colors.listBackground
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? StylePreviewHeaderRowItem else { return }

        if let fileId = item.info.emojiFileId {
            if emojiView == nil || currentEmojiFileId != fileId {
                emojiView?.removeFromSuperview()
                let size = NSMakeSize(item.emojiSize, item.emojiSize)
                let emoji = ChatTextCustomEmojiAttribute(fileId: fileId, file: item.info.emojiFile, emoji: "⭐️")
                let view = InlineStickerView(account: item.context.account, inlinePacksContext: item.context.inlinePacksContext, emoji: emoji, size: size, playPolicy: .loop)
                addSubview(view)
                self.emojiView = view
                self.currentEmojiFileId = fileId
            }
        } else {
            emojiView?.removeFromSuperview()
            emojiView = nil
            currentEmojiFileId = nil
        }

        titleView.update(item.titleLayout)
        subtitleView.update(item.subtitleLayout)

        needsLayout = true
    }

    override func layout() {
        super.layout()
        if let emojiView = emojiView {
            emojiView.centerX(y: StylePreviewHeaderRowItem.topInset)
            titleView.centerX(y: emojiView.frame.maxY + StylePreviewHeaderRowItem.emojiTitleSpacing)
        } else {
            titleView.centerX(y: StylePreviewHeaderRowItem.topInset)
        }
        subtitleView.centerX(y: titleView.frame.maxY + StylePreviewHeaderRowItem.titleSubtitleSpacing)
    }
}


private final class BeforeAfterRowItem : GeneralRowItem {
    fileprivate let example: StyleExample
    fileprivate let beforeLayout: TextViewLayout
    fileprivate let afterLayout: TextViewLayout
    fileprivate let beforeLabelLayout: TextViewLayout
    fileprivate let afterLabelLayout: TextViewLayout

    init(_ initialSize: NSSize, stableId: AnyHashable, example: StyleExample) {
        self.example = example
        let contentWidth = initialSize.width - 40 - 24

        self.beforeLayout = TextViewLayout(.initialize(string: example.from.text, color: theme.colors.text, font: .normal(.text)))
        self.beforeLayout.measure(width: contentWidth)

        self.afterLayout = TextViewLayout(.initialize(string: example.to.text, color: theme.colors.text, font: .normal(.text)))
        self.afterLayout.measure(width: contentWidth)

        self.beforeLabelLayout = TextViewLayout(.initialize(string: strings().aiStylePreviewLabelBefore, color: theme.colors.grayText, font: .normal(.small)))
        self.beforeLabelLayout.measure(width: contentWidth)
        self.afterLabelLayout = TextViewLayout(.initialize(string: strings().aiStylePreviewLabelAfter, color: theme.colors.grayText, font: .normal(.small)))
        self.afterLabelLayout.measure(width: contentWidth)

        super.init(initialSize, stableId: stableId, viewType: .singleItem, inset: NSEdgeInsets(left: 20, right: 20))
    }

    override var height: CGFloat {
        let padding: CGFloat = 12
        let interLabel: CGFloat = 6
        let interBlock: CGFloat = 16
        return padding + beforeLabelLayout.layoutSize.height + interLabel + beforeLayout.layoutSize.height + interBlock + .borderSize + interBlock + afterLabelLayout.layoutSize.height + interLabel + afterLayout.layoutSize.height + padding
    }

    override var accessibilityLabel: String? {
        return "\(beforeLabelLayout.attributedString.string): \(beforeLayout.attributedString.string)"
    }

    override var accessibilityValue: String? {
        return "\(afterLabelLayout.attributedString.string): \(afterLayout.attributedString.string)"
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func viewClass() -> AnyClass {
        return BeforeAfterRowView.self
    }
}

private final class BeforeAfterRowView : GeneralContainableRowView {
    private let beforeLabel = TextView()
    private let beforeText = TextView()
    private let separator = View()
    private let afterLabel = TextView()
    private let afterText = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(beforeLabel)
        addSubview(beforeText)
        addSubview(separator)
        addSubview(afterLabel)
        addSubview(afterText)
        beforeLabel.userInteractionEnabled = false
        beforeLabel.isSelectable = false
        beforeText.userInteractionEnabled = false
        beforeText.isSelectable = false
        afterLabel.userInteractionEnabled = false
        afterLabel.isSelectable = false
        afterText.userInteractionEnabled = false
        afterText.isSelectable = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateColors() {
        super.updateColors()
        separator.backgroundColor = theme.colors.border
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? BeforeAfterRowItem else { return }
        beforeLabel.update(item.beforeLabelLayout)
        beforeText.update(item.beforeLayout)
        afterLabel.update(item.afterLabelLayout)
        afterText.update(item.afterLayout)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? BeforeAfterRowItem else { return }
        let innerInset: CGFloat = 12
        var y: CGFloat = innerInset
        beforeLabel.setFrameOrigin(NSMakePoint(innerInset, y))
        y += beforeLabel.frame.height + 6
        beforeText.setFrameOrigin(NSMakePoint(innerInset, y))
        y += beforeText.frame.height + 16
        separator.frame = NSMakeRect(innerInset, y, containerView.frame.width - innerInset * 2, .borderSize)
        y += .borderSize + 16
        afterLabel.setFrameOrigin(NSMakePoint(innerInset, y))
        y += afterLabel.frame.height + 6
        afterText.setFrameOrigin(NSMakePoint(innerInset, y))
        _ = item
    }
}


private final class Arguments {
    let context: any AccountContextProtocol
    let requestAnother: ()->Void
    let openAuthor: (String, String) -> Void
    init(context: any AccountContextProtocol, requestAnother: @escaping()->Void, openAuthor: @escaping (String, String) -> Void) {
        self.context = context
        self.requestAnother = requestAnother
        self.openAuthor = openAuthor
    }
}

private struct State : Equatable {
    var info: StylePreviewInfo?
    var isLoading: Bool = true
    var example: StyleExample?
    var exampleNum: Int32 = 0
    var hasMoreExamples: Bool = true
    var isInstalled: Bool = false
}

private let _id_header = InputDataIdentifier("_id_header")
private let _id_example_header = InputDataIdentifier("_id_example_header")
private let _id_example_body = InputDataIdentifier("_id_example_body")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId: Int32 = 0
    var index: Int32 = 0


    if let info = state.info {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: InputDataEquatable(info), comparable: nil, item: { initialSize, stableId in
            return StylePreviewHeaderRowItem(initialSize, stableId: stableId, context: arguments.context, info: info)
        }))
        index += 1

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        if let example = state.example {
            let canRefresh = state.hasMoreExamples
            let rightText: NSAttributedString?
            if canRefresh {
                rightText = .initialize(string: strings().aiStylePreviewAnotherExample, color: theme.colors.accent, font: .medium(.small))
            } else {
                rightText = nil
            }
            let requestAnother = arguments.requestAnother
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().aiStylePreviewExampleHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem, rightItem: InputDataGeneralTextRightData(isLoading: false, text: rightText, action: canRefresh ? { requestAnother() } : nil))))
            index += 1

            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_example_body, equatable: InputDataEquatable(example), comparable: nil, item: { initialSize, stableId in
                return BeforeAfterRowItem(initialSize, stableId: stableId, example: example)
            }))
            index += 1

            if let author = state.info?.authorUsername, !author.isEmpty {
                let handle = author.hasPrefix("@") ? author : "@\(author)"
                let username = handle.hasPrefix("@") ? String(handle.dropFirst()) : handle
                let markdown = strings().aiStylePreviewAddByAuthor(handle)
                entries.append(.desc(sectionId: sectionId, index: index, text: .markdown(markdown, linkHandler: { _ in
                    arguments.openAuthor(handle, username)
                }), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            } else {
                entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().aiStylePreviewAddNoAuthor), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            }
            index += 1
        }
    } else if state.isLoading {
        entries.append(.loading)
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}


public func AiStylePreviewModalController(context: any AccountContextProtocol, slug: String, info: StylePreviewInfo, analyticsContext: AnalyticsContext? = nil) -> InputDataModalController {

    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    let getAnalyticsContext: () -> AnalyticsContext = {
        Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: origin)
    }
    let actionsDisposable = DisposableSet()

    let examplesNum = context.appConfiguration.getGeneralValue("aicompose_tone_examples_num", orElse: 3)

    var initialState = State()
    initialState.info = info
    initialState.isLoading = false
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        statePromise.set(stateValue.modify(f))
    }

    var close:(()->Void)? = nil

    let fetchExample: (Int32) -> Void = { num in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        if num >= examplesNum {
            updateState { current in
                var current = current
                current.hasMoreExamples = false
                return current
            }
            return
        }
        let signal = context.engine.messages.getAIComposeToneExample(slug: slug, num: num) |> deliverOnMainQueue
        actionsDisposable.add(getAnalyticsContext().preservingPresentation(signal).start(next: { example in
            updateState { current in
                var current = current
                if let example {
                    current.example = example
                    current.exampleNum = num
                    if num + 1 >= examplesNum {
                        current.hasMoreExamples = false
                    }
                } else {
                    current.hasMoreExamples = false
                }
                return current
            }
        }))
    }

    let arguments = Arguments(context: context, requestAnother: {
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        let nextNum = stateValue.with { $0.exampleNum } + 1
        fetchExample(nextNum)
    }, openAuthor: { handle, username in
        let analyticsContext = getAnalyticsContext()
        let presentation = analyticsContext.beginPresentation()
        defer { presentation.end() }
        TranslateUIHooks.shared.followResolvedNameObserved(handle, username, context, analyticsContext: analyticsContext)
    })

    if let fileId = info.emojiFileId {
        let resolve = context.engine.stickers.resolveInlineStickers(fileIds: [fileId]) |> deliverOnMainQueue
        actionsDisposable.add(getAnalyticsContext().preservingPresentation(resolve).start(next: { files in
            guard let file = files[fileId] else { return }
            updateState { current in
                var current = current
                if var info = current.info {
                    info.emojiFile = file
                    current.info = info
                }
                return current
            }
        }))
    }

    fetchExample(0)

    actionsDisposable.add(getAnalyticsContext().preservingPresentation(context.engine.messages.composeAIMessageStyles() |> take(1) |> deliverOnMainQueue).start(next: { cloudStyles in
        let installed = cloudStyles.contains(where: { style in
            if case let .custom(custom) = style.content, custom.slug == slug {
                return true
            }
            return false
        })
        updateState { current in
            var current = current
            current.isInstalled = installed
            return current
        }
    }))

    let signal = getAnalyticsContext().preservingPresentation(statePromise.get() |> deliverOnPrepareQueue) |> map { state in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: " ")
    controller.analyticsContext = origin
    controller.analyticsScreen = .chatAiEditorStylePreview

    controller.onDeinit = {
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().aiStylePreviewAddStyle, accept: {
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        if stateValue.with({ $0.isInstalled }) {
            close?()
        } else {
            showModalText(for: context.window, text: strings().aiStylePreviewOpenLinkOnTelegram)
            close?()
        }
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(360, 0))

    modalController.analyticsContext = origin

    controller.afterTransaction = { [weak modalInteractions] _ in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        guard let modalInteractions else { return }
        let isInstalled = stateValue.with { $0.isInstalled }
        modalInteractions.updateDone({ button in
            button.set(text: isInstalled ? strings().modalOK : strings().aiStylePreviewAddStyle, for: .Normal)
        })
    }

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        modalController?.close()
    })

    close = { [weak modalController] in
        let presentation = getAnalyticsContext().beginPresentation()
        defer { presentation.end() }
        modalController?.modal?.close()
    }

    return modalController
}
