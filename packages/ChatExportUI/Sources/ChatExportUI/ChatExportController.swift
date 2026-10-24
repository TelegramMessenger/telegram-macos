import Cocoa
import ShortPeerRow
import TGUIKit
import SwiftSignalKit
import Postbox
import TelegramCore
import Localization
import TelegramTheme
import TelegramContext
import InputDataUI
import AlertsUI
import FilePanels
import MessageTextUtils
import TelegramUtils
import GeneralRows
import ColorPalette

private func exportString(_ key: String) -> String {
    switch key {
    case "MenuTitle": return strings().chatExportMenuTitle
    case "Title": return strings().chatExportTitle
    case "MediaHeader": return strings().chatExportMediaHeader
    case "MediaSection": return strings().chatExportMediaSection
    case "Photos": return strings().chatExportPhotos
    case "VideoFiles": return strings().chatExportVideoFiles
    case "VoiceMessages": return strings().chatExportVoiceMessages
    case "VideoMessages": return strings().chatExportVideoMessages
    case "Stickers": return strings().chatExportStickers
    case "GIFs": return strings().chatExportGifs
    case "Files": return strings().chatExportFiles
    case "SizeLimitHeader": return strings().chatExportSizeLimitHeader
    case "SizeLimit": return strings().chatExportSizeLimit
    case "SizeLimitInfo": return strings().chatExportSizeLimitInfo
    case "SizeLimitInfoUnlimited": return strings().chatExportSizeLimitInfoUnlimited
    case "Unlimited": return strings().chatExportUnlimited
    case "MessagesProgressNoTotal": return strings().chatExportMessagesProgressNoTotal
    case "PathHeader": return strings().chatExportPathHeader
    case "Folder": return strings().chatExportFolder
    case "ChoosePath": return strings().chatExportChoosePath
    case "Export": return strings().chatExportExport
    case "Cancel": return strings().chatExportCancel
    case "DownloadingFiles": return strings().chatExportDownloadingFiles
    case "Downloading": return strings().chatExportDownloading
    case "WaitingMedia": return strings().chatExportWaitingMedia
    case "ExportingTitle": return strings().chatExportExportingTitle
    case "Preparing": return strings().chatExportPreparing
    case "MessagesProgress": return strings().chatExportMessagesProgress
    case "Failed": return strings().chatExportFailed
    case "Completed": return strings().chatExportCompleted
    default: return key
    }
}

private struct MediaTypeDescriptor {
    public let identifier: InputDataIdentifier
    public let title: String
    public let option: ChatExportMediaTypes
}

private var mediaTypeDescriptors: [MediaTypeDescriptor] {
    return [
        MediaTypeDescriptor(identifier: InputDataIdentifier("_id_export_photos"), title: exportString("Photos"), option: .photos),
        MediaTypeDescriptor(identifier: InputDataIdentifier("_id_export_video_files"), title: exportString("VideoFiles"), option: .videoFiles),
        MediaTypeDescriptor(identifier: InputDataIdentifier("_id_export_voice"), title: exportString("VoiceMessages"), option: .voiceMessages),
        MediaTypeDescriptor(identifier: InputDataIdentifier("_id_export_video_messages"), title: exportString("VideoMessages"), option: .videoMessages),
        MediaTypeDescriptor(identifier: InputDataIdentifier("_id_export_stickers"), title: exportString("Stickers"), option: .stickers),
        MediaTypeDescriptor(identifier: InputDataIdentifier("_id_export_gifs"), title: exportString("GIFs"), option: .gifs),
        MediaTypeDescriptor(identifier: InputDataIdentifier("_id_export_files"), title: exportString("Files"), option: .files)
    ]
}

private let unlimitedSizeLimit: Int32 = -1
private let sizeLimitPresets: [Int32] = [10, 50, 100, 500, 1024, 2048, unlimitedSizeLimit]

private func sizeLimitTitle(_ mb: Int32) -> String {
    if mb == unlimitedSizeLimit {
        return exportString("Unlimited")
    }
    if mb >= 1024 && mb % 1024 == 0 {
        return "\(mb / 1024) GB"
    }
    return "\(mb) MB"
}

private func sizeLimitBytes(_ mb: Int32) -> Int64 {
    if mb == unlimitedSizeLimit {
        return Int64.max
    }
    return Int64(mb) * 1024 * 1024
}

private func sizeLimitInfoText(_ mb: Int32) -> String {
    if mb == unlimitedSizeLimit {
        return exportString("SizeLimitInfoUnlimited")
    }
    return exportString("SizeLimitInfo").replacingOccurrences(of: "{size}", with: sizeLimitTitle(mb))
}

private let _id_path = InputDataIdentifier("_id_export_path")
private let _id_size = InputDataIdentifier("_id_export_size")
private let _id_media_section = InputDataIdentifier("_id_export_media_section")
private let _id_chats_section = InputDataIdentifier("_id_export_chats_section")
private let _id_msg_progress = InputDataIdentifier("_id_export_msg_progress")
private let _id_media_progress = InputDataIdentifier("_id_export_media_progress")
private let _id_range_start = InputDataIdentifier("_id_export_range_start")
private let _id_range_end = InputDataIdentifier("_id_export_range_end")

private func rangeDateTitle(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = appAppearance.locale
    formatter.dateStyle = .medium
    formatter.timeStyle = .none
    return formatter.string(from: date)
}

private func rangeStartTitle(_ date: Date?) -> String {
    guard let date = date else {
        return strings().chatExportControllerRangeOldest
    }
    return rangeDateTitle(date)
}

private func rangeEndTitle(_ date: Date?) -> String {
    guard let date = date else {
        return strings().chatExportControllerRangePresent
    }
    return rangeDateTitle(date)
}

// MARK: - Progress helpers

private func chatExportProgressInfo(_ update: ChatExportUpdate?) -> (hasPercent: Bool, percent: Int, processed: Int, line: String) {
    switch update {
    case let .progress(processed, total, _, _):
        if total > 0 {
            // Cap in-progress at 99% — 100% is only shown on actual completion,
            // so a temporarily under-reported total never reads as "done".
            let percent = max(0, min(99, Int((Double(processed) / Double(total)) * 100.0)))
            let line = exportString("MessagesProgress")
                .replacingOccurrences(of: "{done}", with: "\(processed)")
                .replacingOccurrences(of: "{total}", with: "\(total)") + " (\(percent)%)"
            return (true, percent, processed, line)
        } else {
            let line = exportString("MessagesProgressNoTotal").replacingOccurrences(of: "{done}", with: "\(processed)")
            return (false, 0, processed, line)
        }
    case .completed:
        return (true, 100, 0, exportString("Completed"))
    case .failed:
        return (false, 0, 0, exportString("Failed"))
    case nil:
        return (false, 0, 0, exportString("Preparing"))
    }
}

private func chatExportMedia(_ update: ChatExportUpdate?) -> ChatExportMediaProgress? {
    if case let .progress(_, _, _, media) = update {
        return media
    }
    return nil
}

