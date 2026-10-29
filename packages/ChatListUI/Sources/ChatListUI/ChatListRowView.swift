import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import Accelerate
import TelegramMedia
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import Strings
import MessageUtils
import MessageTextUtils
import TelegramMediaUtils
import InlineMediaGrid
import AvatarUI
import ShortPeerRow
import PremiumStatusUI
import CommunityUI
import ChatUI
import InlineStickerLayer
import InputDataUI

extension EngineChatList.ForumTopicData {
    public var effectiveTitle: String {
        if let threadPeer {
            return threadPeer._asPeer().displayTitle
        } else {
            return self.title
        }
    }
}

private let badgeDiameter = floor(15.0 * 20.0 / 17.0)
private let avatarBadgeDiameter: CGFloat = floor(floor(15.0 * 22.0 / 17.0))
private let avatarTimerBadgeDiameter: CGFloat = floor(floor(15.0 * 24.0 / 17.0))


private final class AvatarBadgeView: ImageView {
    enum OriginalContent: Equatable {
        case color(NSColor)
        case image(CGImage)
        
        static func ==(lhs: OriginalContent, rhs: OriginalContent) -> Bool {
            switch lhs {
            case let .color(color):
                if case .color(color) = rhs {
                    return true
                } else {
                    return false
                }
            case let .image(lhsImage):
                if case let .image(rhsImage) = rhs {
                    return lhsImage === rhsImage
                } else {
                    return false
                }
            }
        }
    }
    
    private struct Parameters: Equatable {
        var size: CGSize
        var text: String
    }
    
    private var originalContent: OriginalContent?
    private var parameters: Parameters?
    private var hasContent: Bool = false
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(content: OriginalContent) {
        if self.originalContent != content || !self.hasContent {
            self.originalContent = content
            self.update()
        }
    }
    
    public func update(size: CGSize, text: String) {
        let parameters = Parameters(size: size, text: text)
        if self.parameters != parameters || !self.hasContent {
            self.parameters = parameters
            self.update()
        }
    }
    
    private func update() {
        guard let originalContent = self.originalContent, let parameters = self.parameters else {
            return
        }
        
        self.hasContent = true
        
        let blurredWidth = 16
        let blurredHeight = 16
        let blurredContext = DrawingContext(size: CGSize(width: CGFloat(blurredWidth), height: CGFloat(blurredHeight)), scale: 1.0)
        
        let blurredSize = CGSize(width: CGFloat(blurredWidth), height: CGFloat(blurredHeight))
        blurredContext.withContext { c in
            switch originalContent {
            case let .color(color):
                c.setFillColor(color.cgColor)
                c.fill(CGRect(origin: CGPoint(), size: blurredSize))
            case let .image(image):
                c.setFillColor(NSColor.black.cgColor)
                c.fill(CGRect(origin: CGPoint(), size: blurredSize))
                
                c.scaleBy(x: blurredSize.width / parameters.size.width, y: blurredSize.height / parameters.size.height)
                let offsetFactor: CGFloat = 1.0 - 0.6
                let imageFrame = CGRect(origin: CGPoint(x: parameters.size.width - image.size.width + offsetFactor * parameters.size.width, y: parameters.size.height - image.size.height + offsetFactor * parameters.size.height), size: image.size)
                
                c.draw(image, in: imageFrame)
            }
        }
            
        var destinationBuffer = vImage_Buffer()
        destinationBuffer.width = UInt(blurredWidth)
        destinationBuffer.height = UInt(blurredHeight)
        destinationBuffer.data = blurredContext.bytes
        destinationBuffer.rowBytes = blurredContext.bytesPerRow
        
        vImageBoxConvolve_ARGB8888(
            &destinationBuffer,
            &destinationBuffer,
            nil,
            0, 0,
            UInt32(15),
            UInt32(15),
            nil,
            vImage_Flags(kvImageTruncateKernel | kvImageDoNotTile)
        )
        
        let divisor: Int32 = 0x1000

        let rwgt: CGFloat = 0.3086
        let gwgt: CGFloat = 0.6094
        let bwgt: CGFloat = 0.0820

        let adjustSaturation: CGFloat = 1.7

        let a = (1.0 - adjustSaturation) * rwgt + adjustSaturation
        let b = (1.0 - adjustSaturation) * rwgt
        let c = (1.0 - adjustSaturation) * rwgt
        let d = (1.0 - adjustSaturation) * gwgt
        let e = (1.0 - adjustSaturation) * gwgt + adjustSaturation
        let f = (1.0 - adjustSaturation) * gwgt
        let g = (1.0 - adjustSaturation) * bwgt
        let h = (1.0 - adjustSaturation) * bwgt
        let i = (1.0 - adjustSaturation) * bwgt + adjustSaturation

        let satMatrix: [CGFloat] = [
            a, b, c, 0,
            d, e, f, 0,
            g, h, i, 0,
            0, 0, 0, 1
        ]
        
        let brightness: CGFloat = 0.94
        let brighnessMatrix: [CGFloat] = [
            brightness, 0, 0, 0,
            0, brightness, 0, 0,
            0, 0, brightness, 0,
            0, 0, 0, 1
        ]
        
        func matrixMul(a: [CGFloat], b: [CGFloat], result: inout [CGFloat]) {
            for i in 0 ..< 4 {
                for j in 0 ..< 4 {
                    var sum: CGFloat = 0.0
                    for k in 0 ..< 4 {
                        sum += a[i + k * 4] * b[k + j * 4]
                    }
                    result[i + j * 4] = sum
                }
            }
        }
        
        var resultMatrix = Array<CGFloat>(repeating: 0.0, count: 4 * 4)
        matrixMul(a: satMatrix, b: brighnessMatrix, result: &resultMatrix)

        var matrix: [Int16] = resultMatrix.map { value in
            return Int16(value * CGFloat(divisor))
        }

        vImageMatrixMultiply_ARGB8888(&destinationBuffer, &destinationBuffer, &matrix, divisor, nil, nil, vImage_Flags(kvImageDoNotTile))
        
        guard let blurredImage = blurredContext.generateImage() else {
            return
        }
        
        self.image = generateImage(parameters.size, rotatedContext: { size, context in
            
            context.clear(CGRect(origin: CGPoint(), size: size))
            
            context.setBlendMode(.copy)
            context.setFillColor(NSColor.black.cgColor)
            context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
            
            context.setBlendMode(.sourceIn)
            context.draw(blurredImage, in: CGRect(origin: CGPoint(), size: size))
            
            
            context.setBlendMode(.normal)
            
            /*context.setFillColor(UIColor(white: 1.0, alpha: 0.08).cgColor)
            context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
            context.setFillColor(UIColor(white: 0.0, alpha: 0.05).cgColor)
            context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))*/
            
            var fontSize: CGFloat = floor(parameters.size.height * 0.48)
            while true {
                let string: NSAttributedString = .initialize(string: parameters.text, color: .white, font: .bold(fontSize))
                
                
                let line = CTLineCreateWithAttributedString(string)
                let stringBounds = CTLineGetBoundsWithOptions(line, [.excludeTypographicLeading])
                
                if stringBounds.width <= size.width - 5.0 * 2.0 || fontSize <= 2.0 {
                
                    context.saveGState()
                    context.textMatrix = CGAffineTransform(scaleX: 1.0, y: -1.0)
                                        
                    context.textPosition = CGPoint(x: stringBounds.minX + floor((size.width - stringBounds.width) / 2.0), y: stringBounds.maxY + floor((size.height - stringBounds.height) / 2.0))
                    
                    CTLineDraw(line, context)
                    
                    context.restoreGState()
                    
                    break
                } else {
                    fontSize -= 1.0
                }
            }
            
            let lineWidth: CGFloat = 1.5
            let lineInset: CGFloat = 2.0
            let lineRadius: CGFloat = size.width * 0.5 - lineInset - lineWidth * 0.5
            context.setLineWidth(lineWidth)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineCap(.round)
            
            context.addArc(center: CGPoint(x: size.width * 0.5, y: size.height * 0.5), radius: lineRadius, startAngle: CGFloat.pi * 0.5, endAngle: -CGFloat.pi * 0.5, clockwise: false)
            context.strokePath()
            
            let sectionAngle: CGFloat = CGFloat.pi / 11.0
            
            for i in 0 ..< 10 {
                if i % 2 == 0 {
                    continue
                }
                
                let startAngle = CGFloat.pi * 0.5 - CGFloat(i) * sectionAngle - sectionAngle * 0.15
                let endAngle = startAngle - sectionAngle * 0.75
                
                context.addArc(center: CGPoint(x: size.width * 0.5, y: size.height * 0.5), radius: lineRadius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
                context.strokePath()
            }
        })
    }
}

private final class ChatListTagsView : View {
    
    class TagView : View {
        private let textView = InteractiveTextView()
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            textView.userInteractionEnabled = false
            textView.textView.isSelectable = false
            addSubview(textView)
        }
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        func set(item: ChatListTag, context: any AccountContextProtocol, selected: Bool, animated: Bool) {
            self.textView.set(text: selected ? item.selected : item.text, context: context)
            self.backgroundColor = selected ? item.selectedColor : item.color
        }
        
        override func layout() {
            super.layout()
            textView.center()
            textView.setFrameOrigin(NSMakePoint(textView.frame.minX, textView.frame.minY + System.pixel))
        }
    }
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.masksToBounds = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func update(items: [ChatListTag], item: ChatListRowItem, animated: Bool) {
        
        
        while subviews.count > items.count {
            subviews.removeLast()
        }
        while subviews.count < items.count {
            let view = TagView(frame: .zero)
            view.layer?.cornerRadius = 4
            subviews.append(view)
        }
        
        var x: CGFloat = 0
        for (i, tag) in items.enumerated() {
            let view = subviews[i] as! TagView
            view.frame = CGRect(origin: CGPoint(x: x, y: 0), size: tag.size)
            view.set(item: tag, context: item.context, selected: item.isActiveSelected, animated: animated)
            x += tag.size.width + 3
        }
    }
}



public final class ChatListTopicNameAndTextLayout {
    private let context: any AccountContextProtocol
    private let message: Message
    private let items: [EngineChatList.ForumTopicData]
    private let draft:EngineChatList.Draft?
    
    public private(set) var size: NSSize = .zero
    
    public var first: EngineChatList.ForumTopicData? {
        return items.first
    }
    public var peerId: PeerId {
        return message.id.peerId
    }
    
    public private(set) var mainText: TextViewLayout?
    public private(set) var selectedMain: TextViewLayout?
    
    public private(set) var allNames: TextViewLayout?
    public private(set) var allSelectedNames: TextViewLayout?

    public init(_ context: any AccountContextProtocol, message: Message, items: [EngineChatList.ForumTopicData], draft: EngineChatList.Draft?) {
        self.message = message
        self.items = items
        self.context = context
        self.draft = draft
    }
    
    public var fastTrack: Bool {
        return first?.isUnread == true && first?.threadPeer == nil && message.peers[message.id.peerId]?.displayForumAsTabs(splitState: context.layout) == false
    }
    
    public func measure(_ width: CGFloat) {
        
        self.mainText = nil
        self.allNames = nil
        self.allSelectedNames = nil
        self.selectedMain = nil
        
        if let data = items.first {
            let attr = NSMutableAttributedString()
            let title = "\(clown) " + data.effectiveTitle
            let temp = NSAttributedString.initialize(string: title, color: theme.colors.text, font: .normal(.text))
            
            
            let titleSize = temp.sizeFittingWidth(.greatestFiniteMagnitude)
             
            let perSymbol = titleSize.width / CGFloat(title.length)
            let maxCount = (width - 10) / perSymbol
            
            _ = attr.append(string: title.prefixWithDots(Int(maxCount - 3)), color: theme.colors.text, font: .normal(.text))
            
            let range = attr.string.nsstring.range(of: clown)
            if range.location != NSNotFound {
                if let threadPeer = data.threadPeer {
                    attr.insertEmbedded(.embeddedAvatar(threadPeer), for: clown)
                } else {
                    let item: InlineStickerItem
                    if let fileId = data.iconFileId {
                        item = .init(source: .attribute(.init(fileId: fileId, file: message.associatedMedia[MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)] as? TelegramMediaFile, emoji: "")))
                    } else {
                        let file = ForumUI.makeIconFile(title: data.title, iconColor: data.iconColor, isGeneral: data.id == 1)
                        item = .init(source: .attribute(.init(fileId: Int64(data.iconColor), file: file, emoji: "")))
                    }
                    attr.addAttribute(TextInputAttributes.embedded, value: item, range: range)
                }
                
            }
            
            _ = attr.append(string: "\n")
            
            let text = chatListText(account: context.account, for: message, messagesCount: 1, draft: draft, folder: false, applyUserName: false, isPremium: context.isPremium).mutableCopy() as! NSMutableAttributedString
            
            if let author = message.author {
                let ignore: Bool
                if message.media.first is TelegramMediaAction {
                    ignore = true
                } else {
                    ignore = false
                }
                if !ignore {
                    let name = author.id == context.peerId ? strings().you : author.compactDisplayTitle
                    text.insert(.initialize(string: "\(name): ", color: theme.colors.text, font: .normal(.text)), at: 0)
                }
            }
            
            attr.append(text)
            attr.setSelected(color: theme.colors.underSelectedColor, range: attr.range)
            
            let isMonoforum = message.peers[message.id.peerId]?.displayForumAsTabs(splitState: context.layout) == true || data.threadPeer != nil

            let selectedAttr = attr.mutableCopy() as! NSMutableAttributedString
            selectedAttr.addAttribute(.foregroundColor, value: theme.colors.underSelectedColor, range: selectedAttr.range)
            
            self.selectedMain = .init(selectedAttr, maximumNumberOfLines: 2, mayItems: false, truncatingColor: isMonoforum ? theme.colors.underSelectedColor : theme.colors.grayText)
            self.mainText = .init(attr, maximumNumberOfLines: 2, mayItems: false, truncatingColor: theme.colors.grayText)
            
            self.mainText?.measure(width: width - 20)
            self.selectedMain?.measure(width: width - 20)

            if data.isUnread, data.threadPeer == nil, message.peers[message.id.peerId]?.displayForumAsTabs(splitState: context.layout) == false {
                self.mainText?.generateAutoBlock(backgroundColor: theme.colors.grayText.withAlphaComponent(0.1))
                self.selectedMain?.generateAutoBlock(backgroundColor: .clear)
            }
            
            var main: CGFloat = 0
            if let mainText = mainText, let line = mainText.lines.first {
                main = line.frame.width
            }
            
            if items.count > 1, width - main > 40 {
                let rest = items.suffix(items.count - 1)
                let attr = NSMutableAttributedString()
                for item in rest {
                    
                    var range = attr.append(string: clown + item.effectiveTitle, color: item.isUnread ? theme.colors.text : theme.colors.grayText, font: .normal(.text))
                    
                    range = NSMakeRange(range.location, 2)
                    
                    if let threadPeer = item.threadPeer {
                        attr.addAttribute(TextInputAttributes.embedded, value: InlineStickerItem(source: .avatar(threadPeer)), range: range)
                    } else {
                        let embedded: InlineStickerItem
                        if let fileId = item.iconFileId {
                            embedded = .init(source: .attribute(.init(fileId: fileId, file: message.associatedMedia[MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)] as? TelegramMediaFile, emoji: "")))
                        } else {
                            let file = ForumUI.makeIconFile(title: item.title, iconColor: item.iconColor, isGeneral: item.id == 1)
                            embedded = .init(source: .attribute(.init(fileId: Int64(item.iconColor), file: file, emoji: "")))
                        }
                        attr.addAttribute(TextInputAttributes.embedded, value: embedded, range: range)
                    }
                    
                    _ = attr.append(string: " ")
                }
                
                self.allNames = .init(attr, maximumNumberOfLines: 1)
                
                let selectedAttr = attr.mutableCopy() as! NSMutableAttributedString
                selectedAttr.addAttribute(.foregroundColor, value: theme.colors.underSelectedColor, range: selectedAttr.range)
                self.allSelectedNames = .init(selectedAttr, maximumNumberOfLines: 1)

                
                self.allNames?.measure(width: width - 15 - main)
                self.allSelectedNames?.measure(width: width - 15 - main)
            }
        }
        
      

        var size = NSMakeSize(width, 0)
        if let mainText = mainText {
            size.height += mainText.layoutSize.height
        }
        self.size = size
    }
}



