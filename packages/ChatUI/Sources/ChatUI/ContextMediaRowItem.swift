import Cocoa
import TGUIKit
import TelegramCore
import TelegramMedia
import SwiftSignalKit
import Postbox
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import ChatHistoryModel
import InlineMediaGrid

public final class ContextMediaArguments {
    public let sendResult: (ChatContextResultCollection?, ChatContextResult, NSView) -> Void
    public let menuItems: (TelegramMediaFile, NSView) -> Signal<[ContextMenuItem], NoError>
    public let openMessage: (Message) -> Void
    public let messageMenuItems: (Message, NSView) -> Signal<[ContextMenuItem], NoError>
    public var drag: ((ChatContextResult, NSPoint, Bool) -> Bool)?

    public init(sendResult: @escaping(ChatContextResultCollection?, ChatContextResult, NSView) -> Void = { _, _, _ in }, menuItems: @escaping(TelegramMediaFile, NSView) -> Signal<[ContextMenuItem], NoError> = { _, _ in return .single([]) }, openMessage: @escaping(Message) -> Void = { _ in }, messageMenuItems:@escaping (Message, NSView) -> Signal<[ContextMenuItem], NoError> = { _, _ in return .single([]) }) {
        self.sendResult = sendResult
        self.menuItems = menuItems
        self.openMessage = openMessage
        self.messageMenuItems = messageMenuItems
    }
}

public class ContextMediaRowItem: TableRowItem {

    deinit {
        var bp = 0
        bp += 1
    }
    
    public let result:InputMediaContextRow
    private let _index1:Int64
    public let context: any AccountContextProtocol
    public let arguments: ContextMediaArguments
    public let collection: ChatContextResultCollection?
    private let _stableId: AnyHashable?
    public override var stableId: AnyHashable {
        if let _stableId = _stableId {
            return _stableId
        } else {
            return _index1
        }
    }
    
    public init(_ initialSize: NSSize, _ result:InputMediaContextRow, _ index:Int64, _ context: any AccountContextProtocol, _ arguments: ContextMediaArguments, collection: ChatContextResultCollection? = nil, stableId: AnyHashable? = nil) {
        self.result = result
        self.arguments = arguments
        self._index1 = index
        self.context = context
        self.collection = collection
        self._stableId = stableId
        dif = 0
        super.init(initialSize)
    }
    
    public override var height: CGFloat {
        var height:CGFloat = 120
        for size in result.sizes {
             height = min(height, size.height)
        }
        return height
    }
    
    public func contains(_ messageId: MessageId) -> Bool {
        if self.result.messages.contains(where: { $0.id == messageId }) {
            return true
        }
        return false
    }
    
    public override func viewClass() -> AnyClass {
        return ContextMediaRowView.self
    }

    public override var accessibilityLabel: String? {
        return strings().voiceOverChatMediaResults
    }
    
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        var inset:CGFloat = 0
        var i:Int = 0
        for size in result.sizes {
            if location.x > inset && location.x < inset + size.width {
                if !result.messages.isEmpty {
                    if let view = self.view {
                        let items = arguments.messageMenuItems(result.messages[i], view.subviews[i])
                        return items
                    }
                } else {
                    switch result.results[i] {
                    case let .internalReference(values):
                        if let file = values.file, let view = self.view {
                            let items = arguments.menuItems(file, view.subviews[i])
                            return items
                        }
                    default:
                        break
                    }
                }
                break
            }
            inset += size.width
            i += 1
        }
        return .single([])
    }
    
}

private var dif:CGFloat = 0

public class ContextMediaRowView: TableRowView, ModalPreviewRowViewProtocol {
   
    
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        var bp = 0
        bp += 1
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private let stickerFetchedDisposable:MetaDisposable = MetaDisposable()
    private let longDisposable = MetaDisposable()
    private var dragStart: (NSPoint, Int)?
    private var isDraggingResult = false
    deinit {
        stickerFetchedDisposable.dispose()
        longDisposable.dispose()
    }
    
    public func previewMediaIfPossible() -> Bool {
        if let item = self.item as? ContextMediaRowItem, let table = item.table, let window = window as? Window {
            startModalPreviewHandle(table, window: window, context: item.context)
        }
        return true
    }
    
    public override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        
        let signal = Signal<NoValue, NoError>.complete() |> delay(0.2, queue: .mainQueue())
        
        let downIndex = self.index(at: convert(event.locationInWindow, to: nil))

