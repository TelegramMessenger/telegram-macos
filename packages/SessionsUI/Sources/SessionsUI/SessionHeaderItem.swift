import Cocoa
import TGUIKit
import GeneralRows
import TelegramTheme
import TelegramContext
import LocalAnimations

final class SessionHeaderItem: GeneralRowItem {
    fileprivate let context: any AccountContextProtocol
    fileprivate let sticker: LocalAnimatedSticker
    fileprivate let stickerSize: NSSize
    fileprivate let bgColor: NSColor?
    fileprivate let modify: [String]?
    fileprivate let name: String
    fileprivate let nameLayout: TextViewLayout
    fileprivate let dateLayout: TextViewLayout
    fileprivate let rename: ((NSView) -> Void)?

    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, sticker: LocalAnimatedSticker, stickerSize: NSSize, bgColor: NSColor?, modify: [String]?, name: String, date: String, rename: ((NSView) -> Void)?) {
        self.context = context
        self.sticker = sticker
        self.stickerSize = stickerSize
        self.bgColor = bgColor
        self.modify = modify
        self.rename = rename
        self.name = name
        self.nameLayout = SessionHeaderItem.makeNameLayout(name)
        self.dateLayout = TextViewLayout(.initialize(string: date, color: theme.colors.listGrayText, font: .normal(.text)), maximumNumberOfLines: 1, alignment: .center)
        super.init(initialSize, stableId: stableId, inset: NSEdgeInsets(left: 20, right: 20, top: 0, bottom: 10))
    }

    fileprivate static func makeNameLayout(_ name: String) -> TextViewLayout {
        return TextViewLayout(.initialize(string: name, color: theme.colors.text, font: .medium(.title)), maximumNumberOfLines: 1, alignment: .center)
    }

    fileprivate var textWidth: CGFloat {
        return width - inset.left - inset.right - SessionHeaderView.namePadding.width * 2
    }

    override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        nameLayout.measure(width: textWidth)
        dateLayout.measure(width: textWidth)
        return result
    }

    override func viewClass() -> AnyClass {
        return SessionHeaderView.self
    }

    override var height: CGFloat {
        return 10 + stickerSize.height + 10 + nameLayout.layoutSize.height + dateLayout.layoutSize.height + inset.bottom
    }
}

private final class SessionNameControl: Control, MorphHoldObserving {
    var holdDidChange: ((Bool) -> Void)?

    func morphHoldDidChange(_ isHeld: Bool) {
        holdDidChange?(isHeld)
    }
}

private final class SessionHeaderView: GeneralContainableRowView {
    static let namePadding = NSMakeSize(6, 2)

    private var animationView: GeneralRowsAnimatedItemView?
    private let bgView = View()
    private let nameControl = SessionNameControl()
    private let nameView = TextView()
    private let dateView = TextView()

    private var displayedName: String?
    private let scrambleAnimation = ScrambleTextAnimation()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(bgView)
        addSubview(dateView)
        addSubview(nameControl)
        nameControl.addSubview(nameView)
        nameControl.layer?.cornerRadius = 6
        nameView.isSelectable = false
        nameView.userInteractionEnabled = false
        dateView.isSelectable = false
        dateView.userInteractionEnabled = false
        bgView.layer?.cornerRadius = 10

        nameControl.set(handler: { [weak self] control in
            guard let rename = (self?.item as? SessionHeaderItem)?.rename else {
                return
            }
            if !ModalMorphTransition.reduceMotion() {
                self?.updateNameBackground(highlighted: false)
                CATransaction.flush()
            }
            DispatchQueue.main.async { [weak control] in
                if let control = control {
                    rename(control)
                }
            }
        }, for: .Click)

        nameControl.holdDidChange = { [weak self] isHeld in
            if !isHeld {
                self?.updateNameBackground(highlighted: true)
            }
        }
    }

    private func updateNameBackground(highlighted: Bool) {
        let color = highlighted && (item as? SessionHeaderItem)?.rename != nil ? theme.colors.grayForeground : .clear
        nameControl.set(background: .clear, for: .Normal)
        nameControl.set(background: color, for: .Hover)
        nameControl.set(background: color, for: .Highlight)
    }

    override var backdorColor: NSColor {
        return theme.colors.listBackground
    }

    override func updateColors() {
        super.updateColors()
        nameView.backgroundColor = .clear
        dateView.backgroundColor = backdorColor
    }

    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)

        guard let item = item as? SessionHeaderItem else {
            return
        }

        let current: GeneralRowsAnimatedItemView
        if let view = self.animationView {
            current = view
        } else {
            current = GeneralRowsHooks.shared.makeStickerHeaderView(item.stickerSize.bounds)
            self.animationView = current
            addSubview(current)
        }
        let params = GeneralRowsHooks.shared.localStickerParameters(item.sticker)
        if let modify = item.modify, let color = item.bgColor {
            params.colors = modify.map {
                .init(keyPath: $0, color: color)
            }
        }
        current.updateStickerHeader(with: item.sticker.file, size: item.stickerSize, context: item.context, parent: nil, table: item.table, parameters: params, animated: animated, positionFlags: nil, approximateSynchronousValue: false)

        bgView.isHidden = item.bgColor == nil
        bgView.backgroundColor = item.bgColor ?? .clear
        bgView.setFrameSize(item.stickerSize)

        nameControl.userInteractionEnabled = item.rename != nil
        updateNameBackground(highlighted: true)

        dateView.update(item.dateLayout)

        if let displayedName = displayedName, displayedName != item.name, animated {
            self.displayedName = item.name
            let textWidth = item.textWidth
            scrambleAnimation.start(from: nameView.textLayout?.attributedString.string ?? displayedName, to: item.name, update: { [weak self] text in
                let layout = SessionHeaderItem.makeNameLayout(text)
                layout.measure(width: textWidth)
                self?.showName(layout)
            })
        } else if displayedName != item.name || !scrambleAnimation.isRunning {
            scrambleAnimation.cancel()
            displayedName = item.name
            showName(item.nameLayout)
        }

        needsLayout = true
    }

    private func showName(_ layout: TextViewLayout) {
        nameView.update(layout)
        nameView.setFrameSize(layout.layoutSize)
        nameControl.setFrameSize(NSMakeSize(layout.layoutSize.width + SessionHeaderView.namePadding.width * 2, layout.layoutSize.height + SessionHeaderView.namePadding.height * 2))
        layoutName()
    }

    private func layoutName() {
        guard let item = item as? SessionHeaderItem else {
            return
        }
        nameControl.setFrameOrigin(NSMakePoint(floorToScreenPixels((containerView.frame.width - nameControl.frame.width) / 2), 10 + item.stickerSize.height + 10 - SessionHeaderView.namePadding.height))
        nameView.setFrameOrigin(NSMakePoint(SessionHeaderView.namePadding.width, SessionHeaderView.namePadding.height))
    }

    override func layout() {
        super.layout()
        guard let item = item as? SessionHeaderItem else {
            return
        }
        animationView?.centerX(y: 10)
        if let animationView = animationView {
            bgView.frame = animationView.frame
        }
        layoutName()
        dateView.centerX(y: 10 + item.stickerSize.height + 10 + item.nameLayout.layoutSize.height)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
