import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
import TelegramMediaResources
import AudioPlayerCore
import ChatUI
import GalleryUI
import GeneralRows
import TelegramMediaUtils
import TelegramTheme
import TelegramUtils

public class PeerMediaMusicRowItem: PeerMediaRowItem {
    fileprivate let textLayout:TextViewLayout
    fileprivate let descLayout:TextViewLayout?
    public let file:TelegramMediaFile
    fileprivate let thumbResource: TelegramMediaResource?
    fileprivate let isCompactPlayer: Bool
    fileprivate let music:(Message, GalleryAppearType)->Void
    fileprivate let send: ((Message) -> Void)?
    fileprivate let inModal: Bool
    fileprivate let contextMenuItems: (Message)->[ContextMenuItem]
    public init(_ initialSize:NSSize, _ interface:ChatInteraction, _ object: PeerMediaSharedEntry, isCompactPlayer: Bool = false, galleryType: GalleryAppearType = .history, gallery: @escaping(Message, GalleryAppearType)->Void = { _, _ in }, music: @escaping(Message, GalleryAppearType)->Void, send: ((Message) -> Void)? = nil, viewType: GeneralViewType = .legacy, inset: NSEdgeInsets = NSEdgeInsetsZero, contextMenuItems:@escaping(Message)->[ContextMenuItem] = { _ in return [] }, inModal: Bool = false) {
        self.isCompactPlayer = isCompactPlayer
        self.contextMenuItems = contextMenuItems
        self.music = music
        self.send = send
        self.inModal = inModal
        file = object.message!.media[0] as! TelegramMediaFile
        
        let music = file.musicText
        self.textLayout = TextViewLayout(.initialize(string: music.0, color: theme.colors.text, font: .medium(.text)), maximumNumberOfLines: 1, truncationType: .end)

        if !music.1.isEmpty {
            let text: String
            if let duration = file.duration {
                text = timerText(Int(duration)) + " • " + music.1
            } else {
                text = music.1
            }
            self.descLayout = TextViewLayout(.initialize(string: text, color: theme.colors.grayText, font: .normal(.short)), maximumNumberOfLines: 1)
        } else if let size = file.size {
            self.descLayout = TextViewLayout(.initialize(string: String.prettySized(with: size), color: theme.colors.grayText, font: .normal(.short)), maximumNumberOfLines: 1)
        } else {
            descLayout = nil
        }
        let resource: TelegramMediaResource?
        if file.previewRepresentations.isEmpty {
            if !file.mimeType.contains("ogg")  {
                resource = ExternalMusicAlbumArtResource(title: file.musicText.0, performer: file.musicText.1, isThumbnail: true)
            } else {
                resource = nil
            }
        } else {
            resource = file.previewRepresentations.first!.resource
        }
        self.thumbResource = resource
        
        
        super.init(initialSize, interface, object, galleryType: galleryType, gallery: gallery, viewType: viewType, inset: inset)
        
    }
    
    public override var inset: NSEdgeInsets {
        if inModal {
            return NSEdgeInsets(left: 20, right: 20)
        } else if isCompactPlayer {
            return NSEdgeInsetsMake(5, 10, 5, 10)
        } else {
            return super.inset
        }
    }
    
    public override func makeSize(_ width: CGFloat, oldWidth: CGFloat) -> Bool {
        let success = super.makeSize(width, oldWidth: oldWidth)
        textLayout.measure(width: self.blockWidth - contentInset.left - contentInset.right - self.viewType.innerInset.left - self.viewType.innerInset.right)
        descLayout?.measure(width: self.blockWidth - contentInset.left - contentInset.right - self.viewType.innerInset.left - self.viewType.innerInset.right)
        return success
    }
    
    public override func viewClass() -> AnyClass {
        return PeerMediaMusicRowView.self
    }

    public override var accessibilityLabel: String? {
        return textLayout.attributedString.string
    }

    public override var accessibilityValue: String? {
        return descLayout?.attributedString.string
    }

    public override var accessibilityIncludesChildren: Bool {
        return false
    }

    public override func accessibilityPerformPress() -> Bool {
        switch interface.presentation.state {
        case .selecting:
            interface.update({ $0.withToggledSelectedMessage(message.id) })
            return true
        case .normal:
            guard let view = view as? PeerMediaMusicRowView else {
                return false
            }
            view.executeInteraction(false)
            return true
        default:
            return false
        }
    }
    
    public override func menuItems(in location: NSPoint) -> Signal<[ContextMenuItem], NoError> {
        if isCompactPlayer || inModal {
            return .single(contextMenuItems(self.message))
        } else {
            return super.menuItems(in: location)
        }
    }
    
}

public class PeerMediaMusicRowView : PeerMediaRowView, APDelegate {
    private let textView:TextView = TextView()
    private let descView:TextView = TextView()

    private let thumbPlaceholder: ImageView = ImageView(frame: NSMakeRect(0, 0, 40, 40))
    public let thumbView:TransformImageView = TransformImageView(frame: NSMakeRect(0, 0, 40, 40))
    private let playOverlay: View = View()
    private let playIcon: ImageView = ImageView()
    
