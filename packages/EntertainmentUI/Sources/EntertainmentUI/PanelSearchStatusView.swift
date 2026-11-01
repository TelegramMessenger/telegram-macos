import Cocoa
import TGUIKit

final class PanelSearchStatusView: View {
    private let titleView = TextView()
    private let detailView = TextView()
    private let shimmer = CAGradientLayer()
    private let shimmerMask = CAShapeLayer()
    private let frost = PickerFrostView()
    private let frostMask = CAShapeLayer()
    private var animationView: View?
    private var makeAnimation: (() -> View?)?
    private(set) var status: PanelSearchPresentation = .hidden
    private var kind: PanelSearchPlaceholderKind = .stickers
    private var reduceMotion = false
    private var title = ""
    private var detail = ""
    private var textColor: NSColor = .labelColor
    private var detailColor: NSColor = .secondaryLabelColor
    private var measuredWidth: CGFloat = -1
    private var shimmerSize = CGSize(width: -1, height: -1)
    private var shimmerKind: PanelSearchPlaceholderKind = .stickers

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isEventLess = true
        isHidden = true
        frost.wantsLayer = true
        frost.material = .selection
        frost.blendingMode = .withinWindow
        frost.state = .active
        frost.isHidden = true
        frost.layer?.mask = frostMask
        addSubview(frost)
        titleView.isSelectable = false
        detailView.isSelectable = false
        titleView.isAccessibilityDecorative = true
        detailView.isAccessibilityDecorative = true
        addSubview(titleView)
        addSubview(detailView)
        shimmer.mask = shimmerMask
        shimmer.startPoint = CGPoint(x: 0, y: 0.5)
        shimmer.endPoint = CGPoint(x: 1, y: 0.5)
        shimmer.locations = [0, 0.5, 1]
        layer?.addSublayer(shimmer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(status: PanelSearchPresentation, kind: PanelSearchPlaceholderKind, title: String, detail: String, loadingLabel: String, backgroundColor: NSColor, frosted: Bool = false, isDark: Bool = false, textColor: NSColor, detailColor: NSColor, reduceMotion: Bool, makeAnimation: @escaping () -> View?) {
        let textChanged = self.title != title || self.detail != detail || self.textColor != textColor || self.detailColor != detailColor
        if self.reduceMotion != reduceMotion { removeAnimation() }
        self.status = status
        self.kind = kind
        self.title = title
        self.detail = detail
        self.textColor = textColor
        self.detailColor = detailColor
        self.reduceMotion = reduceMotion
        self.makeAnimation = makeAnimation
        self.backgroundColor = backgroundColor
        shimmer.colors = [detailColor.withAlphaComponent(0.08).cgColor, detailColor.withAlphaComponent(0.20).cgColor, detailColor.withAlphaComponent(0.08).cgColor]
        shimmer.isHidden = status != .loading
        frost.isHidden = status != .loading || !frosted
        frost.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        titleView.isHidden = status != .empty
        detailView.isHidden = status != .empty || detail.isEmpty
        isHidden = status == .hidden
        setAccessibilityElement(status != .hidden)
        setAccessibilityRole(status == .loading ? .busyIndicator : .staticText)
        setAccessibilityLabel(status == .loading ? loadingLabel : [title, detail].filter { !$0.isEmpty }.joined(separator: ". "))
        if textChanged { measuredWidth = -1 }
        updateActivity()
        needsLayout = true
    }

    private func removeAnimation() {
        animationView?.removeFromSuperview()
        animationView = nil
    }

    private func updateActivity() {
        let visible = window != nil && !isHiddenOrHasHiddenAncestor
        if visible && status == .empty {
            if animationView == nil, let view = makeAnimation?() {
                animationView = view
                view.setAccessibilityElement(false)
                addSubview(view)
                if !reduceMotion { view.layer?.animateAlpha(from: 0, to: 1, duration: 0.18) }
                needsLayout = true
            }
        } else {
            removeAnimation()
        }
        if visible && status == .loading && !reduceMotion {
            if shimmer.animation(forKey: "searchShimmer") == nil {
                let animation = CABasicAnimation(keyPath: "locations")
                animation.fromValue = [-1, -0.5, 0]
                animation.toValue = [1, 1.5, 2]
                animation.duration = 1.4
                animation.repeatCount = .infinity
                shimmer.add(animation, forKey: "searchShimmer")
            }
        } else {
            shimmer.removeAnimation(forKey: "searchShimmer")
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateActivity()
    }

    override func viewDidHide() {
        super.viewDidHide()
        updateActivity()
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        updateActivity()
    }

    override func layout() {
        super.layout()
        guard status != .hidden else { return }
        if status == .loading {
            if shimmerSize != bounds.size || shimmerKind != kind {
                shimmerSize = bounds.size
                shimmerKind = kind
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                shimmer.frame = bounds
                shimmerMask.frame = bounds
                let path = CGMutablePath()
                for rect in kind.frames(in: bounds.size) {
                    let radius: CGFloat = kind == .emoji ? rect.width / 2 : 12
                    path.addRoundedRect(in: rect, cornerWidth: radius, cornerHeight: radius)
                }
                shimmerMask.path = path
                frost.frame = bounds
                frostMask.frame = bounds
                var flip = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: bounds.height)
                frostMask.path = frost.isFlipped ? path : path.copy(using: &flip)
                CATransaction.commit()
            }
            return
        }
        let width = max(0, bounds.width - 48)
        if measuredWidth != width {
            measuredWidth = width
            let titleLayout = TextViewLayout(.initialize(string: title, color: textColor, font: .medium(15)), maximumNumberOfLines: 2, alignment: .center)
            let detailLayout = TextViewLayout(.initialize(string: detail, color: detailColor, font: .normal(13)), maximumNumberOfLines: 3, alignment: .center)
            titleLayout.measure(width: width)
            detailLayout.measure(width: width)
            titleView.update(titleLayout)
            detailView.update(detailLayout)
        }
        let side = min(120, max(0, bounds.width - 48), max(0, bounds.height - titleView.frame.height - detailView.frame.height - 48))
        let height = side + 16 + titleView.frame.height + (detail.isEmpty ? 0 : 8 + detailView.frame.height)
        let top = max(8, floor((bounds.height - height) * 0.45))
        animationView?.frame = CGRect(x: floor((bounds.width - side) / 2), y: top, width: side, height: side)
        titleView.centerX(y: top + side + 16)
        detailView.centerX(y: titleView.frame.maxY + 8)
    }
}
