import Cocoa
import TelegramMediaUtils
import Postbox
import TelegramCore
import MtProtoKit
import SwiftSignalKit
import TGUIKit
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

public struct ChatExportMediaTypes: OptionSet {
    public let rawValue: Int32
    public static let photos = ChatExportMediaTypes(rawValue: 1 << 0)
    public static let videoFiles = ChatExportMediaTypes(rawValue: 1 << 1)
    public static let voiceMessages = ChatExportMediaTypes(rawValue: 1 << 2)
    public static let videoMessages = ChatExportMediaTypes(rawValue: 1 << 3)
    public static let stickers = ChatExportMediaTypes(rawValue: 1 << 4)
    public static let gifs = ChatExportMediaTypes(rawValue: 1 << 5)
    public static let files = ChatExportMediaTypes(rawValue: 1 << 6)

    public static let all: ChatExportMediaTypes = [.photos, .videoFiles, .voiceMessages, .videoMessages, .stickers, .gifs, .files]
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
}

public struct ChatExportSettings {
    public var mediaTypes: ChatExportMediaTypes
    public var sizeLimit: Int64
    public var path: String
    public var fromTimestamp: Int32?
    public var untilTimestamp: Int32?
    public init(mediaTypes: ChatExportMediaTypes, sizeLimit: Int64, path: String, fromTimestamp: Int32? = nil, untilTimestamp: Int32? = nil) {
        self.mediaTypes = mediaTypes
        self.sizeLimit = sizeLimit
        self.path = path
        self.fromTimestamp = fromTimestamp
        self.untilTimestamp = untilTimestamp
    }
}

public struct ChatExportMediaProgress: Equatable {
    public var name: String
    public var progress: Float
    public init(name: String, progress: Float) {
        self.name = name
        self.progress = progress
    }
}

public enum ChatExportUpdate: Equatable {
    case progress(processed: Int, total: Int, stage: String, media: ChatExportMediaProgress?)
    case completed(URL)
    case failed(String)
}

public func currentExportThemeColors() -> ExportThemeColors {
    func hex(_ color: NSColor) -> String {
        return String(format: "#%06x", color.argb & 0xffffff)
    }
    let p = theme.colors
    return ExportThemeColors(
        background: hex(p.background),
        text: hex(p.text),
        secondaryText: hex(p.grayText),
        accent: hex(p.accent),
        link: hex(p.link),
        surface: hex(p.grayBackground),
        border: hex(p.border)
    )
}

public func exportChatToHtml(context: any AccountContextProtocol, peerId: PeerId, peerTitle: String, settings: ChatExportSettings) -> Signal<ChatExportUpdate, NoError> {
    return Signal { subscriber in
        let queue = Queue(name: "org.telegram.chatExport")
        let cancelled = Atomic<Bool>(value: false)
        queue.async {
            let run = ChatExportRun(context: context, peerId: peerId, peerTitle: peerTitle, settings: settings, cancelled: cancelled, emit: { update in
                subscriber.putNext(update)
            })
            run.run()
            subscriber.putCompletion()
        }
        return ActionDisposable {
            let _ = cancelled.swap(true)
        }
    }
}

private func initialsFor(_ name: String) -> String {
    let components = name.split(separator: " ").filter { !$0.isEmpty }
    var initials = ""
    for component in components.prefix(2) {
        if let first = component.first {
            initials.append(first)
        }
    }
    if initials.isEmpty, let first = name.first {
        initials.append(first)
    }
    return initials.uppercased()
}

private func sanitize(_ name: String) -> String {
    var result = name
    for character in ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\n", "\r", "\t"] {
        result = result.replacingOccurrences(of: character, with: "_")
    }
    result = result.trimmingCharacters(in: .whitespaces)
    if result.isEmpty {
        result = "chat"
    }
    return result
}

private final class ChatExportRun {
    private let context: any AccountContextProtocol
    private let peerId: PeerId
    private let peerTitle: String
    private let settings: ChatExportSettings
    private let cancelled: Atomic<Bool>
    private let emit: (ChatExportUpdate) -> Void
    private let outputURL: URL?
    private let format: ExportFormat
    private let jsonSink: (([String: Any]) -> Void)?
    private let jsonMediaPrefix: String

    private var writer: ChatExportHtmlWriter!
    private var chatBaseURL: URL!
    private var authorAvatars: [PeerId: String?] = [:]

    private var processedCount = 0
    private var totalCount = 0
    private var mediaValue: ChatExportMediaProgress?

    public private(set) var resultEntryURL: URL?
    public private(set) var resultMessageCount: Int = 0

    public init(context: any AccountContextProtocol, peerId: PeerId, peerTitle: String, settings: ChatExportSettings, cancelled: Atomic<Bool>, outputURL: URL? = nil, format: ExportFormat = .html, jsonSink: (([String: Any]) -> Void)? = nil, jsonMediaPrefix: String = "", emit: @escaping (ChatExportUpdate) -> Void) {
        self.context = context
        self.peerId = peerId
        self.peerTitle = peerTitle
        self.settings = settings
        self.cancelled = cancelled
        self.outputURL = outputURL
        self.format = format
        self.jsonSink = jsonSink
        self.jsonMediaPrefix = jsonMediaPrefix
        self.emit = emit
    }

    private var isCancelled: Bool {
        return cancelled.with { $0 }
    }

    // MARK: - Driver

    @discardableResult
    public func run() -> Bool {
        let baseURL = outputURL ?? destinationURL()
        chatBaseURL = baseURL
        if format.includesHtml {
            let header = gatherChatHeader()
            writer = ChatExportHtmlWriter(baseURL: baseURL, chatName: peerTitle, avatarSrc: header.avatarSrc, colorIndex: colorIndexFor(peerId), initials: initialsFor(peerTitle), subtitle: header.subtitle, themeColors: currentExportThemeColors())
            do {
                try writer.begin()
            } catch {
                emit(.failed("Could not create export folder"))
                return false
            }
        } else {
            do {
                try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                emit(.failed("Could not create export folder"))
                return false
            }
        }

        let holder = Atomic<ChatLocationContextHolder?>(value: nil)
        let chatLocation: ChatLocation = .peer(peerId)
        let input = context.chatLocationInput(for: chatLocation, contextHolder: holder)

        var anchor: MessageHistoryAnchorIndex = .lowerBound
        var afterIndex: MessageIndex?
        var seen = Set<MessageId>()
        var previousLast: MessageIndex?
        var reachedRangeEnd = false
        processedCount = 0
        totalCount = 0
        mediaValue = nil

        if let fromTimestamp = settings.fromTimestamp, let index = historyIndex(at: fromTimestamp) {
            anchor = .message(index)
        }

        while true {
            if isCancelled {
                break
            }
            guard let view = blockingFirst(loadPage(anchor: anchor, afterIndex: afterIndex, holder: holder, input: input), timeout: 90.0) else {
                if isCancelled {
                    return false
                }
                emit(.failed("Could not load message history"))
                return false
            }
            if settings.fromTimestamp == nil, settings.untilTimestamp == nil, let pageTotal = view.entries.compactMap({ $0.location?.count }).max(), pageTotal > totalCount {
                totalCount = pageTotal
            }

            let newEntries: [MessageHistoryEntry]
            if let after = afterIndex {
                newEntries = view.entries.filter { $0.index > after }
            } else {
                newEntries = view.entries
            }

            for entry in newEntries {
                if isCancelled {
                    break
                }
                if seen.contains(entry.message.id) {
                    continue
                }
                seen.insert(entry.message.id)
                if let fromTimestamp = settings.fromTimestamp, entry.message.timestamp < fromTimestamp {
                    continue
                }
                if let untilTimestamp = settings.untilTimestamp, entry.message.timestamp >= untilTimestamp {
                    reachedRangeEnd = true
                    break
                }
                appendMessage(entry.message)
                processedCount += 1
                if processedCount % 15 == 0 {
                    emitProgress()
                }
            }

            if reachedRangeEnd {
                break
            }

            let hasMoreLater = view.laterId != nil || view.holeLater
            guard let last = view.entries.last, hasMoreLater else {
                break
            }
            if let prev = previousLast, prev == last.index {
                emit(.failed("Message history pagination did not advance"))
                return false
            }
            previousLast = last.index
            anchor = .message(last.index)
            afterIndex = last.index
        }

        if format.includesHtml {
            resultEntryURL = writer.finish()
        }
        resultMessageCount = processedCount

        if isCancelled {
            return false
        }
        mediaValue = nil
        emit(.progress(processed: processedCount, total: max(totalCount, processedCount), stage: "Finished", media: nil))
        emit(.completed(resultEntryURL ?? chatBaseURL))
        return true
    }

    private func emitProgress() {
        // Use the real total when known (0 = unknown). Never fake it as
        // processedCount — that would show a misleading 100%.
        emit(.progress(processed: processedCount, total: totalCount, stage: mediaValue != nil ? "Downloading media" : "Exporting messages", media: mediaValue))
    }

    private func setMediaProgress(name: String, progress: Float) {
        mediaValue = ChatExportMediaProgress(name: name, progress: progress)
        emitProgress()
    }

