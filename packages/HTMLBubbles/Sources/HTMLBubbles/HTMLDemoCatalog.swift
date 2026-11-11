import Foundation
import Postbox
import TelegramCore
import LiteHTML
import Localization

public struct HTMLDemoCommand {
    public let command: String
    public let description: String
    public let conversationId: String
    public let messageIndices: [Int]
}

public enum HTMLDemoPreset {
    case allWidgets
    case voxelClash
}

public final class HTMLDemoChat {
    public let id: String
    public let title: String
    public let status: String
    public let peer: Peer
    public let engine: HTMLRenderEngine
    public let preset: HTMLDemoPreset?

    init(id: String, title: String, status: String, peer: Peer, engine: HTMLRenderEngine, preset: HTMLDemoPreset? = nil) {
        self.id = id
        self.title = title
        self.status = status
        self.peer = peer
        self.engine = engine
        self.preset = preset
    }

    public var previewText: String {
        if preset != nil {
            return status
        }
        return strings().htmlDemoCatalogTypeToPick
    }
}

public final class HTMLDemoWidgetFile {
    public let name: String
    public let html: String
    private let lock = NSLock()
    private var cachedSummary: HTMLBubbleSummary?

    init(name: String, html: String) {
        self.name = name
        self.html = html
    }

    var summary: HTMLBubbleSummary {
        lock.lock()
        defer { lock.unlock() }
        if let summary = cachedSummary {
            return summary
        }
        let summary = HTMLBubbleSummary(html)
        cachedSummary = summary
        return summary
    }
}

public enum HTMLDemoCatalog {
    public static let botChatId = "html-bot"

    static var fixturesRoot: URL?

    private static func fixture(_ name: String) -> URL? {
        return fixturesRoot?.appendingPathComponent(name)
    }

    public static let conversations: [HTMLDemoConversation] = {
        LHImages.registerDemoImages()
        return HTMLDemoConversation.load(from: fixture("chats"))
    }()

