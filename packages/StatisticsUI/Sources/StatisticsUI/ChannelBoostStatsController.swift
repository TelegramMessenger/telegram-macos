import Foundation
import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramContext
import TelegramUtils
import TelegramTheme
import TelegramIconsTheme
import ColorPalette
import Localization
import LocalAnimations
import GeneralRows
import InputDataUI
import BoostUI
import InviteLinksUI
import AvatarUI
import AppAnalytics

private func actionItems(state: State, width: CGFloat, arguments: Arguments, theme: TelegramPresentationTheme) -> [ActionItem] {
    var items: [ActionItem] = []

    var rowItemsCount: Int = 1

    let actionItemInset = ActionItem.actionItemInsetWidth(isColorfull: true)
    while width - (ActionItem.actionItemWidth + actionItemInset) > ((ActionItem.actionItemWidth * CGFloat(rowItemsCount)) + (CGFloat(rowItemsCount - 1) * actionItemInset)) {
        rowItemsCount += 1
    }
    rowItemsCount = min(rowItemsCount, 4)
    
    
    
    if state.isGroup {
        items.append(.init(text: strings().statsBoostsActionBoost, color: theme.colors.accent, image: theme.icons.stats_boost_boost, animation: .menu_boost_plus, action: {
            arguments.boost(false)
        }))
        
        items.append(.init(text: strings().statsBoostsActionGiveaway, color: theme.colors.accent, image: theme.icons.stats_boost_giveaway, animation: .menu_gift, action: {
            arguments.giveaway(nil)
        }))
        
        items.append(.init(text: strings().statsBoostsActionInfo, color: theme.colors.accent, image: theme.icons.stats_boost_info, animation: .menu_show_info, action: {
            arguments.boost(true)
        }))
    }
   
    if items.count > rowItemsCount {
        var subItems:[SubActionItem] = []
        while items.count > rowItemsCount - 1 {
            let item = items.removeLast()
            subItems.insert(SubActionItem(text: item.text, animation: item.animation, destruct: item.destruct, action: item.action), at: 0)
        }
        if !subItems.isEmpty {
            items.append(ActionItem(text: strings().peerInfoActionMore, color: theme.colors.accent, image: theme.icons.profile_more, animation: .menu_plus, action: { }, subItems: subItems))
        }
    }
    
    return items
}

private func generateBoostReason(_ text: String, color: NSColor = theme.colors.accent) -> CGImage {
    let attr = NSMutableAttributedString()
    
    _ = attr.append(string: text, color: color, font: .medium(.text))
    let textNode = TextNode.layoutText(attr, nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, 20), nil, false, .center)
    
    var size = textNode.0.size
    size.width += 16
    size.height += 8
    return generateImage(size, rotatedContext: { size, ctx in
        let rect = NSMakeRect(0, 0, size.width, size.height)
        ctx.clear(rect)
        ctx.round(rect.size, size.height / 2)
        ctx.setFillColor(color.withAlphaComponent(0.1).cgColor)
        ctx.fill(rect)
        textNode.1.draw(rect.focus(textNode.0.size), in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
    })!
}
private let light = TelegramThemeHooks.shared.image(.iconBoosterMultiplier).precomposed(.white, flipVertical: true)
private func generateBoostMultiply(_ text: String, color: NSColor = premiumGradient[1]) -> CGImage {
    let attr = NSMutableAttributedString()
    
    _ = attr.append(string: text, color: .white, font: .avatar(.small))
    let textNode = TextNode.layoutText(attr, nil, 1, .end, NSMakeSize(.greatestFiniteMagnitude, 20), nil, false, .center)
    
    //x
    var size = textNode.0.size
    size.width += light.backingSize.width + 8
    size.height += 4
    return generateImage(size, rotatedContext: { size, ctx in
        let rect = NSMakeRect(0, 0, size.width, size.height)
        ctx.clear(rect)
        ctx.round(rect.size, size.height / 2)
        ctx.setFillColor(color.cgColor)
        ctx.fill(rect)
        
        var imageRect = rect.focus(light.backingSize)
        imageRect.origin.x = 3
        ctx.draw(light, in: imageRect)
        
        var textRect = rect.focus(textNode.0.size)
        textRect.origin.x = imageRect.maxX + 2
        textRect.origin.y += 0.5
        textNode.1.draw(textRect, in: ctx, backingScaleFactor: System.backingScale, backgroundColor: .clear)
    })!
}