    private func destinationURL() -> URL {
        let root = URL(fileURLWithPath: settings.path, isDirectory: true)
        let base = "ChatExport_" + sanitize(peerTitle)
        var candidate = root.appendingPathComponent(base, isDirectory: true)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(base)_\(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }

    private func loadPage(anchor: MessageHistoryAnchorIndex, afterIndex: MessageIndex?, holder: Atomic<ChatLocationContextHolder?>, input: ChatLocationInput) -> Signal<MessageHistoryView, NoError> {
        return ChatExportHooks.shared.loadHistoryPage(context, peerId, anchor, 100, holder, input)
        |> mapToSignal { view -> Signal<MessageHistoryView, NoError> in
            let newCount: Int
            if let after = afterIndex {
                newCount = view.entries.reduce(0) { $0 + ($1.index > after ? 1 : 0) }
            } else {
                newCount = view.entries.count
            }
            let hasMoreLater = view.laterId != nil || view.holeLater
            if newCount == 0 && hasMoreLater {
                return .never()
            }
            return .single(view)
        }
        |> take(1)
    }

    private func historyIndex(at timestamp: Int32) -> MessageIndex? {
        let signal = context.engine.messages.searchMessageIdByTimestamp(peerId: peerId, threadId: nil, timestamp: timestamp)
        guard let messageId = blockingFirst(signal, timeout: 30.0) ?? nil else {
            return nil
        }
        return MessageIndex(id: messageId, timestamp: timestamp)
    }

    // MARK: - Message → model

    private func appendMessage(_ message: Message) {
        if message.media.first is TelegramMediaAction {
            let (text, entities, _) = serviceMessageText(message, account: context.account)
            let html = ChatExportHtmlWriter.renderEntities(text: text, entities: entities)
            if format.includesHtml, !html.isEmpty {
                writer.appendService(id: message.id.id, html: html, timestamp: message.timestamp)
            }
            if format.includesJson {
                jsonSink?(buildServiceJson(message, actionText: text))
            }
            return
        }

        let authorPeer = message.author ?? message.peers[message.id.peerId]
        let name = authorPeer?.displayTitle ?? "Unknown"
        let colorIndex = colorIndexFor(authorPeer?.id ?? message.id.peerId)
        let initials = initialsFor(name)
        let textHtml: String
        if let richText = message.richText {
            textHtml = ChatExportHtmlWriter.renderInstantPage(richText.instantPage)
        } else {
            textHtml = ChatExportHtmlWriter.renderEntities(text: message.text, entities: message.textEntities?.entities ?? [])
        }

        var forwarded: String?
        if let info = message.forwardInfo {
            forwarded = info.author?.displayTitle ?? info.authorSignature ?? info.source?.displayTitle
        }

        let replyToId = message.replyAttribute?.messageId.id

        var editedSuffix: String?
        if message.attributes.contains(where: { ($0 as? EditedMessageAttribute)?.isHidden == false }) {
            editedSuffix = "edited"
        }

        var reactions: [(emoji: String, count: Int32)] = []
        if let attribute = message.reactionsAttribute {
            for reaction in attribute.reactions {
                if case let .builtin(emoji) = reaction.value {
                    reactions.append((emoji: emoji, count: reaction.count))
                }
            }
        }

        let media = buildMedia(message, colorIndex: colorIndex)

        let model = ExportMessageModel(id: message.id.id, timestamp: message.timestamp, authorId: authorPeer?.id, authorName: name, colorIndex: colorIndex, initials: initials, textHtml: textHtml, forwardedFrom: forwarded, replyToId: replyToId, viaBot: nil, editedSuffix: editedSuffix, media: media, reactions: reactions, signature: nil, avatarSrc: authorAvatarSrc(authorPeer))
        if format.includesHtml {
            writer.appendMessage(model)
        }
        if format.includesJson {
            jsonSink?(buildMessageJson(message, model: model, media: media))
        }
    }

    // MARK: - Media

    private func webpageAccentHex(_ colorIndex: Int) -> String {
        let palette = ["#ff5555", "#64bf47", "#ffab00", "#4f9cd9", "#9884e8", "#e671a5", "#47bcd1", "#ff8c44"]
        return palette[((colorIndex % 8) + 8) % 8]
    }

    private func buildMedia(_ message: Message, colorIndex: Int) -> [ExportMediaRender] {
        var result: [ExportMediaRender] = []
        for (index, media) in message.media.enumerated() {
            if media is TelegramMediaAction {
                continue
            }
            if let image = media as? TelegramMediaImage {
                result.append(buildPhoto(image, message: message, index: index))
            } else if let file = media as? TelegramMediaFile {
                result.append(buildFile(file, message: message, index: index))
            } else if let contact = media as? TelegramMediaContact {
                let composed = [contact.firstName, contact.lastName].filter { !$0.isEmpty }.joined(separator: " ")
                result.append(.contact(name: composed.isEmpty ? contact.phoneNumber : composed, phone: contact.phoneNumber))
            } else if let map = media as? TelegramMediaMap {
                let title = map.venue?.title ?? "Location"
                result.append(.location(latitude: map.latitude, longitude: map.longitude, title: title, address: map.venue?.address))
            } else if let poll = media as? TelegramMediaPoll {
                result.append(.poll(question: poll.text, options: poll.options.map { $0.text }, total: "", closed: poll.isClosed, anonymous: false))
            } else if let webpage = media as? TelegramMediaWebpage {
                if case let .Loaded(content) = webpage.content {
                    var photoSrc: String?
                    if settings.mediaTypes.contains(.photos), let image = content.image, let representation = largestImageRepresentation(image.representations) {
                        photoSrc = download(media: image, resource: representation.resource, contentType: .image, subdir: "webpage_thumbs", fileName: "webpage_\(message.id.id)_\(index).jpg", message: message, showProgress: false)
                    }
                    result.append(.webpage(siteName: content.websiteName, title: content.title, text: content.text, url: content.url, photo: photoSrc, accent: webpageAccentHex(colorIndex)))
                }
            } else if let dice = media as? TelegramMediaDice {
                result.append(.unsupported(title: dice.emoji, status: dice.value.map { "Value: \($0)" }))
            } else if let invoice = media as? TelegramMediaInvoice {
                result.append(.unsupported(title: invoice.title, status: invoice.description))
            }
        }
        return result
    }

    private func buildPhoto(_ image: TelegramMediaImage, message: Message, index: Int) -> ExportMediaRender {
        guard settings.mediaTypes.contains(.photos), let representation = largestImageRepresentation(image.representations) else {
            return .photo(src: nil, width: nil, height: nil)
        }
        let width = Int(representation.dimensions.width)
        let height = Int(representation.dimensions.height)
        let src = download(media: image, resource: representation.resource, contentType: .image, subdir: "photos", fileName: "photo_\(message.id.id)_\(index).jpg", message: message, showProgress: false)
        return .photo(src: src, width: width, height: height)
    }

    private func buildFile(_ file: TelegramMediaFile, message: Message, index: Int) -> ExportMediaRender {
        let contentType = MediaResourceUserContentType(file: file)
        let sizeWithinLimit = (file.size ?? 0) <= settings.sizeLimit

        func downloadThumb() -> String? {
            guard let representation = largestImageRepresentation(file.previewRepresentations) else {
                return nil
            }
            return download(media: file, resource: representation.resource, contentType: .image, subdir: "thumbs", fileName: "thumb_\(message.id.id)_\(index).jpg", message: message, showProgress: false)
        }

        func downloadMain(_ subdir: String, ext: String?) -> String? {
            guard sizeWithinLimit else {
                return nil
            }
            let baseName = file.fileName ?? "file_\(message.id.id)_\(index)"
            let sanitized = sanitize(baseName)
            let finalName: String
            if sanitized.contains(".") {
                finalName = "\(message.id.id)_\(sanitized)"
            } else {
                let resolvedExt = ext ?? fileExtenstion(file)
                finalName = resolvedExt.isEmpty ? "\(message.id.id)_\(sanitized)" : "\(message.id.id)_\(sanitized).\(resolvedExt)"
            }
            return download(media: file, resource: file.resource, contentType: contentType, subdir: subdir, fileName: finalName, message: message, showProgress: true)
        }

        if file.isInstantVideo {
            guard settings.mediaTypes.contains(.videoMessages) else {
                return .roundVideo(thumb: nil, src: nil, duration: nil)
            }
            return .roundVideo(thumb: downloadThumb(), src: downloadMain("round_video_messages", ext: "mp4"), duration: videoDuration(file))
        }
        if file.isVoice {
            guard settings.mediaTypes.contains(.voiceMessages) else {
                return .voice(src: nil, status: durationOrSize(file))
            }
            return .voice(src: downloadMain("voice_messages", ext: "ogg"), status: durationOrSize(file))
        }
        if file.isSticker || file.isAnimatedSticker || file.isVideoSticker {
            guard settings.mediaTypes.contains(.stickers) else {
                return .sticker(src: nil, width: nil, height: nil, emoji: stickerEmoji(file))
            }
            let thumb = downloadThumb()
            let src = downloadMain("stickers", ext: nil) ?? thumb
            let dimensions = mediaDimensions(file)
            return .sticker(src: src, width: dimensions?.0, height: dimensions?.1, emoji: stickerEmoji(file))
        }
        if file.isVideo && file.isAnimated {
            guard settings.mediaTypes.contains(.gifs) else {
                return .gif(thumb: nil, src: nil)
            }
            return .gif(thumb: downloadThumb(), src: downloadMain("gifs", ext: "mp4"))
        }
        if file.isVideo {
            guard settings.mediaTypes.contains(.videoFiles) else {
                return .video(thumb: nil, src: nil, duration: nil, width: nil, height: nil)
            }
            let dimensions = mediaDimensions(file)
            return .video(thumb: downloadThumb(), src: downloadMain("video_files", ext: "mp4"), duration: videoDuration(file), width: dimensions?.0, height: dimensions?.1)
        }
        if file.isMusic {
            guard settings.mediaTypes.contains(.files) else {
                return .audio(src: nil, title: musicTitle(file), status: fileSize(file))
            }
            return .audio(src: downloadMain("files", ext: nil), title: musicTitle(file), status: fileSize(file))
        }
        guard settings.mediaTypes.contains(.files) else {
            return .file(src: nil, thumb: nil, title: file.fileName ?? "File", status: fileSize(file))
        }
        return .file(src: downloadMain("files", ext: nil), thumb: downloadThumb(), title: file.fileName ?? "File", status: fileSize(file))
    }

    private func download(media: Media, resource: MediaResource, contentType: MediaResourceUserContentType, subdir: String, fileName: String, message: Message, showProgress: Bool) -> String? {
        if isCancelled {
            return nil
        }
        let mediaBox = context.account.postbox.mediaBox
        let messageRef = MessageReference(message)
        let reference: MediaResourceReference
        if let file = media as? TelegramMediaFile {
            reference = FileMediaReference.message(message: messageRef, media: file).resourceReference(resource)
        } else if let image = media as? TelegramMediaImage {
            reference = ImageMediaReference.message(message: messageRef, media: image).resourceReference(resource)
        } else {
            return nil
        }

        let fetchDisposable = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(peerId), userContentType: contentType, reference: reference).start()

        let progressValue = Atomic<Float>(value: 0)
        var statusDisposable: Disposable?
        let mediaName = (media as? TelegramMediaFile)?.fileName ?? fileName
        if showProgress, let file = media as? TelegramMediaFile {
            statusDisposable = chatMessageFileStatus(context: context, message: message, file: file).start(next: { status in
                if case let .Fetching(_, progress) = status {
                    _ = progressValue.swap(progress)
                }
            })
            setMediaProgress(name: mediaName, progress: 0)
        }

        let data = waitForComplete(mediaBox: mediaBox, resource: resource, showProgress: showProgress, name: mediaName, progressValue: progressValue, timeout: 180.0)
        statusDisposable?.dispose()
        fetchDisposable.dispose()
        if showProgress {
            // Keep the last file "sticky" at 100% so the modal's media row does
            // not flicker to a placeholder between downloads (static height).
            setMediaProgress(name: mediaName, progress: 1.0)
        }

        guard let sourcePath = data?.path, FileManager.default.fileExists(atPath: sourcePath) else {
            return nil
        }

        let directory = chatBaseURL.appendingPathComponent(subdir, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let safeName = sanitize(fileName)
        let destination = directory.appendingPathComponent(safeName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            do {
                try FileManager.default.copyItem(atPath: sourcePath, toPath: destination.path)
            } catch {
                return nil
            }
        }
        return "\(subdir)/\(safeName)"
    }

    private func waitForComplete(mediaBox: MediaBox, resource: MediaResource, showProgress: Bool, name: String, progressValue: Atomic<Float>, timeout: Double) -> MediaResourceData? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: MediaResourceData?
        let disposable = (mediaBox.resourceData(resource) |> filter { $0.complete } |> take(1)).start(next: { data in
            result = data
            semaphore.signal()
        })
        let deadline = Date().addingTimeInterval(timeout)
        while semaphore.wait(timeout: .now() + 0.2) == .timedOut {
            if isCancelled || Date() > deadline {
                disposable.dispose()
                return nil
            }
            if showProgress {
                setMediaProgress(name: name, progress: progressValue.with { $0 })
            }
        }
        disposable.dispose()
        return result
    }