private final class ChatExportProgressRowItem: GeneralRowItem {
    fileprivate let progress: Float
    fileprivate let textLayout: TextViewLayout
    public init(_ initialSize: NSSize, stableId: AnyHashable, progress: Float, text: String, viewType: GeneralViewType) {
        self.progress = progress
        self.textLayout = TextViewLayout(.initialize(string: text, color: theme.colors.text, font: .normal(.text)), maximumNumberOfLines: 1)
        super.init(initialSize, height: 58, stableId: stableId, viewType: viewType)
    }
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        textLayout.measure(width: blockWidth - viewType.innerInset.left - viewType.innerInset.right)
        return result
    }
    public override func viewClass() -> AnyClass {
        return ChatExportProgressRowView.self
    }

    public override var accessibilityLabel: String? {
        return textLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return "\(Int(progress * 100))%"
    }
}

private final class ChatExportProgressRowView: GeneralContainableRowView {
    private let progressControl = LinearProgressControl(progressHeight: 6)
    private let textView = TextView()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(progressControl)
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        progressControl.userInteractionEnabled = false
    }
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? ChatExportProgressRowItem else {
            return
        }
        progressControl.style = ControlStyle(foregroundColor: theme.colors.accent, backgroundColor: theme.colors.grayUI)
        progressControl.cornerRadius = 3
        progressControl.set(progress: CGFloat(max(0.05, min(1, item.progress))), animated: animated, duration: 0.2, timingFunction: .linear)
        textView.update(item.textLayout)
        needsLayout = true
    }
    public override func layout() {
        super.layout()
        guard let item = item as? ChatExportProgressRowItem else {
            return
        }
        let inset = item.viewType.innerInset
        let barWidth = max(0, containerView.frame.width - inset.left - inset.right)
        progressControl.setFrameSize(NSMakeSize(barWidth, 6))
        progressControl.setFrameOrigin(NSMakePoint(inset.left, inset.top + 4))
        textView.setFrameOrigin(NSMakePoint(inset.left, progressControl.frame.maxY + 8))
    }
}

// MARK: - Export session (single run, multicast progress)

public final class ChatExportSession {
    public let context: any AccountContextProtocol
    public let peerTitle: String
    public let downloadsMedia: Bool

    private let statePipe = ValuePipe<ChatExportUpdate>()
    private let lastState = Atomic<ChatExportUpdate?>(value: nil)
    private let disposable = MetaDisposable()
    private let finishedFlag = Atomic<Bool>(value: false)

    public var onFinished: ((URL?) -> Void)?

    public init(context: any AccountContextProtocol, peerId: PeerId, peerTitle: String, settings: ChatExportSettings) {
        self.context = context
        self.peerTitle = peerTitle
        self.downloadsMedia = !settings.mediaTypes.isEmpty
        disposable.set((exportChatToHtml(context: context, peerId: peerId, peerTitle: peerTitle, settings: settings) |> deliverOnMainQueue).start(next: { [weak self] update in
            guard let self = self else {
                return
            }
            _ = self.lastState.swap(update)
            self.statePipe.putNext(update)
            switch update {
            case let .completed(url):
                self.finish(url)
            case .failed:
                self.finish(nil)
            default:
                break
            }
        }))
    }

    public var updates: Signal<ChatExportUpdate, NoError> {
        return statePipe.signal()
    }

    public var current: ChatExportUpdate? {
        return lastState.with { $0 }
    }

    private func finish(_ url: URL?) {
        if finishedFlag.swap(true) {
            return
        }
        disposable.dispose()
        onFinished?(url)
    }

    public func cancel() {
        finish(nil)
    }

    deinit {
        disposable.dispose()
    }
}

// MARK: - Navigation header banner

private final class ChatExportHeaderView: NavigationHeaderView {
    private let container = Control()
    private let textView = TextView()
    private let disposable = MetaDisposable()
    private weak var session: ChatExportSession?
    private var text: String = "" {
        didSet {
            container.setAccessibilityLabel(text)
        }
    }

    public override init(_ header: NavigationHeader) {
        super.init(header)
        addSubview(container)
        container.addSubview(textView)

        textView.userInteractionEnabled = false
        textView.isSelectable = false

        container.set(handler: { [weak self] _ in
            self?.openModal()
        }, for: .Click)

        updateColors()
        ready.set(.single(true))
    }

    private func updateColors() {
        backgroundColor = .clear
        container.backgroundColor = theme.colors.accent
        needsLayout = true
    }

    public override func update(with contextObject: Any) {
        super.update(with: contextObject)
        guard let session = contextObject as? ChatExportSession else {
            return
        }
        self.session = session
        apply(session.current)
        disposable.set((session.updates |> deliverOnMainQueue).start(next: { [weak self] update in
            self?.apply(update)
        }))
    }

    private func apply(_ update: ChatExportUpdate?) {
        let info = chatExportProgressInfo(update)
        if info.hasPercent {
            self.text = exportString("ExportingTitle") + " — \(info.percent)%"
        } else if info.processed > 0 {
            self.text = exportString("ExportingTitle") + " — \(info.processed)"
        } else {
            self.text = exportString("ExportingTitle")
        }
        needsLayout = true
    }

    private func openModal() {
        guard let session = session else {
            return
        }
        showModal(with: chatExportProgressModal(session: session), for: session.context.window)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        updateColors()
    }

    public override func layout() {
        super.layout()
        let hInset: CGFloat = 12
        let topInset: CGFloat = 12
        let contentHeight: CGFloat = 35
        container.frame = NSMakeRect(hInset, topInset, max(0, frame.width - hInset * 2), contentHeight)
        container.layer?.cornerRadius = contentHeight / 2
        container.layer?.masksToBounds = true

        let layout = TextViewLayout(.initialize(string: text, color: NSColor.white, font: .medium(.text)), maximumNumberOfLines: 1)
        layout.measure(width: max(1, container.frame.width - 40))
        textView.update(layout)
        textView.centerY(x: 20)
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Downloading-state modal

private func chatExportProgressEntries(update: ChatExportUpdate?, peerTitle: String, downloadsMedia: Bool) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(peerTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let info = chatExportProgressInfo(update)
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_msg_progress, equatable: InputDataEquatable(update), comparable: nil, item: { initialSize, stableId in
        return ChatExportProgressRowItem(initialSize, stableId: stableId, progress: info.hasPercent ? Float(info.percent) / 100.0 : 0, text: info.line, viewType: .singleItem)
    }))
    index += 1

