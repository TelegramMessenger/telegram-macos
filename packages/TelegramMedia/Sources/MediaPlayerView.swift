import Cocoa
import Foundation
import TGUIKit
import SwiftSignalKit
import AVFoundation
import TelegramMediaPlayer

private func findContentsLayer(_ sublayers: [CALayer]) -> CALayer? {
    for sublayer in sublayers {
        if let _ = sublayer.contents {
            return sublayer
        } else if let sublayers = sublayer.sublayers, !sublayers.isEmpty {
            return findContentsLayer(sublayers)
        }
    }
    return nil
}

private final class MediaPlayerViewLayer: AVSampleBufferDisplayLayer {
    override func action(forKey event: String) -> CAAction? {
        return NSNull()
    }
    deinit {
    
    }
}

private final class MediaPlayerViewDisplayView: View {
    var updateInHierarchy: ((Bool) -> Void)?
    
    
    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        self.updateInHierarchy?(superview != nil)
    }
}

private enum PollStatus: CustomStringConvertible {
    case delay(Double)
    case finished
    
    var description: String {
        switch self {
        case let .delay(value):
            return "delay(\(value))"
        case .finished:
            return "finished"
        }
    }
}

public final class MediaPlayerView: View {
    
    private struct PollState {
        var numFrames: Int
        var maxTakenTime: Double
    }
    
    
    var videoInHierarchy: Bool = false
    var updateVideoInHierarchy: ((Bool) -> Void)?
    
    private var videoNode: MediaPlayerViewDisplayView
    