        isDraggingResult = false
        if let item = item as? ContextMediaRowItem, item.result.messages.isEmpty, let index = self.index(at: convert(event.locationInWindow, from: nil)) {
            dragStart = (event.locationInWindow, index)
        } else {
            dragStart = nil
        }
        
        longDisposable.set(signal.start(completed: { [weak self] in
            guard let `self` = self, let window = self.window else {
                return
            }
            let nextIndex = self.index(at: self.convert(window.mouseLocationOutsideOfEventStream, to: nil))
            if nextIndex == downIndex {
                _ = self.previewMediaIfPossible()
            }
        }))
    }
    
    
    public override func forceClick(in location: NSPoint) {
        if mouseInside() == true {
            let result = previewMediaIfPossible()
            if !result {
                super.forceClick(in: location)
            }
        } else {
            super.forceClick(in: location)
        }
        
    }
    
    public func fileAtPoint(_ point: NSPoint) -> (QuickPreviewMedia, NSView?)? {
        guard let item = item as? ContextMediaRowItem else {return nil}
        for i in 0 ..< self.subviews.count {
            if NSPointInRect(point, self.subviews[i].frame) {
                switch item.result.entries[i] {
                case let .gif(_, file):
                    return (.file(file, GifPreviewModalView.self), self.subviews[i])
                case let .sticker(_, file):
                    let reference = file.stickerReference != nil ? FileMediaReference.stickerPack(stickerPack: file.stickerReference!, media: file) : FileMediaReference.standalone(media: file)
                    if file.isAnimatedSticker || file.isWebm {
                        return (.file(reference, AnimatedStickerPreviewModalView.self), self.subviews[i])
                    } else {
                        return (.file(reference, StickerPreviewModalView.self), self.subviews[i])
                    }
                default:
                    break
                }
            }
        }
        return nil
    }
    
    public override func interactionContentView(for innerId: AnyHashable, animateIn: Bool) -> NSView {
        if let innerId = innerId.base as? MessageId {
            let view = self.subviews.first(where: {
                ($0 as? GIFContainerView)?.associatedMessageId == innerId
            })
            return view ?? self
        }
        return self
    }
    
    public override var backdorColor: NSColor {
        return .clear
    }
    

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)

        guard let item = item as? ContextMediaRowItem else { return }

        // 1) Trim extra subviews cleanly
        while subviews.count > item.result.entries.count {
            subviews.last?.removeFromSuperview()
        }

        // 2) Reusable helper: ensure view at index is of the expected type
        @discardableResult
        func ensureView<T: NSView>(at index: Int, make: @autoclosure () -> T) -> T {
            if index < subviews.count, let v = subviews[index] as? T {
                return v
            }
            // If there is a view at index but wrong type, replace it
            if index < subviews.count {
                let wrong = subviews[index]
                let v = make()
                replaceSubview(wrong, with: v)
                return v
            } else {
                let v = make()
                addSubview(v)
                return v
            }
        }

        var inset: CGFloat = 0

        for (i, entry) in item.result.entries.enumerated() {
            let targetSize = item.result.sizes[i]

            switch entry {
            case let .gif(_, file):
                let view: GIFContainerView = ensureView(at: i, make: GIFContainerView())
                let effectiveFile = file
                view.update(
                    with: effectiveFile,
                    size: NSMakeSize(targetSize.width, item.height),
                    viewSize: targetSize,
                    context: item.context,
                    table: item.table
                )
                view.userInteractionEnabled = false
                view.background = .clear
                view.frame.origin = NSPoint(x: inset, y: 0)
                inset += targetSize.width

            case let .sticker(_, file):
                if file.isAnimatedSticker {
                    let view: MediaAnimatedStickerView = ensureView(at: i, make: MediaAnimatedStickerView(frame: .zero))
                    view.backgroundColor = .clear
                    let size = NSMakeSize(round(targetSize.width), round(targetSize.height))
                    view.update(
                        with: file,
                        size: size,
                        context: item.context,
                        parent: nil,
                        table: item.table,
                        parameters: nil,
                        animated: false,
                        positionFlags: nil,
                        approximateSynchronousValue: false
                    )
                    view.userInteractionEnabled = false
                    view.background = .clear
                    view.setFrameOrigin(NSPoint(x: inset, y: 0))
                    view.setFrameSize(size)
                    inset += targetSize.width
                } else {
                    let view: TransformImageView = ensureView(at: i, make: TransformImageView(frame: .zero))
                    view.setSignal(
                        chatMessageSticker(
                            postbox: item.context.account.postbox,
                            file: stickerPackFileReference(file),
                            small: true,
                            scale: backingScaleFactor,
                            fetched: true
                        )
                    )
                    let imageSize = targetSize.aspectFitted(NSMakeSize(item.height, item.height - 8))
                    view.set(arguments: TransformImageArguments(
                        corners: ImageCorners(),
                        imageSize: imageSize,
                        boundingSize: imageSize,
                        intrinsicInsets: NSEdgeInsets()
                    ))
                    view.setFrameSize(imageSize)
                    view.background = .clear
                    view.setFrameOrigin(NSPoint(x: inset, y: 0))
                    inset += targetSize.width
                }

            case let .photo(data):
                let view: TransformImageView = ensureView(at: i, make: TransformImageView(frame: .zero))
                let imageSize = targetSize
                let displayDims = data.representationForDisplayAtSize(.init(imageSize))?.dimensions.size ?? imageSize
                let arguments = TransformImageArguments(
                    corners: ImageCorners(),
                    imageSize: displayDims,
                    boundingSize: imageSize,
                    intrinsicInsets: NSEdgeInsets()
                )

                // Try cached first
                view.setSignal(signal: cachedMedia(media: data, arguments: arguments, scale: backingScaleFactor), clearInstantly: true)

                if !view.isFullyLoaded {
                    // Fallback fetch and cache
                    view.setSignal(
                        chatWebpageSnippetPhoto(
                            account: item.context.account,
                            imageReference: ImageMediaReference.standalone(media: data),
                            scale: backingScaleFactor,
                            small: false
                        ),
                        clearInstantly: true,
                        cacheImage: { result in
                            cacheMedia(result, media: data, arguments: arguments, scale: System.backingScale)
                        }
                    )
                }

                _ = chatMessagePhotoInteractiveFetched(
                    account: item.context.account,
                    imageReference: ImageMediaReference.standalone(media: data)
                ).start()

                view.set(arguments: arguments)
                view.setFrameSize(imageSize)
                view.center() // preserves original behavior
                view.background = .clear
                view.setFrameOrigin(NSPoint(x: inset, y: 0))
                inset += targetSize.width
            }
        }

        // Defensive: if entries grew, we already appended; if they shrank, we trimmed above.
        assert(self.subviews.count == item.result.entries.count)
        needsLayout = true
    }

    public func index(at point: NSPoint) -> Int? {
        if let _ = item as? ContextMediaRowItem {
            for (i, subview) in self.subviews.enumerated() {
                if NSPointInRect(point, subview.frame) {
                    return i
                }
            }
        }
        return nil
    }
    
    public override func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        guard let item = item as? ContextMediaRowItem, let drag = item.arguments.drag, let (start, index) = dragStart, index < item.result.results.count else {
            return
        }
        let location = event.locationInWindow
        if isDraggingResult {
            _ = drag(item.result.results[index], location, false)
        } else if hypot(location.x - start.x, location.y - start.y) > 6 {
            isDraggingResult = drag(item.result.results[index], location, false)
            if isDraggingResult {
                longDisposable.set(nil)
            } else {
                dragStart = nil
            }
        }
    }

    public override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        
        longDisposable.set(nil)
        if isDraggingResult {
            isDraggingResult = false
            if let item = item as? ContextMediaRowItem, let (_, index) = dragStart, index < item.result.results.count {
                _ = item.arguments.drag?(item.result.results[index], event.locationInWindow, true)
            }
            dragStart = nil
            return
        }
        dragStart = nil
//        
        if let item = item as? ContextMediaRowItem, event.clickCount == 1  {
            let point = convert(event.locationInWindow, from: nil)
            if let index = self.index(at: point) {
                if !item.result.messages.isEmpty {
                    item.arguments.openMessage(item.result.messages[index])
                } else {
                    item.arguments.sendResult(item.collection, item.result.results[index], self.subviews[index])
                }
            }
        }
    }
    
    public override func layout() {
        super.layout()
        
        let drawn = subviews.reduce(0, { (acc, view) -> CGFloat in
            return acc + view.frame.width
        })
        if drawn < frame.width {
            dif = 2
            var inset:CGFloat = dif
            for subview in subviews {
                subview.setFrameOrigin(inset, 0)
                subview.frame = CGRect(origin: CGPoint(x: inset, y: 0), size: subview.frame.size).insetBy(dx: 1, dy: 1)
                inset += subview.frame.width + dif
            }
        }
    }
    
   
    
    
}