    if downloadsMedia {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(exportString("DownloadingFiles")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        let media = chatExportMedia(update)
        let mediaProgress = media?.progress ?? 0
        let mediaText = (media?.name).flatMap { $0.isEmpty ? nil : $0 } ?? exportString("WaitingMedia")
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_media_progress, equatable: InputDataEquatable(update), comparable: nil, item: { initialSize, stableId in
            return ChatExportProgressRowItem(initialSize, stableId: stableId, progress: mediaProgress, text: mediaText, viewType: .singleItem)
        }))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

private func chatExportProgressModal(session: ChatExportSession) -> InputDataModalController {
    let statePromise = ValuePromise<ChatExportUpdate?>(session.current, ignoreRepeated: false)
    let disposable = MetaDisposable()

    var close: (() -> Void)?

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { update in
        return InputDataSignalValue(entries: chatExportProgressEntries(update: update, peerTitle: session.peerTitle, downloadsMedia: session.downloadsMedia))
    }

    let controller = InputDataController(dataSignal: signal, title: exportString("ExportingTitle"), hasDone: false)

    controller.onDeinit = {
        disposable.dispose()
    }

    disposable.set((session.updates |> deliverOnMainQueue).start(next: { update in
        statePromise.set(update)
        switch update {
        case .completed, .failed:
            close?()
        default:
            break
        }
    }))

    let modalInteractions = ModalInteractions(acceptTitle: exportString("Cancel"), accept: {
        session.cancel()
        close?()
    }, singleButton: true, customTheme: {
        .init(accent: theme.colors.redUI)
    })

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    close = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}

// MARK: - Start / banner presentation

public func startChatExport(context: any AccountContextProtocol, peerId: PeerId, peerTitle: String, settings: ChatExportSettings) {
    let navigation = context.bindings.rootNavigation()
    let session = ChatExportSession(context: context, peerId: peerId, peerTitle: peerTitle, settings: settings)

    session.onFinished = { [weak navigation] url in
        navigation?.additionalHeader?.hide(true)
        if let url = url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            showModalText(for: context.window, text: exportString("Completed"))
        }
    }

    navigation.set(additionalHeader: AdditionalNavigationHeader(47, initializer: { header, contextObject, view -> (NavigationHeaderView, CGFloat) in
        let newView = view as? ChatExportHeaderView ?? ChatExportHeaderView(header)
        newView.update(with: contextObject)
        return (newView, 47)
    }))
    navigation.additionalHeader?.show(true, contextObject: session)

    showModal(with: chatExportProgressModal(session: session), for: context.window)
}

// MARK: - Settings modal

private final class Arguments {
    public let context: any AccountContextProtocol
    public let toggle: (ChatExportMediaTypes) -> Void
    public let toggleMediaReveal: () -> Void
    public let toggleAllMedia: () -> Void
    public let selectFolder: () -> Void
    public let selectSize: (Int32) -> Void
    public let selectRangeStart: (Date?) -> Void
    public let selectRangeEnd: (Date?) -> Void
    public let chooseRangeStart: () -> Void
    public let chooseRangeEnd: () -> Void
    public init(context: any AccountContextProtocol, toggle: @escaping (ChatExportMediaTypes) -> Void, toggleMediaReveal: @escaping () -> Void, toggleAllMedia: @escaping () -> Void, selectFolder: @escaping () -> Void, selectSize: @escaping (Int32) -> Void, selectRangeStart: @escaping (Date?) -> Void, selectRangeEnd: @escaping (Date?) -> Void, chooseRangeStart: @escaping () -> Void, chooseRangeEnd: @escaping () -> Void) {
        self.context = context
        self.toggle = toggle
        self.toggleMediaReveal = toggleMediaReveal
        self.toggleAllMedia = toggleAllMedia
        self.selectFolder = selectFolder
        self.selectSize = selectSize
        self.selectRangeStart = selectRangeStart
        self.selectRangeEnd = selectRangeEnd
        self.chooseRangeStart = chooseRangeStart
        self.chooseRangeEnd = chooseRangeEnd
    }
}

private struct State: Equatable {
    public var mediaTypes: ChatExportMediaTypes = .all
    public var mediaRevealed: Bool = false
    public var sizeLimitMB: Int32 = 100
    public var outputPath: String?
    public var rangeStart: Date?
    public var rangeEnd: Date?
}

private func generateCollapsibleAfter(selected: Int, total: Int, revealed: Bool) -> CGImage {
    let layout = TextNode.layoutText(.initialize(string: "\(selected)/\(total)", color: theme.colors.grayText, font: .normal(.text)), nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, .greatestFiniteMagnitude), nil, false, .center)
    let image = NSImage(named: revealed ? "Icon_Small_Chevron_Up" : "Icon_Small_Chevron_Down")!.precomposed(theme.colors.grayIcon, flipVertical: true)
    return generateImage(NSMakeSize(layout.0.size.width + 6 + image.backingSize.width, max(layout.0.size.height, image.backingSize.height)), contextGenerator: { size, ctx in
        ctx.clear(size.bounds)
        var rect = size.bounds.focus(layout.0.size)
        rect.origin.x = 0
        layout.1.draw(rect, in: ctx, backingScaleFactor: 2, backgroundColor: .clear)
        var imageRect = size.bounds.focus(image.backingSize)
        imageRect.origin.x = rect.maxX + 6
        ctx.draw(image, in: imageRect)
    })!
}

private struct CollapsibleChild {
    public let identifier: InputDataIdentifier
    public let title: String
    public let isOn: Bool
    public let toggle: () -> Void
}

private func collapsibleViewType(isFirst: Bool, isLast: Bool) -> GeneralViewType {
    if isFirst && isLast { return .singleItem }
    if isFirst { return .firstItem }
    if isLast { return .lastItem }
    return .innerItem
}

private func appendCollapsibleSection(_ entries: inout [InputDataEntry], sectionId: inout Int32, index: inout Int32, identifier: InputDataIdentifier, title: String, children: [CollapsibleChild], revealed: Bool, firstInSection: Bool = true, lastInSection: Bool = true, toggleReveal: @escaping () -> Void, toggleAll: @escaping () -> Void) {
    let selected = children.filter { $0.isOn }.count
    let total = children.count
    let anySelected = selected > 0
    let after = generateCollapsibleAfter(selected: selected, total: total, revealed: revealed)
    let parentViewType = collapsibleViewType(isFirst: firstInSection, isLast: lastInSection && !revealed)
    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: identifier, equatable: InputDataEquatable("\(revealed)_\(selected)_\(total)_\(firstInSection)_\(lastInSection)"), comparable: nil, item: { initialSize, stableId in
        return GeneralInteractedRowItem(initialSize, stableId: stableId, name: title, type: .switchable(anySelected), viewType: parentViewType, action: {
            toggleReveal()
        }, switchAction: {
            toggleAll()
        }, afterNameImage: after)
    }))
    index += 1

    if revealed {
        for (i, child) in children.enumerated() {
            let isLastChild = i == children.count - 1
            let viewType = collapsibleViewType(isFirst: false, isLast: lastInSection && isLastChild)
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: child.identifier, data: .init(name: child.title, color: theme.colors.text, type: .switchable(child.isOn), viewType: viewType, action: {
                child.toggle()
            })))
            index += 1
        }
    }
}