    public var fetchStatus: MediaResourceStatus?
    public let statusDisposable = MetaDisposable()
    public let fetchDisposable = MetaDisposable()
    private var playAnimationView: PeerMediaPlayerAnimationView?
    public private(set) var fetchControls:FetchControls!
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        thumbPlaceholder.isAccessibilityDecorative = true
        playIcon.isAccessibilityDecorative = true
        textView.isSelectable = false
        textView.userInteractionEnabled = false
        
        descView.isSelectable = false
        descView.userInteractionEnabled = false
        
        addSubview(textView)
        addSubview(descView)
        addSubview(thumbPlaceholder)
        addSubview(playOverlay)
        addSubview(thumbView)
        addSubview(playIcon)
        thumbPlaceholder.image = theme.icons.playerMusicPlaceholder
        thumbPlaceholder.layer?.masksToBounds = true
        thumbPlaceholder.isEventLess = true
        thumbView.layer?.masksToBounds = true
        playOverlay.backgroundColor = NSColor.black.withAlphaComponent(0.35)
        playOverlay.setFrameSize(NSMakeSize(40, 40))
        playOverlay.isEventLess = true
        playOverlay.isHidden = true
        playIcon.image = theme.icons.chatMusicPlay
        playIcon.sizeToFit()
        playIcon.isEventLess = true
//        fetchControls = FetchControls(fetch: { [weak self] in
//            self?.executeInteraction(true)
//        })
       
