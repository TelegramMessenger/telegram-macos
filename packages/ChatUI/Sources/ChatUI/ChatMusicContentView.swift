import Cocoa
import TelegramCore

import Postbox
import SwiftSignalKit
import TGUIKit
import TelegramMediaResources
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import AudioPlayerCore
import FetchManager

func chatMusicFetchStatus(fetchManager: FetchManager, message: Message?, file: TelegramMediaFile) -> Signal<MediaResourceStatus, NoError> {
    guard let message = message, !(file.resource is LocalFileReferenceMediaResource) else {
        return .single(.Local)
    }
    return fetchManager.fetchStatus(category: .file, location: .chat(message.id.peerId), locationKey: .messageId(message.id), resource: file.resource, reportExternalFetches: false)
}

public class ChatMusicContentView: ChatAudioContentView {
    private let imageView: TransformImageView = TransformImageView(frame: NSMakeRect(0, 0, 40, 40))
    private var playAnimationView: PeerMediaPlayerAnimationView?
    private let partHeaderDisposable = MetaDisposable()
    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(imageView, positioned: .below, relativeTo: progressView)
    }

    public override var fetchStatus: MediaResourceStatus? {
        didSet {
            updateFetchPresentation()
        }
    }

    private func updateFetchPresentation() {
        let presentation: ChatMediaPresentation = parameters?.presentation ?? .Empty
        let showProgress: Bool
        switch fetchStatus {
        case .Fetching?, .Paused?:
            showProgress = playAnimationView == nil || (parent?.flags.contains(.Unsent) == true && parent?.flags.contains(.Failed) != true)
        default:
            showProgress = false
        }
        if showProgress {
            progressView.theme = RadialProgressTheme(backgroundColor: presentation.activityBackground, foregroundColor: presentation.activityForeground, icon: nil, blendMode: presentation.blendingMode)
        }
        progressView.isHidden = !showProgress
        imageView.isHidden = showProgress
    }

    public override func executeInteraction(_ isControl: Bool) {
        if !isControl, userInteractionEnabled, parent?.flags.contains(.Unsent) != true || parent?.flags.contains(.Failed) == true {
            open()
        } else {
            super.executeInteraction(isControl)
        }
    }

    public override func draggingAbility(_ event: NSEvent) -> Bool {
        return NSPointInRect(convert(event.locationInWindow, from: nil), bounds)
    }
    
    public override func viewDidMoveToWindow() {
        if window != nil {
            if let playAnimationView = playAnimationView {
                if playAnimationView.isPlaying {
                    playAnimationView.animateToPlaying()
                } else {
                    playAnimationView.animateToPaused()
                }
            }
        } else {
            playAnimationView?.animateToPaused()
        }
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func update(with media: Media, size: NSSize, context: any AccountContextProtocol, parent: Message?, table: TableView?, parameters: ChatMediaLayoutParameters?, animated: Bool, positionFlags: LayoutPositionFlags? = nil, approximateSynchronousValue: Bool = false) {
        self.statusDisposable.set(nil)
        super.update(with: media, size: size, context: context, parent: parent, table: table, parameters: parameters, animated: animated, positionFlags: positionFlags)

        if let file = media as? TelegramMediaFile, parent?.flags.contains(.Unsent) != true || parent?.flags.contains(.Failed) == true {
            self.updateFetchStatus(chatMusicFetchStatus(fetchManager: context.fetchManager, message: parent, file: file))
        }
        updateFetchPresentation()

        if let parameters = parameters as? ChatMediaMusicLayoutParameters {
            textView.update(parameters.nameLayout)
            durationView.update(parameters.durationLayout)
        }
        
        let iconSize = CGSize(width: 40, height: 40)
        let imageCorners = ImageCorners(radius: 20)
        let arguments = TransformImageArguments(corners: imageCorners, imageSize: iconSize, boundingSize: iconSize, intrinsicInsets: NSEdgeInsets())
        
        let file = media as! TelegramMediaFile
        
        let resource: TelegramMediaResource?
        if file.previewRepresentations.isEmpty {
            if !file.mimeType.contains("ogg") {
                resource = ExternalMusicAlbumArtResource(title: file.musicText.0, performer: file.musicText.1, isThumbnail: true)
            } else {
                resource = nil
            }
        } else {
            resource = file.previewRepresentations.first!.resource
        }
        imageView.layer?.contents = theme.icons.chatMusicPlaceholder

        if let resource = resource {
            let previewRepresentations = [TelegramMediaImageRepresentation(dimensions: PixelDimensions(iconSize), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)]
            let coverFile = TelegramMediaFile(fileId: MediaId(namespace: 0, id: arc4random64()), partialReference: nil, resource: file.resource, previewRepresentations: previewRepresentations, videoThumbnails: [], immediateThumbnailData: nil, mimeType: file.mimeType, size: file.size, attributes: file.attributes, alternativeRepresentations: [])

            imageView.setSignal(signal: cachedMedia(media: media, arguments: arguments, scale: backingScaleFactor, positionFlags: positionFlags), clearInstantly: false)

            if !imageView.isFullyLoaded {
                let reference = parent != nil ? FileMediaReference.message(message: MessageReference(parent!), media: coverFile) : FileMediaReference.standalone(media: coverFile)
                imageView.setSignal(chatMessageImageFile(account: context.account, fileReference: reference, scale: System.backingScale), animate: true, cacheImage: { [weak media] result in
                    if let media = media {
                        cacheMedia(result, media: media, arguments: arguments, scale: System.backingScale, positionFlags: positionFlags)
                    }
                })
            }

            imageView.set(arguments: arguments)
        }
        

      //  imageView.layer?.cornerRadius = 20
    }
    
    override func initializeFetchStatus() {
        if !hasFetchStatusForCurrentMedia {
            fetchStatus = nil
        }
    }

    func updateFetchStatus(_ status: Signal<MediaResourceStatus, NoError>) {
        self.statusDisposable.set((status |> deliverOnMainQueue).start(next: { [weak self] status in
            self?.fetchStatus = status
        }))
    }

    public override func checkState(animated: Bool) {
        if let parent = parent, let controller = ChatMediaUIHooks.shared.getAudioPlayer(context), let song = controller.currentSong, song.entry.isEqual(to: parent) {
            updatePlaybackState(song.state)
        } else {
            updatePlaybackState(nil)
        }
    }

    func updatePlaybackState(_ state: APState?) {
        switch state {
        case .none, .stoped?:
            playAnimationView?.removeFromSuperview()
            playAnimationView = nil
        default:
            if playAnimationView == nil {
                playAnimationView = PeerMediaPlayerAnimationView()
                playAnimationView?.layer?.cornerRadius = 20
                imageView.addSubview(playAnimationView!)
            }
            if case .playing? = state {
                playAnimationView?.isPlaying = true
            } else {
                playAnimationView?.isPlaying = false
            }
        }
        updateFetchPresentation()
    }
    
    public override func preloadStreamblePart() {
        if let context = context, !TelegramUtilsHooks.shared.isLite(.any) {
            if let media = media as? TelegramMediaFile {
                let reference = parent != nil ? FileMediaReference.message(message: MessageReference(parent!), media: media) : FileMediaReference.standalone(media: media)
                partHeaderDisposable.set(fetchedMediaResource(mediaBox: context.account.postbox.mediaBox, userLocation: reference.userLocation, userContentType: reference.userContentType, reference: reference.resourceReference(media.resource), range: (0 ..< 500 * 1024, .default), statsCategory: .audio).start())
                
            }
        }
    }
    
    deinit {
        partHeaderDisposable.dispose()
    }
    
    public override func layout() {
        super.layout()
        let center = floorToScreenPixels(backingScaleFactor, frame.height / 2.0)
        textView.setFrameOrigin(leftInset, center - textView.frame.height - 2)
        durationView.setFrameOrigin(leftInset, center + 2)
    }
    
}
