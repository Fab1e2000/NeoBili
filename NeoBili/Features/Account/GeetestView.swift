import SwiftUI
import WebKit

/// 极验（GT3）滑块验证。本地拼一段 HTML 加载 gt.js，以 bind 方式弹出验证，
/// 结果（challenge/validate/seccode）通过 WKScriptMessageHandler 传回。
/// 这与 PiliPlus 的 geetest_webview 是同一套思路。
struct GeetestView: UIViewRepresentable {
    struct Result: Equatable {
        let challenge: String
        let validate: String
        let seccode: String
    }

    let gt: String
    let challenge: String
    /// 用户关闭验证时回调 nil；验证成功回调结果。
    let onFinish: (Result?) -> Void

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "geetest")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.loadHTMLString(Self.html(gt: gt, challenge: challenge), baseURL: URL(string: "https://passport.bilibili.com")!)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onFinish: (Result?) -> Void

        init(onFinish: @escaping (Result?) -> Void) {
            self.onFinish = onFinish
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "geetest",
                  let payload = message.body as? [String: String],
                  let challenge = payload["challenge"],
                  let validate = payload["validate"],
                  let seccode = payload["seccode"]
            else {
                onFinish(nil)
                return
            }
            onFinish(Result(challenge: challenge, validate: validate, seccode: seccode))
        }
    }

    private static func html(gt: String, challenge: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
        <style>
          body { margin: 0; height: 100vh; display: flex; align-items: center; justify-content: center; background: #fff; }
          #cap { width: 100%; display: flex; justify-content: center; }
        </style>
        </head>
        <body>
        <div id="cap"></div>
        <script src="https://static.geetest.com/static/js/gt.0.5.0.js"></script>
        <script>
        window.onload = function () {
          initGeetest({
            gt: '\(gt)',
            challenge: '\(challenge)',
            product: 'bind',
            offline: false,
            new_captcha: true,
            width: '300px'
          }, function (captchaObj) {
            captchaObj.onSuccess(function () {
              var r = captchaObj.getValidate();
              if (r) {
                window.webkit.messageHandlers.geetest.postMessage({
                  challenge: r.challenge,
                  validate: r.validate,
                  seccode: r.seccode
                });
              } else {
                window.webkit.messageHandlers.geetest.postMessage({});
              }
            });
            captchaObj.onClose(function () {
              window.webkit.messageHandlers.geetest.postMessage({});
            });
            captchaObj.appendTo('#cap');
            captchaObj.verify();
          });
        };
        </script>
        </body>
        </html>
        """
    }
}