private final class BoosterRowItem : GeneralRowItem {
    fileprivate let name: TextViewLayout
    fileprivate let status: TextViewLayout
    fileprivate let reason: CGImage?
    fileprivate let multiply: CGImage
    fileprivate let boost: ChannelBoostersContext.State.Boost
    fileprivate let context: any AccountContextProtocol
    fileprivate let empty: EmptyAvatartType?
    init(_ initialSize: NSSize, stableId: AnyHashable, context: any AccountContextProtocol, boost: ChannelBoostersContext.State.Boost, viewType: GeneralViewType, action: @escaping()->Void) {
        self.context = context
        self.boost = boost
        
        let durationMonths = Int32(round(Float(boost.expires - boost.date) / (86400.0 * 30.0)))
        
        if boost.peer == nil {
            if boost.stars == nil {
                let color: (top: NSColor, bottom: NSColor)
                if durationMonths > 11 {
                    color = theme.colors.peerColors(0)
                } else if durationMonths > 5 {
                    color = theme.colors.peerColors(5)
                } else {
                    color = theme.colors.peerColors(3)
                }
                self.empty = .icon(colors: color, icon: theme.icons.chat_filter_non_contacts_avatar, iconSize: NSMakeSize(24, 24), cornerRadius: nil)
            } else {
                self.empty = .icon(colors: (top: .clear, bottom: .clear), icon: TelegramThemeHooks.shared.image(.iconGiveawayStars).precomposed(), iconSize: NSMakeSize(37, 37), cornerRadius: nil)
            }
        } else {
            self.empty = nil
        }

        
        let nameString: String
        var expiresString: String = strings().statsBoostsExpiresOn(stringForFullDate(timestamp: boost.expires))
        if let peer = boost.peer {
            nameString = peer._asPeer().displayTitle
        } else {
            if let stars = boost.stars {
                nameString = strings().channelBoostBoosterStarsOther(Int(stars))
            } else if boost.flags.contains(.isUnclaimed) {
                nameString = strings().channelBoostBoosterUnclaimed
            } else if boost.flags.contains(.isGiveaway) {
                nameString = strings().channelBoostBoosterToBeDistributed
            } else {
                nameString = "Unknown"
            }
            let durationString = strings().channelBoostBoosterDuration(Int(durationMonths))
            if boost.stars == nil {
                expiresString = "\(durationString) • \(stringForFullDate(timestamp: boost.expires))"
            }
        }
       
        self.name = .init(.initialize(string: nameString, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1)
        self.status = .init(.initialize(string: expiresString, color: theme.colors.grayText, font: .normal(.text)), maximumNumberOfLines: 1)
        
        var label: String?
        if boost.flags.contains(.isGiveaway) {
            label = strings().giveawayBoosterReasonGiveaway
        } else if boost.flags.contains(.isGift) {
            label = strings().giveawayBoosterReasonGift
        }

        if let label = label {
            self.reason = generateBoostReason(label)
        } else {
            self.reason = nil
        }
        self.multiply = generateBoostMultiply("\(boost.multiplier)")
        super.init(initialSize, height: 50, stableId: stableId, viewType: viewType, action: action)
    }
    
    override func makeSize(_ width: CGFloat, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        
        let text_width: CGFloat = blockWidth - (reason?.backingSize.width ?? 0) - 20 - 10 - 10 - 30
        
        self.name.measure(width: text_width)
        self.status.measure(width: text_width)
        
        return true
    }
    
    override var accessibilityLabel: String? {
        return name.attributedString.string
    }

    override var accessibilityValue: String? {
        var parts: [String] = ["x\(boost.multiplier)"]
        if boost.flags.contains(.isGiveaway) {
            parts.append(strings().giveawayBoosterReasonGiveaway)
        } else if boost.flags.contains(.isGift) {
            parts.append(strings().giveawayBoosterReasonGift)
        }
        parts.append(status.attributedString.string)
        return parts.joined(separator: ", ")
    }

    override var accessibilityRole: NSAccessibility.Role? {
        return .button
    }

    override var accessibilityIncludesChildren: Bool {
        return false
    }

    override func accessibilityPerformPress() -> Bool {
        action()
        return true
    }

    override func viewClass() -> AnyClass {
        return BoosterRowItemView.self
    }
}

private final class BoosterRowItemView : GeneralContainableRowView {
    private let nameView = TextView()
    private let statusView = TextView()
    private let multiplierView = ImageView()
    private let reasonView = ImageView()
    private let avatar = AvatarControl(font: .avatar(13))
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(nameView)
        addSubview(statusView)
        addSubview(multiplierView)
        addSubview(reasonView)
        multiplierView.isAccessibilityDecorative = true
        reasonView.isAccessibilityDecorative = true
        
