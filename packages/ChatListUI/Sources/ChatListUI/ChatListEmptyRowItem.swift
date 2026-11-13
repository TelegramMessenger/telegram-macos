import TGUIKit
import Cocoa
import SwiftSignalKit
import Postbox
import TelegramCore
import Localization
import TelegramContext
import TelegramTheme
import TelegramUtils
import GeneralRows
import LocalAnimations
import ChatUI


public class ChatListEmptyRowItem: TableRowItem {
    private let _stableId: AnyHashable
    
    public override var stableId: AnyHashable {
        return _stableId
    }
    public let context: any AccountContextProtocol
    public let filter: ChatListFilter
    public let mode: PeerListMode
    public let peer: Peer?
    public let layoutState: SplitViewState
    public let hideContent: Bool
    public let hiddenByFocus: Bool
    public let openFilterSettings: (ChatListFilter)->Void
    public let createTopic:()->Void
    public let switchOffForum:()->Void
    public init(_ initialSize: NSSize, stableId: AnyHashable, filter: ChatListFilter, mode: PeerListMode, peer: Peer?, layoutState: SplitViewState, hideContent: Bool = false, hiddenByFocus: Bool = false, context: any AccountContextProtocol, openFilterSettings: @escaping(ChatListFilter)->Void, createTopic:@escaping()->Void, switchOffForum:@escaping()->Void) {
        self.context = context
        self.filter = filter
        self.mode = mode
        self.peer = peer
        self.layoutState = layoutState
        self.hideContent = hideContent
        self.hiddenByFocus = hiddenByFocus
        self.createTopic = createTopic
        self.switchOffForum = switchOffForum
        self._stableId = stableId
        self.openFilterSettings = openFilterSettings
        super.init(initialSize)
    }
    
    public var shouldHideContent: Bool {
        return hideContent || layoutState == .minimisize
    }
    
    public override var height: CGFloat {
        return remainingTableHeight(for: self)
    }
    
    public override func viewClass() -> AnyClass {
        return ChatListEmptyRowView.self
    }
    
    var text: String {
        if case .filter = filter {
            return hiddenByFocus ? chatListFocusEmptyText() : strings().chatListFilterEmpty
        }
        switch mode {
        case .forum:
            return strings().chatListEmptyForum
        default:
            return strings().chatListEmptyText
        }
    }

    public override var accessibilityLabel: String? {
        if shouldHideContent {
            return nil
        }
        return parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(.title), textColor: theme.colors.text), bold: MarkdownAttributeSet(font: .medium(.title), textColor: theme.colors.text), link: MarkdownAttributeSet(font: .normal(.title), textColor: theme.colors.link), linkAttribute: { _ in
            return nil
        })).string
    }
    
    public override var accessibilityIsSpacer: Bool {
        return shouldHideContent
    }
}


private class ChatListEmptyRowView : TableRowView {
    
    private final class ForumView: View {
        private let createTopic = TextButton()
        private var offForum: TextButton?
        required init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            createTopic.layer?.cornerRadius = 4
            createTopic.scaleOnClick = true
            createTopic.autohighlight = false
            addSubview(createTopic)
        }
        
