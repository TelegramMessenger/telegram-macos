import Cocoa
import TGUIKit
import TelegramTheme
import Localization

final class WalletStickerTrashView: View {
    static let height: CGFloat = 48
    static let reach: CGFloat = 90
    private static let font: NSFont = .semibold(15)
    private static let iconInset: CGFloat = 16
    private static let textGap: CGFloat = 6

    private let glass = LiquidGlassView(frame: NSZeroRect, cornerRadius: WalletStickerTrashView.height / 2, hasShadow: true, hasBorder: true)
    private let iconView = ImageView()
    private let textView = TextView()
    private(set) var isHot = false
    private(set) var anchor: NSPoint = .zero

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
        layer?.masksToBounds = false
        layer?.opacity = 0
        iconView.isEventLess = true
        iconView.isAccessibilityDecorative = true
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.isEventLess = true
        textView.layer?.opacity = 0
        addSubview(glass)
        addSubview(iconView)
        addSubview(textView)
        applyContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        glass.updateLocalizationAndTheme(theme: theme)
        applyContent()
        layoutContent(transition: .immediate)
    }

    func place(at center: NSPoint) {
        anchor = center
        layoutContent(transition: .immediate)
    }

    func setShown(_ shown: Bool) {
        if !shown {
            setHot(false)
        }
        change(opacity: shown ? 1 : 0, animated: true, duration: 0.2)
    }

    func setHot(_ hot: Bool) {
        guard hot != isHot else {
            return
        }
        isHot = hot
        glass.setCustomTint(hot ? theme.colors.redUI : nil, animated: true)
        applyContent()
        textView.change(opacity: hot ? 1 : 0, animated: true, duration: 0.2)
        layoutContent(transition: .animated(duration: 0.2, curve: .easeOut))
    }

    private func applyContent() {
        iconView.image = NSImage(cgImage: theme.icons.chatSwiping_delete, size: NSMakeSize(24, 24)).precomposed(isHot ? .white : theme.colors.text)
        iconView.sizeToFit()
        let layout = TextViewLayout(.initialize(string: strings().modalRemove, color: .white, font: WalletStickerTrashView.font), maximumNumberOfLines: 1)
        layout.measure(width: .greatestFiniteMagnitude)
        textView.update(layout)
    }

    private func layoutContent(transition: ContainedViewLayoutTransition) {
        let height = WalletStickerTrashView.height
        let iconSize = iconView.frame.size
        let width = isHot ? WalletStickerTrashView.iconInset + iconSize.width + WalletStickerTrashView.textGap + textView.frame.width + WalletStickerTrashView.iconInset + 4 : height
        transition.updateFrame(view: self, frame: NSMakeRect(anchor.x - width / 2, anchor.y - height / 2, width, height))
        transition.updateFrame(view: glass, frame: NSMakeRect(0, 0, width, height))
        glass.updateLayout(size: NSMakeSize(width, height), transition: transition)
        let iconX = isHot ? WalletStickerTrashView.iconInset : (width - iconSize.width) / 2
        transition.updateFrame(view: iconView, frame: NSMakeRect(floorToScreenPixels(backingScaleFactor, iconX), floorToScreenPixels(backingScaleFactor, (height - iconSize.height) / 2), iconSize.width, iconSize.height))
        transition.updateFrame(view: textView, frame: NSMakeRect(floorToScreenPixels(backingScaleFactor, iconX + iconSize.width + WalletStickerTrashView.textGap), floorToScreenPixels(backingScaleFactor, (height - textView.frame.height) / 2), textView.frame.width, textView.frame.height))
    }
}
