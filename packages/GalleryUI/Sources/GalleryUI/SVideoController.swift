import Cocoa
import TGUIKit
import TelegramCore
import TelegramMediaPlayer
import SwiftSignalKit
import Postbox
import RangeSet
import IOKit.pwr_mgt
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
import ColorPalette
import InAppSettings
import FoundationUtils
import ObjcUtils
import TelegramMediaResources
import InputDataUI


private func makePlayer(account: Account, reference: FileMediaReference, fetchAutomatically: Bool = false, isProtected: Bool = false) -> (UniversalVideoContentView & NSView) {
    let player: (UniversalVideoContentView & NSView)
    if isHLSVideo(file: reference.media) {
        player = HLSVideoJSNativeContentView(accountId: account.id, postbox: account.postbox, userLocation: reference.userLocation, fileReference: reference, streamVideo: true, loopVideo: false, enableSound: true, baseRate: FastSettings.playingVideoRate, fetchAutomatically: false, volume: FastSettings.volumeRate, initialQuality: FastSettings.videoQuality)
    } else if shouldUseChunkedVideoPlayer(file: reference.media) {
        player = ChunkedNativeMediaPlayer(postbox: account.postbox, reference: reference, fetchAutomatically: fetchAutomatically, preventsCapture: isProtected)
    } else {
        player = NativeMediaPlayer(postbox: account.postbox, reference: reference, fetchAutomatically: fetchAutomatically)
    }
    return player
}

public enum SVideoStyle {
    case regular
    case pictureInPicture
}



public class SVideoController: GenericViewController<SVideoView>, PictureInPictureControl {
    
    
   
    
    
    public var style: SVideoStyle = .regular
    private var fullScreenWindow: Window?
    private var fullScreenRestoreState: (rect: NSRect, view: NSView)?
    public private(set) var mediaPlayer: (UniversalVideoContentView & NSView)!
    private let reference: FileMediaReference
    private let statusDisposable = MetaDisposable()
    private let bufferingDisposable = MetaDisposable()
    private let hideOnIdleDisposable = MetaDisposable()
    private let hideControlsDisposable = MetaDisposable()
    private let account: Account
    private let context: any AccountContextProtocol
    private var pictureInPicture: Bool = false
    private var hideControls: ValuePromise<Bool> = ValuePromise(true, ignoreRepeated: true)
    private var controlsIsHidden: Bool = false
    public var togglePictureInPictureImpl:((Bool, PictureInPictureControl)->Void)?
    
    private var isPaused: Bool = true
    private var forceHiddenControls: Bool = false
    private var _videoFramePreview: MediaPlayerFramePreview?
    private var mode: PictureInPictureControlMode = .normal
    private var frameStepTimestamp: Double?
    
    private var updateControls: SwiftSignalKit.Timer?
    
    private var videoFramePreview: MediaPlayerFramePreview? {
        if let videoFramePreview = _videoFramePreview {
            return videoFramePreview
        } else {
            let qualityState = self.genericView.mediaPlayer.videoQualityState()
            if let qualityState = qualityState, !qualityState.available.isEmpty {
                if let minQuality = HLSVideoContent.minimizedHLSQuality(file: reference)?.file {
                    self._videoFramePreview = MediaPlayerFramePreview(postbox: account.postbox, fileReference: minQuality)
                } else {
                    _videoFramePreview = nil
                }
            } else {
                self._videoFramePreview = MediaPlayerFramePreview(postbox: account.postbox, fileReference: reference)
            }
        }
        return _videoFramePreview
    }
    
    
    public func setMode(_ mode: PictureInPictureControlMode, animated: Bool) {
        genericView.setMode(mode, animated: animated)
        self.mode = mode
    }
    
    private var scrubbingFrame = Promise<MediaPlayerFramePreviewResult?>(nil)
    private var scrubbingFrames = false
    private var scrubbingFrameDisposable: Disposable?
    private var frameStepDisposable: Disposable?
    private let isProtected: Bool
    private let isControlsLimited: Bool
    private let message: Message?
    
