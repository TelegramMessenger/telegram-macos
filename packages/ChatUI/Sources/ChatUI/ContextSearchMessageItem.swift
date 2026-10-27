import Cocoa
import TelegramCore
import DateUtils
import TGUIKit
import Postbox
import Strings
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import AvatarUI
import MessageUtils
import MessageTextUtils
import ChatHistoryModel

public class ContextSearchMessageItem: GeneralRowItem {
    
    public let message:Message
    
    let context: any AccountContextProtocol
    let peer:Peer
    var peerId:PeerId {
        return peer.id
    }
    
    let photo: AvatarNodeState
    
   
    public override var stableId: AnyHashable {
        return message.id
    }
    
    
    private var date:NSAttributedString?

    private var displayLayout:(TextNodeLayout, TextNode)?

    private var displaySelectedLayout:(TextNodeLayout, TextNode)?
    private var dateLayout:(TextNodeLayout, TextNode)?
    private var dateSelectedLayout:(TextNodeLayout, TextNode)?

    private var displayNode:TextNode = TextNode()
    private var displaySelectedNode:TextNode = TextNode()

    private let titleText:NSAttributedString

    private var messageLayout: TextViewLayout
    private var messageSelectedLayout: TextViewLayout

    fileprivate var displayTextLayout: TextViewLayout
    fileprivate var displaySelectedTextLayout: TextViewLayout
    fileprivate var dateTextLayout: TextViewLayout?
    fileprivate var dateSelectedTextLayout: TextViewLayout?

    
    public init(_ initialSize:NSSize, context: any AccountContextProtocol, message: Message, searchText: String, action: @escaping()->Void) {
        self.context = context
        self.message = message

        
        self.peer = message.chatPeer(context.peerId)!
        
        var peer:Peer = self.peer
        
        var title:String = peer.displayTitle
        let mainPeer = coreMessageMainPeer(message)

        if let _peer = mainPeer as? TelegramChannel, case .broadcast(_) = _peer.info {
            title = _peer.displayTitle
            peer = _peer
        }
        
        
        var nameColor:NSColor = theme.chat.linkColor(true, false)
        
        if mainPeer is TelegramChannel || mainPeer is TelegramGroup {
            if let peer = mainPeer as? TelegramChannel, case .broadcast(_) = peer.info {
                nameColor = theme.chat.linkColor(true, false)
            } else if context.peerId != peer.id {
                let value = abs(Int(peer.id.id._internalGetInt64Value()) % 7)
                nameColor = ChatHistoryModelHooks.shared.peerNameColor(value)
            }
        }
        
        let titleText:NSMutableAttributedString = NSMutableAttributedString()
        let _ = titleText.append(string: title, color: nameColor, font: .medium(.text))
        titleText.setSelected(color: theme.colors.underSelectedColor ,range: titleText.range)
        
        self.titleText = titleText
        let messageTitle = NSMutableAttributedString()
        
        var text = pullText(from: message).string as String
        if text.isEmpty {
            text = serviceMessageText(message, account: context.account).0
        }
        _ = messageTitle.append(string: text, color: theme.colors.text, font: .normal(.text))
        
        let string = text
        _ = findSubstringRanges(in: string.lowercased(), query: searchText.lowercased()).0
        

        
        self.messageLayout = TextViewLayout(messageTitle.trimNewLinesToSpace, maximumNumberOfLines: 1, truncationType: .end, strokeLinks: true)
        
        
        
        
        let selectedAttrText = messageTitle.mutableCopy() as! NSMutableAttributedString
        selectedAttrText.addAttribute(.foregroundColor, value: NSColor.white, range: selectedAttrText.range)
        self.messageSelectedLayout = TextViewLayout(selectedAttrText, maximumNumberOfLines: 1, truncationType: .end, strokeLinks: true)

        
        let date:NSMutableAttributedString = NSMutableAttributedString()
        var time:TimeInterval = TimeInterval(message.timestamp)
        time -= context.timeDifference
        let range = date.append(string: DateUtils.string(forMessageListDate: Int32(time)), color: theme.colors.grayText, font: .normal(.short))
        date.setSelected(color: theme.colors.underSelectedColor, range: range)
        self.date = date.copy() as? NSAttributedString

        dateLayout = TextNode.layoutText(maybeNode: nil,  date, nil, 1, .end, NSMakeSize( .greatestFiniteMagnitude, 20), nil, false, .left)
        dateSelectedLayout = TextNode.layoutText(maybeNode: nil,  date, nil, 1, .end, NSMakeSize( .greatestFiniteMagnitude, 20), nil, true, .left)

        self.displayTextLayout = TextViewLayout(titleText, maximumNumberOfLines: 1, truncationType: .end, alwaysStaticItems: true)
        let selectedTitleText = titleText.mutableCopy() as! NSMutableAttributedString
        selectedTitleText.addAttribute(.foregroundColor, value: theme.colors.underSelectedColor, range: selectedTitleText.range)
        self.displaySelectedTextLayout = TextViewLayout(selectedTitleText, maximumNumberOfLines: 1, truncationType: .end, alwaysStaticItems: true)

        let dateCopy = date.copy() as! NSAttributedString
        self.dateTextLayout = TextViewLayout(dateCopy, maximumNumberOfLines: 1, truncationType: .end, alwaysStaticItems: true)
        let selectedDate = date.mutableCopy() as! NSMutableAttributedString
        selectedDate.addAttribute(.foregroundColor, value: theme.colors.underSelectedColor, range: selectedDate.range)
        self.dateSelectedTextLayout = TextViewLayout(selectedDate, maximumNumberOfLines: 1, truncationType: .end, alwaysStaticItems: true)

        self.photo = .PeerAvatar(peer, TelegramUtilsHooks.shared.peerLetters(peer), peer.smallProfileImage, peer.namePeerColor, message, nil, ChatHistoryModelHooks.shared.peerIsForum(peer), nil)

        super.init(initialSize, height: 44, action: action)

        _ = makeSize(initialSize.width, oldWidth: 0)
    }
    
