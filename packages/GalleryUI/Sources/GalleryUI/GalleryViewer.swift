import Cocoa
import ExternalVideoUtils
import AlertsUI
import FilePanels
import CaptureExclusion
import SwiftSignalKit
import TGUIKit
import TelegramCore
import InAppSettings
import Postbox
import AVFoundation
import ColorPalette
import Translate
import TelegramMediaPlayer
import TelegramMedia
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import ChatModeTypes
import ChatHistoryModel
import GeneralRows
import LocalAnimations
import TelegramMediaUtils
import AvatarUI
import MessageUtils
import InstantPageUI
import SecureIdUtils
import FoundationUtils
import ObjcUtils
import InputDataUI

public final class GalleryInteractions {
    public var dismiss:(NSEvent)->KeyHandlerResult = { _ in return .rejected}
    public var next:(NSEvent)->KeyHandlerResult = { _ in return .rejected}
    public var select:(MGalleryItem)->Void = { _ in}
    public var previous:(NSEvent)->KeyHandlerResult = { _ in return .rejected}
    public var showActions:(Control)->KeyHandlerResult = {_ in return .rejected}
    public var share:(Control)->Void = { _ in }
    public var contextMenu:()->ContextMenu? = {return nil}
    public var openInfo:(PeerId)->Void = {_ in}
    public var openMessage:()->Void = {}
    public var zoomIn:()->Void = {}
    public var zoomOut:()->Void = {}
    public var rotateLeft:()->Void = {}
    
    public var fastSave:()->Void = {}
    
    public var canShare:()->Bool = { true }
    
    public var invokeAd:(PeerId, AdMessageAttribute)->Void = { _, _ in }
    
    public var openLink:(String)->Void = { _ in }
}
public private(set) var viewer:GalleryViewer?

public func getGalleryViewer() -> GalleryViewer? {
    return viewer
}



private func tagsForMessage(_ message: Message) -> MessageTags? {
    for media in message.media {
        switch media {
        case _ as TelegramMediaImage:
            return .photoOrVideo
        case let file as TelegramMediaFile:
            if file.isVideo && file.isAnimated {
                return nil
            } else if file.isVideo && !file.isAnimated {
                return .photoOrVideo
            } else if file.isVoice {
                return .voiceOrInstantVideo
            } else if file.isStaticSticker || (file.isVideo && file.isAnimated) {
                return nil
            } else {
                return .file
            }
        default:
            break
        }
    }
    return nil
}


public enum GalleryAppearType : Equatable {
    case alone
    case history
    case profile(PeerId)
    case secret
    case recentDownloaded
    case messages([Message])
}

private func mediaForMessage(message: Message, postbox: Postbox) -> Media? {
    // `effectiveMedia` falls back to a rich message's instant-page media (its `media` is empty).
    for media in message.effectiveMedia {
        if let media = media as? TelegramMediaInvoice, let extended = media.extendedMedia {
            switch extended {
            case .preview:
                return nil
            case let .full(media):
                return media
            }
        }
        if let media = media as? TelegramMediaAction {
            switch media.action {
            case let .suggestedProfilePhoto(image):
                return image
            case let .photoUpdated(image):
                return image
            default:
                return nil
            }
        }
        if let media = media as? TelegramMediaImage {
            return media
        } else if let file = media as? TelegramMediaFile {
            if file.isGraphicFile || file.isVideo || file.isAnimated {
                return file
            } else if file.isVideoFile, FileManager.default.fileExists(atPath: postbox.mediaBox.resourcePath(file.resource)) {
                return file
            }
        } else if let webpage = media as? TelegramMediaWebpage {
            if case let .Loaded(content) = webpage.content {
                if ExternalVideoLoader.isPlayable(content) {
                    return nil
                } else {
                    return content.file ?? content.image
                }
            }
        }

    }
    return nil
}

private func galleryMediaIsEligible(_ media: Media) -> Bool {
    if media is TelegramMediaImage {
        return true
    }
    if let file = media as? TelegramMediaFile {
        return file.isGraphicFile || file.isVideo || file.isAnimated || file.isVideoFile
    }
    return false
}

// A rich message keeps all of its medias inside the instant page (`message.media` is empty), so the
// chat gallery would otherwise page through it as a single item showing only the first media. Expand
// each such entry into one entry per displayable media, reusing the shared-media synthetic-message
// scheme (distinct ids/stableIds so the entries get distinct `ChatHistoryEntryId.message` keys).
private func expandRichMediaEntries(_ entries: [ChatHistoryEntry]) -> [ChatHistoryEntry] {
    var result: [ChatHistoryEntry] = []
    for entry in entries {
        if case let .MessageEntry(message, _, read, renderType, itemType, fwd, data) = entry, message.media.isEmpty, message.richText != nil {
            let expanded = expandSharedMediaMessages([message], where: galleryMediaIsEligible)
            if expanded.count > 1 {
                for synthetic in expanded {
                    result.append(.MessageEntry(synthetic, MessageIndex(synthetic), read, renderType, itemType, fwd, data))
                }
                continue
            }
        }
        result.append(entry)
    }
    return result
}

fileprivate func itemFor(entry: ChatHistoryEntry, context: any AccountContextProtocol, pagerSize: NSSize) -> MGalleryItem {
    switch entry {
    case let .MessageEntry(message, _, _, _, _, _, _):
        if let media = mediaForMessage(message: message, postbox: context.account.postbox) {
            if let _ = media as? TelegramMediaImage {
                return MGalleryPhotoItem(context, .message(entry), pagerSize)
            } else if let file = media as? TelegramMediaFile {
                if (file.isVideo && !file.isAnimated) {
                    return MGalleryVideoItem(context, .message(entry), pagerSize)
                } else {
                    if file.mimeType.hasPrefix("image/") {
                        return MGalleryPhotoItem(context, .message(entry), pagerSize)
                    } else if file.isVideo && file.isAnimated {
                        return MGalleryGIFItem(context, .message(entry), pagerSize)
                    } else if file.isVideoFile {
                        return MGalleryVideoItem(context, .message(entry), pagerSize)
                    }
                }
            }
        } else if !message.media.isEmpty, let webpage = message.media[0] as? TelegramMediaWebpage {
            if case let .Loaded(content) = webpage.content {
                if let file = content.file {
                    if file.mimeType.hasPrefix("image/") {
                        return MGalleryPhotoItem(context, .message(entry), pagerSize)
                    } else if file.isVideo && file.isAnimated {
                        return MGalleryGIFItem(context, .message(entry), pagerSize)
                    } else if file.isVideoFile {
                        return MGalleryVideoItem(context, .message(entry), pagerSize)
                    }
                }
            }
        }
    default:
        break
    }
    
    return MGalleryItem(context, .message(entry), pagerSize)
}

fileprivate struct GalleryHistoryUpdate {
    var entries: [ChatHistoryEntry]
    var bounds: (earlierId: MessageIndex?, laterId: MessageIndex?)? = nil
    var anchor: MessageIndex? = nil
    var window: (lower: MessageIndex, upper: MessageIndex)? = nil
    var transition: ([ChatHistoryEntry]) -> UpdateTransition<MGalleryItem>
}

fileprivate func galleryTransition(to: [ChatHistoryEntry], context: any AccountContextProtocol, pagerSize:NSSize) -> ([ChatHistoryEntry]) -> UpdateTransition<MGalleryItem> {
    return { from in
        let (removed, inserted, updated) = proccessEntriesWithoutReverse(from, right: to, { (entry) -> MGalleryItem in
           return itemFor(entry: entry, context: context, pagerSize: pagerSize)
        })
        return UpdateTransition(deleted: removed, inserted: inserted, updated: updated)
    }
}



public final class GalleryBackgroundView : NSView {
    
    deinit {
        var bp:Int = 0
        bp += 1
    }
}



public class GalleryViewer: NSResponder {
    
    
    public let window:Window
  //  private var controls:GalleryControls!
    private var controls: GalleryModernControls!
    public let pager:GalleryPageController
    private let backgroundView: GalleryBackgroundView = GalleryBackgroundView()
    private let ready = Promise<Bool>()
    private var didSetReady = false
    private var presentationGeneration = 0
    
    private let disposable = MetaDisposable()
    private let readyDispose = MetaDisposable()
    private let operationDisposable = MetaDisposable()
    public private(set) weak var delegate:InteractionContentViewProtocol?
    private let context:any AccountContextProtocol
    public var accountId: AccountRecordId {
        return context.account.id
    }
    private let indexDisposable:MetaDisposable = MetaDisposable()
    private let messagesActionDisposable = MetaDisposable()
    
    public let interactions:GalleryInteractions = GalleryInteractions()
    public let contentInteractions:(any GalleryContentInteractions)?
    public var cachedPeerData: CachedPeerData?
    private var captureExclusionToken: CaptureExclusionManager.Token?
    fileprivate var firstStableId: AnyHashable? = nil
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    public let type:GalleryAppearType
    public let chatMode: ChatMode?
    public let chatLocation: ChatLocation?
    private let reversed: Bool
    
    private var liveTranslate: ChatLiveTranslateContext?
    
