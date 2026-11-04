import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramTheme
import GeneralRows
import Localization

public func walletMoveActionIcon(_ name: String, diameter: CGFloat = 40) -> CGImage? {
    guard let glyph = NSImage(named: name)?.precomposed(.white) else { return nil }
    return generateImage(NSMakeSize(diameter, diameter), rotatedContext: { size, context in
        context.clear(size.bounds)
        context.addEllipse(in: size.bounds)
        context.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(0x72d5fd).cgColor, NSColor(0x2a9ef1).cgColor] as CFArray, locations: [0, 1]) {
            context.drawLinearGradient(gradient, start: .zero, end: NSMakePoint(0, size.height), options: [])
        }
        context.draw(glyph, in: size.bounds.insetBy(dx: diameter / 8, dy: diameter / 8))
    })
}

final class WalletGiftDepositConfirmationRowItem: GeneralRowItem {
    fileprivate let environment: WalletUIEnvironment
    fileprivate let peer: Peer?
    fileprivate let textLayout: TextViewLayout
    fileprivate let nameLayout: TextViewLayout
    fileprivate let phoneLayout: TextViewLayout?
    fileprivate let locationLayout: TextViewLayout
    fileprivate let pathLayouts: [TextViewLayout]
    fileprivate let chevronLayout: TextViewLayout
    fileprivate var feeLayout: TextViewLayout?
    private let feeDisposable = MetaDisposable()
    fileprivate var peerY: CGFloat { textLayout.layoutSize.height + 14 }
    fileprivate var locationY: CGFloat { peerY + 64 + 16 }
    fileprivate var pathY: CGFloat { locationY + locationLayout.layoutSize.height + 8 }
    fileprivate var feeY: CGFloat { pathY + 16 + 12 }

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, environment: WalletUIEnvironment, networkFee: Signal<Int64?, NoError>, updateSize: @escaping () -> Void) {
        self.environment = environment
        self.peer = context.myPeer
        let text = strings().giftMoveToGiftsText
        textLayout = TextViewLayout(.initialize(string: text, color: theme.colors.text, font: .normal(.text)), alignment: .center)
        nameLayout = TextViewLayout(.initialize(string: context.myPeer.map { environment.peerTitle($0, compact: false) } ?? strings().accountSettingsMyProfile, color: theme.colors.text, font: .medium(.title)), maximumNumberOfLines: 1)
        if let phone = (context.myPeer as? TelegramUser)?.phone, !phone.isEmpty {
            phoneLayout = TextViewLayout(.initialize(string: "+" + phone, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)
        } else {
            phoneLayout = nil
        }
        let location = strings().giftMoveToWalletLocation
        locationLayout = TextViewLayout(.initialize(string: location, color: theme.colors.text, font: .normal(.text)), alignment: .center)
        pathLayouts = [strings().accountSettingsMyProfile, strings().peerMediaGifts].map {
            TextViewLayout(.initialize(string: $0, color: theme.colors.text.withAlphaComponent(0.5), font: .normal(12)), maximumNumberOfLines: 1)
        }
        chevronLayout = TextViewLayout(.initialize(string: "›", color: theme.colors.text.withAlphaComponent(0.5), font: .normal(14)), maximumNumberOfLines: 1)
        super.init(initialSize, stableId: stableId, viewType: .legacy)
        _ = makeSize(initialSize.width, oldWidth: 0)
        feeDisposable.set((networkFee |> take(1) |> deliverOnMainQueue).start(next: { [weak self] fee in
            guard let self, let fee else { return }
            let layout = TextViewLayout(.initialize(string: strings().walletSendControllerNetworkFee + " " + formatGramsText(fee, maxDecimalPositions: 5), color: theme.colors.grayText, font: .normal(12)), alignment: .center)
            layout.measure(width: self.width - 40)
            self.feeLayout = layout
            self.noteHeightOfRow(animated: true)
            self.redraw(animated: true)
            updateSize()
        }))
    }

    deinit {
        feeDisposable.dispose()
    }

    override var height: CGFloat { feeLayout == nil ? pathY + 24 : feeY + 16 }

    override var accessibilityLabel: String? {
        return textLayout.attributedString.string
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        textLayout.measure(width: width - 40)
        nameLayout.measure(width: width - 112)
        phoneLayout?.measure(width: width - 112)
        locationLayout.measure(width: width - 40)
        for layout in pathLayouts { layout.measure(width: width / 2 - 50) }
        chevronLayout.measure(width: 20)
        feeLayout?.measure(width: width - 40)
        return true
    }

    override func viewClass() -> AnyClass { WalletGiftDepositConfirmationRowView.self }
}