    let margin:CGFloat = 5
    
    var titleWidth:CGFloat {
        var dateSize:CGFloat = 0
        if let dateLayout = dateLayout {
            dateSize = dateLayout.0.size.width
        }
        
        return size.width - 50 - margin * 4 - dateSize
    }
    var messageWidth:CGFloat {
        var dateSize:CGFloat = 0
        if let dateLayout = dateLayout {
            dateSize = dateLayout.0.size.width
        }
        return size.width - 70 - margin * 4 - dateSize
    }
    
    let leftInset:CGFloat = 40 + 8;
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let result = super.makeSize(width, oldWidth: oldWidth)
        if displayLayout == nil || !displayLayout!.0.isPerfectSized || self.oldWidth > width {
            displayLayout = TextNode.layoutText(maybeNode: displayNode,  titleText, nil, 1, .end, NSMakeSize(titleWidth, size.height), nil, false, .left)
        }

        messageLayout.measure(width: messageWidth)
        messageSelectedLayout.measure(width: messageWidth)

        displayTextLayout.measure(width: titleWidth)
        displaySelectedTextLayout.measure(width: titleWidth)
        dateTextLayout?.measure(width: .greatestFiniteMagnitude)
        dateSelectedTextLayout?.measure(width: .greatestFiniteMagnitude)

        if displaySelectedLayout == nil || !displaySelectedLayout!.0.isPerfectSized || self.oldWidth > width {
            displaySelectedLayout = TextNode.layoutText(maybeNode: displaySelectedNode,  titleText, nil, 1, .end, NSMakeSize(titleWidth, size.height), nil, true, .left)
        }

        return result
    }


  
    
    var ctxDisplayLayout:(TextNodeLayout, TextNode)? {
        if isSelected {
            return displaySelectedLayout
        }
        return displayLayout
    }
    var ctxMessageLayout: TextViewLayout {
        if isSelected {
            return messageSelectedLayout
        }

        return messageLayout
    }
    var ctxDateLayout:(TextNodeLayout, TextNode)? {
        if isSelected {
            return dateSelectedLayout
        }
        return dateLayout
    }

    fileprivate var ctxDisplayTextLayout: TextViewLayout {
        return isSelected ? displaySelectedTextLayout : displayTextLayout
    }
    fileprivate var ctxDateTextLayout: TextViewLayout? {
        return isSelected ? dateSelectedTextLayout : dateTextLayout
    }

    public override var instantlyResize: Bool {
        return true
    }
    

    public override func viewClass() -> AnyClass {
        return ContextSearchMessageView.self
    }

    public var isFirst: Bool {
        if let table = table {
            return table.firstItem == self
        }
        return index == 0
    }

    public override var accessibilityLabel: String? {
        return displayTextLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        let parts = [messageLayout.attributedString.string, dateTextLayout?.attributedString.string].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }
}