    // MARK: - Media helpers

    private func videoDuration(_ file: TelegramMediaFile) -> String? {
        for attribute in file.attributes {
            if case let .Video(duration, _, _, _, _, _) = attribute {
                return formatDuration(Int(duration))
            }
        }
        return nil
    }

    private func mediaDimensions(_ file: TelegramMediaFile) -> (Int, Int)? {
        for attribute in file.attributes {
            if case let .Video(_, size, _, _, _, _) = attribute {
                return (Int(size.width), Int(size.height))
            }
            if case let .ImageSize(size) = attribute {
                return (Int(size.width), Int(size.height))
            }
        }
        return nil
    }

    private func stickerEmoji(_ file: TelegramMediaFile) -> String? {
        for attribute in file.attributes {
            if case let .Sticker(displayText, _, _) = attribute {
                return displayText.isEmpty ? nil : displayText
            }
        }
        return nil
    }

    private func durationOrSize(_ file: TelegramMediaFile) -> String {
        for attribute in file.attributes {
            if case let .Audio(_, duration, _, _, _) = attribute {
                return formatDuration(duration)
            }
        }
        return fileSize(file)
    }

    private func musicTitle(_ file: TelegramMediaFile) -> String {
        for attribute in file.attributes {
            if case let .Audio(_, _, title, performer, _) = attribute {
                let parts = [performer, title].compactMap { $0 }.filter { !$0.isEmpty }
                if !parts.isEmpty {
                    return parts.joined(separator: " – ")
                }
            }
        }
        return file.fileName ?? "Audio"
    }

    private func fileSize(_ file: TelegramMediaFile) -> String {
        guard let size = file.size, size > 0 else {
            return ""
        }
        return String.prettySized(with: Int(size))
    }

    private func formatDuration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        let secs = s % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    private func gatherChatHeader() -> (avatarSrc: String?, subtitle: String?) {
        let peerId = self.peerId
        let signal = context.account.postbox.transaction { transaction -> (Peer?, CachedPeerData?) in
            return (transaction.getPeer(peerId), transaction.getPeerCachedData(peerId: peerId))
        }
        guard let result = blockingFirst(signal, timeout: 30.0), let peer = result.0 else {
            return (nil, nil)
        }
        return (downloadPeerAvatar(peer, fileName: "avatar.jpg"), chatHeaderSubtitle(peer: peer, cachedData: result.1))
    }

