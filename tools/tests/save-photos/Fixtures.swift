import Cocoa
import SwiftSignalKit

struct PeerId: Hashable { let value: Int }
struct MessageId: Hashable { let id: Int32; var peerId = PeerId(value: 1) }
struct CachedPeerData { var protected = false }
protocol Media {}
struct PixelDimensions { let width: Int32; let height: Int32 }
struct Resource: Hashable {
    let id: Int
    let path: String
    var local = true
    var fails = false
}
struct TelegramMediaImageRepresentation {
    let dimensions: PixelDimensions
    let resource: Resource
}
struct TelegramMediaImage: Media { let representations: [TelegramMediaImageRepresentation] }
struct Message {
    let id: MessageId
    var timestamp: Int32 = 1
    var media: [Media]
    var protected = false
    var containsSecretMedia = false
    var adAttribute: Int?
    var index: Int32 { timestamp }
    func isCopyProtected(cachedData: CachedPeerData?) -> Bool { protected || cachedData?.protected == true }
}
struct MessageReference { init(_ message: Message) {} }
struct MediaReference { let resource: Resource }
enum ImageMediaReference {
    case message(message: MessageReference, media: TelegramMediaImage)
    var userLocation: Int { 0 }
    var userContentType: Int { 0 }
    func resourceReference(_ resource: Resource) -> MediaReference { MediaReference(resource: resource) }
}
struct ResourceData { let path: String; let complete: Bool }
final class MediaBox {
    var requests: [Int] = []
    var disposed: [Int] = []
    private var data: [Int: Promise<ResourceData>] = [:]
    func resourceData(_ resource: Resource) -> Signal<ResourceData, NoError> {
        if data[resource.id] == nil {
            let promise = Promise<ResourceData>()
            promise.set(.single(ResourceData(path: resource.path, complete: resource.local)))
            data[resource.id] = promise
        }
        return data[resource.id]!.get()
    }
    func finish(_ resource: Resource) {
        data[resource.id]?.set(.single(ResourceData(path: resource.path, complete: true)))
    }
}
enum Stats { case image }
enum FetchError { case failed }
func fetchedMediaResource(mediaBox: MediaBox, userLocation: Int, userContentType: Int, reference: MediaReference, statsCategory: Stats) -> Signal<Void, FetchError> {
    return Signal { subscriber in
        let resource = reference.resource
        mediaBox.requests.append(resource.id)
        if resource.fails { subscriber.putError(.failed) }
        return ActionDisposable { mediaBox.disposed.append(resource.id) }
    }
}
final class Transaction {
    var messages: [MessageId: Message] = [:]
    var cachedData: CachedPeerData?
    func getMessage(_ id: MessageId) -> Message? { messages[id] }
    func getPeerCachedData(peerId: PeerId) -> CachedPeerData? { cachedData }
}
final class Postbox {
    let mediaBox = MediaBox()
    let current = Transaction()
    func transaction<T>(_ f: @escaping (Transaction) -> T) -> Signal<T, NoError> { .single(f(current)) }
}
final class Account { let postbox = Postbox() }
final class Window {
    var directory: String?
    var picks = 0
    var successes = 0
    var errors = 0
    var operation: Disposable?
}
final class Context { let account = Account(); let window = Window() }
enum ChatState { case normal, selecting }
struct SelectionState { let selectedIds: Set<MessageId> }
struct Presentation {
    var state = ChatState.normal
    var selectionState: SelectionState?
}
final class ChatInteraction { let interactionContext = Context(); var presentation = Presentation() }
final class ChatRowItem {
    let chatInteraction: ChatInteraction
    let messages: [Message]
    init(_ messages: [Message], _ interaction: ChatInteraction) {
        self.messages = messages
        self.chatInteraction = interaction
    }
}
class ParentChatRowView {
    var menuDispatches = 0
    func rightMouseDown(with event: NSEvent) { menuDispatches += 1 }
}
final class ChatRowView: ParentChatRowView {
    var item: Any?
__RIGHT_MOUSE_DOWN__
}
func selectFolder(for window: Window, completion: @escaping (String) -> Void) {
    window.picks += 1
    if let directory = window.directory { completion(directory) }
}
final class FilePanelsHooks {
    static var shared: FilePanelsHooks?
    let showSavedPathSuccess: (String) -> Void
    init(_ f: @escaping (String) -> Void) { showSavedPathSuccess = f }
}
func showModalProgress<T, E>(signal: Signal<T, E>, for window: Window) -> Signal<T, E> {
    return Signal { subscriber in
        let disposable = (signal |> deliverOnMainQueue).start(next: subscriber.putNext, error: subscriber.putError, completed: subscriber.putCompletion)
        window.operation = disposable
        return disposable
    }
}
struct Strings { let unknownError = "error" }
func strings() -> Strings { Strings() }
func alert(for window: Window, info: String) { window.errors += 1 }
