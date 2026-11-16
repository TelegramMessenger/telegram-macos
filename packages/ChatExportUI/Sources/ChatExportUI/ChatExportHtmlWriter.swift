import Foundation
import Darwin
import Postbox
import TelegramCore

public enum ExportMediaRender {
    case photo(src: String?, width: Int?, height: Int?)
    case video(thumb: String?, src: String?, duration: String?, width: Int?, height: Int?)
    case gif(thumb: String?, src: String?)
    case roundVideo(thumb: String?, src: String?, duration: String?)
    case sticker(src: String?, width: Int?, height: Int?, emoji: String?)
    case voice(src: String?, status: String)
    case audio(src: String?, title: String, status: String)
    case file(src: String?, thumb: String?, title: String, status: String)
    case contact(name: String, phone: String)
    case location(latitude: Double, longitude: Double, title: String, address: String?)
    case poll(question: String, options: [String], total: String, closed: Bool, anonymous: Bool)
    case webpage(siteName: String?, title: String?, text: String?, url: String?, photo: String?, accent: String?)
    case unsupported(title: String, status: String?)
}

public struct ExportMessageModel {
    public var id: Int32
    public var timestamp: Int32
    public var authorId: PeerId?
    public var authorName: String
    public var colorIndex: Int
    public var initials: String
    public var textHtml: String
    public var forwardedFrom: String?
    public var replyToId: Int32?
    public var viaBot: String?
    public var editedSuffix: String?
    public var media: [ExportMediaRender]
    public var reactions: [(emoji: String, count: Int32)]
    public var signature: String?
    public var avatarSrc: String?

    public init(id: Int32, timestamp: Int32, authorId: PeerId?, authorName: String, colorIndex: Int, initials: String, textHtml: String, forwardedFrom: String?, replyToId: Int32?, viaBot: String?, editedSuffix: String?, media: [ExportMediaRender], reactions: [(emoji: String, count: Int32)], signature: String?, avatarSrc: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.authorId = authorId
        self.authorName = authorName
        self.colorIndex = colorIndex
        self.initials = initials
        self.textHtml = textHtml
        self.forwardedFrom = forwardedFrom
        self.replyToId = replyToId
        self.viaBot = viaBot
        self.editedSuffix = editedSuffix
        self.media = media
        self.reactions = reactions
        self.signature = signature
        self.avatarSrc = avatarSrc
    }
}

public final class ChatExportHtmlWriter {
    public let baseURL: URL
    private let chatName: String
    private let headerAvatarSrc: String?
    private let headerColorIndex: Int
    private let headerInitials: String
    private let headerSubtitle: String?
    private let messagesPerPage: Int
    private let themeColors: ExportThemeColors?

    private var currentPageIndex: Int = 0
    private var messagesInCurrentPage: Int = 0
    private var handle: FileHandle?

    private var lastAuthorId: PeerId?
    private var lastTimestamp: Int32 = 0
    private var lastDayKey: String = ""

    private let dayFormatter: DateFormatter
    private let dividerFormatter: DateFormatter
    private let timeFormatter: DateFormatter
    private let fullDateFormatter: DateFormatter

    public init(baseURL: URL, chatName: String, avatarSrc: String? = nil, colorIndex: Int = 0, initials: String = "", subtitle: String? = nil, messagesPerPage: Int = 5000, themeColors: ExportThemeColors? = nil) {
        self.baseURL = baseURL
        self.chatName = chatName
        self.headerAvatarSrc = avatarSrc
        self.headerColorIndex = colorIndex
        self.headerInitials = initials
        self.headerSubtitle = subtitle
        self.messagesPerPage = max(1, messagesPerPage)
        self.themeColors = themeColors

        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        self.dayFormatter = day

        let divider = DateFormatter()
        divider.dateFormat = "d MMMM yyyy"
        self.dividerFormatter = divider

        let time = DateFormatter()
        time.dateFormat = "HH:mm"
        self.timeFormatter = time

        let full = DateFormatter()
        full.dateFormat = "d MMMM yyyy, HH:mm:ss"
        self.fullDateFormatter = full
    }

    // MARK: - Lifecycle

    public func begin() throws {
        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true, attributes: nil)
        let cssDir = baseURL.appendingPathComponent("css")
        let jsDir = baseURL.appendingPathComponent("js")
        try FileManager.default.createDirectory(at: cssDir, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.createDirectory(at: jsDir, withIntermediateDirectories: true, attributes: nil)
        try (ChatExportHtmlWriter.styleCss(themeColors).data(using: .utf8) ?? Data()).write(to: cssDir.appendingPathComponent("style.css"))
        try (ChatExportHtmlWriter.scriptJs.data(using: .utf8) ?? Data()).write(to: jsDir.appendingPathComponent("script.js"))
        try openPage(0)
    }

