// Google Play screenshots: puts a headline over each raw emulator capture.
//
//   build/store-shots/raw/<lang>/<screen>.png → build/store-shots/framed/<lang>/<n>-<screen>.png
//
// 1440×2560 (9:16, what Play wants for phone screenshots). The headlines are the
// welcome carousel's own lines (ox_login i18n, welcome_slide_N_line_1/2), so the
// store and the first screen of the app say the same thing in every language;
// lines the app does not have live in captions.json next to this file. Line 1
// is white, line 2 the carousel's lavender, on the login page's dark background.
//
// Usage (repo root): swift tool/store_shots/frame_shots.swift [lang…]
import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let raw = repo.appendingPathComponent("build/store-shots/raw")
let framed = repo.appendingPathComponent("build/store-shots/framed")
let appStrings = repo.appendingPathComponent("packages/business_modules/ox_login/assets/locale")
let extraStrings = repo.appendingPathComponent("tool/store_shots/captions.json")

/// App i18n file names (i18n_<lang>.json), most installs first.
let allLangs = ["en", "fa", "ar", "fr", "es", "ru", "zh", "pt"]
/// Shot order and the key of each headline; "welcome_slide_N" reads lines 1 and 2.
let order: [(screen: String, key: String)] = [
    ("chat", "welcome_slide_1"), ("circle", "welcome_slide_3"), ("call", "calls"),
    ("signup", "welcome_slide_2"), ("server", "welcome_slide_4"),
]
let width = 1440, height = 2560
let lavender = CGColor(red: 0xC4 / 255.0, green: 0xB5 / 255.0, blue: 0xFD / 255.0, alpha: 1)
let indigo = CGColor(red: 0x81 / 255.0, green: 0x8C / 255.0, blue: 0xF8 / 255.0, alpha: 1)
let violet = CGColor(red: 0xC0 / 255.0, green: 0x84 / 255.0, blue: 0xFC / 255.0, alpha: 1)

func headline(_ lines: [String], lang: String, size: CGFloat) -> CFAttributedString {
    let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, size, lang as CFString)!
    var alignment = CTTextAlignment.center
    var spacing: CGFloat = size * 0.10
    let paragraph = withUnsafePointer(to: &alignment) { a in
        withUnsafePointer(to: &spacing) { sp in
            let settings = [
                CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: a),
                CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: MemoryLayout<CGFloat>.size, value: sp),
            ]
            return CTParagraphStyleCreate(settings, settings.count)
        }
    }
    let s = CFAttributedStringCreateMutable(nil, 0)!
    for (i, line) in lines.enumerated() {
        let attrs: [CFString: Any] = [
            kCTFontAttributeName: font, kCTParagraphStyleAttributeName: paragraph, kCTLanguageAttributeName: lang,
            kCTForegroundColorAttributeName: i == 0 ? CGColor(gray: 1, alpha: 1) : lavender,
        ]
        let text = i < lines.count - 1 ? line + "\n" : line
        let part = CFAttributedStringCreate(nil, text as CFString, attrs as CFDictionary)!
        CFAttributedStringReplaceAttributedString(s, CFRange(location: CFAttributedStringGetLength(s), length: 0), part)
    }
    return s
}

func loadImage(_ url: URL) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
    return CGImageSourceCreateImageAtIndex(src, 0, nil)
}

func savePNG(_ image: CGImage, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func frame(shot: CGImage, lines: [String], lang: String) -> CGImage {
    let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let W = CGFloat(width), H = CGFloat(height)
    // The login page's near-black, with the button gradient's two colours as a
    // soft glow behind the headline (origin is bottom-left).
    ctx.setFillColor(CGColor(red: 0x0E / 255.0, green: 0x0C / 255.0, blue: 0x16 / 255.0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    for (color, x, y, r) in [(indigo, W * 0.22, H - 280, 820.0), (violet, W * 0.80, H - 520, 760.0)] {
        let glow = CGGradient(colorsSpace: nil, colors: [color.copy(alpha: 0.30)!, color.copy(alpha: 0)!] as CFArray, locations: [0, 1])!
        ctx.drawRadialGradient(glow, startCenter: CGPoint(x: x, y: y), startRadius: 0,
                               endCenter: CGPoint(x: x, y: y), endRadius: CGFloat(r), options: [])
    }

    // Headline in the top band. Shrink until each line fits on one line; only
    // below 72 pt may a line wrap, as long as the block still fits.
    let box = CGRect(x: 100, y: H - 500, width: W - 200, height: 360)
    func measure(_ size: CGFloat) -> (CFAttributedString, CGSize, Int) {
        let text = headline(lines, lang: lang, size: size)
        let setter = CTFramesetterCreateWithAttributedString(text)
        let fitted = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(), nil, CGSize(width: box.width, height: .greatestFiniteMagnitude), nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: CGRect(x: 0, y: 0, width: box.width, height: 10_000), transform: nil), nil)
        return (text, fitted, CFArrayGetCount(CTFrameGetLines(frame)))
    }
    var size: CGFloat = lang.hasPrefix("zh") ? 124 : 116
    var (text, fitted, count) = measure(size)
    while (count > lines.count && size > 72) || fitted.height > box.height {
        size -= 4
        (text, fitted, count) = measure(size)
        if size <= 48 { break }
    }
    let setter = CTFramesetterCreateWithAttributedString(text)
    let textRect = CGRect(x: box.minX, y: box.midY - fitted.height / 2, width: box.width, height: ceil(fitted.height) + 2)
    CTFrameDraw(CTFramesetterCreateFrame(setter, CFRange(), CGPath(rect: textRect, transform: nil), nil), ctx)

    // The whole capture, scaled to fit under the headline: what matters sits
    // at the bottom of some screens (call buttons, the message bar).
    let sh = H - 560 - 70, sw = CGFloat(shot.width) * sh / CGFloat(shot.height)
    let rect = CGRect(x: (W - sw) / 2, y: 70, width: sw, height: sh)
    let radius: CGFloat = 56
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -24), blur: 80, color: CGColor(gray: 0, alpha: 0.7))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(shot, in: rect)
    ctx.restoreGState()
    ctx.addPath(CGPath(roundedRect: rect.insetBy(dx: 1.5, dy: 1.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
    ctx.setLineWidth(3)
    ctx.strokePath()
    return ctx.makeImage()!
}

func strings(_ url: URL) -> [String: Any] {
    guard let data = try? Data(contentsOf: url) else { return [:] }
    return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

let extra = strings(extraStrings)
let langs = CommandLine.arguments.count > 1 ? Array(CommandLine.arguments.dropFirst()) : allLangs
var made = 0, missing: [String] = []
for lang in langs {
    let app = strings(appStrings.appendingPathComponent("i18n_\(lang).json"))
    let more = extra[lang] as? [String: Any] ?? [:]
    for (n, item) in order.enumerated() {
        let input = raw.appendingPathComponent("\(lang)/\(item.screen).png")
        guard let shot = loadImage(input) else { missing.append("\(lang)/\(item.screen).png"); continue }
        let lines = (1...2).compactMap { (app["\(item.key)_line_\($0)"] ?? more["\(item.key)_line_\($0)"]) as? String }
        guard lines.count == 2 else { missing.append("\(lang): headline \(item.key)"); continue }
        savePNG(frame(shot: shot, lines: lines, lang: lang),
                to: framed.appendingPathComponent("\(lang)/\(n + 1)-\(item.screen).png"))
        made += 1
    }
}
print("framed \(made) screenshots in build/store-shots/framed/")
if !missing.isEmpty { print("missing:\n  " + missing.joined(separator: "\n  ")) }
