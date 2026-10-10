import AppKit
import QuartzCore
import ServiceManagement

// MARK: - 选项定义

enum TouchBarPlacement: String, CaseIterable {
    case controlStripOnly
    case expandOnLaunch
    case pinned

    var title: String {
        switch self {
        case .controlStripOnly: "只在右侧 Control Strip 显示小图标"
        case .expandOnLaunch: "启动时自动展开整条 Touch Bar"
        case .pinned: "常驻展开整条 Touch Bar"
        }
    }
}

enum ControlStripStyle: String, CaseIterable {
    case gauge
    case numbers

    var title: String {
        switch self {
        case .gauge: "迷你柱状图"
        case .numbers: "图标 + 百分比数字"
        }
    }
}

enum PrimaryMetric: String, CaseIterable {
    case fiveHour
    case weekly

    var title: String {
        switch self {
        case .fiveHour: "5 小时额度"
        case .weekly: "每周额度"
        }
    }
}

enum UsageColorScheme: String, CaseIterable {
    case traffic
    case mono

    var title: String {
        switch self {
        case .traffic: "绿 / 橙 / 红（按用量变色）"
        case .mono: "单色（只在超过红线时变红）"
        }
    }
}

enum FontSizeOption: String, CaseIterable {
    case small, standard, large
    var title: String {
        switch self {
        case .small: "小"
        case .standard: "标准"
        case .large: "大"
        }
    }
    var scale: CGFloat {
        switch self {
        case .small: 0.9
        case .standard: 1.0
        case .large: 1.12
        }
    }
}

enum IconSizeOption: String, CaseIterable {
    case small, medium, large
    var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        }
    }
    /// 展开后用量栏里的图标
    var detailSide: CGFloat {
        switch self {
        case .small: 14
        case .medium: 18
        case .large: 22
        }
    }
    /// Control Strip 上的图标
    var controlStripSide: CGFloat {
        switch self {
        case .small: 20
        case .medium: 24
        case .large: 27
        }
    }
}

enum StripSlotPolicy: String, CaseIterable {
    case musicOnly, always, never
    var title: String {
        switch self {
        case .musicOnly: "只在音乐 App 里顶替（离开后还给输入法等）"
        case .always: "一直占用"
        case .never: "从不占用"
        }
    }
}

enum MusicMode: String, CaseIterable {
    case off, hide, iconOnly
    var title: String {
        switch self {
        case .off: "不处理"
        case .hide: "隐藏用量显示，离开音乐 App 后恢复"
        case .iconOnly: "让出歌词位置，只显示 AI 图标"
        }
    }
}

/// 内置支持的音乐 App。除了精确的 Bundle ID，也按关键词和显示名称识别，
/// 这样 App 改了 ID 或装的是别的版本也能认出来。
struct MusicApp {
    let name: String
    let bundleID: String
    let idKeywords: [String]
    let names: [String]

    static let builtIn: [MusicApp] = [
        MusicApp(name: "QQ音乐", bundleID: "com.tencent.QQMusicMac",
                 idKeywords: ["qqmusic"], names: ["QQ音乐", "QQMusic"]),
        MusicApp(name: "网易云音乐", bundleID: "com.netease.163music",
                 idKeywords: ["163music", "neteasemusic", "netease.music"], names: ["网易云音乐", "NeteaseMusic", "NetEase Cloud Music"]),
        MusicApp(name: "Apple 音乐", bundleID: "com.apple.Music",
                 idKeywords: [], names: []),
        MusicApp(name: "Spotify", bundleID: "com.spotify.client",
                 idKeywords: ["spotify"], names: ["Spotify"]),
    ]

    /// 这些 App 永远不会被当成音乐 App（防止误加入后用量栏不显示）。
    static let neverMusic = ["com.anthropic.", "com.openai.", "local.usage-touchbar"]

    func matches(bundleID: String?, name: String?) -> Bool {
        if let bundleID {
            if bundleID.caseInsensitiveCompare(self.bundleID) == .orderedSame { return true }
            let lower = bundleID.lowercased()
            if idKeywords.contains(where: { lower.contains($0) }) { return true }
        }
        if let name, names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) { return true }
        return false
    }
}

// MARK: - 读取配置（带默认值）

