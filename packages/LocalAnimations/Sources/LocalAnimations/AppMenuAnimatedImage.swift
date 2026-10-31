import Foundation
import TGUIKit
import SwiftSignalKit
import AppKit
import TelegramCore
import Postbox
import TelegramMedia
import TelegramContext
import TelegramTheme
import InAppSettings
import TelegramUtils

public typealias MenuAnimation = LocalAnimatedSticker

extension MenuAnimation {
    public var value: (NSColor, ContextMenuItem)-> AppMenuItemImageDrawable {
        { color, item in
            return AppMenuAnimatedImage(self, color, item)
        }
    }
}

public struct MenuRemoteAnimation {
    fileprivate let context: any AccountContextProtocol
    fileprivate let file: TelegramMediaFile
    fileprivate let thumb: LocalAnimatedSticker
    fileprivate let bot: Peer
    public init(_ context: any AccountContextProtocol, file: TelegramMediaFile, bot: Peer, thumb: LocalAnimatedSticker)  {
        self.context = context
        self.file = file
        self.bot = bot
        self.thumb = thumb
    }
    
    public var value: (NSColor, ContextMenuItem)-> AppMenuItemImageDrawable {
        { color, item in
            return AppMenuAnimatedRemoteImage(self, color, item)
        }
    }
}


public final class AppMenuAnimatedImage : LottiePlayerView, AppMenuItemImageDrawable {
    
    private let sticker: LocalAnimatedSticker
    private let item: ContextMenuItem
    private let imageView = ImageView(frame: NSMakeRect(0, 0, 18, 18))
    
    
    private let disposable = MetaDisposable()
    public init(_ sticker: LocalAnimatedSticker, _ color: NSColor?, _ item: ContextMenuItem) {
        self.sticker = sticker
        self.item = item
        super.init(frame: NSMakeRect(0, 0, 18, 18))
        addSubview(imageView)
        self.imageView.isAccessibilityDecorative = true
        self.imageView.image = sticker.menuIcon(color ?? theme.colors.text)
        
        if let data = sticker.data {

            var colors:[LottieColor] = []
            if let color = color {
                colors = [.init(keyPath: "", color: color)]
            } else {
                colors = []
            }

            let animation = LottieAnimation(compressed: data, key: LottieAnimationEntryKey(key: .bundle(self.sticker.rawValue), size: frame.size), type: .lottie, cachePurpose: .none, playPolicy: .framesCount(1), maximumFps: 60, colors: colors, metalSupport: false)

            self.set(animation)

        }
        
        disposable.set(state.start(next: { [weak self] state in
            switch state {
            case .playing, .finished, .stoped:
                self?.imageView.isHidden = true
            case .initializing, .failed:
                break
            }
        }))
    }
    
    deinit {
        disposable.dispose()
    }
    
    public required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init() {
        fatalError("init() has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public func isEqual(to item: ContextMenuItem) -> Bool {
        return self.item.id == item.id
    }
    public func setColor(_ color: NSColor) {
        self.setColors([.init(keyPath: "", color: color)])
        self.imageView.image = sticker.menuIcon(color)
    }
    public func updateState(_ controlState: ControlState) {
        switch controlState {
        case .Hover:
            if !TelegramUtilsHooks.shared.isLite(.menu_animations) {
                if self.animation?.playPolicy == .framesCount(1) {
                    self.set(self.animation?.withUpdatedPolicy(.once), reset: false)
                } else if self.currentState != .playing {
                    self.playAgain()
                }
            }
            
        default:
            break
        }
    }
    
}



public final class AppMenuAnimatedRemoteImage : LottiePlayerView, AppMenuItemImageDrawable {
    
    private let sticker: MenuRemoteAnimation
    private let item: ContextMenuItem
    private let disposable = MetaDisposable()
    private let color: NSColor?
    public init(_ sticker: MenuRemoteAnimation, _ color: NSColor?, _ item: ContextMenuItem) {
        self.sticker = sticker
        self.item = item
        self.color = color
        super.init(frame: NSMakeRect(0, 0, 18, 18))
        
        if let reference = PeerReference(sticker.bot) {
            _ = fetchedMediaResource(mediaBox: sticker.context.account.postbox.mediaBox, userLocation: .peer(sticker.bot.id), userContentType: .other, reference: .media(media: .attachBot(peer: reference, media: sticker.file), resource: sticker.file.resource)).start()
        }
        
        let signal = sticker.context.account.postbox.mediaBox.resourceData(sticker.file.resource, attemptSynchronously: true) |> deliverOnMainQueue
        
        disposable.set(signal.start(next: { [weak self] data in
            if data.complete, let data = try? Data(contentsOf: URL(fileURLWithPath: data.path)) {
                self?.apply(data)
            } else {
                if let data = self?.sticker.thumb.data {
                    self?.apply(data)
                }
            }
        }))
        

    }
    
    private func apply(_ data: Data) {
        var colors:[LottieColor] = []
        if let color = color {
            colors = [.init(keyPath: "", color: color)]
        } else {
            colors = []
        }

        let animation = LottieAnimation(compressed: data, key: LottieAnimationEntryKey(key: .bundle("file_id_\(self.sticker.file.fileId)_\(data.hashValue)"), size: frame.size), type: .lottie, cachePurpose: .none, playPolicy: .framesCount(1), maximumFps: 60, colors: colors, metalSupport: false)

        self.set(animation, reset: true, saveContext: false, animated: false)
        
    }
    
    deinit {
        disposable.dispose()
    }
    
    public required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init() {
        fatalError("init() has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    public func isEqual(to item: ContextMenuItem) -> Bool {
        return self.item.id == item.id
    }
    public func setColor(_ color: NSColor) {
        self.setColors([.init(keyPath: "", color: color)])
    }
    public func updateState(_ controlState: ControlState) {
        switch controlState {
        case .Hover:
            if !TelegramUtilsHooks.shared.isLite(.menu_animations) {
                if self.animation?.playPolicy == .framesCount(1) {
                    self.set(self.animation?.withUpdatedPolicy(.once), reset: false)
                } else {
                    self.playAgain()
                }
            }
        default:
            break
        }
    }
    
}