private func appendMediaSection(_ entries: inout [InputDataEntry], sectionId: inout Int32, index: inout Int32, mediaTypes: ChatExportMediaTypes, revealed: Bool, firstInSection: Bool = true, lastInSection: Bool = true, toggleReveal: @escaping () -> Void, toggleAll: @escaping () -> Void, toggle: @escaping (ChatExportMediaTypes) -> Void) {
    let children = mediaTypeDescriptors.map { descriptor in
        CollapsibleChild(identifier: descriptor.identifier, title: descriptor.title, isOn: mediaTypes.contains(descriptor.option), toggle: { toggle(descriptor.option) })
    }
    appendCollapsibleSection(&entries, sectionId: &sectionId, index: &index, identifier: _id_media_section, title: exportString("MediaSection"), children: children, revealed: revealed, firstInSection: firstInSection, lastInSection: lastInSection, toggleReveal: toggleReveal, toggleAll: toggleAll)
}

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    appendMediaSection(&entries, sectionId: &sectionId, index: &index, mediaTypes: state.mediaTypes, revealed: state.mediaRevealed, toggleReveal: arguments.toggleMediaReveal, toggleAll: arguments.toggleAllMedia, toggle: arguments.toggle)

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(exportString("SizeLimitHeader")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let sizeItems: [ContextMenuItem] = sizeLimitPresets.map { size in
        return ContextMenuItem(sizeLimitTitle(size), handler: {
            arguments.selectSize(size)
        }, state: size == state.sizeLimitMB ? .on : nil)
    }
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_size, data: .init(name: exportString("SizeLimit"), color: theme.colors.text, type: .contextSelector(sizeLimitTitle(state.sizeLimitMB), sizeItems), viewType: .singleItem)))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(sizeLimitInfoText(state.sizeLimitMB)), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().chatExportControllerDateRange), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let rangeStartItems: [ContextMenuItem] = [
        ContextMenuItem(rangeStartTitle(nil), handler: {
            arguments.selectRangeStart(nil)
        }, state: state.rangeStart == nil ? .on : nil),
        ContextMenuItem(strings().chatExportControllerChooseDate, handler: {
            arguments.chooseRangeStart()
        })
    ]
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_range_start, data: .init(name: strings().chatExportControllerRangeFrom, color: theme.colors.text, type: .contextSelector(rangeStartTitle(state.rangeStart), rangeStartItems), viewType: .firstItem)))
    index += 1

    let rangeEndItems: [ContextMenuItem] = [
        ContextMenuItem(rangeEndTitle(nil), handler: {
            arguments.selectRangeEnd(nil)
        }, state: state.rangeEnd == nil ? .on : nil),
        ContextMenuItem(strings().chatExportControllerChooseDate, handler: {
            arguments.chooseRangeEnd()
        })
    ]
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_range_end, data: .init(name: strings().chatExportControllerRangeTo, color: theme.colors.text, type: .contextSelector(rangeEndTitle(state.rangeEnd), rangeEndItems), viewType: .lastItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(exportString("PathHeader")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let pathDisplay: String
    if let path = state.outputPath, !path.isEmpty {
        pathDisplay = path.nsstring.lastPathComponent
    } else {
        pathDisplay = exportString("ChoosePath")
    }
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_path, data: .init(name: exportString("Folder"), color: theme.colors.text, type: .context(pathDisplay), viewType: .singleItem, action: {
        arguments.selectFolder()
    })))
    index += 1

    if let path = state.outputPath {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(path), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

private func showRangeCalendar(context: any AccountContextProtocol, controller: InputDataController?, identifier: InputDataIdentifier, current: Date?, select: @escaping (Date) -> Void) {
    guard let rowView = controller?.tableView.item(stableId: InputDataEntryId.general(identifier))?.view as? GeneralContainableRowView else {
        return
    }
    guard let calendar = FeatureNavigationHooks.shared.makeCalendarController(context.window, current ?? Date(), 2013, false, select) else {
        return
    }
    let anchor = rowView.containerView
    showPopover(for: anchor, with: calendar, edge: .maxY, inset: NSMakePoint(anchor.frame.width - calendar.frame.width, -anchor.frame.height), static: true)
}

public func ChatExportController(context: any AccountContextProtocol, peerId: PeerId, peerTitle: String) -> InputDataModalController {
    let actionsDisposable = DisposableSet()

    let initialState = State(outputPath: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var closeImpl: (() -> Void)?
    var getController: (() -> InputDataController?)?

    let selectRangeStart: (Date?) -> Void = { date in
        updateState { current in
            var current = current
            current.rangeStart = date.map { Calendar.current.startOfDay(for: $0) }
            if let start = current.rangeStart, let end = current.rangeEnd, end < start {
                current.rangeEnd = start
            }
            return current
        }
    }
    let selectRangeEnd: (Date?) -> Void = { date in
        updateState { current in
            var current = current
            current.rangeEnd = date.map { Calendar.current.startOfDay(for: $0) }
            if let start = current.rangeStart, let end = current.rangeEnd, end < start {
                current.rangeStart = end
            }
            return current
        }
    }

    let arguments = Arguments(context: context, toggle: { option in
        updateState { current in
            var current = current
            if current.mediaTypes.contains(option) {
                current.mediaTypes.remove(option)
            } else {
                current.mediaTypes.insert(option)
            }
            return current
        }
    }, toggleMediaReveal: {
        updateState { current in
            var current = current
            current.mediaRevealed = !current.mediaRevealed
            return current
        }
    }, toggleAllMedia: {
        updateState { current in
            var current = current
            current.mediaTypes = current.mediaTypes.isEmpty ? .all : []
            return current
        }
    }, selectFolder: {
        selectFolder(for: context.window, completion: { path in
            updateState { current in
                var current = current
                current.outputPath = path
                return current
            }
        })
    }, selectSize: { size in
        updateState { current in
            var current = current
            current.sizeLimitMB = size
            return current
        }
    }, selectRangeStart: selectRangeStart, selectRangeEnd: selectRangeEnd, chooseRangeStart: {
        showRangeCalendar(context: context, controller: getController?(), identifier: _id_range_start, current: stateValue.with { $0.rangeStart }, select: { date in
            selectRangeStart(date)
        })
    }, chooseRangeEnd: {
        showRangeCalendar(context: context, controller: getController?(), identifier: _id_range_end, current: stateValue.with { $0.rangeEnd }, select: { date in
            selectRangeEnd(date)
        })
    })

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: exportString("Title"), hasDone: false)

    getController = { [weak controller] in
        return controller
    }

    controller.validateData = { _ in
        let state = stateValue.with { $0 }
        guard let path = state.outputPath, !path.isEmpty else {
            return .fail(.fields([_id_path: .shake]))
        }
        let fromTimestamp = state.rangeStart.map { Int32($0.timeIntervalSince1970) }
        let untilTimestamp = state.rangeEnd.flatMap { Calendar.current.date(byAdding: .day, value: 1, to: $0) }.map { Int32($0.timeIntervalSince1970) }
        let settings = ChatExportSettings(mediaTypes: state.mediaTypes, sizeLimit: sizeLimitBytes(state.sizeLimitMB), path: path, fromTimestamp: fromTimestamp, untilTimestamp: untilTimestamp)
        startChatExport(context: context, peerId: peerId, peerTitle: peerTitle, settings: settings)
        closeImpl?()
        return .none
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: exportString("Export"), accept: { [weak controller] in
        controller?.validateInputValues()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    closeImpl = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}

public func showChatExportModal(context: any AccountContextProtocol, peer: Peer) {
    showModal(with: ChatExportController(context: context, peerId: peer.id, peerTitle: peer.displayTitle), for: context.window)
}

public func chatExportMenuTitle() -> String {
    return exportString("MenuTitle")
}

// MARK: - Full account export ("Export Telegram Data")

private func fullExportString(_ key: String) -> String {
    switch key {
    case "Title": return strings().exportDataTitle
    case "MenuRow": return strings().exportDataMenuRow
    case "MenuRowInfo": return strings().exportDataMenuRowInfo
    case "AccountHeader": return strings().exportDataAccountHeader
    case "PersonalInfo": return strings().exportDataPersonalInfo
    case "PersonalInfoAbout": return strings().exportDataPersonalInfoAbout
    case "Contacts": return strings().exportDataContacts
    case "ContactsAbout": return strings().exportDataContactsAbout
    case "Stories": return strings().exportDataStories
    case "StoriesAbout": return strings().exportDataStoriesAbout
    case "ChatsHeader": return strings().exportDataChatsHeader
    case "ChatsSection": return strings().exportDataChatsSection
    case "PersonalChats": return strings().exportDataPersonalChats
    case "BotChats": return strings().exportDataBotChats
    case "PrivateGroups": return strings().exportDataPrivateGroups
    case "PrivateChannels": return strings().exportDataPrivateChannels
    case "PublicGroups": return strings().exportDataPublicGroups
    case "PublicChannels": return strings().exportDataPublicChannels
    case "OtherHeader": return strings().exportDataOtherHeader
    case "Sessions": return strings().exportDataSessions
    case "SessionsAbout": return strings().exportDataSessionsAbout
    case "Other": return strings().exportDataOther
    case "OtherAbout": return strings().exportDataOtherAbout
    case "FormatHeader": return strings().exportDataFormatHeader
    case "Format": return strings().exportDataFormat
    case "FormatHtml": return strings().exportDataFormatHtml
    case "FormatJson": return strings().exportDataFormatJson
    case "FormatBoth": return strings().exportDataFormatBoth
    case "ExportingTitle": return strings().exportDataExportingTitle
    case "OverallHeader": return strings().exportDataOverallHeader
    case "ChatsProgress": return strings().exportDataChatsProgress
    case "Preparing": return strings().exportDataPreparing
    case "DelayText": return strings().exportDataDelayText
    case "DelayLessThanHour": return strings().exportDataDelayLessThanHour
    case "DelayHours": return strings().exportDataDelayHours
    case "TakeoutFailed": return strings().exportDataTakeoutFailed
    default: return exportString(key)
    }
}

public func fullExportRowTitle() -> String {
    return fullExportString("MenuRow")
}

public func fullExportRowInfo() -> String {
    return fullExportString("MenuRowInfo")
}

private struct FullSectionDescriptor {
    public let identifier: InputDataIdentifier
    public let title: String
    public let section: FullExportSections
}

private var fullChatDescriptors: [FullSectionDescriptor] {
    return [
        FullSectionDescriptor(identifier: InputDataIdentifier("_id_full_personal_chats"), title: fullExportString("PersonalChats"), section: .personalChats),
        FullSectionDescriptor(identifier: InputDataIdentifier("_id_full_bot_chats"), title: fullExportString("BotChats"), section: .botChats),
        FullSectionDescriptor(identifier: InputDataIdentifier("_id_full_private_groups"), title: fullExportString("PrivateGroups"), section: .privateGroups),
        FullSectionDescriptor(identifier: InputDataIdentifier("_id_full_private_channels"), title: fullExportString("PrivateChannels"), section: .privateChannels),
        FullSectionDescriptor(identifier: InputDataIdentifier("_id_full_public_groups"), title: fullExportString("PublicGroups"), section: .publicGroups),
        FullSectionDescriptor(identifier: InputDataIdentifier("_id_full_public_channels"), title: fullExportString("PublicChannels"), section: .publicChannels)
    ]
}

private var fullAccountDescriptors: [FullSectionDescriptor] {
    return [
        FullSectionDescriptor(identifier: InputDataIdentifier("_id_full_personal"), title: fullExportString("PersonalInfo"), section: .personalInfo),
        FullSectionDescriptor(identifier: InputDataIdentifier("_id_full_contacts"), title: fullExportString("Contacts"), section: .contacts),
        FullSectionDescriptor(identifier: InputDataIdentifier("_id_full_stories"), title: fullExportString("Stories"), section: .stories)
    ]
}

private var fullOtherDescriptors: [FullSectionDescriptor] {
    return [
        FullSectionDescriptor(identifier: InputDataIdentifier("_id_full_sessions"), title: fullExportString("Sessions"), section: .sessions),
        FullSectionDescriptor(identifier: InputDataIdentifier("_id_full_other"), title: fullExportString("Other"), section: .otherData)
    ]
}

private let _id_full_format = InputDataIdentifier("_id_full_format")
private let _id_full_overall = InputDataIdentifier("_id_full_overall")
private let _id_full_peer = InputDataIdentifier("_id_full_peer")
private let _id_full_chat_progress = InputDataIdentifier("_id_full_chat_progress")
private let _id_full_media_progress = InputDataIdentifier("_id_full_media_progress")

// MARK: - Progress helpers

private func fullExportInfo(_ update: FullExportUpdate?) -> (overallPercent: Int, overallLine: String, chatLine: String, chatPercent: Int, mediaText: String, mediaProgress: Float) {
    switch update {
    case let .progress(p):
        let overallPercent: Int
        let overallLine: String
        if p.chatCount > 0 {
            overallPercent = max(0, min(100, Int((Double(p.chatIndex) / Double(p.chatCount)) * 100.0)))
            overallLine = fullExportString("ChatsProgress")
                .replacingOccurrences(of: "{done}", with: "\(p.chatIndex)")
                .replacingOccurrences(of: "{total}", with: "\(p.chatCount)") + " (\(overallPercent)%)"
        } else {
            overallPercent = 0
            overallLine = p.stage
        }
        let chatPercent = p.total > 0 ? max(0, min(100, Int((Double(p.processed) / Double(p.total)) * 100.0))) : 0
        var chatLine = p.currentTitle
        if p.total > 0 {
            chatLine += " — \(p.processed)/\(p.total)"
        } else if p.processed > 0 {
            chatLine += " — \(p.processed)"
        }
        let mediaText = (p.media?.name).flatMap { $0.isEmpty ? nil : $0 } ?? exportString("WaitingMedia")
        return (overallPercent, overallLine, chatLine, chatPercent, mediaText, p.media?.progress ?? 0)
    case let .completed(_, failedChats):
        return (100, exportString(failedChats.isEmpty ? "Completed" : "Failed"), "", 100, exportString("WaitingMedia"), 0)
    case .failed:
        return (0, exportString("Failed"), "", 0, exportString("WaitingMedia"), 0)
    case nil:
        return (0, fullExportString("Preparing"), "", 0, exportString("WaitingMedia"), 0)
    }
}

// MARK: - Session (single run, multicast progress)

public final class FullExportSession {
    public let context: any AccountContextProtocol
    public let downloadsMedia: Bool

    private let statePipe = ValuePipe<FullExportUpdate>()
    private let lastState = Atomic<FullExportUpdate?>(value: nil)
    private let disposable = MetaDisposable()
    private let finishedFlag = Atomic<Bool>(value: false)

    public var onFinished: ((URL?) -> Void)?

    public init(context: any AccountContextProtocol, settings: FullExportSettings) {
        self.context = context
        self.downloadsMedia = !settings.mediaTypes.isEmpty
        disposable.set((exportAllChatsToHtml(context: context, settings: settings) |> deliverOnMainQueue).start(next: { [weak self] update in
            guard let self = self else {
                return
            }
            _ = self.lastState.swap(update)
            self.statePipe.putNext(update)
            switch update {
            case let .completed(url, failedChats):
                self.finish(failedChats.isEmpty ? url : nil)
            case .failed:
                self.finish(nil)
            default:
                break
            }
        }))
    }

    public var updates: Signal<FullExportUpdate, NoError> {
        return statePipe.signal()
    }

    public var current: FullExportUpdate? {
        return lastState.with { $0 }
    }

    private func finish(_ url: URL?) {
        if finishedFlag.swap(true) {
            return
        }
        disposable.dispose()
        onFinished?(url)
    }

    public func cancel() {
        finish(nil)
    }

    deinit {
        disposable.dispose()
    }
}

// MARK: - Navigation header banner

private final class FullExportHeaderView: NavigationHeaderView {
    private let container = Control()
    private let textView = TextView()
    private let disposable = MetaDisposable()
    private weak var session: FullExportSession?
    private var text: String = "" {
        didSet {
            container.setAccessibilityLabel(text)
        }
    }

    public override init(_ header: NavigationHeader) {
        super.init(header)
        addSubview(container)
        container.addSubview(textView)

        textView.userInteractionEnabled = false
        textView.isSelectable = false

        container.set(handler: { [weak self] _ in
            self?.openModal()
        }, for: .Click)

        updateColors()
        ready.set(.single(true))
    }

    private func updateColors() {
        backgroundColor = .clear
        container.backgroundColor = theme.colors.accent
        needsLayout = true
    }

    public override func update(with contextObject: Any) {
        super.update(with: contextObject)
        guard let session = contextObject as? FullExportSession else {
            return
        }
        self.session = session
        apply(session.current)
        disposable.set((session.updates |> deliverOnMainQueue).start(next: { [weak self] update in
            self?.apply(update)
        }))
    }

    private func apply(_ update: FullExportUpdate?) {
        if case let .progress(p)? = update, p.chatCount > 0 {
            self.text = fullExportString("ExportingTitle") + " — \(p.chatIndex)/\(p.chatCount)"
        } else if case let .progress(p)? = update {
            self.text = fullExportString("ExportingTitle") + " — " + p.stage
        } else if case let .completed(_, failedChats)? = update {
            self.text = exportString(failedChats.isEmpty ? "Completed" : "Failed")
        } else if case .failed? = update {
            self.text = exportString("Failed")
        } else {
            self.text = fullExportString("ExportingTitle")
        }
        needsLayout = true
    }

    private func openModal() {
        guard let session = session else {
            return
        }
        showModal(with: fullExportProgressModal(session: session), for: session.context.window)
    }

    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        updateColors()
    }

    public override func layout() {
        super.layout()
        let hInset: CGFloat = 12
        let topInset: CGFloat = 12
        let contentHeight: CGFloat = 35
        container.frame = NSMakeRect(hInset, topInset, max(0, frame.width - hInset * 2), contentHeight)
        container.layer?.cornerRadius = contentHeight / 2
        container.layer?.masksToBounds = true

        let layout = TextViewLayout(.initialize(string: text, color: NSColor.white, font: .medium(.text)), maximumNumberOfLines: 1)
        layout.measure(width: max(1, container.frame.width - 40))
        textView.update(layout)
        textView.centerY(x: 20)
    }

    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Downloading-state modal

private func fullExportProgressEntries(update: FullExportUpdate?, context: any AccountContextProtocol, downloadsMedia: Bool) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    let info = fullExportInfo(update)

    var currentPeer: Peer?
    var failedChats: [FullExportChatFailure] = []
    var resultURL: URL?
    var failureReason: String?
    var chatStatus = ""
    var messageLine = exportString("WaitingMedia")
    var messagePercent = 0
    var prepareLine = fullExportString("Preparing")
    switch update {
    case let .progress(p)?:
        failedChats = p.failedChats
        currentPeer = p.currentPeer?.peer
        if !p.stage.isEmpty {
            prepareLine = p.stage
        }
        if p.chatCount > 0 {
            chatStatus = "\(p.chatIndex) / \(p.chatCount)"
        }
        if p.total > 0 {
            messagePercent = max(0, min(100, Int((Double(p.processed) / Double(p.total)) * 100.0)))
            messageLine = exportString("MessagesProgress")
                .replacingOccurrences(of: "{done}", with: "\(p.processed)")
                .replacingOccurrences(of: "{total}", with: "\(p.total)")
        } else if p.processed > 0 {
            messageLine = exportString("MessagesProgressNoTotal").replacingOccurrences(of: "{done}", with: "\(p.processed)")
        }
    case let .completed(url, failures)?:
        resultURL = url
        failedChats = failures
    case let .failed(reason)?:
        failureReason = reason
    case nil:
        break
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(fullExportString("OverallHeader")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    if let failureReason = failureReason {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(failureReason), data: .init(color: theme.colors.redUI, viewType: .textBottomItem)))
        index += 1
    } else if let resultURL = resultURL {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: InputDataIdentifier("_id_full_result"), data: .init(name: strings().contextShowInFinder, color: theme.colors.accent, type: .next, viewType: .singleItem, action: {
            NSWorkspace.shared.activateFileViewerSelecting([resultURL])
        })))
        index += 1
    } else if let currentPeer = currentPeer {
        let peerKey = "\(currentPeer.id.toInt64())_\(chatStatus)"
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_full_peer, equatable: InputDataEquatable(peerKey), comparable: nil, item: { initialSize, stableId in
            return ShortPeerRowItem(initialSize, peer: currentPeer, account: context.account, context: context, stableId: stableId, height: 46, photoSize: NSMakeSize(32, 32), status: chatStatus, inset: NSEdgeInsets(left: 20, right: 20), viewType: .singleItem)
        }))
        index += 1
    } else {
        var prepPercent = info.overallPercent
        var prepText = prepareLine
        if case let .progress(p)? = update, p.total > 0 {
            prepPercent = max(0, min(100, Int((Double(p.processed) / Double(p.total)) * 100.0)))
            prepText = "\(prepareLine) — \(p.processed) of \(p.total)"
        }
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_full_overall, equatable: InputDataEquatable(update), comparable: nil, item: { initialSize, stableId in
            return ChatExportProgressRowItem(initialSize, stableId: stableId, progress: Float(prepPercent) / 100.0, text: prepText, viewType: .singleItem)
        }))
        index += 1
    }

    if currentPeer != nil {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(exportString(downloadsMedia ? "DownloadingFiles" : "Downloading")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_full_chat_progress, equatable: InputDataEquatable(update), comparable: nil, item: { initialSize, stableId in
            return ChatExportProgressRowItem(initialSize, stableId: stableId, progress: Float(messagePercent) / 100.0, text: messageLine, viewType: downloadsMedia ? .firstItem : .singleItem)
        }))
        index += 1

        if downloadsMedia {
            entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_full_media_progress, equatable: InputDataEquatable(update), comparable: nil, item: { initialSize, stableId in
                return ChatExportProgressRowItem(initialSize, stableId: stableId, progress: info.mediaProgress, text: info.mediaText, viewType: .lastItem)
            }))
            index += 1
        }
    }

    for failure in failedChats {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        let identifier = InputDataIdentifier("_id_full_failed_\(failure.peer.peer.id.toInt64())")
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: identifier, equatable: InputDataEquatable(failure), comparable: nil, item: { initialSize, stableId in
            return ShortPeerRowItem(initialSize, peer: failure.peer.peer, account: context.account, context: context, stableId: stableId, height: 46, photoSize: NSMakeSize(32, 32), statusStyle: ControlStyle(font: .normal(.text), foregroundColor: theme.colors.redUI, highlightColor: .white), status: exportString("Failed"), inset: NSEdgeInsets(left: 20, right: 20), viewType: .singleItem)
        }))
        index += 1
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(failure.reason), data: .init(color: theme.colors.redUI, viewType: .textBottomItem)))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

