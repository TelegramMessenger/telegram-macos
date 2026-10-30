import Cocoa
import TGUIKit
import SwiftSignalKit
import ColorPalette
import Localization

final class EditVideoSliderView: View {
    private static let knobSize: CGFloat = 17
    private static let trackHeight: CGFloat = 2

    var minimum: CGFloat = -100
    var maximum: CGFloat = 100
    var value: CGFloat = 0 {
        didSet {
            needsDisplay = true
        }
    }
    var onChange: ((CGFloat, Bool) -> Void)?
    var onDragging: ((Bool) -> Void)?
    var isDragging = false

    private var isBipolar: Bool {
        return minimum < 0
    }

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var trackRect: NSRect {
        let inset = EditVideoSliderView.knobSize / 2.0
        return NSMakeRect(inset, floor((frame.height - EditVideoSliderView.trackHeight) / 2.0), max(1, frame.width - inset * 2), EditVideoSliderView.trackHeight)
    }

    private func position(for value: CGFloat) -> CGFloat {
        let track = trackRect
        return track.minX + track.width * (value - minimum) / max(1, maximum - minimum)
    }

    private func value(for x: CGFloat) -> CGFloat {
        let track = trackRect
        let raw = minimum + (x - track.minX) / track.width * (maximum - minimum)
        let clamped = min(maximum, max(minimum, raw))
        if isBipolar, abs(clamped) < (maximum - minimum) * 0.02 {
            return 0
        }
        return clamped.rounded()
    }

    override func draw(_ layer: CALayer, in ctx: CGContext) {
        super.draw(layer, in: ctx)
        let track = trackRect
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.25).cgColor)
        ctx.fill(track)
        let start = isBipolar ? position(for: 0) : track.minX
        let current = position(for: value)
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.fill(NSMakeRect(min(start, current), track.minY, abs(current - start), track.height))
        if isBipolar {
            ctx.fill(NSMakeRect(start - 2, floor((frame.height - 12) / 2.0), 4, 12))
        }
        let knob = EditVideoSliderView.knobSize
        let knobRect = NSMakeRect(current - knob / 2.0, floor((frame.height - knob) / 2.0), knob, knob)
        ctx.setShadow(offset: CGSize(width: 0, height: 0.5), blur: 1.5, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fillEllipse(in: knobRect)
    }

    private func update(with event: NSEvent, final: Bool) {
        let point = convert(event.locationInWindow, from: nil)
        let updated = value(for: point.x)
        if updated != value || final {
            value = updated
            onChange?(updated, final)
        }
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            value = isBipolar ? 0 : minimum
            onChange?(value, true)
            return
        }
        onDragging?(true)
        update(with: event, final: false)
    }

    override func mouseDragged(with event: NSEvent) {
        update(with: event, final: false)
    }

    override func mouseUp(with event: NSEvent) {
        guard event.clickCount < 2 else {
            return
        }
        update(with: event, final: true)
        onDragging?(false)
    }
}

final class EditVideoToolRowView: View {
    static let height: CGFloat = 46
    private let titleView = TextView()
    private let valueView = TextView()
    let slider = EditVideoSliderView(frame: .zero)
    private var title: String = ""
    private var value: Int = 0
    private var maximum: Int = 100

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        valueView.userInteractionEnabled = false
        valueView.isSelectable = false
        addSubview(titleView)
        addSubview(valueView)
        addSubview(slider)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(title: String, value: Int, minimum: Int, maximum: Int) {
        self.title = title
        self.value = value
        self.maximum = maximum
        slider.minimum = CGFloat(minimum)
        slider.maximum = CGFloat(maximum)
        slider.value = CGFloat(value)
        updateTexts()
    }

    func setValue(_ value: Int) {
        self.value = value
        updateTexts()
    }

    private func updateTexts() {
        let titleLayout = TextViewLayout(.initialize(string: title, color: value == 0 ? NSColor.white.withAlphaComponent(0.5) : .white, font: .bold(13)), maximumNumberOfLines: 1)
        titleLayout.measure(width: .greatestFiniteMagnitude)
        titleView.update(titleLayout)
        let text: String
        if value == 0 {
            text = ""
        } else {
            let normalized = Double(value) / Double(max(1, abs(maximum)))
            text = String(format: normalized > 0 ? "+%0.2f" : "%0.2f", normalized)
        }
        let valueLayout = TextViewLayout(.initialize(string: text, color: nightAccentPalette.accent, font: .bold(13)), maximumNumberOfLines: 1)
        valueLayout.measure(width: .greatestFiniteMagnitude)
        valueView.update(valueLayout)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        titleView.setFrameOrigin(NSMakePoint(21, 4))
        valueView.setFrameOrigin(NSMakePoint(frame.width - 21 - valueView.frame.width, 4))
        slider.frame = NSMakeRect(14, 19, frame.width - 28, 26)
    }
}

