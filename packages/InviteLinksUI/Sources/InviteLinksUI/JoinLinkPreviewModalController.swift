import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramUtils
import TelegramTheme
import ColorPalette
import FoundationUtils
import AlertsUI
import InAppSettings
import AvatarUI
import ShortPeerRow
import AppAnalytics

private final class JoinLinkPreviewHeaderRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let peer: TelegramGroup
    fileprivate let titleLayout: TextViewLayout

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, peer: TelegramGroup) {
        self.context = context
        self.peer = peer

        let attr = NSMutableAttributedString()
        _ = attr.append(string: peer.displayTitle, color: theme.colors.text, font: .normal(.title))
        _ = attr.append(string: "\n")
        _ = attr.append(string: strings().peerStatusMemberOther(peer.participantCount).replacingOccurrences(of: "\(peer.participantCount)", with: peer.participantCount.formattedWithSeparator), color: theme.colors.grayText, font: .normal(.text))
        self.titleLayout = TextViewLayout(attr, alignment: .center)
        self.titleLayout.measure(width: initialSize.width - 40)

        super.init(initialSize, stableId: stableId)
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        titleLayout.measure(width: width - 40)
        return success
    }

    public override var height: CGFloat {
        return 20 + 70 + 10 + titleLayout.layoutSize.height + 10
    }

    public override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func viewClass() -> AnyClass {
        return JoinLinkPreviewHeaderRowView.self
    }
}

private final class JoinLinkPreviewHeaderRowView: TableRowView {
    private let avatar = AvatarControl(font: .avatar(30))
    private let titleView = TextView()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.setFrameSize(NSMakeSize(70, 70))
        addSubview(avatar)
        addSubview(titleView)
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return theme.colors.listBackground
    }

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? JoinLinkPreviewHeaderRowItem else { return }
        avatar.setPeer(account: item.context.account, peer: item.peer)
        titleView.update(item.titleLayout)
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        avatar.centerX(y: 20)
        titleView.centerX(y: avatar.frame.maxY + 10)
    }
}

private final class JoinLinkPreviewParticipantsRowItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let participants: [Peer]
    fileprivate let groupUserCount: Int32
    fileprivate let additionCount: Int

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, participants: [Peer], groupUserCount: Int32) {
        self.context = context
        self.participants = Array(participants.prefix(3))
        self.groupUserCount = groupUserCount
        self.additionCount = max(0, Int(groupUserCount) - self.participants.count)
        super.init(initialSize, stableId: stableId)
    }

    public override var height: CGFloat {
        return 50 + 20
    }

    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonMembers
    }

    public override var accessibilityValue: String? {
        var names = participants.map { $0.compactDisplayTitle }
        if additionCount > 0 {
            names.append("+\(additionCount)")
        }
        return names.joined(separator: ", ")
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func viewClass() -> AnyClass {
        return JoinLinkPreviewParticipantsRowView.self
    }
}

private final class JoinLinkPreviewParticipantsRowView: TableRowView {
    private let container = View()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(container)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return theme.colors.listBackground
    }

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        guard let item = item as? JoinLinkPreviewParticipantsRowItem else { return }

        container.removeAllSubviews()

        for participant in item.participants {
            let avatar = AvatarControl(font: .avatar(20))
            avatar.setFrameSize(NSMakeSize(50, 50))
            avatar.setPeer(account: item.context.account, peer: participant)
            container.addSubview(avatar)
        }

        if item.additionCount > 0 {
            let avatar = AvatarControl(font: .avatar(20))
            avatar.setFrameSize(NSMakeSize(50, 50))
            avatar.setState(account: item.context.account, state: .Empty)
            let icon = generateImage(NSMakeSize(46, 46), contextGenerator: { size, ctx in
                ctx.clear(NSMakeRect(0, 0, size.width, size.height))
                var fontSize: CGFloat = 13
                if item.additionCount.prettyNumber.length == 1 {
                    fontSize = 18
                } else if item.additionCount.prettyNumber.length == 2 {
                    fontSize = 15
                }
                let layout = TextViewLayout(.initialize(string: "+\(item.additionCount.prettyNumber)", color: .white, font: .medium(fontSize)), maximumNumberOfLines: 1, truncationType: .middle)
                layout.measure(width: size.width - 4)
                if !layout.lines.isEmpty {
                    let line = layout.lines[0]
                    ctx.textPosition = NSMakePoint(floorToScreenPixels(System.backingScale, (size.width - line.frame.width) / 2.0) - 1, floorToScreenPixels(System.backingScale, (size.height - line.frame.height) / 2.0) + 4)
                    CTLineDraw(line.line, ctx)
                }
            })!
            avatar.setSignal(generateEmptyPhoto(avatar.frame.size, type: .icon(colors: theme.colors.peerColors(5), icon: icon, iconSize: icon.backingSize, cornerRadius: nil), bubble: false) |> map { ($0, false) })
            container.addSubview(avatar)
        }

        needsLayout = true
    }

    public override func layout() {
        super.layout()
        var x: CGFloat = 0
        for avatar in container.subviews {
            avatar.setFrameOrigin(NSMakePoint(x, 0))
            x += avatar.frame.width + 10
        }
        let height = container.subviews.first?.frame.height ?? 50
        container.setFrameSize(NSMakeSize(max(0, x - 10), height))
        container.centerX(y: 0)
    }
}

