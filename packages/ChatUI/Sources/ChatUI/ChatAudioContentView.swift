import Cocoa
import SwiftSignalKit
import Postbox
import TelegramCore

import TGUIKit
import TelegramContext
import TelegramTheme
import TelegramUtils
import TelegramMedia
import TelegramMediaUtils
import TelegramMediaResources
import InAppSettings
import Localization
import ColorPalette
import MessageUtils
import FoundationUtils
import AudioPlayerCore


public final class SingleTimeVoiceBadgeView: ImageView {
   
    
    private struct Parameters: Equatable {
        var size: CGSize
        var text: String
        var foreground: NSColor
        var background: NSColor
        var blendMode: CGBlendMode
    }
    private var parameters: Parameters?
    private var hasContent: Bool = false
    
    override public init(frame: CGRect) {
        super.init(frame: frame)
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
        
    public func update(size: CGSize, text: String, foreground: NSColor, background: NSColor, blendMode: CGBlendMode) {
        let parameters = Parameters(size: size, text: text, foreground: foreground, background: background, blendMode: blendMode)
        if self.parameters != parameters || !self.hasContent {
            self.parameters = parameters
            self.update()
        }
    }
    
    private func update() {
        guard let parameters = self.parameters else {
            return
        }
        
        
        self.hasContent = true
        
        
        self.image = generateImage(parameters.size, rotatedContext: { size, context in
            
            context.clear(CGRect(origin: CGPoint(), size: size))
            
            context.setBlendMode(.copy)
            context.setFillColor(parameters.background.cgColor)
            context.fillEllipse(in: CGRect(origin: CGPoint(), size: size))
            
            context.setBlendMode(parameters.blendMode)

            var fontSize: CGFloat = floor(parameters.size.height * 0.48)
            while true {
                let string: NSAttributedString = .initialize(string: parameters.text, color: parameters.foreground, font: .bold(fontSize))
                
                
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
            
            let lineWidth: CGFloat = 2
            let lineInset: CGFloat = 2.0
            let lineRadius: CGFloat = size.width * 0.5 - lineInset - lineWidth - 1.5
            
            context.setLineWidth(lineWidth)
            context.setStrokeColor(parameters.foreground.cgColor)
            context.setLineCap(.round)
            
            context.addArc(center: CGPoint(x: size.width * 0.5, y: size.height * 0.5), radius: lineRadius, startAngle: CGFloat.pi * 0.5, endAngle: -CGFloat.pi * 0.5, clockwise: false)
            context.strokePath()
            
//            context.addArc(center: CGPoint(x: size.width * 0.5, y: size.height * 0.5), radius: size.width * 0.5 - lineWidth + 1.0, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
//            context.strokePath()
            
            let sectionAngle: CGFloat = CGFloat.pi / 8
            
            for i in 0 ..< 7 {
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




public class ChatAudioContentView: ChatMediaContentView, APDelegate {
    
    public let progressView:RadialProgressView = RadialProgressView()
    
    public let textView:TextView = TextView()
    public let durationView:TextView = TextView()
    
    public let statusDisposable = MetaDisposable()
    public let fetchDisposable = MetaDisposable()
    
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        super.init(frame:frameRect)
        textView.isSelectable = false
        textView.userInteractionEnabled = false
        durationView.userInteractionEnabled = false
        self.addSubview(textView)
        self.addSubview(durationView)
        progressView.fetchControls = fetchControls
        addSubview(progressView)
        
    }
    
    public override var fetchStatus: MediaResourceStatus? {
        didSet {
            if let fetchStatus = fetchStatus {
                
                switch fetchStatus {
                case let .Fetching(_, progress), let .Paused(progress):
                    let sentGrouped = parent?.groupingKey != nil && (parent!.flags.contains(.Sending) || parent!.flags.contains(.Unsent))
                    if progress == 1.0, sentGrouped {
                        progressView.setState(.Success, animated: statusChangeIsAnimatable)
                    } else {
                        progressView.setState(.Fetching(progress: progress, force: false), animated: statusChangeIsAnimatable)
                    }
                case .Remote:
                    progressView.setState(.Remote, animated: statusChangeIsAnimatable)
                case .Local:
                    updatePlaybackIcon(animated: statusChangeIsAnimatable)
                    checkState(animated: false)
                }
            }
        }
    }
    
    public override func mouseDown(with event: NSEvent) {
//        if mouseInside(), userInteractionEnabled {
//            progressView.fetchControls?.fetch()
//        } else {
//            super.mouseDown(with: event)
//        }
    }
    
 
    
    public override func layout() {
        super.layout()
        textView.centerY(x:leftInset)
    }
    
    
    public override func open() {
        if let parameters = parameters as? ChatMediaMusicLayoutParameters, let context = context, let parent = parent  {
            if let controller = ChatMediaUIHooks.shared.getAudioPlayer(context), controller.playOrPause(parent.id) {
            } else {
                let controller:APController

                if parameters.isWebpage {
                    controller = APSingleResourceController(context: context, wrapper: APSingleWrapper(resource: parameters.resource, mimeType: parameters.file.mimeType, name: parameters.title, performer: parameters.performer, duration: parameters.file.duration, id: parent.chatStableId), streamable: true, volume: FastSettings.volumeRate)
                } else {
                    controller = APChatMusicController(context: context, chatLocationInput: parameters.chatLocationInput(parent), mode: parameters.chatMode, index: MessageIndex(parent), volume: FastSettings.volumeRate)
                }
                parameters.showPlayer(controller)
                controller.start()
            }
        }
    }
    
    
   
    
    public override func fetch(userInitiated: Bool) {
        if let context = context, let media = media as? TelegramMediaFile, let parent = parent {
            fetchDisposable.set(messageMediaFileInteractiveFetched(context: context, messageId: parent.id, messageReference: .init(parent), file: media, userInitiated: userInitiated).start())
        }
    }
    
    
    
    public func songDidChanged(song: APSongItem, for controller: APController, animated: Bool) {
        checkState(animated: animated)
    }
    public func songDidChangedState(song: APSongItem, for controller: APController, animated: Bool) {
        checkState(animated: animated)
    }
    
    public func songDidStartPlaying(song:APSongItem, for controller:APController, animated: Bool) {
        checkState(animated: animated)
    }
    public func songDidStopPlaying(song:APSongItem, for controller:APController, animated: Bool) {
        checkState(animated: animated)
    }
    public func playerDidChangedTimebase(song:APSongItem, for controller:APController, animated: Bool) {
        
    }
    
    public func audioDidCompleteQueue(for controller:APController, animated: Bool) {
        
    }
    
    
    public func checkState(animated: Bool) {
        updatePlaybackIcon(animated: false)
    }
    
    private func updatePlaybackIcon(animated: Bool) {
        let presentation: ChatMediaPresentation = parameters?.presentation ?? .Empty
        let isPlaying: Bool
        if let parent = parent, let controller = ChatMediaUIHooks.shared.getAudioPlayer(context), let song = controller.currentSong, song.entry.isEqual(to: parent), case .playing = song.state {
            isPlaying = true
        } else {
            isPlaying = false
        }
        let icon = isPlaying ? presentation.pauseThumb : presentation.playThumb
        progressView.theme = RadialProgressTheme(backgroundColor: presentation.activityBackground, foregroundColor: presentation.activityForeground, icon: icon, iconInset: NSEdgeInsets(left: isPlaying ? 0 : 1), blendMode: presentation.blendingMode)
        if fetchStatus == nil || fetchStatus == .Local {
            if case let .Icon(current) = progressView.state, current === icon {
                return
            }
            progressView.setState(.Icon(image: icon), animated: animated)
        }
    }

    public var initialFetchStatus: MediaResourceStatus {
        return .Local
    }
    
    public override func update(with media: Media, size:NSSize, context: any AccountContextProtocol, parent:Message?, table:TableView?, parameters:ChatMediaLayoutParameters? = nil, animated: Bool = false, positionFlags: LayoutPositionFlags? = nil, approximateSynchronousValue: Bool = false) {
        
        super.update(with: media, size: size, context: context, parent:parent,table:table, parameters:parameters, animated: animated, positionFlags: positionFlags)
        
        var updatedStatusSignal: Signal<MediaResourceStatus, NoError>?
        

        
        
        if let parent = parent, parent.flags.contains(.Unsent) && !parent.flags.contains(.Failed) {
            updatedStatusSignal = context.account.pendingMessageManager.pendingMessageStatus(parent.id) |> map { pendingStatus in
                if let pendingStatus = pendingStatus.0 {
                    return .Fetching(isActive: true, progress: pendingStatus.progress.progress)
                } else {
                    return .Local
                }
            } |> deliverOnMainQueue
        }
        
        if let updatedStatusSignal = updatedStatusSignal {
            self.statusDisposable.set((updatedStatusSignal |> deliverOnMainQueue).start(next: { [weak self] status in
                self?.fetchStatus = status
            }))
        }
       
        
        
        if let audioPlayer = ChatMediaUIHooks.shared.getAudioPlayer(context), listenedAudioPlayer !== audioPlayer {
            audioPlayer.add(listener: self)
            listenedAudioPlayer = audioPlayer
        }
        self.setNeedsDisplay()
        
        initializeFetchStatus()
        checkState(animated: animated)

    }
    
    func initializeFetchStatus() {
        if !hasFetchStatusForCurrentMedia {
            fetchStatus = initialFetchStatus
        }
    }

    public var leftInset:CGFloat {
        return 40.0 + 10.0;
    }
    
    public override func draggingAbility(_ event:NSEvent) -> Bool {
        return NSPointInRect(convert(event.locationInWindow, from: nil), progressView.frame)
    }
    
    public override func copy() -> Any {
        let view = View()
        view.frame = self.frame
        return view
    }
    
    public override func interactionContentView(for innerId: AnyHashable, animateIn: Bool ) -> NSView {
        return self.progressView
    }
    
    
    public override func cancel() {
        fetchDisposable.set(nil)
        statusDisposable.set(nil)
    }
    
    private weak var listenedAudioPlayer: AnyObject?

    public override func clean() {
        statusDisposable.dispose()
        ChatMediaUIHooks.shared.getAudioPlayer(context)?.remove(listener: self)
        listenedAudioPlayer = nil
    }
    
    deinit {
        fetchDisposable.dispose()
    }
    
}
