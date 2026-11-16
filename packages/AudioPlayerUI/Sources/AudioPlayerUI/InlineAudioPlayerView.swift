import Cocoa
import TGUIKit
import TelegramCore

import Postbox
import SwiftSignalKit
import RangeSet
import TelegramMedia
import InAppSettings
import Localization
import TelegramTheme
import TelegramContext
import TelegramUtils
import LocalAnimations
import GeneralRows
import AudioPlayerCore

private func effectivePlayingRate(for controller: APController) -> Double {
    if controller is APChatMusicController {
        return FastSettings.playingMusicRate
    } else {
        return FastSettings.playingRate
    }
}
private func setPlayingRate(_ rate: Double, for controller: APController) {
    if controller is APChatMusicController {
        FastSettings.setPlayingMusicRate(rate)
    } else {
        FastSettings.setPlayingRate(rate)
    }
}



public class InlineAudioPlayerView: NavigationHeaderView, APDelegate {

    private static let collapsedHeight: CGFloat = 52
    private static let expandedHeight: CGFloat = 66
    private static let containerInset: CGFloat = 12
    private static let hoverInset: CGFloat = 6
    private static let cornerRadius: CGFloat = 20


    public struct ContextObject {
        public let controller: APController
        public let context: any AccountContextProtocol
        public weak var tableView: TableView?
        public weak var supportTableView: TableView?
        public init(controller: APController, context: any AccountContextProtocol, tableView: TableView?, supportTableView: TableView?) {
            self.controller = controller
            self.context = context
            self.tableView = tableView
            self.supportTableView = supportTableView
        }
    }

    public var contextValue: ContextObject? {
        return header?.contextObject as? ContextObject
    }
    public var controller: APController? {
        return contextValue?.controller
    }
    public var context: (any AccountContextProtocol)? {
        return contextValue?.context
    }

    private let previous:ImageButton = ImageButton()
    private let next:ImageButton = ImageButton()

    private let playPause = Button()
    private let playPauseView = LottiePlayerView()

    private let dismiss:ImageButton = ImageButton()
    private let repeatControl:ImageButton = ImageButton()
    private let volumeControl: ImageButton = ImageButton()
    private let progressView:LinearProgressControl = LinearProgressControl(progressHeight: 2)
    private var artistNameView:TextView?
    private let trackNameView:TextView = TextView()
    private let textViewContainer = Control()
    private let containerView:Control
    private let glassView: LiquidGlassView
    private let playingSpeed: ImageButton = ImageButton()
    private let timeTooltip = View()
    private let timeTooltipText = TextView()

    private var isExpanded = false
    private var hoveredProgress: CGFloat? {
        didSet {
            updateHoverPresentation()
        }
    }
    private var expansionProgress: CGFloat = 0
    private var expansionAnimator: DisplayLinkAnimator?
    private var proximityTrackingArea: NSTrackingArea?
    private var windowDidResignKeyObserver: NSObjectProtocol?
    private weak var immovableWindow: NSWindow?


    private var message:Message?
    private(set) var instantVideoPip:InlineAudioPlayerInstantVideoPIP?
    
    private var bufferingStatusDisposable: MetaDisposable = MetaDisposable()
    private weak var observedController: APController?
    
   
    
