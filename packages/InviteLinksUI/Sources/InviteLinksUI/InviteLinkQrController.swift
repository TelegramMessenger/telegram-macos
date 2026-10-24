import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramContext
import TelegramTheme
import ColorPalette
import Localization
import InputDataUI
import GeneralRows
import LocalAnimations
import TelegramMedia
import QRCodeUtils
import FilePanels

private final class InviteLinkQrRowItem: GeneralRowItem {
    let link: String
    fileprivate let textLayout: TextViewLayout
    private let contextMenuItems: () -> [ContextMenuItem]

    init(_ initialSize: NSSize, stableId: AnyHashable, link: String, isChannel: Bool, menuItems: @escaping () -> [ContextMenuItem]) {
        self.link = link
        self.contextMenuItems = menuItems
        let text = isChannel ? strings().inviteLinkQrCodeInfoChannel : strings().inviteLinkQrCodeInfoGroup
        self.textLayout = TextViewLayout(.initialize(string: text, color: theme.colors.grayText, font: .normal(.text)), alignment: .center, alwaysStaticItems: true)
        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        self.textLayout.measure(width: InviteLinkQrRowView.cardSize.width)
        return result
    }

    override var height: CGFloat {
        return InviteLinkQrRowView.cardSize.height + 16 + self.textLayout.layoutSize.height + 10
    }

    override func viewClass() -> AnyClass {
        return InviteLinkQrRowView.self
    }

    override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        return .single(self.contextMenuItems())
    }

    override var accessibilityLabel: String? {
        return self.textLayout.attributedString.string
    }
}

private final class InviteLinkQrRowView: TableRowView {
    static let cardSize = NSMakeSize(240, 240)
    static let codeSize = NSMakeSize(212, 212)

    private let disposable = MetaDisposable()
    private let cardView = View(frame: NSMakeRect(0, 0, cardSize.width, cardSize.height))
    private let imageView = ImageView(frame: NSMakeRect(0, 0, codeSize.width, codeSize.height))
    private let logoView = LottiePlayerView(frame: NSMakeRect(0, 0, 40, 40))
    private let textView = TextView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.cardView.backgroundColor = dayClassicPalette.background
        self.cardView.layer?.cornerRadius = 16
        self.cardView.addSubview(self.imageView)
        self.cardView.addSubview(self.logoView)
        addSubview(self.cardView)
        addSubview(self.textView)
        self.imageView.setAccessibilityLabel(strings().voiceOverCommonQRCode)
        self.textView.userInteractionEnabled = false
        self.textView.isSelectable = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backdorColor: NSColor {
        return theme.colors.listBackground
    }

    override func layout() {
        super.layout()
        self.cardView.centerX(y: 0)
        self.imageView.center()
        self.logoView.center()
        self.textView.centerX(y: self.cardView.frame.maxY + 16)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        self.updateLogo()
    }

    private func updateLogo() {
        if window != nil, let data = LocalAnimatedSticker.login_airplane.data {
            self.logoView.set(LottieAnimation(compressed: data, key: .init(key: .bundle("login_airplane"), size: self.logoView.frame.size, backingScale: Int(System.backingScale), fitzModifier: nil), playPolicy: .loop))
        } else {
            self.logoView.set(nil)
        }
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)

        guard let item = item as? InviteLinkQrRowItem else {
            return
        }

        self.textView.update(item.textLayout)

        let size = InviteLinkQrRowView.codeSize
        self.disposable.set((qrCode(string: item.link, color: dayClassicPalette.text, backgroundColor: dayClassicPalette.background, icon: .custom(theme.icons.login_qr_empty_cap))
        |> map { _, generate -> CGImage? in
            return generate(TransformImageArguments(corners: ImageCorners(), imageSize: size, boundingSize: size, intrinsicInsets: NSEdgeInsets(), scale: System.backingScale))?.generateImage()
        }
        |> deliverOnMainQueue).start(next: { [weak self] image in
            self?.imageView.image = image
        }))

        needsLayout = true
    }

    deinit {
        self.disposable.dispose()
    }
}

private func inviteLinkQrImage(_ link: String) -> Signal<CGImage?, NoError> {
    let size = NSMakeSize(768, 768)
    return qrCode(string: link, color: dayClassicPalette.text, backgroundColor: dayClassicPalette.background, icon: .custom(theme.icons.login_qr_cap))
    |> map { _, generate -> CGImage? in
        return generate(TransformImageArguments(corners: ImageCorners(), imageSize: size, boundingSize: size, intrinsicInsets: NSEdgeInsets(), scale: 1.0))?.generateImage()
    }
    |> deliverOnMainQueue
}

