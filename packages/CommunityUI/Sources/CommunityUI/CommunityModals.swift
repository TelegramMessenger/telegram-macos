import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import DateUtils
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import ShortPeerRow
import AvatarUI
import TelegramMediaUtils
import AlertsUI
import LocalAnimations
import MessageTextUtils
import AppAnalytics

// MARK: - Centered header (avatar + title + subtitle)

public final class CommunityModalHeaderItem: GeneralRowItem {
    fileprivate let context: (any AccountContextProtocol)
    fileprivate let peer: Peer?
    fileprivate let communityStyle: Bool
    fileprivate let topInset: CGFloat
    fileprivate let titleLayout: TextViewLayout
    fileprivate let subtitleLayout: TextViewLayout

    public init(_ initialSize: NSSize, stableId: AnyHashable, context: (any AccountContextProtocol), peer: Peer?, title: String, subtitle: String, communityStyle: Bool = false) {
        self.context = context
        self.peer = peer
        self.communityStyle = communityStyle
        self.topInset = communityStyle ? 8 : 20
        self.titleLayout = TextViewLayout(.initialize(string: title, color: theme.colors.text, font: .medium(.header)), alignment: .center)
        self.subtitleLayout = TextViewLayout(.initialize(string: subtitle, color: theme.colors.grayText, font: .normal(.text)), alignment: .center)
        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }

    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        let textWidth = width - 60
        titleLayout.measure(width: textWidth)
        subtitleLayout.measure(width: textWidth)
        return result
    }

    public override var height: CGFloat {
        return topInset + 80 + 14 + titleLayout.layoutSize.height + 6 + subtitleLayout.layoutSize.height + 8
    }

    public override func viewClass() -> AnyClass { return CommunityModalHeaderView.self }

    public override var accessibilityLabel: String? {
        return titleLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return subtitleLayout.attributedString.string
    }
}

public final class CommunityModalHeaderView: GeneralRowView {
    private let avatar = AvatarControl(font: .avatar(24))
    private let titleView = TextView()
    private let subtitleView = TextView()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        avatar.setFrameSize(NSMakeSize(80, 80))
        avatar.userInteractionEnabled = false
        titleView.userInteractionEnabled = false; titleView.isSelectable = false
        subtitleView.userInteractionEnabled = false; subtitleView.isSelectable = false
        addSubview(avatar)
        addSubview(titleView)
        addSubview(subtitleView)
    }
    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    public override var backdorColor: NSColor { return .clear }

    public override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? CommunityModalHeaderItem else { return }
        avatar.setPeer(account: item.context.account, peer: item.peer, forceCommunity: item.communityStyle)
        titleView.update(item.titleLayout)
        subtitleView.update(item.subtitleLayout)
        needsLayout = true
    }

    public override func layout() {
        super.layout()
        let topInset = (self.item as? CommunityModalHeaderItem)?.topInset ?? 20
        avatar.centerX(y: topInset)
        titleView.centerX(y: avatar.frame.maxY + 14)
        subtitleView.centerX(y: titleView.frame.maxY + 6)
    }
}

// MARK: - Private (invite-only) linked-group modal

/// Shown when a linked group suggested for a community is invite-only — its content can't be previewed, so
/// the only action is to message whoever suggested it. Mirrors iOS `CommunityPrivateChatScreen`.
public func CommunityPrivateChatController(context: (any AccountContextProtocol), chatPeer: Peer?, requestedBy: Peer?, memberCount: Int32?, messageOwner: @escaping () -> Void) -> InputDataModalController {
    var close: (() -> Void)? = nil

    let memberStr: String
    if let mc = memberCount, mc > 0 {
        memberStr = strings().communityMembersOther(Int(mc))
    } else {
        memberStr = ""
    }

    var entries: [InputDataEntry] = []
    var sectionId: Int32 = 0
    var index: Int32 = 0
    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("header"), equatable: nil, comparable: nil, item: { initialSize, stableId in
        return CommunityModalHeaderItem(initialSize, stableId: stableId, context: context, peer: chatPeer, title: chatPeer?.displayTitle ?? strings().communityGroup, subtitle: memberStr)
    }))
    index += 1

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().communityInviteOnlyInfo), data: .init(color: theme.colors.grayText, viewType: .plain(.single), centerViewAlignment: true, alignment: .center)))
    index += 1

    entries.append(.sectionId(sectionId, type: .normal)); sectionId += 1

    let controller = InputDataController(dataSignal: .single(InputDataSignalValue(entries: entries)), title: "", hasDone: false)
    controller.analyticsScreen = .communityPrivateChat

    let modalInteractions: ModalInteractions
    if requestedBy != nil {
        modalInteractions = ModalInteractions(acceptTitle: strings().communityMessageGroupOwner, accept: {
            close?()
            messageOwner()
        }, cancelTitle: strings().modalCancel, cancel: {
            close?()
        })
    } else {
        modalInteractions = ModalInteractions(acceptTitle: strings().modalCancel, accept: {
            close?()
        }, singleButton: true)
    }
    modalInteractions.glassButtons = true

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(340, 400))
    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.close()
    })
    close = { [weak modalController] in modalController?.close() }
    return modalController
}

// MARK: - "You are a community admin" modal
