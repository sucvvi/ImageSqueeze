import Foundation
import JavaScriptCore

/// Runs the bundled SVGO (svgo.js, an IIFE build exposing `SVGO.optimize`) in JavaScriptCore.
/// Falls back to a conservative text minifier if the bundle is unavailable.
enum SVGOptimizer {
    static var isAvailable: Bool { bundleURL != nil }

    private static var bundleURL: URL? {
        Bundle.main.url(forResource: "svgo", withExtension: "js")
    }

    static func optimize(_ svg: String, precision: Int) -> (String, usedSVGO: Bool) {
        if let url = bundleURL,
           let script = try? String(contentsOf: url, encoding: .utf8),
           let ctx = JSContext() {
            var failed = false
            ctx.exceptionHandler = { _, _ in failed = true }
            ctx.evaluateScript(script)
            ctx.setObject(svg, forKeyedSubscript: "__input" as NSString)
            let result = ctx.evaluateScript("SVGO.optimize(__input, {multipass: true, floatPrecision: \(precision)}).data")
            if !failed, let out = result?.toString(), !out.isEmpty, out != "undefined" {
                return (out, true)
            }
        }
        return (fallbackMinify(svg), false)
    }

    private static func fallbackMinify(_ svg: String) -> String {
        var s = svg
        let patterns: [(String, String)] = [
            ("<!--[\\s\\S]*?-->", ""),
            ("<\\?xml[^>]*\\?>", ""),
            ("<!DOCTYPE[^>]*>", ""),
            ("<metadata[\\s\\S]*?</metadata>", ""),
            (">\\s+<", "><"),
            ("\\s{2,}", " "),
        ]
        for (p, r) in patterns {
            s = s.replacingOccurrences(of: p, with: r, options: .regularExpression)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