private final class TopicNameAndTextView : View {
    

    private let mainView = InteractiveTextView()
    private var allView: InteractiveTextView?
    private var highlighted = false
    
    private var validLayout: ChatListTopicNameAndTextLayout?
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(mainView)
        
        mainView.textView.onlyTextIsInteractive = true
        mainView.scaleOnClick = true
        
        self.layer?.masksToBounds = false
        mainView.layer?.masksToBounds = false
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    private var isLite: Bool = false
    
    func update(context: any AccountContextProtocol, item: ChatListTopicNameAndTextLayout, highlighted: Bool, animated: Bool) {
        self.isLite = context.isLite(.emoji)
        self.validLayout = item
        mainView.set(text: highlighted ? item.selectedMain : item.mainText, context: context, decreaseAvatar: 0)
        
        mainView.removeAllHandlers()
        mainView.set(handler: { _ in
            if let first = item.first {
                ForumUI.open(item.peerId, addition: false, context: context, threadId: first.id)
            }
        }, for: .Click)
        
        mainView.userInteractionEnabled = item.fastTrack
        
        if let all = highlighted ? item.allSelectedNames : item.allNames {
            let current: InteractiveTextView
            if let view = self.allView {
                current = view
            } else {
                current = InteractiveTextView()
                current.userInteractionEnabled = false
                self.allView = current
                addSubview(current)
            }
            current.set(text: all, context: context, decreaseAvatar: 5)
        } else if let view = self.allView {
            performSubviewRemoval(view, animated: animated)
            self.allView = nil
        }
        needsLayout = true
    }
    
    
    override func layout() {
        super.layout()
        
        if let main = mainView.textView.textLayout, let first = main.lines.first {
            mainView.setFrameOrigin(.zero)
            if let allView = allView {
                allView.setFrameOrigin(NSMakePoint(first.frame.maxX + 6, first.frame.minY - first.frame.height + 2))
            }
        }
    }
}



private class ChatListDraggingContainerView : View {
    fileprivate var item: ChatListRowItem?
    fileprivate var activeDragging:Bool = false
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.tiff, .string, .kUrl, .kFileUrl])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if activeDragging {
            activeDragging = false
            needsDisplay = true
            if let tiff = sender.draggingPasteboard.data(forType: .tiff), let image = NSImage(data: tiff) {
                _ = (putToTemp(image: image) |> deliverOnMainQueue).start(next: { [weak item] path in
                    guard let item = item, let chatLocation = item.chatLocation else {return}
                    
                    ChatUIHooks.shared.navigateToChatWithFocus(item.context.bindings.rootNavigation(), item.context, chatLocation, nil, .files(list: [path], behavior: .automatic))
                    
                })
            } else {
                let list = sender.draggingPasteboard.propertyList(forType: .kFilenames) as? [String]
                if let item = item, let list = list {
                    let list = list.filter { path -> Bool in
                        if let size = fileSize(path) {
                            let exceed = FeatureNavigationHooks.shared.fileSizeLimitExceed(item.context, size)
                            return exceed
                        }
                        return false
                    }
                    if !list.isEmpty, let chatLocation = item.chatLocation {
                        ChatUIHooks.shared.navigateToChatWithFocus(item.context.bindings.rootNavigation(), item.context, chatLocation, nil, .files(list: list, behavior: .automatic))
                    }
                }
            }
            
            
            return true
        }
        return false
    }
    
    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        if let item = item, let peer = item.peer, peer.canSendMessage(false, threadData: item.mode.threadData), mouseInside() {
            activeDragging = true
            needsDisplay = true
        }
        superview?.draggingEntered(sender)
        return .generic
        
    }
    
    
    
    override public func draggingExited(_ sender: NSDraggingInfo?) {
        activeDragging = false
        needsDisplay = true
        superview?.draggingExited(sender)
    }
    
    public override func draggingEnded(_ sender: NSDraggingInfo) {
        activeDragging = false
        needsDisplay = true
        superview?.draggingEnded(sender)
    }
}

private final class ChatListExpandView: View {
    private let container = View()
    private let titleView = TextView()
    private let arrowView = ImageView()
    private let iconView = ImageView()

    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        titleView.userInteractionEnabled = false
        titleView.isSelectable = false

        container.layer?.cornerRadius = 10
        container.layer?.borderWidth = 1