    private func downloadPeerAvatar(_ peer: Peer, fileName: String) -> String? {
        guard let representation = largestImageRepresentation(peer.profileImageRepresentations), let peerReference = PeerReference(peer) else {
            return nil
        }
        let mediaBox = context.account.postbox.mediaBox
        let reference = MediaResourceReference.avatar(peer: peerReference, resource: representation.resource)
        let fetchDisposable = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(peer.id), userContentType: .image, reference: reference).start()
        let data = waitForResource(mediaBox: mediaBox, resource: representation.resource, timeout: 30.0)
        fetchDisposable.dispose()
        guard let sourcePath = data?.path, FileManager.default.fileExists(atPath: sourcePath) else {
            return nil
        }
        let directory = chatBaseURL.appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let destination = directory.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            do {
                try FileManager.default.copyItem(atPath: sourcePath, toPath: destination.path)
            } catch {
                return nil
            }
        }
        return "photos/\(fileName)"
    }

    private func authorAvatarSrc(_ peer: Peer?) -> String? {
        guard let peer = peer else {
            return nil
        }
        if let cached = authorAvatars[peer.id] {
            return cached
        }
        let src = downloadPeerAvatar(peer, fileName: "author_\(UInt64(bitPattern: peer.id.toInt64())).jpg")
        authorAvatars[peer.id] = src
        return src
    }

    private func waitForResource(mediaBox: MediaBox, resource: MediaResource, timeout: Double) -> MediaResourceData? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: MediaResourceData?
        let disposable = (mediaBox.resourceData(resource) |> filter { $0.complete } |> take(1)).start(next: { data in
            result = data
            semaphore.signal()
        })
        let deadline = Date().addingTimeInterval(timeout)
        while semaphore.wait(timeout: .now() + 0.2) == .timedOut {
            if isCancelled || Date() > deadline {
                disposable.dispose()
                return nil
            }
        }
        disposable.dispose()
        return result
    }

    private func chatHeaderSubtitle(peer: Peer, cachedData: CachedPeerData?) -> String? {
        if let channel = peer as? TelegramChannel {
            let count = (cachedData as? CachedChannelData)?.participantsSummary.memberCount
            switch channel.info {
            case .broadcast:
                if let count = count {
                    return count == 1 ? "1 subscriber" : "\(count) subscribers"
                }
                return "Channel"
            case .group:
                if let count = count {
                    return count == 1 ? "1 member" : "\(count) members"
                }
                return "Group"
            }
        } else if let group = peer as? TelegramGroup {
            let count = group.participantCount
            return count == 1 ? "1 member" : "\(count) members"
        } else if let user = peer as? TelegramUser {
            if user.botInfo != nil {
                return "bot"
            }
        }
        return nil
    }

    private func colorIndexFor(_ peerId: PeerId) -> Int {
        return Int(UInt64(bitPattern: peerId.toInt64()) % 8)
    }

    // MARK: - JSON message model

    private func buildMessageJson(_ message: Message, model: ExportMessageModel, media: [ExportMediaRender]) -> [String: Any] {
        var object: [String: Any] = [:]
        object["id"] = Int(message.id.id)
        object["type"] = "message"
        object["date"] = isoDate(message.timestamp)
        object["date_unixtime"] = "\(message.timestamp)"
        object["from"] = model.authorName
        if let authorId = model.authorId {
            object["from_id"] = authorId.toInt64()
        }
        if let forwarded = model.forwardedFrom {
            object["forwarded_from"] = forwarded
        }
        if let replyToId = model.replyToId {
            object["reply_to_message_id"] = Int(replyToId)
        }
        if model.editedSuffix != nil {
            object["edited"] = true
        }
        if let richText = message.richText {
            object["text"] = richText.instantPage.plainText
        } else {
            object["text"] = message.text
            let entities = message.textEntities?.entities ?? []
            if !entities.isEmpty {
                object["text_entities"] = ChatExportHtmlWriter.textEntitiesJSON(text: message.text, entities: entities)
            }
        }
        if !model.reactions.isEmpty {
            object["reactions"] = model.reactions.map { reaction -> [String: Any] in
                return ["type": "emoji", "emoji": reaction.emoji, "count": Int(reaction.count)]
            }
        }
        for render in media {
            for (key, value) in jsonMedia(render) {
                object[key] = value
            }
        }
        return object
    }

    private func buildServiceJson(_ message: Message, actionText: String) -> [String: Any] {
        return [
            "id": Int(message.id.id),
            "type": "service",
            "date": isoDate(message.timestamp),
            "date_unixtime": "\(message.timestamp)",
            "action": actionText
        ]
    }

    private func jsonMedia(_ render: ExportMediaRender) -> [String: Any] {
        func prefixed(_ src: String?) -> String? {
            return src.map { jsonMediaPrefix + $0 }
        }
        switch render {
        case let .photo(src, width, height):
            guard let path = prefixed(src) else { return [:] }
            var d: [String: Any] = ["photo": path]
            if let width = width { d["width"] = width }
            if let height = height { d["height"] = height }
            return d
        case let .video(thumb, src, duration, width, height):
            guard let path = prefixed(src) else { return [:] }
            var d: [String: Any] = ["file": path, "media_type": "video_file"]
            if let t = prefixed(thumb) { d["thumbnail"] = t }
            if let duration = duration { d["duration"] = duration }
            if let width = width { d["width"] = width }
            if let height = height { d["height"] = height }
            return d
        case let .gif(thumb, src):
            guard let path = prefixed(src) else { return [:] }
            var d: [String: Any] = ["file": path, "media_type": "animation"]
            if let t = prefixed(thumb) { d["thumbnail"] = t }
            return d
        case let .roundVideo(thumb, src, duration):
            guard let path = prefixed(src) else { return [:] }
            var d: [String: Any] = ["file": path, "media_type": "video_message"]
            if let t = prefixed(thumb) { d["thumbnail"] = t }
            if let duration = duration { d["duration"] = duration }
            return d
        case let .sticker(src, width, height, emoji):
            guard let path = prefixed(src) else { return [:] }
            var d: [String: Any] = ["file": path, "media_type": "sticker"]
            if let emoji = emoji { d["sticker_emoji"] = emoji }
            if let width = width { d["width"] = width }
            if let height = height { d["height"] = height }
            return d
        case let .voice(src, status):
            guard let path = prefixed(src) else { return [:] }
            return ["file": path, "media_type": "voice_message", "status": status]
        case let .audio(src, title, status):
            guard let path = prefixed(src) else { return [:] }
            return ["file": path, "media_type": "audio_file", "title": title, "status": status]
        case let .file(src, thumb, title, status):
            guard let path = prefixed(src) else { return [:] }
            var d: [String: Any] = ["file": path, "file_name": title, "status": status]
            if let t = prefixed(thumb) { d["thumbnail"] = t }
            return d
        case let .contact(name, phone):
            return ["contact_information": ["first_name": name, "phone_number": phone]]
        case let .location(latitude, longitude, title, address):
            var loc: [String: Any] = [:]
            if latitude.isFinite { loc["latitude"] = latitude }
            if longitude.isFinite { loc["longitude"] = longitude }
            if !title.isEmpty { loc["title"] = title }
            if let address = address { loc["address"] = address }
            return ["location_information": loc]
        case let .poll(question, options, _, closed, _):
            return ["poll": ["question": question, "closed": closed, "answers": options.map { ["text": $0] }]]
        case let .webpage(siteName, title, text, url, photo, _):
            var web: [String: Any] = [:]
            if let siteName = siteName { web["site_name"] = siteName }
            if let title = title { web["title"] = title }
            if let text = text { web["description"] = text }
            if let url = url { web["url"] = url }
            if let photo = photo { web["photo"] = photo }
            return web.isEmpty ? [:] : ["webpage": web]
        case .unsupported:
            return [:]
        }
    }

    private func isoDate(_ timestamp: Int32) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    // MARK: - Blocking signal helper

    private func blockingFirst<T>(_ signal: Signal<T, NoError>, timeout: Double) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        let disposable = signal.start(next: { value in
            result = value
            semaphore.signal()
        }, completed: {
            semaphore.signal()
        })
        let deadline = timeout > 0 ? Date().addingTimeInterval(timeout) : Date.distantFuture
        while semaphore.wait(timeout: .now() + 0.2) == .timedOut {
            if isCancelled || Date() > deadline {
                disposable.dispose()
                return nil
            }
        }
        disposable.dispose()
        return result
    }
}

// MARK: - Full account export ("Export Telegram Data")

public enum ExportFormat: Int32 {
    case html
    case json
    case both

    public var includesHtml: Bool {
        return self == .html || self == .both
    }
    public var includesJson: Bool {
        return self == .json || self == .both
    }
}

public struct FullExportSections: OptionSet {
    public let rawValue: Int32
    public static let personalInfo = FullExportSections(rawValue: 1 << 0)
    public static let contacts = FullExportSections(rawValue: 1 << 1)
    public static let sessions = FullExportSections(rawValue: 1 << 2)
    public static let personalChats = FullExportSections(rawValue: 1 << 3)
    public static let botChats = FullExportSections(rawValue: 1 << 4)
    public static let privateGroups = FullExportSections(rawValue: 1 << 5)
    public static let privateChannels = FullExportSections(rawValue: 1 << 6)
    public static let publicGroups = FullExportSections(rawValue: 1 << 7)
    public static let publicChannels = FullExportSections(rawValue: 1 << 8)
    public static let stories = FullExportSections(rawValue: 1 << 9)
    public static let otherData = FullExportSections(rawValue: 1 << 10)

    public static let allChatTypes: FullExportSections = [.personalChats, .botChats, .privateGroups, .privateChannels, .publicGroups, .publicChannels]
    public static let defaultSections: FullExportSections = [.personalInfo, .contacts, .stories, .personalChats, .privateGroups]
    public init(rawValue: Int32) {
        self.rawValue = rawValue
    }
}

public struct FullExportSettings {
    public var sections: FullExportSections
    public var mediaTypes: ChatExportMediaTypes
    public var sizeLimit: Int64
    public var path: String
    public var format: ExportFormat
    public init(sections: FullExportSections, mediaTypes: ChatExportMediaTypes, sizeLimit: Int64, path: String, format: ExportFormat) {
        self.sections = sections
        self.mediaTypes = mediaTypes
        self.sizeLimit = sizeLimit
        self.path = path
        self.format = format
    }
}

public struct FullExportChatFailure: Equatable {
    public let peer: PeerEquatable
    public let reason: String
}

public struct FullExportProgress: Equatable {
    public var stage: String
    public var chatIndex: Int
    public var chatCount: Int
    public var currentTitle: String
    public var currentPeer: PeerEquatable? = nil
    public var processed: Int
    public var total: Int
    public var media: ChatExportMediaProgress?
    public var failedChats: [FullExportChatFailure]
    public init(stage: String, chatIndex: Int, chatCount: Int, currentTitle: String, currentPeer: PeerEquatable? = nil, processed: Int, total: Int, media: ChatExportMediaProgress? = nil, failedChats: [FullExportChatFailure] = []) {
        self.stage = stage
        self.chatIndex = chatIndex
        self.chatCount = chatCount
        self.currentTitle = currentTitle
        self.currentPeer = currentPeer
        self.processed = processed
        self.total = total
        self.media = media
        self.failedChats = failedChats
    }
}

public enum FullExportUpdate: Equatable {
    case progress(FullExportProgress)
    case completed(URL, failedChats: [FullExportChatFailure])
    case failed(String)
}

public enum TakeoutSessionResult {
    case ready(Int64)
    case delay(Int32)
    case failed(String)
}

public func requestTakeoutSession(context: any AccountContextProtocol, settings: FullExportSettings) -> Signal<TakeoutSessionResult, NoError> {
    var contents: TakeoutSessionContents = []
    if settings.sections.contains(.contacts) {
        contents.insert(.contacts)
    }
    if settings.sections.contains(.personalChats) || settings.sections.contains(.botChats) {
        contents.insert(.messageUsers)
    }
    if settings.sections.contains(.privateGroups) {
        contents.insert(.messageChats)
    }
    if settings.sections.contains(.privateGroups) || settings.sections.contains(.publicGroups) {
        contents.insert(.messageMegagroups)
    }
    if settings.sections.contains(.privateChannels) || settings.sections.contains(.publicChannels) {
        contents.insert(.messageChannels)
    }
    var fileMaxSize: Int64?
    if !settings.mediaTypes.isEmpty {
        contents.insert(.files)
        fileMaxSize = min(settings.sizeLimit, 4000 * 1024 * 1024)
    }
    return initTakeoutSession(network: context.account.network, contents: contents, fileMaxSize: fileMaxSize)
    |> map { id -> TakeoutSessionResult in
        return .ready(id)
    }
    |> `catch` { error -> Signal<TakeoutSessionResult, NoError> in
        let description = error.errorDescription ?? ""
        let prefix = "TAKEOUT_INIT_DELAY_"
        if description.hasPrefix(prefix) {
            let seconds = Int32(String(description.dropFirst(prefix.count))) ?? 1
            return .single(.delay(max(1, seconds)))
        }
        return .single(.failed(description))
    }
}