extension AppConfig {
    var resolvedPlacement: TouchBarPlacement {
        placement.flatMap(TouchBarPlacement.init(rawValue:)) ?? .expandOnLaunch
    }
    var resolvedControlStripStyle: ControlStripStyle {
        controlStripStyle.flatMap(ControlStripStyle.init(rawValue:)) ?? .gauge
    }
    var resolvedPrimaryMetric: PrimaryMetric {
        primaryMetric.flatMap(PrimaryMetric.init(rawValue:)) ?? .fiveHour
    }
    var resolvedColorScheme: UsageColorScheme {
        colorScheme.flatMap(UsageColorScheme.init(rawValue:)) ?? .traffic
    }
    var resolvedFontSize: FontSizeOption {
        fontSize.flatMap(FontSizeOption.init(rawValue:)) ?? .standard
    }
    var resolvedIconSize: IconSizeOption {
        iconSize.flatMap(IconSizeOption.init(rawValue:)) ?? .medium
    }
    var resolvedMusicMode: MusicMode {
        musicMode.flatMap(MusicMode.init(rawValue:)) ?? .iconOnly
    }
    /// 内置音乐 App 里勾选了哪些（默认全部）。
    var resolvedBuiltInMusicApps: [String] {
        musicApps ?? MusicApp.builtIn.map(\.bundleID)
    }
    var resolvedCustomMusicApps: [String] {
        (customMusicApps ?? "")
            .split(whereSeparator: { $0 == "," || $0 == "，" || $0 == " " || $0 == "\n" })
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    var resolvedMusicApps: Set<String> {
        Set(resolvedBuiltInMusicApps + resolvedCustomMusicApps)
    }

    /// 这个 App 是否算“音乐 App”（勾选的内置 App 按 ID/关键词/名称识别，自定义的按 ID）。
    func isMusicApp(bundleID: String?, name: String?) -> Bool {
        if let bundleID, MusicApp.neverMusic.contains(where: { bundleID.lowercased().hasPrefix($0.lowercased()) }) {
            return false
        }
        let enabled = Set(resolvedBuiltInMusicApps)
        for app in MusicApp.builtIn where enabled.contains(app.bundleID) {
            if app.matches(bundleID: bundleID, name: name) { return true }
        }
        if let bundleID {
            return resolvedCustomMusicApps.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
        }
        return false
    }
    var resolvedCenterContent: Bool { centerContent ?? true }
    var resolvedShowResetCountdown: Bool { showResetCountdown ?? true }
    var resolvedShowSecondaryMetric: Bool { showSecondaryMetric ?? true }
    var resolvedShowMenuBar: Bool { showMenuBar ?? true }
    var resolvedShowInDock: Bool { showInDock ?? true }
    var resolvedStripSlotPolicy: StripSlotPolicy {
        stripSlotPolicy.flatMap(StripSlotPolicy.init(rawValue:)) ?? .musicOnly
    }
    /// 菜单栏和 Touch Bar 按钮不能同时隐藏，否则就没有入口打开设置了。
    var resolvedShowTouchBarButtons: Bool { (showTouchBarButtons ?? true) || !resolvedShowMenuBar }
    var resolvedWarnThreshold: Double { warnThreshold ?? 60 }
    var resolvedDangerThreshold: Double { max(dangerThreshold ?? 85, resolvedWarnThreshold + 1) }
    var resolvedRefreshInterval: Double { max(5, refreshInterval ?? 20) }
}

// MARK: - Touch Bar 文字样式

/// 用量栏里所有文字、图标的样式都从这里取，设置窗口改了立即生效。
enum TouchBarStyle {
    static var defaultNameColor: NSColor { .white }
    static var defaultPercentColor: NSColor { .white }
    /// 套餐（PRO / MAX）、倒计时、5h / W 标签。比原版亮很多，原版是很浅的灰色。
    static var defaultDetailColor: NSColor { NSColor(srgbRed: 0.80, green: 0.80, blue: 0.82, alpha: 1) }

    static var scale: CGFloat { AppConfig.shared.resolvedFontSize.scale }
    static var iconSize: CGFloat { AppConfig.shared.resolvedIconSize.detailSide }
    static var controlStripIconSize: CGFloat { AppConfig.shared.resolvedIconSize.controlStripSide }

    static var nameColor: NSColor { NSColor(hexString: AppConfig.shared.nameColor) ?? defaultNameColor }
    static var percentColor: NSColor { NSColor(hexString: AppConfig.shared.percentColor) ?? defaultPercentColor }
    static var detailColor: NSColor { NSColor(hexString: AppConfig.shared.detailColor) ?? defaultDetailColor }

    /// “5h” / “W” 标签
    static var captionAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 9.5 * scale, weight: .semibold), .foregroundColor: detailColor]
    }
    /// 百分比数字
    static var valueAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: 11 * scale, weight: .bold), .foregroundColor: percentColor]
    }
    /// 重置倒计时
    static var resetAttributes: [NSAttributedString.Key: Any] {
        [.font: NSFont.monospacedDigitSystemFont(ofSize: 9 * scale, weight: .semibold), .foregroundColor: detailColor]
    }
}

extension NSColor {
    convenience init?(hexString: String?) {
        guard var hex = hexString?.trimmingCharacters(in: .whitespaces), !hex.isEmpty else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", max(0, min(255, r)), max(0, min(255, g)), max(0, min(255, b)))
    }
}

/// 根据“主要指标”设置取出要突出显示的那一组数字。
extension UsageSnapshot {
    struct Metric {
        let percent: Double?
        let resetAt: Date?
        let shortLabel: String
    }

    var primaryMetric: Metric {
        switch AppConfig.shared.resolvedPrimaryMetric {
        case .fiveHour: Metric(percent: dailyPercent, resetAt: dailyResetAt, shortLabel: "5h")
        case .weekly: Metric(percent: weeklyPercent, resetAt: weeklyResetAt, shortLabel: "W")
        }
    }

    var secondaryMetric: Metric {
        switch AppConfig.shared.resolvedPrimaryMetric {
        case .fiveHour: Metric(percent: weeklyPercent, resetAt: weeklyResetAt, shortLabel: "W")
        case .weekly: Metric(percent: dailyPercent, resetAt: dailyResetAt, shortLabel: "5h")
        }
    }
}

// MARK: - 诊断信息（显示在设置窗口底部）

@MainActor
enum Diagnostics {
    static let changed = Notification.Name("UsageTouchBarDiagnosticsChanged")