    private let partDisposable = MetaDisposable()
    
    private let mediaPlaybackStateDisposable = MetaDisposable()
    
    private var endPlaybackId: Int?
    
    private var adContext: AdMessagesHistoryContext?
    private let adStateDisposable = MetaDisposable()
    private let nextAdDisposable = MetaDisposable()

    public init(context: any AccountContextProtocol, reference: FileMediaReference, message: Message?, fetchAutomatically: Bool = false, isProtected: Bool = false, isControlsLimited: Bool = false) {
        self.reference = reference
        self.account = context.account
        self.isProtected = isProtected
        self.isControlsLimited = isControlsLimited
        self.message = message
        self.context = context
        super.init()
        bar = .init(height: 0)
    }
    
    public var status: Signal<MediaPlayerStatus, NoError> {
        return mediaPlayer.status
    }
    
    public func play(_ startTime: TimeInterval? = nil) {
        if let startTime = startTime, startTime > 0 {
            mediaPlayer.seek(startTime, play: true)
        } else {
            mediaPlayer.play()
        }
        self.isPaused = false
        self.frameStepTimestamp = nil
        self.genericView.hideFrameStepOverlay()
    }
    
    public func setBaseRate(_ baseRate: Double) {        
        mediaPlayer.setBaseRate(baseRate)
        FastSettings.setPlayingVideoRate(baseRate)
    }
    
    public func playOrPause() {
        self.isPaused = !self.isPaused
        self.frameStepTimestamp = nil
        if !self.isPaused {
            self.genericView.hideFrameStepOverlay()
        }
        mediaPlayer.togglePlayPause()
    }

    public func pause() {
        self.isPaused = true
        self.frameStepTimestamp = nil
        mediaPlayer.pause()
    }

    public func play() {
        self.isPaused = false
        self.frameStepTimestamp = nil
        self.play(nil)
    }
    
    
    public func didEnter() {
        
    }
    
    public func didExit() {
        
    }
    
    public func isPlaying() -> Bool {
        return !self.isPaused
    }
    
    
    private func updateIdleTimer() {
        NSCursor.unhide()
        hideOnIdleDisposable.set((Signal<NoValue, NoError>.complete() |> delay(1.0, queue: Queue.mainQueue())).start(completed: { [weak self] in
            guard let `self` = self else {return}
            let hide = !self.genericView.isInMenu && !self.genericView.insideControls && !contextMenuOnScreen()
            self.hideControls.set(hide)
            if !self.pictureInPicture, hide {
                NSCursor.hide()
            }
        }))
    }
    
    private func updateControlVisibility(_ isMouseUpOrDown: Bool = false) {
        
        
        if let rootView = genericView.superview?.superview {
            var hide = !genericView._mouseInside() && !rootView.isHidden && (NSEvent.pressedMouseButtons & (1 << 0)) == 0
            
           
            if !hide, (NSEvent.pressedMouseButtons & (1 << 0)) != 0 {
                hide = genericView.controlsStyle.isPip
            }

            
            if self.fullScreenWindow != nil && isMouseUpOrDown, !genericView.insideControls {
                hide = true
                if !self.isPaused {
                    if !contextMenuOnScreen() {
                        NSCursor.hide()
                    }
                }
            }
            if contextMenuOnScreen() {
                hide = false
            }
            hideControls.set(hide || forceHiddenControls)
        } else {
            hideControls.set(forceHiddenControls)
        }
    }
    
    
    
