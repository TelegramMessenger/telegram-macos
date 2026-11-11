import Cocoa
import Foundation
import WebKit
import TGUIKit
import TelegramCore
import Postbox
import SwiftSignalKit
import Localization
import ColorPalette
import TelegramTheme
import TelegramContext
import TelegramUtils
import GeneralRows
import InputDataUI
import CurrencyFormat
import InAppSettings
import TelegramMediaUtils
import AlertsUI
import AppAnalytics

private final class Arguments {
    public let context: (any AccountContextProtocol)
    public init(context: (any AccountContextProtocol)) {
        self.context = context
    }
}
public enum PaymentWebInteractionIntent {
    case addPaymentMethod((BotCheckoutPaymentWebToken) -> Void)
    case externalVerification((Bool) -> Void)
}

public final class PaymentWebInteractionController: ModalViewController, WKNavigationDelegate {
    private let url: String
    private let intent: PaymentWebInteractionIntent
    private var completed = false
    public init(context: (any AccountContextProtocol), url: String, intent: PaymentWebInteractionIntent) {
        self.url = url
        self.intent = intent
        super.init(frame: NSMakeRect(0, 0, 380, 440))
        switch intent {
        case .addPaymentMethod:
            self.analyticsScreen = AnalyticsScreen.paymentsCard
        case .externalVerification:
            self.analyticsScreen = AnalyticsScreen.paymentsVerification
        }
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        readyOnce()
    }

    public override func viewWillDisappear(_ animated: Bool) {
        completed = true
        super.viewWillDisappear(animated)
    }
    
    public override var defaultBarTitle: String {
        switch intent {
        case .addPaymentMethod:
            return strings().checkoutNewCardTitle
        case .externalVerification:
            return strings().checkoutWebConfirmationTitle
        }
    }
    
    public override var canBecomeResponder: Bool {
        return true
    }
    
    public override func firstResponder() -> NSResponder? {
        return self.view
    }

    public override var modalHeader: (left: ModalHeaderData?, center: ModalHeaderData?, right: ModalHeaderData?)? {
        return (left: ModalHeaderData(image: theme.icons.modalClose, handler: { [weak self] in
            self?.close()
        }), center: ModalHeaderData(title: defaultBarTitle), right: nil)
    }
    public override var dynamicSize: Bool {
        return true
    }
    
    public override func measure(size: NSSize) {
        self.modal?.resize(with:NSMakeSize(min(max(380, size.width - 20), 380), min(size.height - 70, 500)), animated: false)
    }
    
    public override func initializer() -> NSView {
        let webView: WKWebView
        switch intent {
            case .addPaymentMethod:
            let js = "var TelegramWebviewProxyProto = function() {}; " +
                "TelegramWebviewProxyProto.prototype.postEvent = function(eventName, eventData) { " +
                "window.webkit.messageHandlers.performAction.postMessage({'eventName': eventName, 'eventData': eventData}); " +
                "}; " +
            "var TelegramWebviewProxy = new TelegramWebviewProxyProto();"
               
            let configuration = WKWebViewConfiguration()
            
            if FastSettings.debugWebApp {
                configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
            }
            
            let userController = WKUserContentController()
               
            let userScript = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            userController.addUserScript(userScript)
               
            userController.add(WeakScriptMessageHandler { [weak self] message in
                if let strongSelf = self {
                    strongSelf.handleScriptMessage(message)
                }
            }, name: "performAction")
               
            configuration.userContentController = userController
            webView = WKWebView(frame: CGRect(), configuration: configuration)
            webView.allowsLinkPreview = false

        case .externalVerification:
            
            let configuration = WKWebViewConfiguration()
            if FastSettings.debugWebApp {
                configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
            }
            webView = WKWebView(frame: CGRect(), configuration: configuration)
            webView.allowsLinkPreview = false
            webView.navigationDelegate = self
        }
        if let parsedUrl = URL(string: url) {
           webView.load(URLRequest(url: parsedUrl))
        }
        webView.frame = NSMakeRect(0, 0, _frameRect.width, _frameRect.height - 50)
        return webView
    }
    
    private func handleScriptMessage(_ message: WKScriptMessage) {
        guard !completed else { return }
        let presentation = (analyticsContext ?? Analytics.shared.unresolvedContext()).beginPresentation()
        defer { presentation.end() }
        guard let body = message.body as? [String: Any] else {
            return
        }
        guard message.frameInfo.isMainFrame else {
            return
        }
       
        guard let eventName = body["eventName"] as? String else {
            return
        }
       
        if eventName == "payment_form_submit" {
            guard let eventString = body["eventData"] as? String else {
                return
            }
           
            guard let eventData = eventString.data(using: .utf8) else {
                return
            }
           
            guard let dict = (try? JSONSerialization.jsonObject(with: eventData, options: [])) as? [String: Any] else {
                return
            }
           
            guard let title = dict["title"] as? String else {
                return
            }
           
            guard let credentials = dict["credentials"] else {
                return
            }
           
            guard let credentialsData = try? JSONSerialization.data(withJSONObject: credentials, options: []) else {
                return
            }
           
            guard let credentialsString = String(data: credentialsData, encoding: .utf8) else {
                return
            }
           
            if case let .addPaymentMethod(completion) = self.intent {
                completed = true
                completion(BotCheckoutPaymentWebToken(title: title, data: credentialsString, saveOnServer: false))
                close()
            }
        }
    }
       
   public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let presentation = (analyticsContext ?? Analytics.shared.unresolvedContext()).beginPresentation()
        defer { presentation.end() }
        guard !completed else {
            decisionHandler(.cancel)
            return
        }
        if case let .externalVerification(completion) = self.intent, let host =  navigationAction.request.url?.host {
            if host == PaymentsHooks.shared.meUrlHost() || host == "telegram.me" {
                completed = true
                decisionHandler(.cancel)
                completion(true)
                close()
            } else {
                decisionHandler(.allow)
            }
        } else {
            decisionHandler(.allow)
        }
    }

}
