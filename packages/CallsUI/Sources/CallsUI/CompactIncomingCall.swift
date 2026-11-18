import Cocoa
import TGUIKit
import SwiftSignalKit
import TelegramCore
import TelegramCallsCore
import TelegramVoip
import AvatarUI
import Localization
import TelegramUtils
import CallVideoLayer

private final class IncomingCallPanel: NSPanel {
    override var canBecomeKey: Bool { return true }
    override var canBecomeMain: Bool { return false }
}

private final class IncomingCallContent: NSView {
    override var isFlipped: Bool { return true }
}

private final class IncomingCallButtonCell: NSButtonCell {
    var imageHorizontalOffset: CGFloat = 0

    override func imageRect(forBounds rect: NSRect) -> NSRect {
        return super.imageRect(forBounds: rect).offsetBy(dx: imageHorizontalOffset, dy: 0)
    }
}

private final class IncomingCallButton: NSButton {
    var handler: (() -> Void)?

    init(symbol: String, label: String, frame: NSRect) {
        super.init(frame: frame)
        cell = IncomingCallButtonCell()
        imagePosition = .imageOnly
        isBordered = false
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        contentTintColor = .white
        toolTip = label
        setAccessibilityLabel(label)
        target = self
        action = #selector(invoke)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func invoke() { handler?() }
}

final class CompactIncomingCall: NSObject, NSTextFieldDelegate {
    private let session: PCallSession
    private let panel: IncomingCallPanel
    private let content: IncomingCallContent
    private let banner = IncomingCallContent()
    private let composer = IncomingCallContent()
    private let avatar = AvatarControl(font: .avatar(17))
    private let name = NSTextField(labelWithString: "")
    private let message = NSTextField(string: "")
    private let peerDisposable = MetaDisposable()
    private var video: CallVideoView?
    private var closed = false
    private var submitted = false
    private let answer: (Bool, Bool) -> Void
    private let decline: () -> Void
    private let reply: (String) -> Void