public func finishTakeoutSession(context: any AccountContextProtocol, success: Bool) {
    _ = finishTakeoutSession(network: context.account.network, success: success).start()
}

public func exportAllChatsToHtml(context: any AccountContextProtocol, settings: FullExportSettings) -> Signal<FullExportUpdate, NoError> {
    return Signal { subscriber in
        let queue = Queue(name: "org.telegram.fullExport")
        let cancelled = Atomic<Bool>(value: false)
        let sessionsSignal: Signal<ActiveSessionsContextState, NoError>? = settings.sections.contains(.sessions) ? context.activeSessionsContext.state : nil
        let webSessionsSignal: Signal<WebSessionsContextState, NoError>? = settings.sections.contains(.sessions) ? context.webSessions.state : nil
        queue.async {
            let run = FullExportRun(context: context, settings: settings, cancelled: cancelled, sessionsSignal: sessionsSignal, webSessionsSignal: webSessionsSignal, emit: { update in
                subscriber.putNext(update)
            })
            run.run()
            subscriber.putCompletion()
        }
        return ActionDisposable {
            let _ = cancelled.swap(true)
        }
    }
}

private final class FullExportRun {
    private let context: any AccountContextProtocol
    private let settings: FullExportSettings
    private let cancelled: Atomic<Bool>
    private let sessionsSignal: Signal<ActiveSessionsContextState, NoError>?
    private let webSessionsSignal: Signal<WebSessionsContextState, NoError>?
    private let emit: (FullExportUpdate) -> Void

    private var baseURL: URL!
    private var failedChats: [FullExportChatFailure] = []

    private struct PersonalInfo {
        public let user: TelegramUser?
        public let about: String?
    }
    private struct ContactEntry {
        public let name: String
        public let phone: String?
        public let colorIndex: Int
        public let initials: String
        public let photoSrc: String?
    }
    private struct FrequentContact {
        public let name: String
        public let category: String
        public let rating: Double
        public let colorIndex: Int
        public let initials: String
        public let photoSrc: String?
    }
    private struct OtherMediaItem {
        public let relativePath: String?
        public let emojis: [String]
        public let fileName: String
    }
    private struct ChatEntry {
        public let peerId: PeerId
        public let peer: Peer
        public let title: String
        public let typeLabel: String
        public let jsonType: String
        public let bareId: Int64
        public let colorIndex: Int
        public let initials: String
    }
    private struct StoryMeta {
        public let id: Int32
        public let timestamp: Int32
        public let text: String
        public let mediaType: String
        public let mediaPath: String?
        public let thumbPath: String?
    }

    private static let topAbout = "Machine-readable JSON export of your Telegram data."
    private static let contactsAbout = "If you allow access, contacts are continuously synced with Telegram."
    private static let sessionsAbout = "We may store this to display your connected devices in Settings > Privacy & Security > Show all sessions."
    private static let otherAbout = "Other types of data not mentioned above (beta)."
    private static let chatsAbout = "This is the list of all chats from this export."
    private static let frequentAbout = "People and bots you interact with most often."
    private static let webSessionsAbout = "Websites and bots you have logged into with Telegram."

    public init(context: any AccountContextProtocol, settings: FullExportSettings, cancelled: Atomic<Bool>, sessionsSignal: Signal<ActiveSessionsContextState, NoError>?, webSessionsSignal: Signal<WebSessionsContextState, NoError>?, emit: @escaping (FullExportUpdate) -> Void) {
        self.context = context
        self.settings = settings
        self.cancelled = cancelled
        self.sessionsSignal = sessionsSignal
        self.webSessionsSignal = webSessionsSignal
        self.emit = emit
    }

    private var isCancelled: Bool {
        return cancelled.with { $0 }
    }

    // MARK: - Driver