private func fullExportProgressModal(session: FullExportSession) -> InputDataModalController {
    let statePromise = ValuePromise<FullExportUpdate?>(session.current, ignoreRepeated: false)
    let disposable = MetaDisposable()

    var close: (() -> Void)?

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { update in
        return InputDataSignalValue(entries: fullExportProgressEntries(update: update, context: session.context, downloadsMedia: session.downloadsMedia))
    }

    let controller = InputDataController(dataSignal: signal, title: fullExportString("ExportingTitle"), hasDone: false)

    controller.onDeinit = {
        disposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: exportString("Cancel"), accept: {
        switch session.current {
        case .completed?, .failed?:
            session.context.bindings.rootNavigation().additionalHeader?.hide(true)
        default:
            session.cancel()
        }
        close?()
    }, singleButton: true, customTheme: {
        switch session.current {
        case .completed?, .failed?:
            return .init()
        default:
            return .init(accent: theme.colors.redUI)
        }
    })

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    close = { [weak modalController] in
        modalController?.close()
    }

    disposable.set((Signal<FullExportUpdate?, NoError>.single(session.current)
        |> then(session.updates |> map { Optional($0) })
        |> deliverOnMainQueue).start(next: { update in
            statePromise.set(update)
            switch update {
            case let .completed(_, failedChats)?:
                if failedChats.isEmpty {
                    close?()
                    return
                }
            case .failed?:
                break
            default:
                return
            }
            modalInteractions.acceptTitle = strings().modalOK
            modalInteractions.updateDone { button in
                button.set(text: strings().modalOK, for: .Normal)
                button.set(color: theme.colors.accent, for: .Normal)
            }
        }))

    return modalController
}