    private init(context: any AccountContextProtocol, _ delegate:InteractionContentViewProtocol? = nil, _ contentInteractions:(any GalleryContentInteractions)? = nil, type: GalleryAppearType, reversed:Bool = false, chatMode: ChatMode?, chatLocation: ChatLocation?, cachedPeerData: CachedPeerData? = nil) {
        self.context = context
        self.delegate = delegate
        self.type = type
        self.chatMode = chatMode
        self.chatLocation = chatLocation
        self.cachedPeerData = cachedPeerData
        self.reversed = reversed
        self.contentInteractions = contentInteractions
        if let screen = NSScreen.main {
            let bounds = NSMakeRect(0, 0, screen.frame.width, screen.frame.height)
            self.window = Window(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false, screen: screen)
            self.window.contentView?.wantsLayer = true

            self.window.level = .popUpMenu
            self.window.isOpaque = false
            self.window.backgroundColor = .clear
          //  self.window.appearance = theme.appearance
            backgroundView.wantsLayer = true
            backgroundView.background = NSColor.black.withAlphaComponent(0.9)
            backgroundView.frame = bounds
            
            var topInset: CGFloat = 0
            
            if #available(macOS 12.0, *) {
                topInset = screen.safeAreaInsets.top
            }
            
            self.pager = GalleryPageController(frame: bounds, contentInset:NSEdgeInsets(left: 0, right: 0, top: topInset, bottom: 95), interactions:interactions, window:window, reversed: reversed)

        } else {
            fatalError("main screen not found for MediaViewer")
        }
        
        
        super.init()
        
        
        interactions.dismiss = { [weak self] _ -> KeyHandlerResult in
            if let pager = self?.pager {
               
                if pager.isFullScreen {
                    pager.exitFullScreen()
                    return .invoked
                }
                if !pager.lockedTransition {
                    self?.close(true)
                }
            }
            return .invoked
        }
        
        interactions.next = { [weak self] _ -> KeyHandlerResult in
            self?.pager.next()
            return .invoked
        }
        
        interactions.previous = { [weak self] _ -> KeyHandlerResult in
            self?.pager.prev()
            return .invoked
        }
        
        interactions.select = { [weak self] item in
            self?.pager.select(by: item)
        }
        
        interactions.showActions = { [weak self] control -> KeyHandlerResult in
            self?.showControlsPopover(control)
            return .invoked
        }
        interactions.share = { [weak self] control in
            self?.share(control)
        }
        
        interactions.openInfo = { [weak self] peerId in
            self?.openInfo(peerId)
        }
        
        interactions.openMessage = { [weak self] in
            self?.showMessage()
        }
        
        interactions.contextMenu = {[weak self] in
            return self?.contextMenu
        }
        
        interactions.zoomIn = { [weak self] in
            self?.pager.zoomIn()
        }
        interactions.zoomOut = { [weak self] in
            self?.pager.zoomOut()
        }
        interactions.rotateLeft = { [weak self] in
            self?.pager.rotateLeft()
        }
        interactions.fastSave = { [weak self] in
            self?.saveAs(true)
        }
        
        interactions.invokeAd = { [weak self] peerId, adAttribute in
            
            guard let self else {
                return
            }
            self.close()
            closeAllModals(window: self.window)
            
            GalleryHooks.shared.openAdUrl(adAttribute.url, context, { [weak self] peerId, toChat, messageId, action in
                self?.openInfo(peerId, toChat, messageId, action)
            })
            
            context.engine.messages.markAdAction(opaqueId: adAttribute.opaqueId, media: true, fullscreen: true)
        }
        interactions.openLink = { [weak self] url in
            guard let self else {
                return
            }
            GalleryHooks.shared.openRecognizedLink(url, context, { peerId, toChat, messageId, action in
                self.openInfo(peerId, toChat, messageId, action)
            }, { [weak self] completed in
                if completed {
                    self?.close()
                }
            })
        }
        interactions.canShare = { [weak self] in
            let isProtected = self?.pager.selectedItem?.entry.message?.isCopyProtected(cachedData: self?.cachedPeerData) ?? false
            if isProtected {
                return false
            } else if let chatMode = chatMode {
                return !chatMode.isSavedMode && chatMode.customChatContents == nil
            } else {
                return false
            }
        }
        window.set(handler: { [weak self] event in
            guard let `self` = self else {return .rejected}
            if self.pager.selectedItem is MGalleryVideoItem || self.pager.selectedItem is MGalleryExternalVideoItem {
                self.pager.selectedItem?.togglePlayerOrPause()
                return .invoked
            } else {
                return self.interactions.dismiss(event)
            }
        }, with:self, for: .Space)
        
        window.set(handler: { [weak self] event in
            guard let `self` = self else {return .rejected}
            self.pager.toggleFullScreen()
            return .invoked
        }, with:self, for: .F)
        
        window.set(handler: interactions.dismiss, with:self, for: .Escape)
        
        window.closeInterceptor = { [weak self] in
            if let event = NSApp.currentEvent {
                _ = self?.interactions.dismiss(event)
            }
            return true
        }
        