    private func pageFileName(_ index: Int) -> String {
        return index == 0 ? "messages.html" : "messages\(index + 1).html"
    }

    private func headerAvatarHtml() -> String {
        if let src = headerAvatarSrc, !src.isEmpty {
            return "<img class=\"userpic\" style=\"width: 44px; height: 44px\" src=\"\(esc(src))\"/>\n"
        }
        let bucket = (headerColorIndex % 8) + 1
        return "<div class=\"userpic userpic\(bucket)\" style=\"width: 44px; height: 44px\">\n<div class=\"initials\" style=\"line-height: 44px\">\(esc(headerInitials))</div>\n</div>\n"
    }

    private func headerSubtitleHtml() -> String {
        guard let subtitle = headerSubtitle, !subtitle.isEmpty else {
            return ""
        }
        return "<div class=\"subtitle details\">\(esc(subtitle))</div>\n"
    }

    private func openPage(_ index: Int) throws {
        let url = baseURL.appendingPathComponent(pageFileName(index))
        guard FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
        let header = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(esc(chatName))</title>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <link href="css/style.css" rel="stylesheet">
        <script src="js/script.js" type="text/javascript"></script>
        </head>
        <body onload="CheckLocation();">
        <div class="page_wrap">
        <div class="page_header chat_header">
        <div class="content bubble">
        \(headerAvatarHtml())<div class="body">
        <div class="name bold">\(esc(chatName))</div>
        \(headerSubtitleHtml())</div>
        </div>
        </div>
        <div class="page_body chat_page">
        <div class="history">

        """
        try write(header)
        lastAuthorId = nil
    }

    private func closePage(hasNext: Bool) throws {
        defer {
            handle?.closeFile()
            handle = nil
        }
        var pagination = ""
        let hasPrev = currentPageIndex > 0
        if hasPrev || hasNext {
            pagination += "<div class=\"pagination\">\n"
            if hasPrev {
                pagination += "<a href=\"\(pageFileName(currentPageIndex - 1))\">Previous messages</a>"
            }
            if hasPrev && hasNext {
                pagination += " &nbsp; "
            }
            if hasNext {
                pagination += "<a href=\"\(pageFileName(currentPageIndex + 1))\">Next messages</a>"
            }
            pagination += "\n</div>\n"
        }
        let footer = """
        </div>
        \(pagination)</div>
        </div>
        </body>
        </html>
        """
        try write(footer)
    }

    public func finish() throws -> URL {
        try closePage(hasNext: false)
        return baseURL.appendingPathComponent(pageFileName(0))
    }

    // MARK: - Appending

    private func rolloverIfNeeded() throws {
        if messagesInCurrentPage >= messagesPerPage {
            try closePage(hasNext: true)
            currentPageIndex += 1
            messagesInCurrentPage = 0
            try openPage(currentPageIndex)
        }
    }

    private func insertDateDividerIfNeeded(_ timestamp: Int32) throws {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        let key = dayFormatter.string(from: date)
        if key != lastDayKey {
            lastDayKey = key
            let text = dividerFormatter.string(from: date)
            try writeServiceBlock(id: nil, html: esc(text))
            lastAuthorId = nil
        }
    }

    public func appendService(id: Int32?, html: String, timestamp: Int32) throws {
        try rolloverIfNeeded()
        try insertDateDividerIfNeeded(timestamp)
        try writeServiceBlock(id: id, html: html)
        lastAuthorId = nil
        lastTimestamp = timestamp
        messagesInCurrentPage += 1
    }

    private func writeServiceBlock(id: Int32?, html: String) throws {
        let idAttr = id.flatMap { " id=\"message\($0)\"" } ?? ""
        let block = "<div class=\"message service\"\(idAttr)>\n<div class=\"body details\">\n\(html)\n</div>\n</div>\n"
        try write(block)
    }

    public func appendMessage(_ message: ExportMessageModel) throws {
        try rolloverIfNeeded()
        try insertDateDividerIfNeeded(message.timestamp)

        let joined = message.authorId != nil
            && message.authorId == lastAuthorId
            && (message.timestamp - lastTimestamp) < 15 * 60

        var classes = "message default clearfix"
        if joined {
            classes += " joined"
        }

        var html = "<div class=\"\(classes)\" id=\"message\(message.id)\">\n"

        if !joined {
            if let avatar = message.avatarSrc, !avatar.isEmpty {
                html += """
                <div class="pull_left userpic_wrap">
                <img class="userpic" style="width: 42px; height: 42px" src="\(esc(avatar))"/>
                </div>

                """
            } else {
                html += """
                <div class="pull_left userpic_wrap">
                <div class="userpic userpic\(message.colorIndex + 1)" style="width: 42px; height: 42px">
                <div class="initials" style="line-height: 42px">
                \(esc(message.initials))
                </div>
                </div>
                </div>

                """
            }
        }

        html += "<div class=\"body\">\n"

        let dateTitle = esc(fullDateFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp))))
        let timeText = esc(timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(message.timestamp))))
        var dateInner = timeText
        if let edited = message.editedSuffix {
            dateInner = esc(edited) + " " + timeText
        }
        html += "<div class=\"pull_right date details\" title=\"\(dateTitle)\">\(dateInner)</div>\n"

        if !joined {
            var fromName = esc(message.authorName)
            if let via = message.viaBot {
                fromName += " <span class=\"details\">via @\(esc(via))</span>"
            }
            html += "<div class=\"from_name\">\n\(fromName)\n</div>\n"
        }

        if let forwarded = message.forwardedFrom {
            html += "<div class=\"forwarded_from details\">Forwarded from \(esc(forwarded))</div>\n"
        }

        if let replyId = message.replyToId {
            html += "<div class=\"reply_to details\">In reply to <a href=\"#go_to_message\(replyId)\" onclick=\"return GoToMessage(\(replyId))\">this message</a></div>\n"
        }

        for media in message.media {
            html += renderMedia(media)
        }

        if !message.textHtml.isEmpty {
            html += "<div class=\"text\">\n\(message.textHtml)\n</div>\n"
        }

        if let signature = message.signature, !signature.isEmpty {
            html += "<div class=\"signature details\">\(esc(signature))</div>\n"
        }

        if !message.reactions.isEmpty {
            html += "<div class=\"reactions\">\n"
            for reaction in message.reactions {
                html += "<span class=\"reaction\"><span class=\"emoji\">\(esc(reaction.emoji))</span><span class=\"count\">\(reaction.count)</span></span>\n"
            }
            html += "</div>\n"
        }

        html += "</div>\n</div>\n"

        try write(html)

        lastAuthorId = message.authorId
        lastTimestamp = message.timestamp
        messagesInCurrentPage += 1
    }

    // MARK: - Media rendering

    private func mediaBlock(type: String, href: String?, thumb: String?, title: String, description: String?, status: String?) -> String {
        let tag = href != nil ? "a" : "div"
        let hrefAttr = href != nil ? " href=\"\(esc(href!))\"" : ""
        let linkClass = href != nil ? " block_link" : ""
        var inner = ""
        if let thumb = thumb {
            inner += "<img class=\"thumb pull_left\" src=\"\(esc(thumb))\">\n"
        } else {
            inner += "<div class=\"fill pull_left\"></div>\n"
        }
        inner += "<div class=\"body\">\n<div class=\"title bold\">\(esc(title))</div>\n"
        if let description = description, !description.isEmpty {
            inner += "<div class=\"description\">\(esc(description))</div>\n"
        }
        if let status = status, !status.isEmpty {
            inner += "<div class=\"status details\">\(esc(status))</div>\n"
        }
        inner += "</div>\n"
        return """
        <div class="media_wrap clearfix">
        <\(tag) class="media clearfix pull_left\(linkClass) media_\(type)"\(hrefAttr)>
        \(inner)</\(tag)>
        </div>

        """
    }

    private func renderMedia(_ media: ExportMediaRender) -> String {
        switch media {
        case let .photo(src, width, height):
            if let src = src {
                let style = sizeStyle(width, height)
                return "<a class=\"photo_wrap clearfix pull_left\" href=\"\(esc(src))\"><img class=\"photo\" src=\"\(esc(src))\"\(style)></a>\n"
            }
            return mediaBlock(type: "photo", href: nil, thumb: nil, title: "Photo", description: nil, status: "Not included, change data exporting settings to download.")
        case let .video(thumb, src, duration, width, height):
            if let thumb = thumb {
                let style = sizeStyle(width, height)
                let durationHtml = duration.map { "<div class=\"video_duration details\">\(esc($0))</div>" } ?? ""
                let href = src ?? thumb
                return "<a class=\"video_file_wrap clearfix pull_left\" href=\"\(esc(href))\"><img class=\"video_file\" src=\"\(esc(thumb))\"\(style)><div class=\"video_play_bg\"><div class=\"video_play\"></div></div>\(durationHtml)</a>\n"
            }
            return mediaBlock(type: "video", href: src, thumb: nil, title: "Video", description: nil, status: duration ?? (src == nil ? "Not included, change data exporting settings to download." : nil))
        case let .gif(thumb, src):
            if let thumb = thumb {
                let href = src ?? thumb
                return "<a class=\"animated_wrap clearfix pull_left\" href=\"\(esc(href))\"><img class=\"animated\" src=\"\(esc(thumb))\"><div class=\"video_play_bg\"><div class=\"gif_play\">GIF</div></div></a>\n"
            }
            return mediaBlock(type: "video", href: src, thumb: nil, title: "GIF", description: nil, status: src == nil ? "Not included, change data exporting settings to download." : nil)
        case let .roundVideo(thumb, src, duration):
            if let thumb = thumb {
                let durationHtml = duration.map { "<div class=\"video_duration details\">\(esc($0))</div>" } ?? ""
                let href = src ?? thumb
                return "<a class=\"video_file_wrap clearfix pull_left round\" href=\"\(esc(href))\"><img class=\"video_file\" src=\"\(esc(thumb))\" style=\"border-radius: 50%\"><div class=\"video_play_bg\"><div class=\"video_play\"></div></div>\(durationHtml)</a>\n"
            }
            return mediaBlock(type: "video", href: src, thumb: nil, title: "Video message", description: nil, status: duration)
        case let .sticker(src, width, height, emoji):
            if let src = src {
                let style = sizeStyle(width ?? 128, height ?? 128)
                return "<a class=\"sticker_wrap clearfix pull_left\" href=\"\(esc(src))\"><img class=\"sticker\" src=\"\(esc(src))\"\(style)></a>\n"
            }
            return mediaBlock(type: "photo", href: nil, thumb: nil, title: "Sticker\(emoji.map { " \($0)" } ?? "")", description: nil, status: nil)
        case let .voice(src, status):
            return mediaBlock(type: "voice_message", href: src, thumb: nil, title: "Voice message", description: nil, status: status)
        case let .audio(src, title, status):
            return mediaBlock(type: "audio_file", href: src, thumb: nil, title: title, description: nil, status: status)
        case let .file(src, thumb, title, status):
            return mediaBlock(type: "file", href: src, thumb: thumb, title: title, description: nil, status: status)
        case let .contact(name, phone):
            return mediaBlock(type: "contact", href: nil, thumb: nil, title: name, description: nil, status: phone)
        case let .location(latitude, longitude, title, address):
            let coords = String(format: "%.6f, %.6f", latitude, longitude)
            let href = "https://maps.google.com/?q=\(latitude),\(longitude)"
            let status = address.map { "\($0)\n\(coords)" } ?? coords
            return mediaBlock(type: "location", href: href, thumb: nil, title: title, description: nil, status: status)
        case let .poll(question, options, total, closed, anonymous):
            var poll = "<div class=\"media_wrap clearfix\">\n<div class=\"media_poll\">\n<div class=\"question bold\">\(esc(question))</div>\n"
            var details: [String] = []
            details.append(anonymous ? "Anonymous poll" : "Poll")
            if closed {
                details.append("Final results")
            }
            poll += "<div class=\"details\">\(esc(details.joined(separator: ", ")))</div>\n"
            for option in options {
                poll += "<div class=\"answer\">- \(esc(option))</div>\n"
            }
            poll += "<div class=\"total details\">\(esc(total))</div>\n</div>\n</div>\n"
            return poll
        case let .webpage(siteName, title, text, url, photo, accent):
            let accentStyle = (accent.flatMap { $0.isEmpty ? nil : $0 }).map { " style=\"border-left-color: \(esc($0))\"" } ?? ""
            var body = ""
            if let photo = photo, !photo.isEmpty {
                body += "<img class=\"webpage_photo pull_right\" src=\"\(esc(photo))\"/>\n"
            }
            if let siteName = siteName, !siteName.isEmpty {
                let siteStyle = (accent.flatMap { $0.isEmpty ? nil : $0 }).map { " style=\"color: \(esc($0))\"" } ?? ""
                body += "<div class=\"webpage_site\"\(siteStyle)>\(esc(siteName))</div>\n"
            }
            if let title = title, !title.isEmpty {
                body += "<div class=\"webpage_title bold\">\(esc(title))</div>\n"
            }
            if let text = text, !text.isEmpty {
                body += "<div class=\"webpage_description\">\(esc(text))</div>\n"
            }
            if let url = url.flatMap({ $0.isEmpty ? nil : ChatExportHtmlWriter.safeHref($0) }) {
                return "<div class=\"media_wrap clearfix\">\n<a class=\"webpage_preview clearfix\" href=\"\(esc(url))\"\(accentStyle)>\n\(body)</a>\n</div>\n"
            }
            return "<div class=\"media_wrap clearfix\">\n<div class=\"webpage_preview clearfix\"\(accentStyle)>\n\(body)</div>\n</div>\n"
        case let .unsupported(title, status):
            return mediaBlock(type: "file", href: nil, thumb: nil, title: title, description: nil, status: status)
        }
    }

    private func sizeStyle(_ width: Int?, _ height: Int?) -> String {
        guard let width = width, let height = height, width > 0, height > 0 else {
            return ""
        }
        let maxSide: Double = 320
        let w = Double(width)
        let h = Double(height)
        let scale = min(1.0, min(maxSide / w, maxSide / h))
        return " style=\"width: \(Int(w * scale))px; height: \(Int(h * scale))px\""
    }

    // MARK: - Text

    public static func textEntitiesJSON(text: String, entities: [MessageTextEntity]) -> [[String: Any]] {
        if text.isEmpty {
            return []
        }
        let ns = text as NSString
        let length = ns.length

        var boundaries = Set<Int>([0, length])
        for entity in entities {
            let lower = max(0, min(length, entity.range.lowerBound))
            let upper = max(0, min(length, entity.range.upperBound))
            if lower < upper {
                boundaries.insert(lower)
                boundaries.insert(upper)
            }
        }
        let sorted = boundaries.sorted()

        var runs: [[String: Any]] = []
        var i = 0
        while i < sorted.count - 1 {
            let start = sorted[i]
            let end = sorted[i + 1]
            i += 1
            if start >= end {
                continue
            }
            let piece = ns.substring(with: NSRange(location: start, length: end - start))
            let active = entities.filter { $0.range.lowerBound <= start && $0.range.upperBound >= end }
            guard let entity = active.last else {
                runs.append(["type": "plain", "text": piece])
                continue
            }
            var object: [String: Any] = ["text": piece]
            switch entity.type {
            case .Bold:
                object["type"] = "bold"
            case .Italic:
                object["type"] = "italic"
            case .Underline:
                object["type"] = "underline"
            case .Strikethrough:
                object["type"] = "strikethrough"
            case .Spoiler:
                object["type"] = "spoiler"
            case .BlockQuote:
                object["type"] = "blockquote"
            case .Code:
                object["type"] = "code"
            case let .Pre(language):
                object["type"] = "pre"
                if let language = language, !language.isEmpty {
                    object["language"] = language
                }
            case let .TextUrl(url):
                object["type"] = "text_link"
                object["href"] = url
            case .Url:
                object["type"] = "link"
            case .Email:
                object["type"] = "email"
            case .PhoneNumber:
                object["type"] = "phone"
            case .Mention:
                object["type"] = "mention"
            case let .TextMention(peerId):
                object["type"] = "mention_name"
                object["user_id"] = peerId.toInt64()
            case .Hashtag:
                object["type"] = "hashtag"
            case .BotCommand:
                object["type"] = "bot_command"
            case .BankCard:
                object["type"] = "bank_card"
            case let .CustomEmoji(_, fileId):
                object["type"] = "custom_emoji"
                object["document_id"] = fileId
            default:
                object["type"] = "plain"
            }
            runs.append(object)
        }
        return runs
    }

    public static func renderInstantPage(_ page: InstantPage) -> String {
        return richBlocksToHtml(page.blocks)
    }

    private static func richBlocksToHtml(_ blocks: [InstantPageBlock]) -> String {
        return blocks.map { richBlockToHtml($0) }.joined()
    }

    private static func richBlockToHtml(_ block: InstantPageBlock) -> String {
        switch block {
        case let .title(text):
            return "<h1>\(richToHtml(text))</h1>\n"
        case let .subtitle(text):
            return "<h3>\(richToHtml(text))</h3>\n"
        case let .header(text):
            return "<h2>\(richToHtml(text))</h2>\n"
        case let .subheader(text):
            return "<h3>\(richToHtml(text))</h3>\n"
        case let .kicker(text):
            return "<h4>\(richToHtml(text))</h4>\n"
        case let .heading(text, level):
            let clamped = max(1, min(6, Int(level)))
            return "<h\(clamped)>\(richToHtml(text))</h\(clamped)>\n"
        case let .paragraph(text):
            let html = richToHtml(text)
            return html.isEmpty ? "" : "<p>\(html)</p>\n"
        case let .thinking(text):
            let html = richToHtml(text)
            return html.isEmpty ? "" : "<p class=\"details\">\(html)</p>\n"
        case let .footer(text):
            let html = richToHtml(text)
            return html.isEmpty ? "" : "<p class=\"details\">\(html)</p>\n"
        case let .authorDate(author, _):
            let html = richToHtml(author)
            return html.isEmpty ? "" : "<p class=\"details\">\(html)</p>\n"
        case let .preformatted(text, _):
            return "<pre>\(richEscape(text.plainText))</pre>\n"
        case let .formula(latex):
            return "<pre>\(richEscape(latex))</pre>\n"
        case .divider:
            return "<hr>\n"
        case let .list(items, ordered):
            let tag = ordered ? "ol" : "ul"
            var inner = ""
            for item in items {
                switch item {
                case .unknown:
                    break
                case let .text(text, _, checked):
                    inner += "<li>\(richListPrefix(checked))\(richToHtml(text))</li>\n"
                case let .blocks(blocks, _, checked):
                    inner += "<li>\(richListPrefix(checked))\(richBlocksToHtml(blocks))</li>\n"
                }
            }
            return "<\(tag)>\n\(inner)</\(tag)>\n"
        case let .blockQuote(blocks, caption, _):
            var inner = richBlocksToHtml(blocks)
            let cap = richToHtml(caption)
            if !cap.isEmpty {
                inner += "<p class=\"details\">\(cap)</p>\n"
            }
            return "<blockquote>\n\(inner)</blockquote>\n"
        case let .pullQuote(text, caption):
            var inner = "<p>\(richToHtml(text))</p>\n"
            let cap = richToHtml(caption)
            if !cap.isEmpty {
                inner += "<p class=\"details\">\(cap)</p>\n"
            }
            return "<blockquote>\n\(inner)</blockquote>\n"
        case let .table(title, rows, _, _, _):
            var html = ""
            let heading = richToHtml(title)
            if !heading.isEmpty {
                html += "<h4>\(heading)</h4>\n"
            }
            html += "<table>\n"
            for row in rows {
                html += "<tr>\n"
                for cell in row.cells {
                    let tag = cell.header ? "th" : "td"
                    var attributes = ""
                    if cell.colspan > 1 {
                        attributes += " colspan=\"\(cell.colspan)\""
                    }
                    if cell.rowspan > 1 {
                        attributes += " rowspan=\"\(cell.rowspan)\""
                    }
                    let content = cell.text.map { richToHtml($0) } ?? ""
                    html += "<\(tag)\(attributes)>\(content)</\(tag)>\n"
                }
                html += "</tr>\n"
            }
            html += "</table>\n"
            return html
        case let .details(title, blocks, expanded):
            let open = expanded ? " open" : ""
            return "<details\(open)>\n<summary>\(richToHtml(title))</summary>\n\(richBlocksToHtml(blocks))</details>\n"
        case let .cover(inner):
            return richBlockToHtml(inner)
        default:
            return ""
        }
    }

    private static func richListPrefix(_ checked: Bool?) -> String {
        guard let checked = checked else {
            return ""
        }
        return checked ? "&#9745; " : "&#9744; "
    }

    private static func richToHtml(_ text: RichText) -> String {
        switch text {
        case .empty:
            return ""
        case let .plain(string):
            return richEscape(string).replacingOccurrences(of: "\n", with: "<br>")
        case let .bold(inner):
            return "<strong>\(richToHtml(inner))</strong>"
        case let .italic(inner):
            return "<em>\(richToHtml(inner))</em>"
        case let .underline(inner):
            return "<u>\(richToHtml(inner))</u>"
        case let .strikethrough(inner):
            return "<s>\(richToHtml(inner))</s>"
        case let .fixed(inner):
            return "<code>\(richToHtml(inner))</code>"
        case let .url(inner, url, _):
            guard let href = safeHref(url) else {
                return richToHtml(inner)
            }
            return "<a href=\"\(richEscapeAttribute(href))\">\(richToHtml(inner))</a>"
        case let .email(inner, email):
            return "<a href=\"mailto:\(richEscapeAttribute(email))\">\(richToHtml(inner))</a>"
        case let .phone(inner, phone):
            return "<a href=\"tel:\(richEscapeAttribute(phone))\">\(richToHtml(inner))</a>"
        case let .concat(parts):
            return parts.map { richToHtml($0) }.joined()
        case let .subscript(inner):
            return "<sub>\(richToHtml(inner))</sub>"
        case let .superscript(inner):
            return "<sup>\(richToHtml(inner))</sup>"
        case let .marked(inner):
            return "<mark>\(richToHtml(inner))</mark>"
        case let .anchor(inner, _):
            return richToHtml(inner)
        case let .formula(latex):
            return "<code>\(richEscape(latex))</code>"
        case let .textCustomEmoji(_, alt):
            return richEscape(alt)
        case let .textAutoUrl(inner):
            guard let href = safeHref(inner.plainText) else {
                return richToHtml(inner)
            }
            return "<a href=\"\(richEscapeAttribute(href))\">\(richToHtml(inner))</a>"
        case let .textAutoEmail(inner):
            return "<a href=\"mailto:\(richEscapeAttribute(inner.plainText))\">\(richToHtml(inner))</a>"
        case let .textAutoPhone(inner):
            return "<a href=\"tel:\(richEscapeAttribute(inner.plainText))\">\(richToHtml(inner))</a>"
        case let .textSpoiler(inner):
            return "<span class=\"spoiler hidden\" onclick=\"ShowSpoiler(this)\"><span>\(richToHtml(inner))</span></span>"
        case let .textBankCard(inner):
            return richToHtml(inner)
        case let .textTonAddress(inner):
            return richToHtml(inner)
        case let .textBotCommand(inner):
            return richToHtml(inner)
        case let .textCashtag(inner):
            return richToHtml(inner)
        case let .textHashtag(inner):
            return richToHtml(inner)
        case let .textMention(inner):
            return richToHtml(inner)
        case let .textMentionName(inner, _):
            return richToHtml(inner)
        case let .textDate(inner, _, _):
            return richToHtml(inner)
        case let .textButton(button):
            return richToHtml(button.text)
        default:
            return ""
        }
    }

    private static func richEscape(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        return result
    }

    private static func richEscapeAttribute(_ string: String) -> String {
        return richEscape(string).replacingOccurrences(of: "\"", with: "&quot;")
    }

    public static func renderEntities(text: String, entities: [MessageTextEntity]) -> String {
        if text.isEmpty {
            return ""
        }
        let ns = text as NSString
        let length = ns.length

        var boundaries = Set<Int>([0, length])
        for entity in entities {
            let lower = max(0, min(length, entity.range.lowerBound))
            let upper = max(0, min(length, entity.range.upperBound))
            if lower < upper {
                boundaries.insert(lower)
                boundaries.insert(upper)
            }
        }
        let sorted = boundaries.sorted()

        var result = ""
        var i = 0
        while i < sorted.count - 1 {
            let start = sorted[i]
            let end = sorted[i + 1]
            i += 1
            if start >= end {
                continue
            }
            let substring = ns.substring(with: NSRange(location: start, length: end - start))
            let active = entities.filter { $0.range.lowerBound <= start && $0.range.upperBound >= end }
            result += wrapSegment(substring, entities: active)
        }
        return result
    }

    private static func wrapSegment(_ raw: String, entities: [MessageTextEntity]) -> String {
        var isPre = false
        var preLanguage: String? = nil
        var isCode = false
        for entity in entities {
            switch entity.type {
            case let .Pre(language):
                isPre = true
                preLanguage = language
            case .Code:
                isCode = true
            default:
                break
            }
        }

        var content: String
        if isPre {
            content = escapePlain(raw, convertNewlines: false)
        } else if isCode {
            content = escapePlain(raw, convertNewlines: false)
        } else {
            content = escapePlain(raw, convertNewlines: true)
        }

        var openTags: [String] = []
        var closeTags: [String] = []

        func wrap(_ open: String, _ close: String) {
            openTags.append(open)
            closeTags.insert(close, at: 0)
        }

        for entity in entities {
            switch entity.type {
            case .Bold:
                wrap("<strong>", "</strong>")
            case .Italic:
                wrap("<em>", "</em>")
            case .Underline:
                wrap("<u>", "</u>")
            case .Strikethrough:
                wrap("<s>", "</s>")
            case .Spoiler:
                wrap("<span class=\"spoiler hidden\" onclick=\"ShowSpoiler(this)\"><span>", "</span></span>")
            case .BlockQuote:
                wrap("<blockquote>", "</blockquote>")
            case let .TextUrl(url):
                if let href = safeHref(url) {
                    wrap("<a href=\"\(escapeAttribute(href))\">", "</a>")
                }
            case .Url:
                if let href = safeHref(normalizeUrl(raw)) {
                    wrap("<a href=\"\(escapeAttribute(href))\">", "</a>")
                }
            case .Email:
                wrap("<a href=\"mailto:\(escapeAttribute(raw))\">", "</a>")
            case .PhoneNumber:
                wrap("<a href=\"tel:\(escapeAttribute(raw.replacingOccurrences(of: " ", with: "")))\">", "</a>")
            case .Mention:
                let username = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
                wrap("<a href=\"https://t.me/\(escapeAttribute(username))\">", "</a>")
            case .TextMention:
                wrap("<a onclick=\"return ShowMentionName()\" href=\"#\">", "</a>")
            case .Hashtag:
                let tag = raw.hasPrefix("#") ? String(raw.dropFirst()) : raw
                wrap("<a onclick=\"return ShowHashtag('\(escapeAttribute(escapeJavaScriptString(tag)))')\" href=\"#\">", "</a>")
            case .BotCommand:
                let command = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
                wrap("<a onclick=\"return ShowBotCommand('\(escapeAttribute(escapeJavaScriptString(command)))')\" href=\"#\">", "</a>")
            default:
                break
            }
        }

        if isCode && !isPre {
            content = "<code>\(content)</code>"
        }
        if isPre {
            let langClass = preLanguage.flatMap { $0.isEmpty ? nil : " class=\"language-\(escapeAttribute($0))\"" } ?? ""
            content = "<pre><code\(langClass)>\(content)</code></pre>"
        }

        return openTags.joined() + content + closeTags.joined()
    }

    private static func normalizeUrl(_ raw: String) -> String {
        if raw.contains("://") || raw.hasPrefix("mailto:") || raw.hasPrefix("tel:") {
            return raw
        }
        return "http://" + raw
    }

    // MARK: - Escaping

    private func esc(_ string: String) -> String {
        return ChatExportHtmlWriter.escapePlain(string, convertNewlines: false)
    }

    static func escapePlain(_ string: String, convertNewlines: Bool) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        if convertNewlines {
            result = result.replacingOccurrences(of: "\r\n", with: "\n")
            result = result.replacingOccurrences(of: "\n", with: "<br>")
        }
        return result
    }

    static func escapeAttribute(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "&", with: "&amp;")
        result = result.replacingOccurrences(of: "<", with: "&lt;")
        result = result.replacingOccurrences(of: ">", with: "&gt;")
        result = result.replacingOccurrences(of: "\"", with: "&quot;")
        result = result.replacingOccurrences(of: "'", with: "&#39;")
        return result
    }

    static func escapeJavaScriptString(_ string: String) -> String {
        var result = string
        result = result.replacingOccurrences(of: "\\", with: "\\\\")
        result = result.replacingOccurrences(of: "'", with: "\\'")
        result = result.replacingOccurrences(of: "\"", with: "\\\"")
        result = result.replacingOccurrences(of: "\n", with: "\\n")
        result = result.replacingOccurrences(of: "\r", with: "\\r")
        result = result.replacingOccurrences(of: "<", with: "\\x3C")
        result = result.replacingOccurrences(of: ">", with: "\\x3E")
        result = result.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
        result = result.replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return result
    }

    private static let safeHrefSchemes: Set<String> = ["http", "https", "tg", "ton", "tonsite", "mailto", "tel"]

    static func safeHref(_ url: String) -> String? {
        let normalized = String(String.UnicodeScalarView(url.unicodeScalars.filter { $0.value > 0x20 && $0.value != 0x7F })).lowercased()
        guard let delimiter = normalized.firstIndex(where: { $0 == ":" || $0 == "/" || $0 == "?" || $0 == "#" }), normalized[delimiter] == ":" else {
            return url
        }
        let scheme = String(normalized[normalized.startIndex ..< delimiter])
        return safeHrefSchemes.contains(scheme) ? url : nil
    }

    // MARK: - IO

    private func write(_ string: String) throws {
        guard let handle else {
            throw CocoaError(.fileWriteUnknown)
        }
        try Data(string.utf8).withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else {
                return
            }
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(handle.fileDescriptor, baseAddress.advanced(by: offset), bytes.count - offset)
                if written > 0 {
                    offset += written
                } else if written < 0 && errno == EINTR {
                    continue
                } else {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(written < 0 ? errno : EIO))
                }
            }
        }
    }
}
