import Cocoa
import Foundation
import TGUIKit
import TelegramContext
import TelegramUtils
import SwiftSignalKit
import TelegramCore
import Postbox


private final class AvatarClipImageEntry {
    let source: CGImage
    let clip: CGImage
    init(source: CGImage, clip: CGImage) {
        self.source = source
        self.clip = clip
    }
}

private let avatarClipImageCache: NSCache<NSString, AvatarClipImageEntry> = {
    let cache = NSCache<NSString, AvatarClipImageEntry>()
    cache.countLimit = 200
    return cache
}()

private func avatarClipImage(_ image: CGImage, frameSize: NSSize, inset: CGFloat) -> CGImage {
    let scale = System.backingScale
    let key = "\(UInt(bitPattern: ObjectIdentifier(image).hashValue))_\(frameSize.width)_\(frameSize.height)_\(inset)_\(scale)" as NSString
    if let entry = avatarClipImageCache.object(forKey: key), entry.source === image {
        return entry.clip
    }
    let clip = generateImage(frameSize, scale: scale, rotatedContext: { size, context in
        context.clear(CGRect(origin: CGPoint(), size: size))
        context.translateBy(x: size.width / 2.0, y: size.height / 2.0)
        context.scaleBy(x: 1.0, y: -1.0)
        context.translateBy(x: -size.width / 2.0, y: -size.height / 2.0)
        context.draw(image, in: CGRect(origin: CGPoint(), size: size))
        context.translateBy(x: size.width / 2.0, y: size.height / 2.0)
        context.scaleBy(x: 1.0, y: -1.0)
        context.translateBy(x: -size.width / 2.0, y: -size.height / 2.0)

        context.setBlendMode(.copy)
        context.setFillColor(NSColor.clear.cgColor)
        context.fillEllipse(in: CGRect(origin: CGPoint(), size: size).insetBy(dx: -(inset / 2), dy: -(inset / 2)).offsetBy(dx: -(frameSize.width - inset), dy: 0.0))
    })!
    avatarClipImageCache.setObject(AvatarClipImageEntry(source: image, clip: clip), forKey: key)
    return clip
}

public final class AvatarContentView: View {
    private let unclippedView: ImageView
    private let clippedView: ImageView

    private var disposable: Disposable?
    private var audioLevelView: VoiceBlobView?

    public let peerId: PeerId

    private var scaleAnimator: DisplayLinkAnimator?
    private let inset: CGFloat
    public convenience init(context: (any AccountContextProtocol), peer: Peer, message: Message?, synchronousLoad: Bool, size: NSSize, inset: CGFloat = 3) {
        self.init(account: context.account, peer: peer, message: message, synchronousLoad: synchronousLoad, size: size, inset: inset)
    }
    
    public init(account: Account, peer: Peer, message: Message?, synchronousLoad: Bool, size: NSSize, inset: CGFloat = 3) {
        self.peerId = peer.id
        self.inset = inset
        self.unclippedView = ImageView()
        self.clippedView = ImageView()
        self.unclippedView.isAccessibilityDecorative = true
        self.clippedView.isAccessibilityDecorative = true
        
        super.init(frame: CGRect(origin: .zero, size: size))
        
        self.addSubview(self.unclippedView)
        self.addSubview(self.clippedView)

        let frameSize = self.frame.size

        
        let signal: Signal<(CGImage, CGImage)?, NoError> = peerAvatarImage(account: account, photo: .peer(peer, peer.smallProfileImage, peer.namePeerColor, TelegramUtilsHooks.shared.peerLetters(peer), nil, nil), displayDimensions: size, scale: System.backingScale, font: .avatar(size.height / 3 + 3), genCap: true, synchronousLoad: synchronousLoad) |> runOn(.mainQueue()) |> map { image in
            if let image = image.0 {
                let clipImage = avatarClipImage(image, frameSize: frameSize, inset: inset)
                return (image, clipImage)
            }
            return nil
        }
        
        let disposable = (signal
            |> deliverOnMainQueue).start(next: { [weak self] values in
                guard let strongSelf = self else {
                    return
                }
                if let values = values {
                    let image = values.0
                    let clipImage = values.1
                    strongSelf.updateImage(image: image, clipImage: clipImage)
                }
            })
        self.disposable = disposable
    }