    private func setHandlersOn(window: Window) {
        
        updateIdleTimer()
        
        _ = self.account
        
        let mouseInsidePlayer = genericView.mediaPlayer._mouseInside()
        
        hideControls.set(!mouseInsidePlayer || forceHiddenControls)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            if let window = self?.genericView.window, let contentView = window.contentView {
                let point = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if contentView.hitTest(point) != nil {
                    self?.updateControlVisibility()
                }
            }
            self?.updateIdleTimer()
            return .rejected
        }, with: self, for: .mouseMoved, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            if let window = self?.genericView.window, let contentView = window.contentView {
                let point = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if contentView.hitTest(point) != nil {
                    self?.updateControlVisibility()
                }
            }
            self?.updateIdleTimer()
            return .rejected
        }, with: self, for: .mouseExited, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            self?.updateIdleTimer()
            
            return .rejected
        }, with: self, for: .leftMouseDragged, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            if let window = self?.genericView.window, let contentView = window.contentView {
                let point = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if contentView.hitTest(point) != nil {
                    self?.updateControlVisibility()
                }
            }
            self?.updateIdleTimer()
            return .rejected
        }, with: self, for: .mouseEntered, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            if self?.genericView.mediaPlayer._mouseInside() == true {
                self?.updateControlVisibility(true)
            }
            self?.updateIdleTimer()
            return .rejected
        }, with: self, for: .leftMouseDown, priority: .modal)
        
        window.set(mouseHandler: { [weak self] (event) -> KeyHandlerResult in
            guard let `self` = self else {return .rejected}
            if let window = self.genericView.window, let contentView = window.contentView {
                let point = contentView.convert(window.mouseLocationOutsideOfEventStream, from: nil)
                if contentView.hitTest(point) != nil {
                    self.updateControlVisibility(true)
                }
            }
            self.updateIdleTimer()
            self.genericView.subviews.last?.mouseUp(with: event)
            return .rejected
        }, with: self, for: .leftMouseUp, priority: .modal)
        
        let fromUser1 = TelegramUser(id: PeerId(1), accessHash: nil, firstName: strings().appearanceSettingsChatPreviewUserName1, lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)
        
        let fromUser2 = TelegramUser(id: PeerId(2), accessHash: nil, firstName: strings().appearanceSettingsChatPreviewUserName2, lastName: "", username: nil, phone: nil, photo: [], botInfo: nil, restrictionInfo: nil, flags: [], emojiStatus: nil, usernames: [], storiesHidden: nil, nameColor: nil, backgroundEmojiId: nil, profileColor: nil, profileBackgroundEmojiId: nil, subscriberCount: nil, verificationIconFileId: nil)

        let timestamp2: Int32 = 60 * 22 + 60 * 60 * 18

        
        let message = Message(stableId: 2, stableVersion: 0, id: MessageId(peerId: fromUser1.id, namespace: 0, id: 1), globallyUniqueId: 0, groupingKey: 0, groupInfo: nil, threadId: nil, timestamp: timestamp2, flags: [], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: fromUser1, text: "10.3.0 - [FirebaseAnalytics][I-ACS002002] Measurement timer scheduled to fire in approx. (s): -0.0616508722305297910.3.0 - [FirebaseAnalytics][I-ACS002002] Measurement timer scheduled to fire in approx. (s): -0.06165087223052979", attributes: [AdMessageAttribute(opaqueId: Data(), messageType: .sponsored, url: "https://t.me/durov", buttonText: "Please", sponsorInfo: "Durov Corp.", additionalInfo: "", canReport: true, hasContentMedia: false, minDisplayDuration: 10, maxDisplayDuration: 20)], media: [], peers:SimpleDictionary([fromUser2.id : fromUser2, fromUser1.id : fromUser1]) , associatedMessages: SimpleDictionary(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])

      
        
        window.set(handler: { [weak self] _ in
            self?.runAdMessages([message], 10, 15)

            return .invoked
        }, with: self, for: .T, priority: .supreme, modifierFlags: [.command])

        window.set(handler: { [weak self] _ in
            self?.stepFrameBackward()
            return .invoked
        }, with: self, for: .Comma, priority: .modal)

        window.set(handler: { [weak self] _ in
            self?.stepFrameForward()
            return .invoked
        }, with: self, for: .Period, priority: .modal)

    }
    
    private let screenSleep = ScreenSleepAssertion(reason: "Video Playing")
    
    
    
    
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
      
        if let window = window {
            setHandlersOn(window: window)
        }
        
    }
    
    public override func viewDidDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        super.viewDidDisappear(animated)
        hideOnIdleDisposable.set(nil)
        _ = screenSleep.enableScreenSleep()
        NSCursor.unhide()
        window?.removeAllHandlers(for: self)
        
    }
    
    public var isPictureInPicture: Bool {
        return self.pictureInPicture
    }
    
    
    public func hideControlsIfNeeded(_ forceHideControls: Bool = false) -> Bool {
        self.forceHiddenControls = forceHideControls
        if !controlsIsHidden {
            hideControls.set(true)
            return true
        }
        
        return false
    }
    
    public func unhideControlsIfNeeded(_ forceUnhideControls: Bool = true) -> Bool {
        forceHiddenControls = !forceUnhideControls
        if controlsIsHidden {
            hideControls.set(forceUnhideControls)
            return true
        }
        return false
    }
    
    private func runAdMessages(_ messages: [Message], _ startDelay: Int32, _ betweenDelay: Int32?) {
        
        let context = self.context
        
        var makeNext:((Message, Bool)->Void)? = nil
        
        let arguments = SVideoAdsArguments(context: context, removeAd: { [weak self] current, all, intime in
            guard let window = self?.window else {
                return
            }
            if !intime {
                makeNext?(current, true)
            } else {
                if context.isPremium {
                    if all {
                        _ = context.engine.accountData.updateAdMessagesEnabled(enabled: false).startStandalone()
                        self?.genericView.set(adMessage: nil, arguments: nil, animated: true)
                    }
                    showModalText(for: window, text: strings().chatDisableAdTooltip)
                } else {
                    FeatureNavigationHooks.shared.showPremiumBoarding(context, window, .noAds, true, nil)
                }
            }
        }, maybeNext: { current in
            makeNext?(current, true)
        }, markAsSeen: { [weak self] current in
            if let adAttribute = current.adAttribute {
                self?.adContext?.markAsSeen(opaqueId: adAttribute.opaqueId)
            }
        }, invoke: { [weak self] current in
            if let adAttribute = current.adAttribute {
                self?.adContext?.markAction(opaqueId: adAttribute.opaqueId, media: true, fullscreen: true)
                GalleryHooks.shared.openAdUrl(adAttribute.url, context, { peerId, toChat, messageId, initialAction in
                    getGalleryViewer()?.openInfo(peerId, toChat, messageId, initialAction)
                })
            }
        })
        
        makeNext = { [weak self, weak arguments] current, remove in
            guard let arguments else {
                return
            }
            let index = messages.firstIndex(where: { $0 == current })
            if let index, index < messages.count - 1 {
                if remove {
                    self?.genericView.set(adMessage: nil, arguments: nil, animated: true)
                    self?.updateControlVisibility()
                }
                if let betweenDelay {
                    self?.nextAdDisposable.set(delaySignal(Double(betweenDelay)).start(completed: {
                        self?.genericView.set(adMessage: messages[index + 1], arguments: arguments, animated: true)
                    }))
                }
            } else {
                self?.genericView.set(adMessage: nil, arguments: nil, animated: true)
                self?.nextAdDisposable.set(nil)
            }
        }
        
        
        if let first = messages.first {
            self.genericView.set(adMessage: first, arguments: arguments, animated: true)
        }
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        
        let account = self.account
        
        if isHLSVideo(file: reference.media) {
            let fetchSignal = HLSVideoContent.minimizedHLSQualityPreloadData(postbox: account.postbox, file: reference, userLocation: .other, prefixSeconds: 10, autofetchPlaylist: true, initialQuality: FastSettings.videoQuality)
            |> mapToSignal { fileAndRange -> Signal<Never, NoError> in
                guard let fileAndRange else {
                    return .complete()
                }
                return freeMediaFileResourceInteractiveFetched(postbox: account.postbox, userLocation: .other, fileReference: fileAndRange.0, resource: fileAndRange.0.media.resource, range: (fileAndRange.1, .default))
                |> ignoreValues
                |> `catch` { _ -> Signal<Never, NoError> in
                    return .complete()
                }
            }
            partDisposable.set(fetchSignal.start())
        } else {
            let preload = preloadVideoResource(postbox: account.postbox, userLocation: .other, userContentType: .init(file: reference.media), resourceReference: reference.resourceReference(reference.media.resource), duration: 3.0)
            partDisposable.set(preload.start())
        }
        
        if let message, let peer = message.peers[message.id.peerId], peer.isChannel {
            let adContext = context.engine.messages.adMessages(peerId: message.id.peerId, messageId: message.id)
            self.adContext = adContext
            
            var invoked: Bool = false
            
            adStateDisposable.set(combineLatest(queue:.mainQueue(), adContext.state, status).startStrict(next: { [weak self] values in
               
                let ( _, messages, startDelay, betweenDelay) = values.0
                let status = values.1
                
                if !messages.isEmpty, let startDelay, !invoked {
                    if Int32(status.timestamp) >= startDelay {
                        self?.runAdMessages(messages, startDelay, betweenDelay)
                        invoked = true
                    }
                }
            }))
        }


        
        genericView.layerContentsRedrawPolicy = .duringViewResize

        
        genericView.isControlsLimited = isControlsLimited
        
        
        genericView.isStreamable = reference.media.isStreamable
        hideControlsDisposable.set(hideControls.get().start(next: { [weak self] hide in
            self?.genericView.hideControls(hide, animated: true)
            self?.controlsIsHidden = hide
        }))
        
        
       
        
        let statusValue:Atomic<MediaPlayerStatus?> = Atomic(value: nil)
        let updateTemporaryStatus:(_ f: (MediaPlayerStatus?)->MediaPlayerStatus?) -> Void = { [weak self] f in
            self?.genericView.status = statusValue.modify(f)
        }
        
        let duration = Double(reference.media.duration ?? 0)
        
        statusDisposable.set((mediaPlayer.status |> deliverOnMainQueue).start(next: { [weak self] status in
            let status = status.withUpdatedDuration(status.duration != 0 ? status.duration : duration)
            switch status.status {
            case .playing:
                _ = self?.screenSleep.disableScreenSleep()
            case let .buffering(_, whilePlaying):
                if whilePlaying {
                    _ = self?.screenSleep.disableScreenSleep()
                } else {
                    _ = self?.screenSleep.enableScreenSleep()
                }
            case .paused:
                _ = self?.screenSleep.enableScreenSleep()
            }
            _ = statusValue.swap(status)
           
            self?.genericView.status = status
        }))
        _ = reference.media.resource.size ?? 0
        
        let bufferingStatus = mediaPlayer.bufferingStatus |> deliverOnMainQueue
        
        bufferingDisposable.set(bufferingStatus.start(next: { [weak self] bufferingStatus in
            self?.genericView.bufferingStatus = bufferingStatus
        }))
        
        self.scrubbingFrameDisposable = (self.scrubbingFrame.get()
            |> deliverOnMainQueue).start(next: { [weak self] result in
                guard let `self` = self else {
                    return
                }
            let live = (NSEvent.pressedMouseButtons & (1 << 0)) != 0 && self.genericView.mouseDownIncontrols
                if let result = result {
                    self.genericView.showScrubblerPreviewIfNeeded(live: live)
                    self.genericView.setCurrentScrubblingState(result, live: live)
                } else {
                    self.genericView.hideScrubblerPreviewIfNeeded(live: live)
                    // empty image
                }
            })

        var paused: Bool? = nil
        
        genericView.interactions = SVideoInteractions(playOrPause: { [weak self] in
            self?.playOrPause()
        }, rewind: { [weak self] timestamp in
            self?.mediaPlayer.seek(timestamp)
        }, scrobbling: { [weak self] timecode in
            guard let `self` = self else { return }

            if let timecode = timecode, let videoFramePreview = self.videoFramePreview {
                if !self.scrubbingFrames {
                    self.scrubbingFrames = true
                    self.scrubbingFrame.set(videoFramePreview.generatedFrames
                        |> map(Optional.init))
                }
                videoFramePreview.generateFrame(at: timecode)
            } else {
                self.scrubbingFrame.set(.single(nil))
                self.videoFramePreview?.cancelPendingFrames()
                self.scrubbingFrames = false
            }
        }, volume: { [weak self] value in
            self?.mediaPlayer.setVolume(value)
            FastSettings.setVolumeRate(value)
            updateTemporaryStatus { status in
                return status?.withUpdatedVolume(value)
            }
        }, toggleFullScreen: { [weak self] in
            self?.toggleFullScreen()
        }, togglePictureInPicture: { [weak self] in
            self?.togglePictureInPicture()
        }, closePictureInPicture: {
            closePipVideo()
        }, setBaseRate: { [weak self] rate in
            self?.setBaseRate(rate)
        }, pause: { [weak self] in
            if self?.isPaused == false {
                self?.pause()
                paused = true
            }
        }, play: { [weak self] in
            if paused == true {
                self?.play()
                paused = nil
            }
        })
        
        if let duration = reference.media.duration, duration < 30 {
            mediaPlayer.setActionAtEnd(.loop({ [weak self] in
                Queue.mainQueue().async {
                    self?.updateIdleTimer()
                }
            }))
        } else {
            endPlaybackId = mediaPlayer.addPlaybackCompleted { [weak self] in
                DispatchQueue.main.async {
                    if let duration = self?.mediaPlayer.duration, duration < 30 {
                        self?.mediaPlayer.seek(0, play: true)
                    }
                    self?.hideControls.set(false)
                    self?.updateIdleTimer()
                }
            }
        }
        
        
        if let message {
            let throttledSignal = self.mediaPlayer.status
            |> mapToThrottled { next -> Signal<MediaPlayerStatus, NoError> in
                return .single(next) |> then(.complete() |> delay(2.0, queue: Queue.concurrentDefaultQueue()))
            }
            
            self.mediaPlaybackStateDisposable.set(throttledSignal.startStrict(next: { status in
                if status.duration >= 10, case .playing = status.status {
                    let storedState = MediaPlaybackStoredState(timestamp: status.timestamp)
                    let _ = updateMediaPlaybackStoredStateInteractively(engine: TelegramEngine(account: account), messageId: message.id, state: storedState).startStandalone()
                }
            }))
        }
        


        
        
        readyOnce()
    }
    
    public func togglePictureInPicture() {
        if let function = togglePictureInPictureImpl {
            if fullScreenRestoreState != nil {
                toggleFullScreen()
            }
            self.pictureInPicture = !pictureInPicture
            window?.removeAllHandlers(for: self)
            function(pictureInPicture, self)
            if let window = view.window?.contentView?.window as? Window {
                setHandlersOn(window: window)
            }
            
            genericView.set(isInPictureInPicture: pictureInPicture)
        }
    }
    
    public func togglePlayerOrPause() {
        playOrPause()
    }
    
    
    public func rewindBackward() {
        self.frameStepTimestamp = nil
        genericView.rewindBackward()
    }
    public func rewindForward() {
        self.frameStepTimestamp = nil
        genericView.rewindForward()
    }

    public func stepFrameBackward() {
        guard isPaused else { return }
        if let status = genericView.status {
            let frameDuration = 1.0 / 30.0
            let currentTimestamp = frameStepTimestamp ?? status.timestamp
            let newTimestamp = max(0, currentTimestamp - frameDuration)
            frameStepTimestamp = newTimestamp
            mediaPlayer.seek(newTimestamp)
            if isHLSVideo(file: reference.media) {
                generateFrameStepPreview(at: newTimestamp)
            }
        }
    }

    public func stepFrameForward() {
        guard isPaused else { return }
        if let status = genericView.status {
            let frameDuration = 1.0 / 30.0
            let currentTimestamp = frameStepTimestamp ?? status.timestamp
            let newTimestamp = min(status.duration, currentTimestamp + frameDuration)
            frameStepTimestamp = newTimestamp
            mediaPlayer.seek(newTimestamp)
            if isHLSVideo(file: reference.media) {
                generateFrameStepPreview(at: newTimestamp)
            }
        }
    }

    private func generateFrameStepPreview(at timestamp: Double) {
        guard let videoFramePreview = self.videoFramePreview else { return }

        frameStepDisposable?.dispose()
        frameStepDisposable = (videoFramePreview.generatedFrames
            |> take(1)
            |> deliverOnMainQueue).start(next: { [weak self] result in
                guard let self = self else { return }
                if case let .image(image) = result {
                    self.genericView.showFrameStepImage(image)
                }
            })
        videoFramePreview.generateFrame(at: timestamp)
    }
    
    public var isFullscreen: Bool {
        return self.fullScreenRestoreState != nil
    }
    
    public func toggleFullScreen() {
        if let screen = NSScreen.main {
            if let window = fullScreenWindow, let state = fullScreenRestoreState {
                
                var topInset: CGFloat = 0
                
                if #available(macOS 12.0, *) {
                    topInset = screen.safeAreaInsets.top
                }
                
                
                window.setFrame(NSMakeRect(screen.frame.minX + state.rect.minX, screen.frame.minY + screen.frame.height - state.rect.maxY - topInset, state.rect.width, state.rect.height), display: true, animate: true)
                window.orderOut(nil)
                view.frame = state.rect
                state.view.addSubview(view)
                
                genericView.set(isInFullScreen: false)
                mediaPlayer.setVideoLayerGravity(.resizeAspectFill)

                
                window.removeAllHandlers(for: self)
                if let window = self.window {
                    setHandlersOn(window: window)
                }
                
                self.fullScreenWindow = nil
                self.fullScreenRestoreState = nil
            } else {
                
                mediaPlayer.setVideoLayerGravity(.resizeAspect)

                
                fullScreenRestoreState = (rect: view.frame, view: view.superview!)
                fullScreenWindow = Window(contentRect: NSMakeRect(view.frame.minX, screen.frame.height - view.frame.maxY, view.frame.width, view.frame.height), styleMask: [.fullSizeContentView, .borderless], backing: .buffered, defer: true, screen: screen)
                
                setHandlersOn(window: fullScreenWindow!)
                window?.removeAllHandlers(for: self)
                
                
                fullScreenWindow?.isOpaque = true
                fullScreenWindow?.hasShadow = false
                fullScreenWindow?.level = .screenSaver
                self.view.frame = self.view.bounds
                fullScreenWindow?.contentView?.addSubview(self.view)
                fullScreenWindow?.orderFront(nil)
                genericView.set(isInFullScreen: true)
                fullScreenWindow?.becomeKey()
                fullScreenWindow?.setFrame(screen.frame, display: true, animate: true)
            }
        }
    }
    
    public override func initializer() -> SVideoView {
        mediaPlayer = makePlayer(account: account, reference: reference, isProtected: isProtected)
        return SVideoView(frame: _frameRect, mediaPlayer: self.mediaPlayer)
    }
    
    deinit {
        statusDisposable.dispose()
        bufferingDisposable.dispose()
        hideOnIdleDisposable.dispose()
        hideControlsDisposable.dispose()
        mediaPlaybackStateDisposable.dispose()
        adStateDisposable.dispose()
        nextAdDisposable.dispose()
        partDisposable.dispose()
        frameStepDisposable?.dispose()
        scrubbingFrameDisposable?.dispose()
        if let endPlaybackId {
            mediaPlayer.removePlaybackCompleted(endPlaybackId)
        }
        updateControls?.invalidate()
        _ = screenSleep.enableScreenSleep()
    }
    
}