private final class EditVideoTintSectionView: View {
    private let titleView = TextView()
    private var swatches: [Control] = []
    let slider = EditVideoSliderView(frame: .zero)
    private let colors: [UInt32?]
    private var selected: UInt32?
    var onSelect: ((UInt32?) -> Void)?

    init(title: String, colors: [UInt32]) {
        self.colors = [nil] + colors.map { Optional($0) }
        super.init(frame: .zero)
        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        let layout = TextViewLayout(.initialize(string: title, color: .white, font: .bold(13)), maximumNumberOfLines: 1)
        layout.measure(width: .greatestFiniteMagnitude)
        titleView.update(layout)
        addSubview(titleView)
        for color in self.colors {
            let swatch = Control(frame: NSMakeRect(0, 0, 26, 26))
            swatch.layer?.cornerRadius = 13
            swatch.layer?.borderWidth = 2
            if let color = color {
                swatch.backgroundColor = EditVideoToolsView.color(color)
            } else {
                swatch.backgroundColor = .clear
            }
            swatch.scaleOnClick = true
            swatch.set(handler: { [weak self] _ in
                self?.onSelect?(color)
            }, for: .Click)
            swatches.append(swatch)
            addSubview(swatch)
        }
        slider.minimum = 0
        slider.maximum = 100
        addSubview(slider)
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(selected: UInt32?, intensity: Int) {
        self.selected = selected
        for (swatch, color) in zip(swatches, colors) {
            let isSelected = color == selected
            swatch.layer?.borderColor = (isSelected ? NSColor.white : NSColor.white.withAlphaComponent(color == nil ? 0.6 : 0)).cgColor
        }
        slider.value = CGFloat(intensity)
        slider.alphaValue = selected == nil ? 0.3 : 1
        slider.isEventLess = selected == nil
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let edge: CGFloat = 21
        let size: CGFloat = 26
        let spacing = (frame.width - edge * 2 - size * CGFloat(swatches.count)) / CGFloat(max(1, swatches.count - 1))
        titleView.setFrameOrigin(NSMakePoint(edge, 4))
        for (i, swatch) in swatches.enumerated() {
            swatch.setFrameOrigin(NSMakePoint(floor(edge + (size + spacing) * CGFloat(i)), 26))
        }
        slider.frame = NSMakeRect(14, 60, frame.width - 28, 26)
    }
}

final class EditVideoToolsView: View {
    static func color(_ hex: UInt32) -> NSColor {
        return NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255.0, green: CGFloat((hex >> 8) & 0xff) / 255.0, blue: CGFloat(hex & 0xff) / 255.0, alpha: 1)
    }

    let preview = ImageView()
    let previewControl = Control()
    private let panel = View()
    private let scrollView = NSScrollView()
    private let rowsView = View()
    private(set) var rows: [EditVideoTool: EditVideoToolRowView] = [:]
    private let tintView = View()
    fileprivate let shadowsSection = EditVideoTintSectionView(title: strings().editVideoToolsControllerShadows, colors: EditVideoTint.shadowsColors)
    fileprivate let highlightsSection = EditVideoTintSectionView(title: strings().editVideoToolsControllerHighlights, colors: EditVideoTint.highlightsColors)
    let cancel = makeEditVideoCancelButton()
    let done = makeEditVideoDoneButton()
    let toolsTab: ImageButton
    let tintTab: ImageButton
    private let hud = TextView()
    private var scrollObserver: NSObjectProtocol?
    var imageSize: NSSize = NSMakeSize(16, 9)

