#if DEBUG
import Cocoa
import ImageIO
import zlib
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import PerfLab
import InputView
import InputTextView
import TelegramTheme
import AvatarUI
import PremiumStatusUI
import ChatHistoryModel
import ChatModeTypes

enum ChatFloatingDebug {
    static var moves = 0
    static var violations = 0
    static var creates = 0
    static var attaches = 0
    static var transitions = 0
    static var readds = 0
    static var removes = 0
    static var reuses = 0
}

enum ChatBindProbe {
    static var enabled = false
    static var binds = 0
    static var times: [String: CFTimeInterval] = [:]

    static func measure(_ name: String, _ body: () -> Void) {
        guard enabled else {
            body()
            return
        }
        let start = CACurrentMediaTime()
        body()
        times[name, default: 0] += CACurrentMediaTime() - start
    }

    static func reset() {
        binds = 0
        times.removeAll()
    }
}

enum ChatMergeProbe {
    static var enabled = false
    static var mainThreadItems = 0
    static var active = false
    static var preexisting: Set<AnyHashable> = []
    static var newBinds = 0
    static var preexistingBinds = 0
    static var sameItemBinds = 0
    static var merges: [String] = []
    static var mergeTimes: [Double] = []
    static var totalNewBinds = 0
    static var totalPreexistingBinds = 0
    static var totalReplaced = 0
    static var positionsBefore: [AnyHashable: CGFloat] = [:]
    static var maxShift: CGFloat = 0
    static var shiftedMerges = 0

    static func positions(_ table: TableView) -> [AnyHashable: CGFloat] {
        let range = table.visibleRows()
        guard range.location != NSNotFound, let document = table.documentView else { return [:] }
        var result: [AnyHashable: CGFloat] = [:]
        for row in range.location ..< range.location + range.length {
            let item = table.item(at: row)
            result[item.stableId] = document.convert(table.rectOf(index: row), to: nil).minY
        }
        return result
    }

    static func begin(table: TableView, transition: TableUpdateTransition) -> (Double, Int, Int)? {
        guard enabled else { return nil }
        var existing = Set<AnyHashable>()
        for i in 0..<table.count { existing.insert(table.item(at: i).stableId) }
        preexisting = existing
        positionsBefore = positions(table)
        newBinds = 0
        preexistingBinds = 0
        sameItemBinds = 0
        let deleted = Set(transition.deleted.compactMap { $0 < table.count ? table.item(at: $0).stableId : nil })
        let replaced = transition.inserted.filter { deleted.contains($0.1.stableId) }.count
        active = true
        return (CACurrentMediaTime(), replaced, deleted.count)
    }

    static func end(_ start: (Double, Int, Int)?, transition: TableUpdateTransition, visible: NSRange, table: TableView) {
        guard let start else { return }
        active = false
        let after = positions(table)
        var shift: CGFloat = 0
        for (id, y) in after {
            if let before = positionsBefore[id] {
                shift = max(shift, abs(before - y))
            }
        }
        if shift > 0 { shiftedMerges += 1 }
        maxShift = max(maxShift, shift)
        let ms = (CACurrentMediaTime() - start.0) * 1000
        mergeTimes.append(ms)
        totalNewBinds += newBinds
        totalPreexistingBinds += preexistingBinds
        totalReplaced += start.1
        let state = String(String(describing: transition.state).prefix(48))
        merges.append(String(format: "%.1fms del=%d ins=%d upd=%d replaced=%d binds new=%d pre=%d same=%d visible=%d+%d grouping=%d ", ms, transition.deleted.count, transition.inserted.count, transition.updated.count, start.1, newBinds, preexistingBinds, sameItemBinds, visible.location, visible.length, transition.grouping ? 1 : 0) + "state=" + state)
    }

    static func noteBind(previous: TableRowItem?, next: TableRowItem) {
        guard active else { return }
        if previous?.stableId == next.stableId {
            sameItemBinds += 1
        }
        if preexisting.contains(next.stableId) {
            preexistingBinds += 1
        } else {
            newBinds += 1
        }
    }

    static func reset() {
        mainThreadItems = 0
        merges = []
        mergeTimes = []
        totalNewBinds = 0
        totalPreexistingBinds = 0
        totalReplaced = 0
        maxShift = 0
        shiftedMerges = 0
    }
}

public enum ChatNavigationLab {
    private static var session: AnyObject?
    private static var didStart = false

    @discardableResult
    public static func startIfRequested(context: any AccountContextProtocol, outputDirectory: URL) -> Bool {
        guard !self.didStart, let configuration = PerfLabConfiguration.fromLaunchArguments(defaultOutputDirectory: outputDirectory), configuration.lab == "chat-navigation" else {
            return false
        }
        self.didStart = true
        Queue.mainQueue().after(configuration.double("-PerfLabStartDelay", 4.0), {
            let session = ChatNavigationLabSession(context: context, configuration: configuration, completion: {
                ChatNavigationLab.session = nil
                if configuration.quitWhenDone {
                    NSApp.terminate(nil)
                }
            })
            ChatNavigationLab.session = session
            session.start()
        })
        return true
    }
}

@inline(never) private func perfLabShownMarker() {
    let until = CACurrentMediaTime() + 0.003
    while CACurrentMediaTime() < until {
    }
}