    init(session: PCallSession, answer: @escaping (Bool, Bool) -> Void, decline: @escaping () -> Void, reply: @escaping (String) -> Void) {
        self.session = session
        self.answer = answer
        self.decline = decline
        self.reply = reply
        let size = NSMakeSize(350, session.isVideo ? 350 * 9 / 16 : 84)
        content = IncomingCallContent(frame: NSRect(origin: .zero, size: size))
        panel = IncomingCallPanel(contentRect: content.bounds, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.contentView = content
        content.wantsLayer = true
        content.layer?.cornerRadius = 18
        content.layer?.masksToBounds = true
        let glass = NSVisualEffectView(frame: content.bounds)
        glass.material = .hudWindow
        glass.blendingMode = .behindWindow
        glass.state = .active
        content.addSubview(glass)
        if #available(macOS 26.0, *), !session.isVideo {
            let nativeGlass = NSGlassEffectView(frame: content.bounds)
            nativeGlass.cornerRadius = 18
            nativeGlass.style = .regular
            content.addSubview(nativeGlass)
        }
        banner.frame = content.bounds
        if session.isVideo {
            banner.wantsLayer = true
            let shade = CAGradientLayer()
            shade.frame = banner.bounds
            shade.colors = [NSColor.black.withAlphaComponent(0.35).cgColor, NSColor.black.withAlphaComponent(0).cgColor]
            shade.startPoint = CGPoint(x: 0.5, y: 0)
            shade.endPoint = CGPoint(x: 0.5, y: 1)
            banner.layer?.addSublayer(shade)
        }
        composer.frame = content.bounds
        composer.isHidden = true
        content.addSubview(banner)
        content.addSubview(composer)
        avatar.frame = NSMakeRect(12, 12, 60, 60)
        avatar.autoresizingMask = []
        avatar.userInteractionEnabled = false
        banner.addSubview(avatar)
        let badge = NSImageView(frame: NSMakeRect(55, 55, 19, 19))
        badge.image = NSApp.applicationIconImage
        badge.imageScaling = .scaleProportionallyUpOrDown
        banner.addSubview(badge)
        name.frame = NSMakeRect(84, 25, 164, 18)
        name.font = .systemFont(ofSize: 13, weight: .semibold)
        name.lineBreakMode = .byTruncatingTail
        banner.addSubview(name)
        let subtitle = NSTextField(labelWithString: session.isVideo ? strings().compactCallVideo : strings().compactCallAudio)
        subtitle.frame = NSMakeRect(84, 43, 164, 16)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        if session.isVideo {
            name.textColor = .white
            subtitle.textColor = .white.withAlphaComponent(0.85)
        }
        banner.addSubview(subtitle)
        addSplitControl(y: 13, color: .systemGreen, symbol: session.isVideo ? "video.fill" : "phone.fill", label: strings().compactCallAnswer, main: { [weak self] in
            guard let self else { return }
            self.finish { self.answer(self.session.isVideo, false) }
        }, menu: { [weak self] button in self?.showAnswerMenu(button) })
        addSplitControl(y: 46, color: .systemRed, symbol: "phone.down.fill", label: strings().compactCallDecline, main: { [weak self] in
            self?.finish { self?.decline() }
        }, menu: { [weak self] button in self?.showDeclineMenu(button) })
        message.frame = NSMakeRect(12, 12, 326, 27)
        message.placeholderString = strings().compactCallMessagePlaceholder
        message.delegate = self
        message.target = self
        message.action = #selector(sendReply)
        composer.addSubview(message)
        let cancel = NSButton(title: strings().compactCallCancel, target: self, action: #selector(cancelReply))
        cancel.frame = NSMakeRect(174, 45, 80, 28)
        composer.addSubview(cancel)
        let send = NSButton(title: strings().compactCallSend, target: self, action: #selector(sendReply))
        send.frame = NSMakeRect(258, 45, 80, 28)
        composer.addSubview(send)
        peerDisposable.set((session.account.postbox.loadedPeerWithId(session.peerId) |> deliverOnMainQueue).start(next: { [weak self] peer in
            guard let self else { return }
            self.avatar.setPeer(account: session.account, peer: peer)
            self.name.stringValue = peer.displayTitle
        }))
        if session.isVideo {
            if isMetalVideoRenderingAvailable, let stream = session.makeVideo(isIncoming: false) {
                installVideo(MetalVideoMakeView(videoStreamSignal: stream))
            } else if isNativeCallVideoRenderingAvailable {
                session.makeOutgoingVideoView { [weak self] video in
                    Queue.mainQueue().async {
                        guard let self, !self.closed, let video else { return }
                        let view = NativeCallVideoView(video: video)
                        view.isMirrored = true
                        self.installVideo(view)
                    }
                }
            }
        }
    }

    private func installVideo(_ view: CallVideoView) {
        guard !closed else { return }
        video = view
        view.frame = content.bounds
        view.setGravity(.resizeAspectFill)
        content.addSubview(view, positioned: .above, relativeTo: content.subviews.first)
        view.updateLayout(size: content.bounds.size, transition: .immediate)
    }

    private func addSplitControl(y: CGFloat, color: NSColor, symbol: String, label: String, main: @escaping () -> Void, menu: @escaping (NSButton) -> Void) {
        let pill = IncomingCallContent(frame: NSMakeRect(260, y, 78, 26))
        pill.wantsLayer = true
        pill.layer?.backgroundColor = color.cgColor
        pill.layer?.cornerRadius = 13
        banner.addSubview(pill)
        let action = IncomingCallButton(symbol: symbol, label: label, frame: NSMakeRect(0, 0, 49, 26))
        action.handler = main
        pill.addSubview(action)
        let arrow = IncomingCallButton(symbol: "chevron.down", label: label + "…", frame: NSMakeRect(49, 0, 29, 26))
        (action.cell as? IncomingCallButtonCell)?.imageHorizontalOffset = (arrow.frame.midX - action.frame.width) / 2
        arrow.handler = { [weak arrow] in if let arrow { menu(arrow) } }
        pill.addSubview(arrow)
    }

    private func showAnswerMenu(_ button: NSButton) {
        let menu = NSMenu()
        if session.isVideo {
            let item = NSMenuItem(title: strings().compactCallAnswerWithoutVideo, action: #selector(answerWithoutVideo), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }
        let item = NSMenuItem(title: strings().compactCallAnswerWithoutMic, action: #selector(answerWithoutMic), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        menu.popUp(positioning: nil, at: NSMakePoint(0, button.bounds.height), in: button)
    }

    private func showDeclineMenu(_ button: NSButton) {
        let menu = NSMenu()
        let item = NSMenuItem(title: strings().compactCallReplyWithMessage, action: #selector(composeReply), keyEquivalent: "")
        item.target = self
        menu.addItem(item)
        menu.popUp(positioning: nil, at: NSMakePoint(0, button.bounds.height), in: button)
    }

    @objc private func answerWithoutVideo() { finish { answer(false, false) } }
    @objc private func answerWithoutMic() { finish { answer(session.isVideo, true) } }
    @objc private func composeReply() {
        banner.isHidden = true
        composer.isHidden = false
        panel.makeKey()
        panel.makeFirstResponder(message)
    }
    @objc private func cancelReply() {
        composer.isHidden = true
        banner.isHidden = false
        panel.makeFirstResponder(nil)
        panel.resignKey()
    }
    @objc private func sendReply() {
        let text = message.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        finish { reply(text) }
    }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelReply()
            return true
        }
        return false
    }
    private func finish(_ action: () -> Void) {
        guard !closed, !submitted else { return }
        submitted = true
        action()
    }
    func show() {
        guard !closed else { return }
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? .zero
        panel.setFrameTopLeftPoint(NSMakePoint(frame.maxX - panel.frame.width - 16, frame.maxY - 16))
        panel.orderFrontRegardless()
    }
    func close() {
        guard !closed else { return }
        closed = true
        peerDisposable.dispose()
        video?.isPaused = true
        video?.removeFromSuperview()
        video = nil
        panel.orderOut(nil)
        panel.close()
    }
    deinit { peerDisposable.dispose() }
}
