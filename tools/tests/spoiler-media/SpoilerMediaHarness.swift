import Cocoa
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import TelegramTheme
import TelegramContext

private var spoilerEvidence: SpoilerEvidence?
private final class SpoilerEvidenceButton: NSButton {
    var invoke: (() -> Void)?
    @objc func run() { invoke?() }
}
private final class SpoilerEvidence {
    let context: any AccountContextProtocol
    var closeObserver: NSObjectProtocol?
    let window: Window
    let status: NSTextField
    var tiles: [(ChatInteractiveContentView, TelegramMediaImage, Message)] = []
    var revealed = false
    init(source: ChatInteraction) {
        context = source.interactionContext
        window = Window(contentRect: NSMakeRect(0, 0, 820, 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Media spoiler — isolated preview components"
        let host = View(frame: NSMakeRect(0, 0, 820, 420))
        host.backgroundColor = theme.colors.chatBackground
        window.contentView = host
        status = NSTextField(labelWithString: "Hidden local checkerboard photos · no chat contents")
        status.frame = NSMakeRect(20, 15, 780, 25)
        status.textColor = theme.colors.text
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] notification in
            self?.windowWillClose(notification)
        }
        host.addSubview(status)
        let button = SpoilerEvidenceButton(frame: NSMakeRect(20, 48, 250, 30))
        button.title = "Reveal test previews"
        button.bezelStyle = .rounded
        button.target = button
        button.action = #selector(SpoilerEvidenceButton.run)
        button.invoke = { [weak self] in self?.reveal() }
        host.addSubview(button)
        for i in 0..<3 {
            let resource = LocalFileMediaResource(fileId: Int64.random(in: 1...Int64.max))
            let thumb = LocalFileMediaResource(fileId: Int64.random(in: 1...Int64.max))
            context.account.postbox.mediaBox.storeResourceData(resource.id, data: Self.checker(size: 256))
            context.account.postbox.mediaBox.storeResourceData(thumb.id, data: Self.checker(size: 32))
            let image = TelegramMediaImage(imageId: MediaId(namespace: 0, id: resource.fileId), representations: [TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: 32, height: 32), resource: thumb, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false), TelegramMediaImageRepresentation(dimensions: PixelDimensions(width: 256, height: 256), resource: resource, progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false)], immediateThumbnailData: nil, reference: nil, partialReference: nil, flags: [])
            let peer = source.peer!
            let message = Message(stableId: UInt32(10+i), stableVersion: 0, id: MessageId(peerId: peer.id, namespace: Namespaces.Message.Cloud, id: Int32(10+i)), globallyUniqueId: nil, groupingKey: 1, groupInfo: nil, threadId: nil, timestamp: 1782388800, flags: [.Incoming], tags: [], globalTags: [], localTags: [], customTags: [], forwardInfo: nil, author: peer, text: "", attributes: [], media: [image], peers: SimpleDictionary([peer.id: peer]), associatedMessages: .init(), associatedMessageIds: [], associatedMedia: [:], associatedThreadInfo: nil, associatedStories: [:])
            let view = ChatInteractiveContentView(frame: NSMakeRect(20+CGFloat(i)*265, 110, 250, 250))
            host.addSubview(view)
            tiles.append((view, image, message))
            update(view, image, message, revealed: false)
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    deinit {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
    }
    func windowWillClose(_ notification: Notification) {
        if spoilerEvidence === self {
            spoilerEvidence = nil
        }
    }
    static func checker(size: Int) -> Data {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: size*4, bitsPerPixel: 32)!
        let square = max(1, size/16)
        let bytes = rep.bitmapData!
        for y in 0..<size {
            for x in 0..<size {
                let value: UInt8 = (x/square+y/square)%2 == 0 ? 0 : 255
                let offset = (y*size+x)*4
                bytes[offset] = value
                bytes[offset+1] = value
                bytes[offset+2] = value
                bytes[offset+3] = 255
            }
        }
        return rep.representation(using: .png, properties: [:])!
    }
    func update(_ view: ChatInteractiveContentView, _ image: TelegramMediaImage, _ message: Message, revealed: Bool) {
        let parameters = ChatMediaLayoutParameters(presentation: .Empty, media: image, automaticDownload: false, isRevealed: revealed)
        parameters.forceSpoiler = true
        view.update(with: image, size: NSMakeSize(250, 250), context: context, parent: message, table: nil, parameters: parameters, animated: false, approximateSynchronousValue: true)
    }
    func reveal() {
        guard !revealed else { return }
        revealed = true
        for (view, image, message) in tiles { update(view, image, message, revealed: true) }
        DispatchQueue.main.asyncAfter(deadline: .now()+1) { [weak self] in self?.report() }
    }
    func report() {
        var checks: [[String: Any]] = []
        for (i, tile) in tiles.enumerated() {
            let (image, hidden) = tile.0.codexSpoilerProbe()
            var values: [CGFloat] = []
            if let image {
                let rep = NSBitmapImageRep(cgImage: image)
                for y in 0..<16 {
                    for x in 0..<16 {
                        if let color = rep.colorAt(x: (2*x+1)*rep.pixelsWide/32, y: (2*y+1)*rep.pixelsHigh/32)?.usingColorSpace(.deviceRGB) { values.append(color.redComponent) }
                    }
                }
            }
            let mean = values.reduce(0,+)/CGFloat(max(1,values.count))
            let variance = values.map { ($0-mean)*($0-mean) }.reduce(0,+)/CGFloat(max(1,values.count))
            checks.append(["name": "tile \(i+1) revealed without ink", "pass": !hidden])
            checks.append(["name": "tile \(i+1) sharp after reveal", "pass": variance > 0.1, "pixelVariance": variance])
        }
        let passed = checks.filter { $0["pass"] as? Bool == true }.count
        status.stringValue = "\(passed)/\(checks.count) checks passed · Revealed preview components"
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("spoiler-media.json")
        if let data = try? JSONSerialization.data(withJSONObject: checks, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: file, options: .atomic) }
    }
}
func codexInstallSpoilerEvidence(source: ChatInteraction, parent: NSView) {
    guard source.mode == .history else { return }
    let button = SpoilerEvidenceButton(frame: NSMakeRect(20, 130, 260, 30))
    button.title = "Media spoiler validation"
    button.bezelStyle = .rounded
    button.target = button
    button.action = #selector(SpoilerEvidenceButton.run)
    button.invoke = { [weak source] in
        guard let source else { return }
        spoilerEvidence?.window.close()
        spoilerEvidence = SpoilerEvidence(source: source)
    }
    parent.addSubview(button)
}