    public override init(_ header: NavigationHeader) {

        dismiss.disableActions()
        repeatControl.disableActions()

        trackNameView.isSelectable = false
        trackNameView.userInteractionEnabled = false
        containerView = Control(frame: NSMakeRect(0, 0, 0, header.height))
        glassView = LiquidGlassView(frame: .zero, cornerRadius: Self.cornerRadius, hasShadow: true, hasBorder: true, tintAlpha: 0.4)

        super.init(header)

        dismiss.set(handler: { [weak self] _ in
            self?.stopAndHide(true)
        }, for: .Click)
        
        previous.set(handler: { [weak self] _ in
            self?.controller?.prev()
        }, for: .Click)
        
        next.set(handler: { [weak self] _ in
            self?.controller?.next()
        }, for: .Click)
        
        playPause.set(handler: { [weak self] _ in
            _ = self?.controller?.playOrPause()
        }, for: .Click)
        
        repeatControl.set(handler: { [weak self] _ in
            if let controller = self?.controller {
                if self?.hasPlayerList == true {
                    self?.showAudioPlayerList()
                } else {
                    controller.nextRepeatState()
                }
            }
        }, for: .Click)
        
        repeatControl.scaleOnClick = true
        playPause.scaleOnClick = true
        next.scaleOnClick = true
        previous.scaleOnClick = true
        dismiss.scaleOnClick = true
        playingSpeed.scaleOnClick = true
        
        progressView.layer?.cornerRadius = 2
        progressView.alignment = .center

        progressView.onUserChanged = { [weak self] progress in
            self?.controller?.set(trackProgress: progress)
            self?.progressView.set(progress: CGFloat(progress), animated: false)
            self?.hoveredProgress = CGFloat(progress)
        }

        progressView.onHoverUpdated = { [weak self] progress in
            self?.hoveredProgress = progress
        }

        progressView.set(handler: { [weak self] control in
            let control = control as! LinearProgressControl
            if let strongSelf = self {
                strongSelf.controller?.set(trackProgress: control.interactiveValue)
                strongSelf.progressView.set(progress: CGFloat(control.interactiveValue), animated: false)
            }
        }, for: .Click)
        
        previous.setAccessibilityLabel(strings().voiceOverCommonPrevious)
        next.setAccessibilityLabel(strings().voiceOverCommonNext)
        playPause.setAccessibilityLabel(strings().voiceOverCommonPlay)
        dismiss.setAccessibilityLabel(strings().voiceOverCommonClose)
        repeatControl.setAccessibilityLabel(strings().dateSelectorScheduleRepeat)
        volumeControl.setAccessibilityLabel(strings().voiceOverCommonVolume)
        playingSpeed.setAccessibilityLabel(strings().voiceOverCommonPlaybackSpeed)
        containerView.isAccessibilityDecorative = true

        previous.autohighlight = false
        next.autohighlight = false
        playPause.autohighlight = false
        repeatControl.autohighlight = false
        volumeControl.autohighlight = false
        playingSpeed.autohighlight = false
        
        previous.scaleOnClick = true
        next.scaleOnClick = true
        playPause.scaleOnClick = true
        repeatControl.scaleOnClick = true
        volumeControl.scaleOnClick = true
        playingSpeed.scaleOnClick = true
        
        
        
        containerView.addSubview(previous)
        containerView.addSubview(next)
        
        playPause.addSubview(playPauseView)
        playPause.setFrameSize(NSMakeSize(34, 34))
        playPauseView.setFrameSize(playPause.frame.size)
        containerView.addSubview(playPause)
        
        containerView.addSubview(dismiss)
        containerView.addSubview(repeatControl)
        containerView.addSubview(textViewContainer)
        containerView.addSubview(playingSpeed)
        containerView.addSubview(volumeControl)
        containerView.addSubview(progressView)
        addSubview(glassView)
        addSubview(containerView)
        timeTooltip.isEventLess = true
        timeTooltip.isHidden = true
        timeTooltipText.isEventLess = true
        timeTooltip.addSubview(timeTooltipText)
        addSubview(timeTooltip)

        let tooltipShadow = NSShadow()
        tooltipShadow.shadowBlurRadius = 6
        tooltipShadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
        tooltipShadow.shadowOffset = NSMakeSize(0, 2)
        timeTooltip.shadow = tooltipShadow
        
        textViewContainer.addSubview(trackNameView)

        trackNameView.userInteractionEnabled = false
        trackNameView.isEventLess = true
        trackNameView.isAccessibilityDecorative = true
        
        
        
        
        textViewContainer.set(handler: { [weak self] _ in
            self?.gotoMessage()
        }, for: .SingleClick)
        
        
        playingSpeed.contextMenu = { [weak self] in
            
            let menu = ContextMenu()
            
            guard let controller = self?.controller else {
                return menu
            }

            let customItem = ContextMenuItem(String(format: "%.1fx", effectivePlayingRate(for: controller)), image: NSImage(cgImage: generateEmptySettingsIcon(), size: NSMakeSize(24, 24)))
            
            menu.addItem(SliderContextMenuItem(volume: effectivePlayingRate(for: controller), minValue: 0.2, maxValue: 2.5, midValue: 1, drawable: MenuAnimation.menu_speed, drawable_muted: MenuAnimation.menu_speed, { [weak self] value, _ in
                customItem.title = String(format: "%.1fx", value)
                if let controller = self?.controller {
                    setPlayingRate(value, for: controller)
                    self?.controller?.baseRate = effectivePlayingRate(for: controller)
                }
            }))
            
            
            menu.addItem(customItem)
            
            if effectivePlayingRate(for: controller) != 1.0 {
                menu.addItem(ContextSeparatorItem())
                menu.addItem(ContextMenuItem(strings().playbackSpeedSetToDefault, handler: { [weak self] in
                    if let controller = self?.controller {
                        setPlayingRate(1.0, for: controller)
                        controller.baseRate = effectivePlayingRate(for: controller)
                    }
                }, itemImage: MenuAnimation.menu_reset.value))
            }

            
            return menu
        }
        
//        playingSpeed.set(handler: { [weak self] control in
//            FastSettings.setPlayingRate(FastSettings.playingRate != 1 ? 1.0 : 1.75)
//            self?.controller?.baseRate = FastSettings.playingRate
//        }, for: .Click)
        
        
        volumeControl.set(handler: { [weak self] control in
            if control.popover == nil {
                showPopover(for: control, with: VolumeControllerPopover(initialValue: CGFloat(FastSettings.volumeRate), updatedValue: { updatedVolume in
                    FastSettings.setVolumeRate(Float(updatedVolume))
                    self?.controller?.volume = FastSettings.volumeRate
                }), edge: .maxY, inset: NSMakePoint(-5, -50))
            }
        }, for: .Hover)
        
        volumeControl.set(handler: { control in
            FastSettings.setVolumeRate(FastSettings.volumeRate > 0 ? 0 : 1.0)
            if let popover = control.popover?.controller as? VolumeControllerPopover {
                popover.value = CGFloat(FastSettings.volumeRate)
            }
        }, for: .Up)
        
        self.layer?.masksToBounds = false
        containerView.layer?.masksToBounds = true
        containerView.layer?.cornerRadius = Self.cornerRadius

        updateLocalizationAndTheme(theme: theme)

    }
    
