import Foundation
import AppKit
import Postbox
import TelegramCore
import MtProtoKit
import Colors
import Strings

private func hTmeParseDuration(_ durationStr: String) -> Int {
    let pattern = "^(?:(\\d+)h)?(?:(\\d+)m)?(?:(\\d+)s)?$"

    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
        return Int(durationStr) ?? 0
    }

    let range = NSRange(durationStr.startIndex..., in: durationStr)
    if let match = regex.firstMatch(in: durationStr, options: [], range: range) {
        let hoursRange = match.range(at: 1)
        let minutesRange = match.range(at: 2)
        let secondsRange = match.range(at: 3)

        func intValue(_ nsRange: NSRange) -> Int {
            guard nsRange.location != NSNotFound,
                  let substringRange = Range(nsRange, in: durationStr) else {
                return 0
            }
            return Int(durationStr[substringRange]) ?? 0
        }

        let hours = intValue(hoursRange)
        let minutes = intValue(minutesRange)
        let seconds = intValue(secondsRange)

        return hours * 3600 + minutes * 60 + seconds
    }

    return Int(durationStr) ?? 0
}

public let telegram_me:[String] = ["telegram.me/","telegram.dog/","t.me/"]
private let actions_me:[String] = ["joinchat/","addstickers/","addemoji/","confirmphone","socks", "proxy", "setlanguage/", "bg/", "addtheme/","invoice/", "addlist/", "boost", "giftcode/", "m/", "nft/", "call/", "auction/", "newbot/", "addstyle/", "webproxy"]

let telegram_scheme:String = "tg://"
private let known_scheme:[String] = ["resolve","msg_url","join","addstickers", "addemoji","confirmphone", "socks", "proxy", "passport", "setlanguage", "bg", "privatepost", "addtheme", "settings", "invoice", "premium_offer", "restore_purchases", "login", "addlist", "boost", "giftcode", "premium_multigift", "stars_topup", "message", "nft", "call", "stars", "ton", "stargift_auction", "oauth", "newbot", "addstyle", "grams", "webproxy", sendGramsPath]

let keyURLUsername = "domain";
private let keyURLPhone = "phone";
private let keyURLPostId = "post";
private let keyURLCommentId = "comment";
private let keyURLAdmin = "admin";
private let keyURLThreadId = "thread";
private let keyURLTopicId = "topic";
private let keyURLStoryId = "story";
private let keyURLInvite = "invite";
private let keyURLUrl = "url";
private let keyURLSet = "set";
private let keyURLText = "text";
private let keyURLStart = "start";
private let keyURLVoiceChat = "voicechat";
private let keyURLVideoChat = "videochat";
private let keyURLStartattach = "startattach";
private let keyURLAttach = "attach";
private let keyURLStartGroup = "startgroup";
private let keyURLStartChannel = "startchannel";
let keyURLSecret = "secret";
private let keyURLproxy = "proxy";
private let keyURLLivestream = "livestream";
private let keyURLRef = "ref";
private let keyURLSlug = "slug";
private let keyURLChoose = "choose";
private let keyURLRotation = "rotation";
private let keyURLTimecode = "t";
private let keyURLBgColor = "bg_color";
private let keyURLHash = "hash";
private let keyURLCode = "code";
private let keyURLBalance = "balance"
private let keyURLPurpose = "purpose"

private let keyURLChannel = "channel";
private let keyURLAlbum = "album";
private let keyURLCollection = "collection";
private let keyURLDirect = "direct";
private let keyURLFree = "free";

private let keyURLAppname = "appname";
private let keyURLStartapp = "startapp";

let keyURLHost = "server";
let keyURLPort = "port";
let keyURLUser = "user";
let keyURLPass = "pass";

public let privateTelegramPeerPrefix = "_private_"

public let legacyPassportUsername = "telegrampassport"

public func normalizeURLScheme(_ url: NSString) -> NSString {
    let string = url as String
    guard let colon = string.firstIndex(of: ":") else {
        return url
    }
    let scheme = String(string[string.startIndex..<colon])
    guard let first = scheme.first, first.isLetter, scheme.count > 1 else {
        return url
    }
    guard scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "+" || $0 == "-" }) else {
        return url
    }
    let lowered = scheme.lowercased()
    guard lowered != scheme else {
        return url
    }
    return (lowered + string[colon...]) as NSString
}

