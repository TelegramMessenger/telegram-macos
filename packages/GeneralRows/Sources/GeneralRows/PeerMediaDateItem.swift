import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
import TelegramTheme
import TelegramUtils

public class PeerMediaDateItem: TableStickItem {

    private let _stableId: AnyHashable
    fileprivate let messageIndex: MessageIndex
    fileprivate let textLayout: TextViewLayout
    fileprivate let pinnedMonthLayout: TextViewLayout
    fileprivate let pinnedYearLayout: TextViewLayout
    private let isStickPlaceholder: Bool
    public let viewType: GeneralViewType
    public let inset: NSEdgeInsets

    public init(_ initialSize: NSSize, index: MessageIndex, stableId: AnyHashable, inset: NSEdgeInsets = NSEdgeInsets(left: 0, right: 0)) {
        self.messageIndex = index
        self._stableId = stableId
        self.viewType = .modern(position: .single, insets: NSEdgeInsetsMake(3, 0, 3, 0))
        self.inset = inset
        let timestamp = index.timestamp
        
        let nowTimestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
        
        var t: time_t = time_t(timestamp)
        var timeinfo: tm = tm()
        localtime_r(&t, &timeinfo)
        
        var now: time_t = time_t(nowTimestamp)
        var timeinfoNow: tm = tm()
        localtime_r(&now, &timeinfoNow)
        
        let text = DateSelectorUtil.mediaDate.string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))

        textLayout = TextViewLayout(.initialize(string: text.uppercased(), color: theme.colors.listGrayText, font: .normal(.short)))
        let yearSeparator = text.range(of: " ", options: .backwards)
        let month = yearSeparator.map { String(text[..<$0.lowerBound]) } ?? text
        let year = yearSeparator.map { String(text[$0.upperBound...]) } ?? ""
        pinnedMonthLayout = TextViewLayout(.initialize(string: month, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)
        pinnedYearLayout = TextViewLayout(.initialize(string: year, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)
        isStickPlaceholder = false
        super.init(initialSize)
        _ = makeSize(initialSize.width, oldWidth: 0)
    }

    public required init(_ initialSize: NSSize) {
        self._stableId = AnyHashable(0)
        self.messageIndex = MessageIndex.absoluteLowerBound()
        self.textLayout = TextViewLayout(.initialize(string: ""))
        self.pinnedMonthLayout = TextViewLayout(.initialize(string: ""))
        self.pinnedYearLayout = TextViewLayout(.initialize(string: ""))
        self.isStickPlaceholder = true
        self.viewType = .separator
        self.inset = NSEdgeInsets(left: 0, right: 0)
        super.init(initialSize)
    }


    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        textLayout.measure(width: width - 60)
        pinnedMonthLayout.measure(width: width - 60)
        pinnedYearLayout.measure(width: width - 60)
        return success
    }

    public override var isFixed: Bool {
        return true
    }
    
    public override var stableId: AnyHashable {
        return _stableId
    }
    
    public override var height: CGFloat {
        return textLayout.layoutSize.height + viewType.innerInset.top + viewType.innerInset.bottom + 9
    }
    
    public override func viewClass() -> AnyClass {
        return isStickPlaceholder ? PeerMediaDatePinnedView.self : PeerMediaDateView.self
    }
}

fileprivate class PeerMediaDateView : TableStickView {
     private let containerView = GeneralRowContainerView(frame: NSZeroRect)
       private let textView = TextView()
       required init(frame frameRect: NSRect) {
           super.init(frame: frameRect)
           addSubview(self.containerView)
           containerView.addSubview(self.textView)
           self.textView.disableBackgroundDrawing = true
           self.textView.isSelectable = false
           self.textView.userInteractionEnabled = false
       }
       
       override var header: Bool {
           didSet {
               updateColors()
           }
       }

       override var backdorColor: NSColor {
           return theme.colors.listBackground.withAlphaComponent(0.8)
       }
       
       override func updateColors() {
           guard let item = item as? PeerMediaDateItem else {
               return
           }
           self.backgroundColor = item.viewType.rowBackground
           self.containerView.backgroundColor = backdorColor
       }
       
       override func layout() {
           super.layout()
           guard let item = item as? PeerMediaDateItem else {
               return
           }
           let blockWidth = frame.width - item.inset.left - item.inset.right
           
           self.containerView.frame = NSMakeRect(floorToScreenPixels(backingScaleFactor, (frame.width - blockWidth) / 2), item.inset.top, blockWidth, frame.height - item.inset.bottom - item.inset.top)
           self.containerView.setCorners([])
           
           textView.centerY(x: item.viewType.innerInset.left + 12)
       }
       
       override func set(item: TableRowItem, animated: Bool = false) {
           super.set(item: item, animated: animated)
           
           guard let item = item as? PeerMediaDateItem else {
               return
           }
           self.textView.update(item.textLayout)
           
           needsLayout = true
       }
       
       required init?(coder: NSCoder) {
           fatalError("init(coder:) has not been implemented")
       }
}


