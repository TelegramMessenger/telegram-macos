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
            if let fetchStatus = fetchStatus {
                let presentation: ChatMediaPresentation = parameters?.presentation ?? .Empty
                switch fetchStatus {
                case let .Fetching(_, progress), let .Paused(progress):
                    if let _ = parameters {
                        progressView.theme = RadialProgressTheme(backgroundColor: presentation.activityBackground, foregroundColor: presentation.activityForeground, icon: nil, blendMode: presentation.blendingMode)
                    }
                    let sentGrouped = parent?.groupingKey != nil && (parent!.flags.contains(.Sending) || parent!.flags.contains(.Unsent))
                    if progress == 1.0, sentGrouped {
                        progressView.setState(.Success, animated: statusChangeIsAnimatable)
                    } else {
                        progressView.setState(.Fetching(progress: progress, force: false), animated: statusChangeIsAnimatable)
                    }
                    progressView.isHidden = false
                    imageView.isHidden = true
                case .Remote:
                    progressView.isHidden = true
                    imageView.isHidden = false
                case .Local:
                    progressView.isHidden = true
                    imageView.isHidden = false
                }
            }
        }
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
        super.update(with: media, size: size, context: context, parent: parent, table: table, parameters: parameters, animated: animated, positionFlags: positionFlags)

        let presentation: ChatMediaPresentation = parameters?.presentation ?? .Empty
        if let fetchStatus = fetchStatus {
            switch fetchStatus {
            case .Fetching, .Paused:
                progressView.theme = RadialProgressTheme(backgroundColor: presentation.activityBackground, foregroundColor: presentation.activityForeground, icon: nil, blendMode: presentation.blendingMode)
                progressView.isHidden = false
                imageView.isHidden = true
            case .Remote, .Local:
                progressView.isHidden = true
                imageView.isHidden = false
            }
        }

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
    
    public override func checkState(animated: Bool) {
        if let parent = parent, let controller = ChatMediaUIHooks.shared.getAudioPlayer(context), let song = controller.currentSong {
            if song.entry.isEqual(to: parent) {
                if playAnimationView == nil {
                    playAnimationView = PeerMediaPlayerAnimationView()
                    playAnimationView?.layer?.cornerRadius = 20
                    imageView.addSubview(playAnimationView!)
                }
                if case .playing = song.state {
                    playAnimationView?.isPlaying = true
                } else if case .stoped = song.state {
                    playAnimationView?.removeFromSuperview()
                    playAnimationView = nil
                } else  {
                    playAnimationView?.isPlaying = false
                }
            } else {
                playAnimationView?.removeFromSuperview()
                playAnimationView = nil
            }
        } else {
            playAnimationView?.removeFromSuperview()
            playAnimationView = nil
        }
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