        window.set(handler: interactions.next, with:self, for: .RightArrow)
        window.set(handler: interactions.previous, with:self, for: .LeftArrow)
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.pager.zoomOut()
            return .invoked
        }, with: self, for: .Minus)
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.pager.zoomIn()
            return .invoked
        }, with: self, for: .Equal)
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.pager.decreaseSpeed()
            return .invoked
        }, with: self, for: .Minus, modifierFlags: [.command, .option])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.pager.increaseSpeed()
            return .invoked
        }, with: self, for: .Equal, modifierFlags: [.command, .option])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.pager.rotateLeft()
            return .invoked
        }, with: self, for: .R, modifierFlags: [.command])
        
        window.set(handler: { [weak self] _ -> KeyHandlerResult in
            self?.saveAs()
            return .invoked
        }, with: self, for: .S, priority: .high, modifierFlags: [.command])
        
        window.copyhandler = { [weak self] in
            self?.copy(nil)
        }
        window.masterCopyhandler = { [weak self] in
            self?.copy(nil)
        }
        
        window.firstResponderFilter = { responder in
            return responder
        }
        
        self.controls = GalleryModernControls(context, interactions: interactions, frame: NSMakeRect(0, -150, window.frame.width, 150), thumbsControl: pager.thumbsControl)
        

        self.pager.view.addSubview(self.backgroundView)
        self.window.contentView?.addSubview(self.pager.view)
        self.window.contentView?.addSubview(self.controls.view)
    }
    
    @objc open func windowDidBecomeKey() {
        
    }
    
    
    @objc open func windowDidResignKey() {
        self.window.makeKeyAndOrderFront(self)
      //  window.makeFirstResponder(self)
    }
    
    public var pagerSize: NSSize {
        return NSMakeSize(pager.frame.size.width - pager.contentInset.right - pager.contentInset.left, pager.frame.size.height - pager.contentInset.bottom - pager.contentInset.top)
    }
    
    fileprivate convenience init(context: any AccountContextProtocol, peerId:PeerId, firstStableId:AnyHashable, _ delegate:InteractionContentViewProtocol? = nil, _ contentInteractions:(any GalleryContentInteractions)? = nil, reversed:Bool = false, chatMode: ChatMode?, chatLocation: ChatLocation?, cachedPeerData: CachedPeerData? = nil) {
        self.init(context: context, delegate, contentInteractions, type: .profile(peerId), reversed: reversed, chatMode: chatMode, chatLocation: chatLocation, cachedPeerData: cachedPeerData)

        let pagerSize = self.pagerSize
        
        let previous: Atomic<[GalleryEntry]> = Atomic(value: [])
        
        let transaction: Signal<(UpdateTransition<MGalleryItem>, Int), NoError> = peerPhotosGalleryEntries(context: context, peerId: peerId, firstStableId: firstStableId) |> map { (entries, selected, publicPhoto) in
            let (deleted, inserted, updated) = proccessEntriesWithoutReverse(previous.swap(entries), right: entries, { entry -> MGalleryItem in
                switch entry {
                case let .photo(_, _, photo, _, _, _, _, _, _):
                    if !photo.videoRepresentations.isEmpty {
                        return MGalleryGIFItem(context, entry, pagerSize)
                    } else {
                        return MGalleryPeerPhotoItem(context, entry, pagerSize)
                    }
                default:
                    preconditionFailure()
                }
            })
            return (UpdateTransition(deleted: deleted, inserted: inserted, updated: updated), selected)
        } |> deliverOnMainQueue
        
        
        disposable.set(transaction.start(next: { [weak self] transaction, selected in
            _ = self?.pager.merge(with: transaction, afterTransaction: {
                self?.controls.update(self?.pager.selectedItem)
            })
            self?.pager.selectedIndex.set(selected)
            self?.pager.set(index: selected, animated: false)
            self?.ready.set(.single(true))

        }))

        self.indexDisposable.set((pager.selectedIndex.get() |> deliverOnMainQueue).start(next: { [weak self] selectedIndex in
            guard let `self` = self else {return}
            self.controls.update(self.pager.selectedItem)
            self.updateCaptureExclusion()
        }))
    }

    fileprivate convenience init(context: any AccountContextProtocol, instantMedias:[InstantPageMedia], firstIndex:Int, firstStableId: AnyHashable? = nil, parent: Message? = nil, _ delegate:InteractionContentViewProtocol? = nil, _ contentInteractions:(any GalleryContentInteractions)? = nil, reversed: Bool = false, chatMode: ChatMode?, chatLocation: ChatLocation?, cachedPeerData: CachedPeerData? = nil) {
        self.init(context: context, delegate, contentInteractions, type: .history, reversed: reversed, chatMode: chatMode, chatLocation: chatLocation, cachedPeerData: cachedPeerData)
        self.firstStableId = firstStableId
        let pagerSize = self.pagerSize
        

        
        ready.set(.single(true) |> map { [weak self] _ -> Bool in
            
            guard let `self` = self else {return false}
            
            var inserted: [(Int, MGalleryItem)] = []
            for i in 0 ..< instantMedias.count {
                let media = instantMedias[i]
                if media.media is TelegramMediaImage {
                    inserted.append((media.index, MGalleryPhotoItem(context, .instantMedia(media, parent), pagerSize)))
                } else if let file = media.media as? TelegramMediaFile {
                    if file.isVideo && file.isAnimated {
                        inserted.append((media.index, MGalleryGIFItem(context, .instantMedia(media, parent), pagerSize)))
                    } else if file.isVideo {
                        inserted.append((media.index, MGalleryVideoItem(context, .instantMedia(media, parent), pagerSize)))
                    }
                } else if media.media is TelegramMediaWebpage {
                    inserted.append((media.index, MGalleryExternalVideoItem(context, .instantMedia(media, parent), pagerSize)))
                }
            }
            
            _ = self.pager.merge(with: UpdateTransition(deleted: [], inserted: inserted, updated: []))
            
            //self?.controls.index.set(.single((firstIndex + 1, totalCount)))
            self.pager.set(index: firstIndex, animated: false)
            self.controls.update(self.pager.selectedItem)
            return true

        })

        self.indexDisposable.set((pager.selectedIndex.get() |> deliverOnMainQueue).start(next: { [weak self] selectedIndex in
            guard let `self` = self else {return}
            self.controls.update(self.pager.selectedItem)
            self.updateCaptureExclusion()
        }))
    }

    fileprivate convenience init(context: any AccountContextProtocol, media:[Media], firstIndex: Int, firstStableId: AnyHashable? = nil, parent: Message, _ delegate:InteractionContentViewProtocol? = nil, _ contentInteractions:(any GalleryContentInteractions)? = nil, cachedPeerData: CachedPeerData? = nil) {
        self.init(context: context, delegate, contentInteractions, type: .history, reversed: false, chatMode: nil, chatLocation: nil, cachedPeerData: cachedPeerData)
        self.firstStableId = firstStableId
        let pagerSize = self.pagerSize
        

        
        ready.set(.single(true) |> map { [weak self] _ -> Bool in
            
            guard let `self` = self else {return false}
            
            var inserted: [(Int, MGalleryItem)] = []
            for i in 0 ..< media.count {
                let media = media[i]
                if media is TelegramMediaImage {
                    inserted.append((i, MGalleryPhotoItem(context, .media(media, i, parent), pagerSize)))
                } else if let file = media as? TelegramMediaFile {
                    if file.isVideo && file.isAnimated {
                        inserted.append((i, MGalleryGIFItem(context, .media(media, i, parent), pagerSize)))
                    } else if file.isVideo {
                        inserted.append((i, MGalleryVideoItem(context, .media(media, i, parent), pagerSize)))
                    }
                }
            }
            _ = self.pager.merge(with: UpdateTransition(deleted: [], inserted: inserted, updated: []))
            
            self.pager.set(index: firstIndex, animated: false)
            self.controls.update(self.pager.selectedItem)
            return true
            
        })
        
        self.indexDisposable.set((pager.selectedIndex.get() |> deliverOnMainQueue).start(next: { [weak self] selectedIndex in
            guard let `self` = self else {return}
            self.controls.update(self.pager.selectedItem)
            self.updateCaptureExclusion()
        }))


    }


    fileprivate convenience init(context: any AccountContextProtocol, secureIdMedias:[SecureIdDocumentValue], firstIndex:Int, _ delegate:InteractionContentViewProtocol? = nil, reversed:Bool = false, chatMode: ChatMode?, chatLocation: ChatLocation?, cachedPeerData: CachedPeerData? = nil) {
        self.init(context: context, delegate, nil, type: .history, reversed: reversed, chatMode: chatMode, chatLocation: chatLocation, cachedPeerData: cachedPeerData)
        
        let pagerSize = self.pagerSize
        
        
        
        ready.set(.single(true) |> map { [weak self] _ -> Bool in
            guard let `self` = self else {return false}
            var inserted: [(Int, MGalleryItem)] = []
            for i in 0 ..< secureIdMedias.count {
                let media = secureIdMedias[i]
                inserted.append((i, MGalleryPhotoItem(context, .secureIdDocument(media, i), pagerSize)))

            }
            
            _ = self.pager.merge(with: UpdateTransition(deleted: [], inserted: inserted, updated: []))
            
            self.pager.set(index: firstIndex, animated: false)
            self.controls.update(self.pager.selectedItem)
            return true

            })

        self.indexDisposable.set((pager.selectedIndex.get() |> deliverOnMainQueue).start(next: { [weak self] selectedIndex in
            guard let `self` = self else {return}
            self.controls.update(self.pager.selectedItem)
            self.updateCaptureExclusion()
        }))


    }


    fileprivate convenience init(context: any AccountContextProtocol, message:Message, _ delegate:InteractionContentViewProtocol? = nil, _ contentInteractions:(any GalleryContentInteractions)? = nil, type: GalleryAppearType = .history, item: MGalleryItem? = nil, reversed: Bool = false, chatMode: ChatMode?, chatLocation: ChatLocation?, contextHolder: Atomic<ChatLocationContextHolder?> = Atomic(value: nil), cachedPeerData: CachedPeerData? = nil) {
        
        self.init(context: context, delegate, contentInteractions, type: type, reversed: reversed, chatMode: chatMode, chatLocation: chatLocation, cachedPeerData: cachedPeerData)

        let chatMode = self.chatMode
        let chatLocation = self.chatLocation
        let previous:Atomic<[ChatHistoryEntry]> = Atomic(value:[])
        let current:Atomic<[ChatHistoryEntry]> = Atomic(value:[])
        let currentIndex:Atomic<Int?> = Atomic(value:nil)
        let selectedMessageIndex:Atomic<MessageIndex?> = Atomic(value:nil)
        let restoringSelection:Atomic<Bool> = Atomic(value:false)
        let pendingLoad:Atomic<(anchor: MessageIndex, older: Bool)?> = Atomic(value:nil)
        let loadedRange:Atomic<(lower: MessageIndex, upper: MessageIndex)?> = Atomic(value:nil)
        let request:Promise<MessageIndex> = Promise()
        let pagerSize = self.pagerSize
        let indexes:Atomic<(earlierId: MessageIndex?, laterId: MessageIndex?)> = Atomic(value:(nil, nil))
        
        
        self.liveTranslate = .init(peerId: message.id.peerId, context: context)

        
        if let item = item, let entry = item.entry.chatEntry {
            _ = current.swap([entry])
            
            let transition: UpdateTransition<MGalleryItem> = UpdateTransition(deleted: [], inserted: [(0, item)], updated: [])
            
            _ = pager.merge(with: transition)
            ready.set(.single(true))
        }
        
        let translate: Signal<ChatLiveTranslateContext.State?, NoError>
        if let liveTranslate {
            translate = liveTranslate.state |> map(Optional.init)
        } else {
            translate = .single(nil)
        }
        
        let loadMore:(Bool) -> Void = { atStart in
            let bounds = indexes.with { $0 }
            let edge = atStart ? (reversed ? bounds.laterId : bounds.earlierId) : (reversed ? bounds.earlierId : bounds.laterId)
            guard let edge = edge else {
                return
            }
            _ = pendingLoad.swap((edge, atStart != reversed))
            request.set(.single(edge))
        }

        let signal = combineLatest(request.get() |> distinctUntilChanged, translate |> distinctUntilChanged)
            |> mapToSignal { index, translate -> Signal<GalleryHistoryUpdate, NoError> in
                
                var type = type
                let tags: HistoryViewInputTag? = tagsForMessage(message).flatMap { .tag($0) }
                if tags == nil {
                   type = .alone
                }
                let mode: ChatMode = chatMode ?? .history
                let chatLocation = chatLocation ?? .peer(message.id.peerId)
                
                let signal:Signal<(MessageHistoryView, ViewUpdateType, InitialMessageHistoryData?), NoError>
                switch mode {
                case .history, .preview:
                    signal = context.account.viewTracker.aroundIdMessageHistoryViewForLocation(.peer(peerId: message.id.peerId, threadId: nil), count: 50, ignoreRelatedChats: false, messageId: index.id, tag: tags, orderStatistics: [.combinedLocation], additionalData: [])
                case .thread:
                    if case let .thread(data) = chatLocation {
                        if case let .thread(data) = chatLocation, data.effectiveTopId == message.id {
                            signal = context.account.viewTracker.aroundIdMessageHistoryViewForLocation(.peer(peerId: message.id.peerId, threadId: nil), count: 50, ignoreRelatedChats: false, messageId: index.id, tag: tags, orderStatistics: [.combinedLocation], additionalData: [])
                        } else {
                            signal = context.account.viewTracker.aroundIdMessageHistoryViewForLocation(context.chatLocationInput(for: .thread(data), contextHolder: contextHolder), count: 50, ignoreRelatedChats: false, messageId: index.id, tag: tags, orderStatistics: [.combinedLocation], additionalData: [])
                        }
                    } else {
                        signal = context.account.viewTracker.aroundIdMessageHistoryViewForLocation(.peer(peerId: message.id.peerId, threadId: nil), count: 50, ignoreRelatedChats: false, messageId: index.id, tag: tags, orderStatistics: [.combinedLocation], additionalData: [])
                    }
                case .pinned:
                    signal = context.account.viewTracker.aroundIdMessageHistoryViewForLocation(.peer(peerId: message.id.peerId, threadId: nil), count: 50, ignoreRelatedChats: false, messageId: index.id, tag: .tag(.pinned), orderStatistics: [.combinedLocation], additionalData: [])
                case .scheduled:
                    signal = context.account.viewTracker.scheduledMessagesViewForLocation(.peer(peerId: message.id.peerId, threadId: nil))
                case let .customChatContents(contents):
                    signal = contents.historyView |> map { view in
                        return (MessageHistoryView(tag: nil, namespaces: .all, entries: view.0.entries, holeEarlier: false, holeLater: false, isLoading: false), ViewUpdateType.Generic, nil)
                    }
                case .customLink:
                    signal = .complete()
                }

            
                switch type {
                case .alone:
                    
                    
                    let messageSignal: Signal<Message?, NoError>
                    if message.adAttribute != nil {
                        messageSignal = .single(message)
                    } else {
                        messageSignal = context.engine.data.subscribe(TelegramEngine.EngineData.Item.Messages.Message(id: message.id)) |> map {
                            $0?._asMessage()
                        }
                    }
                    return messageSignal |> map { message in
                        if let message {
                            let entries:[ChatHistoryEntry] = expandRichMediaEntries([.MessageEntry(message, MessageIndex(message), false, .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings))])
                            var inserted: [(Int, MGalleryItem)] = []

                            for (i, entry) in entries.enumerated() {
                                inserted.append((i, itemFor(entry: entry, context: context, pagerSize: pagerSize)))
                            }

                            if entries.count == 1, let webpage = message.anyMedia as? TelegramMediaWebpage {
                                let instantMedias = instantPageMedias(for: webpage)
                                if instantMedias.count > 1 {
                                    for i in 1 ..< instantMedias.count {
                                        let media = instantMedias[i]
                                        if media.media is TelegramMediaImage {
                                            inserted.append((i, MGalleryPhotoItem(context, .instantMedia(media, message), pagerSize)))
                                        } else if let file = media.media as? TelegramMediaFile {
                                            if file.isVideo && file.isAnimated {
                                                inserted.append((i, MGalleryGIFItem(context, .instantMedia(media, message), pagerSize)))
                                            } else if file.isVideo || file.isVideoFile {
                                                inserted.append((i, MGalleryVideoItem(context, .instantMedia(media, message), pagerSize)))
                                            }
                                        } else if media.media is TelegramMediaWebpage {
                                            inserted.append((i, MGalleryExternalVideoItem(context, .instantMedia(media, message), pagerSize)))
                                        }
                                    }
                                }
                            }
                            return GalleryHistoryUpdate(entries: entries, transition: { _ in
                                return UpdateTransition(deleted: [], inserted: inserted, updated: [])
                            })
                        } else {
                            return GalleryHistoryUpdate(entries: [], transition: { _ in
                                return UpdateTransition(deleted: [0], inserted: [], updated: [])
                            })
                        }
                        
                    } |> deliverOnMainQueue
                    
                case .history:
                    return signal |> mapToSignal { view, _, _ -> Signal<GalleryHistoryUpdate, NoError> in
                        let entries:[ChatHistoryEntry] = expandRichMediaEntries(messageEntries(view.entries, includeHoles : false, translate: translate, contentConfig: context.contentConfig).filter { entry -> Bool in
                            switch entry {
                            case let .MessageEntry(message, _, _, _, _, _, _):
                                let firstCheck = message.id.peerId.namespace == Namespaces.Peer.SecretChat || !message.containsSecretMedia && mediaForMessage(message: message, postbox: context.account.postbox) != nil
                                
                                if !firstCheck {
                                    return false
                                }
                                if let peer = message.peers[message.id.peerId] {
                                    if let group = peer as? TelegramGroup {
                                        if group.membership == .Removed {
                                            switch group.role {
                                            case .creator:
                                                return true
                                            case .admin:
                                                return true
                                            case .member:
                                                return false
                                            }
                                        }
                                    }
                                    if let group = peer as? TelegramChannel {
                                        switch group.participationStatus {
                                        case .member, .left:
                                            return true
                                        default:
                                            return group.isAdmin
                                        }
                                    }
                                }
                                
                                return true
                            default:
                                return true
                            }
                        })
                        var window: (lower: MessageIndex, upper: MessageIndex)?
                        if let first = view.entries.first, let last = view.entries.last {
                            window = (view.earlierId == nil ? MessageIndex.absoluteLowerBound() : first.index, view.laterId == nil ? MessageIndex.absoluteUpperBound() : last.index)
                        }
                        return .single(GalleryHistoryUpdate(entries: entries, bounds: (view.earlierId, view.laterId), anchor: index, window: window, transition: galleryTransition(to: entries, context: context, pagerSize: pagerSize)))
                    }
                case .recentDownloaded:
                    return recentDownloadItems(postbox: context.account.postbox) |> mapToSignal { downloaded in
                        let messages = downloaded.map {
                            $0.message
                        }.map {
                            MessageHistoryEntry(message: $0, isRead: true, location: nil, monthLocation: nil, attributes: MutableMessageHistoryEntryAttributes(authorIsContact: false))
                        }
                        let entries:[ChatHistoryEntry] = messageEntries(messages, includeHoles : false, contentConfig: context.contentConfig).filter { entry -> Bool in
                            switch entry {
                            case let .MessageEntry(message, _, _, _, _, _, _):
                                return message.id.peerId.namespace == Namespaces.Peer.SecretChat || !message.containsSecretMedia && mediaForMessage(message: message, postbox: context.account.postbox) != nil
                            default:
                                return true
                            }
                        }
                        return .single(GalleryHistoryUpdate(entries: entries, transition: galleryTransition(to: entries, context: context, pagerSize: pagerSize)))
                        
                    }
                case .secret:
                    return context.account.postbox.messageView(index.id) |> mapToSignal { view -> Signal<GalleryHistoryUpdate, NoError> in
                        var entries:[ChatHistoryEntry] = []
                        if let message = view.message, !(message.anyMedia is TelegramMediaExpiredContent) {
                            entries.append(.MessageEntry(message, MessageIndex(message), false, .list, .Full(rank: nil, rankType: .none, header: .normal), nil, ChatHistoryEntryData(nil, MessageEntryAdditionalData(), AutoplayMediaPreferences.defaultSettings)))
                        }
                        return .single(GalleryHistoryUpdate(entries: entries, transition: galleryTransition(to: entries, context: context, pagerSize: pagerSize)))
                    }
                case .profile:
                    return .complete()
                case let .messages(messages):
                    let messages = messages.map {
                        MessageHistoryEntry(message: $0, isRead: true, location: nil, monthLocation: nil, attributes: MutableMessageHistoryEntryAttributes(authorIsContact: false))
                    }
                    let entries:[ChatHistoryEntry] = expandRichMediaEntries(messageEntries(messages, includeHoles : false, contentConfig: context.contentConfig).filter { entry -> Bool in
                        switch entry {
                        case let .MessageEntry(message, _, _, _, _, _, _):
                            return message.id.peerId.namespace == Namespaces.Peer.SecretChat || !message.containsSecretMedia && mediaForMessage(message: message, postbox: context.account.postbox) != nil
                        default:
                            return true
                        }
                    })
                    return .single(GalleryHistoryUpdate(entries: entries, transition: galleryTransition(to: entries, context: context, pagerSize: pagerSize)))
                }
              
            }  |> deliverOnMainQueue
            |> map { [weak self] update in
                if let strongSelf = self {
                    
                    var entries = update.entries
                    var transition: UpdateTransition<MGalleryItem>
                    if let bounds = update.bounds {
                        let known = loadedRange.with { $0 }
                        if let window = update.window {
                            if let known = known {
                                entries = (previous.with { $0 }.filter { $0.index < window.lower || $0.index > window.upper } + update.entries).sorted(by: { $0.index < $1.index })
                                let extendsEarlier = window.lower < known.lower
                                let extendsLater = window.upper > known.upper
                                let current = indexes.with { $0 }
                                _ = indexes.swap((extendsEarlier ? bounds.earlierId : current.earlierId, extendsLater ? bounds.laterId : current.laterId))
                                _ = loadedRange.swap((min(known.lower, window.lower), max(known.upper, window.upper)))
                            } else {
                                _ = indexes.swap(bounds)
                                _ = loadedRange.swap(window)
                            }
                        } else if known == nil {
                            _ = indexes.swap(bounds)
                        }
                        transition = galleryTransition(to: entries, context: context, pagerSize: pagerSize)(previous.swap(entries))
                    } else {
                        transition = update.transition(previous.swap(entries))
                    }
                    
                    let new = reversed ? entries.reversed() : entries
                    
                    _ = current.swap(new)
                    
                    let selectedMessage = selectedMessageIndex.with { $0 }

                    if let pending = pendingLoad.with({ $0 }), let anchor = update.anchor, pending.anchor == anchor {
                        _ = pendingLoad.swap(nil)
                        if transition.inserted.isEmpty {
                            DispatchQueue.main.async {
                                loadMore(pending.older != reversed)
                            }
                        }
                    }
                    
                    var current:Int? = currentIndex.modify({$0})
                    if current == nil || !reversed {
                        let id = selectedMessage?.id ?? message.id
                        if let found = new.firstIndex(where: { $0.message?.id == id }) {
                            current = found
                        } else if !reversed, let selectedMessage = selectedMessage, !new.isEmpty {
                            current = new.firstIndex(where: { $0.index >= selectedMessage }) ?? new.count - 1
                        }
                    }
                    
//
                    
                    
                    let isEmpty = strongSelf.pager.merge(with: transition)
                    
                    if !isEmpty {
                        
                        
                        if let newIndex = current {
                            _ = restoringSelection.swap(true)
                            strongSelf.pager.selectedIndex.set(newIndex)
                            strongSelf.pager.set(index: newIndex, animated: false)
                            _ = restoringSelection.swap(false)
                            if !new.isEmpty && newIndex < new.count && newIndex >= 0, new[newIndex].message?.autoremoveAttribute != nil {
                            }
                        }
                    } else {
                        strongSelf.close()
                    }
                    strongSelf.ready.set(.single(true))
                }
            }
        
        
        self.disposable.set(signal.start())
        let reqlimit:Int = 10
        self.pager.boundaryReached = loadMore
        self.indexDisposable.set(pager.selectedIndex.get().start(next: { [weak self] (selectedIndex) in
           
            let entries = current.modify({$0})
            let selectedIndex = min(entries.count - 1, selectedIndex)
            
            guard let `self` = self, entries.count > 0 else {return}
            
            let current = entries[selectedIndex]
            let isRestoring = restoringSelection.with { $0 }
            if !isRestoring {
                _ = selectedMessageIndex.swap(current.message.flatMap { MessageIndex($0) })
            }
            self.updateCaptureExclusion()
            if let location = current.location {
                let total = location.count
                _ = reversed ? total - location.index : location.index
                self.controls.update(self.pager.selectedItem)
            } else  {
                self.controls.update(self.pager.selectedItem)
            }

            if let message = entries[selectedIndex].message, message.containsSecretMedia {
                _ = (context.engine.messages.markMessageContentAsConsumedInteractively(messageId: message.id) |> delay(0.5, queue: Queue.concurrentDefaultQueue())).start()
            }
            if !isRestoring, let pagerIndex = currentIndex.modify({$0}) {
                if selectedIndex < pagerIndex && selectedIndex < reqlimit {
                    loadMore(true)
                } else if selectedIndex > pagerIndex && selectedIndex >= entries.count - reqlimit {
                    loadMore(false)
                }
            }
            _ = currentIndex.swap(selectedIndex)
            
            
        }))
        
        request.set(.single(MessageIndex(message)))

    }
    

    private func showControlsPopoverReady(_ control: Control, savedGifs: [RecentMediaItem]) {
        
        var items:[ContextMenuItem] = []
        
        let isProtected = pager.selectedItem?.entry.isProtected == true || pager.selectedItem?.entry.message?.isCopyProtected(cachedData: self.cachedPeerData) == true
        var keepSaveAs: Bool = true
        let context = self.context

        if !isProtected {
            
            
            if let item = pager.selectedItem as? MGalleryVideoItem, let message = item.entry.message {
                if let quality = item.videoQualityState() {
                    
                    let download = ContextMenuItem(strings().galleryContextSaveVideo, itemImage: MenuAnimation.menu_save_as.value)
                    let downloadMenu = ContextMenu()
                    
                    let downloadOrShow:(TelegramMediaFile)->Void = { [weak self] file in
                        
                        let status = chatMessageFileStatus(context: context, message: message, file: file)
                        |> take(1)
                        |> deliverOnMainQueue
                        
                        _ = status.startStandalone(next: { status in
                            if let window = self?.window {
                                let text: String
                                if status == .Local {
                                    text = strings().galleryContextAlertDownloaded
                                } else {
                                    _ = messageMediaFileInteractiveFetched(context: context, messageId: message.id, messageReference: .init(message), file: file, userInitiated: true).startStandalone()
                                    text = strings().galleryContextAlertDownloading
                                }
                                showModalText(for: window, text: text, callback: { _ in
                                    self?.close()
                                    if status == .Local {
                                        showInFinder(file, account: context.account)
                                    } else {
                                        GalleryHooks.shared.openDownloadSearch(context)
                                    }
                                })
                            }
                            
                        })
                        
                       
                    }
                    
                    
                    if context.isPremium {
                        if let size = item.media.size {
                            downloadMenu.addItem(ContextMenuItem(strings().galleryContextOriginal + " (\(String.prettySized(with: size)))", handler: {
                                downloadOrShow(item.media)
                            }))
                        }
                    }
                    for value in quality.available {
                        let q = "\(roundToStandardQuality(size: value))p"
                        
                        let file = item.media.alternativeRepresentations.first(where: {
                            $0.dimensions?.height == Int32(value)
                        })
                                                
                        if let file = file, let size = file.size {
                            downloadMenu.addItem(ContextMenuItem(q + " (\(String.prettySized(with: size)))", handler: {
                                downloadOrShow(file)
                            }))
                        }
                    }
                    download.submenu = downloadMenu
                    items.append(download)
                    keepSaveAs = false
                }
            }
            if keepSaveAs {
                items.append(ContextMenuItem(strings().galleryContextSaveAs, handler: { [weak self] in
                    self?.saveAs()
                }, itemImage: MenuAnimation.menu_save_as.value))
            }
        }
        
        
        var chatMode: ChatMode = self.chatMode ?? .history
        var chatLocation = self.chatLocation ?? .peer(context.peerId)
        
        if let message = pager.selectedItem?.entry.message {
            if message.isScheduledMessage {
                chatMode = .scheduled
            }
            if self.chatLocation == nil {
                chatLocation = .peer(message.id.peerId)
            }
        }
        
        if let item = pager.selectedItem as? MGalleryGIFItem, chatMode == .history {
            let file = item.media
            if file.isAnimated && file.isVideo {
                let reference = item.entry.fileReference(file)
                if savedGifs.contains(where: { $0.media.fileId == file.fileId }) {
                    items.append(ContextMenuItem(strings().galleryRemoveGif, handler: { [weak control] in
                        _ = removeSavedGif(postbox: context.account.postbox, mediaId: file.fileId).start()
                        if let window = control?._window {
                            showModalText(for: window, text: strings().chatContextGifRemoved)
                        }
                    }, itemImage: MenuAnimation.menu_remove_gif.value))
                } else {
                    items.append(ContextMenuItem(strings().gallerySaveGif, handler: { [weak control, weak self] in
                        
                        guard let window = control?._window else {
                            return
                        }
                        
                        let limit = context.isPremium ? context.premiumLimits.saved_gifs_limit_premium : context.premiumLimits.saved_gifs_limit_default
                        if limit <= savedGifs.count, !context.isPremium {
                            showModalText(for: window, text: strings().chatContextFavoriteGifsLimitInfo("\(context.premiumLimits.saved_gifs_limit_premium)"), title: strings().chatContextFavoriteGifsLimitTitle, callback: { value in
                                FeatureNavigationHooks.shared.showPremiumLimit(context, .savedGifs)
                                self?.close()
                            })
                            return
                        }
                        let _ = addSavedGif(postbox: context.account.postbox, fileReference: reference).start()
                        if let window = control?._window {
                            showModalText(for: window, text: strings().chatContextGifAdded)
                        }
                    }, itemImage: MenuAnimation.menu_add_gif.value))
                }
            }
        }
        
        if !isProtected, keepSaveAs {
            items.append(ContextMenuItem(strings().galleryContextCopyToClipboard, handler: { [weak self] in
                self?.copy(nil)
            }, itemImage: MenuAnimation.menu_copy.value))
        }
        
        let acceptInteractions: Bool
        switch chatMode {
        case .customChatContents:
            acceptInteractions = false
        default:
            acceptInteractions = true
        }
        
        let paidMedia = pager.selectedItem?.entry.paidMedia ?? false
        
        if self.contentInteractions != nil, acceptInteractions {
            if let message = pager.selectedItem?.entry.message, let pageItem = pager.selectedItem {
                if self.type == .history {
                    items.append(ContextMenuItem(strings().galleryContextShowMessage, handler: { [weak self] in
                        self?.showMessage()
                    }, itemImage: MenuAnimation.menu_show_message.value))
                }
                if chatMode == .history && message.id.peerId != repliesPeerId && self.type == .history {
                    items.append(ContextMenuItem(strings().galleryContextShowGallery, handler: { [weak self] in
                        self?.showSharedMedia()
                    }, itemImage: MenuAnimation.menu_shared_media.value))
                    
                    if GalleryHooks.shared.canSendHere(context, message) {
                        if let _ = message.anyMedia as? TelegramMediaImage {
                            items.append(ContextMenuItem(strings().gallerySendHere, handler: { [weak self] in

                                self?.close(false)

                                let signal = pageItem.path.get()
                                |> take(1)
                                |> deliverOnMainQueue
                                _ = signal.start(next: { path in
                                    GalleryHooks.shared.sendHere(context, path)
                                })
                            }, itemImage: MenuAnimation.menu_edit.value))
                        }
                    }
                }
                
                
                if canDeleteMessage(message, account: context.account, chatLocation: chatLocation, mode: chatMode), !paidMedia {
                    if !items.isEmpty {
                        items.append(ContextSeparatorItem())
                    }
                    
                    let item = ContextMenuItem(strings().galleryContextDeletePhoto, handler: { [weak self] in
                        self?.deleteMessages([message])
                    }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value)
                    
                    let messages = pager.thumbsControl.items.compactMap({$0.entry.message})
                    if messages.count > 1 {
                        var items:[ContextMenuItem] = []
                        
                        let thisTitle: String
                        if message.anyMedia is TelegramMediaImage {
                            thisTitle = strings().galleryContextShareThisPhoto
                        } else {
                            thisTitle = strings().galleryContextShareThisVideo
                        }
                        items.append(ContextMenuItem(thisTitle, handler: { [weak self] in
                            self?.deleteMessages([message])
                        }, itemImage: MenuAnimation.menu_select_messages.value))
                       
                        let allTitle: String
                        if messages.filter({$0.anyMedia is TelegramMediaImage}).count == messages.count {
                            allTitle = strings().galleryContextShareAllPhotosOther(messages.count)
                        } else if messages.filter({$0.anyMedia is TelegramMediaFile}).count == messages.count {
                            allTitle = strings().galleryContextShareAllVideosOther(messages.count)
                        } else {
                            allTitle = strings().galleryContextShareAllItemsOther(messages.count)
                        }
                        
                        items.append(ContextMenuItem(allTitle, handler: { [weak self] in
                            self?.deleteMessages(messages)
                        }, itemImage: MenuAnimation.menu_select_multiple.value))
                        
                        let submenu = ContextMenu(presentation: .init(colors: darkPalette))
                        for item in items {
                            submenu.addItem(item)
                        }
                        item.submenu = submenu
                    }
                    
                    items.append(item)
                }
            }
        }
        
        
        switch type {
        case .profile(let peerId):
            if peerId == context.peerId {
                if pager.currentIndex != 0 {
                    items.append(ContextMenuItem(strings().galleryContextMainPhoto, handler: { [weak self] in
                        self?.updateMainPhoto()
                    }, itemImage: MenuAnimation.menu_copy_media.value))
                }
                if !items.isEmpty {
                    items.append(ContextSeparatorItem())
                }
                items.append(ContextMenuItem(strings().galleryContextDeletePhoto, handler: { [weak self] in
                    self?.deletePhoto()
                }, itemMode: .destruct, itemImage: MenuAnimation.menu_delete.value))
            }
        default:
            break
        }
        
    
        
        let menu = ContextMenu(presentation: .current(darkPalette), betterInside: true)
        for item in items {
            menu.addItem(item)
        }
        if let event = NSApp.currentEvent {
            AppMenu.show(menu: menu, event: event, for: control)
        }
    }
    
    public func showControlsPopover(_ control: Control) {
        
        let _savedGifsCount: Signal<[RecentMediaItem], NoError> = context.account.postbox.itemCollectionsView(orderedItemListCollectionIds: [Namespaces.OrderedItemList.CloudRecentGifs], namespaces: [Namespaces.ItemCollection.CloudStickerPacks], aroundIndex: nil, count: 100) |> take(1) |> map {
            $0.orderedItemListsViews[0].items.compactMap {
                $0.contents.get(RecentMediaItem.self)
            }
        } |> deliverOnMainQueue

        _ = _savedGifsCount.start(next: { [weak control, weak self] savedGifs in
            if let control = control {
                self?.showControlsPopoverReady(control, savedGifs: savedGifs)
            }
        })
        
    }
    
    private func deleteMessages(_ messages:[Message]) {
        if !messages.isEmpty, let peer = coreMessageMainPeer(messages[0]) {
            
            let peerId = messages[0].id.peerId
            let messageIds = messages.map {$0.id}
            
            
            let chatMode: ChatMode = self.chatMode ?? .history
            let chatLocation = self.chatLocation ?? .peer(context.peerId)
           
            
            
            let adminsPromise = ValuePromise<[RenderedChannelParticipant]>([])
            let (adminsDisposable, _) = context.peerChannelMemberCategoriesContextsManager.admins(peerId: peerId, updated: { membersState in
                if case .loading = membersState.loadingState, membersState.list.isEmpty {
                    adminsPromise.set([])
                } else {
                    adminsPromise.set(membersState.list)
                }
            })
            
            let actionDisposables = DisposableSet()
            actionDisposables.add(adminsDisposable)
            messagesActionDisposable.set(actionDisposables)
            
            actionDisposables.add((adminsPromise.get() |> deliverOnMainQueue).start( next:{ [weak self] admins in
                guard let `self` = self else {return}
                
                var canDelete:Bool = true
                var canDeleteForEveryone = true
                var otherCounter:Int32 = 0
                for message in messages {
                    if !canDeleteMessage(message, account: self.context.account, chatLocation: chatLocation, mode: chatMode) {
                        canDelete = false
                    }
                    if !canDeleteForEveryoneMessage(message, context: self.context) {
                        canDeleteForEveryone = false
                    } else {
                        if message.effectiveAuthor?.id != self.context.peerId && !(self.context.limitConfiguration.canRemoveIncomingMessagesInPrivateChats && message.peers[message.id.peerId] is TelegramUser)  {
                            if let peer = message.peers[message.id.peerId] as? TelegramGroup {
                                inner: switch peer.role {
                                case .member:
                                    otherCounter += 1
                                default:
                                    break inner
                                }
                            } else {
                                otherCounter += 1
                            }
                        }
                    }
                }
                
                if otherCounter == messages.count {
                    canDeleteForEveryone = false
                }
                
                if canDelete {
                    let thrid:String? = (canDeleteForEveryone ? peer.isUser ? strings().chatMessageDeleteForMeAndPerson(peer.compactDisplayTitle) : strings().chatConfirmDeleteMessagesForEveryone : nil)
                    
                    
                    if let thrid = thrid {
                        verifyAlert(for: self.window, header: strings().chatConfirmDeleteMessages1Other(messages.count), information: nil, ok: strings().confirmDelete, option: thrid, successHandler: { [weak self] result in
                            guard let `self` = self else {return}
                            
                            let type:InteractiveMessagesDeletionType
                            switch result {
                            case .basic:
                                type = .forLocalPeer
                            case .thrid:
                                type = .forEveryone
                            }
                            _ = self.context.engine.messages.deleteMessagesInteractively(messageIds: messageIds, type: type).start()
                        })
                    } else {
                        _ = self.context.engine.messages.deleteMessagesInteractively(messageIds: messageIds, type: .forLocalPeer).start()
                    }
                }
            }))
        }
    }
    
    private func updateMainPhoto() {
        if let item = self.pager.selectedItem {
            if let index = self.pager.index(for: item) {
                if case let .photo(_, _, _, reference, _, _, _, _, _) = item.entry {
                    if let reference = reference {
                        _ = context.engine.accountData.updatePeerPhotoExisting(reference: reference).start()
                        _ = pager.merge(with: UpdateTransition<MGalleryItem>(deleted: [index], inserted: [(0, item)], updated: []))
                        pager.selectedIndex.set(0)
                    }
                }
            }
            
        }
    }
    
    private func deletePhoto() {
        if let item = self.pager.selectedItem {
            if let index = self.pager.index(for: item) {
                let isEmpty = pager.merge(with: UpdateTransition<MGalleryItem>(deleted: [index], inserted: [], updated: []))
                
                if isEmpty {
                    close()
                }
                
                pager.selectedIndex.set(index)
                
                if case let .photo(_, _, _, reference, _, _, _, _, _) = item.entry {
                    _ = context.engine.accountData.removeAccountPhoto(reference: index == 0 ? nil : reference).start()
                }
            }
            
        }
    }
    
    
    public var contextMenu:ContextMenu {
        let menu = ContextMenu(presentation: .current(darkPalette), betterInside: true)
        let context = self.context
        let window = self.window

        if let item = self.pager.selectedItem, item.entry.message?.adAttribute == nil {
            if !(item is MGalleryExternalVideoItem) {
                if item.entry.message?.isCopyProtected(cachedData: self.cachedPeerData) == true {

                } else {
                    menu.addItem(ContextMenuItem(strings().galleryContextSaveAs, handler: { [weak self] in
                        self?.saveAs()
                    }, itemImage: MenuAnimation.menu_save_as.value))
                }
            }
            if item.entry.message?.isCopyProtected(cachedData: self.cachedPeerData) == true {
                
            } else {
                if let text = self.pager.selectedText {
                    menu.addItem(ContextMenuItem(strings().chatCopySelectedText, handler: {
                        copyToClipboard(text)
                    }, itemImage: MenuAnimation.menu_copy.value))
                    
                    let fromLang = Translate.detectLanguage(for: text)
                    let toLang = context.sharedContext.baseSettings.doNotTranslate.union([appAppearance.languageCode])
                    
                    if fromLang == nil || !toLang.contains(fromLang!) {
                        menu.addItem(ContextMenuItem.init(strings().peerInfoTranslate, handler: {
                            GalleryHooks.shared.showTranslate(context, fromLang, appAppearance.languageCode, text, window)
                        }, itemImage: MenuAnimation.menu_translate.value))
                    }
                }
            }
            
            
            if let _ = self.contentInteractions {
                menu.addItem(ContextMenuItem(strings().galleryContextShowMessage, handler: { [weak self] in
                    self?.showMessage()
                }, itemImage: MenuAnimation.menu_show_message.value))
            }
            if item.entry.isProtected == true || item.entry.message?.isCopyProtected(cachedData: self.cachedPeerData) == true {

            } else {
                menu.addItem(ContextMenuItem(strings().galleryContextCopyToClipboard, handler: { [weak self] in
                    self?.copy(nil)
                }, itemImage: MenuAnimation.menu_copy_media.value))
            }
            
            if let recognition = self.pager.recognition, self.pager.selectedText == nil {
                if #available(macOS 10.15, *) {
                    if recognition.canTranslate() {
                        let text: String = !recognition.hasTranslation() ? strings().galleryTranslate : strings().galleryHideTranslation
                        menu.addItem(ContextMenuItem.init(text, handler: { [weak recognition] in
                            recognition?.toggleTranslate(to: appAppearance.languageCode)
                        }, itemImage: MenuAnimation.menu_translate.value))
                    }
                }
            }
            
            if let recognition = self.pager.recognition, recognition.canLiftSubject, self.pager.selectedText == nil, item.entry.isProtected == false, item.entry.message?.isCopyProtected(cachedData: self.cachedPeerData) != true {
                let point = NSApp.currentEvent?.locationInWindow
                menu.addItem(ContextMenuItem(strings().galleryContextCopySubject, handler: { [weak recognition] in
                    recognition?.copySubject(at: point)
                }, itemImage: MenuAnimation.menu_copy_media.value))
                
                if let message = item.entry.message, let send = GalleryHooks.shared.stickerSender(context, message) {
                    menu.addItem(ContextMenuItem(strings().galleryContextSendSubjectAsSticker, handler: { [weak self, weak recognition] in
                        recognition?.sendSubjectAsSticker(at: point, send: { path in
                            self?.close()
                            send(path)
                        })
                    }, itemImage: MenuAnimation.menu_smile.value))
                }
            }
            
        }
        
        
        return menu
    }
    
    
    public func saveAs(_ fast: Bool = false) -> Void {
        if let item = self.pager.selectedItem, item.entry.message?.adAttribute == nil {
            let isProtected = item.entry.isProtected || item.entry.message?.isCopyProtected(cachedData: self.cachedPeerData) == true

            if !(item is MGalleryExternalVideoItem), !isProtected {
                let isPhoto = item is MGalleryPhotoItem || item is MGalleryPeerPhotoItem
                let path = item.realStatus |> take(1) |> deliverOnMainQueue |> mapToSignal { [weak self] status -> Signal<String, NoError> in
                    guard let self else {
                        return .complete()
                    }
                    switch status {
                    case .Local:
                        return item.path.get() |> take(1)
                    default:
                        alert(for: self.window, info: isPhoto ? strings().galleryWaitDownloadPhoto : strings().galleryWaitDownloadVideo)
                        return .complete()
                    }
                }
                operationDisposable.set((path |> deliverOnMainQueue).start(next: { [weak self] path in
                    if let strongSelf = self {
                        if fast {

                            let text: String
                            if item is MGalleryVideoItem {
                                 text = strings().galleryViewFastSaveVideo1
                            } else if item is MGalleryGIFItem {
                                text = strings().galleryViewFastSaveGif1
                            } else {
                                text = strings().galleryViewFastSaveImage1
                            }

                            let dateFormatter = makeNewDateFormatter()
                            dateFormatter.dateFormat = "yyyy-MM-dd HH.mm.ss"


                            let file: TelegramMediaFile?
                            if let item = item as? MGalleryVideoItem {
                                file = item.media
                            } else if let item = item as? MGalleryGIFItem {
                                file = item.media
                            } else if let photo = item as? MGalleryPhotoItem {
                                file = photo.entry.file ?? TelegramMediaFile(fileId: MediaId(namespace: 0, id: arc4random64()), partialReference: nil, resource: photo.media.representations.last!.resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "image/jpeg", size: nil, attributes: [.FileName(fileName: "photo_\(dateFormatter.string(from: Date())).jpeg")], alternativeRepresentations: [])
                            } else if let photo = item as? MGalleryPeerPhotoItem {
                                file = TelegramMediaFile(fileId: MediaId(namespace: 0, id: arc4random64()), partialReference: nil, resource: photo.media.representations.last!.resource, previewRepresentations: [], videoThumbnails: [], immediateThumbnailData: nil, mimeType: "image/jpeg", size: nil, attributes: [.FileName(fileName: "photo_\(dateFormatter.string(from: Date())).jpeg")], alternativeRepresentations: [])
                            } else {
                                file = nil
                            }

                            let context = strongSelf.context
                            let attributedText = parseMarkdownIntoAttributedString(text, attributes: MarkdownAttributes(body: MarkdownAttributeSet(font: .bold(15), textColor: .white), bold: MarkdownAttributeSet(font: .bold(15), textColor: .white), link: MarkdownAttributeSet(font: .bold(15), textColor: .link), linkAttribute: { contents in
                                return GeneralRowsHooks.shared.linkAttribute(contents, { _ in })
                            })).mutableCopy() as! NSMutableAttributedString

                            let layout = TextViewLayout(attributedText, alignment: .center, lineSpacing: 5.0, alwaysStaticItems: true)
                            layout.interactions = TextViewInteractions(processURL: { [weak strongSelf] url  in
                                 if let file = file {
                                    showInFinder(file, account: context.account)
                                    strongSelf?.close(false)
                                }
                            })
                            layout.measure(width: 160)

                            if let file = file {

                                _ = (copyToDownloads(file, postbox: context.account.postbox, saveAnyway: true) |> map { _ in } |> deliverOnMainQueue |> take(1) |> then (showSaveModal(for: strongSelf.window, context: context, animation: LocalAnimatedSticker.success_saved, shouldBlur: false, text: layout, delay: 3.0))).start()
                            } else {
                                savePanel(file: path.nsstring.deletingPathExtension, ext: path.nsstring.pathExtension, for: strongSelf.window)
                            }
                        } else {
                            savePanel(file: path.nsstring.deletingPathExtension, ext: path.nsstring.pathExtension, for: strongSelf.window)
                        }
                    }
                }))

            }

        }
    }

    public func showMessage() -> Void {
        let message = self.pager.selectedItem?.entry.message
        close()
        if let message = message {
            contentInteractions?.showMessage(message)
        }
    }
    
    public func showSharedMedia() {
        close()
        if let message = self.pager.selectedItem?.entry.message {
            GalleryHooks.shared.openSharedMedia(context, message.id.peerId)
        }
    }
    
    public func openInfo(_ peerId: PeerId, _ toChat: Bool = false, _ messageId: MessageId? = nil, _ initialAction: ChatInitialAction? = nil) {
        close()
        closeAllModals()
        GalleryHooks.shared.openInfo(context, peerId, toChat, messageId, initialAction)
    }
    
    public func share(_ control: Control) -> Void {
        guard viewer === self else { return }
        let generation = presentationGeneration
        let messages = pager.thumbsControl.items.compactMap { $0.entry.message }
        if let message = self.pager.selectedItem?.entry.message {
            if message.groupInfo != nil, !messages.isEmpty {
                var items:[ContextMenuItem] = []
                
                let thisTitle: String
                let thisMedia = message.anyMedia ?? message.effectiveMedia.first
                if thisMedia is TelegramMediaImage {
                    thisTitle = strings().galleryContextShareThisPhoto
                } else if thisMedia?.isVideoFile == true {
                    thisTitle = strings().galleryContextShareThisVideo
                } else if thisMedia?.isGraphicFile == true {
                    thisTitle = strings().galleryContextShareThisPhoto
                } else {
                    thisTitle = strings().galleryContextShareThisFile
                }
                
                items.append(ContextMenuItem(thisTitle, handler: { [weak self] in
                    guard let self, viewer === self, self.presentationGeneration == generation else { return }
                    GalleryHooks.shared.showShareObserved(self.context, message, nil, self.window)
                }, itemImage: MenuAnimation.menu_share.value))
                
                let allTitle: String
                if messages.filter({ ($0.anyMedia ?? $0.effectiveMedia.first) is TelegramMediaImage }).count == messages.count {
                    allTitle = strings().galleryContextShareAllPhotosOther(messages.count)
                } else if messages.filter({ ($0.anyMedia ?? $0.effectiveMedia.first)?.isVideoFile == true }).count == messages.count {
                    allTitle = strings().galleryContextShareAllVideosOther(messages.count)
                } else if messages.filter({ ($0.anyMedia ?? $0.effectiveMedia.first)?.isGraphicFile == true }).count == messages.count {
                    allTitle = strings().galleryContextShareAllPhotosOther(messages.count)
                } else {
                    allTitle = strings().galleryContextShareAllItemsOther(messages.count)
                }
                
                items.append(ContextMenuItem(allTitle, handler: { [weak self] in
                    guard let self, viewer === self, self.presentationGeneration == generation else { return }
                    GalleryHooks.shared.showShareObserved(self.context, message, messages, self.window)
                }, itemImage: MenuAnimation.menu_share.value))
                
                let menu = ContextMenu(presentation: .current(darkPalette), betterInside: true)
                for item in items {
                    menu.addItem(item)
                }
                if let event = NSApp.currentEvent {
                    AppMenu.show(menu: menu, event: event, for: control)
                }
            } else {
                GalleryHooks.shared.showShareObserved(self.context, message, nil, self.window)
            }
        }
    }
    
    @objc public func copy(_ sender:Any? = nil) -> Void {
        
        if let item = self.pager.selectedItem, !self.pager.copySelectedText() {
            if let message = item.entry.message, item.entry.isProtected || message.isCopyProtected(cachedData: self.cachedPeerData) {
                showProtectedCopyAlert(message, for: self.window)
            } else  if !(item is MGalleryExternalVideoItem), item.entry.message?.containsSecretMedia != true {
                operationDisposable.set((item.path.get() |> take(1) |> deliverOnMainQueue).start(next: { path in
                    let pb = NSPasteboard.general
                    pb.clearContents()
                    var url = NSURL(fileURLWithPath: path)
                    let image = NSImage(contentsOf: url as URL)

                    let dst = try? FileManager.default.destinationOfSymbolicLink(atPath: path)
                    if let dst = dst {
                        let updated = NSTemporaryDirectory() + dst.nsstring.lastPathComponent + "." +  path.nsstring.pathExtension
                        try? FileManager.default.copyItem(atPath: dst, toPath: updated)
                        url = NSURL(fileURLWithPath: updated)
                    }
                    pb.writeObjects([url, image].compactMap { $0 })
                }))
            } else if let item = item as? MGalleryExternalVideoItem {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(item.content.url, forType: .string)
                
            }
        }
    }

    
    
    
    fileprivate func show(_ animated: Bool = true, _ ignoreStableId:AnyHashable? = nil) -> Void {
        presentationGeneration += 1
        viewer = self
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidBecomeKey), name: NSWindow.didBecomeKeyNotification, object: window)
        NotificationCenter.default.addObserver(self, selector: #selector(windowDidResignKey), name: NSWindow.didResignKeyNotification, object: window)
        context.window.resignFirstResponder()
        self.window.makeKeyAndOrderFront(nil)
        //window.makeFirstResponder(self)
        //closePipVideo()
       // backgroundView.alphaValue = 0
        

        
        backgroundView._change(opacity: 0, animated: false)
        self.readyDispose.set((self.ready.get() |> take(1) |> deliverOnMainQueue |> beforeNext { [weak self] _ in
            if let strongSelf = self {

                if let startTime = strongSelf.contentInteractions?.timeCodeInitializer {
                    if let item = strongSelf.pager.selectedItem as? MGalleryVideoItem {
                        item.startTime = startTime
                    }
                }
            
                self?.updateCaptureExclusion()

                
                strongSelf.pager.animateIn(from: { [weak strongSelf] stableId -> NSView? in
                    
                    
                    if let firstStableId = strongSelf?.firstStableId, let innerIndex = stableId.base as? Int {
                        if let ignore = ignoreStableId?.base as? Int, ignore == innerIndex {
                            return nil
                        }
                        guard let view = strongSelf?.delegate?.contentInteractionView(for: firstStableId, animateIn: false), view.subviews.indices.contains(innerIndex) else {
                            return nil
                        }
                        return view.subviews[innerIndex]
                    }
                    if ignoreStableId != stableId {
                        return strongSelf?.delegate?.contentInteractionView(for: stableId, animateIn: false)
                    }
                    
                    return nil
                }, completion:{ [weak strongSelf] in
                    //strongSelf?.backgroundView.alphaValue = 1.0
                    strongSelf?.controls.animateIn()
                    strongSelf?.backgroundView._change(opacity: 1, animated: true)
                }, addAccesoryOnCopiedView: { stableId, view in
                    if stableId != nil {
                        //self?.delegate?.addAccesoryOnCopiedView(for: stableId, view: view)
                    }
                }, addVideoTimebase: { stableId, view  in
                    
                })
            }
            
        }).start(completed:  {}));
        
    }
    
    public func close(_ animated:Bool = false) -> Void {
        disposable.dispose()
        readyDispose.set(nil)
        didSetReady = false
        NotificationCenter.default.removeObserver(self)
        if animated {
            let presentationGeneration = self.presentationGeneration
            backgroundView._change(opacity: 0, animated: true)
            controls.animateOut()
            self.pager.animateOut(to: { [weak self] stableId in
                if let firstStableId = self?.firstStableId, let innerIndex = stableId.base as? Int {
                    guard let view = self?.delegate?.contentInteractionView(for: firstStableId, animateIn: false), view.subviews.indices.contains(innerIndex) else {
                        return nil
                    }
                    return view.subviews[innerIndex]
                }
                return self?.delegate?.contentInteractionView(for: stableId, animateIn: true)
            }, completion: { [weak self] interactive, stableId in
                guard let self, self.presentationGeneration == presentationGeneration, viewer === self else {
                    return
                }
                if let stableId = stableId {
                    self.delegate?.interactionControllerDidFinishAnimation(interactive: interactive, for: stableId)
                }
                self.removeCaptureExclusion()
                self.window.orderOut(nil)
                viewer = nil
                playPipIfNeeded()
            }, addAccesoryOnCopiedView: { [weak self] stableId, view in
                if let stableId = stableId {
                    self?.delegate?.addAccesoryOnCopiedView(for: stableId, view: view)
                }
            }, addVideoTimebase: { stableId, view  in
                
            })
        } else {
            window.orderOut(nil)
            self.removeCaptureExclusion()
            if viewer === self {
                viewer = nil
                playPipIfNeeded()
            }
        }
        
    }
    
    deinit {
        clean()
    }
    
    public func clean() {
        removeCaptureExclusion()
        indexDisposable.dispose()
        disposable.dispose()
        operationDisposable.dispose()
        window.removeAllHandlers(for: self)
        readyDispose.dispose()
        messagesActionDisposable.dispose()
        self.contentInteractions?.remove_timeCodeInitializer()
    }

    private func updateCaptureExclusion() {
        if viewer === self {
        }
        let isProtected = pager.selectedItem?.entry.isProtected == true
            || pager.selectedItem?.entry.message?.isCopyProtected(cachedData: cachedPeerData) == true
        if isProtected {
            if captureExclusionToken == nil {
                captureExclusionToken = context.captureExclusionManager.addExclusion(for: window, view: self.pager.view)
            } else {
                context.captureExclusionManager.forceReapply(for: window)
            }
        } else {
            removeCaptureExclusion()
        }
    }

    private func removeCaptureExclusion() {
        if let token = captureExclusionToken {
            context.captureExclusionManager.removeExclusion(token, for: window)
            captureExclusionToken = nil
        }
    }

}