        container.addSubview(iconView)
        container.addSubview(titleView)
        container.addSubview(arrowView)
        iconView.isAccessibilityDecorative = true
        arrowView.isAccessibilityDecorative = true
        self.addSubview(container)
        updateLocalizationAndTheme(theme: theme)
    }

    override func updateLocalizationAndTheme(theme: PresentationTheme) {
        let theme = theme as! TelegramPresentationTheme
        container.backgroundColor = theme.colors.background.withAlphaComponent(0.4)
        container.layer?.borderColor = theme.colors.border.cgColor

        iconView.image = TelegramThemeHooks.shared.image(.iconFilterArchive).precomposed(theme.colors.grayText)
        iconView.sizeToFit()

        let titleLayout = TextViewLayout(.initialize(string: strings().chatListArchivedChats, color: theme.colors.grayText, font: .medium(12)), maximumNumberOfLines: 1, alwaysStaticItems: true)
        titleLayout.measure(width: .greatestFiniteMagnitude)
        titleView.update(titleLayout)

        arrowView.image = TelegramThemeHooks.shared.image(.iconPeerMusicChevron).precomposed(theme.colors.grayText)
        arrowView.sizeToFit()

        needsLayout = true
    }

    override func layout() {
        super.layout()
        let inset: CGFloat = 5
        container.frame = NSMakeRect(inset, 5, frame.width - inset * 2, frame.height - 5)

        let spacing: CGFloat = 4
        let totalWidth = iconView.frame.width + spacing + titleView.frame.width + arrowView.frame.width
        var x = floorToScreenPixels(backingScaleFactor, (container.frame.width - totalWidth) / 2)
        let cy = floorToScreenPixels(backingScaleFactor, (container.frame.height - iconView.frame.height) / 2)

        iconView.setFrameOrigin(NSMakePoint(x, cy))
        x += iconView.frame.width + spacing
        titleView.setFrameOrigin(NSMakePoint(x, floorToScreenPixels(backingScaleFactor, (container.frame.height - titleView.frame.height) / 2)))
        x += titleView.frame.width + 2
        arrowView.setFrameOrigin(NSMakePoint(x, floorToScreenPixels(backingScaleFactor, (container.frame.height - arrowView.frame.height) / 2)))
    }

    func animateOnce() {
        container.layer?.animateScaleSpring(from: 0.7, to: 1, duration: 0.35, removeOnCompletion: true, bounce: true, completion: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

func makeChatListSelectionPlateLayer() -> SimpleLayer {
    let layer = SimpleLayer()
    layer.anchorPoint = .zero
    layer.zPosition = -1
    layer.cornerRadius = 14
    if #available(macOS 10.15, *) {
        layer.cornerCurve = .continuous
    }
    layer.masksToBounds = true
    layer.isHidden = true
    return layer
}

func chatListAnimateLayerFrame(_ layer: CALayer, to frame: NSRect) {
    if frame.size != layer.frame.size {
        var presentBounds = layer.bounds
        if let presentation = layer.presentation(), layer.animation(forKey: "bounds") != nil {
            presentBounds.size.width = presentation.bounds.width
            presentBounds.size.height = presentation.bounds.height
        }
        layer.animateBounds(from: presentBounds, to: NSMakeRect(0, 0, frame.width, frame.height), duration: 0.2, timingFunction: .easeOut)
        layer.bounds = NSMakeRect(0, 0, frame.width, frame.height)
    }
    if frame.origin != layer.frame.origin {
        var presentOrigin = layer.frame.origin
        if let presentation = layer.presentation(), layer.animation(forKey: "position") != nil {
            presentOrigin = presentation.frame.origin
        }
        layer.animatePosition(from: presentOrigin, to: frame.origin, duration: 0.2, timingFunction: .easeOut)
        layer.position = frame.origin
    }
}

func chatListMediaShowsPlayIcon(_ media: Media) -> Bool {
    if media is TelegramMediaImage {
        return false
    } else if let file = media as? TelegramMediaFile {
        return !file.isAnimated
    } else {
        return true
    }
}

private final class ChatListMediaPreviewView: View {
    private let context: any AccountContextProtocol
    private let message: Message
    private let media: Media
    
    private let imageView: TransformImageView

    private let playIcon: ImageView?

    private var disposable: Disposable?
    private var shimmer: ShimmerLayer?
    private var inkView: MediaInkView?

    init(context: any AccountContextProtocol, message: Message, media: Media) {
        self.context = context
        self.message = message
        self.media = media

        self.imageView = TransformImageView()
        if chatListMediaShowsPlayIcon(media) {
            let playIcon = ImageView()
            playIcon.isAccessibilityDecorative = true
            playIcon.image = theme.icons.chat_list_thumb_play
            playIcon.sizeToFit()
            self.playIcon = playIcon
        } else {
            self.playIcon = nil
        }
        super.init()

        self.addSubview(self.imageView)
        if let playIcon = self.playIcon {
            self.addSubview(playIcon)
        }

    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    deinit {
        self.disposable?.dispose()
    }
    
    func updateLayout(size: CGSize) {
        let frame = CGRect(origin: CGPoint(), size: size)
        let media = self.media
        
        let isProtected = self.message.containsSecretMedia || self.message.isCopyProtected() || self.message.paidContent != nil
        
        self.imageView.preventsCapture = isProtected
        
        var dimensions = CGSize(width: 100.0, height: 100.0)
        var signal: Signal<ImageDataTransformation, NoError>? = nil
        if let image = self.media as? TelegramMediaImage {
            if let largest = largestImageRepresentation(image.representations) {
                dimensions = largest.dimensions.size
                signal = mediaGridMessagePhoto(account: self.context.account, imageReference: .message(message: MessageReference(self.message), media: image), scale: backingScaleFactor, autoFetchFullSize: true)
            }
        } else if let file = self.media as? TelegramMediaFile {
            if let mediaDimensions = file.dimensions {
                dimensions = mediaDimensions.size
                signal = mediaGridMessageVideo(account: self.context.account, fileReference: .message(message: MessageReference(self.message), media: file), scale: backingScaleFactor)
            }
        }
        let arguments = TransformImageArguments(corners: ImageCorners(radius: 2.0), imageSize: dimensions.aspectFilled(size), boundingSize: size, intrinsicInsets: NSEdgeInsets())
        
        self.imageView.setSignal(signal: cachedMedia(media: media, arguments: arguments, scale: System.backingScale, positionFlags: nil), clearInstantly: true)
        
        if imageView.image == nil {
            if shimmer == nil {
                let shimmer = ShimmerLayer()
                shimmer.cornerRadius = .cornerRadius
                if #available(macOS 10.15, *) {
                    shimmer.cornerCurve = .continuous
                }
                shimmer.frame = size.bounds
                self.layer?.addSublayer(shimmer)
                self.shimmer = shimmer
                
                shimmer.update(backgroundColor: nil, foregroundColor: NSColor(rgb: 0x748391, alpha: 0.2), shimmeringColor: NSColor(rgb: 0x748391, alpha: 0.35), data: nil, size: size, imageSize: dimensions)
                shimmer.updateAbsoluteRect(size.bounds, within: size)

            }
        } else if let shimmer = shimmer {
            shimmer.removeFromSuperlayer()
            self.shimmer = nil
        }
        
        if let signal = signal, !imageView.isFullyLoaded {
            self.imageView.setSignal(signal, cacheImage: { [weak self] result in
                cacheMedia(result, media: media, arguments: arguments, scale: System.backingScale, positionFlags: nil)
                if result.highQuality {
                    self?.shimmer?.removeFromSuperlayer()
                    self?.shimmer = nil
                }
            }, isProtected: isProtected)
        }
        
        
        self.imageView.frame = frame
        self.imageView.set(arguments: arguments)
        
        let isSpoiler = message.isMediaSpoilered

        if isSpoiler {
            let current: MediaInkView
            if let view = self.inkView {
                current = view
            } else {
                current = MediaInkView(frame: frame)
                self.inkView = current

                if let aboveView = self.playIcon {
                    self.addSubview(current, positioned: .below, relativeTo: aboveView)
                } else {
                    self.addSubview(current, positioned: .above, relativeTo: self.imageView)
                }
            }
            current.userInteractionEnabled = false
            
            
            self.imageView.layer?.opacity = 0
            
            let image: TelegramMediaImage
            if let current = media as? TelegramMediaImage {
                image = current
            } else if let file = media as? TelegramMediaFile {
                image = TelegramMediaImage.init(imageId: file.fileId, representations: file.previewRepresentations, immediateThumbnailData: file.immediateThumbnailData, reference: nil, partialReference: nil, flags: TelegramMediaImageFlags())
            } else {
                fatalError()
            }
            
            let imageReference = ImageMediaReference.message(message: MessageReference(message), media: image)
            
            current.update(isRevealed: false, updated: true, context: context, imageReference: imageReference, size: size, corners: nil, synchronousLoad: false, isSensitive: false, payAmount: nil)
            current.frame = frame
        } else if let view = self.inkView {
            performSubviewRemoval(view, animated: false)
            self.inkView = nil
            self.imageView.layer?.opacity = 1
        }
        
    }
}


private final class GroupCallActivity : View {
    private let animation:GCChatListIndicator = GCChatListIndicator(color: .white)
    private let backgroundView = ImageView()
    
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        addSubview(animation)
        animation.center()
        isEventLess = true
        animation.isEventLess = true
        backgroundView.isEventLess = true
        backgroundView.isAccessibilityDecorative = true
    }

    
    func update(context: any AccountContextProtocol, tableView: TableView?, foregroundColor: NSColor, backgroundColor: NSColor, animColor: NSColor) {
        self.animation.color = animColor
        backgroundView.image = generateImage(frame.size, contextGenerator: { size, ctx in
            let rect = NSRect(origin: .zero, size: size)
            ctx.clear(rect)
            ctx.setFillColor(backgroundColor.cgColor)
            ctx.fillEllipse(in: rect)
            
            ctx.setFillColor(foregroundColor.cgColor)
            ctx.fillEllipse(in: NSMakeRect(2, 2, frame.width - 4, frame.height - 4))
        })
        backgroundView.sizeToFit()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class ChatListRevealActionView: Control {
    private let circle: View = View()
    private let lottie: LAnimationButton
    private let titleLabel = TextViewLabel()
    private let circleSize: CGFloat = 36
    private let compactIcon: Bool
    let idealWidth: CGFloat

    init(animation: String, title: String, tintColor: NSColor, titleColor: NSColor, autoplaySide: LButtonAutoplaySide?, rotated: Bool = false, keysToColor: [String]? = nil, lottieTintColor: NSColor? = nil, compactIcon: Bool = false) {
        self.compactIcon = compactIcon
        let lottieSize = compactIcon ? NSMakeSize(36, 36) : NSMakeSize(48, 48)
        self.lottie = LAnimationButton(animation: animation, size: lottieSize, keysToColor: keysToColor, color: lottieTintColor ?? tintColor, offset: .zero, autoplaySide: autoplaySide, rotated: rotated)

        self.titleLabel.attributedString = .initialize(string: title, color: titleColor, font: .medium(11))
        self.titleLabel.sizeToFit()

        self.idealWidth = max(circleSize, ceil(titleLabel.frame.width))

        super.init(frame: .zero)

        self.circle.frame = NSMakeRect(0, 0, circleSize, circleSize)
        self.circle.backgroundColor = tintColor
        self.circle.layer?.cornerRadius = circleSize / 2

        self.titleLabel.userInteractionEnabled = false
        self.lottie.userInteractionEnabled = false

        self.layer?.masksToBounds = false

        addSubview(circle)
        addSubview(lottie)
        addSubview(titleLabel)

        scaleOnClick = true
        stretchReferenceView = circle
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }

    override func layout() {
        super.layout()
        let totalHeight = circleSize + 4 + titleLabel.frame.height
        let yStart = floorToScreenPixels(backingScaleFactor, (frame.height - totalHeight) / 2)
        let circleOriginX = floorToScreenPixels(backingScaleFactor, (frame.width - circleSize) / 2)
        let circleRect = NSMakeRect(circleOriginX, yStart, circleSize, circleSize)
        circle.frame = circleRect
        let lottieDim = lottie.frame.width
        let lottieYOffset: CGFloat = compactIcon ? 0 : 6
        lottie.frame = NSMakeRect(circleRect.midX - lottieDim / 2, circleRect.midY - lottieDim / 2 + lottieYOffset, lottieDim, lottieDim)
        titleLabel.centerX(y: circleRect.maxY + 4)
    }
}

final class ChatListTextLayer: SimpleLayer {
    private final class DrawLayer: SimpleLayer {
        var textLayout: TextViewLayout?
        var textSize: NSSize = .zero

        override func draw(in ctx: CGContext) {
            guard let textLayout = textLayout else {
                return
            }
            let renderer = ChatListTextLayer.renderer
            renderer.update(textLayout)
            renderer.setFrameSize(textSize)
            renderer.draw(renderer.drawingLayer, in: ctx)
        }
    }

    static let renderer: TextView = {
        let view = TextView()
        view.userInteractionEnabled = false
        view.isSelectable = false
        return view
    }()

    private let drawLayer = DrawLayer()

    override init() {
        super.init()
        anchorPoint = .zero
        zPosition = 1
        masksToBounds = false
        addSublayer(drawLayer)
    }

    override init(layer: Any) {
        super.init(layer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ layout: TextViewLayout) {
        if drawLayer.textLayout === layout, drawLayer.textSize == layout.layoutSize, bounds.size == layout.layoutSize, drawLayer.contents != nil {
            return
        }
        drawLayer.textLayout = layout
        bounds = CGRect(origin: .zero, size: layout.layoutSize)
        if drawLayer.textSize != bounds.size {
            drawLayer.textSize = bounds.size
        }
        drawLayer.frame = bounds
        drawLayer.bounds = bounds.insetBy(dx: -2, dy: -3)
        drawLayer.setNeedsDisplay()
    }
    
    var hasPendingDisplay: Bool {
        return drawLayer.needsDisplay()
    }

    func updateScale(_ scale: CGFloat) {
        if drawLayer.contentsScale != scale {
            drawLayer.contentsScale = scale
            drawLayer.setNeedsDisplay()
        }
    }

    static func remove(_ layer: CALayer, animated: Bool) {
        if animated {
            let from = layer.presentation()?.opacity ?? layer.opacity
            layer.animateAlpha(from: CGFloat(from), to: 0, duration: 0.2, timingFunction: .easeOut, removeOnCompletion: false, completion: { [weak layer] _ in
                layer?.removeFromSuperlayer()
            })
        } else {
            layer.removeFromSuperlayer()
        }
    }
}

final class ChatListInlineText {
    let view = TextView()
    private let renderer: InlineTextRenderer = GeneralRowsHooks.shared.makeInlineTextRenderer()

    init() {
        view.userInteractionEnabled = false
        view.isSelectable = false
    }

    func set(text: TextViewLayout, context: any AccountContextProtocol, insetEmoji: CGFloat = 0, decreaseAvatar: CGFloat = 0) {
        view.update(text)
        renderer.update(textView: view, layout: text, context: context, insetEmoji: insetEmoji, emojiOffset: .zero, decreaseAvatar: decreaseAvatar)
    }

    func updateAnimatableContent(isLite: Bool) {
        renderer.updateAnimatableContent(window: view.window, isLite: isLite)
    }
}

private final class ChatListRowContentDrawer: ViewDisplayDelegate {
    weak var row: ChatListRowView?
    func draw(_ layer: CALayer, in ctx: CGContext) {
        row?.drawContent(in: ctx)
    }
}

func chatListGramBadgeIcon(highlighted: Bool, muted: Bool) -> CGImage {
    let color: NSColor
    if highlighted {
        color = theme.chatList.badgeSelectedBackgroundColor
    } else if muted {
        color = theme.chatList.badgeMutedBackgroundColor
    } else {
        color = theme.chatList.badgeBackgroundColor
    }
    let background = NSImage(named: "Icon_ChatList_GramBadgeBackground")!.precomposed(color)
    let foreground = NSImage(named: "Icon_ChatList_GramBadgeForeground")!.precomposed(highlighted ? theme.chatList.badgeSelectedTextColor : nil)
    return generateImage(background.backingSize, contextGenerator: { size, ctx in
        ctx.clear(size.bounds)
        ctx.draw(background, in: size.bounds)
        ctx.draw(foreground, in: size.bounds)
    })!
}

public class ChatListRowView: TableRowView, RevealTableView {
    
    private final class ForumTopicArrow : View {
        private let imageView = ImageView()
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            addSubview(imageView)
            self.isEventLess = true
            self.imageView.isEventLess = true
            self.imageView.isAccessibilityDecorative = true
            updateLocalizationAndTheme(theme: theme)
        }
        
        
        override func layout() {
            super.layout()
            imageView.centerY(x: 0)
        }
        
        func update(_ item: ChatListRowItem, animated: Bool) {
            imageView.image = item.isActiveSelected ? theme.icons.chatlist_arrow_active : theme.icons.chatlist_arrow

            imageView.sizeToFit()
            needsLayout = true
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    private let revealLeftView: View = View()
    
    private var internalDelta: CGFloat?
    
    private let revealRightView: View = View()
    
    private var chatNameText: ChatListInlineText? = nil
    private var dateTextView: ChatListTextLayer? = nil
    private var displayNameView: ChatListTextLayer? = nil
    private var monoforumMessagesView: InteractiveTextView? = nil
    private var messageText: ChatListInlineText? = nil

    private var chatNameTextView: TextView? {
        return chatNameText?.view
    }
    private var messageTextView: TextView? {
        return messageText?.view
    }

    private var storyReplyImageView : ImageView?
    
    
    private var forumTopicTextView: ChatListTextLayer? = nil
    private var forumTopicNameIcon: ForumTopicArrow?
    
    private var topicsView: TopicNameAndTextView?
    
    private var inlineTopicPhotoLayer: InlineStickerItemLayer?
        
    private var badgeView:Control?
    private var badgeShortView:View?

    private var mentionsView: ImageView?
    private var reactionsView: ImageView?
    private var pollVotesView: ImageView?
    
    private var selectionView: View?
    
    private var openMiniApp: TextView?

    
    private var activeImage: ImageView?
    private var groupActivityView: GroupCallActivity?
    private var activitiesModel:ChatActivitiesModel?
    private var activityLayout: (width: CGFloat, scale: CGFloat)?
    private let photo: AvatarStoryControl = AvatarStoryControl(font: .avatar(22), size: NSMakeSize(50, 50))

    private var photoVideoView: MediaPlayerView?
    private var photoVideoPlayer: MediaPlayer?
    
    private var starBadgeView: ImageView?
    private var communityDropdown: ImageButton?
    private var communityHiddenView: ImageView?
    
    

    private var hiddenMessage:Bool = false {
        didSet {
            if hiddenMessage != oldValue, let item = self.item {
                self.set(item: item, animated: false)
            }
        }
    }
    private let peerInputActivitiesDisposable:MetaDisposable = MetaDisposable()
    private var animatedView: RowAnimateView?
    private var archivedPhoto: LAnimationButton?
   
    private let containerView: ChatListDraggingContainerView = ChatListDraggingContainerView(frame: NSZeroRect)
    private let contentView: View = View()
    private let contentDrawer = ChatListRowContentDrawer()
    private let selectionBackgroundLayer: SimpleLayer = makeChatListSelectionPlateLayer()
    private var expandView: ChatListExpandView?
    
    private var statusControl: PremiumStatusControl?
    
    private var leftStatusControl: PremiumStatusControl?

    
    private var avatarTimerBadge: AvatarBadgeView?
    
    private var liveStreamView: ImageView?
    
    private var currentMediaPreviewSpecs: [(message: Message, media: Media, size: CGSize)] = []
    private var mediaPreviewViews: [MessageId: ChatListMediaPreviewView] = [:]
    
    private var tagsView: ChatListTagsView?

    
    private var revealActionInvoked: Bool = false {
        didSet {
            animateOnceAfterDelta = true
        }
    }
    public var endRevealState: SwipeDirection? {
        didSet {
            internalDelta = nil
            if let oldValue = oldValue, endRevealState == nil  {
                switch oldValue {
                case .left, .right:
                    revealActionInvoked = true
                    completeReveal(direction: .none)
                default:
                    break
                }
            }
        }
    }
    public override var isFlipped: Bool {
        return true
    }
    
    private var highlighed: Bool {
        if let item = item as? ChatListRowItem {
            let highlighted = item.isSelected && item.context.layout != .single && !(item.isForum && !item.isTopic)
            return highlighted
        }
        return false
    }
    
    
    public var inputActivities:(PeerId, [(Peer, PeerInputActivity)])? {
        didSet {
            
            for (message, _, _) in self.currentMediaPreviewSpecs {
                if let previewView = self.mediaPreviewViews[message.id] {
                    previewView.isHidden = inputActivities != nil && !inputActivities!.1.isEmpty
                }
            }
            
            if let inputActivities = inputActivities, !inputActivities.1.isEmpty, let item = item as? ChatListRowItem {
                let activitiesChanged: Bool
                if let previous = oldValue, previous.0 == inputActivities.0, previous.1.count == inputActivities.1.count {
                    activitiesChanged = !zip(previous.1, inputActivities.1).allSatisfy { previous, current in
                        previous.1 == current.1 && previous.0.isEqual(current.0)
                    }
                } else {
                    activitiesChanged = true
                }
                if activitiesModel == nil {
                    activitiesModel = ChatActivitiesModel()
                    contentView.addSubview(activitiesModel!.view!)
                }

                let activity: ActivitiesTheme
                if self.highlighed {
                    activity = theme.activity(key: 10, foregroundColor: theme.chatList.activitySelectedColor, backgroundColor: backdorColor)
                } else {
                    activity = theme.activity(key: 15, foregroundColor: theme.colors.grayIcon, backgroundColor: theme.colors.background)
                }
                let width = item.inputActivityWidth
                let scale = System.backingScale
                if activitiesChanged || activity != activitiesModel?.theme || activityLayout?.width != width || activityLayout?.scale != scale {
                    activityLayout = (width, scale)
                    activitiesModel?.update(with: inputActivities, for: width, theme: activity, layout: { [weak self] show in
                        self?.hiddenMessage = show
                        self?.needsLayout = true
                    })
                }
            } else {
                activitiesModel?.clean()
                activitiesModel?.view?.removeFromSuperview()
                activitiesModel = nil
                activityLayout = nil
                hiddenMessage = false
            }
        }
    }

    public override func onShowContextMenu() {
        super.onShowContextMenu()
        let inputActivities = self.inputActivities
        self.inputActivities = inputActivities
    }
    
    public override func onCloseContextMenu() {
        super.onCloseContextMenu()
        let inputActivities = self.inputActivities
        self.inputActivities = inputActivities
    }
    
    
    public override func focusAnimation(_ innerId: AnyHashable?, text: String?) {

        if animatedView == nil {
            let initialFrame: NSRect
            let initialCornerRadius: CGFloat
            if let item = item as? ChatListRowItem, item.context.layout == .minimisize {
                initialFrame = photo.frame
                initialCornerRadius = initialFrame.height / 2
            } else {
                initialFrame = bounds
                initialCornerRadius = 0
            }
            self.animatedView = RowAnimateView(frame: initialFrame)
            self.animatedView?.layer?.cornerRadius = initialCornerRadius
            self.animatedView?.isEventLess = true
            containerView.addSubview(animatedView!)
            animatedView?.backgroundColor = theme.colors.focusAnimationColor
            animatedView?.layer?.opacity = 0

        }
        animatedView?.stableId = item?.stableId
        
        
        let animation: CABasicAnimation = makeSpringAnimation("opacity")
        
        animation.fromValue = animatedView?.layer?.presentation()?.opacity ?? 0
        animation.toValue = 0.5
        animation.autoreverses = true
        animation.isRemovedOnCompletion = true
        animation.fillMode = CAMediaTimingFillMode.forwards
        
        animation.delegate = CALayerAnimationDelegate(completion: { [weak self] completed in
            if completed {
                self?.animatedView?.removeFromSuperview()
                self?.animatedView = nil
            }
        })
        animation.isAdditive = false
        
        animatedView?.layer?.add(animation, forKey: "opacity")
        
    }
    
    public var _backgroundColor: NSColor {
        if let item = item as? ChatListRowItem {
            if item.shouldHideContent {
                return theme.colors.listBackground
            } else {
                return theme.colors.background
            }
            
        }
        return theme.colors.background
    }
    
    
    public override var backdorColor: NSColor {
        if let item = item as? ChatListRowItem {
            if item.isForum && !item.isTopic, !isResorting {
                return .clear
            }
            if case .savedMessageIndex = item.entryId {
                return theme.colors.background
            }
            if item.isCollapsed {
                return .clear
            }
        }
        return .clear
    }

    private func selectionBackgroundColor() -> NSColor {
        guard let item = item as? ChatListRowItem else { return .clear }
        if item.isCollapsed { return .clear }
        if case .savedMessageIndex = item.entryId { return .clear }
        if item.isForum && !item.isTopic, !isResorting { return .clear }
        if self.isResorting {
            if item.shouldHideContent {
                return theme.colors.listBackground
            } else {
                return theme.colors.background
            }
        }
        if item.isHighlighted && !item.isSelected {
            return theme.chatList.activeDraggingBackgroundColor
        }
        if item.context.layout == .single, item.isSelected {
            return theme.chatList.singleLayoutSelectedBackgroundColor
        }
        if !item.isSelected && containerView.activeDragging {
            return theme.chatList.activeDraggingBackgroundColor
        }
        if item.isSelected && item.isForum && !item.isTopic {
            return theme.chatList.activeDraggingBackgroundColor
        }
        if item.isSelected && !item.isAutohidden {
            return theme.chatList.selectedBackgroundColor
        }
        if contextMenu != nil {
            return theme.chatList.contextMenuBackgroundColor
        }
        return .clear
    }

    public override func updateIsResorting() {
        super.updateIsResorting()
        animateSelectionChange = true
        updateColors()
        animateSelectionChange = false
        invalidatePreviousRowBorder()
    }

    private func invalidatePreviousRowBorder() {
        guard let item = self.item as? ChatListRowItem, let table = item.table, item.index > 0 else { return }
        if let prev = table.viewNecessary(at: item.index - 1) as? ChatListRowView {
            prev.contentView.needsDisplay = true
        }
    }
    
    
    fileprivate func drawContent(in ctx: CGContext) {
        if let item = self.item as? ChatListRowItem {
             let nextItem = item.table?.nextItem(after: item.index) as? ChatListRowItem
             let nextSelected = nextItem?.isSelected ?? false
             let nextHighlighted = nextItem?.isHighlighted ?? false
             let nextRowView = item.table?.viewNecessary(at: item.index + 1) as? ChatListRowView
             let nextResorting = nextRowView?.isResorting ?? false
             let nextDragging = nextRowView?.containerView.activeDragging ?? false
             let suppressForSelection = item.isSelected && !item.isSelectedForum
             let suppressForHighlight = item.isHighlighted
             let suppressForResort = self.isResorting
             let suppressForDrag = containerView.activeDragging
             if !suppressForSelection, !suppressForHighlight, !suppressForResort, !suppressForDrag, !item.isAutohidden, !nextSelected, !nextHighlighted, !nextResorting, !nextDragging {

                ctx.setFillColor(theme.colors.border.cgColor)
                ctx.fill(NSMakeRect(item.isLastPinned ? 0 : item.leftInset, contentView.bounds.height - .borderSize, item.isLastPinned ? contentView.frame.width : contentView.bounds.width - item.leftInset, .borderSize))
            }

            
            let highlighted = self.highlighed
            
            if item.ctxBadgeNode == nil && !item.showsMentionSlot && (item.isPinned || item.isLastPinned) {
                ctx.draw(highlighted ? theme.icons.pinnedImageSelected : theme.icons.pinnedImage, in: NSMakeRect(frame.width - theme.icons.pinnedImage.backingSize.width - item.margin - 1, frame.height - theme.icons.pinnedImage.backingSize.height - (item.margin + 1), theme.icons.pinnedImage.backingSize.width, theme.icons.pinnedImage.backingSize.height))
            }
            
            if let displayLayout = item.ctxDisplayLayout {
                
                var addition:CGFloat = 0
                if let statusControl = leftStatusControl {
                    addition += statusControl.frame.width + 2
                }
                if item.isSecret {
                    ctx.draw(highlighted ? theme.icons.secretImageSelected : theme.icons.secretImage, in: NSMakeRect(item.leftInset + addition, item.margin + 3, theme.icons.secretImage.backingSize.width, theme.icons.secretImage.backingSize.height))
                    addition += theme.icons.secretImage.backingSize.height
                    
                }
                if item.appearMode == .short, item.isTopic {
                    //addition += 20
                }
                
                if let statusControl = statusControl {
                    addition += statusControl.frame.width + 1
                }

                if item.isMuted {
                    let icon = theme.icons.dialogMuteImage
                    let activeIcon = theme.icons.dialogMuteImageSelected
                    let y: CGFloat
                    let x: CGFloat
                    if displayLayout.numberOfLines > 1 {
                        x = item.leftInset + displayLayout.lastLineWidth + 4 + addition
                        y = item.margin + 2 + displayLayout.layoutSize.height - displayLayout.lastLineHeight
                    } else {
                        x = item.leftInset + displayLayout.layoutSize.width + 4 + addition
                        y = item.margin + round((displayLayout.layoutSize.height - icon.backingSize.height) / 2.0) - 1
                    }
                    ctx.draw(highlighted ? activeIcon : icon, in: NSMakeRect(x, y, icon.backingSize.width, icon.backingSize.height))
                }
                
                if let dateLayout = item.ctxDateLayout, !item.hasDraft {
                    let dateX = contentView.frame.width - dateLayout.layoutSize.width - item.margin
                    
                    if item.isClosedTopic {
                        let icon = theme.icons.chatlist_forum_closed_topic
                        let iconActive = theme.icons.chatlist_forum_closed_topic_active
                        let outX = dateX - icon.backingSize.width - 4
                        ctx.draw(highlighted ? iconActive : icon, in: NSMakeRect(outX, item.margin + 2, icon.backingSize.width, icon.backingSize.height))
                    } else {
                        if !item.isFailed {
                            if item.isSending {
                                let outX = dateX - theme.icons.sendingImage.backingSize.width - 4
                                ctx.draw(highlighted ? theme.icons.sendingImageSelected : theme.icons.sendingImage, in: NSMakeRect(outX,item.margin + 2, theme.icons.sendingImage.backingSize.width, theme.icons.sendingImage.backingSize.height))
                            } else {
                                if item.isOutMessage {
                                    let outX = dateX - theme.icons.outgoingMessageImage.backingSize.width - (item.isRead ? 4.0 : 0.0) - 2
                                    ctx.draw(highlighted ? theme.icons.outgoingMessageImageSelected : theme.icons.outgoingMessageImage, in: NSMakeRect(outX, item.margin + 2, theme.icons.outgoingMessageImage.backingSize.width, theme.icons.outgoingMessageImage.backingSize.height))
                                    if item.isRead {
                                        ctx.draw(highlighted ? theme.icons.readMessageImageSelected : theme.icons.readMessageImage, in: NSMakeRect(outX + 4, item.margin + 2, theme.icons.readMessageImage.backingSize.width, theme.icons.readMessageImage.backingSize.height))
                                    }
                                }
                            }
                        } else {
                            let outX = dateX - theme.icons.errorImageSelected.backingSize.width - 4
                            ctx.draw(highlighted ? theme.icons.errorImageSelected : theme.icons.errorImage, in: NSMakeRect(outX,item.margin, theme.icons.errorImage.backingSize.width, theme.icons.errorImage.backingSize.height))
                        }
                    }
                }
            }
        }
    }


    public required init(frame frameRect: NSRect) {
       
        
        super.init(frame: frameRect)
        
        containerView.layer?.addSublayer(selectionBackgroundLayer)
        containerView.addSubview(contentView)
        self.layerContentsRedrawPolicy = .onSetNeedsDisplay
        photo.userInteractionEnabled = false
        
        photo.frame = NSMakeRect(10, 10, 50, 50)
        containerView.addSubview(photo)
        
        addSubview(containerView)
        
        containerView.frame = bounds
        contentView.frame = bounds
        
        
        photo.contentUpdated = { [weak self] image in
            if let image = image {
                self?.avatarTimerBadge?.update(content: .image(image as! CGImage))
            } else {
                self?.avatarTimerBadge?.update(content: .color(.white))
            }
        }
        
        photo.set(handler: { [weak self] _ in
            if let item = self?.item as? ChatListRowItem {
                if item.showsCommunityDropdown {
                    item.openCommunityPreview()
                } else {
                    item.openPeerStory()
                }
            }
        }, for: .Click)
        
        contentDrawer.row = self
        contentView.displayDelegate = contentDrawer
        
    }
    
    public func takeStoryControl() -> NSView? {
        return self.photo
    }
    
    public func setStoryProgress(_ signal:Signal<Never, NoError>)  {
        SetOpenStoryDisposable(self.photo.pushLoadingStatus(signal: signal))
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
    }
    
    override public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        needsDisplay = true
        animateSelectionChange = true
        updateColors()
        animateSelectionChange = false
        invalidatePreviousRowBorder()
        return .generic

    }

    override public func draggingExited(_ sender: NSDraggingInfo?) {
        needsDisplay = true
        animateSelectionChange = true
        updateColors()
        animateSelectionChange = false
        invalidatePreviousRowBorder()
    }

    public override func draggingEnded(_ sender: NSDraggingInfo) {
        needsDisplay = true
        animateSelectionChange = true
        updateColors()
        animateSelectionChange = false
        invalidatePreviousRowBorder()
    }

    private var selectionVisible: Bool = false
    private var animateSelectionChange: Bool = false
    public override func updateColors() {
        super.updateColors()
        let inputActivities = self.inputActivities
        self.inputActivities = inputActivities
        self.containerView.background = backdorColor
        self.expandView?.backgroundColor = .clear
        self.contentView.backgroundColor = backdorColor

        let selectionColor = selectionBackgroundColor()
        let shouldShow = selectionColor.alphaComponent != 0
        selectionBackgroundLayer.backgroundColor = selectionColor.cgColor

        if shouldShow != selectionVisible {
            selectionVisible = shouldShow
            if animateSelectionChange {
                if shouldShow {
                    selectionBackgroundLayer.removeAllAnimations()
                    selectionBackgroundLayer.isHidden = false
                    selectionBackgroundLayer.opacity = 1
                    selectionBackgroundLayer.animateAlpha(from: 0, to: 1, duration: 0.2)
                } else {
                    selectionBackgroundLayer.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak self] _ in
                        guard let self = self, self.selectionVisible == false else { return }
                        self.selectionBackgroundLayer.removeAllAnimations()
                        self.selectionBackgroundLayer.isHidden = true
                        self.selectionBackgroundLayer.opacity = 1
                    })
                }
            } else {
                selectionBackgroundLayer.removeAllAnimations()
                selectionBackgroundLayer.isHidden = !shouldShow
                selectionBackgroundLayer.opacity = 1
            }
        } else if !shouldShow {
            selectionBackgroundLayer.isHidden = true
        }
    }

    private func updateRevealViewsAttachment() {
        if revealLeftView.subviews.isEmpty && revealRightView.subviews.isEmpty {
            revealLeftView.removeFromSuperview()
            revealRightView.removeFromSuperview()
        } else if revealLeftView.superview == nil {
            addSubview(revealLeftView, positioned: .below, relativeTo: nil)
            addSubview(revealRightView, positioned: .below, relativeTo: nil)
        }
    }
    
    
    public override var isEmojiLite: Bool {
        if let item = item as? ChatListRowItem {
            return item.context.isLite(.emoji)
        }
        return super.isEmojiLite
    }
    
    public override func updateAnimatableContent() -> Void {
        let isLite = self.isEmojiLite
        let checkValue:(InlineStickerItemLayer)->Void = { value in
            if let superview = value.superview {
                var isKeyWindow: Bool = false
                if let window = superview.window {
                    if !window.canBecomeKey {
                        isKeyWindow = true
                    } else {
                        isKeyWindow = window.isKeyWindow
                    }
                }
                value.isPlayable = superview.visibleRect != .zero && isKeyWindow && !isLite
            }
        }
        
        if let value = inlineTopicPhotoLayer {
            checkValue(value)
        }
        updateInlineTextAnimatableContent()
        updatePlayerIfNeeded()
    }

    private func updateInlineTextAnimatableContent() {
        let isLite = self.isEmojiLite
        messageText?.updateAnimatableContent(isLite: isLite)
        chatNameText?.updateAnimatableContent(isLite: isLite)
    }
    
    
    private var videoRepresentation: TelegramMediaImage.VideoRepresentation?

    public override func set(item:TableRowItem, animated:Bool = false) {

        let previousStableId = self.item?.stableId
        animateSelectionChange = animated && previousStableId == item.stableId
        defer { animateSelectionChange = false }

        if let item = item as? ChatListRowItem {
            if item.isCollapsed {
                if expandView == nil {
                    expandView = ChatListExpandView(frame: NSMakeRect(0, frame.height, frame.width, item.height))
                }
                self.addSubview(expandView!, positioned: .below, relativeTo: containerView)
                expandView?.updateLocalizationAndTheme(theme: theme)
            } else {
                if let expandView = expandView {
                    expandView.removeFromSuperview()
                }
            }
        }

        let previous = self.item as? ChatListRowItem


         let wasHidden: Bool = previous?.isCollapsed ?? false
         super.set(item:item, animated:animated)
        
                
         if let item = item as? ChatListRowItem {
             
             let animated = animated && previous?.splitState == item.splitState
                          
             let unhideProgress = item.getHideProgress?()
             guard self.item === item else { return }
             
             
             contentView.change(opacity: unhideProgress ?? (item.shouldHideContent ? 0 : 1), animated: animated)
             contentView.change(pos: contentPoint(item), animated: animated)
             
             
             if item.isForum && !item.isTopic, item.isSelectedForum {
                 let current: View
                 let isNew: Bool
                 if let view = self.selectionView {
                     current = view
                     isNew = false
                 } else {
                     isNew = true
                     current = View()
                     current.layer?.cornerRadius = 4
                     containerView.addSubview(current)
                     self.selectionView = current
                 }
                 current.backgroundColor = theme.colors.accent
                 let rect = selectionViewRect(item)
                 if isNew {
                     current.frame = rect
                     current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                     current.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2, bounce: false)
                 } else {
                     current.change(pos: rect.origin, animated: animated)
                     current.change(size: rect.size, animated: animated)
                 }
             } else if let view = self.selectionView {
                 
                 performSubviewRemoval(view, animated: animated, scale: true)
                 self.selectionView = nil
             }
             
             
             if let displayLayout = item.ctxDisplayLayout {
                 let current: ChatListTextLayer
                 if let view = self.displayNameView {
                     current = view
                 } else {
                     current = ChatListTextLayer()
                     current.updateScale(backingScaleFactor)
                     self.displayNameView = current
                     contentView.layer?.addSublayer(current)
                 }
                 current.update(displayLayout)
             } else if let view = self.displayNameView {
                 ChatListTextLayer.remove(view, animated: animated)
                 self.displayNameView = nil
             }
             
             if let displayLayout = item.ctxMonoforumMessages {
                 let current: InteractiveTextView
                 if let view = self.monoforumMessagesView {
                     current = view
                 } else {
                     current = InteractiveTextView(frame: .zero)
                     current.userInteractionEnabled = false

                     self.monoforumMessagesView = current
                     contentView.addSubview(current)
                 }

                 current.set(text: displayLayout, context: item.context)
                 current.setFrameSize(NSMakeSize(displayLayout.layoutSize.width + 4, displayLayout.layoutSize.height + 4))
                 current.layer?.cornerRadius = .cornerRadius
                 current.background = item.isActiveSelected ? theme.colors.underSelectedColor : theme.colors.grayText.withAlphaComponent(0.15)
             } else if let view = self.monoforumMessagesView {
                 performSubviewRemoval(view, animated: animated)
                 self.monoforumMessagesView = nil
             }
             
             if let dateLayout = item.ctxDateLayout {
                 let current: ChatListTextLayer
                 if let view = self.dateTextView {
                     current = view
                 } else {
                     current = ChatListTextLayer()
                     current.updateScale(backingScaleFactor)
                     self.dateTextView = current
                     contentView.layer?.addSublayer(current)
                 }
                 current.update(dateLayout)
             } else if let view = self.dateTextView {
                 ChatListTextLayer.remove(view, animated: animated)
                 self.dateTextView = nil
             }
             
             let peer = item.renderedPeer?.chatOrMonoforumMainPeer?._asPeer() ?? item.peer
             
             if let peer = peer, peer.id != item.context.peerId, !item.isTopic {
                 let highlighted = self.highlighed
                 let control = PremiumStatusControl.control(peer, account: item.context.account, inlinePacksContext: item.context.inlinePacksContext, left: false, isSelected: highlighted, cached: self.statusControl, animated: animated, autoupdate: false)
                 if let control = control {
                     self.statusControl = control
                     self.contentView.addSubview(control)
                 } else if let view = self.statusControl {
                     performSubviewRemoval(view, animated: animated)
                     self.statusControl = nil
                 }
             } else if let view = self.statusControl {
                 performSubviewRemoval(view, animated: animated)
                 self.statusControl = nil
             }
             
             if let peer = peer, peer.id != item.context.peerId, !item.isTopic {
                 let highlighted = self.highlighed
                 let control = PremiumStatusControl.control(peer, account: item.context.account, inlinePacksContext: item.context.inlinePacksContext, left: true, isSelected: highlighted, cached: self.leftStatusControl, animated: animated, autoupdate: false)
                 if let control = control {
                     self.leftStatusControl = control
                     self.contentView.addSubview(control)
                 } else if let view = self.leftStatusControl {
                     performSubviewRemoval(view, animated: animated)
                     self.leftStatusControl = nil
                 }
             } else if let view = self.leftStatusControl {
                 performSubviewRemoval(view, animated: animated)
                 self.leftStatusControl = nil
             }
             
             if item.isReplyToStory, !hiddenMessage {
                 let current: ImageView
                 if let view = self.storyReplyImageView {
                     current = view
                 } else {
                     current = ImageView()
                     current.isEventLess = true
                     current.isAccessibilityDecorative = true
                     self.storyReplyImageView = current
                     self.contentView.addSubview(current)
                 }
                 current.image = isSelect ? theme.icons.story_chatlist_reply_active : theme.icons.story_chatlist_reply
                 current.sizeToFit()
                 
             } else if let view = self.storyReplyImageView {
                 self.storyReplyImageView = nil
                 performSubviewRemoval(view, animated: false)
             }
             
             if let messageText = item.ctxMessageText, !hiddenMessage {
                 let current: ChatListInlineText
                 if let view = self.messageText {
                     current = view
                 } else {
                     current = ChatListInlineText()
                     self.messageText = current
                     self.contentView.addSubview(current.view)
                 }
                 current.set(text: messageText, context: item.context)

             } else if let view = self.messageTextView {
                 self.messageText = nil
                 performSubviewRemoval(view, animated: false)
             }

             if let nameText = item.ctxChatNameLayout, !hiddenMessage {
                 let current: ChatListInlineText
                 if let view = self.chatNameText {
                     current = view
                 } else {
                     current = ChatListInlineText()
                     self.chatNameText = current
                     self.contentView.addSubview(current.view)
                 }
                 current.set(text: nameText, context: item.context, decreaseAvatar: 4)

             } else if let view = self.chatNameTextView {
                 self.chatNameText = nil
                 performSubviewRemoval(view, animated: false)
             }
             
             if let nameText = item.ctxForumTopicNameLayout, !hiddenMessage {
                 let current: ChatListTextLayer
                 if let view = self.forumTopicTextView {
                     current = view
                 } else {
                     current = ChatListTextLayer()
                     current.updateScale(backingScaleFactor)
                     self.forumTopicTextView = current
                     self.contentView.layer?.addSublayer(current)
                 }
                 current.update(nameText)
                 
             } else if let view = self.forumTopicTextView {
                 self.forumTopicTextView = nil
                 ChatListTextLayer.remove(view, animated: false)
             }
             
             if item.hasForumIcon, !hiddenMessage {
                 let current: ForumTopicArrow
                 if let view = self.forumTopicNameIcon {
                     current = view
                 } else {
                     current = ForumTopicArrow(frame: NSMakeRect(0, 0, 8, 18))
                     self.forumTopicNameIcon = current
                     self.contentView.addSubview(current)
                 }
                 current.update(item, animated: animated)
             } else if let view = self.forumTopicNameIcon {
                 self.forumTopicNameIcon = nil
                 performSubviewRemoval(view, animated: false)
             }
             
             if let layout = item.topicsLayout {
                 let current: TopicNameAndTextView
                 if let view = self.topicsView {
                     current = view
                 } else {
                     current = .init(frame: layout.size.bounds)
                     self.topicsView = current
                     self.contentView.addSubview(current)
                 }
                 current.update(context: item.context, item: layout, highlighted: item.isSelected && item.selectedForum != item.peerId, animated: animated)
             } else if let view = self.topicsView {
                 performSubviewRemoval(view, animated: false)
                 self.topicsView = nil
             }
             
             
            
             
             if !item.photos.isEmpty {
                 
                 if let first = item.photos.first, let video = first.image.videoRepresentations.first {
                    
                     let equal = videoRepresentation?.resource.id == video.resource.id
                     
                     if !equal {
                                                  
                         self.photoVideoView?.removeFromSuperview()
                         self.photoVideoView = nil
                         
                         self.photoVideoView = MediaPlayerView(backgroundThread: true)
                         
                         
                         photo.addSubview(self.photoVideoView!, positioned: .above, relativeTo: self.photo.avatar)

                         self.photoVideoView!.isEventLess = true
                         
                         self.photoVideoView!.frame = self.photo.bounds

                         
                         let file = TelegramMediaFile(fileId: MediaId(namespace: 0, id: 0), partialReference: nil, resource: video.resource, previewRepresentations: first.image.representations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: "video/mp4", size: video.resource.size, attributes: [], alternativeRepresentations: [])
                         
                         
                         let reference: MediaResourceReference
                         
                         if let peer = item.peer, let peerReference = PeerReference(peer) {
                             reference = MediaResourceReference.avatar(peer: peerReference, resource: file.resource)
                         } else {
                             reference = MediaResourceReference.standalone(resource: file.resource)
                         }
                         let userLocation: MediaResourceUserLocation
                         if let id = item.peer?.id {
                             userLocation = .peer(id)
                         } else {
                             userLocation = .other
                         }
                         
                         let mediaPlayer = MediaPlayer(postbox: item.context.account.postbox, userLocation: userLocation, userContentType: .avatar, reference: reference, streamable: true, video: true, preferSoftwareDecoding: false, enableSound: false, fetchAutomatically: true)
                         
                         mediaPlayer.actionAtEnd = .loop(nil)
                         
                         self.photoVideoPlayer = mediaPlayer
                         
                         if let seekTo = video.startTimestamp {
                             mediaPlayer.seek(timestamp: seekTo)
                         }
                         mediaPlayer.attachPlayerView(self.photoVideoView!)
                         self.videoRepresentation = video
                         updatePlayerIfNeeded()
                     }
                 } else {
                     self.photoVideoPlayer = nil
                     self.photoVideoView?.removeFromSuperview()
                     self.photoVideoView = nil
                     self.videoRepresentation = nil
                 }
             } else {
                 self.photoVideoPlayer = nil
                 self.photoVideoView?.removeFromSuperview()
                 self.photoVideoView = nil
                 self.videoRepresentation = nil
             }
             
             self.photoVideoView?.layer?.cornerRadius = item.isForum ? 10 : self.photo.frame.height / 2

             
            
            self.currentMediaPreviewSpecs = item.contentImageSpecs
            
            var validMediaIds: [MessageId] = []
            for (message, media, mediaSize) in item.contentImageSpecs {
                
                validMediaIds.append(message.id)
                let previewView: ChatListMediaPreviewView
                if let current = self.mediaPreviewViews[message.id] {
                    previewView = current
                } else {
                    previewView = ChatListMediaPreviewView(context: item.context, message: message, media: media)
                    self.mediaPreviewViews[message.id] = previewView
                    self.contentView.addSubview(previewView)
                }
                previewView.updateLayout(size: mediaSize)
            }
            var removeMessageIds: [MessageId] = []
            for (messageId, itemView) in self.mediaPreviewViews {
                if !validMediaIds.contains(messageId) {
                    removeMessageIds.append(messageId)
                    itemView.removeFromSuperview()
                }
            }
            for messageId in removeMessageIds {
                self.mediaPreviewViews.removeValue(forKey: messageId)
            }

            if item.isCollapsed != wasHidden {
                expandView?.change(pos: NSMakePoint(0, item.isCollapsed ? 0 : item.height), animated: animated)
                containerView.change(pos: NSMakePoint(0, item.isCollapsed ? -item.height : 0), animated: !revealActionInvoked && animated)
            }

            
            
            
            
            containerView.item = item
            if self.animatedView != nil && self.animatedView?.stableId != item.stableId {
                self.animatedView?.removeFromSuperview()
                self.animatedView = nil
            }
             
             switch item.mode {
             case let .topic(_, data):
                 
                 if item.titleMode == .normal {
                     let value: CGFloat = item.appearMode == .short && !item.shouldHideContent ? 20 : 30
                     let size = NSMakeSize(value, value)
                     let current: InlineStickerItemLayer
                     let forumIconFile = ForumUI.makeIconFile(title: data.info.title, iconColor: data.info.iconColor, isGeneral: item.mode.isGeneralTopic)
                     let textColor = isSelect ? theme.colors.underSelectedColor : theme.colors.accent
                     let checkFileId = data.info.icon ?? forumIconFile.fileId.id
                     if let layer = self.inlineTopicPhotoLayer, layer.fileId == checkFileId, layer.size == size, layer.textColor == textColor {
                         current = layer
                     } else {
                         if let layer = inlineTopicPhotoLayer {
                             performSublayerRemoval(layer, animated: false)
                             self.inlineTopicPhotoLayer = nil
                         }
                         if let fileId = data.info.icon {
                             current = .init(account: item.context.account, inlinePacksContext: item.context.inlinePacksContext, emoji: .init(fileId: fileId, file: nil, emoji: ""), size: size, playPolicy: .framesCount(1), textColor: textColor)
                         } else {
                             current = .init(account: item.context.account, file: forumIconFile, size: size, playPolicy: .framesCount(1))
                         }
                         self.inlineTopicPhotoLayer = current
                     }
                     
                     if item.shouldHideContent {
                         current.frame = CGRect(origin: NSMakePoint(20, 20), size: size)
                         current.superview = containerView
                         self.containerView.layer?.addSublayer(current)
                     } else {
                         if item.appearMode == .short {
                             current.frame = CGRect(origin: NSMakePoint(10, item.margin), size: size)
                         } else {
                             current.frame = CGRect(origin: NSMakePoint(10, 12), size: size)
                         }
                         current.superview = contentView
                         self.contentView.layer?.addSublayer(current)
                     }
                     photo.isHidden = true
                 } else {
                     if let layer = inlineTopicPhotoLayer {
                         performSublayerRemoval(layer, animated: animated)
                         self.inlineTopicPhotoLayer = nil
                     }
                     photo.isHidden = false
                 }
             default:
                 if let layer = inlineTopicPhotoLayer {
                     performSublayerRemoval(layer, animated: animated)
                     self.inlineTopicPhotoLayer = nil
                 }
                 photo.isHidden = false
             }
            
            
            photo.setState(account: item.context.account, state: item.photo)

            if item.isAnonynousSavedMessage {
                self.archivedPhoto?.removeFromSuperview()
                self.archivedPhoto = nil
                let icon = theme.icons.chat_hidden_author
                photo.setState(account: item.context.account, state: .Empty)
                photo.setSignal(generateEmptyPhoto(photo.frame.size, type: .icon(colors: theme.colors.peerColors(5), icon: icon, iconSize: icon.backingSize.aspectFitted(NSMakeSize(photo.frame.size.width - 5, photo.frame.size.height - 5)), cornerRadius: nil), bubble: false) |> map {($0, false)})
            } else if item.isSavedMessage, case .savedMessages = item.mode {
                self.archivedPhoto?.removeFromSuperview()
                self.archivedPhoto = nil
                let icon = theme.icons.chat_my_notes
                photo.setState(account: item.context.account, state: .Empty)
                photo.setSignal(generateEmptyPhoto(photo.frame.size, type: .icon(colors: theme.colors.peerColors(5), icon: icon, iconSize: icon.backingSize.aspectFitted(NSMakeSize(photo.frame.size.width - 5, photo.frame.size.height - 5)), cornerRadius: nil), bubble: false) |> map {($0, false)})
            } else if item.isSavedMessage {
                self.archivedPhoto?.removeFromSuperview()
                self.archivedPhoto = nil
                let icon = theme.icons.searchSaved
                photo.setState(account: item.context.account, state: .Empty)
                photo.setSignal(generateEmptyPhoto(photo.frame.size, type: .icon(colors: theme.colors.peerColors(5), icon: icon, iconSize: icon.backingSize.aspectFitted(NSMakeSize(photo.frame.size.width - 20, photo.frame.size.height - 20)), cornerRadius: item.displayAsTopics ? 20 : nil), bubble: false) |> map {($0, false)})
            } else if item.isRepliesChat {
                self.archivedPhoto?.removeFromSuperview()
                self.archivedPhoto = nil
                let icon = theme.icons.chat_replies_avatar
                photo.setState(account: item.context.account, state: .Empty)
                photo.setSignal(generateEmptyPhoto(photo.frame.size, type: .icon(colors: theme.colors.peerColors(5), icon: icon, iconSize: icon.backingSize.aspectFitted(NSMakeSize(photo.frame.size.width - 22, photo.frame.size.height - 22)), cornerRadius: nil), bubble: false) |> map {($0, false)})
            } else if case .ArchivedChats = item.photo {
                if self.archivedPhoto == nil {
                    self.archivedPhoto = LAnimationButton(animation: "archiveAvatar", size: NSMakeSize(46, 46), offset: NSMakeSize(0, 0))
                    photo.addSubview(self.archivedPhoto!, positioned: .above, relativeTo: self.photo.avatar)
                }
                self.archivedPhoto?.frame = self.photo.photoRect
                self.archivedPhoto?.userInteractionEnabled = false
                self.archivedPhoto?.set(keysToColor: ["box2.box2.Fill 1"], color: item.hideStatus?.isHidden == false ? theme.colors.revealAction_accent_background : theme.colors.grayForeground)
                self.archivedPhoto?.background = item.hideStatus?.isHidden == false ? theme.colors.revealAction_accent_background : theme.colors.grayForeground

                let animateArchive = item.animateArchive && animated
                if animateArchive {
                    archivedPhoto?.loop()
                    if item.isCollapsed {
                        self.expandView?.animateOnce()
                    }
                }
                self.archivedPhoto?.layer?.cornerRadius = photo.radius
                photo.setState(account: item.context.account, state: .Empty)
            } else {
                self.archivedPhoto?.removeFromSuperview()
                self.archivedPhoto = nil
            }
                     
             if let badgeNode = item.ctxBadgeNode {
                 var presented: Bool = false
                 if badgeView == nil {
                     badgeView = Control()
                     badgeView?.setAccessibilityLabel(strings().chatListContextPreview)
                     badgeView?.scaleOnClick = true
                     contentView.addSubview(badgeView!)
                     presented = true
                    badgeView?.set(handler: { [weak self] _ in
                         if let item = self?.item as? ChatListRowItem {
                             item.previewChat()
                         }
                     }, for: .Click)
                 }
                 
                 badgeView?.userInteractionEnabled = item.peerId != nil && item.canPreviewChat
                 badgeView?.setFrameSize(badgeNode.size)
                 badgeNode.aroundFill = nil
                 badgeNode.view = badgeView
                 badgeNode.setNeedDisplay()
                 
                 
                 let point = badgePoint(item)

                 if presented {
                     badgeView?.setFrameOrigin(point)
                     if animated {
                         self.badgeView?.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.4)
                         self.badgeView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                     }
                 } else {
                     badgeView?.change(pos: point, animated: animated)
                 }
             } else if let view = self.badgeView {
                 performSubviewRemoval(view, animated: animated, scale: true)
                 self.badgeView = nil
             }
             
             if item.shouldHideContent, !item.hasLiveItems, let badgeNode = item.ctxShortBadgeNode {
                 var presented: Bool = false
                 if badgeShortView == nil {
                     badgeShortView = View()
                     containerView.addSubview(badgeShortView!)
                     presented = true
                 }
                 badgeShortView?.setFrameSize(badgeNode.size)
                 badgeNode.aroundFill = _backgroundColor
                 badgeNode.view = badgeShortView
                 badgeNode.setNeedDisplay()
                 
                 let point = badgeShortPoint(item)
                 let opacity = unhideProgress.map { 1 - $0 } ?? 1

                 if presented {
                     badgeShortView?.setFrameOrigin(point)
                     badgeShortView?.change(opacity: opacity, animated: false)
                     if animated {
                         self.badgeShortView?.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.4)
                         self.badgeShortView?.layer?.animateAlpha(from: 0, to: opacity, duration: 0.2)
                     }
                 } else {
                     badgeShortView?.change(pos: point, animated: animated)
                     badgeShortView?.change(opacity: opacity, animated: animated)
                 }
             } else if let view = self.badgeShortView {
                 performSubviewRemoval(view, animated: animated, scale: true)
                 self.badgeShortView = nil
             }
             
             if item.hasActiveGroupCall, badgeShortView == nil, !item.hasLiveItems {
                 var animate: Bool = false

                 if self.groupActivityView == nil {
                     self.groupActivityView = GroupCallActivity(frame: .init(origin: .zero, size: NSMakeSize(20, 20)))
                     self.containerView.addSubview(self.groupActivityView!)
                     animate = true
                 }
                 
                 let groupActivityView = self.groupActivityView!
                 
                 groupActivityView.setFrameOrigin(photo.frame.maxX - groupActivityView.frame.width + 3, photo.frame.maxY - 18)
                 
                 let isActive = item.isSelected
                 
                 groupActivityView.update(context: item.context, tableView: item.table, foregroundColor: isActive ? theme.colors.underSelectedColor : theme.colors.accent, backgroundColor: isActive ? theme.colors.accent : _backgroundColor, animColor: isActive ? theme.colors.accent : theme.colors.underSelectedColor)
                 if animated && animate {
                     groupActivityView.layer?.animateAlpha(from: 0.5, to: 1.0, duration: 0.2)
                     groupActivityView.layer?.animateScaleSpring(from: 0.1, to: 1.0, duration: 0.3)
                 }
             } else if let view = groupActivityView {
                 performSubviewRemoval(view, animated: animated, scale: true)
                 self.groupActivityView = nil
             }
             
             if let isOnline = item.isOnline, !item.hasLiveItems {
                 if isOnline, self.badgeShortView == nil {
                     var animate: Bool = false
                     if activeImage == nil {
                         activeImage = ImageView()
                         activeImage?.isAccessibilityDecorative = true
                         self.containerView.addSubview(activeImage!, positioned: .above, relativeTo: photo)
                         animate = true
                     }
                     guard let activeImage = self.activeImage else { return }
                     activeImage.image = item.isSelected && item.context.layout != .single ? theme.icons.hintPeerActiveSelected : theme.icons.hintPeerActive
                     activeImage.sizeToFit()

                     activeImage.setFrameOrigin(photo.frame.maxX - activeImage.frame.width - 3, photo.frame.maxY - 12)

                     if animated && animate {
                         activeImage.layer?.animateAlpha(from: 0.5, to: 1.0, duration: 0.2)
                         activeImage.layer?.animateScaleSpring(from: 0.1, to: 1.0, duration: 0.3)
                     }
                 } else if let view = self.activeImage {
                     performSubviewRemoval(view, animated: animated, scale: true)
                     self.activeImage = nil
                 }
             } else {
                 activeImage?.removeFromSuperview()
                 activeImage = nil
             }
             
             if item.isPaidSubscriptionChannel, self.badgeShortView == nil {
                 var animate: Bool = false
                 let current: ImageView
                 if let view = self.starBadgeView {
                     current = view
                 } else {
                     current = ImageView()
                     current.isAccessibilityDecorative = true
                     self.starBadgeView = current
                     self.containerView.addSubview(current, positioned: .above, relativeTo: photo)
                     animate = true
                 }
                 current.image = item.isSelected && item.context.layout != .single ? theme.icons.avatar_star_badge_active : theme.icons.avatar_star_badge
                 current.sizeToFit()

                 let avatarFrame = self.photo.frame
                 let avatarBadgeSize = current.frame.size
                 let avatarBadgeFrame = CGRect(origin: CGPoint(x: avatarFrame.maxX - avatarBadgeSize.width + 4, y: avatarFrame.maxY - avatarBadgeSize.height), size: avatarBadgeSize)

                 
                 current.frame = avatarBadgeFrame

                 if animated && animate {
                     current.layer?.animateAlpha(from: 0.5, to: 1.0, duration: 0.2)
                     current.layer?.animateScaleSpring(from: 0.1, to: 1.0, duration: 0.3)
                 }
             } else if let view = self.starBadgeView {
                 performSubviewRemoval(view, animated: animated, scale: true)
                 self.starBadgeView = nil
             }

             if item.showsCommunityDropdown, item.context.layout != .minimisize {
                 var animate: Bool = false
                 let current: ImageButton
                 if let view = self.communityDropdown {
                     current = view
                 } else {
                     current = ImageButton()
                     current.setAccessibilityLabel(strings().communityViewTitle)
                     current.autohighlight = false
                     current.scaleOnClick = true
                     current.set(image: TelegramThemeHooks.shared.image(.iconCommunityAvatarDropdown).precomposed(), for: .Normal)
                     current.sizeToFit()
                     current.setGlassEffect(forceAppearance: .forceLight)
                     current.set(handler: { [weak self] _ in
                         (self?.item as? ChatListRowItem)?.openCommunityPreview()
                     }, for: .Click)
                     self.communityDropdown = current
                     self.containerView.addSubview(current, positioned: .above, relativeTo: photo)
                     animate = true
                 }
                 let avatarFrame = self.photo.frame
                 let badgeSize = current.frame.size
                 current.setFrameOrigin(NSMakePoint(round(avatarFrame.maxX - badgeSize.width + 2), round(avatarFrame.maxY - badgeSize.height + 2)))
                 if animated && animate {
                     current.layer?.animateAlpha(from: 0.5, to: 1.0, duration: 0.2)
                     current.layer?.animateScaleSpring(from: 0.1, to: 1.0, duration: 0.3)
                 }
             } else if let view = self.communityDropdown {
                 performSubviewRemoval(view, animated: animated, scale: true)
                 self.communityDropdown = nil
             }

             if item.communityHidden {
                 let current: ImageView
                 if let view = self.communityHiddenView {
                     current = view
                 } else {
                     current = ImageView()
                     current.isAccessibilityDecorative = true
                     self.communityHiddenView = current
                     self.containerView.addSubview(current, positioned: .above, relativeTo: photo)
                 }
                 let selected = item.isSelected && item.context.layout != .single
                 current.image = generateCommunityHiddenIcon(backgroundColor: selected ? theme.colors.accentSelect : theme.colors.background, iconColor: selected ? theme.colors.underSelectedColor : theme.colors.grayIcon)
                 current.sizeToFit()
                 let avatarFrame = self.photo.frame
                 let badgeSize = current.frame.size
                 current.setFrameOrigin(NSMakePoint(avatarFrame.maxX - badgeSize.width + 2, avatarFrame.maxY - badgeSize.height + 2))
             } else if let view = self.communityHiddenView {
                 performSubviewRemoval(view, animated: animated, scale: true)
                 self.communityHiddenView = nil
             }

             
             if let autoremoveTimeout = item.autoremoveTimeout, activeImage == nil, badgeShortView == nil, groupActivityView == nil, !item.hasLiveItems, !item.showsCommunityDropdown  {
                 let current: AvatarBadgeView
                 let isNew: Bool
                 if let view = self.avatarTimerBadge {
                     current = view
                     isNew = false
                 } else {
                     current = AvatarBadgeView(frame: CGRect())
                     self.avatarTimerBadge = current
                     self.containerView.addSubview(current, positioned: .above, relativeTo: photo)
                     isNew = true
                 }
                 let avatarFrame = self.photo.frame
                 
                 let avatarBadgeSize = CGSize(width: avatarTimerBadgeDiameter, height: avatarTimerBadgeDiameter)
                 current.update(size: avatarBadgeSize, text: shortTimeIntervalString(value: autoremoveTimeout))
                 let avatarBadgeFrame = CGRect(origin: CGPoint(x: avatarFrame.maxX - avatarBadgeSize.width + 3, y: avatarFrame.maxY - avatarBadgeSize.height), size: avatarBadgeSize)
                 
                 
                 current.frame = avatarBadgeFrame
                 
                 if isNew, animated {
                     current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                     current.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.2)
                 }
                 
                 photo.callContentUpdater()
                 
             } else if let view = self.avatarTimerBadge {
                 performSubviewRemoval(view, animated: animated, scale: true)
                 self.avatarTimerBadge = nil
             }
             
             if item.showsMentionSlot {
                 
                 let highlighted = self.highlighed
                 let icon: CGImage
                 if item.hasGramBadge {
                     icon = chatListGramBadgeIcon(highlighted: highlighted, muted: item.badgeMuted)
                 } else if item.associatedGroupId == .root {
                     icon = highlighted ? theme.icons.chatListMentionActive : theme.icons.chatListMention
                 } else {
                     icon = highlighted ? theme.icons.chatListMentionArchivedActive : theme.icons.chatListMentionArchived
                 }
                 
                 var presented: Bool = false
                 if self.mentionsView == nil {
                     self.mentionsView = ImageView()
                     self.mentionsView?.isAccessibilityDecorative = true
                     self.contentView.addSubview(self.mentionsView!)
                     presented = true
                 }
                 
                 self.mentionsView?.image = icon
                 self.mentionsView?.sizeToFit()
                 
                 let point = mentionPoint(item)
                 
                 if presented {
                     self.mentionsView?.setFrameOrigin(point)
                     if animated {
                         self.mentionsView?.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.4)
                         self.mentionsView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                     }
                 } else {
                     self.mentionsView?.change(pos: point, animated: animated)
                 }
             } else if let view = mentionsView {
                 performSubviewRemoval(view, animated: animated, scale: true)
                 self.mentionsView = nil
             }
             
             if let _ = item.reactionsCount {
                 
                 let highlighted = self.highlighed
                 let icon: CGImage
                 if item.associatedGroupId == .root {
                     icon = highlighted ? theme.icons.reactions_badge_active : theme.icons.reactions_badge
                 } else {
                     icon = highlighted ? theme.icons.reactions_badge_archive_active : theme.icons.reactions_badge_archive
                 }
                 
                 var presented: Bool = false
                 if self.reactionsView == nil {
                     self.reactionsView = ImageView()
                     self.reactionsView?.isAccessibilityDecorative = true
                     self.contentView.addSubview(self.reactionsView!)
                     presented = true
                 }
                                  
                 self.reactionsView?.image = icon
                 self.reactionsView?.sizeToFit()
                 
                 let point = reactionsPoint(item)

                 if presented {
                     self.reactionsView?.setFrameOrigin(point)
                     if animated {
                         self.reactionsView?.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.4)
                         self.reactionsView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                     }
                 } else {
                     self.reactionsView?.change(pos: point, animated: animated)
                 }
             } else if let view = self.reactionsView {
                 performSubviewRemoval(view, animated: animated, scale: true)
                 self.reactionsView = nil
             }

             if let _ = item.pollVotesCount {

                 let highlighted = self.highlighed
                 let icon: CGImage
                 if item.associatedGroupId == .root {
                     icon = highlighted ? theme.icons.chatListPollBadgeActive : theme.icons.chatListPollBadge
                 } else {
                     icon = highlighted ? theme.icons.chatListPollBadgeArchivedActive : theme.icons.chatListPollBadgeArchived
                 }

                 var presented: Bool = false
                 if self.pollVotesView == nil {
                     self.pollVotesView = ImageView()
                     self.pollVotesView?.isAccessibilityDecorative = true
                     self.contentView.addSubview(self.pollVotesView!)
                     presented = true
                 }

                 self.pollVotesView?.image = icon
                 self.pollVotesView?.sizeToFit()

                 let point = pollVotesPoint(item)

                 if presented {
                     self.pollVotesView?.setFrameOrigin(point)
                     if animated {
                         self.pollVotesView?.layer?.animateScaleSpring(from: 0.1, to: 1, duration: 0.4)
                         self.pollVotesView?.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                     }
                 } else {
                     self.pollVotesView?.change(pos: point, animated: animated)
                 }
             } else if let view = self.pollVotesView {
                 performSubviewRemoval(view, animated: animated, scale: true)
                 self.pollVotesView = nil
             }

             if let tags = item.tags {
                 let current: ChatListTagsView
                 if let view = self.tagsView {
                     current = view
                 } else {
                     current = ChatListTagsView(frame: NSMakeRect(0, 0, 100, tags.tags[0].size.height))
                     self.contentView.addSubview(current)
                     self.tagsView = current
                     
                 }
                 current.update(items: tags.effective, item: item, animated: animated)
             } else if let view = self.tagsView {
                 performSubviewRemoval(view, animated: animated)
                 self.tagsView = nil
             }

            
             if let peerId = item.peerId, item.forumTopicItems.isEmpty {
                let activities = item.activities.map {
                    ($0.peer.peer, $0.activity)
                }
                self.inputActivities = (peerId, activities)
            } else {
                self.inputActivities = nil
            }
             
             
             photo.scaleOnClick = true
             let transition: ContainedViewLayoutTransition = animated ? .animated(duration: 0.2, curve: .easeOut) : .immediate

             if let component = item.avatarStoryIndicator {
                 
                 
                 self.photo.update(component: component, availableSize: NSMakeSize(44, 44), transition: transition)
                 
                 self.photoVideoView?._change(size: NSMakeSize(44, 44), animated: animated)
                 self.archivedPhoto?._change(size: NSMakeSize(44, 44), animated: animated)

                 self.photoVideoView?._change(pos: NSMakePoint(3, 3), animated: animated)
                 self.archivedPhoto?._change(pos: NSMakePoint(3, 3), animated: animated)
                 
                 
                 if let photoVideoView = photoVideoView {
                     photoVideoView.layer?.cornerRadius = item.isForum ? 10 : photoVideoView.frame.height / 2
                 }
                 self.archivedPhoto?.layer?.cornerRadius = photo.radius

             } else {
                 self.photoVideoView?._change(size: NSMakeSize(50, 50), animated: animated)
                 self.archivedPhoto?._change(size: NSMakeSize(50, 50), animated: animated)
                 
                 self.photoVideoView?._change(pos: NSMakePoint(0, 0), animated: animated)
                 self.archivedPhoto?._change(pos: NSMakePoint(0, 0), animated: animated)
                 
                 if let photoVideoView = photoVideoView {
                     photoVideoView.layer?.cornerRadius = item.isForum ? 10 : photoVideoView.frame.height / 2
                 }
                 self.archivedPhoto?.layer?.cornerRadius = photo.radius
                 self.photo.update(component: nil, availableSize: NSMakeSize(44, 44), transition: transition)
             }
             
             
             if let openMiniApp = item.ctxOpenMiniApp {
                 let current: TextView
                 if let view = self.openMiniApp {
                     current = view
                 } else {
                     current = TextView()
                     current.isSelectable = false
                     current.scaleOnClick = true
                     self.openMiniApp = current
                     contentView.addSubview(current)
                 }
                 current.update(openMiniApp)
                 current.backgroundColor = item.isActiveSelected ? theme.colors.underSelectedColor : theme.colors.accent
                 current.setFrameSize(openMiniApp.layoutSize.bounds.insetBy(dx: -8, dy: -4).size)
                 current.layer?.cornerRadius = current.frame.height / 2
                 
                 current.setSingle(handler: { [weak item] _ in
                     item?.openWebApp()
                 }, for: .Click)
                 
             } else if let view = openMiniApp {
                 performSubviewRemoval(view, animated: animated)
                 self.openMiniApp = nil
             }
             
             if  item.hasLiveItems {
                 let current: ImageView
                 if let view = liveStreamView {
                     current = view
                 } else {
                     current = ImageView()
                     current.isAccessibilityDecorative = true
                     self.liveStreamView = current
                     photo.addSubview(current)
                 }
                 current.image = ChatUIHooks.shared.generateLiveStreamBadge(9.5, highlighed ? theme.colors.accent : theme.colors.background)
                 current.sizeToFit()
             } else if let view = liveStreamView {
                 performSubviewRemoval(view, animated: animated)
                 self.liveStreamView = nil
             }
             
         }
        
        
        
        if let _ = endRevealState {
            initRevealState()
        }
        
        contentView.needsLayout = true
        revealActionInvoked = false
        contentView.needsDisplay = true
        needsLayout = true
        
    }
    
    public func initRevealState() {
        guard let item = item as? ChatListRowItem, endRevealState == nil else {return}
        
        revealLeftView.removeAllSubviews()
        revealRightView.removeAllSubviews()
        
        revealLeftView.backgroundColor = backdorColor
        revealRightView.backgroundColor = backdorColor
        
        _ = NSMakeSize(frame.height - 20, frame.height - 20)
        _ = NSMakeSize(frame.height, frame.height)
        _ = NSFont.medium(11)
        
        if item.groupId == .root {

            let titleColor = theme.colors.text

            let unreadBackground = !item.markAsUnread ? theme.colors.revealAction_inactive_background : theme.colors.revealAction_accent_background

            let unread = ChatListRevealActionView(animation: !item.markAsUnread ? "anim_read" : "anim_unread", title: !item.markAsUnread ? strings().chatListSwipingRead : strings().chatListSwipingUnread, tintColor: unreadBackground, titleColor: titleColor, autoplaySide: .right, keysToColor: !item.markAsUnread ? nil : ["Oval.Oval.Stroke 1"])

            let mute = ChatListRevealActionView(animation: item.isMuted ? "anim_unmute" : "anim_mute", title: item.isMuted ? strings().chatListSwipingUnmute : strings().chatListSwipingMute, tintColor: theme.colors.revealAction_neutral2_background, titleColor: titleColor, autoplaySide: .right, keysToColor: item.isMuted ? nil : ["un Outlines.Group 1.Stroke 1"])

            let pin = ChatListRevealActionView(animation: !item.isPinned ? "anim_pin" : "anim_unpin", title: !item.isPinned ? strings().chatListSwipingPin : strings().chatListSwipingUnpin, tintColor: theme.colors.revealAction_constructive_background, titleColor: titleColor, autoplaySide: .left, keysToColor: !item.isPinned ? nil : ["un Outlines.Group 1.Stroke 1"])
            
            pin.set(handler: { [weak self] _ in
                guard let item = self?.item as? ChatListRowItem else {return}
                item.togglePinned()
                self?.endRevealState = nil
            }, for: .Click)
            unread.set(handler: { [weak self] _ in
                guard let item = self?.item as? ChatListRowItem else {return}
                item.toggleUnread()
                self?.endRevealState = nil
            }, for: .Click)
            
            
            
            
            
            
            let isUnarchive = item.associatedGroupId != .root
            let archive = ChatListRevealActionView(animation: isUnarchive ? "anim_unarchive" : "anim_archive", title: isUnarchive ? strings().chatListSwipingUnarchive : strings().chatListSwipingArchive, tintColor: theme.colors.revealAction_inactive_background, titleColor: titleColor, autoplaySide: .left, keysToColor: ["box2.box2.Fill 1"], compactIcon: isUnarchive)

            let delete = ChatListRevealActionView(animation: "anim_delete", title: strings().chatListSwipingDelete, tintColor: theme.colors.revealAction_destructive_background, titleColor: titleColor, autoplaySide: .left)
            
            
            archive.set(handler: { [weak self] _ in
                guard let item = self?.item as? ChatListRowItem else {return}
                self?.endRevealState = nil
                item.toggleArchive()
            }, for: .Click)
            
            mute.set(handler: { [weak self] _ in
                guard let item = self?.item as? ChatListRowItem else {return}
                self?.endRevealState = nil
                item.toggleMuted()
            }, for: .Click)
            
            delete.set(handler: { [weak self] _ in
                guard let item = self?.item as? ChatListRowItem else {return}
                self?.endRevealState = nil
                item.delete()
            }, for: .Click)
            
            if item.isTopic, let peer = item.peer as? TelegramChannel {
                if peer.hasPermission(.pinMessages) {
                    revealRightView.addSubview(pin)
                }
            } else {
                revealRightView.addSubview(pin)
            }

            if (item.isTopic && item.canDeleteTopic) || !item.isTopic {
                revealRightView.addSubview(delete)
            }
            
            if item.filter == .allChats, !item.isTopic {
                revealRightView.addSubview(archive)
            } else if item.isTopic {
                revealRightView.addSubview(mute, positioned: .below, relativeTo: revealRightView.subviews.first)
            }
            
            
            if !item.isTopic, item.canToggleUnread {
                revealLeftView.addSubview(unread)
                revealLeftView.backgroundColor = .clear
            }
            
            unread.setFrameSize(NSMakeSize(unread.idealWidth, frame.height))
            mute.setFrameSize(NSMakeSize(mute.idealWidth, frame.height))
            archive.setFrameSize(NSMakeSize(archive.idealWidth, frame.height))
            pin.setFrameSize(NSMakeSize(pin.idealWidth, frame.height))
            delete.setFrameSize(NSMakeSize(delete.idealWidth, frame.height))

            layoutRevealActions(in: revealRightView)
            layoutRevealActions(in: revealLeftView)

            revealRightView.backgroundColor = .clear

            revealRightView.setFrameSize(rightRevealWidth, frame.height)
            revealLeftView.setFrameSize(leftRevealWidth, frame.height)
        } else {
            
            
            let collapse = ChatListRevealActionView(animation: "anim_hide", title: strings().chatListRevealActionCollapse, tintColor: theme.colors.revealAction_inactive_background, titleColor: theme.colors.text, autoplaySide: .left, keysToColor: ["Path 2.Path 2.Fill 1"])

            collapse.setFrameSize(collapse.idealWidth, frame.height)
            revealRightView.addSubview(collapse)
            revealRightView.backgroundColor = .clear
            layoutRevealActions(in: revealRightView)
            revealRightView.setFrameSize(rightRevealWidth, frame.height)
            
            collapse.set(handler: { [weak self] _ in
                guard let item = self?.item as? ChatListRowItem else {return}
                item.collapseOrExpandArchive()
                self?.endRevealState = nil
            }, for: .Click)
            
            
            
            if let hideStatus = item.hideStatus {

                let hideOrPin: ChatListRevealActionView

                switch hideStatus {
                case .hidden:
                    hideOrPin = ChatListRevealActionView(animation: "anim_hide", title: strings().chatListRevealActionPin, tintColor: theme.colors.revealAction_accent_background, titleColor: theme.colors.text, autoplaySide: .left, rotated: true, keysToColor: ["Path 2.Path 2.Fill 1"])
                default:
                    hideOrPin = ChatListRevealActionView(animation: "anim_hide", title: strings().chatListRevealActionHide, tintColor: theme.colors.revealAction_inactive_background, titleColor: theme.colors.text, autoplaySide: .left, rotated: false, keysToColor: ["Path 2.Path 2.Fill 1"])
                }

                hideOrPin.setFrameSize(hideOrPin.idealWidth, frame.height)
                revealLeftView.addSubview(hideOrPin)
                revealLeftView.backgroundColor = .clear
                layoutRevealActions(in: revealLeftView)
                revealLeftView.setFrameSize(leftRevealWidth, frame.height)

                hideOrPin.set(handler: { [weak self] _ in
                    guard let item = self?.item as? ChatListRowItem else {return}
                    item.toggleHideArchive()
                    self?.endRevealState = nil
                }, for: .Click)

            }


        }
        updateRevealViewsAttachment()
    }

    public var additionalRevealDelta: CGFloat {
        let additionalDelta: CGFloat
        if let state = endRevealState {
            switch state {
            case .left:
                additionalDelta = -leftRevealWidth
            case .right:
                additionalDelta = rightRevealWidth
            case .none:
                additionalDelta = 0
            }
        } else {
            additionalDelta = 0
        }
        return additionalDelta
    }
    
    public var containerX: CGFloat {
        return containerView.frame.minX
    }
    
    public var width: CGFloat {
        return containerView.frame.width
    }

    private static let revealActionInset: CGFloat = 6

    private func layoutRevealActions(in container: View) {
        let inset = ChatListRowView.revealActionInset
        let width = revealActionWidth(of: container)
        var x: CGFloat = inset * 2
        for subview in container.subviews {
            subview.setFrameSize(NSMakeSize(width, subview.frame.height))
            subview.setFrameOrigin(x, 0)
            x += width + inset
        }
    }

    private func revealActionWidth(of container: View) -> CGFloat {
        var maxW: CGFloat = 0
        for subview in container.subviews {
            let w: CGFloat
            if let action = subview as? ChatListRevealActionView {
                w = action.idealWidth
            } else {
                w = subview.frame.width
            }
            maxW = max(maxW, w)
        }
        return maxW
    }

    private func revealWidth(of container: View) -> CGFloat {
        if container.subviews.isEmpty { return 0 }
        let n = CGFloat(container.subviews.count)
        let w = revealActionWidth(of: container)
        let inset = ChatListRowView.revealActionInset
        return n * w + (n - 1) * inset + 4 * inset
    }

    public var rightRevealWidth: CGFloat {
        return revealWidth(of: revealRightView)
    }
    
    public var leftRevealWidth: CGFloat {
        return revealWidth(of: revealLeftView)
    }
    
    private var animateOnceAfterDelta: Bool = true
    private var revealHighlighted: Bool = false
    public func moveReveal(delta: CGFloat) {
        let delta = revealLeftView.subviews.isEmpty ? min(delta, 0) : delta

        if !revealHighlighted, delta != 0, let item = item as? ChatListRowItem, !item.isSelected, let table = item.table {
            _ = table.highlight(item: item)
            revealHighlighted = true
        }

        layoutReveal(delta: delta)
    }

    private func layoutReveal(delta: CGFloat) {
        if revealLeftView.subviews.isEmpty && revealRightView.subviews.isEmpty {
            initRevealState()
        }
      
        self.internalDelta = delta

        containerView.change(pos: NSMakePoint(delta, containerView.frame.minY), animated: false)
        revealLeftView.change(pos: NSMakePoint(min(-leftRevealWidth + delta, 0), revealLeftView.frame.minY), animated: false)
        revealRightView.change(pos: NSMakePoint(frame.width + delta, revealRightView.frame.minY), animated: false)
        
        
        revealLeftView.change(size: NSMakeSize(max(leftRevealWidth, delta), revealLeftView.frame.height), animated: false)
        
        revealRightView.change(size: NSMakeSize(max(rightRevealWidth, abs(delta)), revealRightView.frame.height), animated: false)

        let inset = ChatListRowView.revealActionInset

        
        if delta > 0, !revealLeftView.subviews.isEmpty {
            let action = revealLeftView.subviews.last!
            
            let subviews = revealLeftView.subviews
            let leftPercent: CGFloat = max(min(delta / leftRevealWidth, 1), 0)

            if delta > frame.width - (frame.width / 3) {
                if animateOnceAfterDelta {
                    animateOnceAfterDelta = false
                    action.layer?.animatePosition(from: NSMakePoint(-(revealLeftView.frame.width - action.frame.width - inset * 2), action.frame.minY), to: NSMakePoint(0, 0), duration: 0.2, timingFunction: CAMediaTimingFunctionName.spring, removeOnCompletion: true, additive: true)

                    for i in 0 ..< subviews.count - 1 {
                        let action = revealLeftView.subviews[i]
                        action.layer?.animatePosition(from: NSMakePoint(-(action.frame.width + inset), action.frame.minY), to: NSMakePoint(0, 0), duration: 0.2, timingFunction: CAMediaTimingFunctionName.spring, removeOnCompletion: true, additive: true)
                    }

                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
                }

                for i in 0 ..< subviews.count - 1 {
                    revealLeftView.subviews[i].setFrameOrigin(NSMakePoint(revealLeftView.frame.width, 0))
                }

                action.setFrameOrigin(NSMakePoint(revealLeftView.frame.width - action.frame.width - inset * 2, action.frame.minY))


            } else {

                 if !animateOnceAfterDelta {
                    animateOnceAfterDelta = true
                    action.layer?.animatePosition(from: NSMakePoint(revealLeftView.frame.width - action.frame.width - inset * 2 - (leftRevealWidth - action.frame.width), action.frame.minY), to: NSMakePoint(0, 0), duration: 0.2, timingFunction: CAMediaTimingFunctionName.spring, removeOnCompletion: true, additive: true)

                    for i in stride(from: revealLeftView.subviews.count - 1, to: 0, by: -1) {
                        let action = revealLeftView.subviews[i]
                        action.layer?.animatePosition(from: NSMakePoint(action.frame.width + inset, action.frame.minY), to: NSMakePoint(0, 0), duration: 0.2, timingFunction: CAMediaTimingFunctionName.spring, removeOnCompletion: true, additive: true)
                    }

                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .drawCompleted)
                }
                var restX: CGFloat = inset * 2
                for subview in subviews.reversed() {
                    subview.setFrameOrigin(NSMakePoint(restX * leftPercent, 0))
                    restX += subview.frame.width + inset
                }
            }
        }
        
        var rightPercent: CGFloat = delta / rightRevealWidth
        if rightPercent < 0, !revealRightView.subviews.isEmpty {
            rightPercent = 1 - min(1, abs(rightPercent))
            let subviews = revealRightView.subviews
            

            let action = subviews.last!
            
            if rightPercent == 0 , delta < 0 {
                if delta + action.frame.width * CGFloat(max(1, revealRightView.subviews.count - 1)) - 35 < -frame.midX {
                    if animateOnceAfterDelta {
                        animateOnceAfterDelta = false
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        action.layer?.animatePosition(from: NSMakePoint((revealRightView.frame.width - rightRevealWidth), action.frame.minY), to: NSMakePoint(0, 0), duration: 0.2, timingFunction: CAMediaTimingFunctionName.spring, removeOnCompletion: true, additive: true)
                        
                        for i in 0 ..< subviews.count - 1 {
                            subviews[i].layer?.animatePosition(from: NSMakePoint((subviews[i].frame.width * CGFloat(i + 1)), subviews[i].frame.minY), to: NSMakePoint(0, 0), duration: 0.2, timingFunction: CAMediaTimingFunctionName.spring, removeOnCompletion: true, additive: true)
                        }
                        
                    }
                    
                    for i in 0 ..< subviews.count - 1 {
                         subviews[i].setFrameOrigin(NSMakePoint(-subviews[i].frame.width, 0))
                    }
                    
                    action.setFrameOrigin(NSMakePoint(0, action.frame.minY))
                    
                } else {
                    if !animateOnceAfterDelta {
                        animateOnceAfterDelta = true
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)

                        action.layer?.animatePosition(from: NSMakePoint(-(revealRightView.frame.width - rightRevealWidth), action.frame.minY), to: NSMakePoint(0, 0), duration: 0.2, timingFunction: CAMediaTimingFunctionName.spring, removeOnCompletion: true, additive: true)
                        
                        for i in 0 ..< subviews.count - 1 {
                            subviews[i].layer?.animatePosition(from: NSMakePoint(-(subviews[i].frame.width * CGFloat(i + 1)), subviews[i].frame.minY), to: NSMakePoint(0, 0), duration: 0.2, timingFunction: CAMediaTimingFunctionName.spring, removeOnCompletion: true, additive: true)
                        }
                        
                    }
                    action.setFrameOrigin(NSMakePoint((revealRightView.frame.width - action.frame.width - inset * 2), action.frame.minY))

                    for i in 0 ..< subviews.count - 1 {
                        subviews[i].setFrameOrigin(NSMakePoint(inset * 2 + CGFloat(i) * (subviews[i].frame.width + inset), 0))
                    }
                }
            } else {
                let inset = ChatListRowView.revealActionInset
                for (i, subview) in subviews.enumerated() {
                    let iF = CGFloat(i)
                    let restX = inset * 2 + iF * (subview.frame.width + inset)
                    subview.setFrameOrigin(restX * (1 - rightPercent), 0)
                }
//                subviews[0].setFrameOrigin(0, 0)
//                subviews[1].setFrameOrigin(subviews[0].frame.width - subviews[1].frame.width * rightPercent, 0)
//                subviews[2].setFrameOrigin((subviews[0].frame.width * 2) - (subviews[2].frame.width * 2) * rightPercent, 0)
            }
        }
    }
    
    public func completeReveal(direction: SwipeDirection) {
        self.endRevealState = direction

        if case .none = direction, revealHighlighted {
            revealHighlighted = false
            if let item = item as? ChatListRowItem, item.table?.isHighlighted(item) == true {
                item.table?.cancelHighlight()
            }
        }

        if revealLeftView.subviews.isEmpty || revealRightView.subviews.isEmpty {
            initRevealState()
        }

        
        let inset = ChatListRowView.revealActionInset
        let updateRightSubviews:(Bool) -> Void = { [weak self] animated in
            guard let `self` = self else {return}
            let subviews = self.revealRightView.subviews
            var x: CGFloat = inset * 2
            for subview in subviews {
                if subview != subviews.last {
                    subview._change(pos: NSMakePoint(x, 0), animated: animated, timingFunction: .spring)
                    x += subview.frame.width + inset
                } else {
                    subview._change(pos: NSMakePoint(self.rightRevealWidth - subview.frame.width - inset * 2, 0), animated: animated, timingFunction: .spring)
                }
            }
        }

        let updateLeftSubviews:(Bool) -> Void = { [weak self] animated in
            guard let `self` = self else {return}
            let subviews = self.revealLeftView.subviews
            var x: CGFloat = inset * 2
            for subview in subviews.reversed() {
                subview._change(pos: NSMakePoint(x, 0), animated: animated, timingFunction: .spring)
                x += subview.frame.width + inset
            }
        }
        
        let failed:(@escaping(Bool)->Void)->Void = { [weak self] completion in
            guard let `self` = self else {return}
            self.containerView.change(pos: NSMakePoint(0, self.containerView.frame.minY), animated: true, timingFunction: .spring)
            self.revealLeftView.change(pos: NSMakePoint(-self.revealLeftView.frame.width, self.revealLeftView.frame.minY), animated: true, timingFunction: .spring)
            self.revealRightView.change(pos: NSMakePoint(self.frame.width, self.revealRightView.frame.minY), animated: true, timingFunction: .spring, completion: completion)
            
            updateRightSubviews(true)
            updateLeftSubviews(true)
            self.endRevealState = nil
        }
       
        let animateRightLongReveal:(@escaping(Bool)->Void)->Void = { [weak self] completion in
            guard let `self` = self else {return}
            updateRightSubviews(true)
            self.endRevealState = nil
            let duration: Double = 0.2

            self.containerView.change(pos: NSMakePoint(-self.containerView.frame.width, self.containerView.frame.minY), animated: true, duration: duration, timingFunction: .spring)
            self.revealRightView.change(size: NSMakeSize(self.frame.width + self.rightRevealWidth, self.revealRightView.frame.height), animated: true, duration: duration, timingFunction: .spring)
            self.revealRightView.change(pos: NSMakePoint(-self.rightRevealWidth, self.revealRightView.frame.minY), animated: true, duration: duration, timingFunction: .spring, completion: completion)
            
        }
        
        
       
        
        switch direction {
        case let .left(state):
            
            if revealLeftView.subviews.isEmpty {
                failed( { [weak self] _ in
                    self?.revealRightView.removeAllSubviews()
                    self?.revealLeftView.removeAllSubviews()
                    self?.updateRevealViewsAttachment()
                } )
                return
            }
            
            switch state {
            case .success:
                
                let invokeLeftAction = containerX > frame.width - (frame.width / 3)

                let duration: Double = 0.2

                containerView.change(pos: NSMakePoint(leftRevealWidth, containerView.frame.minY), animated: true, duration: duration, timingFunction: .spring)
                revealLeftView.change(size: NSMakeSize(leftRevealWidth, revealLeftView.frame.height), animated: true, duration: duration, timingFunction: .spring)
                
                revealRightView.change(pos: NSMakePoint(frame.width, revealRightView.frame.minY), animated: true)
                updateLeftSubviews(true)
                
                var last = self.revealLeftView.subviews.last as? Control
                
                revealLeftView.change(pos: NSMakePoint(0, revealLeftView.frame.minY), animated: true, duration: duration, timingFunction: .spring, completion: { [weak self] completed in
                    if completed, invokeLeftAction {
                        last?.send(event: .Click)
                        last = nil
                        self?.needsLayout = true
                    }
                })
            case .failed:
                failed( { [weak self] _ in
                    self?.revealRightView.removeAllSubviews()
                    self?.revealLeftView.removeAllSubviews()
                    self?.updateRevealViewsAttachment()
                } )
            default:
                break
            }
        case let .right(state):
            
            if revealRightView.subviews.isEmpty {
                failed( { [weak self] _ in
                    self?.revealRightView.removeAllSubviews()
                    self?.revealLeftView.removeAllSubviews()
                    self?.updateRevealViewsAttachment()
                } )
                return
            }
            
            switch state {
            case .success:
                let invokeRightAction = containerX + revealRightView.subviews.last!.frame.minX < -frame.midX
                
                var last = self.revealRightView.subviews.last as? Control

                
                if invokeRightAction {
                    if self.revealRightView.subviews.count < 3 {
                        failed({ completed in
                            if invokeRightAction {
                                DispatchQueue.main.async {
                                    last?.send(event: .Click)
                                    last = nil
                                }
                            }
                        })
                    } else {
                        animateRightLongReveal({ completed in
                            if invokeRightAction {
                                DispatchQueue.main.async {
                                    last?.send(event: .Click)
                                    last = nil
                                }
                            }
                        })
                    }
                    
                } else {
                    revealRightView.change(pos: NSMakePoint(frame.width - rightRevealWidth, revealRightView.frame.minY), animated: true, timingFunction: .spring)
                    revealRightView.change(size: NSMakeSize(rightRevealWidth, revealRightView.frame.height), animated: true, timingFunction: .spring)
                    containerView.change(pos: NSMakePoint(-rightRevealWidth, containerView.frame.minY), animated: true, timingFunction: .spring)
                    revealLeftView.change(pos: NSMakePoint(-leftRevealWidth, revealLeftView.frame.minY), animated: true, timingFunction: .spring)
                    
                    
                    let handler = (revealRightView.subviews.last as? Control)?.removeLastHandler()
                    (revealRightView.subviews.last as? Control)?.set(handler: { control in
                        var _control:Control? = control
                        animateRightLongReveal({ completed in
                            if let control = _control {
                                DispatchQueue.main.async {
                                    handler?(control)
                                    _control = nil
                                }
                               
                            }
                        })
                    }, for: .Click)
                    
                }
               updateRightSubviews(true)
            case .failed:
                failed( { [weak self] _ in
                    self?.revealRightView.removeAllSubviews()
                    self?.revealLeftView.removeAllSubviews()
                    self?.updateRevealViewsAttachment()
                } )
            default:
                break
            }
        default:
            self.endRevealState = nil
            failed( { [weak self] _ in
                self?.revealRightView.removeAllSubviews()
                self?.revealLeftView.removeAllSubviews()
                self?.updateRevealViewsAttachment()
            } )
        }
    }
    
    deinit {
        peerInputActivitiesDisposable.dispose()
    }
    
    @objc public func updatePlayerIfNeeded() {
        _ = window != nil && window!.isKeyWindow && !NSIsEmptyRect(visibleRect)
        if photoVideoPlayer != nil {
//            if accept {
//                photoVideoPlayer.play()
//            } else {
//                photoVideoPlayer.pause()
//            }
        }
    }
        
    public func updateHideProgress(animated: Bool) {
        guard let item = self.item as? ChatListRowItem else { return }
        guard item.context.layout == item.splitState else {
            self.set(item: item, animated: animated)
            return
        }
        let progress = item.getHideProgress?()
        guard self.item === item else { return }
        contentView.change(opacity: progress ?? (item.shouldHideContent ? 0 : 1), animated: animated)
        badgeShortView?.change(opacity: progress.map { 1 - $0 } ?? 1, animated: animated)
    }
    
    
    public func badgeShortPoint(_ item: ChatListRowItem) -> NSPoint {
        if let badgeView = badgeShortView {
            let point: NSPoint
            let y = self.containerView.frame.height - badgeView.frame.height - (item.margin + 1)
            point = NSMakePoint(photo.frame.maxX - badgeView.frame.width, y)
            return point
        }
        return .zero
    }
    public func badgePoint(_ item: ChatListRowItem) -> NSPoint {
        if let badgeView = badgeView {
            let point: NSPoint
            let y = self.containerView.frame.height - badgeView.frame.height - (item.margin + 1)
            point = NSMakePoint(self.containerView.frame.width - badgeView.frame.width - item.margin, y)
            return point
        }
        return .zero
    }
    
    public func contentPoint(_ item: ChatListRowItem) -> NSPoint {
        return .zero
    }
    
    public func selectionViewRect(_ item: ChatListRowItem) -> NSRect {
        let rect = NSMakeRect(-5, 10, 10, frame.height - 20)
//        if let progress = item.getHideProgress?() {
//            return rect.scaleLinear(amount:  1 - progress)
//        } else {
//            var bp = 0
//            bp += 1
//        }
        return rect
    }
    
    public func mentionPoint(_ item: ChatListRowItem) -> NSPoint {
        let point = NSMakePoint(self.containerView.frame.width - (item.ctxBadgeNode != nil ? item.ctxBadgeNode!.size.width + item.margin : 0) - 20 - item.margin, self.contentView.frame.height - 20 - (item.margin + 1))
        return point
    }
    public func reactionsPoint(_ item: ChatListRowItem) -> NSPoint {
        let point = NSMakePoint(self.containerView.frame.width - (item.ctxBadgeNode != nil ? item.ctxBadgeNode!.size.width + item.margin : 0) - 20 - item.margin - (item.showsMentionSlot ? 20 + item.margin : 0), self.contentView.frame.height - 20 - (item.margin + 1))

        return point
    }
    public func pollVotesPoint(_ item: ChatListRowItem) -> NSPoint {
        let point = NSMakePoint(self.containerView.frame.width - (item.ctxBadgeNode != nil ? item.ctxBadgeNode!.size.width + item.margin : 0) - 20 - item.margin - (item.showsMentionSlot ? 20 + item.margin : 0) - (item.reactionsCount != nil ? 20 + item.margin : 0), self.contentView.frame.height - 20 - (item.margin + 1))
        return point
    }
    
    
    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        dateTextView?.updateScale(backingScaleFactor)
        displayNameView?.updateScale(backingScaleFactor)
        forumTopicTextView?.updateScale(backingScaleFactor)
    }

    public override func layout() {
        super.layout()
       
        guard let item = item as? ChatListRowItem else { return }
                
        photo.userInteractionEnabled = (item.avatarStoryIndicator != nil || item.showsCommunityDropdown) && item.context.layout != .minimisize && item.selectedForum == nil

        if item.context.layout == .minimisize {
            photo.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, (containerView.frame.width - photo.frame.width) / 2), 10))
        } else {
            photo.setFrameOrigin(NSMakePoint(10, 10))
        }

        if let animatedView {
            if item.context.layout == .minimisize {
                animatedView.frame = photo.frame
                animatedView.layer?.cornerRadius = animatedView.frame.height / 2
            } else {
                animatedView.frame = bounds
                animatedView.layer?.cornerRadius = 0
            }
        }
        
        expandView?.frame = NSMakeRect(0, item.isCollapsed ? 0 : item.height, frame.width - .borderSize, frame.height)
        
        
        let additionalDelta: CGFloat
        if let state = endRevealState {
            switch state {
            case .left:
                additionalDelta = -leftRevealWidth
            case .right:
                additionalDelta = rightRevealWidth
            case .none:
                additionalDelta = 0
            }
        } else {
            additionalDelta = 0
        }
        
        if item.isCollapsed {
            var bp = 0
            bp += 1
        }
        
        containerView.frame = NSMakeRect(-additionalDelta, item.isCollapsed ? -item.height : 0, frame.width - .borderSize, item.height)

        let selectionFrame: NSRect
        if item.shouldHideContent {
            selectionFrame = photo.frame.insetBy(dx: -7, dy: -7)
        } else {
            selectionFrame = containerView.bounds.insetBy(dx: 3, dy: 3)
        }
        if animateSelectionChange, !selectionBackgroundLayer.isHidden, selectionBackgroundLayer.frame != selectionFrame {
            chatListAnimateLayerFrame(selectionBackgroundLayer, to: selectionFrame)
        } else {
            selectionBackgroundLayer.frame = selectionFrame
        }

        contentView.frame = CGRect(origin: contentPoint(item), size: frame.size)
        
        revealLeftView.frame = NSMakeRect(-leftRevealWidth - additionalDelta, 0, leftRevealWidth, frame.height)
        revealRightView.frame = NSMakeRect(frame.width - additionalDelta, 0, rightRevealWidth, frame.height)
        
        
        if item.shouldHideContent {
            self.inlineTopicPhotoLayer?.frame = NSMakeRect(20, 20, 30, 30)
        } else {
            if item.appearMode == .short {
                self.inlineTopicPhotoLayer?.frame = NSMakeRect(12, item.margin + 3, 16, 16)
            } else {
                self.inlineTopicPhotoLayer?.frame = NSMakeRect(12, 15, 30, 30)
            }
        }
        
        if let badgeView = self.badgeView {
            let point = badgePoint(item)
            badgeView.setFrameOrigin(point)
        }
        if let badgeView = self.badgeShortView {
            let point = badgeShortPoint(item)
            badgeView.setFrameOrigin(point)
        }
        
        if let reactionsView = self.reactionsView {
            let point = reactionsPoint(item)
            reactionsView.setFrameOrigin(point)
        }
        
        if let mentionsView = self.mentionsView {
            let point = mentionPoint(item)
            mentionsView.setFrameOrigin(point)
        }

        if let selectionView = self.selectionView {
            selectionView.frame = selectionViewRect(item)
        }
        
        if let liveStreamView {
            liveStreamView.centerX(y: photo.frame.height - floorToScreenPixels(liveStreamView.frame.height * 0.7))
        }
        
        if let view = avatarTimerBadge {
            let avatarFrame = self.photo.frame
            let avatarBadgeSize = CGSize(width: avatarTimerBadgeDiameter, height: avatarTimerBadgeDiameter)
            let avatarBadgeFrame = CGRect(origin: CGPoint(x: avatarFrame.maxX - avatarBadgeSize.width, y: avatarFrame.maxY - avatarBadgeSize.height), size: avatarBadgeSize)
            view.frame = avatarBadgeFrame
        }

        if let view = communityDropdown {
            let avatarFrame = self.photo.frame
            let badgeSize = view.frame.size
            view.setFrameOrigin(NSMakePoint(round(avatarFrame.maxX - badgeSize.width + 2), round(avatarFrame.maxY - badgeSize.height + 2)))
        }

        if let view = communityHiddenView {
            let avatarFrame = self.photo.frame
            let badgeSize = view.frame.size
            view.setFrameOrigin(NSMakePoint(round(avatarFrame.maxX - badgeSize.width + 2), round(avatarFrame.maxY - badgeSize.height + 2)))
        }

        
        if let displayNameView = self.displayNameView {
            
            if let view = activitiesModel?.view {
                view.setFrameOrigin(item.leftInset, displayNameView.frame.height + item.margin + 3)
            }
            
           
            
            if let dateTextView = self.dateTextView {
                let dateX = contentView.frame.width - dateTextView.frame.width - item.margin
                dateTextView.position = NSMakePoint(dateX, item.margin)
            }
            
            
            var addition:CGFloat = 0
            
            if let statusControl = leftStatusControl {
                statusControl.setFrameOrigin(NSMakePoint(item.leftInset, displayNameView.frame.height - 8))
                addition += statusControl.frame.width + 2
            }
            
            if item.isSecret {
                addition += theme.icons.secretImage.backingSize.height
            }
            if item.appearMode == .short, item.isTopic {
               // addition += 20
            }
            displayNameView.position = NSMakePoint(item.leftInset + addition, item.margin - 1)
            
            var offset: CGFloat = 0
            if let chatName = item.ctxChatNameLayout {
                offset += chatName.layoutSize.height + 1
            }
            
            if let statusControl = statusControl {
                var addition:CGFloat = 0
                if item.isSecret {
                    addition += theme.icons.secretImage.backingSize.height
                }
                if let statusControl = leftStatusControl {
                    addition += statusControl.frame.width + 2
                }
                statusControl.setFrameOrigin(NSMakePoint(addition + item.leftInset + displayNameView.frame.width + 2, displayNameView.frame.height - 8))
                
                addition += statusControl.frame.width + 4
            }
            
            if let monoforumMessagesView {
                if item.isMuted {
                    addition += theme.icons.dialogMuteImage.backingSize.width + 2
                }
                if let statusControl {
                    addition += statusControl.frame.width + 2
                }
                monoforumMessagesView.setFrameOrigin(NSMakePoint(displayNameView.frame.maxX + 4 + addition, displayNameView.frame.minY + 2))
            }
            
 
            
            var inset: CGFloat = item.leftInset
            if let view = self.storyReplyImageView {
                view.setFrameOrigin(NSMakePoint(inset, displayNameView.frame.height + item.margin + 2 + offset))
                inset += view.frame.width + 2
            }
            
            var mediaPreviewOffset = NSMakePoint(inset, displayNameView.frame.height + item.margin + 2 + offset)
            let contentImageSpacing: CGFloat = 2.0
            
            if tagsView != nil {
                if let chatNameTextView = chatNameTextView {
                    mediaPreviewOffset.y -= displayNameView.frame.height
                    mediaPreviewOffset.x += chatNameTextView.frame.width + 3
                }

            }
            
            for (message, _, mediaSize) in self.currentMediaPreviewSpecs {
                if let previewView = self.mediaPreviewViews[message.id] {
                    previewView.frame = CGRect(origin: mediaPreviewOffset, size: mediaSize)
                }
                mediaPreviewOffset.x += mediaSize.width + contentImageSpacing
            }

            var messageOffset: CGFloat = 0
            if let chatNameLayout = item.ctxChatNameLayout {
                messageOffset += min(chatNameLayout.layoutSize.height, 17) + 2
            }
            let displayHeight = displayNameView.frame.height
            
            
            if let topicsView = topicsView, let layout = item.topicsLayout {
                var inset: CGPoint = .zero
                if layout.fastTrack {
                    inset.x += 5
                }
                let point = NSMakePoint(item.leftInset - inset.x, displayHeight + item.margin + 2 - inset.y)
                topicsView.frame = CGRect(origin: point, size: layout.size)
            }
            
            if let chatNameTextView = chatNameTextView {
                chatNameTextView.setFrameOrigin(NSMakePoint(item.leftInset, displayHeight + item.margin + 2))
                if let forumTopicNameIcon = forumTopicNameIcon {
                    forumTopicNameIcon.setFrameOrigin(NSMakePoint(chatNameTextView.frame.maxX + 2, displayHeight + item.margin + 2))
                }
                if let forumTopicTextView = forumTopicTextView {
                    forumTopicTextView.position = NSMakePoint(chatNameTextView.frame.maxX + 12, displayHeight + item.margin + 2)
                }
            }
            
            
            if let messageTextView = messageTextView {
                if tagsView == nil || chatNameTextView == nil {
                    messageTextView.setFrameOrigin(NSMakePoint(item.leftInset, displayHeight + item.margin + 1 + messageOffset))
                } else if let chatNameTextView = chatNameTextView {
                    let maxX = [chatNameTextView.frame, forumTopicTextView?.frame].compactMap { $0 }.map { $0.maxX + 3 }.max()
                    if let maxX = maxX {
                        messageTextView.setFrameOrigin(NSMakePoint(maxX, chatNameTextView.frame.minY))
                    }
                }
            }
        }
        
        if let tagsView = tagsView {
            tagsView.setFrameOrigin(NSMakePoint(item.leftInset, contentView.frame.height - tagsView.frame.height - 7))
        }
        
        if let openMiniApp = openMiniApp {
            
            var offset = item.margin + 1
            if (item.isPinned || item.isLastPinned) {
                offset += theme.icons.pinnedImage.systemSize.width + 5
            }
            
            openMiniApp.setFrameOrigin(NSMakePoint(frame.width - openMiniApp.frame.width - offset, frame.height - openMiniApp.frame.height - (item.margin + 1)))
        }

        updateInlineTextAnimatableContent()

        if let delta = internalDelta {
            layoutReveal(delta: delta)
        }
    }
    
    
    
}