    required init(frame frameRect: NSRect) {
        self.toolsTab = makeGlassIconButton(NSImage(resource: .iconEditVideoTools).precomposed(.white))
        self.tintTab = makeGlassIconButton(NSImage(resource: .iconEditVideoTint).precomposed(.white))
        super.init(frame: frameRect)
        preview.contentGravity = .resizeAspect
        preview.isAccessibilityDecorative = true
        addSubview(preview)
        addSubview(previewControl)

        panel.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        panel.layer?.cornerRadius = 12
        addSubview(panel)
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.scrollerStyle = .overlay
        scrollView.applyThemedVerticalScroller()
        scrollView.documentView = rowsView
        scrollView.contentView.postsBoundsChangedNotifications = true
        panel.addSubview(scrollView)
        for tool in EditVideoTool.allCases {
            let row = EditVideoToolRowView(frame: .zero)
            rows[tool] = row
            rowsView.addSubview(row)
        }
        tintView.addSubview(shadowsSection)
        tintView.addSubview(highlightsSection)
        panel.addSubview(tintView)

        toolsTab.setAccessibilityLabel(strings().editVideoToolsControllerTools)
        tintTab.setAccessibilityLabel(strings().editVideoToolsControllerTint)
        for view in [cancel, done, toolsTab, tintTab] as [NSView] {
            addSubview(view)
        }

        hud.userInteractionEnabled = false
        hud.isSelectable = false
        hud.backgroundColor = NSColor.black.withAlphaComponent(0.9)
        hud.layer?.cornerRadius = 6
        hud.isHidden = true
        addSubview(hud)

        scrollObserver = NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scrollView.contentView, queue: nil, using: { [weak self] _ in
            self?.updateRowsVisibility()
        })
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if let scrollObserver = scrollObserver {
            NotificationCenter.default.removeObserver(scrollObserver)
        }
    }

    private func updateRowsVisibility() {
        let visible = scrollView.documentVisibleRect
        for row in rows.values {
            let fraction = max(0, min(1, row.frame.intersection(visible).height / max(1, row.frame.height)))
            row.alphaValue = fraction * fraction
        }
    }

    func showTint(_ tint: Bool) {
        scrollView.isHidden = tint
        tintView.isHidden = !tint
        toolsTab.set(image: NSImage(resource: .iconEditVideoTools).precomposed(tint ? .white : nightAccentPalette.accent), for: .Normal)
        tintTab.set(image: NSImage(resource: .iconEditVideoTint).precomposed(tint ? nightAccentPalette.accent : .white), for: .Normal)
    }

    func showHud(_ text: String?) {
        guard let text = text else {
            hud.isHidden = true
            return
        }
        let layout = TextViewLayout(.initialize(string: text, color: .white, font: .medium(14)), maximumNumberOfLines: 1, alignment: .center)
        layout.measure(width: .greatestFiniteMagnitude)
        hud.update(layout)
        hud.setFrameSize(NSMakeSize(layout.layoutSize.width + 24, 30))
        hud.isHidden = false
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let rowY = frame.height - 16 - 40
        layoutEditVideoRow(in: self, y: rowY, cancel: cancel, done: done, center: [toolsTab, tintTab])

        let padding: CGFloat = 8
        let spacing: CGFloat = 6
        let visibleRows: CGFloat = 4
        let panelWidth = min(frame.width - 32, 560)
        let panelHeight = padding * 2 + visibleRows * EditVideoToolRowView.height + (visibleRows - 1) * spacing
        panel.frame = NSMakeRect(floor((frame.width - panelWidth) / 2.0), rowY - 16 - panelHeight, panelWidth, panelHeight)
        scrollView.frame = panel.bounds
        var y: CGFloat = padding
        for tool in EditVideoTool.allCases {
            rows[tool]?.frame = NSMakeRect(0, y, panel.frame.width, EditVideoToolRowView.height)
            y += EditVideoToolRowView.height + spacing
        }
        rowsView.frame = NSMakeRect(0, 0, panel.frame.width, y - spacing + padding)
        updateRowsVisibility()
        tintView.frame = panel.bounds
        let sectionsY = floor((panel.frame.height - 192) / 2)
        shadowsSection.frame = NSMakeRect(0, sectionsY, panel.frame.width, 92)
        highlightsSection.frame = NSMakeRect(0, sectionsY + 100, panel.frame.width, 92)

        let area = NSMakeRect(24, 24, max(1, frame.width - 48), max(1, panel.frame.minY - 48))
        let fitted = imageSize.aspectFitted(area.size)
        preview.frame = NSMakeRect(floor(area.midX - fitted.width / 2.0), floor(area.midY - fitted.height / 2.0), fitted.width, fitted.height)
        previewControl.frame = preview.frame
        hud.setFrameOrigin(NSMakePoint(floor((frame.width - hud.frame.width) / 2.0), 15))
    }
}

public final class EditVideoToolsController: ModalViewController {
    private let still: CGImage
    private var spec: EditVideoRenderSpec
    private let initialTools: [EditVideoTool: Int]
    private let initialTint: EditVideoTint
    private let completion: ([EditVideoTool: Int], EditVideoTint) -> Void
    private let enhance: [CIFilter]
    private var showsOriginal = false
    private var isClosing = false

    public init(still: CGImage, spec: EditVideoRenderSpec, completion: @escaping ([EditVideoTool: Int], EditVideoTint) -> Void) {
        self.still = EditVideoToolsController.downscaled(still, maxSide: 1280)
        self.spec = spec
        self.initialTools = spec.tools
        self.initialTint = spec.tint
        self.completion = completion
        self.enhance = CIImage(cgImage: self.still).autoAdjustmentFilters(options: [.redEye: false])
        super.init()
        bar = .init(height: 0)
    }

    private static func downscaled(_ image: CGImage, maxSide: CGFloat) -> CGImage {
        let side = CGFloat(max(image.width, image.height))
        guard side > maxSide else {
            return image
        }
        let scale = maxSide / side
        let scaled = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        return EditVideoRenderer.context.createCGImage(scaled, from: scaled.extent) ?? image
    }

