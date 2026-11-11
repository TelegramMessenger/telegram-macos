import Foundation
import AppKit

protocol HTMLMultiplayerDemoSession: AnyObject {
    func start(state: HTMLBubbleState)
    func receive(_ text: String, state: HTMLBubbleState)
    func openLink(_ text: String, forceWatch: Bool)
}

@available(macOS 10.15, *)
final class HTMLMultiplayerDemoClient: HTMLMultiplayerDemoSession {
    private let name: String
    private let endpoint = URL(string: "https://voxel-clash-production.up.railway.app")!
    private let storageKey: String
    private let clientId: String
    private let session: URLSession
    private var credential: [String: String]?
    private var latest: [String: Any]?
    private weak var state: HTMLBubbleState?
    private var timer: Timer?
    private var socket: URLSessionWebSocketTask?
    private var socketGeneration = 0
    private var connected = false
    private var loading = false
    private var pendingLink: (text: String, forceWatch: Bool)?
    private var nextRetry: TimeInterval = 0
    private var attempts = 0
    private var lastHost: ObjectIdentifier?
    private var pending: [String: [String: Any]] = [:]
    private var lastPing: TimeInterval = 0
    private var latency = 0

    init(name: String, accountKey: String) {
        var commanderName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        while commanderName.utf16.count > 24 { commanderName.removeLast() }
        self.name = commanderName.isEmpty ? "Player" : commanderName
        self.storageKey = "voxelClash.v2." + accountKey
        let identityKey = "voxelClash.client." + accountKey
        let identity = UserDefaults.standard.string(forKey: identityKey) ?? UUID().uuidString
        UserDefaults.standard.set(identity, forKey: identityKey)
        self.clientId = identity
        self.credential = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String]
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        self.session = URLSession(configuration: configuration)
    }

    deinit {
        timer?.invalidate()
        socket?.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    func start(state: HTMLBubbleState) {
        self.state = state
        timer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.maintain() }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func maintain() {
        guard let state = state else { return }
        guard state.twidgetHost != nil else { return }
        let host = state.twidgetHost.map { ObjectIdentifier($0) }
        if host != lastHost {
            lastHost = host
            publish()
        }
        if credential == nil, !loading, Date().timeIntervalSince1970 >= nextRetry, state.visibility?.isHTMLBubbleVisible == true {
            load("api/games", body: ["name": name, "clientId": clientId]) { [weak self] result in self?.adopt(result) }
        } else if credential != nil, socket == nil, !loading, Date().timeIntervalSince1970 >= nextRetry {
            connect()
        }
        if connected, Date().timeIntervalSince1970 - lastPing >= 5 {
            lastPing = Date().timeIntervalSince1970
            write(["type": "ping"])
        }
    }

    func receive(_ text: String, state: HTMLBubbleState) {
        self.state = state
        guard let data = text.data(using: .utf8), var action = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any], let type = action["type"] as? String else { return }
        switch type {
        case "sync":
            maintain()
        case "create", "demo":
            load("api/games", body: ["name": name, "clientId": clientId, "title": "\(name)’s sky kingdom"]) { [weak self] result in self?.adopt(result) }
        case "join", "watch":
            if let link = action["url"] as? String { openLink(link, forceWatch: type == "watch") }
        case "joinClipboard":
            if let link = NSPasteboard.general.string(forType: .string) { openLink(link) }
            else { publish(error: "Copy an invitation or spectator link first.") }
        case "copyInvite", "copyWatch":
            let key = type == "copyInvite" ? "invite" : "watch"
            if let links = latest?["links"] as? [String: String], let link = links[key] {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link, forType: .string)
                publish(notice: type == "copyInvite" ? "Invitation copied. Share it with anyone you want to play with." : "Spectator link copied. Anyone with this link can watch live.")
            } else { publish(error: "Create or join a match first.") }
        case "openWatch":
            if let links = latest?["links"] as? [String: String], let text = links["watch"], let url = URL(string: text), url.host == endpoint.host {
                NSWorkspace.shared.open(url)
            }
        default:
            guard credential?["role"] != "spectator" else { publish(error: "You are watching this match. Spectators cannot change the game."); return }
            guard connected, socket != nil else { publish(error: "Reconnecting. Your match is saved; try again in a moment."); return }
            if type == "raid" { action["type"] = "attack" }
            if type == "reset" { action["type"] = "rematch" }
            guard pending.count < 8 else { publish(error: "Waiting for your previous actions…"); return }
            let id = UUID().uuidString
            action["requestId"] = id
            pending[id] = action
            write(action)
        }
    }

    func openLink(_ text: String, forceWatch: Bool = false) {
        if loading {
            pendingLink = (text, forceWatch)
            return
        }
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https", url.host == endpoint.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let key = components.queryItems?.first(where: { $0.name == "key" })?.value,
              key.count >= 24, key.count <= 100 else {
            publish(error: "Copy a Voxel Clash invitation or spectator link, then choose Join link.")
            return
        }
        let path = url.pathComponents.filter { $0 != "/" }
        guard path.count == 2, ["play", "watch"].contains(path[0]), path[1].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else {
            publish(error: "This game link is invalid.")
            return
        }
        let watching = path[0] == "watch" || forceWatch
        if watching {
            var query = URLComponents()
            query.queryItems = [URLQueryItem(name: "key", value: key)]
            load("api/games/\(path[1])/view" + (query.string ?? ""), body: nil) { [weak self] result in self?.adopt(result, watchKey: key) }
        } else {
            load("api/games/\(path[1])/join", body: ["name": name, "clientId": clientId, "key": key]) { [weak self] result in self?.adopt(result) }
        }
    }

    private func load(_ path: String, body: [String: Any]?, completion: @escaping ([String: Any]) -> Void) {
        guard !loading, let url = URL(string: path, relativeTo: endpoint.appendingPathComponent("/"))?.absoluteURL else { return }
        loading = true
        publish()
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
        session.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.loading = false
                defer {
                    if let link = self.pendingLink {
                        self.pendingLink = nil
                        self.openLink(link.text, forceWatch: link.forceWatch)
                    }
                }
                guard error == nil, let data = data, let result = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                    self.nextRetry = Date().timeIntervalSince1970 + 4
                    self.publish(error: "Connection interrupted. Your match is safe; please try again.")
                    return
                }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    self.publish(error: result["error"] as? String ?? "Could not join this match.")
                    return
                }
                completion(result)
            }
        }.resume()
    }

    private func adopt(_ result: [String: Any], watchKey: String? = nil) {
        guard let game = result["game"] as? [String: Any], let id = game["id"] as? String else { return }
        disconnect()
        var credential: [String: String] = ["id": id, "role": watchKey == nil ? "player" : "spectator"]
        if let token = result["token"] as? String { credential["token"] = token }
        if let watchKey = watchKey { credential["watch"] = watchKey }
        self.credential = credential
        UserDefaults.standard.set(credential, forKey: storageKey)
        latest = result
        latest?.removeValue(forKey: "token")
        publish(notice: watchKey == nil ? "Your kingdom is ready." : "You are watching live. Game controls are read only.")
        connect()
    }

    private func connect() {
        guard socket == nil, let credential = credential, let id = credential["id"] else { return }
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.scheme = "wss"
        components.path = "/live"
        components.queryItems = [URLQueryItem(name: "game", value: id)]
        if let watch = credential["watch"] { components.queryItems?.append(URLQueryItem(name: "watch", value: watch)) }
        guard let url = components.url else { return }
        var request = URLRequest(url: url)
        if let token = credential["token"] { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        let socket = session.webSocketTask(with: request)
        socket.maximumMessageSize = 256 * 1024
        self.socket = socket
        let generation = socketGeneration
        socket.resume()
        read(socket, generation: generation)
        publish()
    }

    private func read(_ task: URLSessionWebSocketTask, generation: Int) {
        task.receive { [weak self, weak task] result in
            DispatchQueue.main.async {
                guard let self = self, let task = task, generation == self.socketGeneration, self.socket === task else { return }
                switch result {
                case let .success(message):
                    let data: Data?
                    switch message {
                    case let .string(text): data = text.data(using: .utf8)
                    case let .data(bytes): data = bytes
                    @unknown default: data = nil
                    }
                    if let data = data, let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                        self.handle(value)
                    }
                    self.read(task, generation: generation)
                case .failure:
                    self.socket = nil
                    self.connected = false
                    self.attempts += 1
                    self.nextRetry = Date().timeIntervalSince1970 + min(12, pow(1.6, Double(self.attempts)))
                    self.publish(error: "Reconnecting to the live match…")
                }
            }
        }
    }

    private func handle(_ value: [String: Any]) {
        switch value["type"] as? String {
        case "state":
            let wasConnected = connected
            connected = true
            attempts = 0
            latest = value
            publish()
            if !wasConnected { for action in pending.values { write(action) } }
        case "ack":
            if let id = value["requestId"] as? String { pending.removeValue(forKey: id) }
        case "error":
            if let id = value["requestId"] as? String { pending.removeValue(forKey: id) } else { pending.removeAll() }
            publish(error: value["error"] as? String ?? "This action could not be completed.")
        case "pong":
            latency = max(1, Int((Date().timeIntervalSince1970 - lastPing) * 1000))
        default:
            break
        }
    }

    private func write(_ object: [String: Any]) {
        guard let socket = socket, let data = try? JSONSerialization.data(withJSONObject: object), let text = String(data: data, encoding: .utf8) else { return }
        let generation = socketGeneration
        socket.send(.string(text)) { [weak self] error in
            guard error != nil else { return }
            DispatchQueue.main.async {
                guard let self = self, generation == self.socketGeneration else { return }
                self.socket?.cancel(with: .goingAway, reason: nil)
                self.socket = nil
                self.connected = false
                self.nextRetry = Date().timeIntervalSince1970 + 2
                self.publish(error: "Reconnecting to the live match…")
            }
        }
    }

    private func disconnect() {
        socketGeneration += 1
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        connected = false
        pending.removeAll()
        attempts = 0
        nextRetry = 0
    }

    private func publish(error: String? = nil, notice: String? = nil) {
    }
}