public func parseInAppLink(_ url: NSString, options: InAppLinkParsingOptions = InAppLinkParsingOptions()) -> ParsedInAppLink {
    let peerId = options.peerId
    let messageId = options.messageId
    let confirm = options.confirm

    var value = normalizeURLScheme(url)
    let subdomainRange = url.range(of: ".t.me")
    if subdomainRange.location != NSNotFound, let subdomain = URL(string: url as String) {
        var subdomain = subdomain
        if subdomain.scheme == nil, let domain = URL(string: "https://" + subdomain.path) {
            subdomain = domain
        }
        if let host = subdomain.host {
            var components:[String] = []
            components = host.components(separatedBy: ".")
            var newValue: String = ""
            if components.count == 3, components[1] == "t", components[2] == "me" {
                newValue = "https://" + components[1] + "." + components[2] + "/" + components[0]
                let queryRange = url.range(of: host + "/?")
                if queryRange.location != NSNotFound {
                    let query = url.substring(with: NSMakeRange(NSMaxRange(queryRange), url.length - NSMaxRange(queryRange)))
                    newValue += "?" + query
                } else {
                    let queryRange = url.range(of: host + "/")
                    if queryRange.location != NSNotFound {
                        let query = url.substring(with: NSMakeRange(NSMaxRange(queryRange), url.length - NSMaxRange(queryRange)))
                        newValue += "/" + query
                    }
                }
            }
            if !newValue.isEmpty {
                value = newValue.nsstring
            }
        }
    }

    let external = value
    let urlString = external as String
    let url = value

    if let contact = parseContactTokenLink(urlString) {
        guard options.hasOpenInfo, options.hasContext else {
            return urlString.lowercased().hasPrefix("tg://") ? .nothing : .external(link: urlString, confirm)
        }
        return .contactToken(link: urlString, token: contact.token, freeToken: contact.freeToken)
    }

    let initialURL = URL(string: urlString)

    if let initialURL, initialURL.scheme == "file" {
        return .nothing
    }

    if let initialURL, initialURL.scheme == "ton" {
        if options.hasContext, initialURL.host == "transfer", let data = parseWalletUrl(initialURL) {
            return .tonTransfer(link: urlString, data: data)
        }
        return .nothing
    }

    if let settings = webProxySettings(from: urlString), options.hasContext, options.hasApplyProxy {
        return .socks(link: urlString, settings)
    }

    if var u = initialURL {
        let eligible = u.scheme == "tonsite"
        if options.hasContext {
            if eligible {
                return .tonsite(link: urlString)
            } else {
                if u.scheme == nil, let domain = URL(string: "https://" + u.absoluteString) {
                    u = domain
                }
                let host = urlWithoutScheme(from: u)?.host
                if let host, host.components(separatedBy: ".").last == "ton", urlString != "tg://ton" {
                    var components = URLComponents(url: u, resolvingAgainstBaseURL: false)
                    components?.scheme = "tonsite"
                    var urlString: String? = nil
                    if let url = components?.url?.absoluteString {
                        urlString = url
                    }
                    if let urlString {
                        return .tonsite(link: urlString)
                    }
                }
            }
        }
    }

    if let urlValue = initialURL, let host = urlValue.host?.lowercased(), options.hasContext {

        if options.urlAuthDomains.contains(host) {
            return .urlAuth(link: url as String)
        }
    }

    let mightBeTelegramDomain =
        value.range(of: "t.me").location != NSNotFound ||
        value.range(of: "telegram.").location != NSNotFound

    if mightBeTelegramDomain {
    for domain in telegram_me {
        let range = url.range(of: domain)
        if range.location != NSNotFound && (range.location == 0 || (range.location <= 8 && url.substring(from: range.location - 1).hasPrefix("/"))) {
            let string = external.substring(from: range.location + range.length)
            if options.hasContext, isSendGramsWebPath(string) {
                return .sendGrams(link: urlString, data: parseSendGramsLink(urlVars(with: string).0))
            }
            for action in actions_me {
                if string.hasPrefix(action) {
                    let value = String(string[string.index(string.startIndex, offsetBy: action.length) ..< string.endIndex])
                    switch action {
                    case actions_me[0]:
                        if options.hasOpenInfo, options.hasContext {
                            return .joinchat(link: urlString, value)
                        }
                    case actions_me[1]:
                        if options.hasContext {
                            return .stickerPack(link: urlString, .stickers(value), peerId: peerId)
                        }
                    case actions_me[2]:
                        if options.hasContext {
                            return .stickerPack(link: urlString, .emoji(value), peerId: peerId)
                        }
                    case actions_me[3]:
                        let (vars, _) = urlVars(with: string)
                        if options.hasContext, let phone = vars[keyURLPhone], let hash = vars[keyURLHash] {
                            return .confirmPhone(link: urlString, phone: phone, hash: hash)
                        }
                    case actions_me[4]:
                        let (vars, _) = urlVars(with: string)
                        if options.hasContext, options.hasApplyProxy, let server = vars[keyURLHost], let maybePort = vars[keyURLPort], let port = Int32(maybePort) {
                            let server = escape(with: server)
                            let username = vars[keyURLUser] != nil ? escape(with: vars[keyURLUser]!) : nil
                            let pass = vars[keyURLPass] != nil ? escape(with: vars[keyURLPass]!) : nil
                            return .socks(link: urlString, ProxyServerSettings(host: server, port: port, connection: .socks5(username: username, password: pass)))
                        }
                    case actions_me[5]:
                        let (vars, _) = urlVars(with: string)
                        if options.hasContext, options.hasApplyProxy, let server = vars[keyURLHost], let maybePort = vars[keyURLPort], let port = Int32(maybePort), let rawSecret = vars[keyURLSecret]  {
                            let server = escape(with: server)
                            if let secret = MTProxySecret.parse(rawSecret)?.serialize() {
                                return .socks(link: urlString, ProxyServerSettings(host: server, port: port, connection: .mtp(secret: secret)))
                            }
                        }
                    case actions_me[6]:
                        if options.hasContext, !value.isEmpty {
                            return .applyLocalization(link: urlString, value: value)
                        } else {

                        }
                    case actions_me[7]:
                        if !value.isEmpty {
                            var component = value
                            component = component.components(separatedBy: "?")[0]

                            if options.hasContext {
                                let (vars, _) = urlVars(with: value)
                                var rotation:Int32? = vars[keyURLRotation] != nil ? Int32(vars[keyURLRotation]!) : nil

                                if let r = rotation {
                                    let available:[Int32] = [0, 45, 90, 135, 180, 225, 270, 310]
                                    if !available.contains(r) {
                                        rotation = nil
                                    }
                                }

                                var blur: Bool = false
                                var intensity: Int32? = 80
                                var colors: [UInt32] = []

                                if let bgcolor = vars[keyURLBgColor], !bgcolor.isEmpty {
                                    var components = bgcolor.components(separatedBy: "~")
                                    if components.count == 1 {
                                        components = bgcolor.components(separatedBy: "-")
                                        if components.count > 2 {
                                            components = []
                                        }
                                    }
                                    colors = components.compactMap {
                                        return NSColor(hexString: "#\($0)")?.argb
                                    }
                                } else {
                                    var components = component.components(separatedBy: "~")
                                    if components.count == 1 {
                                        components = component.components(separatedBy: "-")
                                        if components.count > 2 {
                                            components = []
                                        }
                                    }
                                    colors = components.compactMap {
                                        return NSColor(hexString: "#\($0)")?.argb
                                    }
                                }
                                if let intensityString = vars["intensity"] {
                                    intensity = Int32(intensityString)
                                }
                                if let mode = vars["mode"] {
                                    blur = mode.contains("blur")
                                }

                                let settings: WallpaperSettings = WallpaperSettings(blur: blur, motion: false, colors: colors, intensity: intensity, rotation: rotation)

                                var slug = component
                                if let index = component.range(of: "?") {
                                    slug = String(component[component.startIndex ..< index.lowerBound])
                                }
                                if (slug.contains("~") || slug.length < 27) {
                                    slug = ""
                                }

                                var preview: WallpaperPreview = .slug(slug, settings)
                                if !colors.isEmpty, slug == "" {
                                    preview = .gradient(nil, colors.map { NSColor(argb: $0) }, settings)
                                }

                                return .wallpaper(link: urlString, preview: preview)

                            }
                        }
                        return .external(link: urlString, false)
                    case actions_me[8]:
                        let data = string.components(separatedBy: "/")
                        if data.count == 2, options.hasContext {
                            return .theme(link: urlString, name: data[1])
                        }
                        return .external(link: urlString, false)
                    case actions_me[9]:
                        let data = string.components(separatedBy: "/")
                        if data.count == 2, options.hasContext {
                            return .invoice(link: urlString, slug: value)
                        }
                        return .external(link: urlString, false)
                    case actions_me[10]:
                        let data = string.components(separatedBy: "/")
                        if data.count == 2, options.hasContext {
                            return .folder(link: urlString, slug: value)
                        }
                        return .external(link: urlString, false)
                    case actions_me[11]:
                        let data = string.components(separatedBy: "/")
                        if options.hasContext {
                            if data.count == 2 {
                                return .boost(link: urlString, username: data[1])
                            } else {
                                let (vars, _) = urlVars(with: string)
                                if let priv = vars["c"] {
                                    return .boost(link: urlString, username: "\(privateTelegramPeerPrefix)\(priv)")
                                }
                            }
                        }
                    case actions_me[12]:
                        let data = string.components(separatedBy: "/")
                        if options.hasContext, data.count == 2 {
                            return .gift(link: urlString, slug: data[1])
                        }
                    case actions_me[13]:
                        let data = string.components(separatedBy: "/")
                        if options.hasContext, data.count == 2 {
                            return .businessLink(link: urlString, slug: data[1])
                        }
                    case actions_me[14]:
                        let data = string.components(separatedBy: "/")
                        if options.hasContext, data.count == 2 {
                            return .nft(link: urlString, slug: data[1])
                        }
                    case actions_me[15]:
                        let data = string.components(separatedBy: "/")
                        if options.hasContext, data.count == 2 {
                            return .joinCall(link: urlString, slug: data[1])
                        }
                    case actions_me[16]:
                        let data = string.components(separatedBy: "/")
                        if options.hasContext, data.count == 2 {
                            return .auction(link: urlString, slug: data[1])
                        }
                    case actions_me[17]:
                        let parts = value.components(separatedBy: "?")
                        let pathParts = parts[0].components(separatedBy: "/")
                        if let manager = pathParts.first, !manager.isEmpty, options.hasContext {
                            let username = pathParts.count >= 2 ? pathParts[1] : ""
                            let (vars, _) = urlVars(with: value)
                            let title = vars["name"]?.replacingOccurrences(of: "+", with: " ")
                            return .createBot(link: urlString, managerUsername: manager, botUsername: username, title: title)
                        }
                    case actions_me[18]:
                        let data = string.components(separatedBy: "/")
                        if options.hasContext, data.count == 2 {
                            return .addStyle(link: urlString, slug: data[1])
                        }
                    default:
                        break
                    }
                }
            }

            let userAndVariables = string.components(separatedBy: "?")
            let username:String = userAndVariables[0]
            if username == keyURLproxy {
                 if userAndVariables.count == 2 {
                    let (vars, _) = urlVars(with: userAndVariables[1])
                    if options.hasContext, options.hasApplyProxy, let server = vars[keyURLHost], let maybePort = vars[keyURLPort], let port = Int32(maybePort) {
                        let server = escape(with: server)
                        return .socks(link: urlString, ProxyServerSettings(host: server, port: port, connection: .socks5(username: vars[keyURLUser], password: vars[keyURLPass])))
                    } else if options.hasContext, options.hasApplyProxy, let server = vars[keyURLHost], let maybePort = vars[keyURLPort], let port = Int32(maybePort), let rawSecret = vars[keyURLSecret] {
                        let server = escape(with: server)
                        if let secret = MTProxySecret.parse(rawSecret)?.serialize() {
                            return .socks(link: urlString, ProxyServerSettings(host: server, port: port, connection: .mtp(secret: secret)))
                        }
                    }
                }
            }

             if string.range(of: "/") == nil || string.range(of: "/?") != nil {
                let userAndVariables: [String]
                 if string.range(of: "/?") != nil {
                     userAndVariables = string.components(separatedBy: "/?")
                 } else {
                     userAndVariables = string.components(separatedBy: "?")
                 }
                let username:String = userAndVariables[0]
                var action:ParsedChatLinkAction? = nil
                if userAndVariables.count == 2 {
                    let (vars, emptyValue) = urlVars(with: userAndVariables[1])

                    if emptyValue.contains(keyURLStartChannel) || emptyValue.contains(keyURLStartGroup) {
                        if options.hasOpenInfo, options.hasContext {
                            let rights = vars[keyURLAdmin]
                            return .inviteBotToGroup(link: urlString, username: username, action: nil, rights: rights, isChannel: emptyValue.contains(keyURLStartChannel))
                        }
                    }

                    loop: for (key,value) in vars {
                        switch key {
                        case keyURLStart:
                            action = .start(parameter: escape(with: value, addPercent: false), behavior: .none)
                            break loop;
                        case keyURLStartGroup, keyURLStartChannel:
                            if options.hasOpenInfo, options.hasContext {
                                let rights = vars[keyURLAdmin]
                                return .inviteBotToGroup(link: urlString, username: username, action: .start(parameter: value, behavior: .automatic), rights: rights, isChannel: key == keyURLStartChannel)
                            }
                            break loop;
                        case keyURLVoiceChat, keyURLVideoChat, keyURLLivestream:
                            action = .joinVoiceChat(value)
                            break loop;
                        case keyURLAttach:
                            let choose = vars[keyURLChoose]?.split(separator: "+").compactMap { String($0) }
                            let attach = vars[keyURLAttach]?.split(separator: "+").compactMap { String($0) }
                            action = .attachBot(value, nil, attach ?? choose)
                            break loop
                        case keyURLText:
                            if let text = vars[keyURLText], !text.isEmpty {
                                action = .inputText(text: escape(with: text, addPercent: false), behavior: .automatic)
                            }
                        default:
                            break
                        }
                    }
                    if vars.isEmpty && [keyURLVoiceChat, keyURLVideoChat, keyURLLivestream].contains(userAndVariables[1]) {
                        action = .joinVoiceChat(nil)
                    }
                }

                 if userAndVariables.count == 2, userAndVariables[1] == keyURLStartapp {
                     action = .makeWebview(appname: "", command: nil)
                 }

                if action == nil, let messageId = messageId {
                    action = .source(messageId, nil)
                }

                if options.hasOpenInfo {
                    if username == "iv" || username.isEmpty {
                        return .external(link: urlString, username.isEmpty)
                    } else if options.hasContext {

                        if username.hasPrefix("$") {
                            return .invoice(link: urlString, slug: String(username.suffix(username.length - 1)))
                        }

                        let components = string.components(separatedBy: "?")
                        let (vars, empty) = urlVars(with: string)

                        let noPaidToken = vars[keyURLFree] ?? ""
                        let joinKeys:[String] = ["+", "%20"]
                        let phone = username.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                        if "+\(phone)" == username {
                            if !noPaidToken.isEmpty {
                                return .noPaidMessagesToken(link: urlString, username: phone, token: noPaidToken)
                            }
                            let forceProfile = empty.contains("profile")
                            return .followResolvedName(link: urlString, username: phone, postId: nil, forceProfile: forceProfile, action: action)
                        } else {
                            for joinKey in joinKeys {
                                if username.hasPrefix(joinKey), username.length > joinKey.length {
                                    return .joinchat(link: urlString, username.nsstring.substring(from: joinKey.length))
                                }
                            }
                        }

                        if let startapp = vars[keyURLStartapp] {
                            action = .makeWebview(appname: "", command: startapp)
                        } else if vars[keyURLStartattach] != nil || empty.contains(keyURLStartattach) {
                            let choose = vars[keyURLChoose]?.split(separator: "+").compactMap { String($0) }
                            let attach = vars[keyURLAttach]?.split(separator: "+").compactMap { String($0) }
                            action = .attachBot(username, vars[keyURLStartattach], choose ?? attach)
                        } else if components.contains(keyURLLivestream) {
                            action = .joinVoiceChat(nil)
                        } else if components.contains(keyURLDirect) {
                            action = .direct
                        }

                        if username.hasPrefix("$") {
                            return .invoice(link: urlString, slug: String(username.suffix(username.length - 1)))
                        }

                        let forceProfile = components.contains("profile")

                        if components.count == 2, components[1] == "boost" {
                            return .boost(link: urlString, username: username)
                        } else if let storyId = vars[keyURLStoryId]?.nsstring.intValue {
                            return .story(link: urlString, username: username, storyId: storyId, messageId: messageId)
                        } else if let topicId = vars[keyURLTopicId]?.nsstring.intValue {
                            return .topic(link: urlString, username: username, threadId: topicId, commentId: nil)
                        } else if !noPaidToken.isEmpty {
                            return .noPaidMessagesToken(link: urlString, username: username, token: noPaidToken)
                        } else {
                            return .followResolvedName(link: urlString, username: username, postId: nil, forceProfile: forceProfile, action: action)
                        }
                    }
                }
            } else if options.hasOpenInfo {
                let userAndPost = string.components(separatedBy: "/")
                if userAndPost.count >= 2 {
                    let name = userAndPost[0]
                    let forceProfile = false
                    if name == "c" {

                        if options.hasContext {
                            let postIndex = userAndPost.count - 1
                            var post = userAndPost[postIndex].isEmpty ? nil : Int32(userAndPost[postIndex])
                            var username = userAndPost[1]
                            if postIndex == 1 {
                                post = nil
                            }
                            if let range = userAndPost[postIndex].range(of: "?") {
                                if postIndex == 1 {
                                    username = String(userAndPost[1][..<range.lowerBound])
                                } else {
                                    post = Int32(userAndPost[postIndex][..<range.lowerBound])
                                }
                            }
                            let (params, action) = urlVars(with: url as String)
                            if let thread = params[keyURLThreadId]?.nsstring.intValue, let post = post {
                                return .comments(link: urlString, username: "\(privateTelegramPeerPrefix)\(username)", threadId: thread, commentId: post)
                            } else if let topic = params[keyURLTopicId]?.nsstring.intValue {
                                return .topic(link: urlString, username: "\(privateTelegramPeerPrefix)\(username)", threadId: topic, commentId: post)
                            } else if userAndPost.count == 4, let threadId = Int32(userAndPost[2]) {
                                return .topic(link: urlString, username: "\(privateTelegramPeerPrefix)\(username)", threadId: threadId, commentId: post)
                            } else {
                                if action.first == "boost" {
                                    return .boost(link: urlString, username: "\(privateTelegramPeerPrefix)\(username)")
                                } else {
                                    let forceProfile = false

                                    var action: ParsedChatLinkAction? = nil
                                    if let t = params[keyURLTimecode] {
                                        let timemark = hTmeParseDuration(t)
                                        if Int(timemark) < Int32.max {
                                            action = .openMedia(Int32(timemark))
                                        }
                                    }
                                    if let optionId = params["option"] {
                                        let padded = optionId.padding(toLength: ((optionId.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
                                        if let optionData = Data(base64Encoded: padded) {
                                            action = .pollOption(optionData)
                                        }
                                    }
                                    return .followResolvedName(link: urlString, username: "\(privateTelegramPeerPrefix)\(username)", postId: post, forceProfile: forceProfile, action: action)
                                }
                            }
                        }
                    } else if name == "s" {
                        return .external(link: urlString, false)
                    } else if name == "addtheme" {
                        if options.hasContext {
                            return .theme(link: urlString, name: userAndPost[1])
                        }
                    } else {
                        let postIndex: Int = userAndPost.count - 1
                        let postText = userAndPost[postIndex]
                        var post = postText.isEmpty ? nil : Int32(postText)
                        let storyId: Int32? = nil
                        if let range = postText.range(of: "?") {
                            post = Int32(postText[..<range.lowerBound])
                        }
                        if name.hasPrefix("iv?") {
                            return .external(link: urlString, false)
                        } else if name.hasPrefix("share?") || name == "share" {
                            let (params, _) = urlVars(with: url as String)
                            if let url = params[keyURLUrl], options.hasContext {
                                let url = url.nsstring.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
                                let text = params[keyURLText]?.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
                                if let url = url {
                                    return .shareUrl(link: urlString, url, text)

                                }
                            }
                            return .external(link: urlString, false)
                        } else if options.hasContext {
                            let (params, _) = urlVars(with: url as String)

                            var action: ParsedChatLinkAction? = nil

                            if let t = params[keyURLTimecode] {
                                let timemark = Double(hTmeParseDuration(t))
                                if Int(timemark) < Int32.max {
                                    action = .openMedia(Int32(timemark))
                                }
                            } else if (userAndPost.count == 2 && post == nil) || (userAndPost.count == 3 && params[keyURLStartapp] != nil) {
                                var appname = userAndPost[1]
                                if let range = userAndPost[1].range(of: "?") {
                                    appname = String(userAndPost[1][..<range.lowerBound])
                                }
                                if !appname.isEmpty {
                                    action = .makeWebview(appname: appname, command: params[keyURLStartapp])
                                }
                            }

                            if let t = params[keyURLTimecode], action == nil {
                                let timemark = hTmeParseDuration(t)
                                if Int(timemark) < Int32.max {
                                    action = .openMedia(Int32(timemark))
                                }
                            }

                            if let optionId = params["option"] {
                                let padded = optionId.padding(toLength: ((optionId.count + 3) / 4) * 4, withPad: "=", startingAt: 0)
                                if let optionData = Data(base64Encoded: padded) {
                                    action = .pollOption(optionData)
                                }
                            }
                            if action == nil, let messageId = messageId {
                                action = .source(messageId, nil)
                            }

                            if userAndPost.count == 3, let album = post, userAndPost[1] == "a" {
                                return .followResolvedName(link: urlString, username: name, postId: nil, forceProfile: forceProfile, action: .album(album: album, mode: .stories))
                            } else if userAndPost.count == 3, let album = post, userAndPost[1] == "c" {
                                return .followResolvedName(link: urlString, username: name, postId: nil, forceProfile: forceProfile, action: .album(album: album, mode: .gifts))
                            } else if userAndPost.count == 3, let storyId = post, userAndPost[1] == "s" {
                                return .story(link: urlString, username: name, storyId: storyId, messageId: messageId)
                            } else if let comment = params[keyURLCommentId]?.nsstring.intValue, let post = post {
                                return .comments(link: urlString, username: name, threadId: post, commentId: comment)
                            } else if let thread = params[keyURLThreadId]?.nsstring.intValue, let comment = post {
                                 return .comments(link: urlString, username: name, threadId: thread, commentId: comment)
                            } else if let topic = params[keyURLTopicId]?.nsstring.intValue {
                                return .topic(link: urlString, username: name, threadId: topic, commentId: post)
                            } else if userAndPost.count == 3, let threadId = Int32(userAndPost[1]) {
                                return .topic(link: urlString, username: name, threadId: threadId, commentId: post)
                            } else if let storyId = storyId {
                                return .story(link: urlString, username: name, storyId: storyId, messageId: messageId)
                            } else {
                                let forceProfile = userAndPost.contains("profile")

                                return .followResolvedName(link: urlString, username: name, postId: post, forceProfile: forceProfile, action: action)
                            }
                        }
                    }
                }
            }
        }
    }
    } // end if mightBeTelegramDomain

    if url.hasPrefix("@"), options.hasOpenInfo, options.hasContext {
        return .followResolvedName(link: urlString, username: url.substring(from: 1), postId: nil, forceProfile: false, action:nil)
    }

    if url.hasPrefix("/"), options.hasCommand {
        return .botCommand(url as String)
    }
    if url.hasPrefix("#") || url.hasPrefix("$"), options.hasHashtag {
        return .hashtag(url as String)
    }

    if url.hasPrefix(telegram_scheme) {
        let action = url.substring(from: telegram_scheme.length)

        let (vars, emptyVars) = urlVars(with: external as String)

        for i in 0 ..< known_scheme.count {
            let known = known_scheme[i]
            if action.hasPrefix(known) {

                switch known {
                case known_scheme[0]:
                    if let token = vars[keyURLFree], !token.isEmpty, options.hasOpenInfo, options.hasContext, let target = vars[keyURLUsername] ?? vars["username"] ?? vars[keyURLPhone] {
                        return .noPaidMessagesToken(link: urlString, username: target, token: token)
                    }
                    if let username = vars[keyURLUsername], options.hasOpenInfo {
                        let post = vars[keyURLPostId]?.nsstring.intValue
                        let comment = vars[keyURLCommentId]?.nsstring.intValue
                        let thread = vars[keyURLThreadId]?.nsstring.intValue
                        let topic = vars[keyURLTopicId]?.nsstring.intValue
                        let story = vars[keyURLStoryId]?.nsstring.intValue
                        let storyAlbum = vars[keyURLAlbum]?.nsstring.intValue
                        let giftsAlbum = vars[keyURLCollection]?.nsstring.intValue

                        var action:ParsedChatLinkAction? = nil
                        loop: for (key,value) in vars {
                            switch key {
                            case keyURLStartapp:
                                action = .makeWebview(appname: "", command: value)
                            case keyURLStart:
                                action = .start(parameter: escape(with: value, addPercent: false), behavior: .none)
                                break loop;
                            case keyURLStartGroup, keyURLStartChannel:
                                if options.hasContext {
                                    let rights = vars[keyURLAdmin]
                                    return .inviteBotToGroup(link: urlString, username: username, action: .start(parameter: value, behavior: .none), rights: rights, isChannel: key == keyURLStartChannel)
                                }
                            case keyURLVoiceChat, keyURLVideoChat, keyURLLivestream:
                                action = .joinVoiceChat(value)
                                break loop
                            case keyURLAttach:
                                let choose = vars[keyURLChoose]?.split(separator: "+").compactMap { String($0) }
                                let attach = vars[keyURLAttach]?.split(separator: "+").compactMap { String($0) }
                                action = .attachBot(value, vars[keyURLStartattach], attach ?? choose)
                                break loop
                            case keyURLAppname:
                                action = .makeWebview(appname: value, command: vars[keyURLStartapp])
                                break loop
                            case keyURLText:
                                if let text = vars[keyURLText], !text.isEmpty {
                                    action = .inputText(text: escape(with: text, addPercent: false), behavior: .automatic)
                                }
                                break loop
                            case keyURLAlbum:
                                if let storyAlbum {
                                    action = .album(album: storyAlbum, mode: .stories)
                                }
                            case keyURLCollection:
                                if let giftsAlbum {
                                    action = .album(album: giftsAlbum, mode: .gifts)
                                }
                            default:
                                break
                            }
                        }
                        if emptyVars.contains(keyURLStartChannel) || emptyVars.contains(keyURLStartGroup) {
                            if options.hasContext {
                                let rights = vars[keyURLAdmin]
                                return .inviteBotToGroup(link: urlString, username: username, action: nil, rights: rights, isChannel: emptyVars.contains(keyURLStartChannel))
                            }
                        }
                        if action == nil && emptyVars.contains(keyURLStartapp) {
                            action = .makeWebview(appname: "", command: nil)
                        } else if action == nil && (emptyVars.contains(keyURLVoiceChat) || emptyVars.contains(keyURLVideoChat) || emptyVars.contains(keyURLLivestream)) {
                            action = .joinVoiceChat(nil)
                        } else if action == nil, vars[keyURLStartattach] != nil || vars[keyURLAttach] != nil {
                            let choose = vars[keyURLChoose]?.split(separator: "+").compactMap { String($0) }
                            let attach = vars[keyURLAttach]?.split(separator: "+").compactMap { String($0) }
                            action = .attachBot(username, vars[keyURLStartattach], attach ?? choose)
                        } else if action == nil, emptyVars.contains(keyURLDirect) {
                            action = .direct
                        }
                        if username == legacyPassportUsername {
                            var legacyOptions = options
                            legacyOptions.messageId = nil
                            return parseInAppLink(external.replacingOccurrences(of: "tg://resolve", with: "tg://passport").nsstring, options: legacyOptions)
                        } else if username == "oauth", options.hasContext, let token = vars[keyURLStartapp] {
                            return .oauth(link: urlString, token: token)
                        } else if username == "addtheme", options.hasContext {
                            return .theme(link: urlString, name:"")
                        } else if options.hasContext {
                            if let comment = comment, let post = post {
                                return .comments(link: urlString, username: username, threadId: post, commentId: comment)
                            } else if let thread = thread, let comment = post {
                                return .comments(link: urlString, username: username, threadId: thread, commentId: comment)
                            } else if let topic = topic {
                                return .comments(link: urlString, username: username, threadId: topic, commentId: comment)
                            } else if let story = story {
                                return .story(link: urlString, username: username, storyId: story, messageId: messageId)
                            } else {
                                let forceProfile = emptyVars.contains("profile")
                                return .followResolvedName(link: urlString, username: username, postId: post, forceProfile: forceProfile, action: action)
                            }
                        }
                    } else if let phone = vars[keyURLPhone], options.hasOpenInfo, options.hasContext {
                        let forceProfile = emptyVars.contains("profile")
                        return .followResolvedName(link: urlString, username: phone, postId: nil, forceProfile: forceProfile, action: nil)
                    }
                case known_scheme[1]:
                    if let url = vars[keyURLUrl] {
                        let url = url.nsstring.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
                        let text = vars[keyURLText]?.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
                        if let url = url, options.hasContext {
                            let applied = url
                            return .shareUrl(link: urlString, applied, text)

                        }
                    }
                case known_scheme[2]:
                    if let invite = vars[keyURLInvite], options.hasOpenInfo, options.hasContext {
                        return .joinchat(link: urlString, invite)
                    }
                case known_scheme[3]:
                    if let set = vars[keyURLSet], options.hasContext {
                        return .stickerPack(link: urlString, .stickers(set), peerId:nil)
                    }
                case known_scheme[4]:
                    if let set = vars[keyURLSet], options.hasContext {
                        return .stickerPack(link: urlString, .emoji(set), peerId:nil)
                    }
                case known_scheme[5]:
                    if options.hasContext, let phone = vars[keyURLPhone], let hash = vars[keyURLHash] {
                        return .confirmPhone(link: urlString, phone: phone, hash: hash)
                    }
                case known_scheme[6]:
                    if options.hasContext, options.hasApplyProxy, let server = vars[keyURLHost], let maybePort = vars[keyURLPort], let port = Int32(maybePort) {
                        let server = escape(with: server)
                        return .socks(link: urlString, ProxyServerSettings(host: server, port: port, connection: .socks5(username: vars[keyURLUser], password: vars[keyURLPass])))
                    }
                case known_scheme[7]:
                    if options.hasContext, options.hasApplyProxy, let server = vars[keyURLHost], let maybePort = vars[keyURLPort], let port = Int32(maybePort), let rawSecret = vars[keyURLSecret] {
                        let server = escape(with: server)
                        if let secret = MTProxySecret.parse(rawSecret)?.serialize() {
                            return .socks(link: urlString, ProxyServerSettings(host: server, port: port, connection: .mtp(secret: secret)))
                        }
                    }
                case known_scheme[8]:
                    if let scope = vars["scope"], let publicKey = vars["public_key"], let rawBotId = vars["bot_id"], let botId = Int64(rawBotId), options.hasContext {

                        let scope = escape(with: scope, addPercent: false)

                        let isModern: Bool = scope.hasPrefix("{")

                        let nonceString = (isModern ? vars["nonce"] : vars["payload"]) ?? ""

                        let nonce = escape(with: nonceString, addPercent: false).data(using: .utf8) ?? Data()

                        let callbackUrl = vars["callback_url"] != nil ? escape(with: vars["callback_url"]!, addPercent: false) : nil
                        return .requestSecureId(link: urlString, value: inAppSecureIdRequest(peerId: PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(botId)), scope: scope, callback: callbackUrl, publicKey: escape(with: publicKey, addPercent: false), nonce: nonce, isModern: isModern))
                    }
                case known_scheme[9]:
                    if options.hasContext, let value = vars["lang"] {
                        return .applyLocalization(link: urlString, value: value)
                    }
                case known_scheme[10]:
                    if options.hasContext, let value = vars[keyURLSlug] {

                        var blur: Bool = false
                        var intensity: Int32? = 80
                        var colors: [UInt32] = []

                        var rotation:Int32? = vars["rotation"] != nil ? Int32(vars["rotation"]!) : nil

                        if let r = rotation {
                            let available:[Int32] = [0, 45, 90, 135, 180, 225, 270, 310]
                            if !available.contains(r) {
                                rotation = nil
                            }
                        }

                        if let bgcolor = vars["bg_color"], !bgcolor.isEmpty {
                            var components = bgcolor.components(separatedBy: "~")
                            if components.count == 1 {
                                components = bgcolor.components(separatedBy: "-")
                                if components.count > 2 {
                                    components = []
                                }
                            }
                            colors = components.compactMap {
                                return NSColor(hexString: "#\($0)")?.argb
                            }
                        }
                        if let mode = vars["mode"] {
                            blur = mode.contains("blur")
                        }
                        if let intensityString = vars["intensity"] {
                            intensity = Int32(intensityString)
                        }

                        let settings: WallpaperSettings = WallpaperSettings(blur: blur, motion: false, colors: colors, intensity: intensity, rotation: rotation)

                        return .wallpaper(link: urlString, preview: .slug(value, settings))
                    }
                    if options.hasContext, let value = vars["color"] {
                        return .wallpaper(link: urlString, preview: .slug(value, WallpaperSettings()))
                    } else if options.hasContext {

                        var rotation:Int32? = vars["rotation"] != nil ? Int32(vars["rotation"]!) : nil

                        if let r = rotation {
                            let available:[Int32] = [0, 45, 90, 135, 180, 225, 270, 310]
                            if !available.contains(r) {
                                rotation = nil
                            }
                        }

                        var components = vars["bg_color"]?.components(separatedBy: "~") ?? []
                        if components.count == 1 {
                            components = vars["bg_color"]?.components(separatedBy: "-") ?? []
                            if components.count > 2 {
                                components = []
                            }
                        }
                        let colors = components.compactMap {
                            return NSColor(hexString: "#\($0)")
                        }
                        if !colors.isEmpty  {
                            return .wallpaper(link: urlString, preview: .gradient(0, colors, WallpaperSettings(rotation: rotation)))
                        }
                    }
                case known_scheme[11]:
                    if let username = vars["channel"], options.hasOpenInfo {
                        let post = vars[keyURLPostId]?.nsstring.intValue
                        let threadId = vars[keyURLThreadId]?.nsstring.intValue
                        let topicId = vars[keyURLTopicId]?.nsstring.intValue

                        if let threadId = threadId, let post = post, options.hasContext {
                            return .comments(link: urlString, username: "\(privateTelegramPeerPrefix)\(username)", threadId: threadId, commentId: post)
                        } else if let topicId = topicId, options.hasContext {
                            return .topic(link: urlString, username: "\(privateTelegramPeerPrefix)\(username)", threadId: topicId, commentId: post)
                        } else if options.hasContext {
                            let forceProfile = emptyVars.contains("profile")
                            return .followResolvedName(link: urlString, username: "\(privateTelegramPeerPrefix)\(username)", postId: post, forceProfile: forceProfile, action:nil)
                        }
                    }
                case known_scheme[12]:
                    if options.hasContext, let value = vars[keyURLSlug] {
                        return .theme(link: urlString, name: value)
                    }
                case known_scheme[13]:
                    if options.hasContext {
                        if let range = action.range(of: known_scheme[13] + "/") {
                            let section = String(action[range.upperBound...])
                            if let section = InAppSettingsSection(rawValue: section) {
                                return .settings(link: urlString, section: section)
                            }
                        } else if action == known_scheme[13] {
                            return .settings(link: urlString, section: .general)
                        }
                    }
                case known_scheme[14]:
                    if options.hasContext, let value = vars[keyURLSlug] {
                        return .invoice(link: urlString, slug: value)
                    }
                case known_scheme[15]:
                    if options.hasContext {
                        return .premiumOffer(link: urlString, ref: vars[keyURLRef])
                    }
                case known_scheme[16]:
                    if options.hasContext {
                        return .restorePurchase(link: urlString)
                    }
                case known_scheme[17]:
                    if let code = vars[keyURLCode] {
                        return .loginCode(link: urlString, code: code)
                    }
                case known_scheme[18]:
                    if let slug = vars[keyURLSlug], options.hasContext {
                        return .folder(link: urlString, slug: slug)
                    }
                case known_scheme[19]:
                    if let channelId = vars[keyURLChannel], options.hasContext {
                        return .boost(link: urlString, username: "\(privateTelegramPeerPrefix)\(channelId)")
                    } else if let username = vars[keyURLUsername], options.hasContext {
                        return .boost(link: urlString, username: username)
                    }
                case known_scheme[20]:
                    if let slug = vars[keyURLSlug], options.hasContext {
                        return .gift(link: urlString, slug: slug)
                    }
                case known_scheme[21]:
                    if options.hasContext {
                        return .multigift(link: urlString)
                    }
                case known_scheme[22]:
                    if options.hasContext, let amount = vars[keyURLBalance].flatMap ({ Int64($0) }), let purpose = vars[keyURLPurpose] {
                        return .starsTopup(link: urlString, amount: amount, purpose: purpose)
                    }
                case known_scheme[23]:
                    if options.hasContext, let slug = vars[keyURLSlug] {
                        return .businessLink(link: urlString, slug: slug)
                    }
                case known_scheme[24]:
                    if options.hasContext, let slug = vars[keyURLSlug] {
                        return .nft(link: urlString, slug: slug)
                    }
                case known_scheme[25]:
                    if options.hasContext, let slug = vars[keyURLSlug] {
                        return .joinCall(link: urlString, slug: slug)
                    }
                case known_scheme[26]:
                    if options.hasContext {
                        return .starsInfo(link: urlString, isTon: false)
                    }
                case known_scheme[27]:
                    if options.hasContext {
                        return .starsInfo(link: urlString, isTon: true)
                    }
                case known_scheme[28]:
                    if options.hasContext, let slug = vars[keyURLSlug] {
                        return .auction(link: urlString, slug: slug)
                    }
                case known_scheme[29]:
                    if options.hasContext, let token = vars["token"] {
                        return .oauth(link: urlString, token: token)
                    }
                case known_scheme[30]:
                    if options.hasContext, let manager = vars["manager"], !manager.isEmpty {
                        let username = vars["username"] ?? ""
                        let title = vars["name"]
                        return .createBot(link: urlString, managerUsername: manager, botUsername: username, title: title)
                    }
                case known_scheme[31]:
                    if options.hasContext, let slug = vars[keyURLSlug] {
                        return .addStyle(link: urlString, slug: slug)
                    }
                case known_scheme[32]:
                    if options.hasContext {
                        return .starsInfo(link: urlString, isTon: true)
                    }
                case known_scheme[34]:
                    if options.hasContext, isSendGramsSchemeAction(action) {
                        return .sendGrams(link: urlString, data: parseSendGramsLink(vars))
                    }
                default:
                    break
                }

                return .nothing

            }
        }
        if options.hasContext {
            var path = url.substring(from: telegram_scheme.length)
            let qLocation = path.nsstring.range(of: "?").location
            path = path.nsstring.substring(to: qLocation != NSNotFound ? qLocation : path.length)
            return .unsupportedScheme(link: urlString, path: path)
        }

    }

    return .external(link: urlString as String, confirm)
}
