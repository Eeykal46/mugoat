import UIKit
import WebKit

/// The Malay City launcher: the Android app's HTML launcher (Launcher/index.html, plus Launcher/ios.js for
/// iOS) in a web view. The page calls `window.MCNative.<function>(…)` as it does on Android; the app answers
/// with `MCL.on(event, data)`. Everything the page asks for is forwarded to closures set by the owner.
final class LauncherView: UIView, WKNavigationDelegate {
    var onReady: (() -> Void)?
    var onCheck: (() -> Void)?
    var onQuery: (() -> Void)?
    var onPlay: ((_ mode: String, _ nick: String) -> Void)?
    var onSetting: ((_ key: String, _ value: String) -> Void)?
    var onNick: ((String) -> Void)?
    var onAction: ((String) -> Void)?

    private var web: WKWebView?
    private var loadingView: LoadingView?
    private var loadingMode = "story"
    private static let storageKey = "MCLauncherLocalStorage"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        makeWebView()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func makeWebView() {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let content = WKUserContentController()
        content.addUserScript(WKUserScript(source: LauncherView.bridgeScript(), injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.add(WeakMessageHandler(self), name: "mc")
        configuration.userContentController = content
        let web = WKWebView(frame: bounds, configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.scrollView.contentInsetAdjustmentBehavior = .never
        web.navigationDelegate = self
        web.translatesAutoresizingMaskIntoConstraints = false
        insertSubview(web, at: 0)
        NSLayoutConstraint.activate([
            web.leadingAnchor.constraint(equalTo: leadingAnchor), web.trailingAnchor.constraint(equalTo: trailingAnchor),
            web.topAnchor.constraint(equalTo: topAnchor), web.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        if let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "Launcher") {
            web.loadFileURL(index, allowingReadAccessTo: index.deletingLastPathComponent())
        }
        self.web = web
    }

    /// While the game loads: the web launcher is closed (its process, memory and GPU work go away) and the
    /// native loading screen (LoadingView) stays on screen. The game needs that memory to load.
    func showLoading(mode: String, tips: [String]) {
        if let web {
            web.stopLoading()
            web.configuration.userContentController.removeAllScriptMessageHandlers()
            web.configuration.userContentController.removeAllUserScripts()
            web.removeFromSuperview()
            self.web = nil
        }
        loadingMode = mode
        guard loadingView == nil else { return }
        let view = LoadingView(mode: mode, tips: tips)
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor), view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor), view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        loadingView = view
    }
    var isLoading: Bool { web == nil }
    func loadingStage(_ stage: LoadingView.Stage) { loadingView?.advance(to: stage) }
    /// The world shows: the loading screen and its image go away.
    func endLoading() {
        loadingView?.stopTimers()
        loadingView?.removeFromSuperview()
        loadingView = nil
    }

    /// `MCL.on(event, data)` in the page. `data` must be a JSON object or array.
    func send(_ event: String, _ data: [String: Any] = [:]) {
        guard JSONSerialization.isValidJSONObject(data),
              let json = try? JSONSerialization.data(withJSONObject: data),
              let text = String(data: json, encoding: .utf8),
              let name = try? JSONSerialization.data(withJSONObject: [event]),
              let nameText = String(data: name, encoding: .utf8) else { return }
        // Settings are also kept for the page's synchronous getSettings().
        let keep = event == "state" || event == "settings"
        let script = "(function(d,e){\(keep ? "if(e==='settings')window.__mcSettings=JSON.stringify(d);else if(d.settings)window.__mcSettings=JSON.stringify(d.settings);" : "")if(window.MCL)MCL.on(e,d);})(\(text),\(nameText)[0]);"
        DispatchQueue.main.async {
            guard let web = self.web else {
                if event == "playError", let text = (data["text"] ?? data["message"]) as? String {
                    if self.loadingView == nil { self.showLoading(mode: self.loadingMode, tips: []) }	// the game stopped after the world showed
                    self.loadingView?.showError(text)
                }
                return
            }
            web.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    fileprivate func received(_ body: Any) {
        guard let message = body as? [String: Any], let function = message["fn"] as? String else { return }
        let args = (message["args"] as? [Any])?.map { "\($0)" } ?? []
        switch function {
        case "ready": onReady?()
        case "check", "verifyAll": onCheck?()
        case "query": onQuery?()
        case "play":
            let raw = args.first ?? ""
            let parsed = (raw.data(using: .utf8)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            onPlay?(parsed?["mode"] as? String ?? "", parsed?["nick"] as? String ?? "")
        case "setSetting" where args.count >= 2: onSetting?(args[0], args[1])
        case "setNick": onNick?(args.first ?? "")
        case "action": onAction?(args.first ?? "")
        case "openUrl":
            if let link = args.first, let url = URL(string: link), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                UIApplication.shared.open(url)
            }
        case "copyText": UIPasteboard.general.string = args.first
        case "storage":
            // localStorage mirror: launcher choices (music, effects) survive even if WebKit clears its storage.
            if args.count >= 2 {
                var saved = UserDefaults.standard.dictionary(forKey: Self.storageKey) as? [String: String] ?? [:]
                saved[args[0]] = args[1]
                UserDefaults.standard.set(saved, forKey: Self.storageKey)
            }
        default: break   // exitApp, minimize, download, pickFolder: Android/PC only
        }
    }

    // Links inside the page open in Safari instead of replacing the launcher.
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        if let url = action.request.url, url.isFileURL || url.scheme == "about" { decisionHandler(.allow); return }
        if let url = action.request.url { UIApplication.shared.open(url) }
        decisionHandler(.cancel)
    }

    private static func bridgeScript() -> String {
        let saved = UserDefaults.standard.dictionary(forKey: storageKey) as? [String: String] ?? [:]
        let savedJSON = (try? JSONSerialization.data(withJSONObject: saved)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return """
        (function(){
          var post=function(fn,args){ try{ window.webkit.messageHandlers.mc.postMessage({fn:fn,args:args}); }catch(e){} };
          window.__mcSettings="{}";
          var N={};
          ["ready","check","query","play","setSetting","setNick","openUrl","copyText","exitApp","minimize","download","verifyAll","pickFolder","action"]
            .forEach(function(fn){ N[fn]=function(){ post(fn,[].slice.call(arguments).map(String)); return null; }; });
          N.getSettings=function(){ return window.__mcSettings; };
          window.MCNative=N;
          try{
            var saved=\(savedJSON), set=Storage.prototype.setItem;
            for(var k in saved){ try{ if(localStorage.getItem(k)===null) set.call(localStorage,k,saved[k]); }catch(e){} }
            Storage.prototype.setItem=function(k,v){ set.call(this,k,v); if(this===window.localStorage) post("storage",[String(k),String(v)]); };
          }catch(e){}
        })();
        """
    }
}

/// WKUserContentController keeps its handlers alive; this breaks the cycle with the view.
private final class WeakMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: LauncherView?
    init(_ target: LauncherView) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.received(message.body)
    }
}

/// launcher.json: the hosting's copy, else the last one downloaded, else the one in the app.
enum LauncherContent {
    /// The iOS launcher.json first, then the Android one (same hosting), so news and links show before the iOS file exists.
    static var remoteURLs: [URL] {
        ["MCLauncherJSON", "MCLauncherJSONFallback"].compactMap { key in
            (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap(URL.init(string:))
                .flatMap { ["http", "https"].contains($0.scheme?.lowercased() ?? "") ? $0 : nil }
        }
    }
    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("mc_launcher.json")
    }
    private static func parse(_ data: Data?) -> [String: Any]? {
        data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }
    static var local: [String: Any] {
        if let cached = parse(try? Data(contentsOf: cacheURL)) { return cached }
        let bundled = Bundle.main.url(forResource: "launcher", withExtension: "json", subdirectory: "Launcher")
        return parse(bundled.flatMap { try? Data(contentsOf: $0) }) ?? [:]
    }
    /// Calls back on the main queue: first with the local copy, then again if the hosting has a valid one.
    static func load(_ done: @escaping ([String: Any]) -> Void) {
        done(local)
        fetch(remoteURLs, done)
    }
    private static func fetch(_ urls: [URL], _ done: @escaping ([String: Any]) -> Void) {
        guard let url = urls.first else { return }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.setValue("MalayCity-iOS", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: request) { data, response, _ in
            guard (response as? HTTPURLResponse)?.statusCode == 200, let data, data.count < 2_000_000, let json = parse(data) else {
                fetch(Array(urls.dropFirst()), done); return
            }
            try? data.write(to: cacheURL, options: .atomic)
            DispatchQueue.main.async { done(json) }
        }.resume()
    }
    /// Optional server status: {"online":true,"players":12,"max":64}.
    static func status(from content: [String: Any], _ done: @escaping ([String: Any]) -> Void) {
        guard let ios = content["ios"] as? [String: Any], let text = ios["status"] as? String,
              let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { done([:]); return }
        URLSession.shared.dataTask(with: URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 6)) { data, response, _ in
            var result: [String: Any] = ["online": false]
            if (response as? HTTPURLResponse)?.statusCode == 200, let json = parse(data) {
                result = [:]
                if let online = json["online"] as? Bool { result["online"] = online }
                if let players = json["players"] as? Int, let max = json["max"] as? Int, players >= 0, max > 0 { result["players"] = players; result["max"] = max }
            }
            DispatchQueue.main.async { done(result) }
        }.resume()
    }
}