// MARK: - Start / banner presentation

public func beginFullExport(context: any AccountContextProtocol, settings: FullExportSettings, closeSettings: @escaping () -> Void) {
    let signal = requestTakeoutSession(context: context, settings: settings) |> deliverOnMainQueue
    _ = showModalProgress(signal: signal, for: context.window).start(next: { result in
        closeSettings()
        switch result {
        case let .ready(takeoutId):
            startFullExport(context: context, settings: settings, takeoutId: takeoutId)
        case let .delay(seconds):
            showTakeoutDelayAlert(context: context, seconds: seconds)
        case .failed:
            startFullExport(context: context, settings: settings, takeoutId: nil)
        }
    })
}

private func showTakeoutDelayAlert(context: any AccountContextProtocol, seconds: Int32) {
    let clamped = max(1, Int(seconds))
    let hours = clamped / 3600
    let hoursText = hours <= 0 ? fullExportString("DelayLessThanHour") : fullExportString("DelayHours").replacingOccurrences(of: "{count}", with: "\(hours)")
    let formatter = DateFormatter()
    formatter.dateStyle = .long
    formatter.timeStyle = .short
    let dateText = formatter.string(from: Date().addingTimeInterval(TimeInterval(clamped)))
    let text = fullExportString("DelayText")
        .replacingOccurrences(of: "{hours}", with: hoursText)
        .replacingOccurrences(of: "{date}", with: dateText)
    alert(for: context.window, header: appName, info: text)
}