    var hasPlayerList: Bool {
        if let controller = controller, let song = controller.currentSong {
            switch song.entry {
            case .song:
                return true
            case .savedMusic:
                return true
            default:
                return false
            }
        }
        return false
    }
    
    private func showAudioPlayerList() {
        guard let window = _window, let context = self.context else {return}
        if let controller = controller as? APChatMusicController, let song = controller.currentSong {
            switch song.stableId {
            case let .message(message):
                AudioPlayerUIHooks.shared.showChatPlayerList(self, controller, context, message, window)
            default:
                break
            }
        } else if let controller = controller as? APProfileSavedController, let song = controller.currentSong {
            switch song.entry {
            case let .savedMusic(reference, _):
                AudioPlayerUIHooks.shared.showProfilePlayerList(self, controller, context, reference, window)
            default:
                break
            }
        }
    }
    
    func updateStatus(_ ranges: RangeSet<Int64>, _ size: Int64) {
        progressView.set(fetchingProgressRanges: audioPlayerBufferingRanges(ranges, size: size), animated: false)
    }
    
    
    private var playProgressStyle:ControlStyle {
        return ControlStyle(foregroundColor: theme.colors.text, backgroundColor: .clear, highlightColor: .clear)
    }
    private var fetchProgressStyle:ControlStyle {
        return ControlStyle(foregroundColor: theme.colors.grayTransparent, backgroundColor: .clear, highlightColor: .clear)
    }
    