    private(set) static var lastAppName: String?
    private(set) static var lastAppBundleID: String?
    private(set) static var lastAppIsMusic = false
    private(set) static var controlStripSupported = false
    private(set) static var controlStripInstalled = false
    private(set) static var musicModeActive = false

    static func recordFrontApp(name: String?, bundleID: String?, recognizedAsMusic: Bool) {
        lastAppName = name
        lastAppBundleID = bundleID
        lastAppIsMusic = recognizedAsMusic
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func update(controlStripSupported: Bool, controlStripInstalled: Bool, musicModeActive: Bool) {
        self.controlStripSupported = controlStripSupported
        self.controlStripInstalled = controlStripInstalled
        self.musicModeActive = musicModeActive
        NotificationCenter.default.post(name: changed, object: nil)
    }
}

// MARK: - 登录时自动启动

@MainActor
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 返回 nil 表示成功，否则返回错误说明。
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

// MARK: - Touch Bar 内容容器

/// Touch Bar 元素里的固定容器。刷新时只换里面的内容，元素本身保持不变，
/// 这样系统不会因为元素被替换而显示空白。
@MainActor
final class TouchBarContentHost: NSView {
    private var content: NSView?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 10, height: 30))
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setContent(_ view: NSView) {
        // 内容更新时做一次线性淡入淡出，避免数字和图标“跳”一下
        if content != nil {
            wantsLayer = true
            let fade = CATransition()
            fade.type = .fade
            fade.duration = 0.25
            fade.timingFunction = CAMediaTimingFunction(name: .linear)
            layer?.add(fade, forKey: "contentFade")
        }
        content?.removeFromSuperview()
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        content = view
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }
}

// MARK: - 设置窗口

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settingsVC: DisplaySettingsViewController
    private var screenObserver: NSObjectProtocol?

    init(onChange: @escaping () -> Void,
         onArrange: @escaping ([(provider: Provider, enabled: Bool)]) -> Void) {
        settingsVC = DisplaySettingsViewController(onChange: onChange, onArrange: onArrange)
        settingsVC.title = "Usage Touch Bar 设置"
        let window = NSWindow(contentViewController: settingsVC)
        window.title = "Usage Touch Bar 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = settingsVC.minimumSize
        window.setContentSize(settingsVC.idealSize)
        window.setFrameAutosaveName("UsageTouchBarSettings.v4")
        super.init(window: window)
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.fitToScreen() }
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        settingsVC.reload()
        if window?.isVisible != true {
            fitToScreen()
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 换了显示器或改了分辨率后，窗口不超出屏幕。
    func fitToScreen() {
        guard let window, let screen = window.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = window.frame
        frame.size.width = min(frame.width, visible.width - 20)
        frame.size.height = min(frame.height, visible.height - 20)
        frame.origin.x = min(max(frame.minX, visible.minX + 10), visible.maxX - frame.width - 10)
        frame.origin.y = min(max(frame.minY, visible.minY + 10), visible.maxY - frame.height - 10)
        window.setFrame(frame, display: true, animate: false)
    }
}

/// 设置窗口的滚动内容：上面是自适应的几栏，下面是一行状态提示。
///
/// 注意：layout() 里只用缓存好的尺寸摆放位置，绝不在这里计算 fittingSize——
/// 计算尺寸本身会触发排版，在排版过程中调用会无限循环，导致卡死和崩溃。
@MainActor
final class SettingsDocumentView: NSView {
    static let margin: CGFloat = 28
    static let footerHeight: CGFloat = 40
    var columns: AdaptiveColumnsView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let columns { addSubview(columns) }
        }
    }
    var footer: NSTextField? {
        didSet {
            oldValue?.removeFromSuperview()
            if let footer {
                footer.maximumNumberOfLines = 2
                footer.lineBreakMode = .byTruncatingTail
                addSubview(footer)
            }
        }
    }

    override var isFlipped: Bool { true }

    func height(forWidth width: CGFloat) -> CGFloat {
        let inner = max(10, width - Self.margin * 2)
        let columnsHeight = columns?.arrangement(forWidth: inner).height ?? 0
        return 22 + columnsHeight + 20 + Self.footerHeight + 16
    }

    override func layout() {
        super.layout()
        let inner = max(10, bounds.width - Self.margin * 2)
        var y: CGFloat = 22
        if let columns {
            let height = columns.arrangement(forWidth: inner).height
            columns.frame = NSRect(x: Self.margin, y: y, width: inner, height: height)
            y += height + 20
        }
        footer?.frame = NSRect(x: Self.margin, y: y, width: inner, height: Self.footerHeight)
    }
}

/// 自适应分栏：按可用宽度决定一行放几栏（3 → 2 → 1），放不下就换行；
/// 同一行的栏顶部对齐，多出来的空间平均分到栏之间，栏之间画分隔线。
@MainActor
final class AdaptiveColumnsView: NSView {
    private var items: [NSView] = []
    /// 每一栏的尺寸缓存。只在内容变化时由 measure() 更新。
    private var sizes: [NSSize] = []
    private var separators: [NSRect] = []
    private let minGap: CGFloat = 44
    private let rowGap: CGFloat = 30

    override var isFlipped: Bool { true }

    func setItems(_ views: [NSView]) {
        items.forEach { $0.removeFromSuperview() }
        items = views
        for view in views {
            view.translatesAutoresizingMaskIntoConstraints = true
            addSubview(view)
        }
        measure()
    }