    private(set) var videoLayer: AVSampleBufferDisplayLayer?
    private var videoLayerReadyForDisplayObserver: NSObjectProtocol?
    private var didNotifyVideoLayerReadyForDisplay: Bool = false
    public var hasSentFramesToDisplay: (() -> Void)?

    
    public var preventsCapture: Bool = false {
        didSet {
            if #available(macOS 10.15, *) {
                videoLayer?.preventsCapture = preventsCapture
            }
        }
    }
    
    public func setVideoLayerGravity(_ gravity: AVLayerVideoGravity) {
        videoLayer?.videoGravity = gravity
    }

    func setVideoGeometry(rotationAngle: Double, aspect: Double) {
        guard rotationAngle.isFinite, aspect.isFinite, aspect > 0.0 else {
            return
        }
        if self.currentRotationAngle != rotationAngle || self.currentAspect != aspect {
            self.currentRotationAngle = rotationAngle
            self.currentAspect = aspect
            var transform = CGAffineTransform(rotationAngle: CGFloat(rotationAngle))
            if abs(sin(rotationAngle)) > 0.1 {
                transform = transform.scaledBy(x: CGFloat(aspect), y: CGFloat(1.0 / aspect))
            }
            self.videoLayer?.setAffineTransform(transform)
        }
    }
    
    var takeFrameAndQueue: (Queue, () -> MediaTrackFrameResult)?
    var timer: SwiftSignalKit.Timer?
    var polling = false
    
    var currentRotationAngle = 0.0
    var currentAspect = 1.0
    
    public var state: (timebase: CMTimebase, requestFrames: Bool, rotationAngle: Double, aspect: Double)? {
        didSet {
            self.updateState()
        }
    }
    
    private let clipLayer = SimpleLayer()
    
    public var cornerRadius: CGFloat = .cornerRadius
    
    public var positionFlags: LayoutPositionFlags? {
        didSet {
            self.updateCorners()
        }
    }
    
    private let cornersMask = SimpleShapeLayer()
    
    public var corners: ImageCorners? {
        didSet {
            if oldValue != corners {
                self.updateCorners()
            }
        }
    }
    
    private func updateCorners() {
        guard let layer = self.layer else {
            return
        }
        if let corners = self.corners {
            layer.mask = nil
            layer.cornerRadius = 0.0
            layer.masksToBounds = false
            let radius = corners.topLeft.corner
            if corners == ImageCorners(radius: radius) {
                self.clipLayer.mask = nil
                self.clipLayer.cornerRadius = radius
                self.clipLayer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner, .layerMinXMaxYCorner]
                self.clipLayer.masksToBounds = radius > 0
            } else {
                self.clipLayer.cornerRadius = 0.0
                self.clipLayer.masksToBounds = false
                self.cornersMask.frame = self.clipLayer.bounds
                self.cornersMask.path = CGPath.bubbleCorners(size: self.clipLayer.bounds.size, corners: corners)
                self.clipLayer.mask = self.cornersMask
            }
            return
        }
        self.clipLayer.mask = nil
        guard let positionFlags = self.positionFlags else {
            layer.masksToBounds = false
            layer.cornerRadius = 0.0
            self.clipLayer.masksToBounds = false
            self.clipLayer.cornerRadius = 0.0
            return
        }
        var largeCorners: CACornerMask = []
        if positionFlags.contains(.top) && positionFlags.contains(.left) {
            largeCorners.insert(.layerMinXMinYCorner)
        }
        if positionFlags.contains(.top) && positionFlags.contains(.right) {
            largeCorners.insert(.layerMaxXMinYCorner)
        }
        if positionFlags.contains(.bottom) && positionFlags.contains(.right) {
            largeCorners.insert(.layerMaxXMaxYCorner)
        }
        if positionFlags.contains(.bottom) && positionFlags.contains(.left) {
            largeCorners.insert(.layerMinXMaxYCorner)
        }
        let smallCorners = CACornerMask([.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMaxXMaxYCorner, .layerMinXMaxYCorner]).subtracting(largeCorners)
        
        layer.mask = nil
        layer.cornerRadius = .cornerRadius * 3 + 2
        layer.maskedCorners = largeCorners
        layer.masksToBounds = !largeCorners.isEmpty
        
        self.clipLayer.cornerRadius = self.cornerRadius
        self.clipLayer.maskedCorners = smallCorners
        self.clipLayer.masksToBounds = !smallCorners.isEmpty
    }
    
    private func updateState() {
        if let (timebase, requestFrames, rotationAngle, aspect) = self.state {
            if let videoLayer = self.videoLayer {
                let timebaseChanged = videoLayer.controlTimebase !== timebase
                if timebaseChanged {
                    self.timer?.invalidate()
                    self.timer = nil
                }
                if timebaseChanged || videoLayer.status == .failed {
                    videoLayer.flush()
                    videoLayer.controlTimebase = timebase
                }
                
                self.setVideoGeometry(rotationAngle: rotationAngle, aspect: aspect)
                
                if self.videoInHierarchy {
                    if requestFrames {
                        self.startPolling()
                    }
                }
            }
        }
    }
    
    private func startPolling() {
        if !self.polling, let (pollingTimebase, _, _, _) = self.state {
            self.polling = true
            MediaPlayerView.poll(node: self, completion: { [weak self] status in
                self?.polling = false
                
                if let strongSelf = self, let (currentTimebase, requestFrames, _, _) = strongSelf.state, requestFrames {
                    strongSelf.timer?.invalidate()
                    strongSelf.timer = nil
                    if currentTimebase !== pollingTimebase {
                        if strongSelf.videoInHierarchy {
                            strongSelf.startPolling()
                        }
                        return
                    }
                    switch status {
                    case let .delay(delay):
                        strongSelf.timer = SwiftSignalKit.Timer(timeout: delay, repeat: true, completion: {
                            if let strongSelf = self, let videoLayer = strongSelf.videoLayer, let (currentTimebase, requestFrames, _, _) = strongSelf.state, currentTimebase === pollingTimebase, requestFrames, strongSelf.videoInHierarchy {
                                if videoLayer.isReadyForMoreMediaData {
                                    strongSelf.timer?.invalidate()
                                    strongSelf.timer = nil
                                    strongSelf.startPolling()
                                }
                            }
                        }, queue: Queue.mainQueue())
                        strongSelf.timer?.start()
                    case .finished:
                        break
                    }
                }
            })
        }
    }
    
    private static func pollInner(node: MediaPlayerView, layerTime: Double, state: PollState, completion: @escaping (PollStatus) -> Void) {
        assert(Queue.mainQueue().isCurrent())
        
        guard let (takeFrameQueue, takeFrame) = node.takeFrameAndQueue else {
            return
        }
        guard let videoLayer = node.videoLayer else {
            return
        }
        if !videoLayer.isReadyForMoreMediaData {
            completion(.delay(max(1.0 / 30.0, state.maxTakenTime - layerTime)))
            return
        }
        
        var state = state
        
        takeFrameQueue.async { [weak node] in
            switch takeFrame() {
            case let .restoreState(frames, atTime, soft):
                if !soft {
                    Queue.mainQueue().async {
                        guard let strongSelf = node, let videoLayer = strongSelf.videoLayer else {
                            return
                        }
                        videoLayer.flush()
                    }
                }
                for i in 0 ..< frames.count {
                    let frame = frames[i]
                    let frameTime = CMTimeGetSeconds(frame.position)
                    state.maxTakenTime = frameTime
                    let attachments = CMSampleBufferGetSampleAttachmentsArray(frame.sampleBuffer, createIfNecessary: true)! as NSArray
                    let dict = attachments[0] as! NSMutableDictionary
                    if i == 0 && !soft {
                        CMSetAttachment(frame.sampleBuffer, key: kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding as NSString, value: kCFBooleanTrue as AnyObject, attachmentMode: kCMAttachmentMode_ShouldPropagate)
                        CMSetAttachment(frame.sampleBuffer, key: kCMSampleBufferAttachmentKey_EndsPreviousSampleDuration as NSString, value: kCFBooleanTrue as AnyObject, attachmentMode: kCMAttachmentMode_ShouldPropagate)
                    }
                    if !soft {
                        if CMTimeCompare(frame.position, atTime) < 0 {
                            dict.setValue(kCFBooleanTrue as AnyObject, forKey: kCMSampleAttachmentKey_DoNotDisplay as NSString as String)
                        } else if CMTimeCompare(frame.position, atTime) == 0 {
                            dict.setValue(kCFBooleanTrue as AnyObject, forKey: kCMSampleAttachmentKey_DisplayImmediately as NSString as String)
                            dict.setValue(kCFBooleanTrue as AnyObject, forKey: kCMSampleBufferAttachmentKey_EndsPreviousSampleDuration as NSString as String)
                        }
                    }
                    Queue.mainQueue().async {
                        guard let strongSelf = node, let videoLayer = strongSelf.videoLayer else {
                            return
                        }
                        videoLayer.enqueue(frame.sampleBuffer)
                        if #available(macOS 14.4, *) {
                        } else {
                            if !strongSelf.didNotifyVideoLayerReadyForDisplay {
                                strongSelf.didNotifyVideoLayerReadyForDisplay = true
                                strongSelf.hasSentFramesToDisplay?()
                            }
                        }
                    }
                }
                Queue.mainQueue().async {
                    guard let node else {
                        return
                    }
                    MediaPlayerView.pollInner(node: node, layerTime: layerTime, state: state, completion: completion)
                }
            case let .frame(frame):
                state.numFrames += 1
                let frameTime = CMTimeGetSeconds(frame.position)
                if frame.resetDecoder {
                    Queue.mainQueue().async {
                        guard let strongSelf = node, let videoLayer = strongSelf.videoLayer else {
                            return
                        }
                        videoLayer.flush()
                    }
                }
                
                if frame.decoded && frameTime < layerTime {
                    Queue.mainQueue().async {
                        guard let node else {
                            return
                        }
                        MediaPlayerView.pollInner(node: node, layerTime: layerTime, state: state, completion: completion)
                    }
                } else {
                    state.maxTakenTime = frameTime
                    Queue.mainQueue().async {
                        guard let strongSelf = node, let videoLayer = strongSelf.videoLayer else {
                            return
                        }
                        videoLayer.enqueue(frame.sampleBuffer)
                        if !strongSelf.didNotifyVideoLayerReadyForDisplay {
                            strongSelf.didNotifyVideoLayerReadyForDisplay = true
                            strongSelf.hasSentFramesToDisplay?()
                        }
                    }
                    
                    Queue.mainQueue().async {
                        guard let node else {
                            return
                        }
                        MediaPlayerView.pollInner(node: node, layerTime: layerTime, state: state, completion: completion)
                    }
                }
            case .skipFrame:
                Queue.mainQueue().async {
                    guard let node else {
                        return
                    }
                    MediaPlayerView.pollInner(node: node, layerTime: layerTime, state: state, completion: completion)
                }
            case .noFrames:
                DispatchQueue.main.async {
                    completion(.finished)
                }
            case .finished:
                DispatchQueue.main.async {
                    completion(.finished)
                }
            }
        }
    }
    
    private static func poll(node: MediaPlayerView, completion: @escaping (PollStatus) -> Void) {
        if let _ = node.videoLayer, let (timebase, _, _, _) = node.state {
            let layerTime = CMTimeGetSeconds(CMTimebaseGetTime(timebase))
            
            let loopImpl: (PollState) -> Void = { [weak node] state in
                guard let node else {
                    return
                }
                MediaPlayerView.pollInner(node: node, layerTime: layerTime, state: state, completion: completion)
            }
            loopImpl(PollState(numFrames: 0, maxTakenTime: layerTime + 0.1))
        }
    }

    