    public override func updateLocalizationAndTheme(theme: PresentationTheme) {
        super.updateLocalizationAndTheme(theme: theme)
        let theme = (theme as! TelegramPresentationTheme)
        
        progressView.fetchingColor = theme.colors.text.withAlphaComponent(0.3)
        progressView.previewColor = theme.colors.text.withAlphaComponent(0.25)

        backgroundColor = .clear
        containerView.backgroundColor = .clear
        artistNameView?.backgroundColor = .clear
        timeTooltip.backgroundColor = theme.colors.background
        progressView.containerBackground = theme.colors.grayIcon.withAlphaComponent(0.2 * expansionProgress)
        
        controller?.notifyGlobalStateChanged(animated: false)
        
        
    }
    
    private func gotoMessage() {
        if let message = message, let context = context, context.peerId == controller?.context.peerId {
            AudioPlayerUIHooks.shared.gotoMessage(context, message)
        }
    }

    public override func update(with contextObject: Any) {
        super.update(with: contextObject)

        let contextObject = contextObject as! ContextObject

        let controller = contextObject.controller

        observedController?.remove(listener: self)
        observedController = controller
        self.updateStatus(RangeSet(), 0)

        self.bufferingStatusDisposable.set((controller.bufferingStatus
            |> deliverOnMainQueue).start(next: { [weak self, weak controller] status in
                guard let self, let controller, self.observedController === controller, self.controller === controller else {
                    return
                }
                if let status = status {
                    self.updateStatus(status.0, status.1)
                } else {
                    self.updateStatus(RangeSet(), 0)
                }
            }))
        controller.baseRate = effectivePlayingRate(for: controller)


        controller.add(listener: self)
        self.ready.set(controller.ready.get())

        repeatControl.isHidden = !controller.canMakeRepeat
        if let tableView = contextObject.tableView {
            if self.instantVideoPip == nil {
                self.instantVideoPip = AudioPlayerUIHooks.shared.makeInstantVideoPip(controller)
            }
            AudioPlayerUIHooks.shared.updateInstantVideoPip(self.instantVideoPip, tableView, controller)
            addGlobalAudioToVisible(tableView: tableView)
        }
        if let supportTableView = contextObject.supportTableView {
            addGlobalAudioToVisible(tableView: supportTableView)
        }
        if let song = controller.currentSong {
            songDidChanged(song: song, for: controller, animated: true)
        }
    }

    private func addGlobalAudioToVisible(tableView: TableView) {
        if let controller = controller {
            AudioPlayerUIHooks.shared.addGlobalAudioToVisible(tableView, controller)
            controller.notifyGlobalStateChanged(animated: false)
        }
    }
    
    deinit {
        observedController?.remove(listener: self)
        if let windowDidResignKeyObserver {
            NotificationCenter.default.removeObserver(windowDidResignKeyObserver)
        }
        expansionAnimator?.invalidate()
        bufferingStatusDisposable.dispose()
        immovableWindow?.isMovable = true
    }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        setWindowMovable(true)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        if let windowDidResignKeyObserver {
            NotificationCenter.default.removeObserver(windowDidResignKeyObserver)
            self.windowDidResignKeyObserver = nil
        }

        resetExpansion()