        avatar.userInteractionEnabled = false
        self.addSubview(self.avatar)
        self.avatar.setFrameSize(NSMakeSize(36, 36))
        
        nameView.userInteractionEnabled = false
        nameView.isSelectable = false
        
        statusView.userInteractionEnabled = false
        statusView.isSelectable = false
        
        containerView.set(handler: { [weak self] _ in
            (self?.item as? GeneralRowItem)?.action()
        }, for: .Click)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? BoosterRowItem else {
            return
        }
        self.nameView.update(item.name)
        self.statusView.update(item.status)
        if let empty = item.empty {
            self.avatar.setSignal(generateEmptyPhoto(NSMakeSize(36, 36), type: empty, bubble: false) |> map { ($0, false) })
        } else {
            self.avatar.setPeer(account: item.context.account, peer: item.boost.peer?._asPeer())
        }

        self.reasonView.image = item.reason
        self.reasonView.sizeToFit()
        self.reasonView.isHidden = item.reason == nil
        
        self.multiplierView.image = item.multiply
        self.multiplierView.sizeToFit()
        needsLayout = true
    }
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        transition.updateFrame(view: avatar, frame: CGRect(origin: NSMakePoint(10, 7), size: avatar.frame.size))
        transition.updateFrame(view: nameView, frame: CGRect(origin: NSMakePoint(avatar.frame.maxX + 10, 7), size: nameView.frame.size))
        transition.updateFrame(view: multiplierView, frame: CGRect(origin: NSMakePoint(nameView.frame.maxX + 5, 7), size: multiplierView.frame.size))

        
        transition.updateFrame(view: statusView, frame: CGRect(origin: NSMakePoint(avatar.frame.maxX + 10, avatar.frame.maxY - statusView.frame.height), size: statusView.frame.size))
        
        transition.updateFrame(view: reasonView, frame: reasonView.centerFrameY(x: containerView.frame.width - reasonView.frame.width - 10))

    }
    
    override var additionBorderInset: CGFloat {
        return 30 + 10
    }
    
}

private final class BoostRowItem : TableRowItem {
    fileprivate let context: any AccountContextProtocol
    private let _stableId: AnyHashable
    fileprivate let state: State
    fileprivate var items: [ActionItem] = []
    fileprivate let textLayout: TextViewLayout?
    fileprivate let arguments: Arguments
    init(_ initialSize: NSSize, stableId: AnyHashable, state: State, context: any AccountContextProtocol, arguments: Arguments) {
        self.context = context
        self.state = state
        self._stableId = stableId
        self.arguments = arguments
        
        if state.isGroup {
            let attr: NSAttributedString = .initialize(string: strings().statsBoostsGroupInfo, color: theme.colors.text, font: .normal(.text)).detectBold(with: .medium(.text))
            self.textLayout = .init(attr, alignment: .center)
        } else {
            self.textLayout = nil
        }
        
        super.init(initialSize)
        
        _ = makeSize(initialSize.width)
    }
    
    override func makeSize(_ width: CGFloat = CGFloat.greatestFiniteMagnitude, oldWidth: CGFloat = 0) -> Bool {
        _ = super.makeSize(width, oldWidth: oldWidth)
        self.items = actionItems(state: state, width: width, arguments: arguments, theme: theme)
        
        textLayout?.measure(width: blockWidth)
        return true
    }
    
    var blockWidth: CGFloat {
        return min(600, self.width - 40)
    }
    
    override var stableId: AnyHashable {
        return _stableId
    }
    
    
    override var height: CGFloat {
        var height: CGFloat = 100
        if !items.isEmpty {
            let maxActionSize: NSSize = items.max(by: { $0.size.height < $1.size.height })!.size
            height += maxActionSize.height
        }
        if let textLayout {
            height += textLayout.layoutSize.height + 20
        }
        return height
    }
    
    override var accessibilityLabel: String? {
        return strings().boostBadgeLevel(state.currentLevel)
    }

    override func viewClass() -> AnyClass {
        return BoostRowItemView.self
    }
}

private final class BoostRowItemView : TableRowView {
    private let lineView = LineView(frame: .zero)
    private let top = BoostCounterView(frame: .zero)
    private let actionsView = View()
    
    private var textView: TextView?
    
    private class LineView: View {
        
        private let currentLevel = TextView()
        private let nextLevel = TextView()

