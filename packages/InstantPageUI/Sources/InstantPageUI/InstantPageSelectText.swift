import Cocoa
import TGUIKit
import TelegramContext
import AudioPlayerCore
import Localization
import TelegramUtils
import TelegramMediaUtils
import TelegramTheme
import Postbox
import TelegramCore
import Localization
import ColorPalette
import InAppSettings
import TelegramTheme
import TelegramMediaUtils
import TelegramMedia

import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
import RangeSet
import AVFoundation

public struct InstantPageSelectContainer {
    public let attributedString: NSAttributedString
    public init(attributedString: NSAttributedString) {
        self.attributedString = attributedString
    }
}

public class InstantPageSelectManager : NSResponder {
    
    private var ranges:[(WeakReference<InstantPageTextLine>, InstantPageSelectContainer)] = []
    public func add(line: InstantPageTextLine, attributedString: NSAttributedString) {
        ranges.append((WeakReference(value: line), InstantPageSelectContainer(attributedString: attributedString)))
    }
//
    public func removeAll() {
        for selection in ranges {
            selection.0.value?.removeSelection()
        }
        ranges.removeAll()
    }
//
//    func remove(for id:Int64) {
//        
//    }
    public var isEmpty:Bool {
        return ranges.isEmpty
    }
//
//    
    @objc public func copy(_ sender:Any) {
        
        var string:String = ""
        
        for i in 0 ..< ranges.count {
            string += ranges[i].1.attributedString.string
            if i != ranges.count - 1 {
                string += "\n"
            }
        }
        
        let pb = NSPasteboard.general
        pb.declareTypes([.string], owner: self)
        pb.setString(string, forType: .string)
        
    }
    
    public var attributedString: NSAttributedString {
        let attr: NSMutableAttributedString = NSMutableAttributedString()
        for range in ranges {
            attr.append(range.1.attributedString)
            _ = attr.append(string: "\n")
        }
        return attr
    }

    public override func becomeFirstResponder() -> Bool {
        return true
    }
    
    public override func resignFirstResponder() -> Bool {
        removeAll()
        return true
    }
}

private let instantSelectManager:InstantPageSelectManager = {
    let manager = InstantPageSelectManager()
    return manager
}()

private class InstantViewContentInteractive : InteractionContentViewProtocol {
    
    
    private let callback:(AnyHashable)->NSView?
    public init(_ callback:@escaping(AnyHashable)->NSView?) {
        self.callback = callback
    }
    public func contentInteractionView(for stableId: AnyHashable, animateIn: Bool) -> NSView? {
        return callback(stableId)
    }
    public func interactionControllerDidFinishAnimation(interactive: Bool, for stableId: AnyHashable) {
        
    }
    
    public func addAccesoryOnCopiedView(for stableId: AnyHashable, view: NSView) {
        
    }
    public func videoTimebase(for stableId: AnyHashable) -> CMTimebase? {
        return nil
    }
    public func applyTimebase(for stableId: AnyHashable, timebase: CMTimebase?) {
        
    }
}

public class InstantPageSelectText : NSObject {
    
    private var beginInnerLocation:NSPoint = NSMakePoint(-1, -1)
    private var endInnerLocation:NSPoint = NSMakePoint(-1, -1)
    private let scroll:ScrollView
    private var started:Bool = false
    private var interactive: InstantViewContentInteractive?
    
    public init(_ scroll:ScrollView) {
        self.scroll = scroll
    }
    
    private func deepItemsInRect(_ rect: NSRect, itemsInRect:@escaping(NSRect)->[InstantPageItem], effectiveRectForItem:@escaping(InstantPageItem)-> NSRect) -> [(InstantPageItem, InstantPageTableItem?, InstantPageDetailsItem?)] {
        return itemsInRect(rect).reduce([], { (current, item) -> [(InstantPageItem, InstantPageTableItem?, InstantPageDetailsItem?)] in
            var current = current
            if let item = item as? InstantPageTableItem {
                var itemRect = effectiveRectForItem(item)
                let view = findView(item, self.scroll.documentView) as? InstantPageScrollableView
                if let view = view {
                    itemRect.origin.x -= view.documentOffset.x - item.horizontalInset
                }
                current += item.itemsIn(NSMakeRect(rect.minX - itemRect.minX, rect.minY - itemRect.minY, 1, 1)).map {($0, Optional(item), nil)}
            } else if let item = item as? InstantPageDetailsItem, item.isExpanded {
                let itemRect = effectiveRectForItem(item)
                current += item.itemsIn(NSMakeRect(rect.minX - itemRect.minX, rect.minY - itemRect.minY, 1, 1)).map {($0, nil, Optional(item))}
            } else {
                current += [(item, nil, nil)]
            }
            return current
        })
    }
    