//                                    continue loop
//                                }
//                                
//                                //print("took frame at \(frameTime) current \(layerTime)")
//                                maxTakenTime = frameTime
//                                layer.enqueue(frame.sampleBuffer)
//                                
//
//                            case .skipFrame:
//                                break
//                            case .noFrames:
//                                finised = true
//                                break loop
//                            case .finished:
//                                finised = true
//                                break loop
//                            }
//                        } else {
//                            break loop
//                        }
//                    }
//                    if finised {
//                        status = .finished
//                    } else {
//                        status = .delay(max(1.0 / 30.0, maxTakenTime - layerTime))
//                    }
//                    //print("took \(numFrames) frames, status \(status)")
//                }
//                DispatchQueue.main.async {
//                    layerRef.release()
//                    
//                    completion(status)
//                }
//            }
//        }
//    }
    
    public var transformArguments: TransformImageArguments? {
        didSet {
            self.updateLayout()
        }
    }
    
    public init(backgroundThread: Bool = false) {
        self.videoNode = MediaPlayerViewDisplayView()
        
        
        super.init()
        
        self.videoNode.updateInHierarchy = { [weak self] value in
            if let strongSelf = self {
                if strongSelf.videoInHierarchy != value {
                    strongSelf.videoInHierarchy = value
                    if value {
                        strongSelf.updateState()
                    }
                }
                strongSelf.updateVideoInHierarchy?(value)
            }
        }
        self.addSubview(self.videoNode)
        
        let videoLayer = MediaPlayerViewLayer()
        if #available(macOS 10.15, *) {
            videoLayer.preventsCapture = self.preventsCapture
        } 
        videoLayer.videoGravity = .resize
        
       // #if arch(x86_64)