public func startFullExport(context: any AccountContextProtocol, settings: FullExportSettings, takeoutId: Int64?) {
    let navigation = context.bindings.rootNavigation()
    let session = FullExportSession(context: context, settings: settings)

    session.onFinished = { [weak navigation, weak session] url in
        if takeoutId != nil {
            finishTakeoutSession(context: context, success: url != nil)
        }
        if case let .completed(_, failedChats)? = session?.current, !failedChats.isEmpty {
            return
        }
        if case .failed? = session?.current {
            return
        }
        navigation?.additionalHeader?.hide(true)
        if let url = url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
            showModalText(for: context.window, text: exportString("Completed"))
        }
    }

    navigation.set(additionalHeader: AdditionalNavigationHeader(47, initializer: { header, contextObject, view -> (NavigationHeaderView, CGFloat) in
        let newView = view as? FullExportHeaderView ?? FullExportHeaderView(header)
        newView.update(with: contextObject)
        return (newView, 47)
    }))
    navigation.additionalHeader?.show(true, contextObject: session)

    showModal(with: fullExportProgressModal(session: session), for: context.window)
}

// MARK: - Settings modal

private final class FullArguments {
    public let context: any AccountContextProtocol
    public let toggleSection: (FullExportSections) -> Void
    public let toggleMedia: (ChatExportMediaTypes) -> Void
    public let toggleMediaReveal: () -> Void
    public let toggleAllMedia: () -> Void
    public let toggleChatsReveal: () -> Void
    public let toggleAllChats: () -> Void
    public let selectFolder: () -> Void
    public let selectSize: (Int32) -> Void
    public let selectFormat: (ExportFormat) -> Void
    public init(context: any AccountContextProtocol, toggleSection: @escaping (FullExportSections) -> Void, toggleMedia: @escaping (ChatExportMediaTypes) -> Void, toggleMediaReveal: @escaping () -> Void, toggleAllMedia: @escaping () -> Void, toggleChatsReveal: @escaping () -> Void, toggleAllChats: @escaping () -> Void, selectFolder: @escaping () -> Void, selectSize: @escaping (Int32) -> Void, selectFormat: @escaping (ExportFormat) -> Void) {
        self.context = context
        self.toggleSection = toggleSection
        self.toggleMedia = toggleMedia
        self.toggleMediaReveal = toggleMediaReveal
        self.toggleAllMedia = toggleAllMedia
        self.toggleChatsReveal = toggleChatsReveal
        self.toggleAllChats = toggleAllChats
        self.selectFolder = selectFolder
        self.selectSize = selectSize
        self.selectFormat = selectFormat
    }
}

