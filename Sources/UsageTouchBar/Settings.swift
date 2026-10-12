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
    case small, medium, large, extraLarge
    var title: String {
        switch self {
        case .small: "小"
        case .medium: "中"
        case .large: "大"
        case .extraLarge: "特大"
        }
    }
    /// 展开后用量栏里的图标（Touch Bar 高 30，特大就是撑满）
    var detailSide: CGFloat {
        switch self {
        case .small: 18
        case .medium: 22
        case .large: 26
        case .extraLarge: 30
        }
    }
    /// Control Strip 上的图标
    var controlStripSide: CGFloat {
        switch self {
        case .small: 20
        case .medium: 23
        case .large: 26
        case .extraLarge: 29
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
        let first = Metric(percent: dailyPercent, resetAt: dailyResetAt, shortLabel: primaryLabel ?? "5h")
        let second = Metric(percent: weeklyPercent, resetAt: weeklyResetAt, shortLabel: secondaryLabel ?? "W")
        // “主要显示：每周额度”只对有 5h / 每周两种额度的服务生效
        if AppConfig.shared.resolvedPrimaryMetric == .weekly, primaryLabel == nil || primaryLabel == "5h",
           weeklyPercent != nil {
            return second
        }
        return first
    }

    var secondaryMetric: Metric {
        let first = Metric(percent: dailyPercent, resetAt: dailyResetAt, shortLabel: primaryLabel ?? "5h")
        let second = Metric(percent: weeklyPercent, resetAt: weeklyResetAt, shortLabel: secondaryLabel ?? "W")
        if AppConfig.shared.resolvedPrimaryMetric == .weekly, primaryLabel == nil || primaryLabel == "5h",
           weeklyPercent != nil {
            return first
        }
        return second
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

/// 标准 macOS 设置窗口：顶部一排分类图标，每次只显示一类设置，窗口自动调整到这一页的大小。
@MainActor
final class SettingsTabController: NSTabViewController {
    var onSelect: ((Int) -> Void)?

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let item = tabViewItem else { return }
        let index = tabView.indexOfTabViewItem(item)
        onSelect?(index)
        resizeWindow(to: item.viewController?.preferredContentSize)
    }

    /// 窗口高度跟着这一页的内容走，左上角位置不动。
    func resizeWindow(to size: NSSize?) {
        guard let window = view.window, let size, size.width > 0, size.height > 0 else { return }
        let content = window.contentRect(forFrameRect: window.frame)
        let target = window.frameRect(forContentRect: NSRect(x: content.minX, y: content.maxY - size.height,
                                                             width: size.width, height: size.height))
        window.setFrame(target, display: true, animate: window.isVisible)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    private let settingsVC: DisplaySettingsViewController
    private let tabs = SettingsTabController()

    init(onChange: @escaping () -> Void,
         onArrange: @escaping ([(provider: Provider, enabled: Bool)]) -> Void) {
        settingsVC = DisplaySettingsViewController(onChange: onChange, onArrange: onArrange)
        _ = settingsVC.view   // 建好所有设置页

        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade]
        for page in settingsVC.pages {
            let pageVC = NSViewController()
            pageVC.view = page.view
            pageVC.title = page.title
            pageVC.preferredContentSize = page.size
            let item = NSTabViewItem(viewController: pageVC)
            item.label = page.title
            item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.title)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let vc = settingsVC
        tabs.onSelect = { index in vc.attachStatus(to: index) }
        vc.attachStatus(to: 0)
        if let first = settingsVC.pages.first { window.setContentSize(first.size) }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        settingsVC.reload()
        if window?.isVisible != true {
            let index = max(0, tabs.selectedTabViewItemIndex)
            tabs.resizeWindow(to: settingsVC.pages[safe: index]?.size)
            window?.center()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
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
    private let claudeStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let glmKeyField = NSSecureTextField()
    private let glmRegionPopup = NSPopUpButton()
    private let glmSourceLabel = NSTextField(wrappingLabelWithString: "")
    private let geminiNote = NSTextField(wrappingLabelWithString: "")
    private let estimateSwitch = NSSwitch()
    private let keychainButton = NSButton(title: "授权钥匙串…", target: nil, action: nil)
    private let addFrontAppButton = NSButton(title: "把它加入音乐 App 列表", target: nil, action: nil)
    // 账号页：需要填 API Key 的服务
    private let kimiKeyField = NSSecureTextField()
    private let kimiRegionPopup = NSPopUpButton()
    private let minimaxKeyField = NSSecureTextField()
    private let minimaxRegionPopup = NSPopUpButton()
    private let copilotKeyField = NSSecureTextField()
    private let keySourcesLabel = NSTextField(wrappingLabelWithString: "")
    private let autoSourcesLabel = NSTextField(wrappingLabelWithString: "")

    /// 每一页：标题、图标、内容和底部放状态提示的位置
    struct Page {
        let title: String
        let symbol: String
        let view: NSView
        let footer: NSView
        let size: NSSize
    }
    private(set) var pages: [Page] = []
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

    override func loadView() {
        configureControls()
        configureLabels()
        pages = buildPages()
        view = NSView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))   // 各页单独放进设置窗口
        reload()
        // 重新量一次尺寸（reload 填好了服务列表等内容）
        pages = pages.map { Page(title: $0.title, symbol: $0.symbol, view: $0.view, footer: $0.footer, size: measure($0.view)) }
    }

    /// 把底部的状态提示移到当前这一页。
    func attachStatus(to index: Int) {
        guard let page = pages[safe: index] else { return }
        statusLabel.removeFromSuperview()
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        page.footer.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: page.footer.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: page.footer.trailingAnchor),
            statusLabel.topAnchor.constraint(equalTo: page.footer.topAnchor),
        ])
    }

    private func measure(_ view: NSView) -> NSSize {
        let fitting = view.fittingSize
        return NSSize(width: max(560, ceil(fitting.width)), height: ceil(fitting.height))
    }

    private func buildPages() -> [Page] {
        let resetColors = NSButton(title: "恢复默认样式", target: self, action: #selector(resetStyle(_:)))
        resetColors.bezelStyle = .rounded
        resetColors.controlSize = .small

        let musicApps = NSStackView(views: musicAppChecks)
        musicApps.orientation = .vertical
        musicApps.alignment = .leading
        musicApps.spacing = 4

        let musicTip = note("其他 App 可以填 Bundle ID，用逗号分隔。查询方法：终端运行 mdls -name kMDItemCFBundleIdentifier \"/Applications/某某.app\"")

        func keyRow(_ field: NSSecureTextField, tag: Int) -> NSView {
            field.translatesAutoresizingMaskIntoConstraints = false
            field.widthAnchor.constraint(equalToConstant: 230).isActive = true
            let save = NSButton(title: "保存", target: self, action: #selector(saveAPIKey(_:)))
            save.bezelStyle = .rounded
            save.controlSize = .small
            save.tag = tag
            let row = NSStackView(views: [field, save])
            row.orientation = .horizontal
            row.spacing = 8
            return row
        }

        let definitions: [(String, String, [Row])] = [
            ("服务", "square.grid.2x2", [
                .section("显示哪些服务（最多同时显示 3 个，↑ ↓ 调整从左到右的顺序）"),
                .full(providerStack),
                .section("读取状态"),
                .full(claudeStatusLabel),
                .item("Claude 钥匙串：", keychainButton),
                .item("取不到实时数据时显示本地估算：", estimateSwitch),
            ]),
            ("账号", "key", [
                .section("自动读取（不用填）"),
                .full(autoSourcesLabel),
                .section("GLM / ZCode（智谱 GLM Coding Plan）"),
                .item("区域：", glmRegionPopup),
                .item("API Key：", keyRow(glmKeyField, tag: 0)),
                .full(glmSourceLabel),
                .section("Kimi（Kimi Code 编程套餐）"),
                .item("区域：", kimiRegionPopup),
                .item("API Key：", keyRow(kimiKeyField, tag: 1)),
                .section("MiniMax（编程套餐）"),
                .item("区域：", minimaxRegionPopup),
                .item("API Key：", keyRow(minimaxKeyField, tag: 2)),
                .section("GitHub Copilot（可选）"),
                .item("GitHub 令牌：", keyRow(copilotKeyField, tag: 3)),
                .full(keySourcesLabel),
            ]),
            ("显示", "rectangle.split.3x1", [
                .section("Touch Bar"),
                .item("显示位置：", placementPopup),
                .item("展开后内容：", alignPopup),
                .item("Control Strip 样式：", stripStylePopup),
                .item("刷新 / 设置按钮：", buttonsSwitch),
                .section("显示内容"),
                .item("主要显示：", metricPopup),
                .item("同时显示另一项额度：", secondarySwitch),
                .item("显示重置倒计时：", resetSwitch),
            ]),
            ("外观", "paintpalette", [
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
            ]),
            ("音乐", "music.note", [
                .section("音乐 App 在前台时（QQ音乐、网易云音乐等用 Touch Bar 显示歌词）"),
                .item("处理方式：", musicModePopup),
                .item("Control Strip 图标：", slotPopup),
                .item("对这些 App 生效：", musicApps),
                .item("其他 App：", customMusicField),
                .full(musicTip),
                .section("诊断"),
                .full(diagnosticsLabel),
                .full(addFrontAppButton),
            ]),
            ("通用", "gearshape", [
                .section("通用"),
                .item("刷新间隔：", intervalPopup),
                .item("菜单栏显示用量文字：", menuBarSwitch),
                .item("在 Dock 显示图标：", dockSwitch),
                .item("登录时自动启动：", loginSwitch),
            ]),
        ]

        return definitions.map { title, symbol, rows in
            let grid = makeGrid(rows)
            grid.translatesAutoresizingMaskIntoConstraints = false
            let footer = NSView()
            footer.translatesAutoresizingMaskIntoConstraints = false
            let container = NSView()
            container.addSubview(grid)
            container.addSubview(footer)
            NSLayoutConstraint.activate([
                grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 22),
                grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
                grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -30),
                footer.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 18),
                footer.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 30),
                footer.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -30),
                footer.heightAnchor.constraint(equalToConstant: 32),
                footer.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),
                container.widthAnchor.constraint(greaterThanOrEqualToConstant: 560),
            ])
            return Page(title: title, symbol: symbol, view: container, footer: footer, size: measure(container))
        }
    }

    private func note(_ text: String) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: 11)
        field.textColor = .secondaryLabelColor
        field.preferredMaxLayoutWidth = 480
        return field
    }

    private func configureLabels() {
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 2
        statusLabel.preferredMaxLayoutWidth = 500
        statusLabel.stringValue = "修改后立即生效，保存在 ~/.config/usage-touchbar/config.json。"

        glmRegionPopup.addItems(withTitles: ["国内（open.bigmodel.cn）", "国际（api.z.ai）"])
        glmRegionPopup.target = self
        glmRegionPopup.action = #selector(glmRegionChanged(_:))
        kimiRegionPopup.addItems(withTitles: ["国内（kimi.com）", "国际（kimi.ai）"])
        minimaxRegionPopup.addItems(withTitles: ["国内（minimaxi.com）", "国际（minimax.io）"])
        for popup in [kimiRegionPopup, minimaxRegionPopup] {
            popup.target = self
            popup.action = #selector(otherRegionChanged(_:))
        }
        glmKeyField.placeholderString = "留空则自动读取 Claude Code 里的配置"
        kimiKeyField.placeholderString = "Kimi Code 控制台里创建的 API Key"
        minimaxKeyField.placeholderString = "编程套餐的 API Key"
        copilotKeyField.placeholderString = "一般不用填，会自动读取 Copilot 插件的登录"
        for label in [glmSourceLabel, geminiNote, keySourcesLabel, autoSourcesLabel] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
            label.preferredMaxLayoutWidth = 480
        }
        claudeStatusLabel.font = .systemFont(ofSize: 12)
        claudeStatusLabel.preferredMaxLayoutWidth = 480
        diagnosticsLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        diagnosticsLabel.preferredMaxLayoutWidth = 480
        keychainButton.target = self
        keychainButton.action = #selector(authorizeKeychain(_:))
        keychainButton.bezelStyle = .rounded
        keychainButton.controlSize = .small
        addFrontAppButton.target = self
        addFrontAppButton.action = #selector(addFrontApp(_:))
        addFrontAppButton.bezelStyle = .rounded
        addFrontAppButton.controlSize = .small
        diagnosticsObserver = NotificationCenter.default.addObserver(
            forName: Diagnostics.changed, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateDiagnostics() }
        }
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
        for control in [resetSwitch, secondarySwitch, buttonsSwitch, menuBarSwitch, dockSwitch, loginSwitch, estimateSwitch,
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
                        resetSwitch, secondarySwitch, buttonsSwitch, menuBarSwitch, dockSwitch, slotPopup,
                        estimateSwitch] as [NSControl] {
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
        glmRegionPopup.selectItem(at: config.glmRegion == "intl" ? 1 : 0)
        glmKeyField.stringValue = ""
        kimiRegionPopup.selectItem(at: config.kimiRegion == "intl" ? 1 : 0)
        minimaxRegionPopup.selectItem(at: config.minimaxRegion == "intl" ? 1 : 0)
        updateAccountLabels()
        estimateSwitch.state = config.claudeOfflineEstimate == true ? .on : .off
        slotPopup.selectItem(at: StripSlotPolicy.allCases.firstIndex(of: config.resolvedStripSlotPolicy) ?? 0)
        loginSwitch.state = LaunchAtLogin.isEnabled ? .on : .off
        updateMusicControlsEnabled()
        arrangement = config.arrangement
        renderProviders()
        updateDiagnostics()
    }

    private func updateDiagnostics() {
        var lines: [String] = []
        var anyFailed = false
        if let status = ClaudeUsageCollector.lastStatus() {
            lines.append((status.ok ? "✓ Claude：" : "✗ Claude：") + status.detail)
            anyFailed = anyFailed || !status.ok
        } else {
            lines.append("Claude：还没有读取过（点 Touch Bar 上的刷新按钮可立即读取）。")
        }
        let visible = AppConfig.shared.orderedVisibleProviders
        let caches: [(Provider, LiveCache)] = [
            (.gemini, GeminiUsageCollector.cache), (.antigravity, AntigravityUsageCollector.cache),
            (.glm, GLMUsageCollector.cache), (.kimi, KimiUsageCollector.cache),
            (.minimax, MiniMaxUsageCollector.cache), (.copilot, CopilotUsageCollector.cache),
            (.cursor, CursorUsageCollector.cache),
        ]
        for (provider, cache) in caches where visible.contains(provider) {
            if let status = cache.lastStatus() {
                lines.append((status.ok ? "✓ " : "✗ ") + provider.rawValue + "：" + status.detail)
                anyFailed = anyFailed || !status.ok
            } else {
                lines.append(provider.rawValue + "：还没有读取过。")
            }
        }
        claudeStatusLabel.stringValue = lines.joined(separator: "\n")
        claudeStatusLabel.textColor = anyFailed ? .systemOrange : .secondaryLabelColor
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
        if sender.state == .on, arrangement.filter(\.enabled).count >= Provider.maxVisible {
            sender.state = .off
            statusLabel.stringValue = "最多同时显示 \(Provider.maxVisible) 个服务（Touch Bar 放不下更多），先取消勾选一个。"
            return
        }
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

    // MARK: GLM

    /// 保存 API Key（按钮的 tag：0 GLM、1 Kimi、2 MiniMax、3 Copilot）。留空保存表示清除。
    @objc private func saveAPIKey(_ sender: NSButton) {
        let ok: Bool
        let name: String
        let field: NSSecureTextField
        switch sender.tag {
        case 0:
            field = glmKeyField; name = "GLM"
            ok = GLMCredentials.saveKey(field.stringValue)
            GLMUsageCollector.cache.flush()
        case 1:
            field = kimiKeyField; name = "Kimi"
            ok = APIKeyStore.save(field.stringValue, for: .kimi)
            KimiUsageCollector.cache.flush()
        case 2:
            field = minimaxKeyField; name = "MiniMax"
            ok = APIKeyStore.save(field.stringValue, for: .minimax)
            MiniMaxUsageCollector.cache.flush()
        default:
            field = copilotKeyField; name = "GitHub"
            ok = APIKeyStore.save(field.stringValue, for: .copilot)
            CopilotUsageCollector.cache.flush()
        }
        let cleared = field.stringValue.trimmingCharacters(in: .whitespaces).isEmpty
        statusLabel.stringValue = !ok ? "保存失败。"
            : cleared ? "已清除 \(name) 的 Key。"
            : "已保存 \(name) 的 Key（只保存在你电脑上，仅你自己的账户可读）。"
        field.stringValue = ""
        updateAccountLabels()
        onChange()
    }

    @objc private func authorizeKeychain(_ sender: Any?) {
        statusLabel.stringValue = "请在弹出的窗口里输入登录密码，并选「始终允许」。"
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = ClaudeCredentials.authorize()
            DispatchQueue.main.async { [weak self] in
                self?.statusLabel.stringValue = ok
                    ? "已授权。只要选的是「始终允许」，这个版本以后都不会再问。"
                    : "没有授权成功（可能点了「拒绝」，或 Claude Code 还没登录）。"
                ClaudeUsageCollector.clearFailure()
                ClaudeUsageCollector.expireCache()
                self?.onChange()
            }
        }
    }

    @objc private func otherRegionChanged(_ sender: NSPopUpButton) {
        var config = AppConfig.shared
        let value = sender.indexOfSelectedItem == 1 ? "intl" : "cn"
        if sender === kimiRegionPopup {
            config.kimiRegion = value
            KimiUsageCollector.cache.flush()
        } else {
            config.minimaxRegion = value
            MiniMaxUsageCollector.cache.flush()
        }
        AppConfig.save(config)
        statusLabel.stringValue = "已切换区域。"
        onChange()
    }

    /// 账号页上“哪些已配置”的说明文字。
    private func updateAccountLabels() {
        glmSourceLabel.stringValue = GLMCredentials.sourceDescription
        func mark(_ ok: Bool) -> String { ok ? "✓" : "—" }
        let antigravity = AntigravityLocal.isRunning
        let antigravityInstalled = FileManager.default.fileExists(atPath: "/Applications/Antigravity.app")
        autoSourcesLabel.stringValue = [
            "\(mark(true)) Claude：读取 Claude Code 的登录（钥匙串）",
            "\(mark(FileManager.default.fileExists(atPath: DataFiles.expand("~/.codex/auth.json")))) Codex：读取 ~/.codex/auth.json",
            "\(mark(GeminiCredentials.isLoggedIn)) Gemini：读取 Gemini CLI 的 Google 登录（在终端运行 gemini 登录一次）",
            "\(mark(antigravity)) Antigravity：读取本机正在运行的 Antigravity（\(antigravity ? "正在运行" : antigravityInstalled ? "打开 Antigravity 后自动读取" : "没有安装"))",
            "\(mark(CursorCredentials.cookie() != nil)) Cursor：读取 Cursor App 的登录（打开 Cursor 登录一次即可）",
            "\(mark(CopilotCredentials.token() != nil)) GitHub Copilot：读取 Copilot 插件的登录（~/.config/github-copilot）",
        ].joined(separator: "\n")
        let kimi = APIKeyStore.key(for: .kimi) != nil
        let minimax = APIKeyStore.key(for: .minimax) != nil
        keySourcesLabel.stringValue = "Kimi：\(kimi ? "已填写 Key" : "未填写")；MiniMax：\(minimax ? "已填写 Key" : "未填写")。Key 只保存在 ~/.config/usage-touchbar/ 里（仅你自己的账户可读），只会发给对应服务自己的接口。"
    }

    @objc private func glmRegionChanged(_ sender: Any?) {
        var config = AppConfig.shared
        config.glmRegion = glmRegionPopup.indexOfSelectedItem == 1 ? "intl" : "cn"
        AppConfig.save(config)
        GLMCredentials.invalidate()
        GLMUsageCollector.cache.flush()
        glmSourceLabel.stringValue = GLMCredentials.sourceDescription
        statusLabel.stringValue = "已切换 GLM 区域。"
        onChange()
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
        config.claudeOfflineEstimate = estimateSwitch.state == .on
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