    public func updateAudioLevel(color: NSColor, value: Float) {
        if self.audioLevelView == nil, value > 0.0 {
            let blobFrame = NSMakeRect(0, 0, frame.width + 8, frame.height + 8)

            let audioLevelView = VoiceBlobView(
                frame: blobFrame,
                maxLevel: 0.3,
                smallBlobRange: (0, 0),
                mediumBlobRange: (0.7, 0.8),
                bigBlobRange: (0.8, 0.9)
            )


            audioLevelView.setColor(color, animated: true)
            self.audioLevelView = audioLevelView
            self.addSubview(audioLevelView, positioned: .below, relativeTo: self.subviews.first)
            audioLevelView.center()
      }

      let level = min(1.0, max(0.0, CGFloat(value)))
      if let audioLevelView = self.audioLevelView {
          audioLevelView.updateLevel(CGFloat(value) * 2.0)

          let avatarScale: CGFloat
          if value > 0.0 {
              audioLevelView.startAnimating()
              avatarScale = 1.03 + level * 0.07
          } else {
              audioLevelView.stopAnimating()
              avatarScale = 1.0
          }
            let t = clippedView.layer!.transform
            let scale = sqrt((t.m11 * t.m11) + (t.m12 * t.m12) + (t.m13 * t.m13))
            if self.scaleAnimator == nil, abs(scale - avatarScale) < 0.0001 {
                return
            }
            self.scaleAnimator = DisplayLinkAnimator(duration: 0.1, from: scale, to: avatarScale, update: { [weak self] value in
                guard let `self` = self else {
                    return
                }

                let rect = self.clippedView.bounds

                var fr = CATransform3DIdentity
                fr = CATransform3DTranslate(fr, rect.width / 2, rect.width / 2, 0)
                fr = CATransform3DScale(fr, value, value, 1)
                fr = CATransform3DTranslate(fr, -(rect.width / 2), -(rect.height / 2), 0)

                self.clippedView.layer?.transform = fr
                self.unclippedView.layer?.transform = fr

            }, completion: { [weak self] in
                self?.scaleAnimator = nil
            })
      }
  }

    
    public required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    private func updateImage(image: CGImage, clipImage: CGImage) {
        self.unclippedView.image = image
        _ = NSMakeSize(frame.height, frame.height)
        self.clippedView.image = clipImage
    }
    
    deinit {
        self.disposable?.dispose()
    }
    
    public func updateLayout(size: CGSize, isClipped: Bool, animated: Bool) {
        self.unclippedView.frame = CGRect(origin: focus(size).origin, size: size)
        self.clippedView.frame = CGRect(origin: focus(size).origin, size: size)
        self.unclippedView.change(opacity: isClipped ? 0.0 : 1.0, animated: animated)
        self.clippedView.change(opacity: isClipped ? 1.0 : 0.0, animated: animated)
    }
}




public final class AvatarContentLayer: SimpleLayer {
    private let unclippedView: SimpleLayer = SimpleLayer()
    private let clippedView: SimpleLayer = SimpleLayer()

    private var disposable: Disposable?
    private var audioLevelView: VoiceBlobView?

    public let peerId: PeerId

    private var scaleAnimator: DisplayLinkAnimator?
    private let inset: CGFloat
    public init(context: (any AccountContextProtocol), peer: Peer, message: Message?, synchronousLoad: Bool, size: NSSize, inset: CGFloat = 3) {
        self.peerId = peer.id
        self.inset = inset
        
        super.init()
        self.frame = CGRect(origin: .zero, size: size)
        
        self.addSublayer(self.unclippedView)
        self.addSublayer(self.clippedView)

        let frameSize = self.frame.size

        
        let signal: Signal<(CGImage, CGImage)?, NoError> = peerAvatarImage(account: context.account, photo: .peer(peer, peer.smallProfileImage, peer.namePeerColor, TelegramUtilsHooks.shared.peerLetters(peer), nil, nil), displayDimensions: size, scale: System.backingScale, font: .avatar(size.height / 3 + 3), genCap: true, synchronousLoad: synchronousLoad) |> map { image in
            if let image = image.0 {
                let clipImage = avatarClipImage(image, frameSize: frameSize, inset: inset)
                return (image, clipImage)
            }
            return nil
        }
        
        let disposable = (signal
            |> deliverOnMainQueue).start(next: { [weak self] values in
                guard let strongSelf = self else {
                    return
                }
                if let values = values {
                    let image = values.0
                    let clipImage = values.1
                    strongSelf.updateImage(image: image, clipImage: clipImage)
                }
            })
        self.disposable = disposable
    }


    
    public required init?(coder decoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func updateImage(image: CGImage, clipImage: CGImage) {
        self.unclippedView.contents = image
        self.clippedView.contents = clipImage
    }
    
    deinit {
        self.disposable?.dispose()
    }
    
    public var animatesClipChanges: Bool = false

    public func updateLayout(size: CGSize, isClipped: Bool, animated: Bool) {
        self.unclippedView.frame = CGRect(origin: self.frame.focus(size).origin, size: size)
        self.clippedView.frame = CGRect(origin: self.frame.focus(size).origin, size: size)
        let unclipped: Float = isClipped ? 0.0 : 1.0
        let clipped: Float = isClipped ? 1.0 : 0.0
        if animatesClipChanges {
            for (layer, target) in [(self.unclippedView, unclipped), (self.clippedView, clipped)] where layer.opacity != target {
                if animated {
                    var from = CGFloat(layer.opacity)
                    if let presentation = layer.presentation(), layer.animation(forKey: "opacity") != nil {
                        from = CGFloat(presentation.opacity)
                    }
                    layer.animateAlpha(from: from, to: CGFloat(target), duration: 0.2, timingFunction: .easeOut)
                } else {
                    layer.removeAnimation(forKey: "opacity")
                }
            }
        }
        self.unclippedView.opacity = unclipped
        self.clippedView.opacity = clipped
    }
}


public struct Avatar : Comparable, Identifiable {
    public static func < (lhs: Avatar, rhs: Avatar) -> Bool {
        return lhs.index < rhs.index
    }

    public var stableId: PeerId {
        return peer.id
    }

    public static func == (lhs: Avatar, rhs: Avatar) -> Bool {
        if lhs.index != rhs.index {
            return false
        }
        if !lhs.peer.isEqual(rhs.peer) {
            return false
        }
        return true
    }

    public let peer: Peer
    public let index: Int
    public init(peer: Peer, index: Int) {
        self.peer = peer
        self.index = index
    }
}