        func update(_ peer: Peer, animated: Bool, createTopic:@escaping()->Void, switchOffForum:@escaping()->Void) {
            
            self.createTopic.set(font: .normal(.text), for: .Normal)
            self.createTopic.set(color: theme.colors.underSelectedColor, for: .Normal)
            self.createTopic.set(background: theme.colors.accent, for: .Normal)
            self.createTopic.set(text: strings().chatListEmptyCreateTopic, for: .Normal)
            self.createTopic.sizeToFit(NSMakeSize(80, 20), .zero, thatFit: false)

            
            if peer.groupAccess.isCreator {
                let current: TextButton
                if let view = self.offForum {
                    current = view
                } else {
                    current = TextButton()
                    self.offForum = current
                    addSubview(current)
                }
                current.set(font: .normal(.text), for: .Normal)
                current.set(color: theme.colors.accent, for: .Normal)
                current.set(background: theme.colors.background, for: .Normal)
                current.set(text: strings().chatListEmptyDisableForum, for: .Normal)
                current.sizeToFit(NSMakeSize(20, 10), .zero, thatFit: false)
                current.scaleOnClick = true
                current.autohighlight = false
                
            } else if let view = self.offForum {
                performSubviewRemoval(view, animated: animated)
                self.offForum = nil
            }
            
            self.createTopic.removeAllHandlers()
            self.createTopic.set(handler: { _ in
                createTopic()
            }, for: .Click)
            
            self.offForum?.removeAllHandlers()
            self.offForum?.set(handler: { _ in
                switchOffForum()
            }, for: .Click)
            
            needsLayout = true
        }
        
        override func layout() {
            super.layout()
            createTopic.centerX(y: 0)
            if let offForum = offForum {
                offForum.centerX(y: createTopic.frame.maxY + 10)
            }
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    private let disposable = MetaDisposable()
    private let textView = TextView()
    private let separator = View()
    private let sticker: MediaAnimatedStickerView = MediaAnimatedStickerView(frame: NSZeroRect)
    private var forumView: ForumView?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        textView.isSelectable = false
        
        addSubview(separator)
        addSubview(sticker)
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        
        guard let item = item as? ChatListEmptyRowItem else {
            return
        }
        
        let animatedSticker: LocalAnimatedSticker
        
        if case .allChats = item.filter {
            animatedSticker = .chiken_born
        } else {
            animatedSticker = .folder_empty
        }
        sticker.update(with: animatedSticker.file, size: NSMakeSize(112, 112), context: item.context, parent: nil, table: item.table, parameters: animatedSticker.parameters, animated: animated, positionFlags: nil, approximateSynchronousValue: false)
        
        switch item.mode {
        case .forum:
            if let peer = item.peer, item.layoutState != .minimisize, peer.groupAccess.isCreator {
                let current: ForumView
                if let view = self.forumView {
                    current = view
                } else {
                    current = ForumView(frame: NSMakeRect(0, 0, frame.width, 80))
                    self.forumView = current
                    self.addSubview(current)
                }
                current.update(peer, animated: animated, createTopic: item.createTopic, switchOffForum: item.switchOffForum)
            } else if let forumView = forumView {
                performSubviewRemoval(forumView, animated: animated)
                self.forumView = nil
            }
        default:
            if let forumView = forumView {
                performSubviewRemoval(forumView, animated: animated)
                self.forumView = nil
            }
        }
        
        needsLayout = true
    }
    
    deinit {
        disposable.dispose()
    }
    
    
    override func layout() {
        super.layout()
        
        separator.background = theme.colors.border
        
        guard let item = item as? ChatListEmptyRowItem else {
            return
        }
        
        
        let attr = parseMarkdownIntoAttributedString(item.text, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .normal(.title), textColor: theme.colors.text), bold: MarkdownAttributeSet(font: .medium(.title), textColor: theme.colors.text), link: MarkdownAttributeSet(font: .normal(.title), textColor: theme.colors.link), linkAttribute: { [weak item] contents in
            return (NSAttributedString.Key.link.rawValue, LinkHooks.shared.callbackLink(contents, { [weak item] value in
                if value == "filter", let filter = item?.filter {
                    item?.openFilterSettings(filter)
                }
               
            }))
        })).mutableCopy() as! NSMutableAttributedString
        
        
        attr.detectBoldColorInString(with: .medium(.title))
        
        let layout = TextViewLayout(attr, alignment: .center)

        layout.measure(width: frame.width - 40)
        layout.interactions = LinkHooks.shared.globalLinkExecutor()
        textView.update(layout)
        textView.center()
        
        textView.isHidden = item.shouldHideContent
        sticker.isHidden = item.shouldHideContent
        
        separator.frame = NSMakeRect(frame.width - .borderSize, 0, .borderSize, frame.height)
        
        sticker.centerX(y: textView.frame.minY - sticker.frame.height - 20)
        
        if let forumView = forumView {
            forumView.frame = NSMakeRect(30, frame.height - 80 - 40, frame.width - 60, 80)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}





