import AppKit
import ApplicationServices
import QuartzCore

// MARK: - 汽水音乐歌词
//
// 汽水音乐没有给 Touch Bar 提供歌词，也没有公开的歌词接口。这里用 macOS 的
// 「辅助功能」接口读取汽水音乐窗口里正在显示的文字（只读汽水音乐这一个 App，
// 不联网、不读其他程序），优先读它的「桌面歌词」小窗口。
//
// 逐字上色：读不到每个字的精确时间，所以按“这一行显示了多久”估算进度，
// 并根据前几行的实际时长自动校准语速。

/// 读取汽水音乐窗口文字。
enum SodaAX {
    struct WindowInfo {
        let title: String
        let size: CGSize
        let texts: [String]
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// 弹出系统的「辅助功能」授权提示。
    static func requestPermission() {
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String? {
        (attribute(element, name) as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func size(_ element: AXUIElement) -> CGSize {
        guard let value = attribute(element, "AXSize"), CFGetTypeID(value) == AXValueGetTypeID() else { return .zero }
        var size = CGSize.zero
        AXValueGetValue(unsafeBitCast(value, to: AXValue.self), .cgSize, &size)
        return size
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        (attribute(element, "AXChildren") as? [AXUIElement]) ?? []
    }

    /// 列出汽水音乐的所有窗口和窗口里的文字。
    static func windows(pid: pid_t, maxNodes: Int = 1500) -> [WindowInfo] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        let windows = (attribute(app, "AXWindows") as? [AXUIElement]) ?? []
        return windows.map { window in
            var texts: [String] = []
            var seen = Set<String>()
            var queue: [(AXUIElement, Int)] = [(window, 0)]
            var visited = 0
            while !queue.isEmpty, visited < maxNodes {
                let (element, depth) = queue.removeFirst()
                visited += 1
                for name in ["AXValue", "AXTitle", "AXDescription"] {
                    if let text = string(element, name), !text.isEmpty, text.count <= 120, !seen.contains(text) {
                        seen.insert(text)
                        texts.append(text)
                    }
                }
                if depth < 30 {
                    queue.append(contentsOf: children(element).map { ($0, depth + 1) })
                }
            }
            return WindowInfo(title: string(window, "AXTitle") ?? "", size: size(window), texts: texts)
        }
    }

    /// 从窗口里挑出“当前这一句歌词”：优先桌面歌词窗口（标题含“歌词”，或又宽又矮的小窗口）。
    static func currentLyric(in windows: [WindowInfo]) -> String? {
        let desktopLyrics = windows.first { info in
            info.title.contains("歌词") || info.title.lowercased().contains("lyric")
                || (info.size.height > 0 && info.size.height < 220 && info.size.width > 240)
        }
        guard let lyrics = desktopLyrics else { return nil }
        return lyrics.texts.first { text in
            !text.contains("歌词") && text != lyrics.title
        }
    }

    /// 给“读取测试”用的完整报告。
    static func probeReport(pid: pid_t?) -> String {
        guard let pid else { return "没有找到正在运行的汽水音乐。请先打开汽水音乐并开始播放。" }
        guard isTrusted else { return "还没有「辅助功能」权限。请先点「授权」，在系统设置里打开 Usage Touch Bar 的开关后再试。" }
        let windows = windows(pid: pid, maxNodes: 3000)
        if windows.isEmpty { return "读不到汽水音乐的窗口（可能窗口被最小化了，或者它不支持辅助功能读取）。" }
        var lines = ["汽水音乐共有 \(windows.count) 个窗口："]
        for (i, w) in windows.enumerated() {
            lines.append("")
            lines.append("【窗口 \(i + 1)】标题：\(w.title.isEmpty ? "（无）" : w.title)  大小：\(Int(w.size.width))×\(Int(w.size.height))")
            for text in w.texts.prefix(40) { lines.append("  · \(text)") }
            if w.texts.count > 40 { lines.append("  …还有 \(w.texts.count - 40) 条") }
        }
        lines.append("")
        lines.append("识别出的当前歌词：\(currentLyric(in: windows) ?? "（没有识别到）")")
        return lines.joined(separator: "\n")
    }
}

/// 定时读取汽水音乐当前歌词，变化时回调。
@MainActor
final class SodaLyricsReader {
    var onLine: ((String) -> Void)?
    private var timer: Timer?
    private var pid: pid_t = 0
    private var lastLine: String?

    func start(pid: pid_t) {
        stop()
        self.pid = pid
        lastLine = nil
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        lastLine = nil
    }

    private func poll() {
        let line: String
        if !SodaAX.isTrusted {
            line = "需要「辅助功能」权限才能读取歌词（在设置里点「授权」）"
        } else if let lyric = SodaAX.currentLyric(in: SodaAX.windows(pid: pid)) {
            line = lyric
        } else {
            line = "♪ 打开汽水音乐的「桌面歌词」后即可在这里显示"
        }
        guard line != lastLine else { return }
        lastLine = line
        onLine?(line)
    }
}

/// 一行歌词：居中显示，从左到右逐渐上色；太长时随进度向左平移。
@MainActor
final class KaraokeLineView: NSView {
    private(set) var text = ""
    var progress: CGFloat = 0 { didSet { needsDisplay = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 30) }

    /// 换一行：用线性的淡入 + 轻微上移过渡。
    func setText(_ newText: String, animated: Bool) {
        if animated, let layer {
            let transition = CATransition()
            transition.type = .push
            transition.subtype = .fromTop
            transition.duration = 0.28
            transition.timingFunction = CAMediaTimingFunction(name: .linear)
            layer.add(transition, forKey: "lyricLine")
        }
        text = newText
        progress = 0
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard !text.isEmpty else { return }
        let font = NSFont.systemFont(ofSize: 15 * TouchBarStyle.scale, weight: .semibold)
        let base: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: LyricsStyle.baseColor]
        let fill: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: LyricsStyle.highlightColor]
        let string = text as NSString
        let size = string.size(withAttributes: base)

        let x: CGFloat
        if size.width <= bounds.width - 16 {
            x = (bounds.width - size.width) / 2
        } else {
            // 太长：开头左对齐，随进度平移到结尾右对齐
            let start: CGFloat = 8
            let end = bounds.width - 8 - size.width
            x = start + (end - start) * min(1, max(0, progress * 1.15 - 0.1))
        }
        let point = NSPoint(x: x, y: (bounds.height - size.height) / 2)
        string.draw(at: point, withAttributes: base)

        let filled = size.width * max(0, min(1, progress))
        guard filled > 0 else { return }
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: NSRect(x: x, y: 0, width: filled, height: bounds.height)).addClip()
        string.draw(at: point, withAttributes: fill)
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// 歌词颜色。
enum LyricsStyle {
    static var defaultHighlight: NSColor { NSColor(srgbRed: 1.0, green: 0.69, blue: 0.24, alpha: 1) }
    static var defaultBase: NSColor { NSColor(white: 1, alpha: 0.55) }

