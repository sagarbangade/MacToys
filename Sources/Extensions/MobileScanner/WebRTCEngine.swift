import Foundation
import WebKit
import Cocoa

@MainActor
protocol WebRTCEngineDelegate: AnyObject {
    func webRTCEngine(_ engine: WebRTCEngine, didGenerateRoomID roomID: String)
    func webRTCEngine(_ engine: WebRTCEngine, didReceivePayload payload: String)
    func webRTCEngine(_ engine: WebRTCEngine, didEncounterError error: String)
}

@MainActor
class WebRTCEngine: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView!
    weak var delegate: WebRTCEngineDelegate?
    
    override init() {
        super.init()
        setupWebView()
    }
    
    private func setupWebView() {
        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        contentController.add(self, name: "mactoys")
        config.userContentController = contentController
        
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
    }
    
    func startReceiving() {
        // We load a local HTML string that uses PeerJS to act as the receiver.
        // It connects to PeerJS, gets an ID, and sends it to Swift.
        // Then it waits for a connection and messages.
        
        let html = """
        <!DOCTYPE html>
        <html>
        <head>
            <script src="https://unpkg.com/peerjs@1.5.2/dist/peerjs.min.js"></script>
        </head>
        <body>
            <script>
                function sendMessageToSwift(type, payload) {
                    window.webkit.messageHandlers.mactoys.postMessage({ type: type, payload: payload });
                }
                
                try {
                    const peer = new Peer();
                    
                    peer.on('open', (id) => {
                        sendMessageToSwift('ready', id);
                    });
                    
                    peer.on('connection', (conn) => {
                        conn.on('data', (data) => {
                            if (data && data.type === 'scan' && data.payload) {
                                sendMessageToSwift('payload', data.payload);
                            }
                        });
                    });
                    
                    peer.on('error', (err) => {
                        sendMessageToSwift('error', err.toString());
                    });
                } catch (e) {
                    sendMessageToSwift('error', e.toString());
                }
            </script>
        </body>
        </html>
        """
        
        webView.loadHTMLString(html, baseURL: URL(string: "https://mactoys.local"))
    }
    
    func stopReceiving() {
        webView.loadHTMLString("", baseURL: nil)
    }
    
    // MARK: - WKScriptMessageHandler
    nonisolated func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String else { return }
        
        Task { @MainActor in
            switch type {
            case "ready":
                if let id = body["payload"] as? String {
                    self.delegate?.webRTCEngine(self, didGenerateRoomID: id)
                }
            case "payload":
                if let payload = body["payload"] as? String {
                    self.delegate?.webRTCEngine(self, didReceivePayload: payload)
                }
            case "error":
                if let errorMsg = body["payload"] as? String {
                    self.delegate?.webRTCEngine(self, didEncounterError: errorMsg)
                }
            default:
                break
            }
        }
    }
}