public class ChatListLoadingRowItem: TableRowItem {
    private let _stableId: AnyHashable
    
    public override var stableId: AnyHashable {
        return _stableId
    }
    public let context: any AccountContextProtocol
    public let filter: ChatListFilter?
    public init(_ initialSize: NSSize, stableId: AnyHashable, filter: ChatListFilter?, context: any AccountContextProtocol) {
        self.context = context
        self.filter = filter
        self._stableId = stableId
        super.init(initialSize)
    }
    
    public override var height: CGFloat {
        return remainingTableHeight(for: self)
    }
    
    public override func viewClass() -> AnyClass {
        return ChatListLoadingRowView.self
    }
    
    public override var accessibilityLabel: String? {
        if filter != .allChats {
            return strings().chatListFilterLoading
        } else {
            return strings().voiceOverCommonLoading
        }
    }
    
    public override var accessibilityIncludesChildren: Bool {
        return false
    }
}


private class ChatListLoadingRowView : TableRowView {
    private let disposable = MetaDisposable()
    private let textView = TextView()
    private let separator = View()
    private let sticker: MediaAnimatedStickerView = MediaAnimatedStickerView(frame: NSZeroRect)
    private let indicator: ProgressIndicator = ProgressIndicator(frame: NSMakeRect(0, 0, 30, 30))
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(textView)
        textView.isSelectable = false
        
        addSubview(separator)
        addSubview(sticker)
        addSubview(indicator)
    }
    
    override var backdorColor: NSColor {
        return .clear
    }
    
    override func set(item: TableRowItem, animated: Bool = false) {
        super.set(item: item, animated: animated)
        
        
        guard let item = item as? ChatListLoadingRowItem else {
            return
        }
        
        
        if item.filter != .allChats {
            let animatedSticker: LocalAnimatedSticker = LocalAnimatedSticker.new_folder
            sticker.update(with: animatedSticker.file, size: NSMakeSize(112, 112), context: item.context, parent: nil, table: item.table, parameters: animatedSticker.parameters, animated: animated, positionFlags: nil, approximateSynchronousValue: false)
            sticker.isHidden = false
            indicator.isHidden = true
        } else {
            sticker.isHidden = true
            indicator.isHidden = false
        }
        
        needsLayout = true
    }
    
    deinit {
        disposable.dispose()
    }
    
    
    override func layout() {
        super.layout()
        
        separator.background = theme.colors.border
        
        guard let item = item as? ChatListLoadingRowItem else {
            return
        }
        
        let text: String
        if item.filter != .allChats {
            text = strings().chatListFilterLoading
        } else {
            text = strings().chatListEmptyLoading
        }
        
        let attr = NSAttributedString.initialize(string: text, color: theme.colors.text, font: .normal(.text)).mutableCopy() as! NSMutableAttributedString
        
        attr.detectBoldColorInString(with: .medium(.text))
        
        let layout = TextViewLayout(attr, alignment: .center)
        
        layout.measure(width: frame.width - 40)
        layout.interactions = LinkHooks.shared.globalLinkExecutor()
        textView.update(layout)
        textView.center()
        
        textView.isHidden = frame.width <= 70 || item.filter == .allChats
        sticker.isHidden = frame.width <= 70 || item.filter == .allChats
        
        indicator.isHidden = item.filter != .allChats
        
        separator.frame = NSMakeRect(frame.width - .borderSize, 0, .borderSize, frame.height)
        
        sticker.centerX(y: textView.frame.minY - sticker.frame.height - 20)
        indicator.center()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
