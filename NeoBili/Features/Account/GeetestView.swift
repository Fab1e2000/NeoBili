#if canImport(NeoBiliDomain)
import NeoBiliDomain
#endif
import SwiftUI
import WebKit

/// GT3 bind mode must wait for onReady before asking the SDK to show its challenge.
/// https://docs.geetest.com/captcha/apirefer/api/web
struct GeetestView: View {
    struct Result: Equatable {
        let challenge: String
        let validate: String
        let seccode: String
    }
    enum LoadState: Equatable { case loading, ready, failed }

    let gt: String
    let challenge: String
    /// A user close returns nil; a loading failure stays on this page for retry.
    let onFinish: (Result?) -> Void
    @Environment(\.locale) private var locale
    @State private var state: LoadState = .loading
    @State private var attempt = UUID()

    var body: some View {
        GeetestWebContent(gt: gt, challenge: challenge,
            language: locale.language.languageCode?.identifier == "en" ? "en" : "zh-cn",
            onState: { state = $0 }, onFinish: onFinish)
            .id(attempt)
            .allowsHitTesting(state == .ready)
            .background(Color(uiColor: .systemBackground))
            .overlay {
                switch state {
                case .loading:
                    ProgressView("正在加载安全验证")
                        .accessibilityIdentifier("captcha.loading")
                case .ready:
                    EmptyView()
                case .failed:
                    ContentUnavailableView {
                        Label("安全验证加载失败", systemImage: "exclamationmark.bubble")
                    } description: {
                        Text("请检查网络连接后重试。")
                    } actions: {
                        Button("重新加载") { state = .loading; attempt = UUID() }
                            .accessibilityIdentifier("captcha.retry")
                    }
                    .background(Color(uiColor: .systemBackground))
                }
            }
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let onFinish: (Result?) -> Void
        private let onState: (LoadState) -> Void
        private var finished = false
        private var failed = false
        private var loadingTimeout: Task<Void, Never>?

        init(onState: @escaping (LoadState) -> Void = { _ in }, onFinish: @escaping (Result?) -> Void) {
            self.onState = onState
            self.onFinish = onFinish
        }

        func makeWebView() -> WKWebView {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            configuration.userContentController.add(self, name: "geetest")
            let web = WKWebView(frame: .zero, configuration: configuration)
            web.navigationDelegate = self
            web.isOpaque = false
            web.backgroundColor = .systemBackground
            web.scrollView.backgroundColor = .systemBackground
            return web
        }

        func beginLoading(timeout: Duration = .seconds(35)) {
            loadingTimeout?.cancel()
            loadingTimeout = Task { [weak self] in
                do { try await Task.sleep(for: timeout) }
                catch { return }
                self?.fail()
            }
        }

        func cancel() { finished = true; loadingTimeout?.cancel(); loadingTimeout = nil }

        func finish(_ result: Result?) {
            guard !finished, !failed else { return }
            finished = true
            loadingTimeout?.cancel(); loadingTimeout = nil
            onFinish(result)
        }

        func fail() {
            guard !finished, !failed else { return }
            failed = true
            loadingTimeout?.cancel(); loadingTimeout = nil
            onState(.failed)
        }

        func receive(_ payload: [String: String]) {
            guard !finished, !failed else { return }
            switch payload["type"] {
            case "ready":
                loadingTimeout?.cancel(); loadingTimeout = nil
                onState(.ready)
            case "success":
                guard let challenge = payload["challenge"], !challenge.isEmpty,
                      let validate = payload["validate"], !validate.isEmpty,
                      let seccode = payload["seccode"], !seccode.isEmpty else { fail(); return }
                finish(Result(challenge: challenge, validate: validate, seccode: seccode))
            case "close": finish(nil)
            case "error": fail()
            default: fail()
            }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "geetest", message.frameInfo.isMainFrame else { return }
            guard let payload = message.body as? [String: String] else { fail(); return }
            receive(payload)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if !error.isCancellation { fail() }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if !error.isCancellation { fail() }
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { fail() }
    }

    static func html(gt: String, challenge: String, language: String = "zh-cn") -> String {
        // JSON encoding also protects quotes/newlines in server-supplied challenge values.
        let settings: [String: Any] = ["gt": gt, "challenge": challenge, "product": "bind", "https": true,
            "offline": false, "new_captcha": true, "width": "300px", "lang": language, "timeout": 30_000]
        let data = try! JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])
        let config = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "<", with: "\\u003c")
        // Regression runs use an injected local SDK fixture, never the public CAPTCHA service.
        let sdk = RuntimePolicy.isRegression ? "" : """
        <script src="https://static.geetest.com/static/js/gt.0.5.0.js" onerror="window.neobiliCaptchaFailure()"></script>
        """
        return """
        <!DOCTYPE html>
        <html><head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>html, body { margin: 0; min-height: 100%; background: transparent; }</style>
        </head><body>
        <script>
        (() => {
          let complete = false;
          const post = payload => window.webkit.messageHandlers.geetest.postMessage(payload);
          const fail = () => { if (!complete) { complete = true; post({type: 'error'}); } };
          window.neobiliCaptchaFailure = fail;
          window.addEventListener('error', fail);
          window.addEventListener('load', () => {
            if (complete) return;
            try {
              if (typeof initGeetest !== 'function') { fail(); return; }
              initGeetest(\(config), captcha => {
                try {
                  captcha.onSuccess(() => {
                    if (complete) return;
                    const result = captcha.getValidate();
                    if (!result || !result.geetest_challenge || !result.geetest_validate || !result.geetest_seccode) {
                      fail(); return;
                    }
                    complete = true;
                    post({type: 'success', challenge: result.geetest_challenge,
                          validate: result.geetest_validate, seccode: result.geetest_seccode});
                  });
                  captcha.onClose(() => {
                    if (!complete) { complete = true; post({type: 'close'}); }
                  });
                  captcha.onError(fail);
                  let ready = false;
                  captcha.onReady(() => {
                    if (complete || ready) return;
                    ready = true;
                    post({type: 'ready'});
                    try { captcha.verify(); } catch (_) { fail(); }
                  });
                } catch (_) { fail(); }
              });
            } catch (_) { fail(); }
          }, {once: true});
        })();
        </script>
        \(sdk)
        </body></html>
        """
    }
}

private struct GeetestWebContent: UIViewRepresentable {
    let gt: String
    let challenge: String
    let language: String
    let onState: (GeetestView.LoadState) -> Void
    let onFinish: (GeetestView.Result?) -> Void

    func makeCoordinator() -> GeetestView.Coordinator {
        GeetestView.Coordinator(onState: onState, onFinish: onFinish)
    }
    func makeUIView(context: Context) -> WKWebView {
        let web = context.coordinator.makeWebView()
        context.coordinator.beginLoading()
        web.loadHTMLString(GeetestView.html(gt: gt, challenge: challenge, language: language),
                           baseURL: URL(string: "https://passport.bilibili.com")!)
        return web
    }
    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: GeetestView.Coordinator) {
        coordinator.cancel()
        view.stopLoading()
        view.navigationDelegate = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: "geetest")
    }
}