        private let nextLevel_background = View()
        private let currentLevel_background = PremiumGradientView(frame: .zero)
        
        private var state: State?
        
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(nextLevel_background)
            addSubview(currentLevel_background)
            addSubview(nextLevel)
            addSubview(currentLevel)
            nextLevel.userInteractionEnabled = false
            currentLevel.userInteractionEnabled = false
            
            nextLevel.isSelectable = false
            currentLevel.isSelectable = false
        }
        
        func update(_ state: State, context: any AccountContextProtocol, transition: ContainedViewLayoutTransition) {
            
            self.state = state
            
            let width = frame.width * state.percentToNext

            
            var normalCountLayout = TextViewLayout(.initialize(string:  strings().boostBadgeLevel(state.currentLevel), color: theme.colors.text, font: .medium(13)))
            normalCountLayout.measure(width: .greatestFiniteMagnitude)
            
            if width >= 10 + normalCountLayout.layoutSize.width {
                normalCountLayout = TextViewLayout(.initialize(string: normalCountLayout.attributedString.string, color: .white, font: .medium(13)))
                normalCountLayout.measure(width: .greatestFiniteMagnitude)
            }

            currentLevel.update(normalCountLayout)

            var premiumCountLayout = TextViewLayout(.initialize(string: strings().boostBadgeLevel(state.currentLevel + 1), color: theme.colors.text, font: .medium(13)))
            premiumCountLayout.measure(width: .greatestFiniteMagnitude)
            
            if width >= frame.width - 10 {
                premiumCountLayout = TextViewLayout(.initialize(string: premiumCountLayout.attributedString.string, color: .white, font: .medium(13)))
                premiumCountLayout.measure(width: .greatestFiniteMagnitude)
            }

            nextLevel.update(premiumCountLayout)
            
            nextLevel_background.backgroundColor = theme.colors.background
            
            self.updateLayout(size: self.frame.size, transition: transition)
        }
        
        func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
            guard let state = self.state else {
                return
            }
            
            let width = frame.width * state.percentToNext

            transition.updateFrame(view: currentLevel, frame: currentLevel.centerFrameY(x: 10))
            transition.updateFrame(view: nextLevel, frame: nextLevel.centerFrameY(x: bounds.width - 10 - nextLevel.frame.width))

            transition.updateFrame(view: nextLevel_background, frame: NSMakeRect(width, 0, size.width - width, frame.height))
            transition.updateFrame(view: currentLevel_background, frame: NSMakeRect(0, 0, width, frame.height))
            
        }
        
        override func layout() {
            super.layout()
            self.updateLayout(size: self.frame.size, transition: .immediate)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    private func _actionItemWidth(_ items: [ActionItem]) -> CGFloat {
        guard let item = item as? BoostRowItem else {
            return 0
        }
        let actionItemInset = ActionItem.actionItemInsetWidth(isColorfull: true)
        let width = (item.blockWidth - (actionItemInset * CGFloat(items.count - 1)))

        return max(ActionItem.actionItemWidth, min(150, width / CGFloat(items.count)))
    }
    
    private func layoutActionItems(_ items: [ActionItem], animated: Bool) {
        
        if !items.isEmpty {
            let maxActionSize: NSSize = items.max(by: { $0.size.height < $1.size.height })!.size
            
            
            while actionsView.subviews.count > items.count {
                actionsView.subviews.removeLast()
            }
            while actionsView.subviews.count < items.count {
                actionsView.addSubview(ActionButton(frame: .zero))
            }
            
            let inset: CGFloat = 0

            let actionItemWidth = _actionItemWidth(items)
            let actionItemInset = ActionItem.actionItemInsetWidth(isColorfull: true)

            actionsView.change(size: NSMakeSize(actionItemWidth * CGFloat(items.count) + CGFloat(items.count - 1) * actionItemInset, maxActionSize.height), animated: animated)

            var x: CGFloat = inset

            for (i, item) in items.enumerated() {
                let view = actionsView.subviews[i] as! ActionButton
                view.updateAndLayout(item: item, bgColor: theme.colors.background, useGlass: true)
                view.setFrameSize(NSMakeSize(actionItemWidth, maxActionSize.height))
                view.change(pos: NSMakePoint(x, 0), animated: false)
                x += actionItemWidth + actionItemInset
            }
            
        } else {
            actionsView.removeAllSubviews()
        }
    }
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.addSubview(top)
        self.addSubview(lineView)
        self.addSubview(actionsView)
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        guard let item = item as? BoostRowItem else {
            return
        }
        
        lineView.setFrameSize(NSMakeSize(item.blockWidth, 30))
        lineView.layer?.cornerRadius = 10
        lineView.update(item.state, context: item.context, transition: .immediate)
        
        let size = top.update(boosts: item.state.currentBoosts, context: item.context, transition: .immediate)
        top.setFrameSize(size)
        
        if let textLayout = item.textLayout {
            let current: TextView
            if let view = self.textView {
                current = view
            } else {
                current = TextView()
                current.userInteractionEnabled = false
                current.isSelectable = false
                self.textView = current
                addSubview(current)
            }
            current.update(textLayout)
        } else if let view = self.textView {
            performSubviewRemoval(view, animated: animated)
            self.textView = nil
        }
        
        needsLayout = true
    }
    
    
    override func updateLayout(size: NSSize, transition: ContainedViewLayoutTransition) {
        super.updateLayout(size: size, transition: transition)
        
        guard let item = self.item as? BoostRowItem else {
            return
        }
        
        layoutActionItems(item.items, animated: transition.isAnimated)
    
        transition.updateFrame(view: lineView, frame: lineView.centerFrameX(y: top.frame.height + 10))
        

        let topPoint = NSMakePoint(max(min(lineView.frame.minX + lineView.frame.width * item.state.percentToNext - top.frame.width / 2, size.width - 20 - top.frame.width), lineView.frame.minX), lineView.frame.minY - top.frame.height - 10)
        
        transition.updateFrame(view: top, frame: CGRect(origin: topPoint, size: top.frame.size))

        if let textView = textView {
            transition.updateFrame(view: textView, frame: textView.centerFrameX(y: lineView.frame.maxY + 10))
        }
        
        transition.updateFrame(view: actionsView, frame: actionsView.centerFrameX(y: size.height - actionsView.frame.height))
    
    }
}