        if let window {
            windowDidResignKeyObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main, using: { [weak self] _ in
                self?.resetExpansion()
            })
        }
    }
    
    func attributedTitle(for song:APSongItem) -> (NSAttributedString, NSAttributedString?) {
        let trackName:NSAttributedString
        let artistName:NSAttributedString?

        if song.songName.isEmpty {
            trackName = .initialize(string: song.performerName, color: theme.colors.text, font: .normal(.text))
            artistName = nil
        } else {
            trackName = .initialize(string: song.songName, color: theme.colors.text, font: .normal(.text))
            if !song.performerName.isEmpty {
                artistName = .initialize(string: song.performerName, color: theme.colors.darkGrayText, font: .normal(.text))
            } else {
                artistName = nil
            }
        }

        return (trackName, artistName)
    }
    
    
    private func update(_ song: APSongItem, controller: APController, animated: Bool) {
        guard observedController === controller, self.controller === controller, controller.currentSong?.stableId == song.stableId else {
            return
        }
        
        
        let iconColor = theme.colors.text
        let dimColor = theme.colors.darkGrayText
        dismiss.set(image: TelegramThemeHooks.shared.image(.iconPipClose).precomposed(iconColor), for: .Normal)

        switch song.entry {
        case let .song(message):
            self.message = message
        default:
            self.message = nil
        }

        next.userInteractionEnabled = controller.nextEnabled
        previous.userInteractionEnabled = controller.prevEnabled

        switch controller.nextEnabled {
        case true:
            next.set(image: TelegramThemeHooks.shared.image(.iconInlinePlayerNext).precomposed(iconColor), for: .Normal)
        case false:
            next.set(image: TelegramThemeHooks.shared.image(.iconInlinePlayerNext).precomposed(dimColor), for: .Normal)
        }

        switch controller.prevEnabled {
        case true:
            previous.set(image: TelegramThemeHooks.shared.image(.iconInlinePlayerNext).precomposed(iconColor, flipHorizontal: true), for: .Normal)
        case false:
            previous.set(image: TelegramThemeHooks.shared.image(.iconInlinePlayerNext).precomposed(dimColor, flipHorizontal: true), for: .Normal)
        }
                
        let attr = attributedTitle(for: song)
        
        if trackNameView.textLayout?.attributedString != attr.0 {
            let artist = TextViewLayout(attr.0, maximumNumberOfLines:1, alignment: .left)
            self.trackNameView.update(artist)
        }
        textViewContainer.setAccessibilityLabel([attr.0.string, attr.1?.string ?? ""].filter { !$0.isEmpty }.joined(separator: ", "))
        if let attr = attr.1 {
            let current: TextView
            if self.artistNameView == nil {
                current = TextView()
                current.userInteractionEnabled = false
                current.isEventLess = true
                current.isAccessibilityDecorative = true
                self.artistNameView = current
                textViewContainer.addSubview(current)
            } else {
                current = self.artistNameView!
            }
            if current.textLayout?.attributedString != attr {
                let artist = TextViewLayout(attr, maximumNumberOfLines:1, alignment: .left)
                current.update(artist)
            }
            
        } else {
            if let view = self.artistNameView {
                self.artistNameView = nil
                if animated {
                    view.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak view] _ in
                        view?.removeFromSuperview()
                    })
                } else {
                    view.removeFromSuperview()
                }
            }
        }
        
        playingSpeed.set(image: optionsRateImage(rate: String(format: "%.1fx", effectivePlayingRate(for: controller)), color: effectivePlayingRate(for: controller) == 1.0 ? dimColor : iconColor, isLarge: true), for: .Normal)

        volumeControl.setAccessibilityValue(FastSettings.volumeRate == 0 ? strings().voiceOverCommonMuted : nil)
        switch FastSettings.volumeRate {
        case 0:
            volumeControl.set(image: TelegramThemeHooks.shared.image(.iconInlinePlayerVolumeOff).precomposed(dimColor), for: .Normal)
        default:
            volumeControl.set(image: TelegramThemeHooks.shared.image(.iconInlinePlayerVolumeOn).precomposed(iconColor), for: .Normal)
        }

        if hasPlayerList {
            repeatControl.setAccessibilityLabel(strings().voiceOverCommonPlaylist)
            repeatControl.setAccessibilityValue(nil)
            repeatControl.set(image: TelegramThemeHooks.shared.image(.iconAudioPlayerList).precomposed(dimColor), for: .Normal)
        } else {
            repeatControl.setAccessibilityLabel(strings().dateSelectorScheduleRepeat)
            switch controller.state.repeatState {
            case .circle:
                repeatControl.setAccessibilityValue(strings().voiceOverCommonRepeatAll)
                repeatControl.set(image: TelegramThemeHooks.shared.image(.iconInlinePlayerRepeat).precomposed(iconColor), for: .Normal)
            case .one:
                repeatControl.setAccessibilityValue(strings().voiceOverCommonRepeatOne)
                repeatControl.set(image: TelegramThemeHooks.shared.image(.iconInlinePlayerRepeatOne).precomposed(iconColor), for: .Normal)
            case .none:
                repeatControl.setAccessibilityValue(strings().dateSelectorScheduleRepeatNever)
                repeatControl.set(image: TelegramThemeHooks.shared.image(.iconInlinePlayerRepeat).precomposed(dimColor), for: .Normal)
            }

        }
        
       
       
        
        switch song.state {
        case .waiting:
            progressView.style = playProgressStyle
            progressView.set(progress: 0, animated: animated)
        case .stoped:
            progressView.style = playProgressStyle
            progressView.set(progress: 0, animated: animated)
        case let .playing(_, _, progress), let .paused(_, _, progress):
            progressView.style = playProgressStyle
            progressView.set(progress: CGFloat(progress.isFinite ? min(max(progress, 0), 1) : 0), animated: animated, duration: 0.2)
        case let .fetching(progress):
            progressView.style = fetchProgressStyle
            progressView.set(progress: CGFloat(progress.isFinite ? min(max(progress, 0), 1) : 0), animated: animated)
        }
        
        switch controller.state.status {
        case .playing:
            playPause.setAccessibilityLabel(strings().voiceOverCommonPause)
            play(animated: animated, sticker: LocalAnimatedSticker.playlist_play_pause)
        case .paused:
            playPause.setAccessibilityLabel(strings().voiceOverCommonPlay)
            play(animated: animated, sticker: LocalAnimatedSticker.playlist_pause_play)
        default:
            break
        }
        
        _ = previous.sizeToFit()
        _ = next.sizeToFit()
        _ = dismiss.sizeToFit()
        _ = repeatControl.sizeToFit()
        _ = playingSpeed.sizeToFit()
        _ = volumeControl.sizeToFit()
        
        needsLayout = true
        updateHoverPresentation()
    }
    
    public func songDidChanged(song:APSongItem, for controller:APController, animated: Bool) {
        self.update(song, controller: controller, animated: animated)
    }
    
    public func songDidChangedState(song: APSongItem, for controller: APController, animated: Bool) {
        self.update(song, controller: controller, animated: animated)
    }
    
    public func songDidStartPlaying(song:APSongItem, for controller:APController, animated: Bool) {
        self.update(song, controller: controller, animated: animated)
    }
    public func songDidStopPlaying(song:APSongItem, for controller:APController, animated: Bool) {
        self.update(song, controller: controller, animated: animated)
    }
    public func playerDidChangedTimebase(song:APSongItem, for controller:APController, animated: Bool) {
        self.update(song, controller: controller, animated: animated)
    }
    
    public func audioDidCompleteQueue(for controller:APController, animated: Bool) {
        guard observedController === controller, self.controller === controller else {
            return
        }
        stopAndHide(true)
    }

    private var progressHoverRect: NSRect {
        let progressRect = convert(progressView.bounds, from: progressView)
        return progressRect.insetBy(dx: -Self.hoverInset, dy: -Self.hoverInset)
    }

    private func updateExpansionForCurrentMouseLocation() {
        guard let window, window.isKeyWindow else {
            setExpanded(false)
            return
        }
        let location = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setExpanded(progressHoverRect.contains(location))
    }

    private func updateProximityTrackingArea() {
        let trackingRect = NSMakeRect(bounds.minX, bounds.minY, bounds.width, Self.expandedHeight)
            .insetBy(dx: -Self.hoverInset, dy: -Self.hoverInset)

        if proximityTrackingArea?.rect == trackingRect {
            return
        }
        if let proximityTrackingArea {
            removeTrackingArea(proximityTrackingArea)
        }
        let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .enabledDuringMouseDrag]
        let proximityTrackingArea = NSTrackingArea(rect: trackingRect, options: options, owner: self, userInfo: nil)
        self.proximityTrackingArea = proximityTrackingArea
        addTrackingArea(proximityTrackingArea)
        updateExpansionForCurrentMouseLocation()
    }

    public override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        updateExpansionForCurrentMouseLocation()
    }

    public override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updateExpansionForCurrentMouseLocation()
    }

    public override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        updateExpansionForCurrentMouseLocation()
    }

    private func setExpanded(_ isExpanded: Bool) {
        guard self.isExpanded != isExpanded else {
            return
        }
        self.isExpanded = isExpanded
        setWindowMovable(!isExpanded)
        if !isExpanded {
            hoveredProgress = nil
        }
        expansionAnimator?.invalidate()

        let target: CGFloat = isExpanded ? 1 : 0
        let distance = abs(target - expansionProgress)
        guard distance > CGFloat.ulpOfOne else {
            applyExpansionProgress(target)
            expansionAnimator = nil
            return
        }

        let duration = max(1.0 / 60.0, 0.15 * Double(distance))
        expansionAnimator = DisplayLinkAnimator(duration: duration, from: expansionProgress, to: target, timingFunction: .init(controlPoints: 0, 0, 0.2, 1), update: { [weak self] progress in
            self?.applyExpansionProgress(progress)
        }, completion: { [weak self] in
            self?.applyExpansionProgress(target)
            self?.expansionAnimator = nil
        })
    }

    private func applyExpansionProgress(_ progress: CGFloat) {
        expansionProgress = min(max(progress, 0), 1)
        let height = Self.collapsedHeight + (Self.expandedHeight - Self.collapsedHeight) * expansionProgress

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        header?.updateRealHeight(height, animated: false)
        needsLayout = true
        layoutSubtreeIfNeeded()
        CATransaction.commit()
    }

    private func resetExpansion() {
        expansionAnimator?.invalidate()
        expansionAnimator = nil
        isExpanded = false
        setWindowMovable(true)
        hoveredProgress = nil
        applyExpansionProgress(0)
    }

    private func setWindowMovable(_ movable: Bool) {
        if movable {
            immovableWindow?.isMovable = true
            immovableWindow = nil
        } else if let window, window.isMovable {
            window.isMovable = false
            immovableWindow = window
        }
    }

    private func formattedDuration(_ duration: Double) -> String {
        let duration = max(0, Int(duration))
        let hours = duration / 3600
        let minutes = duration / 60 % 60
        let seconds = duration % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    private func updateHoverPresentation() {
        guard isExpanded, let hoveredProgress, let controller, controller.duration > 0 else {
            progressView.previewProgress = nil
            timeTooltip.isHidden = true
            return
        }
        progressView.previewProgress = hoveredProgress
        let current = controller.duration * hoveredProgress
        let text = NSMutableAttributedString()
        _ = text.append(string: formattedDuration(current), color: theme.colors.text, font: .medium(.text))
        _ = text.append(string: "  \(formattedDuration(controller.duration))", color: theme.colors.grayText, font: .normal(.text))
        let layout = TextViewLayout(text, maximumNumberOfLines: 1)
        layout.measure(width: 160)
        timeTooltipText.update(layout)
        timeTooltip.isHidden = false
        needsLayout = true
    }
    
    public override func layout() {
        super.layout()

        let hInset = Self.containerInset
        let topInset = Self.containerInset
        let contentHeight = frame.height - topInset
        let controlsHeight: CGFloat = 40
        let glassRect = NSMakeRect(hInset, topInset, max(0, frame.width - hInset * 2), contentHeight)
        glassView.frame = glassRect
        glassView.updateLayout(size: glassRect.size, transition: .immediate)
        containerView.frame = glassRect

        func place(_ view: NSView, x: CGFloat) {
            view.setFrameOrigin(NSMakePoint(x, floor((controlsHeight - view.frame.height) / 2)))
        }

        place(previous, x: 10)
        place(playPause, x: previous.frame.maxX + 5)
        place(next, x: playPause.frame.maxX + 5)

        place(dismiss, x: containerView.frame.width - 12 - dismiss.frame.width)

        let progressRadius: CGFloat = 20
        let collapsedLineHeight: CGFloat = 2
        let expandedLineHeight: CGFloat = 6
        let progressLineHeight = collapsedLineHeight + (expandedLineHeight - collapsedLineHeight) * expansionProgress
        let progressPadding = (progressLineHeight + 2) * expansionProgress
        let progressControlHeight = progressLineHeight + progressPadding * 2
        let progressY = contentHeight - progressControlHeight
        progressView.progressHeight = progressLineHeight
        progressView.frame = NSMakeRect(progressRadius, progressY, max(0, containerView.frame.width - progressRadius * 2), progressControlHeight)
        progressView.cornerRadius = 0
        progressView.roundCorners = true
        progressView.containerBackground = theme.colors.grayIcon.withAlphaComponent(0.2 * expansionProgress)
        updateProximityTrackingArea()

        let textWidth = containerView.frame.width - (next.frame.maxX + dismiss.frame.width + repeatControl.frame.width + (playingSpeed.isHidden ? 0 : playingSpeed.frame.width + 10) + volumeControl.frame.width + 70)

        artistNameView?.resize(textWidth)
        trackNameView.resize(textWidth)

        let effectiveWidth = [artistNameView, trackNameView].compactMap { $0?.frame.width }.max(by: { $0 < $1 }) ?? 0

        textViewContainer.frame = NSMakeRect(next.frame.maxX + 20, 0, effectiveWidth, controlsHeight)

        if let artistNameView = artistNameView {
            trackNameView.setFrameOrigin(NSMakePoint(0, 4))
            artistNameView.setFrameOrigin(NSMakePoint(0, textViewContainer.frame.height - artistNameView.frame.height - 4))
        } else {
            trackNameView.centerY(x: 0)
        }

        let controls = [volumeControl, playingSpeed, repeatControl].filter { !$0.isHidden }

        var x: CGFloat = dismiss.frame.minX - 10
        for control in controls {
            x = x - control.frame.width
            place(control, x: x)
            x -= 10
        }

        if !timeTooltip.isHidden {
            let tooltipHeight: CGFloat = 24
            let tooltipWidth = timeTooltipText.frame.width + 16
            let progressMinX = containerView.frame.minX + progressView.frame.minX
            let progressMaxX = containerView.frame.minX + progressView.frame.maxX
            let pointerX = progressMinX + progressView.frame.width * (hoveredProgress ?? 0)
            let maxTooltipX = max(progressMinX, progressMaxX - tooltipWidth)
            let x = min(max(pointerX + 12, progressMinX), maxTooltipX)
            let visibleTrackMaxY = progressView.frame.midY + progressLineHeight / 2
            let y = containerView.frame.minY + visibleTrackMaxY + 4
            timeTooltip.frame = NSMakeRect(x, y, tooltipWidth, tooltipHeight)
            timeTooltip.layer?.cornerRadius = tooltipHeight / 2
            timeTooltipText.center()
        }
    }
    
    private func play(animated: Bool, sticker: LocalAnimatedSticker) {
        let data = sticker.data
        if let data = data {
            
            let current: Int32
            let total: Int32
            if playPauseView.animation?.key.key != LottieAnimationKey.bundle(sticker.rawValue) {
                current = playPauseView.currentFrame ?? 0
                total = playPauseView.totalFrames ?? 0
            } else {
                current = 0
                total = playPauseView.currentFrame ?? 0
            }
            let animation = LottieAnimation(compressed: data, key: .init(key: .bundle(sticker.rawValue), size: NSMakeSize(34, 34)), cachePurpose: .none, playPolicy: .toEnd(from: animated ? total - current : .max), colors: [.init(keyPath: "", color: theme.colors.text)], runOnQueue: .mainQueue())
            playPauseView.set(animation)
        }
    }
    
    func stopAndHide(_ animated:Bool) -> Void {
        guard let controller = self.controller, observedController === controller else {
            return
        }
        resetExpansion()
        observedController = nil
        bufferingStatusDisposable.set(nil)
        controller.remove(listener: self)
        controller.stop()
        controller.cleanup()
        AudioPlayerUIHooks.shared.hideInstantVideoPip(instantVideoPip)
        instantVideoPip = nil
        AudioPlayerUIHooks.shared.endInlinePlayer(context, animated)
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