    private static let table: [(String, String, String, [Int])] = [
        ("chicken", "Chicken Cross, a 3D game: hop across the roads", "13-3d-lab", [0]),
        ("three", "three.js scene drawn with Metal", "13-3d-lab", [1]),
        ("chess3d", "3D chess against the bot", "13-3d-lab", [2]),
        ("easing", "Easing curves, animated by a script", "12-motion-lab", [1]),
        ("launch", "Release card with falling confetti", "12-motion-lab", [2]),
        ("music", "Music player with a live equalizer", "12-motion-lab", [4]),
        ("pipeline", "Deploy pipeline that runs step by step", "12-motion-lab", [5]),
        ("streaming", "A reply that types itself, like an AI", "12-motion-lab", [7]),
        ("clock", "Live clock", "12-motion-lab", [8]),
        ("linkpreview", "Link preview that shimmers, then loads", "12-motion-lab", [9]),
        ("reactions", "Live reactions from the audience", "12-motion-lab", [10]),
        ("activity", "Activity rings that fill up", "12-motion-lab", [11]),
        ("slots", "Slot machine", "12-motion-lab", [12]),
        ("counter", "Counter with buttons", "11-live-scripts", [1]),
        ("vote", "Live vote, click again to take it back", "11-live-scripts", [2, 3]),
        ("tictactoe", "Tic-tac-toe against the bot", "11-live-scripts", [5]),
        ("whack", "Whack-a-mole", "11-live-scripts", [6]),
        ("stopwatch", "Stopwatch", "11-live-scripts", [9]),
        ("dice", "Dice that really roll", "11-live-scripts", [10]),
        ("sandbox", "Runaway scripts the sandbox stops", "11-live-scripts", [12, 13, 14, 15, 16]),
        ("chess", "Chess board", "10-game-night", [1]),
        ("quiz", "Quiz, pick an answer", "10-game-night", [2]),
        ("sudoku", "Sudoku", "10-game-night", [8]),
        ("pixelart", "Pixel art made of divs", "10-game-night", [7]),
        ("calendar", "Month calendar", "10-game-night", [4]),
        ("playlist", "Music player with a playlist", "10-game-night", [5]),
        ("recipe", "Recipe with servings and ingredients", "10-game-night", [6]),
        ("poll", "Poll, click to vote", "01-design-crew", [7]),
        ("invite", "Meeting invite with Accept and Decline", "01-design-crew", [11]),
        ("sprint", "Sprint board", "01-design-crew", [3]),
        ("build", "CI build with Promote, Logs and Roll back", "02-deploy-bot", [0]),
        ("environments", "Environments status table", "02-deploy-bot", [2]),
        ("playground", "Ask for a table, a card or a chart", "04-playground", [0, 1]),
        ("boardingpass", "Boarding pass", "06-trip-lisbon", [1]),
        ("itinerary", "Itinerary with day tabs", "06-trip-lisbon", [3]),
        ("weather", "Weather forecast", "06-trip-lisbon", [4]),
        ("hotel", "Hotel booking", "06-trip-lisbon", [6]),
        ("expenses", "Shared trip expenses", "06-trip-lisbon", [8]),
        ("packing", "Packing list, click to tick", "06-trip-lisbon", [9]),
        ("lunch", "Pick a place for lunch", "06-trip-lisbon", [10]),
        ("phrasebook", "Phrasebook, hover a row", "06-trip-lisbon", [11]),
        ("product", "Product page with size and colour", "07-shop", [3]),
        ("receipt", "Order receipt", "07-shop", [5]),
        ("tracking", "Order tracking", "07-shop", [6]),
        ("reviews", "Product reviews", "07-shop", [7]),
        ("coupon", "Discount coupon", "07-shop", [9]),
        ("kpis", "Key numbers for the week", "08-analytics", [1]),
        ("revenue", "Revenue chart, hover a column", "08-analytics", [2]),
        ("heatmap", "Deploys heatmap", "08-analytics", [5]),
        ("funnel", "Conversion funnel", "08-analytics", [7]),
        ("retention", "Retention by cohort", "08-analytics", [8]),
        ("leaderboard", "Sales leaderboard", "08-analytics", [9]),
        ("pr", "Pull request with Approve", "09-code-review", [0]),
        ("diff", "Code diff", "09-code-review", [1]),
        ("terminal", "Terminal output", "09-code-review", [3]),
        ("json", "Collapsible JSON", "09-code-review", [4]),
        ("api", "API docs with language tabs", "09-code-review", [6]),
        ("crash", "Crash report", "09-code-review", [7]),
        ("shortcuts", "Keyboard shortcuts", "09-code-review", [8]),
        ("article", "Long article", "05-long-reads", [0]),
        ("releasenotes", "Release notes with Show all", "05-long-reads", [2]),
        ("faq", "FAQ, click a question", "05-long-reads", [3]),
        ("poem", "A poem", "05-long-reads", [6]),
        ("typography", "Headings, sizes and weights", "03-stress-test", [0]),
        ("table", "Table with rowspan and colspan", "03-stress-test", [5]),
        ("flexbox", "Flexbox layouts", "03-stress-test", [11]),
        ("images", "Images and SF Symbols", "03-stress-test", [15]),
    ]

    private static let featured: [String] = ["chicken", "chess3d", "three", "streaming", "slots", "tictactoe", "chess", "poll", "boardingpass", "product", "revenue", "pr", "faq"]

    public static let commands: [HTMLDemoCommand] = table.map {
        HTMLDemoCommand(command: $0.0, description: $0.1, conversationId: $0.2, messageIndices: $0.3)
    }

    static let statsCommand = "stats"

    public static var botCommands: [BotCommand] {
        return [BotCommand(text: statsCommand, description: strings().htmlDemoCatalogStatsCommandDescription)] + commands.map {
            BotCommand(text: $0.command, description: $0.description)
        }
    }

    public static func command(_ text: String) -> HTMLDemoCommand? {
        return commands.first(where: { $0.command == text })
    }

    public static func conversation(_ id: String) -> HTMLDemoConversation? {
        return conversations.first(where: { $0.id == id })
    }