private func inviteLinkQrWriteImage(_ image: CGImage) -> String? {
    let path = NSTemporaryDirectory() + "invite-qr-\(UInt32.random(in: 0 ... UInt32.max)).png"
    guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]), (try? data.write(to: URL(fileURLWithPath: path))) != nil else {
        return nil
    }
    return path
}

func inviteLinkQrMenuIcon() -> NSImage {
    let image = TelegramThemeHooks.shared.image(.iconWalletQR).precomposed(theme.colors.text)
    return NSImage(cgImage: image, size: image.backingSize)
}

private final class InviteLinkQrActions {
    private let context: any AccountContextProtocol
    private let link: String
    private let disposable = MetaDisposable()
    var close: (()->Void)?

    init(context: any AccountContextProtocol, link: String) {
        self.context = context
        self.link = link
    }

    deinit {
        self.disposable.dispose()
    }

    private func withImage(_ f: @escaping (CGImage) -> Void) {
        self.disposable.set(inviteLinkQrImage(self.link).start(next: { image in
            if let image {
                f(image)
            }
        }))
    }

    func share() {
        let context = self.context
        let link = self.link
        self.withImage { [weak self] image in
            guard let path = inviteLinkQrWriteImage(image) else {
                return
            }
            self?.close?()
            InviteLinksHooks.shared.shareQrImage(context, path, link, context.window)
        }
    }

    func copyLink() {
        copyToClipboard(self.link)
        showModalText(for: self.context.window, text: strings().shareLinkCopied)
    }

    func saveImage() {
        let window = self.context.window
        self.withImage { image in
            guard let path = inviteLinkQrWriteImage(image) else {
                return
            }
            savePanel(file: path, ext: "png", for: window, defaultName: "qr-code.png")
        }
    }

    func copyImage() {
        let window = self.context.window
        self.withImage { image in
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([NSImage(cgImage: image, size: NSMakeSize(CGFloat(image.width), CGFloat(image.height)))])
            showModalText(for: window, text: strings().contextAlertCopied)
        }
    }

    func menuItems() -> [ContextMenuItem] {
        return [
            ContextMenuItem(strings().inviteLinkQrCodeMenuShare, handler: { [weak self] in
                self?.share()
            }, itemImage: MenuAnimation.menu_share.value),
            ContextMenuItem(strings().inviteLinkQrCodeMenuCopyLink, handler: { [weak self] in
                self?.copyLink()
            }, itemImage: MenuAnimation.menu_copy_link.value),
            ContextMenuItem(strings().inviteLinkQrCodeMenuSaveImage, handler: { [weak self] in
                self?.saveImage()
            }, itemImage: MenuAnimation.menu_save_as.value),
            ContextMenuItem(strings().inviteLinkQrCodeMenuCopyImage, handler: { [weak self] in
                self?.copyImage()
            }, itemImage: MenuAnimation.menu_copy_media.value)
        ]
    }
}

private let _id_qr = InputDataIdentifier("_id_qr")

public func InviteLinkQrController(context: any AccountContextProtocol, link: String, isChannel: Bool) -> InputDataModalController {

    let actions = InviteLinkQrActions(context: context, link: link)

    let signal: Signal<InputDataSignalValue, NoError> = .single(InputDataSignalValue(entries: [
        .sectionId(0, type: .customModern(10)),
        .custom(sectionId: 1, index: 0, value: .none, identifier: _id_qr, equatable: InputDataEquatable(link), comparable: nil, item: { initialSize, stableId in
            return InviteLinkQrRowItem(initialSize, stableId: stableId, link: link, isChannel: isChannel, menuItems: { [weak actions] in
                return actions?.menuItems() ?? []
            })
        }),
        .sectionId(1, type: .customModern(10))
    ]))

    let controller = InputDataController(dataSignal: signal, title: strings().inviteLinkQrCodeTitle)

    controller.onDeinit = {
        actions.close = nil
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().inviteLinkQrCodeShare, accept: { [weak actions] in
        actions?.share()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions, size: NSMakeSize(340, 300))

    controller.leftModalHeader = ModalHeaderData(image: theme.icons.modalClose, handler: { [weak modalController] in
        modalController?.modal?.close()
    })

    controller.rightModalHeader = ModalHeaderData(image: theme.icons.chatActionsActive, contextMenu: { [weak actions] in
        return actions?.menuItems() ?? []
    })

    actions.close = { [weak modalController] in
        modalController?.modal?.close()
    }

    return modalController
}