    public func run() {
        assert(!Queue.mainQueue().isCurrent())
        let baseURL = destinationURL()
        self.baseURL = baseURL

        let overview: ExportOverviewWriter? = settings.format.includesHtml ? ExportOverviewWriter(baseURL: baseURL, themeColors: currentExportThemeColors()) : nil
        let jsonWriter: ExportJsonWriter? = settings.format.includesJson ? ExportJsonWriter(baseURL: baseURL) : nil
        do {
            try overview?.writeAssets()
            try jsonWriter?.begin(about: FullExportRun.topAbout)
        } catch {
            emit(.failed("Could not create export folder"))
            return
        }

        let chats = gatherChats()
        let chatCount = chats.count
        var menu: [ExportMenuItem] = []

        if !isCancelled, settings.sections.contains(.personalInfo) {
            emitStage("Personal information", chatCount: chatCount)
            if let info = gatherPersonalInfo() {
                let name = info.user?.displayTitle ?? "You"
                let colorIndex = colorIndexFor(context.account.peerId)
                let photoSrcs = downloadAllAccountPhotos(info.user)
                var rows: [ExportInfoRow] = []
                rows.append(ExportInfoRow(label: "Name", value: name))
                if let username = info.user?.username, !username.isEmpty {
                    rows.append(ExportInfoRow(label: "Username", value: "@\(username)"))
                }
                if let phone = info.user?.phone, !phone.isEmpty {
                    rows.append(ExportInfoRow(label: "Phone number", value: "+\(phone)"))
                }
                if let about = info.about, !about.isEmpty {
                    rows.append(ExportInfoRow(label: "Bio", value: about))
                }
                overview?.writePersonalInfo(fileName: "personal_information.html", title: "Personal information", name: name, colorIndex: colorIndex, initials: initialsFor(name), photoSrcs: photoSrcs, rows: rows)
                if overview != nil {
                    menu.append(ExportMenuItem(title: "Personal information", counter: nil, href: "personal_information.html"))
                }
                let personal: [String: Any] = [
                    "user_id": context.account.peerId.toInt64(),
                    "first_name": info.user?.firstName ?? "",
                    "last_name": info.user?.lastName ?? "",
                    "phone_number": (info.user?.phone).flatMap { $0.isEmpty ? nil : "+\($0)" } ?? "",
                    "username": info.user?.username ?? "",
                    "bio": info.about ?? ""
                ]
                jsonWriter?.writeSection("personal_information", object: personal)
                if !photoSrcs.isEmpty {
                    jsonWriter?.writeSection("profile_pictures", object: photoSrcs.map { ["photo": $0] })
                }
            }
        }

        if !isCancelled, settings.sections.contains(.contacts) {
            emitStage("Contacts", chatCount: chatCount)
            let contacts = gatherContacts()
            if overview != nil {
                let entries = contacts.map { contact in
                    ExportListEntry(colorIndex: contact.colorIndex, initials: contact.initials, title: contact.name, subtitle: contact.phone.flatMap { $0.isEmpty ? nil : "+\($0)" }, info: [], href: nil, photoSrc: contact.photoSrc)
                }
                overview?.writeListPage(fileName: "contacts.html", title: "Contacts", about: nil, entries: entries)
                menu.append(ExportMenuItem(title: "Contacts", counter: "\(contacts.count)", href: "contacts.html"))
            }
            jsonWriter?.writeSection("contacts", object: [
                "about": FullExportRun.contactsAbout,
                "list": contacts.map { contact -> [String: Any] in
                    return ["first_name": contact.name, "last_name": "", "phone_number": contact.phone ?? ""]
                }
            ])

            let frequent = gatherFrequentContacts()
            if overview != nil, !frequent.isEmpty {
                let entries = frequent.map { fc in
                    ExportListEntry(colorIndex: fc.colorIndex, initials: fc.initials, title: fc.name, subtitle: fc.category, info: fc.rating > 0 ? [String(format: "rating: %.2f", fc.rating)] : [], href: nil, photoSrc: fc.photoSrc)
                }
                overview?.writeListPage(fileName: "frequent_contacts.html", title: "Frequent contacts", about: nil, entries: entries)
                menu.append(ExportMenuItem(title: "Frequent contacts", counter: "\(frequent.count)", href: "frequent_contacts.html"))
            }
            jsonWriter?.writeSection("frequent_contacts", object: [
                "about": FullExportRun.frequentAbout,
                "list": frequent.map { fc -> [String: Any] in
                    return ["name": fc.name, "category": fc.category, "rating": fc.rating]
                }
            ])
        }

        if !isCancelled, settings.sections.contains(.stories) {
            emitStage("Story archive", chatCount: chatCount)
            let storyItems = gatherStoryItems()
            let peerReference = accountPeerReference()
            var metas: [StoryMeta] = []
            var gridItems: [ExportStoryGridItem] = []
            for (index, item) in storyItems.enumerated() {
                if isCancelled {
                    break
                }
                emit(.progress(FullExportProgress(stage: "Story archive", chatIndex: 0, chatCount: chatCount, currentTitle: "Story archive", processed: index + 1, total: storyItems.count, media: nil)))
                let media = item.media._asMedia()
                let isVideo = (media as? TelegramMediaFile)?.isVideo ?? false
                let mediaType: String
                if media is TelegramMediaImage {
                    mediaType = "photo"
                } else if isVideo {
                    mediaType = "video"
                } else if media is TelegramMediaFile {
                    mediaType = "file"
                } else {
                    mediaType = ""
                }
                var mediaPath: String?
                var thumbPath: String?
                if let peerReference = peerReference {
                    let paths = downloadStoryMedia(item, index: index, peerReference: peerReference)
                    mediaPath = paths.mediaPath
                    thumbPath = paths.thumbPath
                }
                metas.append(StoryMeta(id: item.id, timestamp: item.timestamp, text: item.text, mediaType: mediaType, mediaPath: mediaPath, thumbPath: thumbPath))
                gridItems.append(ExportStoryGridItem(mediaSrc: mediaPath, thumbSrc: thumbPath ?? mediaPath, isVideo: isVideo, caption: item.text, dateBadge: storyDateBadge(item.timestamp), colorIndex: colorIndexForInt(Int64(item.id))))
            }
            if overview != nil {
                overview?.writeStoriesGrid(fileName: "stories.html", title: "Story archive", about: nil, items: gridItems)
                menu.append(ExportMenuItem(title: "Story archive", counter: "\(metas.count)", href: "stories.html"))
            }
            jsonWriter?.writeSection("stories", object: metas.map { story -> [String: Any] in
                var object: [String: Any] = ["date": isoDate(story.timestamp), "date_unixtime": "\(story.timestamp)", "text": story.text, "media_type": story.mediaType]
                if let path = story.mediaPath {
                    object["media"] = path
                }
                return object
            })
        }

        if !isCancelled, settings.sections.contains(.sessions), let sessionsSignal = sessionsSignal {
            emitStage("Active sessions", chatCount: chatCount)
            let sessions = gatherSessions(sessionsSignal)
            if overview != nil {
                let entries = sessions.map { session -> ExportListEntry in
                    let appTitle = [session.appName, session.appVersion].filter { !$0.isEmpty }.joined(separator: " ")
                    let title = appTitle.isEmpty ? session.deviceModel : appTitle
                    var info: [String] = []
                    let device = [session.deviceModel, session.platform, session.systemVersion].filter { !$0.isEmpty }.joined(separator: ", ")
                    if !device.isEmpty { info.append(device) }
                    let location = [session.ip, session.country].filter { !$0.isEmpty }.joined(separator: " — ")
                    if !location.isEmpty { info.append(location) }
                    info.append("Last active: \(formatDate(session.activityDate))")
                    return ExportListEntry(colorIndex: colorIndexForInt(session.hash), initials: initialsFor(title), title: session.isCurrent ? "\(title) (current)" : title, subtitle: nil, info: info, href: nil)
                }
                overview?.writeListPage(fileName: "sessions.html", title: "Active sessions", about: nil, entries: entries)
                menu.append(ExportMenuItem(title: "Active sessions", counter: "\(sessions.count)", href: "sessions.html"))
            }
            jsonWriter?.writeSection("sessions", object: [
                "about": FullExportRun.sessionsAbout,
                "list": sessions.map { session -> [String: Any] in
                    return [
                        "last_active": isoDate(session.activityDate),
                        "last_active_unixtime": "\(session.activityDate)",
                        "last_ip": session.ip,
                        "last_country": session.country,
                        "last_region": session.region,
                        "application_name": session.appName,
                        "application_version": session.appVersion,
                        "device_model": session.deviceModel,
                        "platform": session.platform,
                        "system_version": session.systemVersion,
                        "created": isoDate(session.creationDate),
                        "created_unixtime": "\(session.creationDate)"
                    ]
                }
            ])

            if let webSessionsSignal = webSessionsSignal {
                let webSessions = gatherWebSessions(webSessionsSignal)
                if overview != nil, !webSessions.isEmpty {
                    let entries = webSessions.map { session -> ExportListEntry in
                        var info: [String] = []
                        let where_ = [session.browser, session.platform].filter { !$0.isEmpty }.joined(separator: ", ")
                        if !where_.isEmpty { info.append(where_) }
                        let location = [session.ip, session.region].filter { !$0.isEmpty }.joined(separator: " — ")
                        if !location.isEmpty { info.append(location) }
                        info.append("Last active: \(formatDate(session.dateActive))")
                        return ExportListEntry(colorIndex: colorIndexForInt(session.hash), initials: initialsFor(session.domain.isEmpty ? "Web" : session.domain), title: session.domain.isEmpty ? "Website" : session.domain, subtitle: nil, info: info, href: nil)
                    }
                    overview?.writeListPage(fileName: "web_sessions.html", title: "Connected websites", about: FullExportRun.webSessionsAbout, entries: entries)
                    menu.append(ExportMenuItem(title: "Connected websites", counter: "\(webSessions.count)", href: "web_sessions.html"))
                }
                jsonWriter?.writeSection("web_sessions", object: [
                    "about": FullExportRun.webSessionsAbout,
                    "list": webSessions.map { session -> [String: Any] in
                        return [
                            "last_active": isoDate(session.dateActive),
                            "last_active_unixtime": "\(session.dateActive)",
                            "last_ip": session.ip,
                            "last_region": session.region,
                            "domain_name": session.domain,
                            "browser": session.browser,
                            "platform": session.platform,
                            "created": isoDate(session.dateCreated),
                            "created_unixtime": "\(session.dateCreated)"
                        ]
                    }
                ])
            }
        }

        if !isCancelled, settings.sections.contains(.otherData) {
            emitStage("Miscellaneous data", chatCount: chatCount)
            let other = gatherOtherData()
            if overview != nil {
                var entries: [ExportListEntry] = []
                for (i, gif) in other.gifs.enumerated() {
                    entries.append(ExportListEntry(colorIndex: i % 8, initials: "GIF", title: gif.fileName, subtitle: "Saved GIF", info: [], href: gif.relativePath))
                }
                for (i, sticker) in other.stickers.enumerated() {
                    let emoji = sticker.emojis.joined(separator: " ")
                    entries.append(ExportListEntry(colorIndex: i % 8, initials: sticker.emojis.first ?? "S", title: emoji.isEmpty ? sticker.fileName : emoji, subtitle: "Favorite sticker", info: [], href: sticker.relativePath))
                }
                overview?.writeListPage(fileName: "other_data.html", title: "Miscellaneous data", about: FullExportRun.otherAbout, entries: entries)
                menu.append(ExportMenuItem(title: "Miscellaneous data", counter: "\(other.gifs.count + other.stickers.count)", href: "other_data.html"))
            }
            jsonWriter?.writeSection("other_data", object: [
                "saved_gifs": other.gifs.map { item -> [String: Any] in
                    var d: [String: Any] = ["file_name": item.fileName]
                    if let path = item.relativePath { d["file"] = path }
                    return d
                },
                "favorite_stickers": other.stickers.map { item -> [String: Any] in
                    var d: [String: Any] = ["emoji": item.emojis]
                    if let path = item.relativePath { d["file"] = path }
                    return d
                }
            ])
        }

        jsonWriter?.beginChats(about: FullExportRun.chatsAbout)
        var paneItems: [ExportChatPaneItem] = []
        for (index, chat) in chats.enumerated() {
            if isCancelled { break }
            let folder = String(format: "%04ld", index) + "_" + sanitize(chat.title)
            let chatURL = baseURL.appendingPathComponent("chats", isDirectory: true).appendingPathComponent(folder, isDirectory: true)
            let chatSettings = ChatExportSettings(mediaTypes: settings.mediaTypes, sizeLimit: settings.sizeLimit, path: settings.path)
            jsonWriter?.beginChat(name: chat.title, type: chat.jsonType, id: chat.bareId)
            let run = ChatExportRun(context: context, peerId: chat.peerId, peerTitle: chat.title, settings: chatSettings, cancelled: cancelled, outputURL: chatURL, format: settings.format, jsonSink: jsonWriter != nil ? { [weak jsonWriter] object in jsonWriter?.appendMessage(object) } : nil, jsonMediaPrefix: "chats/\(folder)/", emit: { [weak self] update in
                self?.forwardChatProgress(update, chatIndex: index + 1, chatCount: chatCount, chat: chat)
            })
            let succeeded = run.run()
            jsonWriter?.endChat()
            if isCancelled { break }
            if !succeeded {
                continue
            }
            if overview != nil, let entryURL = run.resultEntryURL {
                let relative = "chats/\(folder)/\(entryURL.lastPathComponent)"
                let subtitle = "\(chat.typeLabel) · \(run.resultMessageCount) messages"
                let avatarRelative = "chats/\(folder)/photos/avatar.jpg"
                let photoSrc = FileManager.default.fileExists(atPath: baseURL.appendingPathComponent(avatarRelative).path) ? avatarRelative : nil
                paneItems.append(ExportChatPaneItem(colorIndex: chat.colorIndex, initials: chat.initials, title: chat.title, subtitle: subtitle, messagesHref: relative, photoSrc: photoSrc))
            }
        }

        if overview != nil, !paneItems.isEmpty {
            overview?.writeChatsPane(fileName: "chats.html", title: "Chats", chats: paneItems)
            let chatsItem = ExportMenuItem(title: "Chats", counter: "\(paneItems.count)", href: "chats.html")
            if let personalIndex = menu.firstIndex(where: { $0.href == "personal_information.html" }) {
                menu.insert(chatsItem, at: personalIndex + 1)
            } else {
                menu.insert(chatsItem, at: 0)
            }
        }

        let account = overview != nil ? accountHeaderInfo() : nil
        overview?.writeIndex(fileName: "export_results.html", title: "Telegram Data Export", accountName: account?.name, accountAvatarSrc: account?.avatarSrc, accountColorIndex: account?.colorIndex ?? 0, accountInitials: account?.initials ?? "", menu: menu, chatsHeader: nil, chats: [])
        jsonWriter?.finish()

        if isCancelled {
            return
        }
        let indexURL = overview != nil ? baseURL.appendingPathComponent("export_results.html") : baseURL.appendingPathComponent("result.json")
        emit(.completed(indexURL, failedChats: failedChats))
    }