    private func findView(_ item: InstantPageItem, _ currentView: NSView?) -> NSView? {
        if let currentView = currentView {
            for (_, subview) in currentView.subviews.enumerated() {
                if let subview = subview as? InstantPageView, item.matchesView(subview) {
                    return subview as? NSView
                } else if let subview = subview as? InstantPageDetailsView {
                    if let view = findView(item, subview.contentView) as? InstantPageView, item.matchesView(view) {
                        return view as? NSView
                    }
                }
            }
        }
        return nil
    }
    
    public func initializeHandlers(for window:Window, instantLayout: InstantPageLayout, instantPage: InstantPage, context: (any AccountContextProtocol), updateLayout: @escaping()->Void, openUrl:@escaping(InstantPageUrlItem) -> Void, itemsInRect:@escaping(NSRect) -> [InstantPageItem], effectiveRectForItem:@escaping(InstantPageItem)-> NSRect) {
        window.removeAllHandlers(for: self)
        

        
        window.set(mouseHandler: { [weak self, weak window] event -> KeyHandlerResult in
            
            
            let isInDocument = self?.scroll.documentView?.isInnerView(window?.contentView?.hitTest(event.locationInWindow)) ?? false
            
            self?.started = false
            if isInDocument {
                _ = window?.makeFirstResponder(nil)
                if let scroll = self?.scroll, let superview = scroll.superview, let documentView = scroll.documentView, let window = window {
                    let point = superview.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                    let documentPoint = documentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                    if !NSPointInRect(point, scroll.frame) {
                        self?.beginInnerLocation = NSZeroPoint
                    } else {
                        self?.beginInnerLocation = documentPoint
                    }
                    self?.started = self?.beginInnerLocation != NSZeroPoint
                    updateLayout()
                }
            }
            return .invokeNext
            
        }, with: self, for: .leftMouseDown, priority: .modal)
        
        window.set(mouseHandler: { [weak self, weak window] event -> KeyHandlerResult in
            
            self?.started = false
            let isInDocument = self?.scroll.documentView?.isInnerView(window?.contentView?.hitTest(event.locationInWindow)) ?? false
            if isInDocument {
                if self?.scroll.documentView != nil {
                    if !instantSelectManager.isEmpty {
                        let textView = BaseTextView()
                        textView.isSelectable = false
                        textView.isEditable = false
                        textView.isFieldEditor = false
                        textView.textStorage?.setAttributedString(instantSelectManager.attributedString)

                    }
                }
            }
            
            return .invokeNext
        }, with: self, for: .rightMouseDown, priority: .modal)
        
        window.set(mouseHandler: { [weak self, weak window] event -> KeyHandlerResult in
            
            let isInDocument = self?.scroll.documentView?.isInnerView(window?.contentView?.hitTest(event.locationInWindow)) ?? false
            
            guard isInDocument, let `self` = self else {
                return .rejected
            }
            
            let result: KeyHandlerResult
            
            self.beginInnerLocation = NSZeroPoint

            let point = self.scroll.documentView?.convert(event.locationInWindow, from: nil) ?? NSZeroPoint
            
             _ = window?.makeFirstResponder(instantSelectManager)
            
            
            let rect = NSMakeRect(point.x, point.y, 1.0, 1.0)
            
            let item = self.deepItemsInRect(rect, itemsInRect: itemsInRect, effectiveRectForItem: effectiveRectForItem).last
            
            if let item = item {
                if let textItem = item.0 as? InstantPageTextItem {
                    let itemRect: NSRect
                    if let tableItem = item.1 {
                        let effectiveRect = effectiveRectForItem(item.1!)
                        let skipCells = tableItem.itemFrameSkipCells(textItem, effectiveRect: effectiveRect)
                        itemRect = rect.offsetBy(dx: -skipCells.minX, dy: -skipCells.minY)
                    } else if let detailsItem = item.2 {
                        let effectiveRect = detailsItem.effectiveRect
                        let r = NSMakeRect(rect.minX - effectiveRect.minX, rect.minY - effectiveRect.minY, 1, 1).offsetBy(dx: 0, dy: -detailsItem.titleHeight)
                        itemRect = detailsItem.deepRect(r).offsetBy(dx: -item.0.frame.minX, dy: -item.0.frame.minY)
                    } else {
                        let effectiveRect = effectiveRectForItem(textItem)
                        itemRect = rect.offsetBy(dx: -effectiveRect.minX, dy: -effectiveRect.minY)
                    }
                    
                    if event.clickCount == 1, instantSelectManager.isEmpty {
                        if let link = textItem.linkAt(point: itemRect.origin) {
                            openUrl(link)
                            result = .rejected
                        } else {
                            result = .invokeNext
                        }
                    } else if event.clickCount == 2, item.1 == nil  {
                        instantSelectManager.removeAll()
                        for line in textItem.lines {
                            
                            var minX:CGFloat = item.0.frame.minX
                            switch textItem.alignment {
                            case .center:
                                minX += floorToScreenPixels(System.backingScale, (item.0.frame.width - line.frame.width) / 2)
                            default:
                                break
                            }
                            
                            let beginX = point.x - minX
                            if line.frame.intersects(itemRect.offsetBy(dx: -itemRect.minX, dy: 0)) {
                                instantSelectManager.add(line: line, attributedString: line.selectWord(in: NSMakePoint(beginX, 0), boundingWidth: textItem.frame.width, alignment: textItem.alignment, rect: itemRect))
                            }
                        }
                        result = .rejected
                    } else if (event.clickCount == 3 && item.1 == nil) || (event.clickCount == 2 && item.1 != nil) {
                        instantSelectManager.removeAll()
                        for line in textItem.lines {
                            instantSelectManager.add(line: line, attributedString: line.selectText(in: NSMakeRect(0, 0, line.frame.width, 1), boundingWidth: textItem.frame.width, alignment: textItem.alignment))
                        }
                        result = .rejected
                    } else {
                        result = .invokeNext
                    }
                } else {
                    
                    
                    if item.0.isInteractive {
                        
                        let items:[InstantPageItem]
                        if let details = item.2 {
                            let itemRect = effectiveRectForItem(details)
                            items = details.deepItemsInRect(NSMakeRect(rect.minX - itemRect.minX, rect.minY - itemRect.minY, 1, 1).offsetBy(dx: 0, dy: -details.titleHeight)).filter({$0.isInteractive})
                        } else {
                            items = instantLayout.items.filter({$0.isInteractive})
                        }
                        
                        let medias:[InstantPageMedia] = instantLayout.deepMedias
                        let item = item.0
                        
                       
                        
                        self.interactive = InstantViewContentInteractive({ [weak self] stableId in
                            if let index = stableId.base as? Int, let `self` = self {
                                if let media = medias.first(where: {$0.index == index}) {
                                    if let item = items.first(where: {$0.medias.contains(media)}) {
                                        return self.findView(item, self.scroll.documentView)
                                    }
                                }
                            }
                            return nil
                        })
                        
                        var index = medias.firstIndex(of: item.medias.first!)!
                        
                        let view = self.interactive?.contentInteractionView(for: AnyHashable(index), animateIn: false)
                        
                        if let view = view as? InstantPageSlideshowView {
                            index += view.indexOfDisplayedSlide
                        }
                        
                        if let file = medias[index].media as? TelegramMediaFile, file.isMusic || file.isVoice {
                            
                            if view?.hitTest(point) is RadialProgressView, let view = view as? InstantPageAudioView {
                                if view.controller != nil {
                                    _ = view.controller?.playOrPause()
                                } else {
                                    let audio = APSingleResourceController(context: context, wrapper: view.wrapper, streamable: true)
                                    view.controller = audio
                                    audio.start()
                                }
                            }
                            return .invokeNext
                        } else if let map = medias[index].media as? TelegramMediaMap {
                            LinkHooks.shared.openExternalLink("https://maps.google.com/maps?q=\(String(format:"%f", map.latitude)),\(String(format:"%f", map.longitude))", false)
                            return .rejected
                        }
                        
                        if let v = view?.hitTest(point) as? RadialProgressView {
                            switch v.state {
                            case .Fetching:
                                return .invokeNext
                            case .Remote:
                                return .invokeNext
                            default:
                                break
                            }
                        }
                        
                        
                        InstantPageHooks.shared.showGallery(context, medias, index, self.interactive)
                        
                        result = .rejected
                        
                    } else {
                        if let media = item.0.medias.first {
                            if let webpage = media.media as? TelegramMediaWebpage {
                                switch webpage.content {
                                case let .Loaded(content):
                                    LinkHooks.shared.openExternalLink(content.url, false)
                                    result = .rejected
                                default:
                                     result = .invokeNext
                                }
                            } else {
                                 result = .invokeNext
                            }
                        } else {
                             result = .invokeNext
                        }
                    }
                }
            } else {
                result = .invokeNext
            }
            
        

            
            
            
            
            if result == .invokeNext {
                Queue.mainQueue().justDispatch(updateLayout)
            } else {
                updateLayout()
            }
            
            
            return result
        }, with: self, for: .leftMouseUp, priority: .modal)
        
        window.set(mouseHandler: { [weak self, weak window] event -> KeyHandlerResult in
            
            let isInDocument = self?.scroll.documentView?.isInnerView(window?.contentView?.hitTest(event.locationInWindow)) ?? false
            
            guard isInDocument, let `self` = self else {
                return .rejected
            }
            
            let point = self.scroll.documentView?.convert(event.locationInWindow, from: nil) ?? NSZeroPoint
            
            let rect = NSMakeRect(point.x, point.y, 1.0, 1.0)
            
            for item in self.deepItemsInRect(rect, itemsInRect: itemsInRect, effectiveRectForItem: effectiveRectForItem).reversed() {
                if let textItem = item.0 as? InstantPageTextItem {
                    let itemRect: NSRect
                    if let tableItem = item.1 {
                        let effectiveRect = effectiveRectForItem(item.1!)
                        let skipCells = tableItem.itemFrameSkipCells(textItem, effectiveRect: effectiveRect)
                        itemRect = rect.offsetBy(dx: -skipCells.minX, dy: -skipCells.minY)
                    } else if let detailsItem = item.2 {
                        let effectiveRect = detailsItem.effectiveRect
                        let r = NSMakeRect(rect.minX - effectiveRect.minX, rect.minY - effectiveRect.minY, 1, 1).offsetBy(dx: 0, dy: -detailsItem.titleHeight)
                        itemRect = detailsItem.deepRect(r).offsetBy(dx: -item.0.frame.minX, dy: -item.0.frame.minY)
                    } else {
                        let effectiveRect = effectiveRectForItem(textItem)
                        itemRect = rect.offsetBy(dx: -effectiveRect.minX, dy: -effectiveRect.minY)
                    }
                    if let _ = textItem.linkAt(point: itemRect.origin) {
                        NSCursor.pointingHand.set()
                        break
                    } else if item.1 == nil {
                        NSCursor.iBeam.set()
                        break
                    } else {
                        NSCursor.arrow.set()
                    }
                } else {
                    NSCursor.arrow.set()
                }
            }
            
            
            return .invokeNext
        }, with: self, for: .mouseMoved, priority:.modal)
        
        window.set(mouseHandler: { [weak self, weak window] event -> KeyHandlerResult in
            self?.endInnerLocation = self?.scroll.documentView?.convert(event.locationInWindow, from: nil) ?? NSZeroPoint
            
            
            if self?.started == true {
                
                self?.scroll.contentView.autoscroll(with: event)
                
                if window?.firstResponder != instantSelectManager {
                    _ = window?.makeFirstResponder(instantSelectManager)
                }
                self?.runSelector(instantLayout, updateLayout: updateLayout, itemsInRect: itemsInRect, effectiveRectForItem: effectiveRectForItem)
                return .invoked
            }
            return .invokeNext
        }, with: self, for: .leftMouseDragged, priority:.modal)
    }
    
