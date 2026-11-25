import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import InputDataUI
import GeneralRows
import Localization
import TelegramContext
import TelegramTheme
import ColorPalette
import ChatHistoryModel
import Postbox
import AppAnalytics


private let _id_header = InputDataIdentifier("_id_header")
private let _id_description = InputDataIdentifier("_id_description")
private let _id_preview = InputDataIdentifier("_id_preview")

private final class Arguments {
    public let context: any AccountContextProtocol
    public let dismiss: () -> Void
    public init(context: any AccountContextProtocol, dismiss: @escaping () -> Void) {
        self.context = context
        self.dismiss = dismiss
    }
}

private struct State : Equatable {

}

// MARK: - Header Item

private final class UserTagHeaderItem: GeneralRowItem {
    fileprivate let headerImage: CGImage
    fileprivate let circleColor: NSColor
    fileprivate let circleSize: CGFloat = 100
    fileprivate let dismiss: () -> Void

    public init(_ initialSize: NSSize, stableId: AnyHashable, headerImage: CGImage, circleColor: NSColor, dismiss: @escaping () -> Void) {
        self.headerImage = headerImage
        self.circleColor = circleColor
        self.dismiss = dismiss
        super.init(initialSize, stableId: stableId)
    }

    public override func viewClass() -> AnyClass {
        return UserTagHeaderView.self
    }

    public override var height: CGFloat {
        return circleSize + 30
    }

    public override var accessibilityLabel: String? {
        return strings().voiceOverCommonTagInfo
    }
}

private final class UserTagHeaderView: GeneralRowView {
    private let imageView = ImageView()
    private let circleView = View()
    private let dismiss = ImageButton()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(circleView)
        addSubview(imageView)
        addSubview(dismiss)
        dismiss.scaleOnClick = true
        imageView.isAccessibilityDecorative = true
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)

        guard let item = item as? UserTagHeaderItem else {
            return
        }

        imageView.image = item.headerImage
        imageView.sizeToFit()

        circleView.setFrameSize(NSMakeSize(item.circleSize, item.circleSize))
        circleView.layer?.cornerRadius = item.circleSize / 2
        circleView.backgroundColor = item.circleColor

        dismiss.set(image: theme.icons.glass_close, for: .Normal)
        dismiss.setGlassEffect(size: NSMakeSize(36, 36))
        dismiss.sizeToFit(.zero, NSMakeSize(36, 36), thatFit: true)
        dismiss.removeAllHandlers()
        dismiss.setSingle(handler: { [weak item] _ in
            item?.dismiss()
        }, for: .Click)

        needsLayout = true
    }

    public override func layout() {
        super.layout()
        dismiss.setFrameOrigin(NSMakePoint(10, 10))
        circleView.centerX(y: 20)
        imageView.centerX(y: circleView.frame.minY + (circleView.frame.height - imageView.frame.height) / 2)
    }
}

// MARK: - Message Preview Item

private final class UserTagPreviewItem: GeneralRowItem {
    fileprivate let bubbleImage: CGImage
    fileprivate let contentImage: CGImage
    fileprivate let leftLabel: TextViewLayout
    fileprivate let rightLabel: TextViewLayout
    fileprivate let leftBadgeColor: NSColor
    fileprivate let rightBadgeColor: NSColor
    fileprivate let rightHasBadgeBg: Bool
    fileprivate let timeLayout: TextViewLayout

    public init(_ initialSize: NSSize, stableId: AnyHashable, bubbleImage: CGImage, contentImage: CGImage, badgeType: AdminBadgeType) {
        self.bubbleImage = bubbleImage
        self.contentImage = contentImage
        self.leftBadgeColor = theme.colors.grayText

        let rightColor: NSColor
        let rightText: String
        switch badgeType {
        case .owner:
            rightColor = premiumGradient[1]
            rightText = " \(strings().userTagInfoOwnerTag) "
        case .admin:
            rightColor = theme.colors.greenUI.darker()
            rightText = " \(strings().userTagInfoAdminTag) "
        case .none:
            rightColor = theme.colors.greenUI.darker()
            rightText = " \(strings().userTagInfoAdminTag) "
        }
        self.rightBadgeColor = rightColor
        self.rightHasBadgeBg = true

        let leftAttr = NSMutableAttributedString()
        _ = leftAttr.append(string: strings().userTagInfoMemberTag, color: theme.colors.grayText, font: .normal(.short))
        self.leftLabel = TextViewLayout(leftAttr, maximumNumberOfLines: 1)
        self.leftLabel.measure(width: 140)

        let rightAttr = NSMutableAttributedString()
        _ = rightAttr.append(string: rightText, color: rightColor, font: .normal(.short))
        self.rightLabel = TextViewLayout(rightAttr, maximumNumberOfLines: 1)
        self.rightLabel.measure(width: 140)

        let timeAttr = NSMutableAttributedString()
        _ = timeAttr.append(string: "9:41", color: theme.colors.grayText, font: .normal(.short))
        self.timeLayout = TextViewLayout(timeAttr, maximumNumberOfLines: 1)
        self.timeLayout.measure(width: 140)

        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }

    public override func viewClass() -> AnyClass {
        return UserTagPreviewView.self
    }

    public override var height: CGFloat {
        return bubbleImage.backingSize.height + 20
    }

    public override var accessibilityLabel: String? {
        let left = leftLabel.attributedString.string.trimmingCharacters(in: .whitespaces)
        let right = rightLabel.attributedString.string.trimmingCharacters(in: .whitespaces)
        return left + ", " + right
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class UserTagPreviewView: GeneralRowView {
    private let leftBubble = ImageView()
    private let leftContent = ImageView()
    private let leftLabel = TextView()
    private let rightBubble = ImageView()
    private let rightContent = ImageView()
    private let rightLabel = TextView()
    private var rightBadgeBg: View?
    private let leftTime = TextView()
    private let rightTime = TextView()

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(leftBubble)
        addSubview(leftContent)
        addSubview(leftLabel)
        addSubview(rightBubble)
        addSubview(rightContent)
        addSubview(rightLabel)
        addSubview(leftTime)
        addSubview(rightTime)
        leftBubble.isAccessibilityDecorative = true
        leftContent.isAccessibilityDecorative = true
        rightBubble.isAccessibilityDecorative = true
        rightContent.isAccessibilityDecorative = true
        leftLabel.userInteractionEnabled = false
        leftLabel.isSelectable = false
        rightLabel.userInteractionEnabled = false
        rightLabel.isSelectable = false
        leftTime.userInteractionEnabled = false
        leftTime.isSelectable = false
        rightTime.userInteractionEnabled = false
        rightTime.isSelectable = false
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)

        guard let item = item as? UserTagPreviewItem else {
            return
        }

        leftBubble.image = item.bubbleImage
        leftBubble.sizeToFit()
        leftContent.image = item.contentImage
        leftContent.sizeToFit()
        rightBubble.image = item.bubbleImage
        rightBubble.sizeToFit()
        rightContent.image = item.contentImage
        rightContent.sizeToFit()
        leftLabel.update(item.leftLabel)
        rightLabel.update(item.rightLabel)
        leftTime.update(item.timeLayout)
        rightTime.update(item.timeLayout)

        if item.rightHasBadgeBg {
            if rightBadgeBg == nil {
                rightBadgeBg = View()
                addSubview(rightBadgeBg!, positioned: .below, relativeTo: rightLabel)
            }
            rightBadgeBg?.background = item.rightBadgeColor.withAlphaComponent(0.2)
        } else {
            rightBadgeBg?.removeFromSuperview()
            rightBadgeBg = nil
        }

        needsLayout = true
    }

    public override func layout() {
        super.layout()
        let bubbleSize = leftBubble.frame.size
        let spacing: CGFloat = 10
        let totalWidth = bubbleSize.width * 2 + spacing
        let startX = (frame.width - totalWidth) / 2
        let y: CGFloat = 10

        leftBubble.setFrameOrigin(NSMakePoint(startX, y))
        leftContent.setFrameOrigin(NSMakePoint(startX, y))

        let leftTagX = startX + bubbleSize.width - leftLabel.frame.width - 8
        leftLabel.setFrameOrigin(NSMakePoint(leftTagX, y + 8))

        let rightBubbleX = startX + bubbleSize.width + spacing
        rightBubble.setFrameOrigin(NSMakePoint(rightBubbleX, y))
        rightContent.setFrameOrigin(NSMakePoint(rightBubbleX, y))

        let rightTagX = rightBubbleX + bubbleSize.width - rightLabel.frame.width - 8
        rightLabel.setFrameOrigin(NSMakePoint(rightTagX, y + 8))

        leftTime.setFrameOrigin(NSMakePoint(startX + bubbleSize.width - leftTime.frame.width - 8, y + bubbleSize.height - leftTime.frame.height - 6))
        rightTime.setFrameOrigin(NSMakePoint(rightBubbleX + bubbleSize.width - rightTime.frame.width - 8, y + bubbleSize.height - rightTime.frame.height - 6))

        if let bg = rightBadgeBg {
            let padding = NSEdgeInsets(top: 1, left: 0, bottom: 1, right: 3)
            let bgFrame = NSMakeRect(rightTagX + padding.left, y + 8 - padding.top, rightLabel.frame.width - padding.left + padding.right, rightLabel.frame.height + padding.top + padding.bottom)
            bg.frame = bgFrame
            bg.layer?.cornerRadius = bgFrame.height / 2
        }
    }
}

