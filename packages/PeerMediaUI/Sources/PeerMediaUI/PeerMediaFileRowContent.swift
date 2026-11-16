import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
import FoundationUtils
import ChatUI
import GalleryUI
import GeneralRows
import Localization
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils
import ChatModeTypes
import Strings




public class PeerMediaFileRowItem: PeerMediaRowItem {
    
    public private(set) var nameLayout:TextViewLayout
    public private(set) var actionLayout:TextViewLayout
    public private(set) var actionLayoutLocal:TextViewLayout
    public private(set) var iconArguments:TransformImageArguments?
    public private(set) var icon:TelegramMediaImage?
    public private(set) var docIcon:CGImage?

    public private(set) var file:TelegramMediaFile?
    
    public private(set) var docTitle:NSAttributedString?
    public override init(_ initialSize:NSSize, _ interface:ChatInteraction, _ object: PeerMediaSharedEntry, galleryType: GalleryAppearType = .history, gallery: @escaping(Message, GalleryAppearType)->Void, viewType: GeneralViewType = .legacy, inset: NSEdgeInsets = NSEdgeInsetsZero, customTheme: GeneralRowItem.Theme? = nil) {
        
        
        let message = object.message!
        let file = message.file!
        self.file = file
        
        nameLayout = TextViewLayout(.initialize(string: file.fileName ?? "Unknown", color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1, truncationType: .end)
        
        let dateFormatter = DateSelectorUtil.mediaFileDate
        
        let dateString = dateFormatter.string(from: Date(timeIntervalSince1970: Double(TimeInterval(message.timestamp) - interface.interactionContext.timeDifference)))
        
        actionLayout = TextViewLayout(NSAttributedString.initialize(string: "\(dataSizeString(file.size ?? 0, formatting: DataSizeStringFormatting.current)) • \(dateString)",color: theme.colors.grayText, font: NSFont.normal(12.5)), maximumNumberOfLines: 1, truncationType: .end, alwaysStaticItems: true)
        
        let localAction = NSMutableAttributedString()
        let range = localAction.append(string: strings().contextShowInFinder, color: theme.colors.link, font: .normal(.text))
        localAction.add(link: LinkHooks.shared.callbackLink("finder", { _ in
            showInFinder(file, account: interface.interactionContext.account)
        }), for: range)
        actionLayoutLocal = TextViewLayout(localAction, maximumNumberOfLines: 1, truncationType: .end, alwaysStaticItems: true)
        actionLayoutLocal.interactions = LinkHooks.shared.globalLinkExecutor()
        
        let iconImageRepresentation:TelegramMediaImageRepresentation? = firstImageRepresentation(file.previewRepresentations)
        
        let fileName: String = file.fileName ?? ""
        
        var fileExtension: String = "file"
        if let range = fileName.range(of: ".", options: [.backwards]) {
            fileExtension = fileName[range.upperBound...].lowercased()
        }
        if fileExtension.length > 5 {
            fileExtension = "file"
        }
        docIcon = extensionImage(fileExtension: fileExtension)
        
        if let iconImageRepresentation = iconImageRepresentation {
            iconArguments = TransformImageArguments(corners: ImageCorners(radius: .cornerRadius), imageSize: iconImageRepresentation.dimensions.size.aspectFilled(PeerMediaIconSize), boundingSize: PeerMediaIconSize, intrinsicInsets: NSEdgeInsets())
            icon = TelegramMediaImage(imageId: file.fileId, representations: [iconImageRepresentation], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
        } else {
           
            
            docTitle = NSAttributedString.initialize(string: fileExtension, color: theme.colors.text, font: .medium(.text))

        }
        super.init(initialSize, interface, object, galleryType: galleryType, gallery: gallery, viewType: viewType, inset: inset, customTheme: customTheme)
    }
    
    
    public override func makeSize(_ width: CGFloat, oldWidth:CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        nameLayout.measure(width: self.blockWidth - contentInset.left - contentInset.right - self.viewType.innerInset.left - self.viewType.innerInset.right)
        actionLayout.measure(width: self.blockWidth - contentInset.left - contentInset.right - self.viewType.innerInset.left - self.viewType.innerInset.right)
        actionLayoutLocal.measure(width: self.blockWidth - contentInset.left - contentInset.right - self.viewType.innerInset.left - self.viewType.innerInset.right)
        return success
    }
    
    public override func viewClass() -> AnyClass {
        return PeerMediaFileRowView.self
    }

    public override var accessibilityLabel: String? {
        return nameLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return actionLayout.attributedString.string
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        if interface.presentation.state == .selecting {
            interface.update({ $0.withToggledSelectedMessage(message.id) })
            return true
        }
        guard let view = view as? PeerMediaFileRowView else {
            return false
        }
        view.executeInteraction(true)
        return true
    }
}

public class PeerMediaFileRowView : PeerMediaRowView {
    
    public var nameView:TextView = TextView()
    public var actionView:TextView = TextView()
    public var imageView:TransformImageView = TransformImageView(frame:NSMakeRect(0, 0, 40, 40))
    
    private var downloadStatusControl:ImageView?
    private var downloadProgressView:LinearProgressControl?
    
    private let statusDisposable = MetaDisposable()
    private let fetchControls = Atomic<FetchControls?>(value: nil)
    private var fetchStatus: MediaResourceStatus?
    private let fetchDisposable = MetaDisposable()
    
    public required init(frame frameRect: NSRect) {
        nameView.isSelectable = false
        nameView.userInteractionEnabled = false
        actionView.isSelectable = false
        super.init(frame: frameRect)
        addSubview(imageView)
        addSubview(nameView)
        addSubview(actionView)
        
    }
    
    
    public func cancel() -> Void {
        cancelFetching()
    }
    
    public func delete() -> Void {
        if let item = item as? PeerMediaFileRowItem {
            let messageId = item.message.id
            let engine = item.interface.interactionContext.engine
            _ = item.interface.interactionContext.account.postbox.transaction { transaction -> Void in
                engine.messages.deleteMessages(transaction: transaction, ids: [messageId])
            }.start()
        }
    }
    
    public func cancelFetching() {
        if let item = item as? PeerMediaFileRowItem, let file = item.file {
            if item.galleryType != .recentDownloaded {
                messageMediaFileCancelInteractiveFetch(context: item.context, messageId: item.message.id, file: file)
            } else {
                toggleInteractiveFetchPaused(context: item.context, file: file, isPaused: true)
            }
        }
    }
    
    public func open() -> Void {
        if let item = item as? PeerMediaFileRowItem, let file = item.file {
            if file.isGraphicFile {
                item.gallery(item.message, item.galleryType)
            } else {
               PeerMediaUIHooks.shared.showQuickLookPreview(item.interface.interactionContext, file, item.message.chatStableId, item.table)
            }
        }
    }
    
    public func fetch(userInitiated: Bool) -> Void {
        if let item = item as? PeerMediaFileRowItem, let file = item.file {
            fetchDisposable.set(messageMediaFileInteractiveFetched(context: item.context, messageId: item.message.id, messageReference: .init(item.message), file: file, userInitiated: userInitiated).start())
        }
    }
    
    public func executeInteraction(_ isControl:Bool) -> Void {
        if let fetchStatus = self.fetchStatus, let item = item as? PeerMediaFileRowItem, let file = item.file {
            switch fetchStatus {
            case .Fetching:
                if isControl {
                    if item.message.flags.contains(.Unsent) && !item.message.flags.contains(.Failed) {
                        delete()
                    }
                    cancel()
                } else {
                    open()
                }
            case .Remote:
                if isControl {
                    fetch(userInitiated: true)
                } else {
                    open()
                }
            case .Paused:
                if item.galleryType == .recentDownloaded {
                    toggleInteractiveFetchPaused(context: item.context, file: file, isPaused: false)
                } else {
                    cancel()
                }
            case .Local:
                open()
                break
                
            }
        }
    }
    
    public override func mouseUp(with event: NSEvent) {
        if let item = item as? PeerMediaRowItem, !(item.interface.presentation.state == .selecting) {
            if imageView._mouseInside() {
                executeInteraction(true)
                return
            } else if let status = self.fetchStatus {
                switch status {
                case .Remote:
                    executeInteraction(true)
                case .Fetching, .Paused:
                    executeInteraction(true)
                default:
                    break
                }
            }
        }
        super.mouseUp(with: event)
    }
    
    public override func layout() {
        super.layout()
        if let item = item as? PeerMediaRowItem {
            if let downloadProgressView = downloadProgressView {
                downloadProgressView.frame = NSMakeRect(item.separatorOffset, containerView.frame.height - 4, containerView.frame.width - item.separatorOffset - item.viewType.innerInset.right, 4)
            }
            if let downloadStatusControl = downloadStatusControl {
                downloadStatusControl.setFrameOrigin(NSMakePoint(item.contentInset.left, contentView.frame.height - 4 - downloadStatusControl.frame.height))
                actionView.setFrameOrigin(item.contentInset.left + downloadStatusControl.frame.width + 2.0,actionView.frame.minY)
            } else {
                actionView.setFrameOrigin(item.contentInset.left, actionView.frame.minY)
            }
        }
        
    }
    
    public override func interactionContentView(for innerId: AnyHashable, animateIn: Bool ) -> NSView {
        return imageView
    }
    
    deinit {
        statusDisposable.dispose()
    }
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func updateSelectingMode(with selectingMode: Bool, animated: Bool = false) {
        super.updateSelectingMode(with: selectingMode, animated: animated)
        if let status = fetchStatus {
            if case .Local = status {
               self.actionView.userInteractionEnabled = !selectingMode
            } else {
               self.actionView.userInteractionEnabled = false
            }
        }
    }
    
    public override func set(item: TableRowItem, animated: Bool) {
        let previous = self.item as? PeerMediaFileRowItem
        super.set(item: item, animated: animated)
        
        
        
        
        statusDisposable.set(nil)
        if let item = item as? PeerMediaFileRowItem {
            

            
            nameView.update(item.nameLayout, origin: NSMakePoint(item.contentInset.left, item.contentInset.top + 2))
            if actionView.textLayout == nil {
                actionView.update(item.actionLayout, origin: NSMakePoint(item.contentInset.left, item.contentSize.height - item.actionLayout.layoutSize.height - item.contentInset.bottom - 2))
            }

            let updateIconImageSignal:Signal<ImageDataTransformation,NoError>
            if let icon = item.icon {
                updateIconImageSignal = chatWebpageSnippetPhoto(account: item.interface.interactionContext.account, imageReference: ImageMediaReference.message(message: MessageReference(item.message), media: icon), scale: backingScaleFactor, small:true)
            } else {
                updateIconImageSignal = .complete()
            }
            
            
            if let icon = item.icon, let arguments = item.iconArguments {
                imageView.setSignal(signal: cachedMedia(media: icon, arguments: arguments, scale: System.backingScale), clearInstantly: previous?.message.id != item.message.id)
            } else {
                imageView.clear()
            }
            
            if !imageView.isFullyLoaded {
                if !imageView.hasImage {
                    imageView.layer?.contents = item.docIcon
                }
                imageView.setSignal(updateIconImageSignal, clearInstantly: false, animate: true, cacheImage: { result in
                    if let icon = item.icon, let arguments = item.iconArguments {
                        cacheMedia(result, media: icon, arguments: arguments, scale: System.backingScale, positionFlags: nil)
                    }
                })
            }
            
            if let arguments = item.iconArguments {
                imageView.set(arguments: arguments)
            }
            
            
            var updatedStatusSignal: Signal<MediaResourceStatus, NoError>?
            var updatedFetchControls: FetchControls?
            
            let context = item.interface.interactionContext
            if let file = item.file {
                updatedStatusSignal = chatMessageFileStatus(context: context, message: item.message, file: file, approximateSynchronousValue: false)
                updatedFetchControls = FetchControls(fetch: { [weak self] in
                    self?.executeInteraction(true)
                })
            }
           
            let animated:Atomic<Bool> = Atomic(value:false)
            
            if let updatedStatusSignal = updatedStatusSignal {
                self.statusDisposable.set((updatedStatusSignal |> deliverOnMainQueue).start(next: { [weak self] status in
                    if let strongSelf = self {
                        strongSelf.fetchStatus = status
                        if case .Local = status {
                            strongSelf.actionView.userInteractionEnabled = (strongSelf.item as? PeerMediaRowItem)?.interface.presentation.state != .selecting
                        } else {
                            strongSelf.actionView.userInteractionEnabled = false
                        }
                        
                        let initStatusControlIfNeeded = { [weak strongSelf] in
                           if let strongSelf = strongSelf, strongSelf.downloadStatusControl == nil {
                               strongSelf.downloadStatusControl = ImageView(frame:NSMakeRect(0, 0, theme.icons.peerMediaDownloadFileStart.backingSize.width, theme.icons.peerMediaDownloadFileStart.backingSize.height))
                               strongSelf.downloadStatusControl?.animates = true
                               strongSelf.addSubview(strongSelf.downloadStatusControl!)
                               strongSelf.needsLayout = true
                           }
                       }
                        
                        let initDownloadControlIfNeeded = { [weak strongSelf] in
                            if let strongSelf = strongSelf {
                                if strongSelf.downloadStatusControl == nil {
                                    strongSelf.downloadStatusControl = ImageView(frame:NSMakeRect(0, 0, theme.icons.peerMediaDownloadFileStart.backingSize.width, theme.icons.peerMediaDownloadFileStart.backingSize.height))
                                    strongSelf.downloadStatusControl?.animates = true
                                    strongSelf.addSubview(strongSelf.downloadStatusControl!)
                                }
                                if strongSelf.downloadProgressView == nil {
                                    strongSelf.downloadProgressView = LinearProgressControl()
                                    strongSelf.downloadProgressView?.cornerRadius = 2.0
                                    strongSelf.containerView.addSubview(strongSelf.downloadProgressView!)
                                }
                                strongSelf.downloadProgressView?.style = ControlStyle(foregroundColor:theme.colors.accent)
                                strongSelf.needsLayout = true
                            }
                        }
                        
                        let deinitDownloadControls = { [weak strongSelf] in
                            if let strongSelf = strongSelf {
                                if let downloadProgressView = strongSelf.downloadProgressView {
                                    strongSelf.downloadProgressView = nil
                                    downloadProgressView.set(progress: 1.0)
                                    downloadProgressView.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak downloadProgressView] _ in
                                        downloadProgressView?.removeFromSuperview()
                                    })
                                }
                                strongSelf.downloadStatusControl?.removeFromSuperview()
                                strongSelf.downloadStatusControl = nil
                            }
                            strongSelf?.needsLayout = true
                        }
                        
                        let deinitProgressControl = { [weak strongSelf] in
                            if let strongSelf = strongSelf {
                                strongSelf.downloadProgressView?.removeFromSuperview()
                                strongSelf.downloadProgressView = nil
                            }
                            strongSelf?.needsLayout = true
                        }

                        
                        switch status {
                        case .Local:
                            deinitDownloadControls()
                            strongSelf.actionView.update(item.actionLayoutLocal)
                        case .Remote, .Paused:
                            deinitProgressControl()
                            initStatusControlIfNeeded()
                            strongSelf.downloadStatusControl?.image = theme.icons.peerMediaDownloadFileStart
                            strongSelf.actionView.update(item.actionLayout)
                            break
                        case let .Fetching(_, progress):
                            
                            initDownloadControlIfNeeded()
                            
                            let animated = animated.swap(true)
                            
                            strongSelf.downloadProgressView?.set(progress: CGFloat(progress), animated: animated)
                            
                            strongSelf.downloadStatusControl?.image = theme.icons.peerMediaDownloadFilePause
                            
                            break
                        }
                        
                    }
                }))
            }

            if let updatedFetchControls = updatedFetchControls {
                let _ = fetchControls.swap(updatedFetchControls)
            }
        }
        self.needsLayout = true
    }
    
}