    public override var containerBackground: NSColor {
        return .clear
    }

    public override var isVisualEffectBackground: Bool {
        return true
    }

    public override var background: NSColor {
        return .clear
    }

    public override func measure(size: NSSize) {
        if let contentSize = self.modal?.window.contentView?.frame.size {
            self.modal?.resize(with: NSMakeSize(contentSize.width - 80, contentSize.height - 80), animated: false)
        }
    }

    public override var dynamicSize: Bool {
        return true
    }

    public override func viewClass() -> AnyClass {
        return EditVideoToolsView.self
    }

    private var genericView: EditVideoToolsView {
        return self.view as! EditVideoToolsView
    }

    private var hasChanges: Bool {
        return spec.tools != initialTools || spec.tint != initialTint
    }

    private func renderPreview() {
        var current = spec
        if showsOriginal {
            current.tools = [:]
            current.tint = EditVideoTint()
        }
        let output = EditVideoRenderer.render(CIImage(cgImage: still), spec: current, enhance: enhance, outputSize: nil)
        if let image = EditVideoRenderer.context.createCGImage(output, from: output.extent) {
            genericView.imageSize = image.size
            genericView.preview.image = image
            genericView.needsLayout = true
        }
    }

    private func updateTint() {
        genericView.shadowsSection.update(selected: spec.tint.shadowsColor, intensity: spec.tint.shadowsIntensity)
        genericView.highlightsSection.update(selected: spec.tint.highlightsColor, intensity: spec.tint.highlightsIntensity)
    }

    private func done() {
        guard !isClosing else {
            return
        }
        isClosing = true
        completion(spec.tools.filter { $0.value != 0 }, spec.tint)
        close()
    }

    private func cancel() {
        guard !isClosing else {
            return
        }
        let close: () -> Void = { [weak self] in
            self?.isClosing = true
            self?.close()
        }
        if hasChanges, let window = self.window, let confirm = ImageCanvasUIHooks.shared.confirm {
            confirm(window, strings().editImageControlConfirmDiscard, strings().alertDiscard, close)
        } else {
            close()
        }
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        let genericView = self.genericView
        for tool in EditVideoTool.allCases {
            guard let row = genericView.rows[tool] else {
                continue
            }
            row.update(title: tool.title, value: spec.tools[tool] ?? 0, minimum: tool.minimum, maximum: tool.maximum)
            row.slider.onChange = { [weak self, weak row] value, _ in
                guard let self = self else {
                    return
                }
                self.spec.tools[tool] = Int(value)
                row?.setValue(Int(value))
                self.genericView.showHud(row?.slider.isDragging == true ? "\(tool.title)  \(Int(value))" : nil)
                self.renderPreview()
            }
            row.slider.onDragging = { [weak self, weak row] dragging in
                row?.slider.isDragging = dragging
                if !dragging {
                    self?.genericView.showHud(nil)
                }
            }
        }
        genericView.shadowsSection.onSelect = { [weak self] color in
            self?.spec.tint.shadowsColor = color
            self?.updateTint()
            self?.renderPreview()
        }
        genericView.highlightsSection.onSelect = { [weak self] color in
            self?.spec.tint.highlightsColor = color
            self?.updateTint()
            self?.renderPreview()
        }
        genericView.shadowsSection.slider.onChange = { [weak self] value, _ in
            self?.spec.tint.shadowsIntensity = Int(value)
            self?.renderPreview()
        }
        genericView.highlightsSection.slider.onChange = { [weak self] value, _ in
            self?.spec.tint.highlightsIntensity = Int(value)
            self?.renderPreview()
        }
        genericView.toolsTab.set(handler: { [weak self] _ in
            self?.genericView.showTint(false)
        }, for: .Click)
        genericView.tintTab.set(handler: { [weak self] _ in
            self?.genericView.showTint(true)
        }, for: .Click)
        genericView.cancel.set(handler: { [weak self] _ in
            self?.cancel()
        }, for: .Click)
        genericView.done.set(handler: { [weak self] _ in
            self?.done()
        }, for: .Click)
        genericView.previewControl.set(handler: { [weak self] _ in
            self?.showsOriginal = true
            self?.genericView.showHud(strings().editVideoToolsControllerOriginal)
            self?.renderPreview()
        }, for: .Down)
        genericView.previewControl.set(handler: { [weak self] _ in
            self?.showsOriginal = false
            self?.genericView.showHud(nil)
            self?.renderPreview()
        }, for: .Up)
        genericView.showTint(false)
        updateTint()
        renderPreview()
        readyOnce()
    }

    public override func returnKeyAction() -> KeyHandlerResult {
        done()
        return .invoked
    }

    public override func escapeKeyAction() -> KeyHandlerResult {
        cancel()
        return .invoked
    }
}