// MARK: - Description Item

private final class UserTagDescriptionItem: GeneralRowItem {
    fileprivate let textLayout: TextViewLayout
    fileprivate let tagRange: NSRange
    fileprivate let tagBgColor: NSColor?

    public init(_ initialSize: NSSize, stableId: AnyHashable, attributedString: NSAttributedString, tagRange: NSRange, tagBgColor: NSColor?) {
        self.tagRange = tagRange
        self.tagBgColor = tagBgColor
        self.textLayout = TextViewLayout(attributedString, alignment: .center)
        self.textLayout.measure(width: initialSize.width - 40)
        super.init(initialSize, stableId: stableId, viewType: .legacy)
    }

    public override func viewClass() -> AnyClass {
        return UserTagDescriptionView.self
    }

    public override var height: CGFloat {
        return textLayout.layoutSize.height
    }

    public override var accessibilityLabel: String? {
        return textLayout.attributedString.string
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private final class UserTagDescriptionView: GeneralRowView {
    private let textView = TextView()
    private var badgeBgView: View?

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        textView.userInteractionEnabled = false
        textView.isSelectable = false
    }

    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override var backdorColor: NSColor {
        return .clear
    }

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)

        guard let item = item as? UserTagDescriptionItem else {
            return
        }

        textView.update(item.textLayout)

        if let bgColor = item.tagBgColor {
            if badgeBgView == nil {
                badgeBgView = View()
                addSubview(badgeBgView!, positioned: .below, relativeTo: textView)
            }
            badgeBgView?.background = bgColor.withAlphaComponent(0.2)
        } else {
            badgeBgView?.removeFromSuperview()
            badgeBgView = nil
        }

        needsLayout = true
    }

    public override func layout() {
        super.layout()
        textView.centerX(y: 0)

        if let bg = badgeBgView, let item = item as? UserTagDescriptionItem {
            let rects = item.textLayout.rects(item.tagRange)
            if let first = rects.first {
                let textOrigin = textView.frame.origin
                let padding = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 3)
                let bgFrame = NSMakeRect(textOrigin.x + first.0.origin.x + padding.left, textOrigin.y + first.0.origin.y - padding.top, first.0.width - padding.left + padding.right, first.0.height + padding.top + padding.bottom)
                bg.frame = bgFrame
                bg.layer?.cornerRadius = bgFrame.height / 2
            }
        }
    }
}

// MARK: - Entries