    static var highlightColor: NSColor { NSColor(hexString: AppConfig.shared.lyricsHighlightColor) ?? defaultHighlight }
    static var baseColor: NSColor {
        NSColor(hexString: AppConfig.shared.lyricsBaseColor)?.withAlphaComponent(0.85) ?? defaultBase
    }
}

/// 管理“当前句”的上色进度：按字数估算这一句的时长，并用前几句的实际时长校准。
@MainActor
final class KaraokeTimer {
    private let view: KaraokeLineView
    private var timer: Timer?
    private var lineStart = Date()
    private var lineDuration: TimeInterval = 3
    private var secondsPerChar: TimeInterval = 0.32
    private var previousCharCount = 0

    init(view: KaraokeLineView) {
        self.view = view
    }

    func newLine(_ text: String) {
        let now = Date()
        // 用上一句真实显示的时长校准语速
        if previousCharCount > 0 {
            let actual = now.timeIntervalSince(lineStart)
            if actual > 0.6 && actual < 15 {
                let measured = actual / Double(previousCharCount)
                secondsPerChar = secondsPerChar * 0.6 + measured * 0.4
            }
        }
        let chars = Self.lyricCharCount(text)
        let isMessage = text.hasPrefix("♪") || text.hasPrefix("需要")
        previousCharCount = isMessage ? 0 : chars
        lineStart = now
        lineDuration = min(10, max(1.2, Double(chars) * secondsPerChar * 0.92))
        view.setText(text, animated: true)
        if isMessage {
            view.progress = 0
            stopTicking()
        } else {
            startTicking()
        }
    }

    func stop() {
        stopTicking()
        previousCharCount = 0
    }

    private func startTicking() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func stopTicking() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let elapsed = Date().timeIntervalSince(lineStart)
        view.progress = CGFloat(min(1, elapsed / lineDuration))   // 线性上色
    }

    /// 中文按字算，英文按单词算一个“字”。
    private static func lyricCharCount(_ text: String) -> Int {
        var count = 0
        var inWord = false
        for scalar in text.unicodeScalars {
            if CharacterSet.letters.contains(scalar) && scalar.isASCII {
                if !inWord { count += 1; inWord = true }
            } else {
                inWord = false
                if !CharacterSet.whitespacesAndNewlines.contains(scalar) && !CharacterSet.punctuationCharacters.contains(scalar) {
                    count += 1
                }
            }
        }
        return max(1, count)
    }
}