//        if let sublayers = videoLayer.sublayers {
//            findContentsLayer(sublayers)?.minificationFilter = .nearest
//        }
       // #endif
        
        self.videoLayer = videoLayer
        self.layer?.addSublayer(self.clipLayer)
        self.clipLayer.addSublayer(videoLayer)
        self.updateLayout()
        
        
        if #available(macOS 14.4, *) {
//            self.videoLayerReadyForDisplayObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name.AVSampleBufferDisplayLayerReadyForDisplayDidChange, object: videoLayer, queue: .main, using: { [weak self] _ in
//                guard let self else {
//                    return
//                }
//                if !self.didNotifyVideoLayerReadyForDisplay {
//                    self.didNotifyVideoLayerReadyForDisplay = true
//                    self.hasSentFramesToDisplay?()
//                }
//            })
        }
        
        self.updateState()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    required init(frame frameRect: NSRect) {
        fatalError("init(frame:) has not been implemented")
    }
    
    deinit {
        assert(Queue.mainQueue().isCurrent())
        self.videoLayer?.removeFromSuperlayer()
        self.videoLayer?.flushAndRemoveImage()
    }
    
    public override var frame: CGRect {
        didSet {
            if !oldValue.size.equalTo(self.frame.size) {
                self.updateLayout()
            }
        }
    }
    
    public override func setFrameSize(_ newSize: NSSize) {
        let oldValue = self.frame
        super.setFrameSize(newSize)
        if !oldValue.size.equalTo(self.frame.size) {
            self.updateLayout()
        }
    }
    
    public func updateLayout() {
        let bounds = self.bounds
        self.clipLayer.frame = bounds
        if self.corners != nil {
            self.updateCorners()
        }
        
        let fittedRect: CGRect
        if let arguments = self.transformArguments {
            let drawingRect = bounds
            var fittedSize = arguments.imageSize
            if abs(fittedSize.width - bounds.size.width).isLessThanOrEqualTo(CGFloat(1.0)) {
                fittedSize.width = bounds.size.width
            }
            if abs(fittedSize.height - bounds.size.height).isLessThanOrEqualTo(CGFloat(1.0)) {
                fittedSize.height = bounds.size.height
            }
            
            fittedRect = CGRect(origin: CGPoint(x: drawingRect.origin.x + (drawingRect.size.width - fittedSize.width) / 2.0, y: drawingRect.origin.y + (drawingRect.size.height - fittedSize.height) / 2.0), size: fittedSize)
        } else {
            fittedRect = bounds
        }
        
        if let videoLayer = self.videoLayer {
            videoLayer.position = CGPoint(x: fittedRect.midX, y: fittedRect.midY)
            videoLayer.bounds = CGRect(origin: CGPoint(), size: fittedRect.size)
        }
    }
    
    public func reset() {
        self.videoLayer?.flush()
    }
}