private func entries(_ state: State, arguments: Arguments, config: UserTagInfoConfiguration) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []

    var sectionId:Int32 = 0
    var index: Int32 = 0

    let headerColor: NSColor
    switch config.badgeType {
    case .owner:
        headerColor = premiumGradient[1]
    case .admin:
        headerColor = theme.colors.greenUI
    case .none:
        headerColor = theme.colors.grayIcon
    }

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_header, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return UserTagHeaderItem(initialSize, stableId: stableId, headerImage: TelegramThemeHooks.shared.image(.iconUserTag).precomposed(.white), circleColor: headerColor, dismiss: arguments.dismiss)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(5)))
    sectionId += 1

    let title: String
    switch config.badgeType {
    case .owner:
        title = strings().userTagInfoOwner
    case .admin:
        title = strings().userTagInfoAdmin
    case .none:
        title = strings().userTagInfoMember
    }

    entries.append(.desc(sectionId: sectionId, index: index, text: .plain("**\(title)**"), data: .init(color: theme.colors.text, detectBold: true, viewType: .plain(.single), fontSize: 18, centerViewAlignment: true, alignment: .center)))
    index += 1

    let descAttr = NSMutableAttributedString()
    let tagBadgeColor: NSColor
    let tagBgColor: NSColor?
    switch config.badgeType {
    case .owner:
        tagBadgeColor = premiumGradient[1]
        tagBgColor = premiumGradient[1]
        _ = descAttr.append(string: strings().userTagInfoThisRedTag, color: theme.colors.grayText, font: .normal(.text))
    case .admin:
        tagBadgeColor = theme.colors.greenUI.darker()
        tagBgColor = theme.colors.greenUI
        _ = descAttr.append(string: strings().userTagInfoThisGreenTag, color: theme.colors.grayText, font: .normal(.text))
    case .none:
        tagBadgeColor = theme.colors.grayText
        tagBgColor = nil
        _ = descAttr.append(string: strings().userTagInfoTheTag, color: theme.colors.grayText, font: .normal(.text))
    }
    let tagRange = NSMakeRange(descAttr.length, (" " + config.tag).count)
    _ = descAttr.append(string: " " + config.tag, color: tagBadgeColor, font: .normal(.short))
    switch config.badgeType {
    case .owner:
        _ = descAttr.append(string: strings().userTagInfoOwnerTagDesc(config.authorName, config.groupName), color: theme.colors.grayText, font: .normal(.text))
    case .admin:
        _ = descAttr.append(string: strings().userTagInfoAdminTagDesc(config.authorName, config.groupName), color: theme.colors.grayText, font: .normal(.text))
    case .none:
        _ = descAttr.append(string: strings().userTagInfoCustomTagDesc(config.authorName, config.groupName), color: theme.colors.grayText, font: .normal(.text))
    }
    descAttr.detectBoldColorInString(with: .medium(.text))

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_description, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return UserTagDescriptionItem(initialSize, stableId: stableId, attributedString: descAttr, tagRange: tagRange, tagBgColor: tagBgColor)
    }))
    index += 1

    entries.append(.sectionId(sectionId, type: .customModern(10)))
    sectionId += 1

    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_preview, equatable: .init(state), comparable: nil, item: { initialSize, stableId in
        return UserTagPreviewItem(initialSize, stableId: stableId, bubbleImage: TelegramThemeHooks.shared.image(.iconUserTagMessageBubble).precomposed(theme.colors.grayBackground), contentImage: TelegramThemeHooks.shared.image(.iconUserTagMessageContent).precomposed(), badgeType: config.badgeType)
    }))
    index += 1

        if config.canEditRank {

        entries.append(.sectionId(sectionId, type: .customModern(10)))
        sectionId += 1

        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().userTagInfoSetOwnTag), data: .init(color: theme.colors.grayText, viewType: .plain(.single), centerViewAlignment: true, alignment: .center)))
        index += 1
    }

    entries.append(.sectionId(sectionId, type: .normal))
    sectionId += 1

    return entries
}

public struct UserTagInfoConfiguration {
    public let tag: String
    public let authorName: String
    public let groupName: String
    public let badgeType: AdminBadgeType
    public let canEditRank: Bool

    public init(tag: String, authorName: String, groupName: String, badgeType: AdminBadgeType, canEditRank: Bool) {
        self.tag = tag
        self.authorName = authorName
        self.groupName = groupName
        self.badgeType = badgeType
        self.canEditRank = canEditRank
    }
}

public func UserTagInfoModalController(context: any AccountContextProtocol, configuration: UserTagInfoConfiguration, analyticsContext: AnalyticsContext? = nil) -> InputDataModalController {
    let origin = Analytics.shared.captureContext(engine: context.engine, peerId: context.peerId, inherited: analyticsContext ?? Analytics.shared.unresolvedContext())
    let presentation = origin.beginPresentation()
    defer { presentation.end() }

    let actionsDisposable = DisposableSet()

    let initialState = State()

    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    _ = updateState

    var close:(()->Void)? = nil

    let arguments = Arguments(context: context, dismiss: {
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        close?()
    })

    let signal = origin.preservingPresentation(statePromise.get() |> deliverOnPrepareQueue) |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments, config: configuration))
    }

    let controller = InputDataController(dataSignal: signal, title: "")
    controller.analyticsContext = origin
    controller.analyticsScreen = .chatMemberTagInfo

    controller.validateData = { _ in
        let presentation = origin.beginPresentation()
        defer { presentation.end() }
        close?()
        return .none
    }

    controller.onDeinit = {
        actionsDisposable.dispose()
    }

    let modalInteractions = ModalInteractions(acceptTitle: strings().userTagInfoUnderstood, accept: { [weak controller] in
        _ = controller?.returnKeyAction()
    }, singleButton: true)

    let modalController = InputDataModalController(controller, modalInteractions: modalInteractions)
    modalController.analyticsContext = origin
    modalController._hasBorder = false

    close = { [weak modalController] in
        modalController?.modal?.close()
    }

    return modalController
}
