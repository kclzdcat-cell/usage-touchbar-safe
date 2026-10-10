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
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        settingsVC.reload()
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
final class DisplaySettingsViewController: NSViewController {
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
    private let resetSwitch = NSSwitch()
    private let secondarySwitch = NSSwitch()
    private let buttonsSwitch = NSSwitch()
    private let menuBarSwitch = NSSwitch()
    private let dockSwitch = NSSwitch()
    private let loginSwitch = NSSwitch()
    private let providerStack = NSStackView()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")

    private var arrangement: [(provider: Provider, enabled: Bool)] = []

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
        placementPopup.addItems(withTitles: TouchBarPlacement.allCases.map(\.title))
        alignPopup.addItems(withTitles: ["居中", "靠左"])
        stripStylePopup.addItems(withTitles: ControlStripStyle.allCases.map(\.title))
        metricPopup.addItems(withTitles: PrimaryMetric.allCases.map(\.title))
        colorPopup.addItems(withTitles: UsageColorScheme.allCases.map(\.title))
        warnPopup.addItems(withTitles: warnChoices.map { "\(Int($0))%" })
        dangerPopup.addItems(withTitles: dangerChoices.map { "\(Int($0))%" })
        intervalPopup.addItems(withTitles: intervalChoices.map(\.title))

        for control in [placementPopup, alignPopup, stripStylePopup, metricPopup, colorPopup,
                        warnPopup, dangerPopup, intervalPopup] as [NSControl] {
            control.target = self
            control.action = #selector(valueChanged(_:))
        }
        for toggle in [resetSwitch, secondarySwitch, buttonsSwitch, menuBarSwitch, dockSwitch] {
            toggle.target = self
            toggle.action = #selector(valueChanged(_:))
        }
        loginSwitch.target = self
        loginSwitch.action = #selector(loginChanged(_:))

        func label(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.alignment = .right
            return field
        }
        func section(_ text: String) -> NSTextField {
            let field = NSTextField(labelWithString: text)
            field.font = .systemFont(ofSize: 13, weight: .semibold)
            return field
        }
        let empty = { NSGridCell.emptyContentView }

        providerStack.orientation = .vertical
        providerStack.alignment = .leading
        providerStack.spacing = 4