public func closeGalleryViewer(_ animated: Bool) {
    viewer?.close(animated)
}


public func showChatGallery(context: any AccountContextProtocol, message:Message, _ delegate:InteractionContentViewProtocol? = nil, _ contentInteractions:(any GalleryContentInteractions)? = nil, type: GalleryAppearType = .history, reversed: Bool = false, chatMode: ChatMode?, chatLocation: ChatLocation?, contextHolder: Atomic<ChatLocationContextHolder?> = Atomic(value: nil), cachedPeerData: CachedPeerData? = nil) {
    if viewer == nil {
        viewer?.clean()
        let gallery = GalleryViewer(context: context, message: message, delegate, contentInteractions, type: type, reversed: reversed, chatMode: chatMode, chatLocation: chatLocation, contextHolder: contextHolder, cachedPeerData: cachedPeerData)
        gallery.show()
    }
}

public func showGalleryFromPip(item: MGalleryItem, gallery: GalleryViewer, delegate:InteractionContentViewProtocol? = nil, contentInteractions:(any GalleryContentInteractions)? = nil, type: GalleryAppearType = .history) {
    if viewer == nil {
        viewer?.clean()
        gallery.show(true, item.stableId)
    }
}

public func showPhotosGallery(context: any AccountContextProtocol, peerId:PeerId, firstStableId:AnyHashable, _ delegate:InteractionContentViewProtocol? = nil, _ contentInteractions:(any GalleryContentInteractions)? = nil) {
    if viewer == nil {
        viewer?.clean()
        let gallery = GalleryViewer(context: context, peerId: peerId, firstStableId: firstStableId, delegate, contentInteractions, chatMode: nil, chatLocation: nil)
        gallery.show()
    }
}