private final class Arguments {
    let context: any AccountContextProtocol
    let openPeerInfo:(PeerId)->Void
    let shareLink:(String)->Void
    let copyLink:(String)->Void
    let showMore:()->Void
    let giveaway:(PrepaidGiveaway?)->Void
    let openSlug:(String)->Void
    let boost:(Bool)->Void
    init(context: any AccountContextProtocol, openPeerInfo:@escaping(PeerId)->Void, shareLink: @escaping(String)->Void, copyLink: @escaping(String)->Void, showMore:@escaping()->Void, giveaway:@escaping(PrepaidGiveaway?)->Void, openSlug:@escaping(String)->Void, boost:@escaping(Bool)->Void) {
        self.context = context
        self.shareLink = shareLink
        self.copyLink = copyLink
        self.openPeerInfo = openPeerInfo
        self.showMore = showMore
        self.giveaway = giveaway
        self.openSlug = openSlug
        self.boost = boost
    }
}



private struct State : Equatable {
    var peer: PeerEquatable?
    var boostStatus: ChannelBoostStatus?
    var booster: ChannelBoostersContext.State?
    var myStatus: MyBoostStatus?
    var revealed: Bool = false
    var isGroup: Bool
    
    func link(_ context: any AccountContextProtocol) -> String {
        if let peer = peer {
            if let address = peer.peer.addressName {
                return context.meUrlPrefix + "\(address)?boost"
            } else {
                return context.meUrlPrefix + "c/\(peer.peer.id.id._internalGetInt64Value())?boost"

            }
        } else {
            return ""
        }
    }
    
    var percentToNext: CGFloat {
        if let status = self.boostStatus {
            if let nextLevelBoosts = status.nextLevelBoosts {
                return CGFloat(status.boosts - status.currentLevelBoosts) / CGFloat(nextLevelBoosts - status.currentLevelBoosts)
            } else {
                return 1.0
            }
        } else {
            return 0.0
        }
        
    }
    
    var currentLevel: Int {
        if let stats = self.boostStatus {
            return stats.level
        }
        return 0
    }
    var currentBoosts: Int {
        if let stats = self.boostStatus {
            return stats.boosts
        }
        return 0
    }
}

private func _id_boost(_ id: String) -> InputDataIdentifier {
    return .init("_id_peer_\(id)")
}
private func _id_prepaid(_ subject: PrepaidGiveaway) ->InputDataIdentifier {
    return .init("_id_prepaid_\(subject.id)")
}
private let _id_loading = InputDataIdentifier("_id_loading")
private let _id_empty_boosters = InputDataIdentifier("_id_empty_boosters")
private let _id_load_more = InputDataIdentifier("_id_load_more")