      //  thumbView.fetchControls = fetchControls
    }
    
    public override var backdorColor: NSColor {
        return theme.colors.background
    }
    
    public override func mouseUp(with event: NSEvent) {
        guard let item = item as? PeerMediaMusicRowItem else {
            super.mouseUp(with: event)
            return
        }
        if item.interface.presentation.state == .normal {
            let point = thumbView.convert(event.locationInWindow, from: nil)
            let isThumbHit = NSPointInRect(point, thumbView.bounds) || (playAnimationView != nil && NSPointInRect(playAnimationView!.convert(event.locationInWindow, from: nil), playAnimationView!.bounds))
            if item.inModal, let send = item.send {
                if isThumbHit {
                    open()
                } else {
                    send(item.message)
                }
                return
            }
            executeInteraction(isThumbHit)
        } else {
            super.mouseUp(with: event)
        }
    }
    
    public override func layout() {
        super.layout()
        if let item = item as? PeerMediaMusicRowItem {
            textView.update(item.textLayout, origin: NSMakePoint(item.contentInset.left, item.contentInset.top + 2))
            
            if let descLayout = item.descLayout {
                descView.update(descLayout, origin: NSMakePoint(item.contentInset.left, item.contentSize.height - descLayout.layoutSize.height - item.contentInset.bottom - 2))
            } else {
                descView.update(nil)
                textView.centerY()
            }
            
            thumbPlaceholder.centerY(x: 0)
            thumbView.centerY(x: 0)
            playAnimationView?.centerY(x: 0)
            playOverlay.frame = thumbView.frame
            playOverlay.layer?.cornerRadius = thumbView.layer?.cornerRadius ?? 0
            playIcon.setFrameOrigin(NSMakePoint(floorToScreenPixels(backingScaleFactor, thumbView.frame.midX - playIcon.frame.width / 2), floorToScreenPixels(backingScaleFactor, thumbView.frame.midY - playIcon.frame.height / 2)))
        }
    }
    
    public func songDidChanged(song: APSongItem, for controller: APController, animated: Bool) {
        checkState()
    }
    public func songDidChangedState(song: APSongItem, for controller: APController, animated: Bool) {
        checkState()
    }
    
    public func songDidStartPlaying(song:APSongItem, for controller:APController, animated: Bool) {
        checkState()
    }
    public func songDidStopPlaying(song:APSongItem, for controller:APController, animated: Bool) {
        checkState()
    }
    public func playerDidChangedTimebase(song:APSongItem, for controller:APController, animated: Bool) {
        //checkState()
    }
    
    public func audioDidCompleteQueue(for controller:APController, animated: Bool) {
        checkState()
    }
    
    public func executeInteraction(_ isControl:Bool) -> Void {
        if let item = item as? PeerMediaMusicRowItem, item.inModal, !isControl, let send = item.send {
            send(item.message)
        } else {
            open()
        }
    }
    
    public func checkState() {
        if let item = item as? PeerMediaMusicRowItem {
            if let controller = PeerMediaUIHooks.shared.getAudioPlayer(item.context), let song = controller.currentSong {
                let isCurrentSong = item.inModal ? song.resource.id == item.file.resource.id : song.entry.isEqual(to: item.message.id)
                if isCurrentSong {
                    if playAnimationView == nil {
                        playAnimationView = PeerMediaPlayerAnimationView()
                        addSubview(playAnimationView!)
                        playAnimationView?.centerY(x: 0)
                        playAnimationView?.userInteractionEnabled = false
                        playAnimationView?.isEventLess = true
                    }
                    if item.inModal {
                        playAnimationView?.layer?.cornerRadius = playAnimationView!.frame.width / 2
                        playAnimationView?.layer?.masksToBounds = true
                    }
                    if case .playing = song.state {
                        playAnimationView?.isPlaying = true
                        playIcon.isHidden = true
                    } else if case .stoped = song.state {
                        playAnimationView?.removeFromSuperview()
                        playAnimationView = nil
                        playIcon.isHidden = !item.inModal
                    playOverlay.isHidden = !item.inModal || item.thumbResource == nil
                    } else {
                        playAnimationView?.isPlaying = false
                        playIcon.isHidden = true
                    }
                    
                } else {
                    playAnimationView?.removeFromSuperview()
                    playAnimationView = nil
                    playIcon.isHidden = !item.inModal
                    playOverlay.isHidden = !item.inModal || item.thumbResource == nil
                }
            } else {
                playAnimationView?.removeFromSuperview()
                playAnimationView = nil
                playIcon.isHidden = !item.inModal
                    playOverlay.isHidden = !item.inModal || item.thumbResource == nil
            }
        }
    }

    public override func set(item: TableRowItem, animated: Bool) {
        super.set(item: item, animated: animated)
        
        if let item = item as? PeerMediaMusicRowItem {
            var updatedStatusSignal: Signal<MediaResourceStatus, NoError>?
            textView.update(item.textLayout)
            textView.centerY(x: item.contentInset.left)
            textView.backgroundColor = backdorColor
            PeerMediaUIHooks.shared.getAudioPlayer(item.context)?.add(listener: self)
            
            
            let cornerRadius: CGFloat = item.inModal ? thumbView.frame.width / 2 : 8
            let imageCorners = ImageCorners(topLeft: .Corner(cornerRadius), topRight: .Corner(cornerRadius), bottomLeft: .Corner(cornerRadius), bottomRight: .Corner(cornerRadius))
            let arguments = TransformImageArguments(corners: imageCorners, imageSize: PeerMediaIconSize, boundingSize: PeerMediaIconSize, intrinsicInsets: NSEdgeInsets())
            
            thumbPlaceholder.image = theme.icons.playerMusicPlaceholder
            thumbPlaceholder.layer?.cornerRadius = cornerRadius
            thumbView.layer?.cornerRadius = cornerRadius
            playIcon.isHidden = !item.inModal
                    playOverlay.isHidden = !item.inModal || item.thumbResource == nil
            if let resource = item.thumbResource {
                let previewRepresentations = [TelegramMediaImageRepresentation(dimensions: PixelDimensions(PeerMediaIconSize), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)]
                let coverFile = TelegramMediaFile(fileId: MediaId(namespace: 0, id: arc4random64()), partialReference: nil, resource: item.file.resource, previewRepresentations: previewRepresentations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: item.file.mimeType, size: item.file.size, attributes: item.file.attributes, alternativeRepresentations: [])

                let reference = FileMediaReference.message(message: MessageReference(item.message), media: coverFile)
                thumbView.setSignal(chatMessageImageFile(account: item.interface.interactionContext.account, fileReference: reference, scale: System.backingScale))

                thumbView.set(arguments: arguments)
            }

            
            if item.message.flags.contains(.Unsent) && !item.message.flags.contains(.Failed) {
                updatedStatusSignal = combineLatest(chatMessageFileStatus(context: item.interface.interactionContext, message: item.message, file: item.file), item.interface.interactionContext.account.pendingMessageManager.pendingMessageStatus(item.message.id))
                    |> map { resourceStatus, pendingStatus -> MediaResourceStatus in
                        if let pendingStatus = pendingStatus.0 {
                            return .Fetching(isActive: true, progress: pendingStatus.progress.progress)
                        } else {
                            return resourceStatus
                        }
                    } |> deliverOnMainQueue
            } else {
                updatedStatusSignal = chatMessageFileStatus(context: item.interface.interactionContext, message: item.message, file: item.file) |> deliverOnMainQueue
            }
            
            
            if let updatedStatusSignal = updatedStatusSignal {
                self.statusDisposable.set((updatedStatusSignal |> deliverOnMainQueue).start(next: { [weak self] status in
                    self?.fetchStatus = status
                }))
                checkState()
            }
            needsLayout = true
        }
    }
    
    public func open() {
        if let item = item as? PeerMediaMusicRowItem  {
            item.music(item.message, item.galleryType)
        }
    }
    

    
    public func fetch() {
        if let item = item as? PeerMediaMusicRowItem {
            fetchDisposable.set(messageMediaFileInteractiveFetched(context: item.context, messageId: item.message.id, messageReference: .init(item.message), file: item.file, userInitiated: true).start())
        }
        open()
    }
    
    
    public func cancelFetching() {
        if let item = item as? PeerMediaMusicRowItem {
            messageMediaFileCancelInteractiveFetch(context: item.interface.interactionContext, messageId: item.message.id, file: item.file)
        }
    }
    
    
    deinit {
        clean()
    }
    
    public func clean() {
        fetchDisposable.dispose()
        statusDisposable.dispose()
        if let item = item as? PeerMediaMusicRowItem {
            PeerMediaUIHooks.shared.getAudioPlayer(item.context)?.remove(listener: self)
        }
    }
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