    public static let chats: [HTMLDemoChat] = {
        guard fixturesRoot != nil else {
            return []
        }
        DispatchQueue.global(qos: .utility).async {
            HTMLBubbleState.prewarmLibraries()
            for file in widgetFiles(.allWidgets) {
                _ = file.summary
            }
        }
        let title = strings().htmlDemoCatalogAllWidgets
        let status = strings().htmlDemoCatalogWidgetsCountOther(widgetFiles(.allWidgets).count)
        let webKitTitle = strings().htmlDemoCatalogAllWidgetsWebKit
        var chats: [HTMLDemoChat] = []
        // if #available(macOS 10.15, *) {
        //     chats.append(HTMLDemoChat(id: "html-voxel-clash", title: "Voxel Clash", status: "The floating kingdoms · live multiplayer", peer: makeUser(index: 9, name: "Voxel Clash", isBot: true), engine: .twidget, preset: .voxelClash))
        // }
        chats += [
            HTMLDemoChat(id: "html-all-widgets", title: title, status: status, peer: makeUser(index: 6, name: title, isBot: true), engine: .twidget, preset: .allWidgets),
            HTMLDemoChat(id: "html-all-widgets-webkit", title: webKitTitle, status: status, peer: makeUser(index: 7, name: webKitTitle, isBot: true), engine: .webKit, preset: .allWidgets),
        ]
        return chats
    }()

    private static let sandboxGroups = ["showcase", "generated", "common", "compat"]