private final class WalletGiftDepositConfirmationRowView: TableRowView {
    private let textView = TextView()
    private let peerView = View()
    private var avatarView: WalletUIAvatarView?
    private let nameView = TextView()
    private let phoneView = TextView()
    private let locationView = TextView()
    private let pathViews = [TextView(), TextView()]
    private let pathIcons = [ImageView(), ImageView()]
    private let chevronView = TextView()
    private let feeView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        for view in [textView, nameView, phoneView, locationView, chevronView, feeView] + pathViews {
            view.userInteractionEnabled = false
            view.isSelectable = false
        }
        peerView.layer?.cornerRadius = 14
        peerView.addSubview(nameView)
        peerView.addSubview(phoneView)
        addSubview(textView)
        addSubview(peerView)
        addSubview(locationView)
        addSubview(chevronView)
        addSubview(feeView)
        for view in pathViews { addSubview(view) }
        for view in pathIcons {
            view.isEventLess = true
            addSubview(view)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var backdorColor: NSColor { .clear }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? WalletGiftDepositConfirmationRowItem else { return }
        textView.update(item.textLayout)
        nameView.update(item.nameLayout)
        phoneView.update(item.phoneLayout)
        phoneView.isHidden = item.phoneLayout == nil
        locationView.update(item.locationLayout)
        chevronView.update(item.chevronLayout)
        if animated, feeView.textLayout == nil, item.feeLayout != nil {
            feeView.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
        }
        feeView.update(item.feeLayout)
        for (view, layout) in zip(pathViews, item.pathLayouts) { view.update(layout) }
        for (view, name) in zip(pathIcons, ["Wallet_PathUser", "Wallet_PathGift"]) {
            view.image = NSImage(named: name)?.precomposed(theme.colors.text.withAlphaComponent(0.5))
            view.setFrameSize(NSMakeSize(14, 14))
        }
        if avatarView == nil {
            let avatar = item.environment.makeAvatar(font: .avatar(16))
            avatar.setFrameSize(NSMakeSize(40, 40))
            peerView.addSubview(avatar)
            avatarView = avatar
        }
        avatarView?.update(peer: item.peer)
        peerView.backgroundColor = theme.colors.text.withAlphaComponent(0.06)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard let item = item as? WalletGiftDepositConfirmationRowItem else { return }
        textView.centerX(y: 0)
        peerView.frame = NSMakeRect(20, item.peerY, frame.width - 40, 64)
        avatarView?.setFrameOrigin(NSMakePoint(12, 12))
        let textHeight = nameView.frame.height + (item.phoneLayout == nil ? 0 : phoneView.frame.height + 2)
        nameView.setFrameOrigin(NSMakePoint(64, (64 - textHeight) / 2))
        phoneView.setFrameOrigin(NSMakePoint(64, nameView.frame.maxY + 2))
        locationView.centerX(y: item.locationY)
        feeView.centerX(y: item.feeY)
        let textWidth: CGFloat = pathViews.reduce(0) { $0 + $1.frame.width }
        let iconWidth: CGFloat = 14 * 2
        let spacing: CGFloat = 4 * 4
        let pathWidth: CGFloat = textWidth + iconWidth + spacing + chevronView.frame.width
        var x = floor((frame.width - pathWidth) / 2)
        for index in 0 ..< 2 {
            pathIcons[index].setFrameOrigin(NSMakePoint(x, item.pathY + 1))
            x += 18
            pathViews[index].setFrameOrigin(NSMakePoint(x, item.pathY))
            x += pathViews[index].frame.width + 4
            if index == 0 {
                chevronView.setFrameOrigin(NSMakePoint(x, item.pathY - 1))
                x += chevronView.frame.width + 4
            }
        }
    }
}