private let _id_giveaway = InputDataIdentifier("_id_load_more")

private func entries(_ state: State, arguments: Arguments) -> [InputDataEntry] {
    var entries:[InputDataEntry] = []
    
    var sectionId:Int32 = 0
    var index: Int32 = 0
    
    if let boostStatus = state.boostStatus {
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("level"), equatable: InputDataEquatable(state), comparable: nil, item: { initialSize, stableId in
            return BoostRowItem(initialSize, stableId: stableId, state: state, context: arguments.context, arguments: arguments)
        }))
      
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().channelStatsOverview), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        
        var overviewItems:[ChannelOverviewItem] = []
        
        overviewItems.append(ChannelOverviewItem(title: strings().statsBoostsLevel, value: .initialize(string: "\(boostStatus.level)", color: theme.colors.text, font: .medium(.text))))
        
        var premiumSubscribers: Double = 0.0
        if let premiumAudience = boostStatus.premiumAudience, premiumAudience.total > 0 {
            premiumSubscribers = premiumAudience.value / premiumAudience.total
        }
                        
        let audience: NSMutableAttributedString = NSMutableAttributedString()
        audience.append(string: "~\(Int(boostStatus.premiumAudience?.value ?? 0))", color: theme.colors.text, font: .medium(.text))
        audience.append(string: " ", color: theme.colors.text, font: .medium(.text))
        audience.append(string: String(format: "%.02f%%", premiumSubscribers * 100.0), color: theme.colors.grayText, font: .normal(.short))


        overviewItems.append(ChannelOverviewItem(title: strings().statsBoostsPremiumSubscribers, value: audience))
        
        overviewItems.append(ChannelOverviewItem(title: strings().statsBoostsExistingBoosts, value: .initialize(string: boostStatus.boosts.formattedWithSeparator, color: theme.colors.text, font: .medium(.text))))

        if let nextLevelBoosts = boostStatus.nextLevelBoosts {
            overviewItems.append(ChannelOverviewItem(title: strings().statsBoostsBoostsToLevelUp, value: .initialize(string: ("\(nextLevelBoosts - boostStatus.currentLevelBoosts)"), color: theme.colors.text, font: .medium(.text))))
        }

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("overview"), equatable: InputDataEquatable(overviewItems), comparable: nil, item: { initialSize, stableId in
            return ChannelOverviewStatsRowItem(initialSize, stableId: stableId, items: overviewItems, viewType: .singleItem)
        }))
                
        let prepaidList:[PrepaidGiveaway] = state.boostStatus?.prepaidGiveaways ?? []
        
        
        
        if !prepaidList.isEmpty {
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().channelBoostsStatsPrepaidTitle), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1
            
            for (i, prepaid) in prepaidList.enumerated() {
                let title: String
                let info: String
                let icon: CGImage
                let countIcon: CGImage
                let viewType = bestGeneralViewType(prepaidList, for: i)
                switch prepaid.prize {
                case let .premium(months):
                    countIcon = generalPrepaidGiveawayIcon(theme.colors.accent, count: .initialize(string: "\(prepaid.quantity)", color: theme.colors.accent, font: .avatar(.text)))
                    icon = generateGiveawayTypeImage(TelegramThemeHooks.shared.image(.iconGiveawayRandom), colorIndex: Int(months) % 7)
                    title = strings().giveawayTypePrepaidTitle(Int(prepaid.quantity))
                    info = strings().giveawayTypePrepaidDesc(Int(months))
                case let .stars(stars, boosts):
                    countIcon = generalPrepaidGiveawayIcon(theme.colors.accent, count: .initialize(string: "\(boosts)", color: theme.colors.accent, font: .avatar(.text)))
                    icon = TelegramThemeHooks.shared.image(.iconGiveawayStars).precomposed(flipVertical: true)
                    title = strings().giveawayStarsPrepaidTitle(Int(stars))
                    info = strings().giveawayStarsPrepaidDescOther(Int(prepaid.quantity))
                }
                
                entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_prepaid(prepaid), data: .init(name: title, color: theme.colors.text, icon: icon, type: .imageContext(countIcon, ""), viewType: viewType, description: info, descTextColor: theme.colors.grayText, action: {
                    arguments.giveaway(prepaid)
                })))
            }
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().channelBoostsStatsPrepaidInfo), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1

        }


        if let boosters = state.booster {
           
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            
            
            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().statsBoostsBoostersOther(Int(boosters.count))), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
            index += 1

            let boosts = boosters.boosts
            
            if !boosts.isEmpty {
                
                struct Tuple: Equatable {
                    let booster: ChannelBoostersContext.State.Boost
                    let viewType: GeneralViewType
                }
                
                var items: [Tuple] = []
                for (i, booster) in boosts.enumerated() {
                    var viewType: GeneralViewType = bestGeneralViewType(boosters.boosts, for: i)
                    if i == boosts.count - 1, (boosters.canLoadMore && boosters.count < boosters.boosts.count) || boosters.isLoadingMore {
                        viewType = .innerItem
                    }
                    items.append(.init(booster: booster, viewType: viewType))
                }
                                
                for item in items {
                    let stableId = _id_boost(item.booster.id)
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: stableId, equatable: InputDataEquatable(item), comparable: nil, item: { initialSize, stableId in
                        return BoosterRowItem(initialSize, stableId: stableId, context: arguments.context, boost: item.booster, viewType: item.viewType, action: {
                            if let slug = item.booster.slug {
                                arguments.openSlug(slug)
                            } else if let peerId = item.booster.peer?.id {
                                arguments.openPeerInfo(peerId)
                            }
                        })
                    }))
                }
                
                if boosters.canLoadMore && boosters.count > boosters.count {
                    entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_load_more, data: .init(name: strings().statsBoostsShowMore, color: theme.colors.accent, viewType: .lastItem, action: arguments.showMore)))
                } else if boosters.isLoadingMore {
                    entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading, equatable: .init(boosters), comparable: nil, item: { initialSize, stableId in
                        return GeneralLoadingRowItem(initialSize, stableId: stableId, viewType: .lastItem)
                    }))
                }
                
                entries.append(.desc(sectionId: sectionId, index: index, text: .plain(state.isGroup ? strings().statsBoostsBoostersInfoGroup : strings().statsBoostsBoostersInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
                index += 1
            } else {
                entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_empty_boosters, equatable: nil, comparable: nil, item: { initialSize, stableId in
                    return GeneralBlockTextRowItem(initialSize, stableId: stableId, viewType: .singleItem, text: state.isGroup ? strings().statsBoostsNoBoostersYetGroup : strings().statsBoostsNoBoostersYet, font: .normal(.text), color: theme.colors.grayText)
                }))
            }

        }
        
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().statsBoostsLinkHeader), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1

        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("link"), equatable: InputDataEquatable(state.link(arguments.context)), comparable: nil, item: { initialSize, stableId in
            return ExportedInvitationRowItem(initialSize, stableId: stableId, context: arguments.context, exportedLink: _ExportedInvitation.initialize(.link(link: state.link(arguments.context), title: nil, isPermanent: true, requestApproval: false, isRevoked: false, adminId: arguments.context.peerId, date: 0, startDate: 0, expireDate: nil, usageLimit: nil, count: nil, requestedCount: nil, pricing: nil)), lastPeers: [], viewType: .singleItem, mode: .normal(hasUsage: false), menuItems: {
                
                var items:[ContextMenuItem] = []
                
                items.append(ContextMenuItem(strings().contextCopy, handler: {
                    arguments.copyLink(state.link(arguments.context))
                }, itemImage: MenuAnimation.menu_copy.value))
                
                return .single(items)
            }, share: arguments.shareLink, copyLink: arguments.copyLink)
        }))
        
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(state.isGroup ? strings().statsBoostsLinkInfoGroup : strings().statsBoostsLinkInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
        index += 1
                
        // entries
        
               
        let boosts_available = arguments.context.appConfiguration.getBoolValue("giveaway_gifts_purchase_available", orElse: false)

        if boosts_available {
            entries.append(.sectionId(sectionId, type: .normal))
            sectionId += 1
            
            entries.append(.general(sectionId: sectionId, index: index, value: .none, error: nil, identifier: _id_giveaway, data: .init(name: strings().channelBoostsStatsGetBoostsViaGifts, color: theme.colors.accent, icon: TelegramThemeHooks.shared.image(.iconBoostGiveaway).precomposed(theme.colors.accent, flipVertical: true), viewType: .singleItem, action: {
                arguments.giveaway(nil)
            })))

            entries.append(.desc(sectionId: sectionId, index: index, text: .plain(state.isGroup ? strings().channelBoostsStatsGetBoostsViaGiftsInfoGroup : strings().channelBoostsStatsGetBoostsViaGiftsInfo), data: .init(color: theme.colors.listGrayText, viewType: .textBottomItem)))
            index += 1
        }
       

        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        
    } else if statisticsChartStyle.usesGlass {
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("level"), equatable: InputDataEquatable("skeleton"), comparable: nil, item: { initialSize, stableId in
            return StatisticSkeletonListRowItem(initialSize, stableId: stableId, style: .level, viewType: .singleItem, heightProvider: { width in
                return BoostRowItem(NSMakeSize(width, initialSize.height), stableId: stableId, state: state, context: arguments.context, arguments: arguments).height
            })
        }))
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        entries.append(.desc(sectionId: sectionId, index: index, text: .plain(strings().channelStatsOverview), data: .init(color: theme.colors.listGrayText, viewType: .textTopItem)))
        index += 1
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: InputDataIdentifier("overview"), equatable: InputDataEquatable("skeleton"), comparable: nil, item: { initialSize, stableId in
            return ChannelOverviewStatsRowItem(initialSize, stableId: stableId, skeletonCount: 4, viewType: .singleItem)
        }))
        index += 1
        entries.append(.sectionId(sectionId, type: .normal))
        sectionId += 1
        entries.append(contentsOf: statisticsListSkeletonEntries(prefix: "booster", count: 3, sectionId: sectionId, index: &index))
    } else {
        entries.append(.custom(sectionId: sectionId, index: index, value: .none, identifier: _id_loading, equatable: nil, comparable: nil, item: { initialSize, stableId in
            return SearchEmptyRowItem(initialSize, stableId: stableId, isLoading: true)
        }))
    }
    
    
    return entries
}

