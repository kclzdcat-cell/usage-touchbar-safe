import AppKit
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

/// 内置支持的音乐 App。
struct MusicApp {
    let name: String
    let bundleID: String

    static let builtIn: [MusicApp] = [
        MusicApp(name: "QQ音乐", bundleID: "com.tencent.QQMusicMac"),
        MusicApp(name: "网易云音乐", bundleID: "com.netease.163music"),
        MusicApp(name: "Apple 音乐", bundleID: "com.apple.Music"),
        MusicApp(name: "Spotify", bundleID: "com.spotify.client"),
    ]
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
    var resolvedCenterContent: Bool { centerContent ?? true }
    var resolvedShowResetCountdown: Bool { showResetCountdown ?? true }
    var resolvedShowSecondaryMetric: Bool { showSecondaryMetric ?? true }
    var resolvedShowMenuBar: Bool { showMenuBar ?? true }
    var resolvedShowInDock: Bool { showInDock ?? true }
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

    init(onChange: @escaping () -> Void,
         onArrange: @escaping ([(provider: Provider, enabled: Bool)]) -> Void) {
        settingsVC = DisplaySettingsViewController(onChange: onChange, onArrange: onArrange)
        settingsVC.title = "Usage Touch Bar 设置"
        let window = NSWindow(contentViewController: settingsVC)
        window.title = "Usage Touch Bar 设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 520, height: 360)
        window.setContentSize(settingsVC.idealSize)
        window.setFrameAutosaveName("UsageTouchBarSettings")
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        settingsVC.reload()
        if window?.isVisible != true { window?.center() }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// 让滚动区域的内容从左上角开始排。
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
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
    private let loginSwitch = NSSwitch()
    private let providerStack = NSStackView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let content = NSStackView()

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

    /// 窗口第一次打开时的大小：刚好放下全部内容（横向两栏）。
    var idealSize: NSSize {
        _ = view
        let fitting = content.fittingSize
        let maxHeight = (NSScreen.main?.visibleFrame.height ?? 800) - 60
        return NSSize(width: fitting.width + 48, height: min(fitting.height + 40, maxHeight))
    }

    override func loadView() {
        configureControls()

        let left = makeGrid([
            .section("显示哪些服务（勾选显示，↑ ↓ 调整从左到右的顺序）"),
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
            .section("用量颜色"),
            .item("配色：", colorPopup),
            .item("超过多少变橙色：", warnPopup),
            .item("超过多少变红色：", dangerPopup),
        ])

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
        musicTip.preferredMaxLayoutWidth = 300

        let right = makeGrid([
            .section("文字与图标"),
            .item("字号：", fontSizeControl),
            .item("图标大小：", iconSizeControl),
            .item("服务名称颜色：", nameColorWell),
            .item("百分比数字颜色：", percentColorWell),
            .item("套餐、倒计时颜色：", detailColorWell),
            .item("", resetColors),
            .section("音乐 App（歌词）"),
            .item("音乐 App 在前台时：", musicModePopup),
            .item("对这些 App 生效：", musicApps),
            .item("其他 App：", customMusicField),
            .full(musicTip),
            .section("其他"),
            .item("刷新间隔：", intervalPopup),
            .item("菜单栏显示用量文字：", menuBarSwitch),
            .item("在 Dock 显示图标：", dockSwitch),
            .item("登录时自动启动：", loginSwitch),
        ])

        let divider = NSBox()
        divider.boxType = .separator

        let columns = NSStackView(views: [left, divider, right])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = 28
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.heightAnchor.constraint(equalTo: columns.heightAnchor).isActive = true

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "修改后立即生效，保存在 ~/.config/usage-touchbar/config.json。"

        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 16
        content.addArrangedSubview(columns)
        content.addArrangedSubview(statusLabel)
        content.translatesAutoresizingMaskIntoConstraints = false

        // 放进滚动区域：窗口可以随意拉大缩小，缩小时可以滚动查看。
        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(content)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = document

        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            content.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(lessThanOrEqualTo: document.trailingAnchor, constant: -24),
            content.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -20),
            document.topAnchor.constraint(equalTo: clip.topAnchor),
            document.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            document.widthAnchor.constraint(greaterThanOrEqualTo: clip.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: clip.heightAnchor),
        ])
        statusLabel.preferredMaxLayoutWidth = 700

        scroll.frame = NSRect(x: 0, y: 0, width: 900, height: 600)
        view = scroll
        reload()
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
                        resetSwitch, secondarySwitch, buttonsSwitch, menuBarSwitch, dockSwitch] as [NSControl] {
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
        loginSwitch.state = LaunchAtLogin.isEnabled ? .on : .off
        updateMusicControlsEnabled()
        arrangement = config.arrangement
        renderProviders()
    }

    private func updateMusicControlsEnabled() {
        let enabled = musicModePopup.indexOfSelectedItem > 0
        musicAppChecks.forEach { $0.isEnabled = enabled }
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