    /// 重新计算每一栏需要多大。内容变了（比如诊断文字、服务列表）之后调用，
    /// 不能在 layout() 里调用。
    func measure() {
        sizes = items.map { view in
            let fitting = view.fittingSize
            return NSSize(width: ceil(fitting.width), height: ceil(fitting.height))
        }
        needsLayout = true
    }

    /// 所有栏放在一行时需要的宽度。
    var widthForAllInOneRow: CGFloat {
        sizes.reduce(0) { $0 + $1.width } + minGap * CGFloat(max(0, sizes.count - 1))
    }

    /// 最宽的一栏（窗口最窄只能缩到这么宽）。
    var widestItem: CGFloat {
        sizes.map(\.width).max() ?? 300
    }

    struct Arrangement {
        var frames: [NSRect]
        var separators: [NSRect]
        var height: CGFloat
    }

    func arrangement(forWidth width: CGFloat) -> Arrangement {
        let sizes = self.sizes
        guard sizes.count == items.count, !sizes.isEmpty else {
            return Arrangement(frames: [], separators: [], height: 0)
        }
        // 按顺序装行：当前行放不下下一栏就换行
        var rows: [[Int]] = []
        var current: [Int] = []
        var used: CGFloat = 0
        for (index, itemSize) in sizes.enumerated() {
            let needed = current.isEmpty ? itemSize.width : used + minGap + itemSize.width
            if !current.isEmpty && needed > width {
                rows.append(current)
                current = [index]
                used = itemSize.width
            } else {
                current.append(index)
                used = needed
            }
        }
        if !current.isEmpty { rows.append(current) }

        var frames = Array(repeating: NSRect.zero, count: items.count)
        var separators: [NSRect] = []
        var y: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            let rowHeight = row.map { sizes[$0].height }.max() ?? 0
            let total = row.map { sizes[$0].width }.reduce(0, +)
            // 一行多栏时把剩余宽度平均分到栏间距里（最多加宽到 120），看起来更均衡
            let gap = row.count > 1
                ? min(120, max(minGap, (width - total) / CGFloat(row.count - 1)))
                : 0
            var x: CGFloat = 0
            for (position, index) in row.enumerated() {
                if position > 0 {
                    separators.append(NSRect(x: x - gap / 2, y: y, width: 1, height: rowHeight))
                }
                frames[index] = NSRect(x: x, y: y, width: sizes[index].width, height: sizes[index].height)
                x += sizes[index].width + gap
            }
            y += rowHeight
            if rowIndex < rows.count - 1 {
                // 行与行之间画一条横线
                separators.append(NSRect(x: 0, y: y + rowGap / 2, width: width, height: 1))
                y += rowGap
            }
        }
        return Arrangement(frames: frames, separators: separators, height: y)
    }

    override func layout() {
        super.layout()
        let result = arrangement(forWidth: bounds.width)
        for (view, frame) in zip(items, result.frames) where view.frame != frame {
            view.frame = frame
        }
        if separators != result.separators {
            separators = result.separators
            needsDisplay = true
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setFill()
        for rect in separators { rect.fill() }
    }
}

@MainActor
final class DisplaySettingsViewController: NSViewController {
    private enum Row {
        case section(String)
        case full(NSView)
        case item(String, NSView)
    }

    private let onChange: () -> Void
    private let onArrange: ([(provider: Provider, enabled: Bool)]) -> Void

    private let placementPopup = NSPopUpButton()
    private let alignPopup = NSPopUpButton()
    private let stripStylePopup = NSPopUpButton()
    private let metricPopup = NSPopUpButton()
    private let colorPopup = NSPopUpButton()
    private let warnPopup = NSPopUpButton()
    private let dangerPopup = NSPopUpButton()
    private let intervalPopup = NSPopUpButton()
    private let fontSizeControl = NSSegmentedControl()
    private let iconSizeControl = NSSegmentedControl()
    private let nameColorWell = NSColorWell()
    private let percentColorWell = NSColorWell()
    private let detailColorWell = NSColorWell()
    private let musicModePopup = NSPopUpButton()
    private var musicAppChecks: [NSButton] = []
    private let customMusicField = NSTextField()
    private let resetSwitch = NSSwitch()
    private let secondarySwitch = NSSwitch()
    private let buttonsSwitch = NSSwitch()
    private let menuBarSwitch = NSSwitch()
    private let dockSwitch = NSSwitch()
    private let slotPopup = NSPopUpButton()
    private let loginSwitch = NSSwitch()
    private let providerStack = NSStackView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let diagnosticsLabel = NSTextField(wrappingLabelWithString: "")
    private let addFrontAppButton = NSButton(title: "把它加入音乐 App 列表", target: nil, action: nil)
    private let columnsView = AdaptiveColumnsView()
    private let documentView = SettingsDocumentView()
    private var diagnosticsObserver: NSObjectProtocol?

    private var arrangement: [(provider: Provider, enabled: Bool)] = []
    private var isReloading = false

    private let warnChoices: [Double] = [40, 50, 60, 70, 75, 80]
    private let dangerChoices: [Double] = [70, 80, 85, 90, 95]
    private let intervalChoices: [(seconds: Double, title: String)] = [
        (10, "10 秒"), (20, "20 秒"), (30, "30 秒"), (60, "1 分钟"), (120, "2 分钟"), (300, "5 分钟")
    ]