public func ChannelBoostStatsController(context: any AccountContextProtocol, peerId: PeerId, isGroup: Bool = false) -> InputDataController {
    
    let actionsDisposable = DisposableSet()
    
    let initialState = State(isGroup: isGroup)
    
    let statePromise = ValuePromise(initialState, ignoreRepeated: true)
    let stateValue = Atomic(value: initialState)
    let updateState: ((State) -> State) -> Void = { f in
        statePromise.set(stateValue.modify (f))
    }
    
    let boostData = context.engine.peers.getChannelBoostStatus(peerId: peerId)
    let boostersContext = ChannelBoostersContext(account: context.account, peerId: peerId, gift: false)
    
    
    actionsDisposable.add(combineLatest(context.account.postbox.loadedPeerWithId(peerId), boostData, boostersContext.state, context.engine.peers.getMyBoostStatus()).start(next: { peer, boostData, boosters, myStatus in
        
        updateState { current in
            var current = current
            current.peer = .init(peer)
            current.boostStatus = boostData
            current.booster = boosters
            current.myStatus = myStatus
            return current
        }
    }))
    
    let arguments = Arguments(context: context, openPeerInfo: { peerId in
        StatisticsHooks.shared.openPeerInfo(context, peerId)
    }, shareLink: { link in
        StatisticsHooks.shared.shareLink(context, link)
    }, copyLink: { link in
        showModalText(for: context.window, text: strings().shareLinkCopied)
        copyToClipboard(link)
    }, showMore: { [weak boostersContext] in
        boostersContext?.loadMore()
    }, giveaway: { prepaid in
        showModal(with: GiveawayModalController(context: context, peerId: peerId, prepaid: prepaid, isGroup: isGroup), for: context.window)
    }, openSlug: { slug in
        StatisticsHooks.shared.openGiftSlug(context, slug)
    }, boost: { features in
        let status = stateValue.with { $0.boostStatus }
        let myStatus = stateValue.with { $0.myStatus }
        let peer = stateValue.with { $0.peer?.peer }
        if let status = status, let peer = peer {
            showModal(with: BoostChannelModalController(context: context, peer: peer, boosts: status, myStatus: myStatus, onlyFeatures: features), for: context.window)
        }
    })
    
    let signal = statePromise.get() |> deliverOnPrepareQueue |> map { state in
        return InputDataSignalValue(entries: entries(state, arguments: arguments))
    }
    
    let controller = InputDataController(dataSignal: signal, title: strings().statsBoosts, removeAfterDisappear: false, hasDone: false)
    controller.analyticsScreen = .peerInfoBoosts
    
    controller.contextObject = boostersContext
    
    
    controller.onDeinit = {
        actionsDisposable.dispose()
    }
    
    controller.didAppear = { controller in
        context.window.set(handler: { _ -> KeyHandlerResult in
            arguments.giveaway(nil)
            return .invoked
        }, with: controller, for: .T, priority: .supreme, modifierFlags: [.command])}
    
    return controller
    
}