    private func emitStage(_ stage: String, chatCount: Int) {
        emit(.progress(FullExportProgress(stage: stage, chatIndex: 0, chatCount: chatCount, currentTitle: stage, processed: 0, total: 0, media: nil, failedChats: failedChats)))
    }

    private func forwardChatProgress(_ update: ChatExportUpdate, chatIndex: Int, chatCount: Int, chat: ChatEntry) {
        switch update {
        case let .progress(processed, total, _, media):
            emit(.progress(FullExportProgress(stage: "Chats", chatIndex: chatIndex, chatCount: chatCount, currentTitle: chat.title, currentPeer: PeerEquatable(chat.peer), processed: processed, total: total, media: media, failedChats: failedChats)))
        case let .failed(reason):
            if isCancelled { return }
            failedChats.append(FullExportChatFailure(peer: PeerEquatable(chat.peer), reason: reason))
            emit(.progress(FullExportProgress(stage: "Chats", chatIndex: chatIndex, chatCount: chatCount, currentTitle: chat.title, processed: 0, total: 0, failedChats: failedChats)))
        case .completed:
            break
        }
    }

    // MARK: - Account data

    private func gatherPersonalInfo() -> PersonalInfo? {
        let peerId = context.account.peerId
        let signal = context.account.postbox.transaction { transaction -> PersonalInfo in
            let user = transaction.getPeer(peerId) as? TelegramUser
            let about = (transaction.getPeerCachedData(peerId: peerId) as? CachedUserData)?.about
            return PersonalInfo(user: user, about: about)
        }
        return blockingFirst(signal, timeout: 30.0)
    }

    private func accountHeaderInfo() -> (name: String, avatarSrc: String?, colorIndex: Int, initials: String) {
        let peerId = context.account.peerId
        let user = (blockingFirst(context.account.postbox.transaction { transaction -> TelegramUser? in
            return transaction.getPeer(peerId) as? TelegramUser
        }, timeout: 15.0)) ?? nil
        let name = user?.displayTitle ?? "You"
        var avatarSrc: String?
        let existing = baseURL.appendingPathComponent("profile_pictures").appendingPathComponent("photo.jpg")
        if FileManager.default.fileExists(atPath: existing.path) {
            avatarSrc = "profile_pictures/photo.jpg"
        } else {
            avatarSrc = downloadAllAccountPhotos(user).first
        }
        return (name, avatarSrc, colorIndexFor(peerId), initialsFor(name))
    }