    init(onChange: @escaping () -> Void,
         onArrange: @escaping ([(provider: Provider, enabled: Bool)]) -> Void) {
        self.onChange = onChange
        self.onArrange = onArrange
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 窗口第一次打开时的大小：按屏幕分辨率挑一个能放下最多栏的宽度。
    var idealSize: NSSize {
        _ = view
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1400, height: 800)
        let width = min(columnsView.widthForAllInOneRow + SettingsDocumentView.margin * 2, screen.width - 40)
        let height = documentView.height(forWidth: width)
        return NSSize(width: max(minimumSize.width, width),
                      height: min(max(360, height), screen.height - 60))
    }

    /// 最窄能缩到只剩一栏。
    var minimumSize: NSSize {
        _ = view
        return NSSize(width: columnsView.widestItem + SettingsDocumentView.margin * 2, height: 360)
    }

    override func loadView() {
        configureControls()

        let resetColors = NSButton(title: "恢复默认样式", target: self, action: #selector(resetStyle(_:)))
        resetColors.bezelStyle = .rounded
        resetColors.controlSize = .small

        let musicApps = NSStackView(views: musicAppChecks)
        musicApps.orientation = .vertical
        musicApps.alignment = .leading
        musicApps.spacing = 4

        let musicTip = NSTextField(wrappingLabelWithString:
            "其他 App 可以填 Bundle ID，用逗号分隔。查询方法：终端运行 mdls -name kMDItemCFBundleIdentifier \"/Applications/某某.app\"")
        musicTip.font = .systemFont(ofSize: 11)
        musicTip.textColor = .secondaryLabelColor
        musicTip.preferredMaxLayoutWidth = 320

        let column1 = makeGrid([
            .section("显示哪些服务（勾选显示，↑ ↓ 调整顺序）"),
            .full(providerStack),
            .section("Touch Bar"),
            .item("显示位置：", placementPopup),
            .item("展开后内容：", alignPopup),
            .item("Control Strip 样式：", stripStylePopup),
            .item("刷新 / 设置按钮：", buttonsSwitch),
            .section("显示内容"),
            .item("主要显示：", metricPopup),
            .item("同时显示另一项额度：", secondarySwitch),
            .item("显示重置倒计时：", resetSwitch),
        ])
        let column2 = makeGrid([
            .section("用量颜色"),
            .item("配色：", colorPopup),
            .item("超过多少变橙色：", warnPopup),
            .item("超过多少变红色：", dangerPopup),
            .section("文字与图标"),
            .item("字号：", fontSizeControl),
            .item("图标大小：", iconSizeControl),
            .item("服务名称颜色：", nameColorWell),
            .item("百分比数字颜色：", percentColorWell),
            .item("套餐、倒计时颜色：", detailColorWell),
            .item("", resetColors),
            .section("其他"),
            .item("刷新间隔：", intervalPopup),
            .item("菜单栏显示用量文字：", menuBarSwitch),
            .item("在 Dock 显示图标：", dockSwitch),
            .item("登录时自动启动：", loginSwitch),
        ])
        let column3 = makeGrid([
            .section("音乐 App（歌词）"),
            .item("音乐 App 在前台时：", musicModePopup),
            .item("Control Strip 图标：", slotPopup),
            .item("对这些 App 生效：", musicApps),
            .item("其他 App：", customMusicField),
            .full(musicTip),
            .full(diagnosticsLabel),
            .full(addFrontAppButton),
        ])

        // 自适应：窗口够宽三栏并排，窄一些自动换成两栏、一栏
        columnsView.setItems([column1, column2, column3])

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "修改后立即生效，保存在 ~/.config/usage-touchbar/config.json。"

        diagnosticsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        diagnosticsLabel.preferredMaxLayoutWidth = 300
        addFrontAppButton.target = self
        addFrontAppButton.action = #selector(addFrontApp(_:))
        addFrontAppButton.bezelStyle = .rounded
        addFrontAppButton.controlSize = .small
        diagnosticsObserver = NotificationCenter.default.addObserver(
            forName: Diagnostics.changed, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDiagnostics() }
        }
        // 放进滚动区域：内容宽度永远跟着窗口走，只在高度放不下时上下滚动
        documentView.columns = columnsView
        documentView.footer = statusLabel

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = documentView
        scroll.contentView.postsFrameChangedNotifications = true
        clipObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.relayout() }
        }

        scroll.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        view = scroll
        reload()
        relayout()
    }

    private var clipObserver: NSObjectProtocol?
    private var isRelayouting = false

    /// 窗口大小变了：按新宽度重新排列栏，并更新可滚动的高度。
    /// 只在尺寸真的变了时才改，并防止重入，避免排版死循环。
    private func relayout() {
        guard !isRelayouting, let scroll = view as? NSScrollView else { return }
        isRelayouting = true
        defer { isRelayouting = false }
        let width = scroll.contentView.bounds.width
        guard width > 0 else { return }
        let height = max(documentView.height(forWidth: width), scroll.contentView.bounds.height)
        let frame = NSRect(x: 0, y: 0, width: width, height: height)
        if abs(documentView.frame.width - frame.width) > 0.5 || abs(documentView.frame.height - frame.height) > 0.5 {
            documentView.frame = frame
        }
        documentView.needsLayout = true
    }

    /// 内容变了（服务列表、诊断文字）后重新量尺寸再排版。
    private func remeasure() {
        guard isViewLoaded else { return }
        columnsView.measure()
        relayout()
    }

    private func makeGrid(_ rows: [Row]) -> NSGridView {
        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        var views: [[NSView]] = []
        var fullRows: [Int] = []
        var sectionRows: [Int] = []
        for (index, row) in rows.enumerated() {
            switch row {
            case .section(let title):
                let field = NSTextField(labelWithString: title)
                field.font = .systemFont(ofSize: 13, weight: .semibold)
                views.append([field, NSGridCell.emptyContentView])
                fullRows.append(index)
                sectionRows.append(index)
            case .full(let view):
                views.append([view, NSGridCell.emptyContentView])
                fullRows.append(index)
            case .item(let title, let control):
                views.append([label(title), control])
            }
        }
        let grid = NSGridView(views: views)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        for index in fullRows {
            let gridRow = grid.row(at: index)
            gridRow.mergeCells(in: NSRange(location: 0, length: 2))
            gridRow.cell(at: 0).xPlacement = .leading
            gridRow.rowAlignment = .none
            if sectionRows.contains(index) && index > 0 { gridRow.topPadding = 10 }
        }
        for control in [resetSwitch, secondarySwitch, buttonsSwitch, menuBarSwitch, dockSwitch, loginSwitch,
                        nameColorWell, percentColorWell, detailColorWell] as [NSView] {
            if let cell = grid.cell(for: control) {
                cell.yPlacement = .center
                cell.row?.rowAlignment = .none
            }
        }
        return grid
    }

    private func configureControls() {
        placementPopup.addItems(withTitles: TouchBarPlacement.allCases.map(\.title))
        alignPopup.addItems(withTitles: ["居中", "靠左"])
        stripStylePopup.addItems(withTitles: ControlStripStyle.allCases.map(\.title))
        metricPopup.addItems(withTitles: PrimaryMetric.allCases.map(\.title))
        colorPopup.addItems(withTitles: UsageColorScheme.allCases.map(\.title))
        warnPopup.addItems(withTitles: warnChoices.map { "\(Int($0))%" })
        dangerPopup.addItems(withTitles: dangerChoices.map { "\(Int($0))%" })
        intervalPopup.addItems(withTitles: intervalChoices.map(\.title))
        musicModePopup.addItems(withTitles: MusicMode.allCases.map(\.title))
        slotPopup.addItems(withTitles: StripSlotPolicy.allCases.map(\.title))

        fontSizeControl.segmentCount = FontSizeOption.allCases.count
        for (i, option) in FontSizeOption.allCases.enumerated() { fontSizeControl.setLabel(option.title, forSegment: i) }
        fontSizeControl.trackingMode = .selectOne
        iconSizeControl.segmentCount = IconSizeOption.allCases.count
        for (i, option) in IconSizeOption.allCases.enumerated() { iconSizeControl.setLabel(option.title, forSegment: i) }
        iconSizeControl.trackingMode = .selectOne

        musicAppChecks = MusicApp.builtIn.map { app in
            NSButton(checkboxWithTitle: app.name, target: self, action: #selector(valueChanged(_:)))
        }

        customMusicField.placeholderString = "例如 com.example.player"
        customMusicField.cell?.sendsActionOnEndEditing = true
        customMusicField.translatesAutoresizingMaskIntoConstraints = false
        customMusicField.widthAnchor.constraint(equalToConstant: 220).isActive = true

        for well in [nameColorWell, percentColorWell, detailColorWell] {
            well.translatesAutoresizingMaskIntoConstraints = false
            well.widthAnchor.constraint(equalToConstant: 44).isActive = true
            well.heightAnchor.constraint(equalToConstant: 24).isActive = true
        }

        for control in [placementPopup, alignPopup, stripStylePopup, metricPopup, colorPopup,
                        warnPopup, dangerPopup, intervalPopup, musicModePopup,
                        fontSizeControl, iconSizeControl,
                        nameColorWell, percentColorWell, detailColorWell, customMusicField,
                        resetSwitch, secondarySwitch, buttonsSwitch, menuBarSwitch, dockSwitch, slotPopup] as [NSControl] {
            control.target = self
            control.action = #selector(valueChanged(_:))
        }
        loginSwitch.target = self
        loginSwitch.action = #selector(loginChanged(_:))

        providerStack.orientation = .vertical
        providerStack.alignment = .leading
        providerStack.spacing = 4
    }

    /// 把当前保存的配置同步到界面上。
    func reload() {
        guard isViewLoaded else { return }
        isReloading = true
        defer { isReloading = false }
        let config = AppConfig.shared
        placementPopup.selectItem(at: TouchBarPlacement.allCases.firstIndex(of: config.resolvedPlacement) ?? 0)
        alignPopup.selectItem(at: config.resolvedCenterContent ? 0 : 1)
        stripStylePopup.selectItem(at: ControlStripStyle.allCases.firstIndex(of: config.resolvedControlStripStyle) ?? 0)
        metricPopup.selectItem(at: PrimaryMetric.allCases.firstIndex(of: config.resolvedPrimaryMetric) ?? 0)
        colorPopup.selectItem(at: UsageColorScheme.allCases.firstIndex(of: config.resolvedColorScheme) ?? 0)
        warnPopup.selectItem(at: Self.nearestIndex(of: config.resolvedWarnThreshold, in: warnChoices))
        dangerPopup.selectItem(at: Self.nearestIndex(of: config.resolvedDangerThreshold, in: dangerChoices))
        intervalPopup.selectItem(at: Self.nearestIndex(of: config.resolvedRefreshInterval, in: intervalChoices.map(\.seconds)))
        musicModePopup.selectItem(at: MusicMode.allCases.firstIndex(of: config.resolvedMusicMode) ?? 0)
        fontSizeControl.selectedSegment = FontSizeOption.allCases.firstIndex(of: config.resolvedFontSize) ?? 1
        iconSizeControl.selectedSegment = IconSizeOption.allCases.firstIndex(of: config.resolvedIconSize) ?? 1
        nameColorWell.color = TouchBarStyle.nameColor
        percentColorWell.color = TouchBarStyle.percentColor
        detailColorWell.color = TouchBarStyle.detailColor
        let enabledMusic = Set(config.resolvedBuiltInMusicApps)
        for (check, app) in zip(musicAppChecks, MusicApp.builtIn) {
            check.state = enabledMusic.contains(app.bundleID) ? .on : .off
        }
        customMusicField.stringValue = config.customMusicApps ?? ""
        resetSwitch.state = config.resolvedShowResetCountdown ? .on : .off
        secondarySwitch.state = config.resolvedShowSecondaryMetric ? .on : .off
        buttonsSwitch.state = (config.showTouchBarButtons ?? true) ? .on : .off
        menuBarSwitch.state = config.resolvedShowMenuBar ? .on : .off
        dockSwitch.state = config.resolvedShowInDock ? .on : .off
        slotPopup.selectItem(at: StripSlotPolicy.allCases.firstIndex(of: config.resolvedStripSlotPolicy) ?? 0)
        loginSwitch.state = LaunchAtLogin.isEnabled ? .on : .off
        updateMusicControlsEnabled()
        arrangement = config.arrangement
        renderProviders()
        updateDiagnostics()
    }

    private func updateDiagnostics() {
        let name = Diagnostics.lastAppName ?? "（还没有切换过 App）"
        let id = Diagnostics.lastAppBundleID ?? "—"
        let recognized = Diagnostics.lastAppBundleID == nil ? "" : (Diagnostics.lastAppIsMusic ? "✓ 已识别为音乐 App" : "✗ 不在音乐 App 列表里")
        let strip = Diagnostics.controlStripSupported
            ? (Diagnostics.controlStripInstalled ? "已添加" : "未添加")
            : "系统不支持"
        diagnosticsLabel.stringValue = """
        诊断：上一个前台 App
          \(name)
          \(id)  \(recognized)
        Control Strip 图标：\(strip)
        """
        addFrontAppButton.isHidden = Diagnostics.lastAppBundleID == nil || Diagnostics.lastAppIsMusic
        addFrontAppButton.title = "把「\(Diagnostics.lastAppName ?? "它")」加入音乐 App 列表…"
        // 诊断文字和按钮长度变了，栏宽可能跟着变
        remeasure()
    }

    @objc private func addFrontApp(_ sender: Any?) {
        guard let id = Diagnostics.lastAppBundleID else { return }
        let alert = NSAlert()
        alert.messageText = "把「\(Diagnostics.lastAppName ?? id)」当成音乐 App？"
        alert.informativeText = "它在前台时，Touch Bar 会收起 AI 用量栏，让出位置给它显示歌词。\n（\(id)）\n以后可以在「其他 App」里删掉。"
        alert.addButton(withTitle: "加入")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        var list = AppConfig.shared.resolvedCustomMusicApps
        if !list.contains(id) { list.append(id) }
        customMusicField.stringValue = list.joined(separator: ", ")
        valueChanged(nil)
        statusLabel.stringValue = "已把 \(Diagnostics.lastAppName ?? id) 加入音乐 App 列表。"
    }

    private func updateMusicControlsEnabled() {
        let enabled = musicModePopup.indexOfSelectedItem > 0
        musicAppChecks.forEach { $0.isEnabled = enabled }
        slotPopup.isEnabled = enabled
        customMusicField.isEnabled = enabled
    }

    private static func nearestIndex(of value: Double, in choices: [Double]) -> Int {
        choices.indices.min { abs(choices[$0] - value) < abs(choices[$1] - value) } ?? 0
    }

    // MARK: 服务列表

    private func renderProviders() {
        providerStack.arrangedSubviews.forEach {
            providerStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }
        for (index, item) in arrangement.enumerated() {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .centerY
            row.spacing = 6

            let check = NSButton(checkboxWithTitle: item.provider.rawValue, target: self, action: #selector(providerToggled(_:)))
            check.state = item.enabled ? .on : .off
            check.tag = index
            check.translatesAutoresizingMaskIntoConstraints = false
            check.widthAnchor.constraint(equalToConstant: 140).isActive = true
            row.addArrangedSubview(check)

            let up = NSButton(title: "↑", target: self, action: #selector(moveProviderUp(_:)))
            up.bezelStyle = .rounded
            up.controlSize = .small
            up.tag = index
            up.isEnabled = index > 0
            row.addArrangedSubview(up)

            let down = NSButton(title: "↓", target: self, action: #selector(moveProviderDown(_:)))
            down.bezelStyle = .rounded
            down.controlSize = .small
            down.tag = index
            down.isEnabled = index < arrangement.count - 1
            row.addArrangedSubview(down)

            providerStack.addArrangedSubview(row)
        }
    }

    @objc private func providerToggled(_ sender: NSButton) {
        guard arrangement.indices.contains(sender.tag) else { return }
        arrangement[sender.tag].enabled = sender.state == .on
        if !arrangement.contains(where: { $0.enabled }) {
            arrangement[sender.tag].enabled = true
            sender.state = .on
            statusLabel.stringValue = "至少要显示一个服务。"
            return
        }
        commitArrangement()
    }

    @objc private func moveProviderUp(_ sender: NSButton) {
        let i = sender.tag
        guard i > 0, arrangement.indices.contains(i) else { return }
        arrangement.swapAt(i, i - 1)
        renderProviders()
        commitArrangement()
    }

    @objc private func moveProviderDown(_ sender: NSButton) {
        let i = sender.tag
        guard arrangement.indices.contains(i), i < arrangement.count - 1 else { return }
        arrangement.swapAt(i, i + 1)
        renderProviders()
        commitArrangement()
    }

    private func commitArrangement() {
        onArrange(arrangement)
        statusLabel.stringValue = "已保存，立即生效。"
    }

    // MARK: 其他设置

    @objc private func resetStyle(_ sender: Any?) {
        var config = AppConfig.shared
        config.nameColor = nil
        config.percentColor = nil
        config.detailColor = nil
        config.fontSize = nil
        config.iconSize = nil
        AppConfig.save(config)
        reload()
        statusLabel.stringValue = "已恢复默认的字号、图标大小和颜色。"
        onChange()
    }

    @objc private func valueChanged(_ sender: Any?) {
        guard !isReloading else { return }
        var config = AppConfig.shared
        config.placement = TouchBarPlacement.allCases[max(0, placementPopup.indexOfSelectedItem)].rawValue
        config.centerContent = alignPopup.indexOfSelectedItem == 0
        config.controlStripStyle = ControlStripStyle.allCases[max(0, stripStylePopup.indexOfSelectedItem)].rawValue
        config.primaryMetric = PrimaryMetric.allCases[max(0, metricPopup.indexOfSelectedItem)].rawValue
        config.colorScheme = UsageColorScheme.allCases[max(0, colorPopup.indexOfSelectedItem)].rawValue
        config.warnThreshold = warnChoices[max(0, warnPopup.indexOfSelectedItem)]
        config.dangerThreshold = dangerChoices[max(0, dangerPopup.indexOfSelectedItem)]
        config.refreshInterval = intervalChoices[max(0, intervalPopup.indexOfSelectedItem)].seconds
        config.musicMode = MusicMode.allCases[max(0, musicModePopup.indexOfSelectedItem)].rawValue
        config.fontSize = FontSizeOption.allCases[max(0, fontSizeControl.selectedSegment)].rawValue
        config.iconSize = IconSizeOption.allCases[max(0, iconSizeControl.selectedSegment)].rawValue
        // 颜色只在和默认值不同时才保存，这样“默认”以后也能跟着改进
        config.nameColor = Self.hexIfChanged(nameColorWell.color, default: TouchBarStyle.defaultNameColor)
        config.percentColor = Self.hexIfChanged(percentColorWell.color, default: TouchBarStyle.defaultPercentColor)
        config.detailColor = Self.hexIfChanged(detailColorWell.color, default: TouchBarStyle.defaultDetailColor)
        config.musicApps = zip(musicAppChecks, MusicApp.builtIn).filter { $0.0.state == .on }.map { $0.1.bundleID }
        let custom = customMusicField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        config.customMusicApps = custom.isEmpty ? nil : custom
        config.showResetCountdown = resetSwitch.state == .on
        config.showSecondaryMetric = secondarySwitch.state == .on
        config.showTouchBarButtons = buttonsSwitch.state == .on
        config.showMenuBar = menuBarSwitch.state == .on
        config.showInDock = dockSwitch.state == .on
        config.stripSlotPolicy = StripSlotPolicy.allCases[max(0, slotPopup.indexOfSelectedItem)].rawValue
        updateMusicControlsEnabled()

        var notes: [String] = []
        if (config.dangerThreshold ?? 85) <= (config.warnThreshold ?? 60) {
            notes.append("红色阈值需要高于橙色阈值，已自动按橙色阈值 +1% 处理。")
        }
        if !config.resolvedShowMenuBar && config.showTouchBarButtons == false {
            notes.append("菜单栏和 Touch Bar 按钮不能同时隐藏，已保留 Touch Bar 上的设置按钮。")
        }
        if !config.resolvedShowMenuBar && !config.resolvedShowInDock {
            notes.append("菜单栏和 Dock 都隐藏后，可在 Finder 里再次双击打开本 App 来进入设置。")
        }

        if AppConfig.save(config) {
            statusLabel.stringValue = notes.isEmpty ? "已保存，立即生效。" : notes.joined(separator: "  ")
        } else {
            statusLabel.stringValue = "保存失败：无法写入 ~/.config/usage-touchbar/config.json"
        }
        onChange()
    }

    private static func hexIfChanged(_ color: NSColor, default defaultColor: NSColor) -> String? {
        let hex = color.hexString
        return hex == defaultColor.hexString ? nil : hex
    }

    @objc private func loginChanged(_ sender: NSSwitch) {
        if let error = LaunchAtLogin.set(sender.state == .on) {
            statusLabel.stringValue = "设置开机启动失败：\(error)。可以在「系统设置 › 通用 › 登录项」里手动添加。"
        } else {
            statusLabel.stringValue = sender.state == .on ? "已设置为登录时自动启动。" : "已取消登录时自动启动。"
        }
        loginSwitch.state = LaunchAtLogin.isEnabled ? .on : .off
    }
}
