import Cocoa
import TGUIKit
import GeneralRows
import InAppSettings
import TelegramTheme
import ColorPalette
import Localization

final class IncomingCallStyleRowItem: GeneralRowItem {
    let style: IncomingCallStyle
    let presentation: TelegramPresentationTheme
    let select: (IncomingCallStyle) -> Void

    init(_ initialSize: NSSize, stableId: AnyHashable, style: IncomingCallStyle, presentation: TelegramPresentationTheme, select: @escaping (IncomingCallStyle) -> Void) {
        self.style = style
        self.presentation = presentation
        self.select = select
        super.init(initialSize, stableId: stableId, viewType: .singleItem)
    }

    override var height: CGFloat {
        return max(0, (blockWidth - 48) / 2) * 2 / 3 + 60
    }

    override func viewClass() -> AnyClass {
        return IncomingCallStyleRowView.self
    }
}

private final class IncomingCallStyleRowView: GeneralContainableRowView {
    private let classic = IncomingCallStyleButton(style: .classic)
    private let compact = IncomingCallStyleButton(style: .compact)

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        containerView.addSubview(classic)
        containerView.addSubview(compact)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        guard let item = item as? IncomingCallStyleRowItem else { return }
        for button in [classic, compact] {
            button.presentation = item.presentation
            button.title = button.callStyle == .classic ? strings().callSettingsIncomingStyleClassic : strings().callSettingsIncomingStyleCompact
            button.setAccessibilityLabel(button.title)
            button.isSelected = button.callStyle == item.style
            button.select = item.select
            button.needsDisplay = true
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = max(0, (containerView.bounds.width - 48) / 2)
        let height = width * 2 / 3 + 32
        classic.frame = NSMakeRect(16, 14, width, height)
        compact.frame = NSMakeRect(32 + width, 14, width, height)
    }
}

private final class IncomingCallStyleButton: Control {
    let callStyle: IncomingCallStyle
    var presentation: TelegramPresentationTheme = theme
    var title: String
    var select: ((IncomingCallStyle) -> Void)?

    override var isFlipped: Bool { return true }

    init(style: IncomingCallStyle) {
        self.callStyle = style
        self.title = style == .classic ? strings().callSettingsIncomingStyleClassic : strings().callSettingsIncomingStyleCompact
        super.init(frame: .zero)
        set(handler: { [weak self] _ in
            guard let self else { return }
            self.select?(self.callStyle)
        }, for: .Click)
        setAccessibilityLabel(title)
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ layer: CALayer, in context: CGContext) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        defer { NSGraphicsContext.restoreGraphicsState() }
        let colors = presentation.colors
        let preview = NSMakeRect(1, 1, bounds.width - 2, bounds.width * 2 / 3 - 2)
        let outline = NSBezierPath(roundedRect: preview, xRadius: 12, yRadius: 12)
        colors.listBackground.setFill()
        outline.fill()
        NSGraphicsContext.saveGraphicsState()
        outline.addClip()
        var transform = AffineTransform(scaleByX: preview.width / 240, byY: preview.height / 160)
        transform.translate(x: preview.minX * 240 / preview.width, y: preview.minY * 160 / preview.height)
        (transform as NSAffineTransform).concat()
        drawDesktop()
        NSGraphicsContext.restoreGraphicsState()
        (isSelected ? colors.accent : colors.border).setStroke()
        outline.lineWidth = isSelected ? 2 : 1
        outline.stroke()
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13, weight: isSelected ? .medium : .regular),
            .foregroundColor: isSelected ? colors.accent : colors.text,
            .paragraphStyle: paragraph
        ]
        (title as NSString).draw(in: NSMakeRect(0, preview.maxY + 10, bounds.width, 20), withAttributes: attributes)
    }

    private func fill(_ rect: NSRect, color: NSColor, radius: CGFloat = 3) {
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    }

    private func avatar(_ rect: NSRect, color: NSColor) {
        fill(rect, color: color.withAlphaComponent(0.16), radius: rect.width / 2)
        color.setFill()
        NSBezierPath(ovalIn: NSMakeRect(rect.midX - rect.width * 0.13, rect.minY + rect.height * 0.22, rect.width * 0.26, rect.height * 0.26)).fill()
        NSBezierPath(roundedRect: NSMakeRect(rect.minX + rect.width * 0.24, rect.minY + rect.height * 0.54, rect.width * 0.52, rect.height * 0.28), xRadius: rect.width * 0.15, yRadius: rect.width * 0.15).fill()
    }

    private func symbol(_ name: String, in rect: NSRect, color: NSColor) {
        guard #available(macOS 11.0, *) else { return }
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.copy() as? NSImage else { return }
        image.isTemplate = false
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        image.unlockFocus()
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func drawDesktop() {
        let colors = presentation.colors
        if callStyle == .classic {
            let translation = AffineTransform(translationByX: 0, byY: -4.5)
            (translation as NSAffineTransform).concat()
            let window = NSMakeRect(38, 23, 164, 123)
            let gradient = NSGradient(starting: colors.accent.withAlphaComponent(0.45), ending: colors.accent.withAlphaComponent(0.8))
            gradient?.draw(in: NSBezierPath(roundedRect: window, xRadius: 8, yRadius: 8), angle: 75)
            avatar(NSMakeRect(102, 45, 36, 36), color: colors.underSelectedColor)
            fill(NSMakeRect(91, 89, 58, 4), color: colors.underSelectedColor, radius: 2)
            fill(NSMakeRect(102, 98, 36, 2), color: colors.underSelectedColor.withAlphaComponent(0.5), radius: 1)
            let names = ["video.fill", "rectangle.on.rectangle", "mic.slash.fill", "phone.down.fill"]
            for (index, name) in names.enumerated() {
                let x = CGFloat(75 + index * 24)
                fill(NSMakeRect(x, 114, 18, 18), color: index == 3 ? colors.redUI : colors.underSelectedColor.withAlphaComponent(0.2), radius: 9)
                symbol(name, in: NSMakeRect(x + 5, 119, 8, 8), color: colors.underSelectedColor)
            }
        } else {
            fill(NSMakeRect(0, 0, 240, 12), color: colors.text.withAlphaComponent(0.04), radius: 0)
            symbol("wifi", in: NSMakeRect(181, 3, 9, 6), color: colors.text)
            symbol("battery.100", in: NSMakeRect(197, 3, 13, 6), color: colors.text)
            ("9:41" as NSString).draw(in: NSMakeRect(217, 2, 20, 9), withAttributes: [.font: NSFont.systemFont(ofSize: 7, weight: .medium), .foregroundColor: colors.text])
            fill(NSMakeRect(61, 20, 167, 46), color: colors.background, radius: 9)
            avatar(NSMakeRect(70, 30, 26, 26), color: colors.grayText)
            fill(NSMakeRect(104, 34, 58, 4), color: colors.text.withAlphaComponent(0.8), radius: 2)
            fill(NSMakeRect(104, 44, 39, 3), color: colors.grayText.withAlphaComponent(0.45), radius: 1.5)
            fill(NSMakeRect(187, 28, 32, 12), color: colors.greenUI, radius: 4)
            fill(NSMakeRect(187, 45, 32, 12), color: colors.redUI, radius: 4)
            symbol("phone.fill", in: NSMakeRect(200, 30, 7, 8), color: colors.underSelectedColor)
            symbol("phone.down.fill", in: NSMakeRect(199, 48, 9, 6), color: colors.underSelectedColor)
        }
    }
}