private struct FullState: Equatable {
    public var sections: FullExportSections = .defaultSections
    public var mediaTypes: ChatExportMediaTypes = .all
    public var mediaRevealed: Bool = false
    public var chatsRevealed: Bool = false
    public var sizeLimitMB: Int32 = 100
    public var format: ExportFormat = .html
    public var outputPath: String?
}

private func fullFormatTitle(_ format: ExportFormat) -> String {
    switch format {
    case .html:
        return fullExportString("FormatHtml")
    case .json:
        return fullExportString("FormatJson")
    case .both:
        return fullExportString("FormatBoth")
    }
}

private func fullEntries(_ state: FullState, arguments: FullArguments) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(fullExportString("AccountHeader")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    for (i, descriptor) in fullAccountDescriptors.enumerated() {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: descriptor.identifier, data: .init(name: descriptor.title, color: theme.colors.text, type: .switchable(state.sections.contains(descriptor.section)), viewType: bestGeneralViewType(fullAccountDescriptors, for: i), action: {
            arguments.toggleSection(descriptor.section)
        })))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    let chatChildren = fullChatDescriptors.map { descriptor in
        CollapsibleChild(identifier: descriptor.identifier, title: descriptor.title, isOn: state.sections.contains(descriptor.section), toggle: { arguments.toggleSection(descriptor.section) })
    }
    appendCollapsibleSection(&entries, sectionId: &sectionId, index: &index, identifier: _id_chats_section, title: fullExportString("ChatsSection"), children: chatChildren, revealed: state.chatsRevealed, firstInSection: true, lastInSection: false, toggleReveal: arguments.toggleChatsReveal, toggleAll: arguments.toggleAllChats)

    appendMediaSection(&entries, sectionId: &sectionId, index: &index, mediaTypes: state.mediaTypes, revealed: state.mediaRevealed, firstInSection: false, lastInSection: true, toggleReveal: arguments.toggleMediaReveal, toggleAll: arguments.toggleAllMedia, toggle: arguments.toggleMedia)

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(exportString("SizeLimitHeader")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let sizeItems: [ContextMenuItem] = sizeLimitPresets.map { size in
        return ContextMenuItem(sizeLimitTitle(size), handler: {
            arguments.selectSize(size)
        }, state: size == state.sizeLimitMB ? .on : nil)
    }
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_size, data: .init(name: exportString("SizeLimit"), color: theme.colors.text, type: .contextSelector(sizeLimitTitle(state.sizeLimitMB), sizeItems), viewType: .singleItem)))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(sizeLimitInfoText(state.sizeLimitMB)), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(fullExportString("OtherHeader")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    for (i, descriptor) in fullOtherDescriptors.enumerated() {
        entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: descriptor.identifier, data: .init(name: descriptor.title, color: theme.colors.text, type: .switchable(state.sections.contains(descriptor.section)), viewType: bestGeneralViewType(fullOtherDescriptors, for: i), action: {
            arguments.toggleSection(descriptor.section)
        })))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(fullExportString("FormatHeader")), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
    index += 1

    let formatItems: [ContextMenuItem] = [ExportFormat.html, .json, .both].map { format in
        return ContextMenuItem(fullFormatTitle(format), handler: {
            arguments.selectFormat(format)
        }, state: state.format == format ? .on : nil)
    }
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_full_format, data: .init(name: fullExportString("Format"), color: theme.colors.text, type: .contextSelector(fullFormatTitle(state.format), formatItems), viewType: .firstItem)))
    index += 1

    let pathDisplay: String
    if let path = state.outputPath, !path.isEmpty {
        pathDisplay = path.nsstring.lastPathComponent
    } else {
        pathDisplay = exportString("ChoosePath")
    }
    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_path, data: .init(name: exportString("Folder"), color: theme.colors.text, type: .context(pathDisplay), viewType: .lastItem, action: {
        arguments.selectFolder()
    })))
    index += 1

    if let path = state.outputPath {
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(path), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public func FullExportController(context: any AccountContextProtocol) -> InputDataModalController {
    let actionsDisposable = DisposableSet()

    let initialState = FullState(outputPath: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path)
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((FullState) -> FullState) -> Void = { f in
        statePromise.set(stateValue.modify(f))
    }

    var closeImpl: (() -> Void)?

    let arguments = FullArguments(context: context, toggleSection: { section in
        updateState { current in
            var current = current
            if current.sections.contains(section) {
                current.sections.remove(section)
            } else {
                current.sections.insert(section)
            }
            return current
        }
    }, toggleMedia: { option in
        updateState { current in
            var current = current
            if current.mediaTypes.contains(option) {
                current.mediaTypes.remove(option)
            } else {
                current.mediaTypes.insert(option)
            }
            return current
        }
    }, toggleMediaReveal: {
        updateState { current in
            var current = current
            current.mediaRevealed = !current.mediaRevealed
            return current
        }
    }, toggleAllMedia: {
        updateState { current in
            var current = current
            current.mediaTypes = current.mediaTypes.isEmpty ? .all : []
            return current
        }
    }, toggleChatsReveal: {
        updateState { current in
            var current = current
            current.chatsRevealed = !current.chatsRevealed
            return current
        }
    }, toggleAllChats: {
        updateState { current in
            var current = current
            if current.sections.isDisjoint(with: .allChatTypes) {
                current.sections.formUnion(.allChatTypes)
            } else {
                current.sections.subtract(.allChatTypes)
            }
            return current
        }
    }, selectFolder: {
        selectFolder(for: context.window, completion: { path in
            updateState { current in
                var current = current
                current.outputPath = path
                return current
            }
        })
    }, selectSize: { size in
        updateState { current in
            var current = current
            current.sizeLimitMB = size
            return current
        }
    }, selectFormat: { format in
        updateState { current in
            var current = current
            current.format = format
            return current
        }
    })

    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: fullEntries(state, arguments: arguments))
    }

    let controller = InputDataController(dataSignal: signal, title: fullExportString("Title"), hasDone: false)

    controller.validateData = { _ in
        let state = stateValue.with { $0 }
        guard let path = state.outputPath, !path.isEmpty else {
            return .fail(.fields([_id_path: .shake]))
        }
        let settings = FullExportSettings(sections: state.sections, mediaTypes: state.mediaTypes, sizeLimit: sizeLimitBytes(state.sizeLimitMB), path: path, format: state.format)
        beginFullExport(context: context, settings: settings, closeSettings: { closeImpl?() })
        return .none
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: exportString("Export"), accept: { [weak controller] in
        controller?.validateInputValues()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    closeImpl = { [weak modalController] in
        modalController?.close()
    }

    return modalController
}

public func showFullExportModal(context: any AccountContextProtocol) {
    showModal(with: FullExportController(context: context), for: context.window)
}
