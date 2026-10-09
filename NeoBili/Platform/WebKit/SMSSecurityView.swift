import SwiftUI
import WebKit

/// 官方登录安全验证页面；仅接收指定验证接口成功返回的授权 code。
struct SMSSecurityView: UIViewRepresentable {
    @Environment(\.applicationServices) private var services
    let url: URL
    let loginContext: SMSLoginModels.Context
    let onCode: (String) -> Void
    let onError: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(loginContext: loginContext, authentication: services.authentication, onCode: onCode, onError: onError) }
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(context.coordinator, name: "smsVerification")
        configuration.userContentController.addScriptMessageHandler(context.coordinator, contentWorld: .page, name: "smsRequest")
        configuration.userContentController.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        // 仅为指定安全接口补当前 App 的签名，不实现或冒充完整官方 JS bridge。
        view.load(URLRequest(url: url))
        return view
    }
    func updateUIView(_ uiView: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading(); view.configuration.userContentController.removeScriptMessageHandler(forName: "smsVerification")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "smsRequest", contentWorld: .page)
        view.navigationDelegate = nil
    }
    final class Coordinator: NSObject, WKScriptMessageHandler, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
        let authentication: AuthenticationService
        let loginContext: SMSLoginModels.Context
        let onCode: (String) -> Void
        let onError: () -> Void
        private var finished = false
        init(loginContext: SMSLoginModels.Context, authentication: AuthenticationService = ApplicationServices.live.authentication, onCode: @escaping (String) -> Void, onError: @escaping () -> Void) {
            self.authentication = authentication
            self.loginContext = loginContext; self.onCode = onCode; self.onError = onError
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                                   replyHandler: @escaping @MainActor (Any?, String?) -> Void) {
            guard !finished, message.frameInfo.isMainFrame, message.frameInfo.securityOrigin.protocol == "https",
                  message.frameInfo.securityOrigin.host == "passport.bilibili.com",
                  let input = message.body as? [String: String], let raw = input["url"], let url = URL(string: raw),
                  let method = input["method"], let body = input["body"] else {
                replyHandler(nil, "Invalid security request"); return
            }
            do { replyHandler(try authentication.securityRequest(url: url, method: method, body: body, context: loginContext), nil) }
            catch { replyHandler(nil, "Unable to prepare security request"); onError() }
        }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard !finished, message.frameInfo.isMainFrame,
                  message.frameInfo.securityOrigin.protocol == "https",
                  message.frameInfo.securityOrigin.host == "passport.bilibili.com",
                  let code = message.body as? String, !code.isEmpty, code.count <= 4096 else { return }
            finished = true; onCode(code)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onError() }
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if (error as NSError).code != NSURLErrorCancelled { onError() }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { decisionHandler(.cancel); return }
            if url.absoluteString == "about:blank" { decisionHandler(.allow); return }
            let host = url.host ?? ""
            let allowed = url.scheme == "https" && (host == "bilibili.com" || host.hasSuffix(".bilibili.com") || host == "geetest.com" || host.hasSuffix(".geetest.com"))
            decisionHandler(allowed ? .allow : .cancel)
        }
    }
    /// 把真实验证结果交回 App 的 authorization_code 兑换；阻止网页继续用同一码兑换 Cookie。
    private static let script = #"""
    (() => {
      const accept = (raw, body) => {
        try {
          const url = new URL(raw, location.href);
          if (url.protocol !== 'https:' || url.hostname !== 'api.bilibili.com' ||
              !['/x/safecenter/answer/submit','/x/safecenter/pwd/verify'].includes(url.pathname)) return false;
          const value = typeof body === 'string' ? JSON.parse(body) : body;
          if (value.code !== 0 || !value.data || typeof value.data.code !== 'string' || !value.data.code) return false;
          window.webkit.messageHandlers.smsVerification.postMessage(value.data.code);
          return true;
        } catch (_) { return false; }
      };
      const securityPaths = ['/x/safecenter/user/info', '/x/safecenter/answer/questions', '/x/safecenter/answer/submit', '/x/safecenter/pwd/verify'];
      const isSecurity = raw => {
        try { const u = new URL(raw, location.href); return u.protocol === 'https:' && u.hostname === 'api.bilibili.com' && securityPaths.includes(u.pathname); }
        catch (_) { return false; }
      };
      const sign = (raw, method, body) => window.webkit.messageHandlers.smsRequest.postMessage({url: new URL(raw, location.href).href, method, body: body || ''});
      const originalFetch = window.fetch;
      window.fetch = async function(...args) {
        let raw = typeof args[0] === 'string' ? args[0] : args[0].url;
        if (isSecurity(raw)) {
          const request = new Request(args[0], args[1]);
          const method = request.method.toUpperCase();
          const signed = await sign(raw, method, method === 'POST' ? await request.clone().text() : '');
          const headers = new Headers(request.headers);
          if (method === 'POST') headers.set('Content-Type', 'application/x-www-form-urlencoded');
          const next = new Request(signed.url, request);
          args = [next, {headers, ...(method === 'POST' ? {body: signed.body} : {})}];
          raw = signed.url;
        }
        const response = await originalFetch.apply(this, args);
        if (isSecurity(raw) && accept(raw, await response.clone().text())) return new Promise(() => {});
        return response;
      };
      const open = XMLHttpRequest.prototype.open;
      const send = XMLHttpRequest.prototype.send;
      const setHeader = XMLHttpRequest.prototype.setRequestHeader;
      XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        this.__smsRequest = {method: String(method).toUpperCase(), url, rest, headers: []};
        this.addEventListener('readystatechange', event => {
          if (this.readyState === 4 && this.status === 200 && isSecurity(url) &&
              ['', 'text', 'json'].includes(this.responseType) && accept(url, this.responseType === 'json' ? this.response : this.responseText)) {
            event.stopImmediatePropagation();
            this.addEventListener('load', e => e.stopImmediatePropagation(), {once:true});
          }
        });
        return open.call(this, method, url, ...rest);
      };
      XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
        if (this.__smsRequest) this.__smsRequest.headers.push([name, value]);
        return setHeader.call(this, name, value);
      };
      XMLHttpRequest.prototype.send = function(body) {
        const request = this.__smsRequest;
        if (!request || !isSecurity(request.url)) return send.call(this, body);
        if (request.rest[0] === false) throw new Error('Synchronous security request unsupported');
        const responseType = this.responseType, timeout = this.timeout, credentials = this.withCredentials;
        sign(request.url, request.method, body == null ? '' : String(body)).then(signed => {
          open.call(this, request.method, signed.url, ...request.rest);
          this.responseType = responseType; this.timeout = timeout; this.withCredentials = credentials;
          for (const [name, value] of request.headers) setHeader.call(this, name, value);
          if (request.method === 'POST' && !request.headers.some(([name]) => name.toLowerCase() === 'content-type')) setHeader.call(this, 'Content-Type', 'application/x-www-form-urlencoded');
          send.call(this, request.method === 'POST' ? signed.body : null);
        }).catch(() => this.dispatchEvent(new Event('error')));
      };
    })();
    """#
}