private let _id_header = InputDataIdentifier("_id_header")
private let _id_participants = InputDataIdentifier("_id_participants")

private func joinLinkPreviewEntries(context: any AccountContextProtocol, peer: TelegramGroup, participants: [Peer]?, groupUserCount: Int32) -> [InputDataEntry] {
    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: InputDataEquatable(peer.id.toInt64()), comparable: nil, item: { initialSize, stableId in
        return JoinLinkPreviewHeaderRowItem(initialSize, stableId: stableId, context: context, peer: peer)
    }))
    index += 1

    if let participants = participants, !participants.isEmpty {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_participants, equatable: InputDataEquatable(participants.map { $0.id.toInt64() }), comparable: nil, item: { initialSize, stableId in
            return JoinLinkPreviewParticipantsRowItem(initialSize, stableId: stableId, context: context, participants: participants, groupUserCount: groupUserCount)
        }))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public func JoinLinkPreviewModalController(_ context: any AccountContextProtocol, hash: String, join: ExternalJoiningChatState, interaction: @escaping (Peer) -> Void) -> InputDataModalController {
    return JoinLinkPreviewModalController(context, hash: hash, join: join, analyticsContext: nil, interaction: interaction)
}

public func JoinLinkPreviewModalController(_ context: any AccountContextProtocol, hash: String, join: ExternalJoiningChatState, analyticsContext: AnalyticsContext?, interaction: @escaping (Peer) -> Void) -> InputDataModalController {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let presentation = origin.beginPresentation()
    defer { presentation.end() }
    let action = InviteJoinAction()
    let request = MetaDisposable()

    var close: (() -> Void)? = nil

    let peer: TelegramGroup
    let participants: [Peer]?
    let groupUserCount: Int32
    switch join {
    case let .invite(state):
        peer = TelegramGroup(id: PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(0)), title: state.title, photo: state.photoRepresentation.flatMap { [$0] } ?? [], participantCount: Int(state.participantsCount), role: .member, membership: .Left, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
        participants = state.participants?.map { $0._asPeer() }
        groupUserCount = state.participantsCount
    default:
        peer = TelegramGroup(id: PeerId(namespace: Namespaces.Peer.CloudGroup, id: PeerId.Id._internalFromInt64Value(0)), title: "", photo: [], participantCount: 0, role: .member, membership: .Left, flags: [], defaultBannedRights: nil, migrationReference: nil, creationDate: 0, version: 0)
        participants = nil
        groupUserCount = 0
    }

    let signal: Signal<InputDataSignalValue, NoError> = .single(InputDataSignalValue(entries: joinLinkPreviewEntries(context: context, peer: peer, participants: participants, groupUserCount: groupUserCount)))

    let controller = InputDataController(dataSignal: signal, title: " ")
    controller.analyticsScreen = .linkInvitePreview
    controller.analyticsContext = origin

    controller.onDeinit = {
        action.close()
        request.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().joinLinkJoin, accept: { [weak controller] in
        guard let window = controller?.window, let attempt = action.begin() else { return }
        let subscription = MetaDisposable()
        request.set(subscription)
        subscription.set(performInviteJoin(context: context, hash: hash, window: window, analyticsContext: origin, requestSentAsSuccess: false, takeResult: { terminal in
            action.take(attempt, terminal: terminal)
        }, close: { close?() }, interaction: interaction))
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, closeHandler: { finish in
        action.close()
        request.dispose()
        finish()
    }, size: NSMakeSize(300, 0))
    modalController.analyticsContext = origin

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })

    close = { [weak modalController] in
        action.close()
        request.dispose()
        modalController?.modal?.close()
    }

    return modalController
}