private final class ChatNavigationLabSession {
    static func syntheticWidgets(directory: String, width: Int32, height: Int32) -> [TelegramMediaWidget] {
        guard !directory.isEmpty, let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return []
        }
        return names.filter { $0.hasSuffix(".html") || $0.hasSuffix(".zlib") || $0.hasSuffix(".gzip") || $0.hasSuffix(".tgw") }.sorted().compactMap { name in
            guard let data = FileManager.default.contents(atPath: (directory as NSString).appendingPathComponent(name)) else {
                return nil
            }
            let payload: Data
            if name.hasSuffix(".html") {
                guard let compressed = zlib(data) else {
                    return nil
                }
                payload = compressed
            } else {
                payload = data
            }
            return TelegramMediaWidget(width: width, height: height, payload: payload)
        }
    }

    private static func zlib(_ data: Data) -> Data? {
        var stream = z_stream()
        guard deflateInit2_(&stream, Z_BEST_COMPRESSION, Z_DEFLATED, MAX_WBITS, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            return nil
        }
        defer { deflateEnd(&stream) }
        var output = Data(count: Int(deflateBound(&stream, uLong(data.count))) + 32)
        let status = data.withUnsafeBytes { input -> Int32 in
            output.withUnsafeMutableBytes { buffer -> Int32 in
                stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(data.count)
                stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(buffer.count)
                return deflate(&stream, Z_FINISH)
            }
        }
        guard status == Z_STREAM_END else {
            return nil
        }
        output.count = Int(stream.total_out)
        return output
    }

    private let context: any AccountContextProtocol
    private let configuration: PerfLabConfiguration
    private let completion: () -> Void
    private let report: PerfLabReport
    private let processMonitor = PerfLabProcessMonitor()
    private var controller: (any ChatControllerKind)?
    private var loadDisposable: Disposable?
    private var navigationIndex = 0
    private var namePrefix = ""
    private var chatNotes: [String: String] = [:]

    init(context: any AccountContextProtocol, configuration: PerfLabConfiguration, completion: @escaping () -> Void) {
        self.context = context
        self.configuration = configuration
        self.completion = completion
        self.report = PerfLabReport(configuration: configuration)
    }

    func start() {
        try? FileManager.default.createDirectory(at: self.configuration.outputDirectory, withIntermediateDirectories: true)
        ChatDateStickView.debugForceBlur = self.configuration.double("-PerfLabDateBlur", 0.0) != 0
        ChatRowView.debugMediaReuse = self.configuration.double("-PerfLabMediaReuse", 0) != 0
        ChatReactionEmojiLayer.debugIgnoresKeyWindow = self.configuration.double("-PerfLabIgnoreKeyWindow", 0.0) != 0
        if self.configuration.scenarios.contains("sweep") {
            self.startSweep()
            return
        }
        if self.configuration.scenarios.contains("list") {
            self.listReadChats()
            return
        }
        let context = self.context
        if self.configuration.double("-PerfLabSavedMessages", 0.0) != 0 {
            self.chatNotes = ["chat": "Saved Messages"]
            self.open(peerId: context.peerId)
            return
        }
        let synthetic = Int(self.configuration.double("-PerfLabSynthetic", 0))
        if synthetic > 0 {
            let widgets = ChatNavigationLabSession.syntheticWidgets(directory: self.configuration.string("-PerfLabSyntheticWidgets", ""), width: Int32(self.configuration.double("-PerfLabWidgetWidth", 0)), height: Int32(self.configuration.double("-PerfLabWidgetHeight", 0)))
            let contents = ChatSyntheticContents(accountPeerId: context.peerId, count: synthetic, media: self.configuration.double("-PerfLabSyntheticMedia", 0) != 0, widgets: widgets, widgetEvery: Int(self.configuration.double("-PerfLabWidgetEvery", 3)), title: self.configuration.string("-PerfLabSyntheticTitle", "Perf Lab"), status: self.configuration.string("-PerfLabSyntheticStatus", "synthetic"))
            contents.storePhotoData(in: context.account.postbox.mediaBox)
            self.chatNotes = ["chat": "synthetic", "messages": "\(synthetic)", "widgets": "\(widgets.count)"]
            self.open(peerId: contents.peer.id, mode: .customChatContents(contents: contents))
            return
        }
        if let rawPeerId = Int64(self.configuration.string("-PerfLabPeerId", "")) {
            self.chatNotes = ["chat": "\(rawPeerId)"]
            self.open(peerId: PeerId(rawPeerId))
            return
        }
        let username = self.configuration.string("-PerfLabChannel", "")
        let title = self.configuration.string("-PerfLabPeerTitle", "INVEST ZONE")
        let peerSignal: Signal<PeerId?, NoError>
        if !username.isEmpty {
            peerSignal = context.engine.peers.resolvePeerByName(name: username, referrer: nil)
            |> mapToSignal { result -> Signal<PeerId?, NoError> in
                if case let .result(peer) = result {
                    return .single(peer?.id)
                }
                return .complete()
            }
            |> take(1)
        } else {
            peerSignal = context.engine.contacts.searchLocalPeers(query: title)
            |> map { peers -> PeerId? in
                if self.configuration.scenarios.contains("reaction-picker") {
                    return peers.first(where: { $0.peer?._asPeer().displayTitle == title && $0.peer?._asPeer().isSupergroup == true })?.peerId
                }
                return peers.first(where: { $0.peer?._asPeer().isChannel == true })?.peerId ?? peers.first?.peerId
            }
            |> take(1)
            |> mapToSignal { peerId -> Signal<PeerId?, NoError> in
                if let peerId {
                    return .single(peerId)
                }
                if self.configuration.scenarios.contains("reaction-picker") {
                    return .single(nil)
                }
                return context.engine.contacts.searchRemotePeers(query: title)
                |> map { own, global -> PeerId? in
                    return (own + global).first?.peer.id
                }
                |> take(1)
            }
        }
        self.loadDisposable = (peerSignal |> deliverOnMainQueue).start(next: { [weak self] peerId in
            guard let self else {
                return
            }
            guard let peerId else {
                self.report.add(scenario: "open", run: 0, metrics: [:], notes: ["error": "peer not found"])
                self.finish()
                return
            }
            self.chatNotes = ["chat": username.isEmpty ? title : username]
            self.open(peerId: peerId)
        })
    }

    private func makeChatController<C: AccountContextProtocol>(context: C, peerId: PeerId, mode: ChatMode = .history) -> any ChatControllerKind {
        return ChatController(context: context, chatLocation: .peer(peerId), mode: mode)
    }

    private func open(peerId: PeerId, mode: ChatMode = .history) {
        let controller = self.makeChatController(context: self.context, peerId: peerId, mode: mode)
        self.controller = controller
        self.context.bindings.rootNavigation().push(controller)
        Queue.mainQueue().after(self.configuration.double("-PerfLabOpenWait", 5.0), { [weak self] in
            self?.runScenarios(self?.configuration.scenarios ?? [])
        })
    }

    private func runReactionPicker(completion: @escaping () -> Void) {
        self.checkReactionPermissionModels()
        guard let controller = self.controller else {
            completion()
            return
        }
        var row: ChatRowItem?
        var rows = 0
        controller.genericView.tableView.enumerateItems(with: { item in
            rows += 1
            if let item = item as? ChatRowItem, let message = item.message, message.id.namespace == Namespaces.Message.Cloud, message.media.isEmpty, !item.isUnsent, !item.isFailed {
                row = item
                return false
            }
            return true
        })
        guard let row, let message = row.message else {
            self.report.add(scenario: "reaction-picker", run: 0, metrics: ["rows": Double(rows)], notes: ["error": "no ordinary cloud message", "actualChat": controller.chatInteraction.peer?.displayTitle ?? "nil"])
            completion()
            return
        }
        let state = controller.chatInteraction.presentation
        let peer = state.peer.flatMap { $0.id == message.id.peerId ? $0 : nil } ?? message.peers[message.id.peerId]
        let cached = state.cachedData as? CachedChannelData
        var metrics: [String: Double] = [
            "canReact": row.canReact ? 1 : 0,
            "rawPermission": peer.map { canSendReactionsToPeer(EnginePeer($0)) ? 1 : 0 } ?? 0,
            "boostsRequired": Double(cached?.boostsToUnrestrict ?? -1),
            "boostsApplied": Double(cached?.appliedBoosts ?? -1),
            "sendAsChat": state.currentSendAsPeerId == message.id.peerId ? 1 : 0,
            "sendAsOther": state.currentSendAsPeerId.map { $0 != self.context.peerId ? 1 : 0 } ?? 0
        ]
        if let peer = peer as? TelegramChannel {
            metrics["defaultReactionBan"] = peer.defaultBannedRights?.flags.contains(.banSendReactions) == true ? 1 : 0
            metrics["personalReactionBan"] = peer.bannedRights?.flags.contains(.banSendReactions) == true ? 1 : 0
            metrics["administrator"] = peer.adminRights != nil || peer.flags.contains(.isCreator) ? 1 : 0
        }
        self.loadDisposable = (row.menuAdditionView |> take(1) |> deliverOnMainQueue).start(next: { [weak self] picker in
            guard let self else { return }
            metrics["pickerWindow"] = picker != nil ? 1 : 0
            self.report.add(scenario: "reaction-picker", run: 0, metrics: metrics, notes: ["chat": state.peer?.displayTitle ?? "", "messageId": "\(message.id.id)"])
            picker?.orderOut(nil)
            completion()
        })
    }

    private func checkReactionPermissionModels() {
        let channelId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(424242424))
        let groupId = PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(424242424))
        let ban = TelegramChatBannedRights(flags: [.banSendReactions], untilDate: Int32.max)
        func channel(defaultBan: Bool = true, personalBan: Bool = false, admin: Bool = false, creator: Bool = false, broadcast: Bool = false) -> TelegramChannel {
            return TelegramChannel(id: channelId, accessHash: nil, title: "Reaction permission fixture", username: nil, photo: [], creationDate: 0, version: 0, participationStatus: .member, info: broadcast ? .broadcast(.init(flags: [])) : .group(.init(flags: [])), flags: creator ? [.isCreator] : [], restrictionInfo: nil, adminRights: admin ? .init(rights: []) : nil, bannedRights: personalBan ? ban : nil, defaultBannedRights: defaultBan ? ban : nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, emojiStatus: nil, approximateBoostLevel: nil, subscriptionUntilDate: nil, verificationIconFileId: nil, sendPaidMessageStars: nil, linkedMonoforumId: nil)
        }
        func group(_ role: TelegramGroupRole) -> TelegramGroup {
            return TelegramGroup(id: groupId, title: "Reaction permission fixture", photo: [], participantCount: 2, role: role, membership: .Member, flags: [], defaultBannedRights: ban, migrationReference: nil, creationDate: 0, version: 0)
        }
        let cases: [(String, Peer, Int32?, Int32?, Bool, Bool)] = [
            ("allowed", channel(defaultBan: false), nil, nil, false, true),
            ("default-ban", channel(), nil, nil, false, false),
            ("boost-threshold", channel(), 1, 1, false, true),
            ("boost-above", channel(), 1, 2, false, true),
            ("boost-below", channel(), 2, 1, false, false),
            ("boost-missing", channel(), 1, nil, false, false),
            ("boost-zero", channel(), 0, 1, false, false),
            ("boost-negative", channel(), -1, 1, false, false),
            ("personal-ban-boosted", channel(personalBan: true), 1, 1, false, false),
            ("administrator", channel(admin: true), nil, nil, false, true),
            ("creator", channel(creator: true), nil, nil, false, true),
            ("anonymous-restricted", channel(), nil, nil, true, false),
            ("anonymous-boosted", channel(), 1, 1, true, true),
            ("broadcast-restricted", channel(broadcast: true), nil, nil, false, false),
            ("broadcast-allowed", channel(defaultBan: false, broadcast: true), nil, nil, false, true),
            ("legacy-member", group(.member), nil, nil, false, false),
            ("legacy-admin", group(.admin(.init(rights: []), rank: nil)), nil, nil, true, true),
            ("legacy-creator", group(.creator(rank: nil)), nil, nil, true, true)
        ]
        for (index, test) in cases.enumerated() {
            let (name, peer, required, applied, anonymous, expected) = test
            let interaction = ChatInteraction(chatLocation: .peer(peer.id), context: self.context)
            let cached = CachedChannelData().withUpdatedBoostsToUnrestrict(required).withUpdatedAppliedBoosts(applied)
            interaction.update(animated: false) { $0.updatedPeer { _ in peer }.updatedMainPeer(peer).withUpdatedCachedData(cached).withUpdatedCurrentSendAsPeerId(anonymous ? peer.id : nil) }
            let message = Message(stableId: 1, stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: 1), globallyUniqueId: nil, groupingKey: nil, groupInfo: nil, threadId: nil, timestamp: 1782388800, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: peer, text: "Reaction permission fixture", attributes: [], media: [], peers: SimpleDictionary([peer.id: peer]), associatedMessages: .init(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
            let entry = ChatHistoryEntry.MessageEntry(message, message.index, true, .bubble, .Full(rank: nil, rankType: .none, header: .normal), nil, .init())
            let row = ChatRowItem.item(NSMakeSize(820, 410), from: entry, interaction: interaction, theme: theme) as? ChatRowItem
            let actual = row?.canReact ?? false
            self.report.add(scenario: "reaction-permission-model", run: index, metrics: ["actual": actual ? 1 : 0, "expected": expected ? 1 : 0, "passed": row != nil && actual == expected ? 1 : 0], notes: ["case": name])
        }
    }

    private func finish() {
        let url = self.report.write()
        NSLog("PerfLab report written to %@", url?.path ?? "nil")
        self.completion()
    }

    private func runScenarios(_ scenarios: [String]) {
        guard let scenario = scenarios.first else {
            self.finish()
            return
        }
        let rest = Array(scenarios.dropFirst())
        let next: () -> Void = { [weak self] in
            Queue.mainQueue().after(1.5, {
                self?.runScenarios(rest)
            })
        }
        switch scenario {
        case "reaction-picker":
            self.runReactionPicker(completion: next)
        case "manual":
            self.report.add(scenario: "manual", run: 0, metrics: [:], notes: self.chatNotes)
            self.finish()
        case "pinned":
            self.runPinned(remaining: Int(self.configuration.double("-PerfLabPinnedClicks", 8.0)), completion: next)
        case "jump":
            self.waitForPinned(attempts: 40, completion: { [weak self] in
                guard let self else {
                    return
                }
                let targets = self.controller?.chatInteraction.presentation.pinnedMessageId.map { [$0.messageId] + $0.others } ?? []
                if targets.isEmpty {
                    self.report.add(scenario: "jump", run: 0, metrics: [:], notes: ["error": "no pinned messages"])
                }
                self.runJumps(targets: Array(Set(targets)).sorted(by: { $0.id > $1.id }), completion: next)
            })
        case "scroll":
            if self.configuration.double("-PerfLabFloatWindow", 1.0) != 0, let window = self.controller?.genericView.tableView.window {
                window.level = .floating
                window.orderFrontRegardless()
            }
            if self.configuration.double("-PerfLabStripHidden", 0.0) != 0, let root = self.controller?.genericView.tableView.window?.contentView {
                var stripped: [NSView] = []
                func walk(_ view: NSView) {
                    for subview in view.subviews {
                        let onlyGlass = self.configuration.double("-PerfLabStripHidden", 0.0) == 2
                        if subview.isHidden && (!onlyGlass || String(describing: type(of: subview)).contains("Glass")) {
                            stripped.append(subview)
                        } else {
                            walk(subview)
                        }
                    }
                }
                walk(root)
                var owners: [String: Int] = [:]
                for view in stripped {
                    owners["\(type(of: view))<\(view.superview.map { String(describing: type(of: $0)) } ?? "-")", default: 0] += 1
                }
                for view in stripped {
                    view.removeFromSuperview()
                }
                self.chatNotes["stripped"] = "\(stripped.count)"
                self.chatNotes["owners"] = owners.sorted(by: { $0.value > $1.value }).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
            }
            if self.configuration.double("-PerfLabDetachSidebar", 0.0) != 0, let table = self.controller?.genericView.tableView, let root = table.window?.contentView {
                var branch: NSView = table
                var detached: [String] = []
                var chain: [String] = []
                let tableRect = table.convert(table.bounds, to: nil)
                while let parent = branch.superview {
                    chain.append("\(type(of: parent))[\(parent.subviews.map { "\(type(of: $0))@\(Int($0.convert($0.bounds, to: nil).minX))w\(Int($0.frame.width))" }.joined(separator: ","))]")
                    let siblings = parent.subviews.filter { $0 !== branch && $0.frame.width > 100 && $0.convert($0.bounds, to: nil).maxX <= tableRect.minX + 2 }
                    if !siblings.isEmpty, detached.isEmpty {
                        for sibling in siblings {
                            detached.append(String(describing: type(of: sibling)))
                            sibling.removeFromSuperview()
                        }
                    }
                    if parent === root { break }
                    branch = parent
                }
                self.chatNotes["detached"] = detached.joined(separator: ", ")
                self.chatNotes["chain"] = chain.joined(separator: " <- ")
            }
            self.calibrateWheel(completion: { [weak self] in
                self?.runScrollPasses(index: 0, completion: next)
            })
        case "snapshot":
            self.runSnapshots(index: 0, completion: next)
        case "widgets":
            self.runWidgets(completion: next)
        case "widget-inline":
            self.runWidgetInline(completion: next)
        case "parity":
            self.runParity(completion: next)
        case "reuseparity":
            self.runReuseParity(completion: next)
        case "floatparity":
            self.runFloatParity(completion: next)
        case "typing":
            self.runTyping(index: 0, completion: next)
        case "resize":
            self.runResize(index: 0, completion: next)
        case "selection":
            self.runSelection(index: 0, completion: next)
        case "viewcount":
            if let window = self.controller?.genericView.tableView.window, let root = window.contentView {
                var total = 0
                var hidden = 0
                var layers = 0
                var classes: [String: Int] = [:]
                var hiddenClasses: [String: Int] = [:]
                func walk(_ view: NSView, parentHidden: Bool) {
                    total += 1
                    let isHidden = parentHidden || view.isHidden
                    if isHidden {
                        hidden += 1
                        hiddenClasses[String(describing: type(of: view)), default: 0] += 1
                    }
                    classes[String(describing: type(of: view)), default: 0] += 1
                    layers += view.layer?.sublayers?.count ?? 0
                    for subview in view.subviews {
                        walk(subview, parentHidden: isHidden)
                    }
                }
                walk(root, parentHidden: false)
                let table = self.controller?.genericView.tableView
                let top = classes.sorted(by: { $0.value > $1.value }).prefix(25).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                let topHidden = hiddenClasses.sorted(by: { $0.value > $1.value }).prefix(15).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                var rowClasses: [String: Int] = [:]
                var rowViews = 0
                var rows = 0
                func walkRow(_ view: NSView) {
                    rowViews += 1
                    rowClasses["\(type(of: view))<\(view.superview.map { String(describing: type(of: $0)) } ?? "-")", default: 0] += 1
                    for subview in view.subviews { walkRow(subview) }
                }
                for subview in table?.documentView?.subviews ?? [] where subview is ChatRowView {
                    rows += 1
                    walkRow(subview)
                }
                let rowTop = rowClasses.sorted(by: { $0.value > $1.value }).prefix(30).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                self.report.add(scenario: "viewcount", run: 0, metrics: ["views": Double(total), "hiddenViews": Double(hidden), "sublayers": Double(layers), "tableSubviews": Double(table?.documentView?.subviews.count ?? 0), "visibleRows": Double(table?.visibleRows().length ?? 0), "chatRows": Double(rows), "chatRowViews": Double(rowViews)], notes: ["top": top, "hidden": topHidden, "rowTop": rowTop])
            }
            next()
        case "census":
            Queue.mainQueue().after(self.configuration.double("-PerfLabCensusDelay", 3.0), { [weak self] in
                guard let self else {
                    return
                }
                if let root = self.controller?.genericView.tableView.window?.contentView {
                    let census = PerfLabViewCensus.take(root)
                    var metrics = census.metrics
                    metrics["footprintMB"] = Double(self.processMonitor.snapshot().footprint) / 1048576.0
                    var rowClasses: [String: Int] = [:]
                    var rowKinds: [String: Int] = [:]
                    var rows = 0, rowViews = 0
                    func countRow(_ view: NSView) {
                        for subview in view.subviews {
                            rowClasses["\(type(of: subview))<\(type(of: view))", default: 0] += 1
                            rowViews += 1
                            countRow(subview)
                        }
                    }
                    if let document = self.controller?.genericView.tableView.documentView {
                        for case let row as ChatRowView in document.subviews where !row.isHidden {
                            rows += 1
                            rowKinds["\(type(of: row))", default: 0] += 1
                            countRow(row)
                        }
                    }
                    metrics["chatRows"] = Double(rows)
                    metrics["chatRowSubviews"] = Double(rowViews)
                    var notes = census.notes(top: 60).merging(self.chatNotes, uniquingKeysWith: { $1 })
                    notes["chatRowClasses"] = rowClasses.sorted(by: { $0.value > $1.value }).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                    notes["chatRowKinds"] = rowKinds.sorted(by: { $0.value > $1.value }).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
                    self.report.add(scenario: "census", run: 0, metrics: metrics, notes: notes)
                }
                next()
            })
        case "idle":
            self.runIdle(index: 0, completion: next)
        case "open":
            self.runOpens(remaining: Int(self.configuration.double("-PerfLabOpens", 6.0)), index: 0, completion: next)
        case "contextpopup":
            self.runContextPopup(index: 0, completion: next)
        case "opentrace":
            let peers = self.configuration.string("-PerfLabOpenPeers", "self").split(separator: ",").compactMap { raw -> PeerId? in
                raw == "self" ? self.context.peerId : Int64(raw).map { PeerId($0) }
            }
            self.runOpenTraces(peers: peers, remaining: Int(self.configuration.double("-PerfLabOpens", 6.0)), index: 0, completion: next)
        case "pininfo":
            guard let peerId = self.controller?.chatInteraction.peerId else {
                next()
                return
            }
            let signal = self.context.engine.messages.searchMessages(location: .peer(peerId: peerId, fromId: nil, tags: .pinned, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "", state: nil, limit: 50)
            |> take(1)
            self.loadDisposable = (signal |> deliverOnMainQueue).start(next: { [weak self] result in
                var notes: [String: String] = [:]
                for message in result.0.messages {
                    notes["m\(message.id.id)"] = "threadId=\(message.threadId.map { "\($0)" } ?? "nil")"
                }
                notes["peerKind"] = self?.controller?.chatInteraction.presentation.peer.map { "\(type(of: $0))" } ?? "?"
                notes["pinned"] = self?.controller?.chatInteraction.presentation.pinnedMessageId.map { "\($0.messageId.id) others=\($0.others.map { $0.id })" } ?? "nil"
                self?.report.add(scenario: "pininfo", run: 0, metrics: [:], notes: notes)
                next()
            })
        default:
            self.report.add(scenario: scenario, run: 0, metrics: [:], notes: ["error": "unknown scenario"])
            next()
        }
    }

    private var wheelSign: Double = 1
    private var scrollMeasurement: PerfLabScrollMeasurement?
    private var openPeerId: PeerId?

    private func lowestVisibleMessageId() -> Int32? {
        guard let table = self.controller?.genericView.tableView else {
            return nil
        }
        let range = table.visibleRows()
        var result: Int32?
        if range.length > 0 {
            for row in range.location ..< range.location + range.length {
                if let item = table.item(at: row) as? ChatRowItem, let id = item.messages.first?.id.id {
                    result = min(result ?? id, id)
                }
            }
        }
        return result
    }

    private func calibrateWheel(completion: @escaping () -> Void) {
        guard let table = self.controller?.genericView.tableView else {
            completion()
            return
        }
        let before = self.lowestVisibleMessageId()
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 400, wheel2: 0, wheel3: 0), let nsEvent = NSEvent(cgEvent: event) {
            table.scrollWheel(with: nsEvent)
        }
        Queue.mainQueue().after(0.6, { [weak self] in
            guard let self else {
                return
            }
            let after = self.lowestVisibleMessageId()
            if let before, let after {
                self.wheelSign = after < before ? 1 : -1
            }
            self.controller?.chatInteraction.scrollToLatest(false)
            Queue.mainQueue().after(1.0, completion)
        })
    }

    private func runScrollPasses(index: Int, completion: @escaping () -> Void) {
        let runs = Int(self.configuration.double("-PerfLabRuns", 2.0))
        guard index <= runs, let table = self.controller?.genericView.tableView else {
            completion()
            return
        }
        table.mergesSaveVisibleInOneGroup = self.configuration.double("-PerfLabMergeGrouped", 1) != 0
        let floatNodes = self.configuration.double("-PerfLabFloatNodes", 1) != 0
        if ChatFloatingAvatar.usesNodes != floatNodes {
            ChatFloatingAvatar.usesNodes = floatNodes
            self.controller?.debugRebuildFloatingAvatars()
        }
        ChatMergeProbe.enabled = true
        ChatBindProbe.enabled = true
        ChatBindProbe.reset()
        self.placeCursor(self.configuration.string("-PerfLabCursor", ""), table: table)
        let speed = self.configuration.double("-PerfLabScrollSpeed", 2400.0)
        let duration = self.configuration.double("-PerfLabScrollDuration", 7.0)
        let segments = [
            PerfLabScrollSegment(duration: 0.2, velocity: 0),
            PerfLabScrollSegment(duration: duration, velocity: speed),
            PerfLabScrollSegment(duration: duration, velocity: -speed),
            PerfLabScrollSegment(duration: 0.2, velocity: 0)
        ]
        let measurement = PerfLabScrollMeasurement(view: table, scrollView: table, segments: segments, wheelSign: self.wheelSign, processMonitor: self.processMonitor, sampler: { [weak table] in
            guard let table else {
                return [:]
            }
            var avatarsBelowRows = 0
            if let subviews = table.documentView?.subviews, let lastRow = subviews.lastIndex(where: { !($0 is ChatAvatarView) }) {
                avatarsBelowRows = subviews.prefix(lastRow).filter { $0 is ChatAvatarView }.count
            }
            return ["rows": Double(table.count), "avatarsBelowRows": Double(avatarsBelowRows)]
        })
        self.scrollMeasurement = measurement
        let name = index == 0 ? "scroll-warmup" : "scroll"
        ChatMergeProbe.mainThreadItems = 0
        measurement.run(completion: { [weak self] metrics in
            guard let self else {
                return
            }
            self.scrollMeasurement = nil
            let notes = self.chatNotes.merging(["wheelSign": "\(self.wheelSign)"], uniquingKeysWith: { $1 })
            var metrics = metrics
            if let window = table.window {
                metrics["cursorInWindow"] = window.frame.contains(NSEvent.mouseLocation) ? 1 : 0
            }
            metrics["binds"] = Double(ChatBindProbe.binds)
            for (name, time) in ChatBindProbe.times {
                metrics["bindMs_\(name)"] = time * 1000
            }
            ChatBindProbe.reset()
            metrics["floatingMoves"] = Double(ChatFloatingDebug.moves)
            metrics["floatingOrderViolations"] = Double(ChatFloatingDebug.violations)
            metrics["floatingCreates"] = Double(ChatFloatingDebug.creates)
            metrics["floatingAttaches"] = Double(ChatFloatingDebug.attaches)
            metrics["floatingTransitions"] = Double(ChatFloatingDebug.transitions)
            metrics["floatingReadds"] = Double(ChatFloatingDebug.readds)
            metrics["floatingRemoves"] = Double(ChatFloatingDebug.removes)
            metrics["floatingReuses"] = Double(ChatFloatingDebug.reuses)
            ChatFloatingDebug.moves = 0
            ChatFloatingDebug.violations = 0
            ChatFloatingDebug.creates = 0
            ChatFloatingDebug.attaches = 0
            ChatFloatingDebug.transitions = 0
            ChatFloatingDebug.readds = 0
            ChatFloatingDebug.removes = 0
            ChatFloatingDebug.reuses = 0
            metrics["merges"] = Double(ChatMergeProbe.mergeTimes.count)
            metrics["mergeMsMax"] = ChatMergeProbe.mergeTimes.max() ?? 0
            metrics["mergeMsTotal"] = ChatMergeProbe.mergeTimes.reduce(0, +)
            metrics["mergeNewBinds"] = Double(ChatMergeProbe.totalNewBinds)
            metrics["mergePreexistingBinds"] = Double(ChatMergeProbe.totalPreexistingBinds)
            metrics["mergeReplaced"] = Double(ChatMergeProbe.totalReplaced)
            metrics["mergeMaxShift"] = Double(ChatMergeProbe.maxShift)
            metrics["mergeShifted"] = Double(ChatMergeProbe.shiftedMerges)
            metrics["mainThreadItems"] = Double(ChatMergeProbe.mainThreadItems)
            var scenesTracking = 0
            var scenesMissingTracking = 0
            var controlsTracking = 0
            var controlsMissingTracking = 0
            var spareReactions = 0, spareChips = 0, sparePlayable = 0, shownPlayable = 0
            func visitScenes(_ view: NSView) {
                if let reactions = view as? ChatReactionsView {
                    if reactions.isHidden {
                        spareReactions += 1
                        spareChips += reactions.debugChipNodeCount
                        sparePlayable += reactions.debugPlayableChipCount
                    } else {
                        shownPlayable += reactions.debugPlayableChipCount
                    }
                }
                if let scene = view as? ChatLayerSceneView {
                    let tracking = scene.debugPointerTracking
                    if tracking.needed {
                        scenesTracking += 1
                        if !tracking.installed { scenesMissingTracking += 1 }
                    }
                } else if let control = view as? Control, control.window != nil, control.visibleRect != .zero {
                    controlsTracking += 1
                    if control.trackingAreas.isEmpty { controlsMissingTracking += 1 }
                }
                for subview in view.subviews { visitScenes(subview) }
            }
            if let documentView = table.documentView { visitScenes(documentView) }
            metrics["scenesTracking"] = Double(scenesTracking)
            metrics["spareReactions"] = Double(spareReactions)
            metrics["spareReactionChips"] = Double(spareChips)
            metrics["spareReactionPlayable"] = Double(sparePlayable)
            metrics["shownReactionPlayable"] = Double(shownPlayable)
            metrics["scenesMissingTracking"] = Double(scenesMissingTracking)
            metrics["controlsTracking"] = Double(controlsTracking)
            metrics["controlsMissingTracking"] = Double(controlsMissingTracking)
            var notes2 = notes
            notes2["merges"] = ChatMergeProbe.merges.joined(separator: "; ")
            ChatMergeProbe.reset()
            self.report.add(scenario: name, run: max(0, index - 1), metrics: metrics, notes: notes2)
            self.controller?.chatInteraction.scrollToLatest(false)
            Queue.mainQueue().after(2.0, {
                self.runScrollPasses(index: index + 1, completion: completion)
            })
        })
    }

    private func placeCursor(_ mode: String, table: NSView) {
        guard let window = table.window, let screen = window.screen ?? NSScreen.main, let primary = NSScreen.screens.first else {
            return
        }
        let target: NSPoint
        switch mode {
        case "inside":
            let rect = window.convertToScreen(table.convert(table.bounds, to: nil))
            target = NSMakePoint(rect.midX, rect.midY)
        case "outside":
            let frame = window.frame
            let visible = screen.frame
            if frame.maxX + 40 < visible.maxX {
                target = NSMakePoint(frame.maxX + 20, frame.midY)
            } else if frame.minX - 40 > visible.minX {
                target = NSMakePoint(frame.minX - 20, frame.midY)
            } else {
                target = NSMakePoint(visible.midX, visible.maxY - 5)
            }
        default:
            return
        }
        CGWarpMouseCursorPosition(CGPoint(x: target.x, y: primary.frame.maxY - target.y))
    }

    private func windowImage(_ window: NSWindow) -> CGImage? {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
        let createImage = unsafeBitCast(symbol, to: CreateImage.self)
        return createImage(.null, CGWindowListOption.optionIncludingWindow.rawValue, UInt32(window.windowNumber), CGWindowImageOption.boundsIgnoreFraming.rawValue | CGWindowImageOption.bestResolution.rawValue)?.takeRetainedValue()
    }

    private func pixels(_ image: CGImage) -> Data? {
        let width = image.width, height = image.height
        var data = Data(count: width * height * 4)
        let drawn = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? data : nil
    }

    private func savePNG(_ image: CGImage, name: String) {
        let url = self.configuration.outputDirectory.appendingPathComponent("chat-navigation-\(self.configuration.label)-\(name).png")
        if let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }

    private func runFloatParity(completion: @escaping () -> Void) {
        guard let controller = self.controller, let window = controller.genericView.tableView.window, let documentView = controller.genericView.tableView.documentView else {
            completion()
            return
        }
        let table = controller.genericView.tableView
        let clip = table.clipView
        let previousLevel = window.level
        window.level = .floating
        window.orderFrontRegardless()
        let positions = Int(self.configuration.double("-PerfLabFloatPositions", 12))
        let wait = self.configuration.double("-PerfLabParityWait", 0.8)
        let saveAll = self.configuration.double("-PerfLabParitySaveAll", 0) != 0
        ChatFloatingAvatar.parityMutation = self.configuration.double("-PerfLabFloatMutate", 0)
        let start = clip.bounds.origin
        let range = max(0, documentView.frame.height - clip.bounds.height)
        var leftInset: CGFloat = 0
        table.enumerateItems(with: { item in
            if let item = item as? ChatRowItem {
                leftInset = item.leftInset
                return false
            }
            return true
        })
        var compared = 0, equal = 0, different = 0, unstable = 0, failed = 0
        var nodes = 0, nodeViews = 0, legacyViews = 0, hitOK = 0, hitTotal = 0, viewHitOK = 0, viewHitTotal = 0
        var details: [String] = []
        var misses: [String] = []
        func crop(_ image: CGImage) -> CGImage? {
            let tableRect = table.convert(table.bounds, to: nil)
            let column = NSRect(x: tableRect.minX, y: tableRect.minY, width: leftInset + ChatFloatingAvatarNode.size.width + 2, height: tableRect.height)
            let scale = CGFloat(image.width) / window.frame.width
            let rect = CGRect(x: column.minX * scale, y: (window.frame.height - column.maxY) * scale, width: column.width * scale, height: column.height * scale).integral
            return image.cropping(to: rect)
        }
        func capture(nodesPath: Bool, done: @escaping (CGImage?) -> Void) {
            ChatFloatingAvatar.usesNodes = nodesPath
            controller.debugRebuildFloatingAvatars()
            Queue.mainQueue().after(wait, {
                window.displayIfNeeded()
                CATransaction.flush()
                let counts = controller.genericView.debugFloatingAvatarCounts
                if nodesPath {
                    nodes += counts.nodes
                    nodeViews += counts.views
                    hitOK += counts.hitOK
                    hitTotal += counts.hitTotal
                    if !counts.misses.isEmpty {
                        misses.append(counts.misses)
                    }
                } else {
                    legacyViews += counts.views
                    viewHitOK += counts.viewHitOK
                    viewHitTotal += counts.viewHitTotal
                }
                Queue.mainQueue().after(0.1, {
                    done(self.windowImage(window).flatMap(crop))
                })
            })
        }
        func finish() {
            ChatFloatingAvatar.usesNodes = true
            ChatFloatingAvatar.parityMutation = 0
            clip.scroll(to: start)
            table.reflectScrolledClipView(clip)
            controller.debugRebuildFloatingAvatars()
            window.level = previousLevel
            self.report.add(scenario: "floatparity", run: 0, metrics: ["positions": Double(compared), "equal": Double(equal), "different": Double(different), "unstable": Double(unstable), "failed": Double(failed), "avatarNodes": Double(nodes), "avatarViewsNodesPath": Double(nodeViews), "avatarViewsLegacy": Double(legacyViews), "avatarHitOK": Double(hitOK), "avatarHitTotal": Double(hitTotal), "viewHitOK": Double(viewHitOK), "viewHitTotal": Double(viewHitTotal)], notes: ["different": details.joined(separator: "; "), "misses": misses.joined(separator: " | ")])
            completion()
        }
        func step(_ index: Int) {
            guard index < positions else {
                finish()
                return
            }
            let y = positions > 1 ? range * CGFloat(index) / CGFloat(positions - 1) : start.y
            clip.scroll(to: NSPoint(x: start.x, y: floor(y)))
            table.reflectScrolledClipView(clip)
            capture(nodesPath: false, done: { first in
                capture(nodesPath: true, done: { candidate in
                    capture(nodesPath: false, done: { second in
                        capture(nodesPath: true, done: { candidateSecond in
                            guard let first, let candidate, let second, let candidateSecond, let a = self.pixels(first), let b = self.pixels(candidate), let c = self.pixels(second), let d = self.pixels(candidateSecond) else {
                                failed += 1
                                step(index + 1)
                                return
                            }
                            compared += 1
                            if saveAll {
                                self.savePNG(first, name: "float\(index)-legacy")
                                self.savePNG(candidate, name: "float\(index)-layers")
                            }
                            if a != c || b != d {
                                unstable += 1
                            } else if a == b {
                                equal += 1
                            } else {
                                different += 1
                                details.append("\(index)@\(Int(y))")
                                self.savePNG(first, name: "float\(index)-legacy")
                                self.savePNG(candidate, name: "float\(index)-layers")
                            }
                            step(index + 1)
                        })
                    })
                })
            })
        }
        step(0)
    }

    private func runReuseParity(completion: @escaping () -> Void) {
        guard let table = self.controller?.genericView.tableView, let mainWindow = table.window else {
            completion()
            return
        }
        var items: [ChatRowItem] = []
        table.enumerateItems(with: { item in
            if let item = item as? ChatRowItem {
                items.append(item)
            }
            return true
        })
        let limit = min(items.count, Int(self.configuration.double("-PerfLabParityRows", 60.0)))
        let wait = self.configuration.double("-PerfLabParityWait", 0.7)
        let width = table.frame.width
        let window = NSWindow(contentRect: NSRect(x: mainWindow.frame.minX, y: mainWindow.frame.minY, width: width, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = mainWindow.appearance
        window.colorSpace = mainWindow.colorSpace
        let host = View(frame: NSRect(x: 0, y: 0, width: width, height: 200))
        host.backgroundColor = theme.colors.background
        window.contentView = host
        window.orderFront(nil)
        let withReactions = items.filter { $0.reactionsLayout != nil }
        let withoutReactions = items.filter { $0.reactionsLayout == nil }
        var pool: [ObjectIdentifier: TableRowView] = [:]
        var compared = 0, equal = 0, different = 0, unstable = 0, priorBinds = 0
        func hasStars(_ item: ChatRowItem) -> Bool {
            guard item.reactionsLayout != nil, let attribute = item.message?.attributes.compactMap({ $0 as? ReactionsMessageAttribute }).first else { return false }
            return attribute.reactions.contains(where: { $0.value == .stars })
        }
        let starRows = items.prefix(limit).filter(hasStars).count
        let priorStarRows = withReactions.filter(hasStars).count
        var details: [String] = []
        func place(_ view: TableRowView, _ item: ChatRowItem) {
            let height = max(1, item.height)
            window.setContentSize(NSSize(width: width, height: height))
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            view.frame = NSRect(x: 0, y: 0, width: width, height: height)
            if view.superview !== host {
                host.addSubview(view)
            }
            view.set(item: item, animated: false)
            view.needsLayout = true
            host.layoutSubtreeIfNeeded()
        }
        func render(_ view: TableRowView, _ item: ChatRowItem, done: @escaping (Data?) -> Void) {
            place(view, item)
            window.displayIfNeeded()
            Queue.mainQueue().after(wait, {
                view.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                CATransaction.flush()
                Queue.mainQueue().after(0.1, {
                    let image = self.windowImage(window)
                    view.removeFromSuperview()
                    done(image.flatMap { self.pixels($0) })
                })
            })
        }
        func step(_ index: Int) {
            guard index < limit else {
                window.orderOut(nil)
                self.report.add(scenario: "reuseparity", run: 0, metrics: ["rows": Double(compared), "equal": Double(equal), "different": Double(different), "unstable": Double(unstable), "priorBinds": Double(priorBinds), "starRows": Double(starRows), "priorStarRows": Double(priorStarRows), "reactionRows": Double(withReactions.count)], notes: ["different": details.joined(separator: "; ")])
                completion()
                return
            }
            let item = items[index]
            guard let type = item.viewClass() as? TableRowView.Type else {
                step(index + 1)
                return
            }
            let fresh = type.init(frame: NSRect(x: 0, y: 0, width: width, height: max(1, item.height)))
            render(fresh, item, done: { first in
                let key = ObjectIdentifier(type)
                let reused = pool[key] ?? type.init(frame: NSRect(x: 0, y: 0, width: width, height: max(1, item.height)))
                pool[key] = reused
                var priors: [ChatRowItem] = []
                if !withReactions.isEmpty {
                    priors.append(withReactions[(index * 7 + 3) % withReactions.count])
                }
                if !withoutReactions.isEmpty {
                    priors.append(withoutReactions[(index * 5 + 1) % withoutReactions.count])
                }
                for prior in priors where prior !== item && (prior.viewClass() as? TableRowView.Type).map(ObjectIdentifier.init) == key {
                    place(reused, prior)
                    priorBinds += 1
                }
                render(reused, item, done: { second in
                    compared += 1
                    if let first, first == second {
                        equal += 1
                        step(index + 1)
                        return
                    }
                    let again = type.init(frame: NSRect(x: 0, y: 0, width: width, height: max(1, item.height)))
                    render(again, item, done: { third in
                        if first != third {
                            unstable += 1
                        } else {
                            different += 1
                            details.append("\(index)")
                        }
                        step(index + 1)
                    })
                })
            })
        }
        step(0)
    }

    private func runParity(completion: @escaping () -> Void) {
        guard let table = self.controller?.genericView.tableView, let mainWindow = table.window else {
            completion()
            return
        }
        var items: [ChatRowItem] = []
        table.enumerateItems(with: { item in
            if let item = item as? ChatRowItem {
                items.append(item)
            }
            return true
        })
        let limit = Int(self.configuration.double("-PerfLabParityRows", 80.0))
        let wait = self.configuration.double("-PerfLabParityWait", 0.7)
        let width = table.frame.width
        let window = NSWindow(contentRect: NSRect(x: mainWindow.frame.minX, y: mainWindow.frame.minY, width: width, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = mainWindow.appearance
        window.colorSpace = mainWindow.colorSpace
        let host = View(frame: NSRect(x: 0, y: 0, width: width, height: 200))
        host.backgroundColor = theme.colors.background
        window.contentView = host
        window.orderFront(nil)
        var compared = 0, equal = 0, unstable = 0, different = 0, failed = 0, hosted = 0
        ChatRowView.parityMutation = self.configuration.double("-PerfLabParityMutate", 0.0)
        ChatRowView.parityEmojiMutation = self.configuration.double("-PerfLabParityMutateEmoji", 0.0)
        ChatRowView.parityAvatarMutation = self.configuration.double("-PerfLabParityMutateAvatar", 0.0)
        ChatRowView.parityStatusMutation = self.configuration.double("-PerfLabParityMutateStatus", 0.0)
        ChatRowView.parityChipMutation = self.configuration.double("-PerfLabParityMutateChip", 0.0)
        ChatRowView.parityBadgeMutation = self.configuration.double("-PerfLabParityMutateBadge", 0.0)
        ChatRowView.parityReplyMutation = self.configuration.double("-PerfLabParityMutateReply", 0.0)
        ChatAccessoryView.debugRejectsLayerUpdates = self.configuration.double("-PerfLabParityReplyFallback", 0.0) != 0
        var photoLayers = 0, photoViews = 0, videoLayers = 0, videoViews = 0, snapshotEqual = 0, snapshotDifferent = 0
        var countingIndex = -1
        var videoRows = Set<Int>()
        var videoOutcomes: [String] = []
        var snapshotMismatches: [String] = []
        var snapshotSignatures: [String: String] = [:]
        func snapshotSignature(_ view: NSView) -> String {
            var parts: [String] = []
            func visit(_ current: NSView) {
                if let media = current as? ChatInteractiveContentView, media.debugImageHost.isPhoto || media.debugImageHost.isVideo, let snapshot = media.copy() as? NSView {
                    var digest = "nil"
                    if let contents = snapshot.layer?.contents, CFGetTypeID(contents as CFTypeRef) == CGImage.typeID, let data = self.pixels(contents as! CGImage) {
                        digest = "\(data.count):\(data.hashValue)"
                    }
                    parts.append("\(snapshot.frame)|\(snapshot.layer?.masksToBounds == true)|\(snapshot.layer?.shouldRasterize == true)|\(digest)")
                }
                current.subviews.forEach(visit)
            }
            visit(view)
            return parts.joined(separator: ";")
        }
        ChatMediaImageHost.parityMutation = self.configuration.double("-PerfLabParityMutateMedia", 0.0)
        var replyNodes = 0, replyViews = 0, replyNodeThumbnails = 0, replyViewThumbnails = 0, replyHitOK = 0, replyHitTotal = 0
        var badgeNodes = 0, badgeViews = 0, badgeHitOK = 0, badgeHitTotal = 0
        let fakeBadge = Int(self.configuration.double("-PerfLabParityFakeBadge", 0))
        var restoredBadges: [(ChatRowItem, ChatRowItem.DebugAdminBadgeState)] = []
        if fakeBadge != 0 {
            for item in items where item.authorText != nil && item.adminBadge == nil {
                restoredBadges.append((item, item.debugAdminBadgeState))
                let color: NSColor? = fakeBadge == 1 ? theme.colors.greenUI : nil
                let badge = TextViewLayout(.initialize(string: " admin", color: color ?? theme.colors.grayText, font: .normal(.short)), maximumNumberOfLines: 1, truncationType: .end, alignment: .left)
                badge.mayItems = false
                badge.measure(width: .greatestFiniteMagnitude)
                item.debugAdminBadgeState = (badge, color != nil, color != nil ? .admin : .none, color, false, color != nil ? item.message?.author?.id : nil)
            }
        }
        var avatarLayers = 0, avatarViews = 0, statusLayers = 0, statusViews = 0, chipNodes = 0, chipViews = 0, chipHitOK = 0, chipHitTotal = 0
        func countAvatars(_ view: NSView) {
            var seen = Set<ObjectIdentifier>()
            func walk(_ layer: CALayer) {
                guard seen.insert(ObjectIdentifier(layer)).inserted else { return }
                if layer is AvatarContentLayer { avatarLayers += 1 }
                if layer is PremiumStatusLayer { statusLayers += 1 }
                (layer.sublayers ?? []).forEach(walk)
            }
            func visit(_ view: NSView) {
                if view is AvatarContentView { avatarViews += 1 }
                if view is PremiumStatusControl { statusViews += 1 }
                if view is ChatReactionsView.ReactionView { chipViews += 1 }
                if let row = view as? ChatRowView, row.debugHasLegacyAdminBadge { badgeViews += 1 }
                if let row = view as? ChatRowView, row.debugHasReplyNode {
                    replyNodes += 1
                    if row.debugReplyThumbnail { replyNodeThumbnails += 1 }
                    if let hit = row.debugReplyHit {
                        replyHitTotal += 1
                        if hit { replyHitOK += 1 }
                    }
                }
                if let media = view as? ChatInteractiveContentView, media.debugImageHost.isPhoto {
                    if media.debugImageHost.layer {
                        photoLayers += 1
                    } else {
                        photoViews += 1
                    }
                }
                if let media = view as? ChatInteractiveContentView, media.debugImageHost.isVideo {
                    videoRows.insert(countingIndex)
                    if media.debugImageHost.layer {
                        videoLayers += 1
                    } else {
                        videoViews += 1
                    }
                }
                if let row = view as? ChatRowView, row.debugHasReplyView {
                    replyViews += 1
                    if row.debugReplyThumbnail { replyViewThumbnails += 1 }
                }
                if let scene = view as? ChatLayerRowView, scene.hasAdminBadgeNode {
                    badgeNodes += 1
                    if let hit = scene.debugAdminBadgeHit {
                        badgeHitTotal += 1
                        if hit { badgeHitOK += 1 }
                    }
                }
                if let reactions = view as? ChatReactionsView {
                    chipNodes += reactions.debugChipNodeCount
                    let hits = reactions.debugChipHitChecks()
                    chipHitOK += hits.ok
                    chipHitTotal += hits.total
                }
                view.layer.map(walk)
                view.subviews.forEach(visit)
            }
            visit(view)
        }
        var details: [String] = []
        var dumps: [String] = []
        var playbackMismatch: [String] = []
        let dumpRow = Int(self.configuration.double("-PerfLabParityDumpRow", -1))
        let saveAll = self.configuration.double("-PerfLabParitySaveAll", 0) != 0
        func describe(_ layer: CALayer?, _ name: String) -> String {
            guard let layer else { return "\(name)=nil" }
            return "\(name){\(type(of: layer)) f=\(layer.frame) b=\(layer.bounds) s=\(layer.contentsScale) aa=\(layer.edgeAntialiasingMask.rawValue) aae=\(layer.allowsEdgeAntialiasing) clip=\(layer.masksToBounds) flip=\(layer.isGeometryFlipped) op=\(layer.isOpaque) z=\(layer.zPosition) mag=\(layer.magnificationFilter.rawValue) min=\(layer.minificationFilter.rawValue) grav=\(layer.contentsGravity.rawValue) cc=\(layer.contentsCenter) c=\(layer.contents.map { String(describing: type(of: $0)) } ?? "nil") bg=\(layer.backgroundColor.map { String(describing: $0.components ?? []) } ?? "nil") fmt=\(layer.contentsFormat.rawValue) grp=\(layer.allowsGroupOpacity) anim=\(layer.animationKeys() ?? []) pcc=\(layer.presentation()?.contentsCenter ?? .zero) pf=\(layer.presentation()?.frame ?? .zero) sub=\((layer.sublayers ?? []).map { String(describing: type(of: $0)) })}"
        }
        func capture(_ item: ChatRowItem, legacy: Bool, done: @escaping (CGImage?) -> Void) {
            ChatRowView.usesLegacyRowChrome = legacy
            guard let type = item.viewClass() as? TableRowView.Type else {
                done(nil)
                return
            }
            let height = max(1, item.height)
            window.setContentSize(NSSize(width: width, height: height))
            host.frame = NSRect(x: 0, y: 0, width: width, height: height)
            let view = type.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
            host.addSubview(view)
            view.set(item: item, animated: false)
            if !legacy, (view as? ChatRowView)?.rightView.isContentHosted == true {
                hosted += 1
            }
            view.needsLayout = true
            host.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            Queue.mainQueue().after(wait, {
                view.layoutSubtreeIfNeeded()
                window.displayIfNeeded()
                CATransaction.flush()
                countingIndex = items.firstIndex(where: { $0 === item }) ?? -1
                countAvatars(view)
                if let index = items.firstIndex(where: { $0 === item }) {
                    let key = "\(index)-\(legacy)"
                    if snapshotSignatures[key] == nil {
                        snapshotSignatures[key] = snapshotSignature(view)
                    }
                    if let native = snapshotSignatures["\(index)-true"], let hosted = snapshotSignatures["\(index)-false"], !native.isEmpty, snapshotSignatures["\(index)-done"] == nil {
                        snapshotSignatures["\(index)-done"] = ""
                        if native == hosted {
                            snapshotEqual += 1
                        } else {
                            snapshotDifferent += 1
                            snapshotMismatches.append("\(index): native \(native) hosted \(hosted)")
                        }
                    }
                }
                if dumpRow == items.firstIndex(where: { $0 === item }), let row = view as? ChatRowView {
                    let layer = row.bubbleView.layer
                    dumps.append("\(legacy ? "native" : "hosted"): " + describe(layer, "bubble") + " " + describe(layer?.mask, "mask") + " " + (layer?.sublayers ?? []).map { describe($0, "child") }.joined(separator: " "))
                }
                Queue.mainQueue().after(0.1, {
                    let image = self.windowImage(window)
                    view.removeFromSuperview()
                    done(image)
                })
            })
        }
        func step(_ index: Int) {
            guard index < min(items.count, limit) else {
                ChatRowView.usesLegacyRowChrome = false
                ChatRowView.parityMutation = 0
                ChatRowView.parityEmojiMutation = 0
                ChatRowView.parityAvatarMutation = 0
                ChatRowView.parityStatusMutation = 0
                ChatRowView.parityChipMutation = 0
                ChatRowView.parityBadgeMutation = 0
                ChatRowView.parityReplyMutation = 0
                ChatMediaImageHost.parityMutation = 0
                ChatAccessoryView.debugRejectsLayerUpdates = false
                for (item, state) in restoredBadges {
                    item.debugAdminBadgeState = state
                }
                window.orderOut(nil)
                self.report.add(scenario: "parity", run: 0, metrics: ["rows": Double(compared), "equal": Double(equal), "different": Double(different), "unstable": Double(unstable), "failed": Double(failed), "hostedRight": Double(hosted), "avatarLayers": Double(avatarLayers), "avatarViews": Double(avatarViews), "statusLayers": Double(statusLayers), "statusViews": Double(statusViews), "chipNodes": Double(chipNodes), "chipViews": Double(chipViews), "chipHitOK": Double(chipHitOK), "chipHitTotal": Double(chipHitTotal), "badgeNodes": Double(badgeNodes), "badgeViews": Double(badgeViews), "badgeHitOK": Double(badgeHitOK), "badgeHitTotal": Double(badgeHitTotal), "replyNodes": Double(replyNodes), "replyViews": Double(replyViews), "replyNodeThumbnails": Double(replyNodeThumbnails), "replyViewThumbnails": Double(replyViewThumbnails), "replyHitOK": Double(replyHitOK), "replyHitTotal": Double(replyHitTotal), "photoLayers": Double(photoLayers), "photoViews": Double(photoViews), "videoLayers": Double(videoLayers), "videoViews": Double(videoViews), "snapshotEqual": Double(snapshotEqual), "snapshotDifferent": Double(snapshotDifferent)], notes: ["different": details.joined(separator: "; "), "layers": dumps.joined(separator: "\n"), "playback": playbackMismatch.joined(separator: "; "), "videoRows": videoOutcomes.joined(separator: "; "), "snapshot": snapshotMismatches.joined(separator: " | ")])
                completion()
                return
            }
            let item = items[index]
            let name = String(describing: type(of: item))
            capture(item, legacy: true, done: { first in
                capture(item, legacy: false, done: { candidate in
                    capture(item, legacy: true, done: { second in
                    capture(item, legacy: false, done: { candidateSecond in
                        guard let first, let candidate, let second, let candidateSecond, let a = self.pixels(first), let b = self.pixels(candidate), let c = self.pixels(second), let d = self.pixels(candidateSecond) else {
                            failed += 1
                            step(index + 1)
                            return
                        }
                        compared += 1
                        if saveAll {
                            self.savePNG(first, name: "row\(index)-legacy")
                            self.savePNG(candidate, name: "row\(index)-layers")
                        }
                        if (a == c) != (b == d) {
                            playbackMismatch.append("\(index):\(name):\(a == c ? "nativeStatic" : "nativeAnimates")")
                        }
                        if videoRows.contains(index) {
                            videoOutcomes.append("\(index):\(a != c ? "unstable" : a == b ? "equal" : "different")\(b != d ? ":layerAnimates" : "")")
                        }
                        if a != c {
                            unstable += 1
                        } else if a == b {
                            equal += 1
                        } else {
                            different += 1
                            details.append("\(index):\(name)")
                            self.savePNG(first, name: "parity\(index)-legacy")
                            self.savePNG(candidate, name: "parity\(index)-layers")
                        }
                        step(index + 1)
                    })
                    })
                })
            })
        }
        step(0)
    }

    private func captureWindow(_ window: NSWindow, name: String) {
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let createImage = unsafeBitCast(symbol, to: CreateImage.self)
            if let image = createImage(.null, CGWindowListOption.optionIncludingWindow.rawValue, UInt32(window.windowNumber), CGWindowImageOption.boundsIgnoreFraming.rawValue | CGWindowImageOption.nominalResolution.rawValue)?.takeRetainedValue() {
                let url = self.configuration.outputDirectory.appendingPathComponent("chat-navigation-\(self.configuration.label)-\(name).png")
                if let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
                    CGImageDestinationAddImage(destination, image, nil)
                    CGImageDestinationFinalize(destination)
                }
            }
        }
    }

    private func runWidgetInline(completion: @escaping () -> Void) {
        guard let peer = self.controller?.chatInteraction.presentation.peer as? TelegramUser, peer.botInfo != nil else {
            self.report.add(scenario: "widget-inline", run: 0, metrics: ["errors": 1], notes: ["error": "current chat is not a bot"])
            completion()
            return
        }
        let notes = ["bot": peer.addressName ?? "", "inlinePlaceholder": peer.botInfo?.inlinePlaceholder ?? "<absent>"]
        let query = self.configuration.string("-PerfLabWidgetInlineQuery", "live")
        self.loadDisposable = (self.context.engine.messages.requestChatContextResults(botId: peer.id, peerId: peer.id, query: query, offset: "") |> take(1) |> deliverOnMainQueue).start(next: { [weak self] response in
            guard let self else { return }
            let results = response?.results.results ?? []
            let widgets = results.filter { result in
                if case .widget = result.message { return true }
                return false
            }
            var notes = notes
            notes["query"] = query
            notes["titles"] = results.compactMap { $0.title }.joined(separator: " | ")
            self.report.add(scenario: "widget-inline", run: 0, metrics: ["results": Double(results.count), "widgets": Double(widgets.count), "errors": 0, "hasResponse": response == nil ? 0 : 1], notes: notes)
            completion()
        }, error: { [weak self] error in
            var notes = notes
            notes["error"] = String(describing: error)
            self?.report.add(scenario: "widget-inline", run: 0, metrics: ["errors": 1], notes: notes)
            completion()
        })
    }

    private struct WidgetActionPlan: Decodable {
        let contains: String
        let actions: [[String: String]]
    }

    private func runWidgetActions(_ item: ChatHTMLRowItem, index: Int, plans: [WidgetActionPlan], completion: @escaping () -> Void) {
        guard let table = item.table, let plan = plans.first(where: { item.state.source.contains($0.contains) }) else {
            completion()
            return
        }
        let clock = PerfLabFrameClock(view: table)
        clock.start()
        let start = Date().timeIntervalSince1970
        var missing = 0
        var mismatches = 0
        var outcomes: [String] = []
        func step(_ actionIndex: Int) {
            guard actionIndex < plan.actions.count else {
                clock.stop()
                self.report.add(scenario: "widget-interactions", run: index, metrics: ["startUnixTime": start, "endUnixTime": Date().timeIntervalSince1970, "actions": Double(plan.actions.count), "missingActions": Double(missing), "heightMismatch": Double(mismatches), "frames": Double(clock.stats.frames), "hitches": Double(clock.stats.hitches), "longHitches": Double(clock.stats.longHitches), "worstGapMs": clock.stats.worstGap * 1000], notes: ["widget": plan.contains, "message": "\(item.message?.id.id ?? 0)", "actions": outcomes.joined(separator: "\n"), "state": item.state.debugTwidgetSummary])
                if let view = table.item(stableId: item.stableId)?.view {
                    self.captureView(view, name: "widget\(index)-final")
                }
                completion()
                return
            }
            let attributes = plan.actions[actionIndex]
            item.state.debugTwidgetClick(attributes: attributes) { found in
                if !found { missing += 1 }
                Queue.mainQueue().after(self.configuration.double("-PerfLabWidgetActionWait", 0.35), {
                    let current = (table.item(stableId: item.stableId) as? ChatHTMLRowItem) ?? item
                    let laid = current.state.layout(width: current.renderWidth, appearance: current.appearance)
                    let mismatch = abs(laid.height + current.state.statsReservedHeight - current.contentSize.height) > 1
                    if mismatch { mismatches += 1 }
                    outcomes.append("\(actionIndex): \(attributes.sorted(by: { $0.key < $1.key }).map { "\($0.key)=\($0.value)" }.joined(separator: ",")) found=\(found) height=\(Int(laid.height)) mismatch=\(mismatch)")
                    if self.configuration.double("-PerfLabWidgetCaptureActions", 0) != 0, let view = current.view {
                        self.captureView(view, name: "widget\(index)-action\(actionIndex)")
                    }
                    current.state.debugTwidgetFrameState { frameState in
                        outcomes.append("\(actionIndex) renderer: \(frameState)")
                        step(actionIndex + 1)
                    }
                })
            }
        }
        step(0)
    }

    private func runWidgets(completion: @escaping () -> Void) {
        guard let table = self.controller?.genericView.tableView else {
            completion()
            return
        }
        var items: [ChatHTMLRowItem] = []
        var seen = Set<AnyHashable>()
        func appendLoadedItems() -> Int {
            let previousCount = items.count
            table.enumerateItems(with: { item in
                if let item = item as? ChatHTMLRowItem, seen.insert(item.stableId).inserted {
                    items.append(item)
                }
                return true
            })
            return items.count - previousCount
        }
        _ = appendLoadedItems()
        var historyPasses = max(1, Int(self.configuration.double("-PerfLabWidgetHistoryPasses", 1)))
        var rows: [String] = []
        var unavailable = 0, dead = 0, errors = 0, mismatched = 0
        let planPath = self.configuration.string("-PerfLabWidgetActions", "")
        var plans: [WidgetActionPlan] = []
        if !planPath.isEmpty {
            do {
                plans = try JSONDecoder().decode([WidgetActionPlan].self, from: Data(contentsOf: URL(fileURLWithPath: planPath)))
            } catch {
                self.report.add(scenario: "widgets", run: 0, metrics: ["errors": 1], notes: ["error": "Invalid action plan: \(error)"])
                completion()
                return
            }
        }
        let sourcePath = self.configuration.string("-PerfLabWidgetSources", "")
        if !sourcePath.isEmpty {
            try? FileManager.default.createDirectory(atPath: sourcePath, withIntermediateDirectories: true)
        }
        func step(_ index: Int) {
            guard index < items.count else {
                if historyPasses > 1 {
                    historyPasses -= 1
                    if appendLoadedItems() > 0 {
                        step(index)
                        return
                    }
                }
                self.report.add(scenario: "widgets", run: 0, metrics: ["widgets": Double(items.count), "unavailable": Double(unavailable), "dead": Double(dead), "errors": Double(errors), "heightMismatch": Double(mismatched)], notes: ["rows": rows.joined(separator: "\n")])
                completion()
                return
            }
            let item = items[index]
            table.scroll(to: .center(id: item.stableId, innerId: nil, animated: false, focus: .init(focus: false), inset: 0), inset: NSEdgeInsets(), toVisible: false)
            Queue.mainQueue().after(self.configuration.double("-PerfLabWidgetWait", 2.0), { [weak self] in
                guard let self else {
                    return
                }
                let item = (table.item(stableId: item.stableId) as? ChatHTMLRowItem) ?? item
                let state = item.state
                if !sourcePath.isEmpty {
                    try? state.source.write(toFile: (sourcePath as NSString).appendingPathComponent("\(item.message?.id.id ?? Int32(index)).html"), atomically: true, encoding: .utf8)
                }
                let laid = state.layout(width: item.renderWidth, appearance: item.appearance)
                let summary = state.debugTwidgetSummary
                let isUnavailable = state.source.contains("Widget unavailable")
                if isUnavailable { unavailable += 1 }
                if summary.contains("dead=") && !summary.contains("dead=-") { dead += 1 }
                if !summary.contains("lastError=-") || summary.contains("errors=") && !summary.hasSuffix("errors=") { errors += 1 }
                if abs(laid.height + state.statsReservedHeight - item.contentSize.height) > 1 { mismatched += 1 }
                rows.append("#\(index) id=\(item.message?.id.id ?? 0) content=\(Int(item.contentSize.width))x\(Int(item.contentSize.height)) itemHeight=\(Int(item.height)) viewHeight=\(Int(item.view?.frame.height ?? -1)) laid=\(Int(laid.width))x\(Int(laid.height)) unavailable=\(isUnavailable) \(summary)")
                if let view = item.view {
                    self.captureView(view, name: "widget\(index)")
                }
                self.runWidgetActions(item, index: index, plans: plans) {
                    step(index + 1)
                }
            })
        }
        step(0)
    }

    private func captureView(_ view: NSView, name: String) {
        let scale = view.window?.backingScaleFactor ?? 2
        let size = view.bounds.size
        guard size.width > 0, size.height > 0, let layer = view.layer, let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return
        }
        context.scaleBy(x: scale, y: scale)
        if !view.isFlipped {
            layer.render(in: context)
        } else {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
            layer.render(in: context)
        }
        guard let image = context.makeImage() else {
            return
        }
        let url = self.configuration.outputDirectory.appendingPathComponent("chat-navigation-\(self.configuration.label)-\(name).png")
        if let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }

    private func runSnapshots(index: Int, completion: @escaping () -> Void) {
        let count = Int(self.configuration.double("-PerfLabSnapshots", 3.0))
        guard index < count, let table = self.controller?.genericView.tableView, let window = table.window else {
            completion()
            return
        }
        self.captureWindow(window, name: "snapshot\(index)")
        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(1200 * self.wheelSign), wheel2: 0, wheel3: 0), let nsEvent = NSEvent(cgEvent: event) {
            table.scrollWheel(with: nsEvent)
        }
        Queue.mainQueue().after(1.5, { [weak self] in
            self?.runSnapshots(index: index + 1, completion: completion)
        })
    }

    private func runTyping(index: Int, completion: @escaping () -> Void) {
        let runs = Int(self.configuration.double("-PerfLabRuns", 2.0))
        guard index < runs, let controller = self.controller, controller.chatInteraction.peerId == self.context.peerId else {
            completion()
            return
        }
        let textView = controller.genericView.inputView.textView.view.textView
        let table = controller.genericView.tableView
        let text = Array("The quick brown fox jumps over the lazy dog while the chat keeps scrolling smoothly, and every keystroke should stay cheap. ")
        let interval = 1.0 / self.configuration.double("-PerfLabTypingRate", 15.0)
        let clock = PerfLabFrameClock(view: table)
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        clock.start()
        func type(_ position: Int) {
            if position < text.count {
                textView.insertText(String(text[position]), replacementRange: NSRange(location: NSNotFound, length: 0))
                Queue.mainQueue().after(interval, {
                    type(position + 1)
                })
                return
            }
            clock.stop()
            let end = self.processMonitor.snapshot()
            let elapsed = max(0.001, end.time - start.time)
            self.report.add(scenario: "typing", run: index, metrics: [
                "characters": Double(text.count),
                "cpuCores": (end.cpuTime - start.cpuTime) / elapsed,
                "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / elapsed * 100,
                "mainMsPerCharacter": (end.mainThreadCpuTime - start.mainThreadCpuTime) * 1000 / Double(text.count),
                "hitches": Double(clock.stats.hitches),
                "worstGapMs": clock.stats.worstGap * 1000,
                "startUnixTime": startUnixTime,
                "endUnixTime": Date().timeIntervalSince1970
            ], notes: self.chatNotes)
            if self.configuration.double("-PerfLabTypingSnapshot", 0.0) != 0, let window = table.window {
                self.captureWindow(window, name: "typing\(index)")
            }
            textView.selectAll(nil)
            textView.deleteBackward(nil)
            Queue.mainQueue().after(2.0, { [weak self] in
                self?.runTyping(index: index + 1, completion: completion)
            })
        }
        type(0)
    }

    private func runResize(index: Int, completion: @escaping () -> Void) {
        let runs = Int(self.configuration.double("-PerfLabRuns", 2.0))
        guard index < runs, let table = self.controller?.genericView.tableView, let window = table.window else {
            completion()
            return
        }
        let original = window.frame
        let delta = CGFloat(self.configuration.double("-PerfLabResizeDelta", 240.0))
        let steps = Int(self.configuration.double("-PerfLabResizeSteps", 30.0))
        var widths: [CGFloat] = []
        for i in 0 ... steps {
            widths.append(original.width - delta * CGFloat(i) / CGFloat(steps))
        }
        widths += widths.reversed()
        let clock = PerfLabFrameClock(view: table)
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        clock.start()
        func step(_ position: Int) {
            if position < widths.count {
                window.setFrame(NSMakeRect(original.minX, original.minY, widths[position], original.height), display: true)
                Queue.mainQueue().after(1.0 / 30.0, {
                    step(position + 1)
                })
                return
            }
            clock.stop()
            window.setFrame(original, display: true)
            let end = self.processMonitor.snapshot()
            let elapsed = max(0.001, end.time - start.time)
            self.report.add(scenario: "resize", run: index, metrics: [
                "steps": Double(widths.count),
                "cpuCores": (end.cpuTime - start.cpuTime) / elapsed,
                "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / elapsed * 100,
                "mainMsPerStep": (end.mainThreadCpuTime - start.mainThreadCpuTime) * 1000 / Double(widths.count),
                "hitches": Double(clock.stats.hitches),
                "worstGapMs": clock.stats.worstGap * 1000,
                "rows": Double(table.count),
                "startUnixTime": startUnixTime,
                "endUnixTime": Date().timeIntervalSince1970
            ], notes: self.chatNotes)
            Queue.mainQueue().after(2.0, { [weak self] in
                self?.runResize(index: index + 1, completion: completion)
            })
        }
        step(0)
    }

    private func runSelection(index: Int, completion: @escaping () -> Void) {
        let runs = Int(self.configuration.double("-PerfLabRuns", 2.0))
        guard index < runs, let controller = self.controller else {
            completion()
            return
        }
        let table = controller.genericView.tableView
        var ids: [MessageId] = []
        let range = table.visibleRows()
        if range.length > 0 {
            for row in range.location ..< range.location + range.length {
                if let item = table.item(at: row) as? ChatRowItem, let id = item.message?.id {
                    ids.append(id)
                }
            }
        }
        let actions = 1 + ids.count * 2 + 1
        let clock = PerfLabFrameClock(view: table)
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        clock.start()
        func step(_ position: Int) {
            if position == 0 {
                controller.chatInteraction.update({ $0.withSelectionState() })
            } else if position <= ids.count * 2 {
                let id = ids[(position - 1) % ids.count]
                controller.chatInteraction.update({ $0.withToggledSelectedMessage(id) })
            } else {
                controller.chatInteraction.update({ $0.withoutSelectionState() })
            }
            if position + 1 < actions {
                Queue.mainQueue().after(1.0 / 20.0, {
                    step(position + 1)
                })
                return
            }
            Queue.mainQueue().after(0.5, { [weak self] in
                guard let self else {
                    return
                }
                clock.stop()
                let end = self.processMonitor.snapshot()
                let elapsed = max(0.001, end.time - start.time)
                self.report.add(scenario: "selection", run: index, metrics: [
                    "actions": Double(actions),
                    "cpuCores": (end.cpuTime - start.cpuTime) / elapsed,
                    "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / elapsed * 100,
                    "mainMsPerAction": (end.mainThreadCpuTime - start.mainThreadCpuTime) * 1000 / Double(actions),
                    "hitches": Double(clock.stats.hitches),
                    "worstGapMs": clock.stats.worstGap * 1000,
                    "startUnixTime": startUnixTime,
                    "endUnixTime": Date().timeIntervalSince1970
                ], notes: self.chatNotes)
                Queue.mainQueue().after(1.5, { [weak self] in
                    self?.runSelection(index: index + 1, completion: completion)
                })
            })
        }
        step(0)
    }

    private func runIdle(index: Int, completion: @escaping () -> Void) {
        let runs = Int(self.configuration.double("-PerfLabRuns", 2.0))
        guard index < runs, let table = self.controller?.genericView.tableView else {
            completion()
            return
        }
        let duration = self.configuration.double("-PerfLabIdleDuration", 10.0)
        let clock = PerfLabFrameClock(view: table)
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        clock.start()
        Queue.mainQueue().after(duration, { [weak self] in
            guard let self else {
                return
            }
            clock.stop()
            let end = self.processMonitor.snapshot()
            let elapsed = max(0.001, end.time - start.time)
            self.report.add(scenario: "idle", run: index, metrics: [
                "cpuCores": (end.cpuTime - start.cpuTime) / elapsed,
                "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / elapsed * 100,
                "hitches": Double(clock.stats.hitches),
                "footprintMB": Double(end.footprint) / 1048576.0,
                "startUnixTime": startUnixTime,
                "endUnixTime": Date().timeIntervalSince1970
            ], notes: self.chatNotes)
            self.runIdle(index: index + 1, completion: completion)
        })
    }

    private func runOpens(remaining: Int, index: Int, completion: @escaping () -> Void) {
        guard let peerId = self.openPeerId ?? self.controller?.chatInteraction.peerId else {
            completion()
            return
        }
        self.openPeerId = peerId
        if self.controller != nil {
            self.context.bindings.rootNavigation().back()
            self.controller = nil
            Queue.mainQueue().after(1.5, { [weak self] in
                self?.runOpens(remaining: remaining, index: index, completion: completion)
            })
            return
        }
        guard remaining > 0 else {
            let controller = self.makeChatController(context: self.context, peerId: peerId)
            self.controller = controller
            self.context.bindings.rootNavigation().push(controller)
            Queue.mainQueue().after(3.0, completion)
            return
        }
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        let startedAt = CACurrentMediaTime()
        let controller = self.makeChatController(context: self.context, peerId: peerId)
        self.context.bindings.rootNavigation().push(controller)
        var firstRowsAt: Double?
        func poll() {
            let elapsed = CACurrentMediaTime() - startedAt
            if firstRowsAt == nil, controller.genericView.tableView.count > 1 {
                firstRowsAt = elapsed
            }
            if elapsed < 2.0 {
                Queue.mainQueue().after(1.0 / 60.0, poll)
                return
            }
            let end = self.processMonitor.snapshot()
            let duration = max(0.001, end.time - start.time)
            self.report.add(scenario: "open", run: index, metrics: [
                "firstRowsSeconds": firstRowsAt ?? -1,
                "rows": Double(controller.genericView.tableView.count),
                "cpuSeconds": end.cpuTime - start.cpuTime,
                "cpuCores": (end.cpuTime - start.cpuTime) / duration,
                "mainThreadSeconds": end.mainThreadCpuTime - start.mainThreadCpuTime,
                "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / duration * 100,
                "footprintMB": Double(end.footprint) / 1048576.0,
                "startUnixTime": startUnixTime,
                "endUnixTime": Date().timeIntervalSince1970
            ], notes: self.chatNotes)
            self.context.bindings.rootNavigation().back()
            Queue.mainQueue().after(1.5, { [weak self] in
                self?.runOpens(remaining: remaining - 1, index: index + 1, completion: completion)
            })
        }
        poll()
    }

    private func runContextPopup(index: Int, completion: @escaping () -> Void) {
        guard index < 2, let controller = self.controller, let peer = controller.chatInteraction.peer else {
            completion()
            return
        }
        let helper = controller.genericView.inputContextHelper
        let createdBefore = helper.accessoryView != nil
        controller.chatInteraction.update { $0.updatedInputQueryResult { _ in .mentions([peer]) } }
        Queue.mainQueue().after(1.0, { [weak self] in
            let shown = helper.accessoryView != nil && helper.controller.genericView.tableView.count > 0
            controller.chatInteraction.update { $0.updatedInputQueryResult { _ in nil } }
            Queue.mainQueue().after(1.0, { [weak self] in
                let hidden = helper.accessoryView == nil
                self?.report.add(scenario: "contextpopup", run: index, metrics: ["visibleBefore": createdBefore ? 1 : 0, "shown": shown ? 1 : 0, "hidden": hidden ? 1 : 0], notes: [:])
                self?.runContextPopup(index: index + 1, completion: completion)
            })
        })
    }

    private struct OpenTraceFrame {
        let time: Double
        let rows: Int
        let shown: Bool
        let pixels: [UInt8]?
    }

    private func openTracePixels(_ view: NSView) -> [UInt8]? {
        let width = Int(view.bounds.width / 4)
        let height = Int(view.bounds.height / 4)
        guard width > 0, height > 0, let layer = view.layer, let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return nil
        }
        context.scaleBy(x: 0.25, y: 0.25)
        if view.isFlipped {
            context.translateBy(x: 0, y: view.bounds.height)
            context.scaleBy(x: 1, y: -1)
        }
        layer.render(in: context)
        guard let data = context.data else {
            return nil
        }
        return Array(UnsafeBufferPointer(start: data.assumingMemoryBound(to: UInt8.self), count: width * height))
    }

    private func writeOpenTraceFrame(_ pixels: [UInt8], view: NSView, name: String) {
        let width = Int(view.bounds.width / 4)
        let height = Int(view.bounds.height / 4)
        guard pixels.count == width * height, let provider = CGDataProvider(data: Data(pixels) as CFData), let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            return
        }
        let url = self.configuration.outputDirectory.appendingPathComponent("chat-navigation-\(self.configuration.label)-\(name).png")
        if let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) {
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
        }
    }

    private static func collectAnimations(_ view: NSView, into result: inout [String: Int], frame: Int) {
        func visit(_ layer: CALayer, owner: String) {
            let name = (layer.delegate as? NSView).map { String(describing: type(of: $0)) } ?? owner
            if let keys = layer.animationKeys(), !keys.isEmpty {
                var path: [String] = []
                var superview = (layer.delegate as? NSView)?.superview
                while let current = superview, path.count < 4 {
                    path.append(String(describing: type(of: current)))
                    superview = current.superview
                }
                let details = keys.sorted().map { key -> String in
                    if let animation = layer.animation(forKey: key) as? CABasicAnimation {
                        let age = animation.beginTime == 0 ? "new" : String(format: "%.0f", (CACurrentMediaTime() - layer.convertTime(animation.beginTime, to: nil)) * 1000)
                        return "\(key)[\(animation.fromValue.map { "\($0)" } ?? "-")->\(animation.toValue.map { "\($0)" } ?? "-") \(String(format: "%.2f", animation.duration)) age=\(age)]"
                    }
                    return key
                }
                result["f\(frame) \(name)<\(path.joined(separator: "<")) \(details.joined(separator: ","))", default: 0] += 1
            }
            for sublayer in layer.sublayers ?? [] where !(sublayer.delegate is NSView) {
                visit(sublayer, owner: name)
            }
        }
        func visit(_ view: NSView) {
            if let layer = view.layer {
                visit(layer, owner: String(describing: type(of: view)))
            }
            for subview in view.subviews {
                visit(subview)
            }
        }
        visit(view)
    }

    private static func openTraceDifference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Double {
        guard lhs.count == rhs.count, !lhs.isEmpty else {
            return 100
        }
        var changed = 0
        for index in 0 ..< lhs.count where abs(Int(lhs[index]) - Int(rhs[index])) > 24 {
            changed += 1
        }
        return Double(changed) / Double(lhs.count) * 100
    }

    private func runOpenTraces(peers: [PeerId], remaining: Int, index: Int, completion: @escaping () -> Void) {
        guard remaining > 0, !peers.isEmpty, let contentView = self.context.window.contentView else {
            completion()
            return
        }
        let capture = self.configuration.double("-PerfLabOpenCapture", 0) != 0
        if index == 0 {
            self.controller = nil
        }
        let settle = self.configuration.double("-PerfLabOpenSettle", 1.5)
        let peerId = peers[index % peers.count]
        let clock = PerfLabFrameClock(view: contentView)
        var frames: [OpenTraceFrame] = []
        var readyAt: Double?
        var shownAt: Double?
        var firstRowsAt: Double?
        var animationFrames = 0
        var animations: [String: Int] = [:]
        var dirty: [String: Int] = [:]
        let start = self.processMonitor.snapshot()
        ChatOpenProbe.begin()
        let startedAt = CACurrentMediaTime()
        if capture, let pixels = self.openTracePixels(contentView) {
            frames.append(OpenTraceFrame(time: 0, rows: 0, shown: false, pixels: pixels))
        }
        clock.start()
        let controller = self.makeChatController(context: self.context, peerId: peerId)
        let readyDisposable = (controller.ready.get() |> filter { $0 } |> take(1)).start(next: { _ in
            readyAt = CACurrentMediaTime() - startedAt
            ChatOpenProbe.mark("ready")
        })
        self.context.bindings.rootNavigation().push(controller)
        ChatOpenProbe.mark("pushed")
        var lastTick: Double?
        clock.onFrame = { [weak self, weak controller] timestamp in
            if let lastTick, timestamp - lastTick > 0.0125 {
                ChatOpenProbe.mark(String(format: "gap %.1f", (timestamp - lastTick) * 1000))
            }
            lastTick = timestamp
            guard let self, let controller else {
                return
            }
            let elapsed = CACurrentMediaTime() - startedAt
            let shown = controller.view.window != nil
            let rows = controller.genericView.tableView.count
            if shown, shownAt == nil {
                shownAt = elapsed
                ChatOpenProbe.mark("frame.shown rows=\(rows)")
                if self.configuration.double("-PerfLabShownMarker", 0) != 0 {
                    perfLabShownMarker()
                }
            }
            if shown, rows > 1, firstRowsAt == nil {
                firstRowsAt = elapsed
                ChatOpenProbe.mark("frame.rows rows=\(rows)")
            }
            if shown, animationFrames < 2 {
                animationFrames += 1
                Self.collectAnimations(controller.view, into: &animations, frame: animationFrames)
                if let root = controller.view.window?.contentView {
                    func walk(_ view: NSView) {
                        var flags: [String] = []
                        if view.needsUpdateConstraints {
                            flags.append("constraints")
                        }
                        if view.needsLayout {
                            flags.append("layout")
                        }
                        if !flags.isEmpty {
                            var path: [String] = [String(describing: type(of: view))]
                            var superview = view.superview
                            while let current = superview, path.count < 4 {
                                path.append(String(describing: type(of: current)))
                                superview = current.superview
                            }
                            dirty["f\(animationFrames) \(flags.joined(separator: "+")) \(view.isHiddenOrHasHiddenAncestor ? "hidden" : "visible") \(path.joined(separator: "<"))", default: 0] += 1
                        }
                        for subview in view.subviews {
                            walk(subview)
                        }
                    }
                    walk(root)
                }
            }
            if capture, elapsed < settle {
                frames.append(OpenTraceFrame(time: elapsed, rows: rows, shown: shown, pixels: self.openTracePixels(contentView)))
            }
        }
        Queue.mainQueue().after(settle + 0.5, { [weak self] in
            guard let self else {
                return
            }
            clock.stop()
            readyDisposable.dispose()
            let events = ChatOpenProbe.end()
            let end = self.processMonitor.snapshot()
            let stats = clock.stats
            var metrics: [String: Double] = [
                "readyMs": (readyAt ?? -1) * 1000,
                "shownMs": (shownAt ?? -1) * 1000,
                "firstRowsMs": (firstRowsAt ?? -1) * 1000,
                "hitches": Double(stats.hitches),
                "longHitches": Double(stats.longHitches),
                "worstGapMs": stats.worstGap * 1000,
                "mainThreadMs": (end.mainThreadCpuTime - start.mainThreadCpuTime) * 1000,
                "rows": Double(controller.genericView.tableView.count)
            ]
            var notes = self.chatNotes
            notes["peer"] = "\(peerId.toInt64())"
            notes["hostStart"] = String(format: "%.4f", startedAt)
            notes["animations"] = animations.sorted(by: { $0.key < $1.key }).map { "\($0.key) x\($0.value)" }.joined(separator: "\n")
            metrics["animatedLayers"] = Double(animations.values.reduce(0, +))
            var glass: [String: Int] = [:]
            func countGlass(_ view: NSView) {
                if NSStringFromClass(type(of: view)).contains("GlassEffectView") {
                    var path: [String] = []
                    var superview = view.superview
                    while let current = superview, path.count < 3 {
                        path.append(String(describing: type(of: current)))
                        superview = current.superview
                    }
                    glass["\(view.isHiddenOrHasHiddenAncestor ? "hidden" : "visible") \(path.joined(separator: "<"))", default: 0] += 1
                }
                for subview in view.subviews {
                    countGlass(subview)
                }
            }
            countGlass(controller.view)
            notes["glass"] = glass.sorted(by: { $0.key < $1.key }).map { "\($0.key) x\($0.value)" }.joined(separator: "\n")
            notes["dirty"] = dirty.sorted(by: { $0.key < $1.key }).map { "\($0.key) x\($0.value)" }.joined(separator: "\n")
            notes["events"] = events.map { String(format: "%.1f %@", $0.1 * 1000, $0.0) }.joined(separator: "\n")
            if capture, let first = frames.first?.pixels, let last = frames.last?.pixels {
                self.writeOpenTraceFrame(first, view: contentView, name: String(format: "open%02d-first", index))
                self.writeOpenTraceFrame(last, view: contentView, name: String(format: "open%02d-last", index))
            }
            if capture, let last = frames.last?.pixels {
                var changes: [String] = []
                var regressions = 0
                var previous: OpenTraceFrame?
                for frame in frames {
                    if let previous, let lhs = previous.pixels, let rhs = frame.pixels {
                        let step = Self.openTraceDifference(lhs, rhs)
                        if step > 0.05 {
                            let before = Self.openTraceDifference(lhs, last)
                            let after = Self.openTraceDifference(rhs, last)
                            if after > before + 0.5 {
                                regressions += 1
                            }
                            changes.append(String(format: "%.1fms rows=%d shown=%d step=%.2f%% toFinal=%.2f%%", frame.time * 1000, frame.rows, frame.shown ? 1 : 0, step, after))
                            self.writeOpenTraceFrame(rhs, view: contentView, name: String(format: "open%02d-%04d", index, Int(frame.time * 1000)))
                        }
                    }
                    previous = frame
                }
                metrics["visualChanges"] = Double(changes.count)
                metrics["regressions"] = Double(regressions)
                metrics["capturedFrames"] = Double(frames.count)
                notes["changes"] = changes.joined(separator: "\n")
            }
            self.report.add(scenario: "opentrace", run: index, metrics: metrics, notes: notes)
            if self.configuration.double("-PerfLabPostEvents", 0) != 0, let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
                NSApp.postEvent(event, atStart: false)
            }
            Queue.mainQueue().after(0.5, { [weak self] in
                self?.runOpenTraces(peers: peers, remaining: remaining - 1, index: index + 1, completion: completion)
            })
        })
    }

    private func waitForPinned(attempts: Int, completion: @escaping () -> Void) {
        if attempts <= 0 || self.controller?.chatInteraction.presentation.pinnedMessageId != nil {
            completion()
            return
        }
        Queue.mainQueue().after(0.25, { [weak self] in
            self?.waitForPinned(attempts: attempts - 1, completion: completion)
        })
    }

    private func runPinned(remaining: Int, completion: @escaping () -> Void) {
        guard remaining > 0, let controller = self.controller, let pinned = controller.chatInteraction.presentation.pinnedMessageId else {
            completion()
            return
        }
        let target = pinned.messageId
        self.navigate(name: "\(self.namePrefix)pinned", target: target, notes: self.chatNotes.merging(["pinnedIndex": "\(pinned.index)", "pinnedTotal": "\(pinned.totalCount)"], uniquingKeysWith: { $1 }), action: {
            controller.chatInteraction.focusPinnedMessageId(target)
        }, after: { [weak controller] in
            let next = controller?.chatInteraction.presentation.pinnedMessageId?.messageId
            return ["barAdvanced": next != nil && next != target ? 1.0 : 0.0, "barCleared": next == nil ? 1.0 : 0.0]
        }, completion: { [weak self] in
            self?.traceBar(ticks: 20, trace: [], completion: { [weak self] trace in
                self?.report.add(scenario: "\(self?.namePrefix ?? "")barTrace", run: 0, metrics: [:], notes: ["target": "\(target.id)", "trace": trace.joined(separator: ",")])
                self?.runPinned(remaining: remaining - 1, completion: completion)
            })
        })
    }

    private func traceBar(ticks: Int, trace: [String], completion: @escaping ([String]) -> Void) {
        var trace = trace
        let current = self.controller?.chatInteraction.presentation.pinnedMessageId.map { "\($0.messageId.id)" } ?? "nil"
        if trace.last != current {
            trace.append(current)
        }
        if ticks <= 0 {
            completion(trace)
            return
        }
        Queue.mainQueue().after(0.1, { [weak self] in
            self?.traceBar(ticks: ticks - 1, trace: trace, completion: completion)
        })
    }

    private func runJumps(targets: [MessageId], completion: @escaping () -> Void) {
        guard let target = targets.first, let controller = self.controller else {
            completion()
            return
        }
        let rest = Array(targets.dropFirst())
        controller.chatInteraction.scrollToLatest(true)
        Queue.mainQueue().after(2.0, { [weak self] in
            guard let self else {
                return
            }
            self.navigate(name: "\(self.namePrefix)jump", target: target, notes: self.chatNotes, action: {
                controller.chatInteraction.focusMessageId(nil, .init(messageId: target, string: nil), .CenterEmpty)
            }, completion: { [weak self] in
                Queue.mainQueue().after(1.0, {
                    self?.runJumps(targets: rest, completion: completion)
                })
            })
        })
    }

    private func rowRect(for messageId: MessageId) -> (rect: NSRect, visible: NSRect)? {
        guard let table = self.controller?.genericView.tableView else {
            return nil
        }
        let range = table.visibleRows()
        guard range.length > 0 else {
            return nil
        }
        let clip = table.clipView
        let presented = clip.layer?.presentation()?.bounds ?? clip.bounds
        for row in range.location ..< range.location + range.length {
            if let item = table.item(at: row) as? ChatRowItem, item.messages.contains(where: { $0.id == messageId }) {
                let rect = table.rectOf(index: row)
                guard rect.intersects(presented) else {
                    return nil
                }
                return (rect, presented)
            }
        }
        return nil
    }

    private func navigate(name: String, target: MessageId, notes: [String: String], action: () -> Void, after: (() -> [String: Double])? = nil, completion: @escaping () -> Void) {
        guard let table = self.controller?.genericView.tableView else {
            completion()
            return
        }
        self.navigationIndex += 1
        let index = self.navigationIndex
        var notes = notes
        notes["messageId"] = "\(target.id)"
        if Int(self.configuration.double("-PerfLabSampleNavigation", 0.0)) == index {
            let process = Process()
            process.launchPath = "/usr/bin/sample"
            process.arguments = ["\(ProcessInfo.processInfo.processIdentifier)", "3", "-file", self.configuration.outputDirectory.appendingPathComponent("chat-navigation-\(self.configuration.label)-nav\(index).sample.txt").path]
            try? process.run()
        }
        let wasVisibleBefore = self.rowRect(for: target) != nil
        let destinationAtStart = table.clipView.destination != nil
        let start = self.processMonitor.snapshot()
        let startUnixTime = Date().timeIntervalSince1970
        let startedAt = CACurrentMediaTime()
        let clock = PerfLabFrameClock(view: table)
        var coverageFrames = 0
        var blankFrames = 0
        var worstBlank: CGFloat = 0
        var travel: CGFloat = 0
        var lastPresentedY: CGFloat?
        var blankTrace: [String] = []
        var uncommittedFrames = 0
        var teleports = 0
        clock.onFrame = { [weak table] _ in
            guard let table, let rows = table.documentView as? NSTableView else {
                return
            }
            let clip = table.clipView
            let presented = clip.layer?.presentation()?.bounds ?? clip.bounds
            if abs(presented.minY - clip.bounds.minY) > clip.bounds.height * 1.5 {
                uncommittedFrames += 1
                return
            }
            if let lastPresentedY {
                let delta = abs(presented.minY - lastPresentedY)
                if delta > presented.height {
                    teleports += 1
                } else {
                    travel += delta
                }
            }
            lastPresentedY = presented.minY
            let range = rows.rows(in: presented)
            var blank: CGFloat = 0
            if range.length > 0 {
                for row in range.location ..< range.location + range.length {
                    if rows.rowView(atRow: row, makeIfNecessary: false) == nil {
                        blank += rows.rect(ofRow: row).intersection(presented).height
                    }
                }
            }
            coverageFrames += 1
            if blank > 0 {
                blankFrames += 1
                worstBlank = max(worstBlank, blank)
                if blankTrace.count < 6 {
                    let prepared = rows.preparedContentRect
                    let visible = rows.visibleRect
                    var available: [Int] = []
                    rows.enumerateAvailableRowViews { _, row in
                        available.append(row)
                    }
                    blankTrace.append("f\(coverageFrames) pres=\(Int(presented.minY))..\(Int(presented.maxY)) vis=\(Int(visible.minY))..\(Int(visible.maxY)) prep=\(Int(prepared.minY))..\(Int(prepared.maxY)) need=\(range.location)..<\(range.location + range.length) have=\(available.min() ?? -1)...\(available.max() ?? -1)#\(available.count) blank=\(Int(blank))")
                }
            }
        }
        clock.start()
        action()
        let timeout = self.configuration.double("-PerfLabNavigationTimeout", 8.0)
        var visibleAt: Double?
        var lastMinY: CGFloat?
        var stableTicks = 0
        func poll() {
            let now = CACurrentMediaTime()
            let elapsed = now - startedAt
            if let (rect, visible) = self.rowRect(for: target) {
                if visibleAt == nil {
                    visibleAt = elapsed
                }
                let offset = rect.minY - visible.minY
                if let lastMinY, abs(lastMinY - offset) < 0.5 {
                    stableTicks += 1
                } else {
                    stableTicks = 0
                }
                lastMinY = offset
                if stableTicks >= 6 && elapsed > 0.3 {
                    done(settledAt: elapsed, rect: rect, visible: visible)
                    return
                }
            } else {
                stableTicks = 0
                lastMinY = nil
            }
            if elapsed > timeout {
                done(settledAt: nil, rect: nil, visible: nil)
                return
            }
            Queue.mainQueue().after(1.0 / 60.0, poll)
        }
        func done(settledAt: Double?, rect: NSRect?, visible: NSRect?) {
            clock.stop()
            let end = self.processMonitor.snapshot()
            let duration = max(0.001, end.time - start.time)
            var metrics: [String: Double] = [
                "found": settledAt == nil ? 0.0 : 1.0,
                "visibleSeconds": visibleAt ?? -1.0,
                "settledSeconds": settledAt ?? -1.0,
                "wasVisibleBefore": wasVisibleBefore ? 1.0 : 0.0,
                "hitches": Double(clock.stats.hitches),
                "worstGapMs": clock.stats.worstGap * 1000,
                "cpuCores": (end.cpuTime - start.cpuTime) / duration,
                "mainThreadBusyPercent": (end.mainThreadCpuTime - start.mainThreadCpuTime) / duration * 100,
                "footprintMB": Double(end.footprint) / 1048576.0,
                "frames": Double(coverageFrames),
                "blankFrames": Double(blankFrames),
                "worstBlankPx": Double(worstBlank),
                "scrollTravelPx": Double(travel),
                "uncommittedFrames": Double(uncommittedFrames),
                "teleports": Double(teleports),
                "destinationAtStart": destinationAtStart ? 1.0 : 0.0,
                "windowKey": table.window?.isKeyWindow == true ? 1.0 : 0.0,
                "startUnixTime": startUnixTime,
                "endUnixTime": Date().timeIntervalSince1970
            ]
            if let after {
                for (key, value) in after() {
                    metrics[key] = value
                }
            }
            if let rect, let visible, visible.height > 0 {
                metrics["finalOffsetPx"] = rect.minY - visible.minY
                metrics["rowHeight"] = rect.height
                metrics["centerOffset"] = (rect.midY - visible.midY) / visible.height
                metrics["fullyVisible"] = visible.contains(rect) || rect.height > visible.height ? 1.0 : 0.0
            }
            if !blankTrace.isEmpty {
                notes["blankTrace"] = blankTrace.joined(separator: " | ")
            }
            self.report.add(scenario: "\(name)-\(index)", run: 0, metrics: metrics, notes: notes)
            completion()
        }
        poll()
    }

    private func readChannelsAndGroups(count: Int) -> Signal<[(PeerId, String)], NoError> {
        return self.context.engine.messages.chatList(group: .root, count: count)
        |> take(1)
        |> map { chatList -> [(PeerId, String)] in
            var result: [(PeerId, String)] = []
            for item in chatList.items.reversed() {
                guard case let .chatList(peerId) = item.id, item.readCounters?.isUnread != true, (item.readCounters?.count ?? 0) == 0, let peer = item.renderedPeer.peer else {
                    continue
                }
                if case let .channel(channel) = peer, !channel.flags.contains(.isForum) {
                    result.append((peerId, peer.debugDisplayTitle))
                } else if case .legacyGroup = peer {
                    result.append((peerId, peer.debugDisplayTitle))
                }
            }
            return result
        }
    }

    private func listReadChats() {
        self.loadDisposable = (self.readChannelsAndGroups(count: 200) |> deliverOnMainQueue).start(next: { [weak self] candidates in
            guard let self else {
                return
            }
            for (index, candidate) in candidates.enumerated() {
                self.report.add(scenario: "chat", run: index, metrics: [:], notes: ["peerId": "\(candidate.0.toInt64())", "title": candidate.1])
            }
            self.finish()
        })
    }

    private func startSweep() {
        let maxChats = Int(self.configuration.double("-PerfLabMaxChats", 8.0))
        let candidates = self.readChannelsAndGroups(count: 80)
        self.loadDisposable = (candidates |> deliverOnMainQueue).start(next: { [weak self] candidates in
            NSLog("ChatNavigationLab: %d read channels/groups", candidates.count)
            self?.sweep(candidates: candidates, chatsWithPins: 0, maxChats: maxChats)
        })
    }

    private func sweep(candidates: [(PeerId, String)], chatsWithPins: Int, maxChats: Int) {
        guard chatsWithPins < maxChats, let (peerId, title) = candidates.first else {
            self.finish()
            return
        }
        let rest = Array(candidates.dropFirst())
        let pinnedSignal = self.context.engine.messages.searchMessages(location: .peer(peerId: peerId, fromId: nil, tags: .pinned, reactions: nil, threadId: nil, minDate: nil, maxDate: nil), query: "", state: nil, limit: 20)
        |> map { $0.0.messages.map { $0.id } }
        |> take(1)
        |> timeout(10.0, queue: Queue.mainQueue(), alternate: .single([]))
        self.loadDisposable = (pinnedSignal |> deliverOnMainQueue).start(next: { [weak self] pinnedIds in
            guard let self else {
                return
            }
            guard !pinnedIds.isEmpty else {
                self.sweep(candidates: rest, chatsWithPins: chatsWithPins, maxChats: maxChats)
                return
            }
            let chatIndex = chatsWithPins
            self.namePrefix = "c\(chatIndex)-"
            self.chatNotes = ["chat": title, "pins": "\(pinnedIds.count)"]
            let controller = self.makeChatController(context: self.context, peerId: peerId)
            self.controller = controller
            self.context.bindings.rootNavigation().push(controller)
            Queue.mainQueue().after(self.configuration.double("-PerfLabOpenWait", 4.0), {
                self.runPinned(remaining: min(pinnedIds.count + 1, 6), completion: {
                    self.runJumps(targets: Array(pinnedIds.prefix(4)), completion: {
                        self.context.bindings.rootNavigation().back()
                        self.controller = nil
                        Queue.mainQueue().after(1.5, {
                            self.sweep(candidates: rest, chatsWithPins: chatsWithPins + 1, maxChats: maxChats)
                        })
                    })
                })
            })
        })
    }
}
#endif
