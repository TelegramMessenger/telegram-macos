import Cocoa
import TelegramCallsCore
import Foundation
import TGUIKit
import SwiftSignalKit
import TelegramCore
import Postbox
import InAppSettings
import CallsUI
import Localization

private final class GroupCallControlsTooltipView: Control {
    private let backgroundView = View()
    private let textView = TextView()
    private let cornerView =  ImageView()
    private let closeView = ImageButton()
    private(set) weak var toView: NSView?
    required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)
        backgroundView.addSubview(textView)
        addSubview(cornerView)
        addSubview(closeView)
        cornerView.isEventLess = true
        cornerView.isAccessibilityDecorative = true
        closeView.setAccessibilityLabel(strings().voiceOverCommonClose)
        backgroundView.isEventLess = true
        textView.userInteractionEnabled = false
        textView.isSelectable = false
        textView.disableBackgroundDrawing = true
        cornerView.image = generateImage(NSMakeSize(30, 12), rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            context.setFillColor(GroupCallTheme.memberSeparatorColor.cgColor)
            context.scaleBy(x: 0.333, y: 0.333)
            let _ = try? drawSvgPath(context, path: "M85.882251,0 C79.5170552,0 73.4125613,2.52817247 68.9116882,7.02834833 L51.4264069,24.5109211 C46.7401154,29.1964866 39.1421356,29.1964866 34.4558441,24.5109211 L16.9705627,7.02834833 C12.4696897,2.52817247 6.36519576,0 0,0 L85.882251,0 ")
            context.fillPath()
        })!
        cornerView.sizeToFit()
        
        closeView.autohighlight = false
        closeView.scaleOnClick = true
        
        closeView.set(image: generateImage(NSMakeSize(20, 20), contextGenerator: { size, ctx in
            ctx.clear(size.bounds)
            ctx.round(size, size.height / 2)
            ctx.setFillColor(GroupCallTheme.membersColor.cgColor)
            ctx.fill(size.bounds)
            
            ctx.draw(GroupCallTheme.closeTooltip, in: size.bounds.focus(GroupCallTheme.closeTooltip.backingSize))
        })!, for: .Normal)
        
        closeView.set(handler: { [weak self] _ in
            self?.send(event: .SingleClick)
        }, for: .SingleClick)
        
        closeView.sizeToFit()
    }
    
    func set(text: String, maxWidth: CGFloat, to view: NSView?) {
        let layout = TextViewLayout(.initialize(string: text, color: GroupCallTheme.customTheme.textColor, font: .normal(12)))
        layout.measure(width: maxWidth)
        textView.update(layout)
        
        self.toView = view
        backgroundView.background = GroupCallTheme.memberSeparatorColor
        
        setFrameSize(NSMakeSize(layout.layoutSize.width + 16 + 24, layout.layoutSize.height + 8 + 10))
        
        backgroundView.layer?.cornerRadius = (frame.height - 10) / 2
    }
    
    override func layout() {
        super.layout()
        backgroundView.frame = focus(NSMakeSize(frame.width, frame.height - 10))
        
        if let toView = toView {
            cornerView.setFrameOrigin(NSMakePoint(toView.frame.minX - 12 + toView.frame.width / 2 - cornerView.frame.width / 2, frame.height - 10))
        } else {
            cornerView.centerX(y: frame.height - 10)
        }
        
        closeView.centerY(x: 1)
        textView.centerY(x: 26)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

public final class GroupCallControlsView : View {
    
    public enum Mode : Equatable {
        case normal
        case fullscreen
    }
    
    public private(set) var mode: Mode = .normal
    public var callMode: GroupCallUIState.Mode = .voice
    
    public private(set) var hasVideo: Bool = false
    public private(set) var hasScreencast: Bool = false
    
    private let speak: GroupCallSpeakButton = GroupCallSpeakButton(frame: NSMakeRect(0, 0, 140, 140))
    private let leftButton1: CallControl = CallControl(frame: .zero)
    private var leftButton2: CallControl?
    private var rightButton1: CallControl?
    private let end: CallControl = CallControl(frame: .zero)
    private var speakText: TextView?
    public var arguments: GroupCallUIArguments?

    private let backgroundView = VoiceChatActionButtonBackgroundView()
    public let fullscreenBackgroundView: NSView
    private var tooltipView: GroupCallControlsTooltipView?
    private var isStream: Bool = false
    private var canMessage: Bool = false

    public required init(frame frameRect: NSRect, callMode: GroupCallUIState.Mode) {

        self.callMode = callMode

        self.fullscreenBackgroundView = LiquidGlassView(frame: .zero, cornerRadius: 20, hasShadow: true, hasBorder: true, forceAppearance: .forceDark)

        super.init(frame: frameRect)

        self.fullscreenBackgroundView.wantsLayer = true
        self.fullscreenBackgroundView.layer?.cornerRadius = 20
        self.fullscreenBackgroundView.layer?.opacity = 0
        
        addSubview(fullscreenBackgroundView)
        
        addSubview(backgroundView)
        addSubview(speak)
        

        addSubview(leftButton1)
        addSubview(end)
        
        backgroundView.isEventLess = true
        backgroundView.userInteractionEnabled = false
        
        self.isEventLess = true
        

        end.set(handler: { [weak self] _ in
            self?.arguments?.leave()
        }, for: .SingleClick)
                
        speak.set(handler: { [weak self] control in
            if let state = self?.currentState {
                if state.isStream, state.state.scheduleTimestamp == nil {
                    control.window?.level = .normal
                    control.window?.toggleFullScreen(nil)
                } else {
                    if let _ = state.state.scheduleTimestamp {
                        if state.state.canManageCall {
                            self?.arguments?.startVoiceChat()
                        } else {
                            self?.arguments?.toggleReminder(!state.state.subscribedToScheduled)
                        }
                    } else if let muteState = state.state.muteState, !muteState.canUnmute {
                        if !state.state.raisedHand {
                            self?.arguments?.toggleRaiseHand()
                        }
                        self?.speak.playRaiseHand()
                    } else {
                        self?.arguments?.toggleSpeaker()
                    }
                }
                
            }
            
        }, for: .SingleClick)

        self.backgroundView.update(state: .connecting, animated: false)
        
        self.updateLayout(size: frameRect.size, transition: .immediate)

        self.updateMode(self.mode, callMode: self.callMode, canMessage: self.canMessage, isStream: self.isStream, hasVideo: self.hasVideo, hasScreencast: self.hasScreencast, animated: false, force: true)
    }
    
    private var first: Bool = true
    
    public func updateMode(_ mode: Mode, callMode: GroupCallUIState.Mode, canMessage: Bool, isStream: Bool, hasVideo: Bool, hasScreencast: Bool, animated: Bool, force: Bool = false) {
        let previous = self.mode
        let previousCallMode = first ? nil : self.callMode
        self.isStream = isStream
        self.first = false
        
        if (previous != mode) || hasVideo != self.hasVideo  || hasScreencast != self.hasScreencast || previousCallMode != callMode || force || canMessage != self.canMessage {
            self.speakText?.change(opacity: mode == .fullscreen || callMode == .video ? 0 : 1, animated: animated)
            self.fullscreenBackgroundView._change(opacity: mode == .fullscreen ? 1 : 0, animated: animated)
            let leftButton1Text: String
            let leftBg: CallControlData.Mode
            let hasText: Bool = mode != .fullscreen
            switch callMode {
            case .voice:
                leftButton1Text = canMessage ? strings().voiceChatVideoStreamMessage : strings().voiceChatSettings
                leftBg = .normal(GroupCallTheme.settingsColor, canMessage ? GroupCallTheme.messageIcon : GroupCallTheme.settingsIcon)
                if let view = leftButton2 {
                    self.leftButton2 = nil
                    if animated {
                        view.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak view] _ in
                            view?.removeFromSuperview()
                        })
                    } else {
                        view.removeFromSuperview()
                    }
                }
                if let view = rightButton1 {
                    self.rightButton1 = nil
                    if animated {
                        view.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak view] _ in
                            view?.removeFromSuperview()
                        })
                    } else {
                        view.removeFromSuperview()
                    }
                }
            case .video:
                leftButton1Text = isStream ? canMessage ? strings().voiceChatVideoStreamMessage : strings().voiceChatSettings : strings().voiceChatVideoStreamVideo
                if isStream {
                    if canMessage {
                        leftBg = .normal(GroupCallTheme.settingsColor, GroupCallTheme.messageIcon)
                    } else {
                        leftBg = .normal(GroupCallTheme.settingsColor, GroupCallTheme.settingsIcon)
                    }
                } else {
                    leftBg = .animated(!hasVideo ? .cameraoff : .cameraon, GroupCallTheme.settingsColor)
                }
                
                if !isStream {
                    let leftButton2: CallControl
                    let rightButton1: CallControl
                    
                    
                    if let control = self.rightButton1 {
                        rightButton1 = control
                    } else {
                        rightButton1 = CallControl(frame: .zero)
                        self.rightButton1 = rightButton1
                        rightButton1.setFrameOrigin(end.frame.origin)
                        addSubview(rightButton1, positioned: .below, relativeTo: end)
                        if animated {
                            rightButton1.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                        }
                    }
                    if let control = self.leftButton2 {
                        leftButton2 = control
                    } else {
                        leftButton2 = CallControl(frame: .zero)
                        self.leftButton2 = leftButton2
                        leftButton2.setFrameOrigin(leftButton1.frame.origin)
                        addSubview(leftButton2, positioned: .below, relativeTo: leftButton1)
                        if animated {
                            leftButton2.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                        }
                    }
                    leftButton2.updateWithData(CallControlData(text: hasText ? strings().voiceChatVideoStreamScreencast : nil, mode: .animated(!hasScreencast ? .screenoff : .screenon, GroupCallTheme.settingsColor), iconSize: NSMakeSize(48, 48)), animated: animated)
                    leftButton2.setAccessibilityLabel(strings().voiceOverCommonShareScreen)
                    leftButton2.setAccessibilityValue(hasScreencast ? strings().voiceOverCommonOn : strings().voiceOverCommonOff)
                    
                    rightButton1.updateWithData(CallControlData(text: hasText ? (canMessage ? strings().voiceChatVideoStreamMessage : strings().voiceChatSettings) : nil, mode: .normal(GroupCallTheme.settingsColor, canMessage ? GroupCallTheme.messageIcon : GroupCallTheme.settingsIcon), iconSize: NSMakeSize(48, 48)), animated: animated)
                    rightButton1.setAccessibilityLabel(canMessage ? strings().voiceChatVideoStreamMessage : strings().voiceChatSettings)
                }
            }
            
            end.updateWithData(CallControlData(text: hasText ? strings().voiceChatLeaveGrupCall : nil, mode: .normal(GroupCallTheme.declineColor, GroupCallTheme.declineIcon), iconSize: NSMakeSize(48, 48)), animated: animated)
            leftButton1.updateWithData(CallControlData(text: hasText ? leftButton1Text : nil, mode: leftBg, iconSize: NSMakeSize(48, 48)), animated: animated)
            end.setAccessibilityLabel(strings().voiceChatLeaveGrupCall)
            leftButton1.setAccessibilityLabel(leftButton1Text)
            if callMode == .video, !isStream {
                leftButton1.setAccessibilityValue(hasVideo ? strings().voiceOverCommonOn : strings().voiceOverCommonOff)
            } else {
                leftButton1.setAccessibilityValue(nil)
            }

            let view = self.backgroundView

            
            let rect = view.bounds
            var fr = CATransform3DIdentity
            fr = CATransform3DTranslate(fr, rect.width / 2, rect.height / 2, 0)
            fr = CATransform3DScale(fr, 0.42, 0.42, 1)
            fr = CATransform3DTranslate(fr, -(rect.width / 2), -(rect.height / 2), 0)
            view.layer?.sublayerTransform = fr
            view.layer?.removeAnimation(forKey: "transform")

        }
        self.mode = mode
        self.callMode = callMode
        self.hasVideo = hasVideo
        self.hasScreencast = hasScreencast
        self.canMessage = canMessage
    }
    
    
    public override func layout() {
        super.layout()
        self.updateLayout(size: frame.size, transition: .immediate)
    }
    
    public func updateLayout(size: CGSize, transition: ContainedViewLayoutTransition) {
        
        let bsize = isStream || callMode == .voice ? NSMakeSize(220, 70) : NSMakeSize(340, 70)
        
        let bgRect = focus(bsize)

        
        self.speak.frame = focus(NSMakeSize(80, 80))
        speak.update(size: NSMakeSize(80, 80), transition: .immediate)
        
        let addition: CGFloat = mode == .normal ? 10 : 0
        
        transition.updateFrame(view: self.leftButton1, frame: leftButton1.centerFrameY(x: bgRect.minX + 16, addition: addition))
        if let leftButton2 = self.leftButton2 {
            transition.updateFrame(view: leftButton2, frame: leftButton1.centerFrameY(x: leftButton1.frame.maxX + 16, addition: addition))
        }
        transition.updateFrame(view: self.end, frame: end.centerFrameY(x: bgRect.maxX - end.frame.width - 16, addition: addition))
        if let rightButton1 = self.rightButton1 {
            transition.updateFrame(view: rightButton1, frame: leftButton1.centerFrameY(x: end.frame.minX - 16 - rightButton1.frame.width, addition: addition))
        }
        if let speakText = self.speakText {
            let speakFrame = speakText.centerFrameX(y: self.speak.frame.maxY + floorToScreenPixels(backingScaleFactor, ((frame.height - speak.frame.maxY) - speakText.frame.height) / 2 - 33))
            transition.updateFrame(view: speakText, frame: speakFrame)
        }
        
        transition.updateFrame(view: self.backgroundView, frame: focus(.init(width: 360, height: 360)))
        transition.updateFrame(view: self.fullscreenBackgroundView, frame: bgRect)

        
        if let tooltipView = tooltipView {
            
            var yOffset: CGFloat = 0
            switch callMode {
            case .video:
                if mode == .normal {
                    yOffset = 10
                }
            case .voice:
                yOffset = -20
            }
            
            var rect = CGRect(origin: CGPoint(x: fullscreenBackgroundView.frame.minX, y: fullscreenBackgroundView.frame.minY - tooltipView.frame.height - 5 + yOffset), size: tooltipView.frame.size)
            
            if tooltipView.toView == nil {
                rect.origin.x = focus(rect.size).minX
            }
            
            transition.updateFrame(view: tooltipView, frame: rect)
        }
    }
    
        
    
    fileprivate private(set) var currentState: GroupCallUIState?
    private var leftToken: UInt32?
    public func updateAudioLevel(_ audioLevel: Float) {
        self.backgroundView.audioLevel = CGFloat(audioLevel)
    }

    public func update(_ callState: GroupCallUIState, voiceSettings: VoiceCallSettings, audioLevel: Float?, animated: Bool) {

        

        let mode: Mode = callState.isFullScreen && !callState.videoActive(.main).isEmpty ? .fullscreen : .normal
        
        let hidden: Bool = true

        self.updateMode(mode, callMode: callState.mode, canMessage: callState.commentsEnabled, isStream: callState.isStream, hasVideo: callState.hasVideo, hasScreencast: callState.hasScreencast, animated: animated)

        let state = callState.state
        speak.update(with: state, isStream: callState.isStream, isFullScreen: callState.windowIsFullscreen, isMuted: callState.isMuted, animated: animated)

        if let leftToken = leftToken {
            leftButton1.removeHandler(leftToken)
        }
        leftToken = leftButton1.set(handler: { [weak self, weak callState] _ in
            if let callState = callState {
                if callState.isStream {
                    ModalMorphContextSource.withSource({ [weak self] in self?.leftButton1.modalMorphSource }) {
                        self?.arguments?.message(nil)
                    }
                } else {
                    switch callState.mode {
                    case .video:
                        if !callState.hasVideo {
                            self?.arguments?.shareSource(.video, false)
                        } else {
                            self?.arguments?.cancelShareVideo()
                        }
                    case .voice:
                        ModalMorphContextSource.withSource({ [weak self] in self?.leftButton1.modalMorphSource }) {
                            self?.arguments?.message(nil)
                        }
                    }
                }
            }
        }, for: .SingleClick)
        
        
        leftButton2?.removeAllHandlers()
        leftButton2?.set(handler: { [weak self, weak callState] _ in
            if let callState = callState, callState.hasScreencast {
                self?.arguments?.cancelShareScreencast()
            } else {
                self?.arguments?.shareSource(.screencast, false)
            }
        }, for: .SingleClick)
        
        rightButton1?.removeAllHandlers()
        rightButton1?.set(handler: { [weak self] _ in
            ModalMorphContextSource.withSource({ [weak self] in self?.rightButton1?.modalMorphSource }) {
                self?.arguments?.message(nil)
            }
        }, for: .SingleClick)

        var backgroundState: VoiceChatActionButtonBackgroundView.State
        if state.scheduleTimestamp == nil {
            switch state.networkState {
                case .connected:
                    if callState.isMuted {
                        if let _ = callState.state.muteState {
                            if callState.canUnmute {
                                backgroundState = .blob(false)
                            } else {
                                backgroundState = .disabled
                            }
                        } else {
                            backgroundState = .blob(true)
                        }
                    } else {
                        backgroundState = .blob(true)
                    }
                case .connecting:
                    backgroundState = .connecting
            }
        } else {
            backgroundState = .disabled
        }
        
        self.backgroundView.isDark = false
        self.backgroundView.update(state: backgroundState, animated: animated)

        if let audioLevel {
            self.backgroundView.audioLevel = CGFloat(audioLevel)
        }

        
        let statusText: String
        var secondary: String? = nil
        if state.scheduleTimestamp == nil {
            switch state.networkState {
            case .connected:
                if callState.isMuted {
                    if let muteState = state.muteState {
                        if muteState.canUnmute {
                            statusText = strings().voiceChatClickToUnmute
                            switch voiceSettings.mode {
                            case .always:
                                if let pushToTalk = voiceSettings.pushToTalk, !pushToTalk.isSpace {
                                    secondary = strings().voiceChatClickToUnmuteSecondaryPress(pushToTalk.string)
                                } else {
                                    secondary = strings().voiceChatClickToUnmuteSecondaryPressDefault
                                }
                            case .pushToTalk:
                                if let pushToTalk = voiceSettings.pushToTalk, !pushToTalk.isSpace {
                                    secondary = strings().voiceChatClickToUnmuteSecondaryHold(pushToTalk.string)
                                } else {
                                    secondary = strings().voiceChatClickToUnmuteSecondaryHoldDefault
                                }
                            case .none:
                                secondary = nil
                            }
                        } else {
                            if !state.raisedHand {
                                statusText = strings().voiceChatMutedByAdmin
                                secondary = strings().voiceChatClickToRaiseHand
                            } else {
                                statusText = strings().voiceChatRaisedHandTitle
                                secondary = strings().voiceChatRaisedHandText
                            }
                           
                        }
                    } else {
                        statusText = strings().voiceChatYouLive
                    }
                } else {
                    statusText = strings().voiceChatYouLive
                }
            case .connecting:
                statusText = strings().voiceChatConnecting
            }
        } else if let _ = state.scheduleTimestamp {
            if state.canManageCall {
                statusText = strings().voiceChatStartNow
            } else if state.subscribedToScheduled {
                statusText = strings().voiceChatRemoveReminder
            } else {
                statusText = strings().voiceChatSetReminder
            }
        } else {
            statusText = ""
        }
        

        let string = NSMutableAttributedString()
        string.append(.initialize(string: statusText, color: .white, font: .medium(.title)))
        if let secondary = secondary {
            string.append(.initialize(string: "\n", color: .white, font: .medium(.text)))
            string.append(.initialize(string: secondary, color: .white, font: .normal(.short)))
        }

        if string.string != self.speakText?.textLayout?.attributedString.string {
            let speakText = TextView()
            speakText.userInteractionEnabled = false
            speakText.isSelectable = false
            let layout = TextViewLayout(string, alignment: .center)
            layout.measure(width: frame.width - 60)
            speakText.update(layout)

            if hidden {
                speakText.layer?.opacity = 0
            } else {
                speakText.layer?.opacity = 1
            }
            
            let animated = animated && !hidden
            
            if let speakText = self.speakText {
                self.speakText = nil
                if animated {
                    speakText.layer?.animateAlpha(from: 1, to: 0, duration: 0.3, removeOnCompletion: false, completion: { [weak speakText] _ in
                        speakText?.removeFromSuperview()
                    })
                    speakText.layer?.animateScaleSpring(from: 1, to: 0.2, duration: 0.5)
                } else {
                    speakText.removeFromSuperview()
                }
            }


            self.speakText = speakText
            addSubview(speakText)
            speakText.centerX(y: speak.frame.maxY + floorToScreenPixels(backingScaleFactor, ((frame.height - speak.frame.maxY) - speakText.frame.height) / 2) - 33)
            if animated {
                speakText.layer?.animateAlpha(from: 0, to: 1, duration: 0.3)
                speakText.layer?.animateScaleSpring(from: 0.2, to: 1, duration: 0.5)
            }
        }
        
        if self.currentState?.controlsTooltip != callState.controlsTooltip {
            
            if let tooltip = callState.controlsTooltip {
                let current: GroupCallControlsTooltipView
                var presented = false
                if let view = self.tooltipView {
                    current = view
                } else {
                    current = GroupCallControlsTooltipView(frame: .zero)
                    self.tooltipView = current
                    self.addSubview(current)
                    presented = true
                    
                    current.set(handler: { [weak self] _ in
                        self?.arguments?.dismissTooltip(tooltip)
                    }, for: .SingleClick)
                }
                let toView: NSView?
                switch tooltip.type {
                case .camera:
                    toView = self.leftButton1
                case .micro:
                    toView = nil
                }
                current.set(text: tooltip.text, maxWidth: 340, to: toView)
                
                if presented {
                    if animated {
                        current.layer?.animateAlpha(from: 0, to: 1, duration: 0.2)
                    }
                    
                    var yOffset: CGFloat = 0
                    switch callMode {
                    case .video:
                        if mode == .normal {
                            yOffset = 10
                        }
                    case .voice:
                        yOffset = -20
                    }
                    
                    var point = CGPoint(x: fullscreenBackgroundView.frame.minX, y: fullscreenBackgroundView.frame.minY - current.frame.height - 5 + yOffset)
                        
                    if current.toView == nil {
                        point.x = focus(current.frame.size).minX
                    }
                    current.setFrameOrigin(point)
                }
                
            } else {
                if let current = self.tooltipView {
                    self.tooltipView = nil
                    
                    if animated {
                        current.layer?.animateAlpha(from: 1, to: 0, duration: 0.2, removeOnCompletion: false, completion: { [weak current] _ in
                            current?.removeFromSuperview()
                        })
                    } else {
                        current.removeFromSuperview()
                    }
                }
            }
            
        }

        self.currentState = callState
        
        let transition: ContainedViewLayoutTransition = !animated ? .immediate : .animated(duration: 0.2, curve: .spring)
        
        updateLayout(size: frame.size, transition: transition)
    }
    
    public override var mouseDownCanMoveWindow: Bool {
        return true
    }


   
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
}