        let rows: [[NSView]] = [
            [section("显示哪些服务（勾选显示，↑ ↓ 调整从左到右的顺序）"), empty()],
            [providerStack, empty()],
            [section("Touch Bar"), empty()],
            [label("显示位置："), placementPopup],
            [label("展开后内容："), alignPopup],
            [label("Control Strip 样式："), stripStylePopup],
            [label("刷新 / 设置按钮："), buttonsSwitch],
            [section("显示内容"), empty()],
            [label("主要显示："), metricPopup],
            [label("同时显示另一项额度："), secondarySwitch],
            [label("显示重置倒计时："), resetSwitch],
            [section("颜色"), empty()],
            [label("配色："), colorPopup],
            [label("超过多少变橙色："), warnPopup],
            [label("超过多少变红色："), dangerPopup],
            [section("其他"), empty()],
            [label("刷新间隔："), intervalPopup],
            [label("菜单栏显示用量文字："), menuBarSwitch],
            [label("在 Dock 显示图标："), dockSwitch],
            [label("登录时自动启动："), loginSwitch],
        ]
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        // 整行（跨两列）的行：各分组标题 + 服务列表
        let sectionRows = [0, 2, 7, 11, 15]
        for index in sectionRows + [1] {
            let gridRow = grid.row(at: index)
            gridRow.mergeCells(in: NSRange(location: 0, length: 2))
            gridRow.cell(at: 0).xPlacement = .leading
            if sectionRows.contains(index) && index > 0 { gridRow.topPadding = 10 }
        }
        grid.row(at: 1).rowAlignment = .none
        for toggle in [resetSwitch, secondarySwitch, buttonsSwitch, menuBarSwitch, dockSwitch, loginSwitch] {
            grid.cell(for: toggle)?.yPlacement = .center
        }
        grid.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.preferredMaxLayoutWidth = 440
        statusLabel.stringValue = "修改后立即生效，保存在 ~/.config/usage-touchbar/config.json。"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let root = NSView()
        root.addSubview(grid)
        root.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: root.topAnchor, constant: 20),
            grid.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -24),
            statusLabel.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 14),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -18),
            root.widthAnchor.constraint(greaterThanOrEqualToConstant: 500),
        ])
        view = root
        reload()
    }

    /// 把当前保存的配置同步到界面上。
    func reload() {
        guard isViewLoaded else { return }
        let config = AppConfig.shared
        placementPopup.selectItem(at: TouchBarPlacement.allCases.firstIndex(of: config.resolvedPlacement) ?? 0)
        alignPopup.selectItem(at: config.resolvedCenterContent ? 0 : 1)
        stripStylePopup.selectItem(at: ControlStripStyle.allCases.firstIndex(of: config.resolvedControlStripStyle) ?? 0)
        metricPopup.selectItem(at: PrimaryMetric.allCases.firstIndex(of: config.resolvedPrimaryMetric) ?? 0)
        colorPopup.selectItem(at: UsageColorScheme.allCases.firstIndex(of: config.resolvedColorScheme) ?? 0)
        warnPopup.selectItem(at: Self.nearestIndex(of: config.resolvedWarnThreshold, in: warnChoices))
        dangerPopup.selectItem(at: Self.nearestIndex(of: config.resolvedDangerThreshold, in: dangerChoices))
        intervalPopup.selectItem(at: Self.nearestIndex(of: config.resolvedRefreshInterval, in: intervalChoices.map(\.seconds)))
        resetSwitch.state = config.resolvedShowResetCountdown ? .on : .off
        secondarySwitch.state = config.resolvedShowSecondaryMetric ? .on : .off
        buttonsSwitch.state = (config.showTouchBarButtons ?? true) ? .on : .off
        menuBarSwitch.state = config.resolvedShowMenuBar ? .on : .off
        dockSwitch.state = config.resolvedShowInDock ? .on : .off
        loginSwitch.state = LaunchAtLogin.isEnabled ? .on : .off
        arrangement = config.arrangement
        renderProviders()
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

    @objc private func valueChanged(_ sender: Any?) {
        var config = AppConfig.shared
        config.placement = TouchBarPlacement.allCases[max(0, placementPopup.indexOfSelectedItem)].rawValue
        config.centerContent = alignPopup.indexOfSelectedItem == 0
        config.controlStripStyle = ControlStripStyle.allCases[max(0, stripStylePopup.indexOfSelectedItem)].rawValue
        config.primaryMetric = PrimaryMetric.allCases[max(0, metricPopup.indexOfSelectedItem)].rawValue
        config.colorScheme = UsageColorScheme.allCases[max(0, colorPopup.indexOfSelectedItem)].rawValue
        config.warnThreshold = warnChoices[max(0, warnPopup.indexOfSelectedItem)]
        config.dangerThreshold = dangerChoices[max(0, dangerPopup.indexOfSelectedItem)]
        config.refreshInterval = intervalChoices[max(0, intervalPopup.indexOfSelectedItem)].seconds
        config.showResetCountdown = resetSwitch.state == .on
        config.showSecondaryMetric = secondarySwitch.state == .on
        config.showTouchBarButtons = buttonsSwitch.state == .on
        config.showMenuBar = menuBarSwitch.state == .on
        config.showInDock = dockSwitch.state == .on

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
            statusLabel.stringValue = notes.isEmpty ? "已保存，立即生效。" : notes.joined(separator: "\n")
        } else {
            statusLabel.stringValue = "保存失败：无法写入 ~/.config/usage-touchbar/config.json"
        }
        onChange()
    }

    @objc private func loginChanged(_ sender: NSSwitch) {
        if let error = LaunchAtLogin.set(sender.state == .on) {
            statusLabel.stringValue = "设置开机启动失败：\(error)\n可以在「系统设置 › 通用 › 登录项」里手动添加。"
        } else {
            statusLabel.stringValue = sender.state == .on ? "已设置为登录时自动启动。" : "已取消登录时自动启动。"
        }
        loginSwitch.state = LaunchAtLogin.isEnabled ? .on : .off
    }
}