    private func runSelector(_ instantPage: InstantPageLayout, updateLayout: @escaping()->Void, itemsInRect:@escaping(NSRect) -> [InstantPageItem], effectiveRectForItem:@escaping(InstantPageItem)-> NSRect) {
        
        
        instantSelectManager.removeAll()
        
        let itemsRect = NSMakeRect(max(min(endInnerLocation.x, beginInnerLocation.x), 0), max(min(endInnerLocation.y, beginInnerLocation.y), 0), abs(endInnerLocation.x - beginInnerLocation.x), abs(endInnerLocation.y - beginInnerLocation.y))
        
        guard itemsRect.size != NSZeroSize else {
            return
        }
        
       // let items = itemsInRect(itemsRect).compactMap { $0 as? InstantPageTextItem }
        

        let reversed = endInnerLocation.y < beginInnerLocation.y
        
        

//        let lines = items.reduce([]) { (current, item) -> [InstantPageTextLine] in
//            let itemRect = effectiveRectForItem(item)
//
//            let rect = NSMakeRect(itemRect.minX, itemsRect.minY < itemRect.minY ? 0 : itemsRect.minY - itemRect.minY, itemsRect.width ,itemsRect.minY < itemRect.minY ? min(itemsRect.maxY - itemRect.minY, itemRect.height) : itemsRect.minY < itemRect.minY ? min(itemRect.maxY - itemsRect.minY, itemRect.height) : itemsRect.height)
//
//            let lines = item.lines.filter { line in
//                return line.frame.intersects(rect)
//            }
//
//            return current + lines
//        }
//
//
        let items = itemsInRect(itemsRect).reduce([], { (current, item) -> [(InstantPageItem, InstantPageTableItem?, InstantPageDetailsItem?)] in
            var current = current

            let itemRect = effectiveRectForItem(item)
            let rect = NSMakeRect(itemsRect.minX - itemRect.minX, itemsRect.minY - itemRect.minY, itemsRect.width, itemsRect.height)
            if let item = item as? InstantPageTextItem {
                current += [(item, nil, nil)]
            } else if let item = item as? InstantPageDetailsItem, item.isExpanded {
                current += item.itemsIn(rect).map {($0, nil, Optional(item))}
            }
            return current
        })
        
       // let items = deepItemsInRect(itemsRect, itemsInRect: itemsInRect, effectiveRectForItem: effectiveRectForItem)
        
        var lines:[(InstantPageTextLine, InstantPageTextItem)] = []
        
        for item in items {
            if let textItem = item.0 as? InstantPageTextItem {
                var itemRect: NSRect
                 if let detailsItem = item.2 {
                    let effectiveRect = detailsItem.effectiveRect
                    let r = NSMakeRect(itemsRect.minX - effectiveRect.minX, itemsRect.minY - effectiveRect.minY, itemsRect.width, itemsRect.height).offsetBy(dx: 0, dy: -detailsItem.titleHeight)
                    itemRect = detailsItem.deepRect(r).offsetBy(dx: -item.0.frame.minX, dy: -item.0.frame.minY)
                } else {
                    let effectiveRect = effectiveRectForItem(textItem)
                    itemRect = itemsRect.offsetBy(dx: -effectiveRect.minX, dy: -effectiveRect.minY)
                }
                
                for line in textItem.lines {
                    switch textItem.alignment {
                    case .center:
                        itemRect.origin.x -= floorToScreenPixels(System.backingScale, (textItem.frame.width - line.frame.width) / 2)
                    case .right:
                        itemRect.origin.x = textItem.frame.width - itemRect.origin.x
                    default:
                        break
                    }
                    if line.frame.intersects(itemRect.insetBy(dx: -itemRect.minX, dy: 0)) {
                        lines.append((line, textItem))
                    }
                }
            }
        }
        
        for i in 0 ..< lines.count  {
            let line = lines[i].0
            let item = lines[i].1
            let alignment = item.alignment
            
            var minX:CGFloat = item.frame.minX
            switch alignment {
            case .center:
                minX += floorToScreenPixels(System.backingScale, (item.frame.width - line.frame.width) / 2)
            case .right:
                minX = item.frame.width - minX
            default:
                break
            }
            
            let selectedText:NSAttributedString
            
            let beginX = beginInnerLocation.x - minX
            let endX = endInnerLocation.x - minX
            
            let firstLine: InstantPageTextLine = reversed ? lines.last!.0 : lines.first!.0
            let endLine: InstantPageTextLine = !reversed ? lines.last!.0 : lines.first!.0
            let multiple: Bool = lines.count > 1
            
            if firstLine === line {
                if !reversed {
                    if multiple {
                        selectedText = line.selectText(in: NSMakeRect(beginX, 0, item.frame.width - beginX, 0), boundingWidth: item.frame.width, alignment: alignment)
                    } else {
                        selectedText = line.selectText(in: NSMakeRect(beginX, 0, endX - beginX, 0), boundingWidth: item.frame.width, alignment: alignment)
                    }
                } else {
                    if multiple {
                        selectedText = line.selectText(in: NSMakeRect(0, 0, beginX, 0), boundingWidth: item.frame.width, alignment: alignment)
                    } else {
                        selectedText = line.selectText(in: NSMakeRect(endX, 0, beginX - endX, 0), boundingWidth: item.frame.width, alignment: alignment)
                    }
                }
                
            } else if endLine === line {
                if !reversed {
                    selectedText = line.selectText(in: NSMakeRect(0, 0, endX, 0), boundingWidth: item.frame.width, alignment: alignment)
                } else {
                    selectedText = line.selectText(in: NSMakeRect(endX, 0, item.frame.maxX - endX, 0), boundingWidth: item.frame.width, alignment: alignment)
                }
            } else {
                selectedText = line.selectText(in: NSMakeRect(0, 0, item.frame.width, 0), boundingWidth: item.frame.width, alignment: alignment)
            }
            
            instantSelectManager.add(line: line, attributedString: selectedText)
        }

        updateLayout()
        
    }
    
    
    public func removeHandlers(for window:Window) {
        window.removeAllHandlers(for: self)
    }
    
}