    private func downloadAllAccountPhotos(_ user: TelegramUser?) -> [String] {
        guard let user = user, let peerReference = PeerReference(user) else {
            return []
        }
        var images: [TelegramMediaImage] = (blockingFirst(context.engine.peers.requestPeerPhotos(peerId: user.id), timeout: 60.0) ?? []).map { $0.image }
        if images.isEmpty {
            let representations = user.profileImageRepresentations
            if !representations.isEmpty {
                images = [TelegramMediaImage(imageId: MediaId(namespace: 0, id: 0), representations: representations, immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])]
            }
        }
        guard !images.isEmpty else {
            return []
        }
        let mediaBox = context.account.postbox.mediaBox
        let directory = baseURL.appendingPathComponent("profile_pictures", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        var result: [String] = []
        for (index, image) in images.enumerated() {
            if isCancelled {
                break
            }
            guard let representation = largestImageRepresentation(image.representations) else {
                continue
            }
            let reference = MediaResourceReference.avatar(peer: peerReference, resource: representation.resource)
            let fetchDisposable = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(user.id), userContentType: .image, reference: reference).start()
            let data = waitForResource(mediaBox: mediaBox, resource: representation.resource, timeout: 30.0)
            fetchDisposable.dispose()
            guard let sourcePath = data?.path, FileManager.default.fileExists(atPath: sourcePath) else {
                continue
            }
            let fileName = index == 0 ? "photo.jpg" : "photo_\(index).jpg"
            let destination = directory.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: destination.path) {
                do {
                    try FileManager.default.copyItem(atPath: sourcePath, toPath: destination.path)
                } catch {
                    continue
                }
            }
            result.append("profile_pictures/\(fileName)")
        }
        return result
    }

    private func gatherContacts() -> [ContactEntry] {
        let signal = context.engine.data.get(TelegramEngine.EngineData.Item.Contacts.List(includePresences: false))
        guard let list = blockingFirst(signal, timeout: 60.0) else {
            return []
        }
        var result: [ContactEntry] = []
        for peer in list.peers {
            if isCancelled {
                break
            }
            let underlying = peer._asPeer()
            let name = underlying.displayTitle
            var phone: String?
            if case let .user(user) = peer {
                phone = user.phone
            }
            let photoSrc = copyCachedAvatar(underlying, fileName: "contact_\(UInt64(bitPattern: underlying.id.toInt64())).jpg")
            result.append(ContactEntry(name: name, phone: phone, colorIndex: colorIndexFor(underlying.id), initials: initialsFor(name), photoSrc: photoSrc))
        }
        result.sort { $0.name.lowercased() < $1.name.lowercased() }
        return result
    }

    private func copyCachedAvatar(_ peer: Peer, fileName: String) -> String? {
        guard let representation = largestImageRepresentation(peer.profileImageRepresentations) else {
            return nil
        }
        let mediaBox = context.account.postbox.mediaBox
        guard let data = blockingFirst(mediaBox.resourceData(representation.resource) |> take(1), timeout: 3.0), data.complete, FileManager.default.fileExists(atPath: data.path) else {
            return nil
        }
        let directory = baseURL.appendingPathComponent("avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let destination = directory.appendingPathComponent(fileName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            do {
                try FileManager.default.copyItem(atPath: data.path, toPath: destination.path)
            } catch {
                return nil
            }
        }
        return "avatars/\(fileName)"
    }

    private func gatherSessions(_ signal: Signal<ActiveSessionsContextState, NoError>) -> [RecentAccountSession] {
        let ready = signal |> filter { !$0.isLoadingMore } |> take(1)
        guard let state = blockingFirst(ready, timeout: 30.0) else {
            return []
        }
        return state.sessions
    }

    // MARK: - Chat enumeration

    private func gatherChats() -> [ChatEntry] {
        let sections = settings.sections
        let signal = context.account.postbox.transaction { transaction -> [ChatEntry] in
            var ids: [PeerId] = []
            var seen = Set<PeerId>()
            for id in transaction.chatListGetAllPeerIds(groupId: .root) + transaction.chatListGetAllPeerIds(groupId: Namespaces.PeerGroup.archive) {
                if seen.insert(id).inserted {
                    ids.append(id)
                }
            }
            var result: [ChatEntry] = []
            for id in ids {
                guard let peer = transaction.getPeer(id) else {
                    continue
                }
                guard let categorized = self.categorize(peer) else {
                    continue
                }
                guard sections.contains(categorized.section) else {
                    continue
                }
                let title = peer.displayTitle
                result.append(ChatEntry(peerId: id, peer: peer, title: title, typeLabel: categorized.label, jsonType: categorized.jsonType, bareId: id.toInt64(), colorIndex: self.colorIndexFor(id), initials: initialsFor(title)))
            }
            return result
        }
        return blockingFirst(signal, timeout: 60.0) ?? []
    }

    private func categorize(_ peer: Peer) -> (section: FullExportSections, label: String, jsonType: String)? {
        if peer is TelegramSecretChat {
            return nil
        }
        if let user = peer as? TelegramUser {
            if user.id == context.account.peerId {
                return (.personalChats, "Saved Messages", "saved_messages")
            }
            if user.botInfo != nil {
                return (.botChats, "Bot chat", "bot_chat")
            }
            return (.personalChats, "Personal chat", "personal_chat")
        }
        if peer is TelegramGroup {
            return (.privateGroups, "Private group", "private_group")
        }
        if let channel = peer as? TelegramChannel {
            let isPublic = !(channel.addressName ?? "").isEmpty
            switch channel.info {
            case .broadcast:
                return isPublic ? (.publicChannels, "Public channel", "public_channel") : (.privateChannels, "Private channel", "private_channel")
            case .group:
                return isPublic ? (.publicGroups, "Public group", "public_supergroup") : (.privateGroups, "Private group", "private_supergroup")
            }
        }
        return nil
    }

    private func gatherStoryItems() -> [EngineStoryItem] {
        let account = context.account
        let peerId = account.peerId
        let signal = Signal<[EngineStoryItem], NoError> { subscriber in
            let listContext = PeerStoryListContext(account: account, peerId: peerId, isArchived: true, folderId: nil)
            let stateDisposable = (listContext.state |> deliverOnMainQueue).start(next: { state in
                if state.isLoading {
                    return
                }
                if state.loadMoreToken == nil {
                    subscriber.putNext(state.items.map { $0.storyItem })
                    subscriber.putCompletion()
                } else {
                    listContext.loadMore(completion: nil)
                }
            })
            return ActionDisposable {
                stateDisposable.dispose()
                withExtendedLifetime(listContext) {}
            }
        }
        return blockingFirst(signal, timeout: 180.0) ?? []
    }

    private func accountPeerReference() -> PeerReference? {
        let signal = context.account.postbox.transaction { transaction -> PeerReference? in
            return transaction.getPeer(self.context.account.peerId).flatMap(PeerReference.init)
        }
        return (blockingFirst(signal, timeout: 15.0)) ?? nil
    }

    private func storyDateBadge(_ timestamp: Int32) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private func downloadStoryMedia(_ item: EngineStoryItem, index: Int, peerReference: PeerReference) -> (mediaPath: String?, thumbPath: String?) {
        let media = item.media._asMedia()
        let mediaBox = context.account.postbox.mediaBox
        let directory = baseURL.appendingPathComponent("stories", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)

        func fetchCopy(resource: MediaResource, contentType: MediaResourceUserContentType, fileName: String) -> String? {
            if isCancelled {
                return nil
            }
            let reference = MediaResourceReference.media(media: .story(peer: peerReference, id: item.id, media: media), resource: resource)
            let fetchDisposable = fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(context.account.peerId), userContentType: contentType, reference: reference).start()
            let data = waitForResource(mediaBox: mediaBox, resource: resource, timeout: 120.0)
            fetchDisposable.dispose()
            guard let sourcePath = data?.path, FileManager.default.fileExists(atPath: sourcePath) else {
                return nil
            }
            let destination = directory.appendingPathComponent(fileName)
            if !FileManager.default.fileExists(atPath: destination.path) {
                do {
                    try FileManager.default.copyItem(atPath: sourcePath, toPath: destination.path)
                } catch {
                    return nil
                }
            }
            return "stories/\(fileName)"
        }

        if let image = media as? TelegramMediaImage {
            guard let representation = largestImageRepresentation(image.representations) else {
                return (nil, nil)
            }
            let path = fetchCopy(resource: representation.resource, contentType: .story, fileName: "photo_\(index).jpg")
            return (path, path)
        } else if let file = media as? TelegramMediaFile, file.isVideo {
            var thumbPath: String?
            if let thumbRep = largestImageRepresentation(file.previewRepresentations) {
                thumbPath = fetchCopy(resource: thumbRep.resource, contentType: .story, fileName: "thumb_\(index).jpg")
            }
            var mediaPath: String?
            if (file.size ?? 0) <= settings.sizeLimit {
                mediaPath = fetchCopy(resource: file.resource, contentType: .story, fileName: "video_\(index).mp4")
            }
            return (mediaPath, thumbPath)
        }
        return (nil, nil)
    }

    private func gatherOtherData() -> (gifs: [OtherMediaItem], stickers: [OtherMediaItem]) {
        let listSignal = context.account.postbox.transaction { transaction -> ([TelegramMediaFile], [(TelegramMediaFile, [String])]) in
            var gifFiles: [TelegramMediaFile] = []
            for entry in transaction.getOrderedListItems(collectionId: Namespaces.OrderedItemList.CloudRecentGifs) {
                if let item = entry.contents.get(RecentMediaItem.self) {
                    gifFiles.append(item.media._parse())
                }
            }
            var stickerFiles: [(TelegramMediaFile, [String])] = []
            for entry in transaction.getOrderedListItems(collectionId: Namespaces.OrderedItemList.CloudSavedStickers) {
                if let item = entry.contents.get(SavedStickerItem.self) {
                    stickerFiles.append((item.file._parse(), item.stringRepresentations))
                }
            }
            return (gifFiles, stickerFiles)
        }
        guard let (gifFiles, stickerFiles) = blockingFirst(listSignal, timeout: 30.0) else {
            return ([], [])
        }
        var gifs: [OtherMediaItem] = []
        for (index, file) in gifFiles.enumerated() {
            if isCancelled { break }
            let path = downloadOtherMedia(file, subdir: "other_data/gifs", index: index, contentType: .file, defaultExtension: "mp4")
            gifs.append(OtherMediaItem(relativePath: path, emojis: [], fileName: file.fileName ?? "gif_\(index).mp4"))
        }
        var stickers: [OtherMediaItem] = []
        for (index, entry) in stickerFiles.enumerated() {
            if isCancelled { break }
            let path = downloadOtherMedia(entry.0, subdir: "other_data/stickers", index: index, contentType: .sticker, defaultExtension: "webp")
            stickers.append(OtherMediaItem(relativePath: path, emojis: entry.1, fileName: entry.0.fileName ?? "sticker_\(index).webp"))
        }
        return (gifs, stickers)
    }

    private func downloadOtherMedia(_ file: TelegramMediaFile, subdir: String, index: Int, contentType: MediaResourceUserContentType, defaultExtension: String) -> String? {
        let mediaBox = context.account.postbox.mediaBox
        let reference = MediaResourceReference.standalone(resource: file.resource)
        let fetchDisposable = fetchedMediaResource(mediaBox: mediaBox, userLocation: .other, userContentType: contentType, reference: reference).start()
        let data = waitForResource(mediaBox: mediaBox, resource: file.resource, timeout: 60.0)
        fetchDisposable.dispose()
        guard let sourcePath = data?.path, FileManager.default.fileExists(atPath: sourcePath) else {
            return nil
        }
        let directory = baseURL.appendingPathComponent(subdir, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
        let baseName = (file.fileName).flatMap { $0.isEmpty ? nil : sanitize($0) } ?? "media_\(index).\(defaultExtension)"
        let safeName = "\(index)_\(baseName)"
        let destination = directory.appendingPathComponent(safeName)
        if !FileManager.default.fileExists(atPath: destination.path) {
            do {
                try FileManager.default.copyItem(atPath: sourcePath, toPath: destination.path)
            } catch {
                return nil
            }
        }
        return "\(subdir)/\(safeName)"
    }

    private func gatherFrequentContacts() -> [FrequentContact] {
        let botsSignal = context.account.postbox.transaction { transaction -> [(Peer, String, Double)] in
            var result: [(Peer, String, Double)] = []
            for entry in transaction.getOrderedListItems(collectionId: Namespaces.OrderedItemList.CloudRecentInlineBots) {
                let peerId = RecentPeerItemId(entry.id).peerId
                guard let peer = transaction.getPeer(peerId), let contents = entry.contents.get(RecentPeerItem.self) else {
                    continue
                }
                result.append((peer, "inline_bots", contents.rating))
            }
            return result
        }
        var raw = blockingFirst(botsSignal, timeout: 30.0) ?? []
        if let recent = blockingFirst(context.engine.peers.recentPeers() |> take(1), timeout: 30.0), case let .peers(peers) = recent {
            for peer in peers {
                raw.append((peer, "people", 0))
            }
        }
        var result: [FrequentContact] = []
        for (peer, category, rating) in raw {
            let name = peer.displayTitle
            let photoSrc = copyCachedAvatar(peer, fileName: "frequent_\(UInt64(bitPattern: peer.id.toInt64())).jpg")
            result.append(FrequentContact(name: name, category: category, rating: rating, colorIndex: colorIndexFor(peer.id), initials: initialsFor(name), photoSrc: photoSrc))
        }
        return result
    }

    private func gatherWebSessions(_ signal: Signal<WebSessionsContextState, NoError>) -> [WebAuthorization] {
        let ready = signal |> filter { !$0.isLoadingMore } |> take(1)
        guard let state = blockingFirst(ready, timeout: 30.0) else {
            return []
        }
        return state.sessions
    }

    private func isoDate(_ timestamp: Int32) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    // MARK: - Helpers

    private func destinationURL() -> URL {
        let root = URL(fileURLWithPath: settings.path, isDirectory: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let base = "Telegram_Export_" + formatter.string(from: Date())
        var candidate = root.appendingPathComponent(base, isDirectory: true)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = root.appendingPathComponent("\(base)_\(index)", isDirectory: true)
            index += 1
        }
        return candidate
    }

    private func waitForResource(mediaBox: MediaBox, resource: MediaResource, timeout: Double) -> MediaResourceData? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: MediaResourceData?
        let disposable = (mediaBox.resourceData(resource) |> filter { $0.complete } |> take(1)).start(next: { data in
            result = data
            semaphore.signal()
        })
        let deadline = Date().addingTimeInterval(timeout)
        while semaphore.wait(timeout: .now() + 0.2) == .timedOut {
            if isCancelled || Date() > deadline {
                disposable.dispose()
                return nil
            }
        }
        disposable.dispose()
        return result
    }

    private func formatDate(_ timestamp: Int32) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }

    private func colorIndexFor(_ peerId: PeerId) -> Int {
        return Int(UInt64(bitPattern: peerId.toInt64()) % 8)
    }

    private func colorIndexForInt(_ value: Int64) -> Int {
        return Int(UInt64(bitPattern: value) % 8)
    }

    private func blockingFirst<T>(_ signal: Signal<T, NoError>, timeout: Double) -> T? {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        let disposable = signal.start(next: { value in
            result = value
            semaphore.signal()
        }, completed: {
            semaphore.signal()
        })
        let deadline = timeout > 0 ? Date().addingTimeInterval(timeout) : Date.distantFuture
        while semaphore.wait(timeout: .now() + 0.2) == .timedOut {
            if isCancelled || Date() > deadline {
                disposable.dispose()
                return nil
            }
        }
        disposable.dispose()
        return result
    }
}