    private static func htmlFiles(in directory: URL, prefix: String) -> [HTMLDemoWidgetFile] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil) else {
            return []
        }
        var files: [(String, URL)] = []
        for case let url as URL in enumerator where url.pathExtension == "html" {
            let relative = String(url.path.dropFirst(directory.path.count + 1))
            files.append((prefix + relative, url))
        }
        return files.sorted { $0.0 < $1.0 }.compactMap { name, url in
            (try? String(contentsOf: url, encoding: .utf8)).map { HTMLDemoWidgetFile(name: name, html: $0) }
        }
    }

    private static let sandboxFiles: [HTMLDemoWidgetFile] = {
        guard let root = fixture("widget-sandbox") else {
            return []
        }
        return sandboxGroups.flatMap { htmlFiles(in: root.appendingPathComponent($0), prefix: $0 + "/") }
    }()

    private static let portedFiles: [HTMLDemoWidgetFile] = {
        guard let root = fixture("ported") else {
            return []
        }
        return htmlFiles(in: root, prefix: "ported/")
    }()

    private static let allWidgetFiles: [HTMLDemoWidgetFile] = {
        let files = portedFiles + sandboxFiles
        let stress = files.filter { $0.name.contains("/stress/") }
        return files.filter { !$0.name.contains("/stress/") } + stress
    }()

    public static func widgetFiles(_ preset: HTMLDemoPreset) -> [HTMLDemoWidgetFile] {
        switch preset {
        case .allWidgets:
            return allWidgetFiles
        case .voxelClash:
            guard let url = fixture("multiplayer")?.appendingPathComponent("voxel-clash.html"), let html = try? String(contentsOf: url, encoding: .utf8) else {
                return []
            }
            return [HTMLDemoWidgetFile(name: "Build your kingdom. Invite a rival. Share the battle live. /rival opens another signed-in account.", html: html)]
        }
    }

    public static func chat(_ id: String) -> HTMLDemoChat? {
        return chats.first(where: { $0.id == id })
    }

    private static let peerIdBase: Int64 = 4_000_000_000_000

    static func makeUser(index: Int, name: String, isBot: Bool) -> TelegramUser {
        return makeUser(id: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(peerIdBase + Int64(index) * 100 + 7)), name: name, isBot: isBot)
    }

    static func makeUser(id: PeerId, name: String, isBot: Bool) -> TelegramUser {
        let parts = name.components(separatedBy: " ")
        let first = parts.first ?? name
        let last = parts.dropFirst().joined(separator: " ")
        return TelegramUser(id: id, accessHash: nil, firstName: first, lastName: last, username: nil, phone: nil, photo: [], botInfo: isBot ? BotUserInfo(flags: [], inlinePlaceholder: nil) : nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
    }

    static func welcomeHTML(engine: HTMLRenderEngine) -> String {
        let chips = featured.map { command in
            "<a class=\"chip\" href=\"chat:send?text=/\(command)\">/\(command)</a>"
        }.joined(separator: " ")
        let logo = engine == .litehtml || engine == .litehtmlGPU || engine == .litehtmlBefore ? "<img src=\"data:image/svg+xml,%3Csvg%20xmlns=%27http://www.w3.org/2000/svg%27%20width=%2764%27%20height=%2764%27%20viewBox=%270%200%2064%2064%27%3E%3Cdefs%3E%3ClinearGradient%20id=%27g%27%20x1=%270%27%20y1=%271%27%20x2=%271%27%20y2=%270%27%3E%3Cstop%20offset=%270%27%20stop-color=%27%237f5af0%27/%3E%3Cstop%20offset=%271%27%20stop-color=%27%232cb67d%27/%3E%3C/linearGradient%3E%3C/defs%3E%3Crect%20width=%2764%27%20height=%2764%27%20rx=%2714%27%20fill=%27url%28%23g%29%27/%3E%3Cpath%20d=%27M24.5%2024.5L16%2032L24.5%2039.5M39.5%2024.5L48%2032L39.5%2039.5M35.5%2022L28.5%2042%27%20fill=%27none%27%20stroke=%27%23ffffff%27%20stroke-width=%273.6%27%20stroke-linecap=%27round%27%20stroke-linejoin=%27round%27/%3E%3C/svg%3E\" style=\"width: 44px; height: 44px; margin-right: 12px\">" : ""
        return """
        <div class="card pad" style="width: 380px; max-width: 100%">
          <div class="row">
            \(logo)
            <div class="grow">
              <div style="font-size: 17px; font-weight: 700">HTML Bot</div>
              <div class="muted small">Every reply is HTML + CSS, rendered by \(engine.title). No network.</div>
            </div>
          </div>
          <div class="sep" style="margin: 12px 0 8px 0"></div>
          <div>Type <b>/</b> to pick one of \(commands.count) messages, and I'll send it to you. Each one is a small app: click around and it changes in place, with animation.</div>
          <div class="caps" style="margin-top: 10px">Try these</div>
          <div style="margin-top: 4px">\(chips)</div>
          <div class="muted small" style="margin-top: 8px">Or send any HTML, with &lt;style&gt; and &lt;script&gt;. It shows fullsize, without a bubble. Wrap it in &lt;div class="widget"&gt; to show it inside a bubble.</div>
        </div>
        """
    }

    static func portedHTML(conversationId: String, index: Int) -> String? {
        guard let directory = fixture("ported")?.appendingPathComponent(conversationId) else {
            return nil
        }
        let prefix = String(format: "%02d-", index + 1)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        guard let file = files.sorted().first(where: { $0.hasPrefix(prefix) && $0.hasSuffix(".html") }) else {
            return nil
        }
        return try? String(contentsOf: directory.appendingPathComponent(file), encoding: .utf8)
    }

    static func statsHTML(enabled: Bool) -> String {
        let link = "<a href=\"chat:send?text=/\(statsCommand)\">/\(statsCommand)</a>"
        let text = enabled ? strings().htmlDemoCatalogStatsOn(link) : strings().htmlDemoCatalogStatsOff(link)
        return "<div class=\"widget\">\(text)</div>"
    }

    static func unknownCommandHTML(_ text: String) -> String {
        return """
        <div class="widget">I don't know <code>\(HTMLBubbleState.escape(text))</code> yet. <a href="chat:send?text=/help">Show commands</a></div>
        """
    }

    static func fallbackHTML(_ command: HTMLDemoCommand) -> String {
        return """
        <div class="widget">Here's one of my messages, <a href="chat:send?text=/\(command.command)"><b>/\(command.command)</b></a>. Type <b>/</b> to see all of them.</div>
        """
    }

    static let staticTypingHTML = """
    <div class="widget" style="font-size: 20px; line-height: 16px; color: #8e8e93; padding: 2px 0 4px 0">&#8226;&#8226;&#8226;</div>
    """

    static let typingHTML = """
    <div class="widget" style="font-size: 20px; line-height: 16px; color: #8e8e93; padding: 2px 0 4px 0">&#8226;&#8226;&#8226;</div>
    <script>
    function frame() { requestAnimationFrame(frame); }
    frame();
    function render() {
      const t = performance.now() / 1000;
      let dots = '';
      for (let i = 0; i < 3; i++) {
        const a = 0.3 + 0.7 * Math.max(0, Math.sin(t * 7 - i * 0.9));
        dots += `<span style="color: rgba(142, 142, 147, ${a.toFixed(2)})">&#8226;</span>`;
      }
      return `<div style="font-size: 20px; line-height: 16px; padding: 2px 0 4px 0">${dots}</div>`;
    }
    </script>
    """
}