public func showInstantViewGallery(context: any AccountContextProtocol, medias:[InstantPageMedia], firstIndex: Int, firstStableId:AnyHashable? = nil, parent: Message? = nil, _ delegate: InteractionContentViewProtocol? = nil, _ contentInteractions:(any GalleryContentInteractions)? = nil) {
    if viewer == nil {
        viewer?.clean()
        let gallery = GalleryViewer(context: context, instantMedias: medias, firstIndex: firstIndex, firstStableId: firstStableId, parent: parent, delegate, contentInteractions, chatMode: nil, chatLocation: nil)
        gallery.show()
    }
}

public func showGalleryMedia(context: any AccountContextProtocol, medias:[Media], parent: Message, firstIndex: Int, firstStableId:AnyHashable? = nil, _ delegate: InteractionContentViewProtocol? = nil, _ contentInteractions:(any GalleryContentInteractions)? = nil) {
    if viewer == nil {
        viewer?.clean()
        let gallery = GalleryViewer(context: context, media: medias, firstIndex: firstIndex, firstStableId: firstStableId, parent: parent, delegate, contentInteractions)
        gallery.show()
    }
}


public func showSecureIdDocumentsGallery(context: any AccountContextProtocol, medias:[SecureIdDocumentValue], firstIndex: Int, _ delegate: InteractionContentViewProtocol? = nil) {
    if viewer == nil {
        viewer?.clean()
        let gallery = GalleryViewer(context: context, secureIdMedias: medias, firstIndex: firstIndex, delegate, chatMode: nil, chatLocation: nil)
        gallery.show()
    }
   
}