fileprivate final class PeerMediaDatePinnedView : TableStickView {
    private static let pillHeight: CGFloat = 28
    private static let pillInset: CGFloat = 13
    private static let partSpacing: CGFloat = 4
    private static let hideTimeout: Double = 2.0
    private static let morphDuration: Double = 0.35
    private static let morphOffset: CGFloat = 14
    private static let morphScale: CGFloat = 0.7

    private let pillView = View()
    private let glassView = LiquidGlassView(frame: NSZeroRect, cornerRadius: PeerMediaDatePinnedView.pillHeight / 2, hasShadow: true, hasBorder: true)
    private let clipView = View()
    private var monthView = PeerMediaDatePinnedView.makeTextView()
    private var yearView = PeerMediaDatePinnedView.makeTextView()
    private var outgoingViews: [TextView] = []
    private var appliedTheme: PresentationTheme?
    private var hideDeadline: CFTimeInterval = 0
    private var hideTimer: SwiftSignalKit.Timer?

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
        pillView.layer?.masksToBounds = false
        pillView.layer?.opacity = 0
        clipView.layer?.cornerRadius = PeerMediaDatePinnedView.pillHeight / 2
        addSubview(pillView)
        pillView.addSubview(glassView)
        pillView.addSubview(clipView)
        clipView.addSubview(monthView)
        clipView.addSubview(yearView)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        hideTimer?.invalidate()
    }

    private static func makeTextView() -> TextView {
        let textView = TextView()
        textView.disableBackgroundDrawing = true
        textView.isSelectable = false
        textView.userInteractionEnabled = false
        return textView
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    override func updateColors() {
        super.updateColors()
        if appliedTheme !== theme {
            appliedTheme = theme
            glassView.updateLocalizationAndTheme(theme: theme)
        }
    }

    override func updateIsVisible(_ visible: Bool, animated: Bool) {
        pillView.change(opacity: visible ? 1 : 0, animated: animated)
        if visible {
            hideDeadline = CACurrentMediaTime() + PeerMediaDatePinnedView.hideTimeout
            if hideTimer == nil {
                armHideTimer(PeerMediaDatePinnedView.hideTimeout)
            }
        } else {
            hideTimer?.invalidate()
            hideTimer = nil
        }
    }

    private func armHideTimer(_ timeout: Double) {
        let timer = SwiftSignalKit.Timer(timeout: timeout, repeat: false, completion: { [weak self] in
            guard let self = self else {
                return
            }
            self.hideTimer = nil
            let remaining = self.hideDeadline - CACurrentMediaTime()
            if remaining > 0 {
                self.armHideTimer(remaining)
            } else {
                self.pillView.change(opacity: 0, animated: true, duration: 0.3)
            }
        }, queue: Queue.mainQueue())
        hideTimer = timer
        timer.start()
    }

    override func set(item: TableRowItem, animated: Bool = false) {
        let previous = self.item as? PeerMediaDateItem
        super.set(item: item, animated: animated)
        guard let item = item as? PeerMediaDateItem else {
            return
        }
        for view in outgoingViews {
            view.removeFromSuperview()
        }
        outgoingViews.removeAll()

        let monthChanged = previous?.pinnedMonthLayout.attributedString.string != item.pinnedMonthLayout.attributedString.string
        let yearChanged = previous?.pinnedYearLayout.attributedString.string != item.pinnedYearLayout.attributedString.string
        guard let previous = previous, !previous.pinnedMonthLayout.attributedString.string.isEmpty, monthChanged || yearChanged, pillView.layer?.opacity != 0 else {
            monthView.update(item.pinnedMonthLayout)
            yearView.update(item.pinnedYearLayout)
            updateLayout(size: frame.size, transition: .immediate)
            return
        }

        let transition: ContainedViewLayoutTransition = .animated(duration: PeerMediaDatePinnedView.morphDuration, curve: .spring)
        let direction: CGFloat = item.messageIndex < previous.messageIndex ? 1 : -1
        let shift = pillFrame(item, size: frame.size).minX - pillView.frame.minX
        let frames = partFrames(item)
        if monthChanged {
            monthView = morph(monthView, to: item.pinnedMonthLayout, frame: frames.month, shift: shift, direction: direction, transition: transition)
        }
        if yearChanged {
            yearView = morph(yearView, to: item.pinnedYearLayout, frame: frames.year, shift: shift, direction: direction, transition: transition)
        }
        updateLayout(size: frame.size, transition: transition)
    }

    private func morph(_ outgoing: TextView, to layout: TextViewLayout, frame: NSRect, shift: CGFloat, direction: CGFloat, transition: ContainedViewLayoutTransition) -> TextView {
        let duration = PeerMediaDatePinnedView.morphDuration
        let offset = PeerMediaDatePinnedView.morphOffset * direction
        let scale = PeerMediaDatePinnedView.morphScale

        let incoming = PeerMediaDatePinnedView.makeTextView()
        incoming.update(layout)
        incoming.frame = frame.offsetBy(dx: shift, dy: 0)
        clipView.addSubview(incoming)
        incoming.layer?.animate(from: NSValue(point: NSMakePoint(0, offset)), to: NSValue(point: .zero), keyPath: "position", timingFunction: .easeOut, duration: duration, additive: true, forKey: "morph")
        incoming.layer?.animateScaleSpring(from: scale, to: 1, duration: duration, bounce: false)
        incoming.layer?.animateAlpha(from: 0, to: 1, duration: duration * 0.6)

        outgoingViews.append(outgoing)
        transition.updateFrame(view: outgoing, frame: outgoing.frame.offsetBy(dx: -shift, dy: 0))
        outgoing.layer?.animate(from: NSValue(point: .zero), to: NSValue(point: NSMakePoint(0, -offset)), keyPath: "position", timingFunction: .easeOut, duration: duration, removeOnCompletion: false, additive: true, forKey: "morph")
        outgoing.layer?.animateScaleSpring(from: 1, to: scale, duration: duration, removeOnCompletion: false, bounce: false)
        outgoing.layer?.animateAlpha(from: 1, to: 0, duration: duration * 0.4, removeOnCompletion: false, completion: { [weak self, weak outgoing] _ in
            guard let outgoing = outgoing else {
                return
            }
            outgoing.removeFromSuperview()
            self?.outgoingViews.removeAll(where: { $0 === outgoing })
        })
        return incoming
    }

    private func pillFrame(_ item: PeerMediaDateItem, size: NSSize) -> NSRect {
        let monthWidth = item.pinnedMonthLayout.layoutSize.width
        let yearWidth = item.pinnedYearLayout.layoutSize.width
        let contentWidth = yearWidth > 0 ? monthWidth + PeerMediaDatePinnedView.partSpacing + yearWidth : monthWidth
        let width = contentWidth + PeerMediaDatePinnedView.pillInset * 2
        let height = PeerMediaDatePinnedView.pillHeight
        return NSMakeRect(floorToScreenPixels(backingScaleFactor, (size.width - width) / 2), floorToScreenPixels(backingScaleFactor, (size.height - height) / 2), width, height)
    }

    private func partFrames(_ item: PeerMediaDateItem) -> (month: NSRect, year: NSRect) {
        let monthSize = item.pinnedMonthLayout.layoutSize
        let yearSize = item.pinnedYearLayout.layoutSize
        let height = PeerMediaDatePinnedView.pillHeight
        let month = NSMakeRect(PeerMediaDatePinnedView.pillInset, floorToScreenPixels(backingScaleFactor, (height - monthSize.height) / 2), monthSize.width, monthSize.height)
        let year = NSMakeRect(month.maxX + PeerMediaDatePinnedView.partSpacing, floorToScreenPixels(backingScaleFactor, (height - yearSize.height) / 2), yearSize.width, yearSize.height)
        return (month, year)
    }

    override func layout() {
        super.layout()
        updateLayout(size: frame.size, transition: .immediate)
    }

    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        guard let item = item as? PeerMediaDateItem else {
            return
        }
        let pillFrame = self.pillFrame(item, size: size)
        let frames = partFrames(item)
        transition.updateFrame(view: pillView, frame: pillFrame)
        transition.updateFrame(view: glassView, frame: pillFrame.size.bounds)
        glassView.updateLayout(size: pillFrame.size, transition: transition)
        transition.updateFrame(view: clipView, frame: pillFrame.size.bounds)
        transition.updateFrame(view: monthView, frame: frames.month)
        transition.updateFrame(view: yearView, frame: frames.year)
    }
}
