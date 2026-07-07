import WebKit
import Foundation

let htmlPath = CommandLine.arguments.count > 1 
    ? CommandLine.arguments[1] 
    : NSString(string: "~/Desktop/kilo/上海20260418鸟类统计.html").expandingTildeInPath

let outPath = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "/tmp/bird_browser.png"

var done = false
var success = false

class Handler: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    let outPath: String
    
    init(webView: WKWebView, outPath: String) {
        self.webView = webView
        self.outPath = outPath
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.webView.evaluateJavaScript("document.body.scrollHeight") { result, _ in
                let height = max((result as? CGFloat) ?? 600, 600)
                self.webView.frame = NSRect(x: 0, y: 0, width: 900, height: height)
                
                let config = WKSnapshotConfiguration()
                config.rect = NSRect(x: 0, y: 0, width: 900, height: height)
                // Render at 2x for Retina-quality text
                if let screen = NSScreen.main {
                    config.snapshotWidth = NSNumber(value: 900 * Int(screen.backingScaleFactor))
                }
                
                self.webView.takeSnapshot(with: config) { image, _ in
                    if let image = image,
                       let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        let rep = NSBitmapImageRep(cgImage: cg)
                        let png = rep.representation(using: .png, properties: [:])!
                        try! png.write(to: URL(fileURLWithPath: self.outPath))
                        fputs("OK: \(Int(image.size.width))x\(Int(image.size.height))\n", stderr)
                        success = true
                    }
                    done = true
                    CFRunLoopStop(CFRunLoopGetMain())
                }
            }
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fputs("ERR: \(error.localizedDescription)\n", stderr)
        done = true
        CFRunLoopStop(CFRunLoopGetMain())
    }
}

let config = WKWebViewConfiguration()
config.preferences.setValue(true, forKey: "developerExtrasEnabled")
let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 600), configuration: config)
// Match Safari's user agent for consistent font rendering
webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"
let handler = Handler(webView: webView, outPath: outPath)
webView.navigationDelegate = handler

webView.loadFileURL(URL(fileURLWithPath: htmlPath), allowingReadAccessTo: URL(fileURLWithPath: (htmlPath as NSString).deletingLastPathComponent))

let deadline = Date().addingTimeInterval(25)
while !done && Date() < deadline {
    RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.1))
}

if !success { fputs("ERR: timeout\n", stderr); exit(1) }