private class ContextSearchMessageView : GeneralRowView {


    private let titleView = TextView()
    private let messageText = TextView()
    private let dateView = TextView()
    private let separator = View()
    private let photo = AvatarControl(font: .avatar(14))
    private let selectionView = View()



    override var isFlipped: Bool {
        return true
    }




    override var backdorColor: NSColor {
        return .clear
    }

    private var selectionColor: NSColor {
        if let item = item {
            if item.isHighlighted && !item.isSelected {
                return theme.colors.grayHighlight
            } else if item.isSelected {
                return theme.chatList.selectedBackgroundColor
            }
        }
        return .clear
    }


    required init(frame frameRect: NSRect) {


        super.init(frame: frameRect)
        selectionView.userInteractionEnabled = false
        selectionView.isEventLess = true
        if #available(macOS 10.15, *) {
            selectionView.layer?.cornerCurve = .continuous
        }
        addSubview(selectionView)
        addSubview(separator)
        photo.userInteractionEnabled = false
        photo.frame = NSMakeRect(8, 8, 30, 30)
        addSubview(photo)

        titleView.userInteractionEnabled = false
        titleView.isSelectable = false
        addSubview(titleView)

        dateView.userInteractionEnabled = false
        dateView.isSelectable = false
        addSubview(dateView)

        messageText.userInteractionEnabled = false
        messageText.isSelectable = false
        addSubview(messageText)
    }

    override func layout() {
        super.layout()
        guard let item = item as? ContextSearchMessageItem else {return}
        selectionView.frame = bounds
        var mask: CACornerMask = []
        if item.isFirst && item.isLast {
            mask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        } else if item.isFirst {
            mask = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        } else if item.isLast {
            mask = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        selectionView.layer?.cornerRadius = InputContextHelper.containerCornerRadius
        selectionView.layer?.maskedCorners = mask
        separator.frame = NSMakeRect(item.leftInset, frame.height - .borderSize, frame.width - item.leftInset, .borderSize)
        separator.isHidden = item.isSelected || item.isHighlighted || item.isLast
        photo.centerY(x: 8)
        titleView.setFrameOrigin(NSMakePoint(item.leftInset, item.margin - 1))
        let dateX = frame.width - dateView.frame.width - 8
        dateView.setFrameOrigin(NSMakePoint(dateX, floor((frame.height - dateView.frame.height) / 2)))
        messageText.setFrameOrigin(item.leftInset, frame.height - messageText.frame.height - item.margin - 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }


    override func updateColors() {
        super.updateColors()
        messageText.backgroundColor = .clear
        titleView.backgroundColor = .clear
        dateView.backgroundColor = .clear
        selectionView.backgroundColor = selectionColor
        if let item = item as? ContextSearchMessageItem {
            separator.backgroundColor = theme.colors.border
            separator.isHidden = item.isSelected || item.isHighlighted || item.isLast
        } else {
            separator.backgroundColor = theme.colors.border
        }
    }


    override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)

        guard let item = item as? ContextSearchMessageItem else {return}

        var mask: CACornerMask = []
        if item.isFirst && item.isLast {
            mask = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        } else if item.isFirst {
            mask = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        } else if item.isLast {
            mask = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        selectionView.layer?.cornerRadius = InputContextHelper.containerCornerRadius
        selectionView.layer?.maskedCorners = mask
        separator.isHidden = item.isSelected || item.isHighlighted || item.isLast

        photo.setState(account: item.context.account, state: item.photo)
        titleView.update(item.ctxDisplayTextLayout)
        dateView.update(item.ctxDateTextLayout)
        messageText.update(item.ctxMessageLayout)

        self.toolTip = item.ctxMessageLayout.attributedString.string.prefixWithDots(300)
    }

}
