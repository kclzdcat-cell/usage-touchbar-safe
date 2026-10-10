import Darwin
import Foundation
import SQLite3

// 更多服务的用量读取：Antigravity、GitHub Copilot、Cursor、Kimi、MiniMax。
//
// 接口和字段参考了开源项目 CodexBar（MIT 许可，© Peter Steinberger，
// https://github.com/steipete/CodexBar）。按本项目的安全原则，凡是需要读取浏览器
// Cookie 或执行外部命令的读取方式都没有采用。

// MARK: - API Key 存储（Kimi、MiniMax 等）

/// 用户在设置里填的 API Key，每个服务一个文件：~/.config/usage-touchbar/keys/<服务>，权限 600。
enum APIKeyStore {
    private static var directory: String { DataFiles.expand("~/.config/usage-touchbar/keys") }

    static func key(for provider: Provider) -> String? {
        let path = "\(directory)/\(provider.rawValue.lowercased())"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    @discardableResult
    static func save(_ key: String?, for provider: Provider) -> Bool {
        let fm = FileManager.default
        let path = "\(directory)/\(provider.rawValue.lowercased())"
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            try? fm.removeItem(atPath: path)
            return true
        }
        try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        guard fm.createFile(atPath: path, contents: Data(key.utf8), attributes: [.posixPermissions: 0o600]) else {
            return false
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        return true
    }
}

private func httpFailure(_ code: Int, service: String, cache: LiveCache) {
    switch code {
    case 401, 403: cache.fail("登录失效", "\(service) 拒绝了这个登录（HTTP \(code)），请重新登录或检查 API Key。")
    case 429: cache.fail("被限流", "请求太频繁，被暂时限流（HTTP 429），稍后会自动恢复。")
    default: cache.fail("HTTP \(code)", "\(service) 接口返回了 HTTP \(code)。")
    }
}

private func parseISODate(_ text: String?) -> Date? {
    guard let text, !text.isEmpty else { return nil }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso.date(from: text) { return date }
    if let date = ISO8601DateFormatter().date(from: text) { return date }
    let day = DateFormatter()
    day.dateFormat = "yyyy-MM-dd"
    day.timeZone = TimeZone(identifier: "UTC")
    return day.date(from: text)
}

/// 共用的读取流程：有新鲜缓存就用缓存，失败后退避，失败时显示原因。
private func collectWithCache(
    _ provider: Provider,
    cache: LiveCache,
    connected: Bool,
    fetch: () async -> UsageSnapshot?
) async -> UsageSnapshot {
    guard connected else { return .disconnected(provider) }
    if let fresh = cache.fresh() { return fresh }
    if !cache.inBackoff, let live = await fetch() {
        cache.store(live)
        return live
    }
    if let stale = cache.last() { return stale }
    return .failure(provider, message: cache.lastStatus()?.short ?? "读取失败")
}

// MARK: - Antigravity（只连本机正在运行的 Antigravity 语言服务，不联网）

/// 用系统接口（不执行任何外部命令）找到 Antigravity 的 language_server 进程，
/// 读出它的 --csrf_token 参数和监听端口。
enum AntigravityLocal {
    struct Endpoint {
        let port: Int
        let csrfToken: String
    }

    static func findEndpoints() -> [Endpoint] {
        var endpoints: [Endpoint] = []
        for pid in allPIDs() {
            guard let path = executablePath(pid: pid) else { continue }
            let lower = path.lowercased()
            let name = (lower as NSString).lastPathComponent
            guard lower.contains("antigravity"), name.hasPrefix("language_server") else { continue }
            guard let args = arguments(pid: pid), let token = flag("--csrf_token", in: args) else { continue }
            for port in listeningTCPPorts(pid: pid) {
                endpoints.append(Endpoint(port: port, csrfToken: token))
            }
        }
        return endpoints
    }

    static var isRunning: Bool { !findEndpoints().isEmpty }

    private static func flag(_ name: String, in args: [String]) -> String? {
        for (index, arg) in args.enumerated() {
            if arg == name, index + 1 < args.count { return args[index + 1] }
            if arg.hasPrefix(name + "=") { return String(arg.dropFirst(name.count + 1)) }
        }
        return nil
    }

    private static func allPIDs() -> [Int32] {
        let count = proc_listallpids(nil, 0)
        guard count > 0 else { return [] }
        var pids = [Int32](repeating: 0, count: Int(count) + 32)
        let actual = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        guard actual > 0 else { return [] }
        return Array(pids.prefix(Int(actual))).filter { $0 > 0 }
    }

    private static func executablePath(pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = buffer.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func arguments(pid: Int32) -> [String]? {
        var mib = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size >= 4, size < 4_000_000 else { return nil }
        var data = Data(count: size)
        let ok = data.withUnsafeMutableBytes { sysctl(&mib, u_int(mib.count), $0.baseAddress, &size, nil, 0) } == 0
        guard ok else { return nil }
        let bytes = [UInt8](data.prefix(size))
        let argc = bytes.withUnsafeBytes { Int(Int32(littleEndian: $0.loadUnaligned(as: Int32.self))) }
        guard argc >= 0 else { return nil }
        var offset = 4
        guard let execEnd = bytes[offset...].firstIndex(of: 0) else { return nil }
        offset = execEnd + 1
        while offset < bytes.count, bytes[offset] == 0 { offset += 1 }
        var args: [String] = []
        for _ in 0..<argc {
            guard offset < bytes.count, let end = bytes[offset...].firstIndex(of: 0) else { break }
            args.append(String(decoding: bytes[offset..<end], as: UTF8.self))
            offset = end + 1
        }
        return args
    }

    private static func listeningTCPPorts(pid: Int32) -> [Int] {
        let needed = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard needed > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(needed) / stride + 8)
        let actual = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard actual > 0 else { return [] }
        var ports = Set<Int>()
        for fd in fds.prefix(Int(actual) / stride) where fd.proc_fdtype == PROX_FDTYPE_SOCKET {
            var info = socket_fdinfo()
            let size = proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &info, Int32(MemoryLayout<socket_fdinfo>.size))
            guard size == MemoryLayout<socket_fdinfo>.size,
                  info.psi.soi_kind == SOCKINFO_TCP,
                  info.psi.soi_proto.pri_tcp.tcpsi_state == TSI_S_LISTEN else { continue }
            let raw = UInt16(truncatingIfNeeded: info.psi.soi_proto.pri_tcp.tcpsi_ini.insi_lport)
            ports.insert(Int(UInt16(bigEndian: raw)))
        }
        return ports.sorted()
    }
}

struct AntigravityUsageCollector: UsageCollecting {
    let provider: Provider = .antigravity
    static let cache = LiveCache(freshFor: 10)   // 只连本机，可以查得勤一些

    private struct Response: Decodable {
        let userStatus: UserStatus?
    }
    private struct UserStatus: Decodable {
        let planStatus: PlanStatus?
        let cascadeModelConfigData: ModelData?
        let userTier: Tier?
    }
    private struct PlanStatus: Decodable { let planInfo: PlanInfo? }
    private struct PlanInfo: Decodable {
        let planName: String?
        let planDisplayName: String?
        let displayName: String?
    }
    private struct Tier: Decodable { let name: String? }
    private struct ModelData: Decodable { let clientModelConfigs: [Model]? }
    private struct Model: Decodable {
        let label: String?
        let quotaInfo: Quota?
    }
    private struct Quota: Decodable {
        let remainingFraction: Double?
        let resetTime: String?
    }

    func collect() async -> UsageSnapshot {
        let endpoints = AntigravityLocal.findEndpoints()
        if endpoints.isEmpty {
            // 没在运行：有上次的数据就继续显示，没有就提示打开 Antigravity
            if let stale = Self.cache.last() { return stale }
            Self.cache.fail("未运行", "没有找到正在运行的 Antigravity。打开 Antigravity 后会自动读取额度（数据来自本机的 Antigravity 进程）。")
            return .failure(.antigravity, message: "未运行")
        }
        return await collectWithCache(.antigravity, cache: Self.cache, connected: true) {
            await fetch(endpoints)
        }
    }

    private func fetch(_ endpoints: [AntigravityLocal.Endpoint]) async -> UsageSnapshot? {
        let body: [String: Any] = [
            "metadata": ["ideName": "antigravity", "extensionName": "antigravity", "ideVersion": "unknown", "locale": "zh"],
        ]
        guard let json = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        for endpoint in endpoints {
            for scheme in ["https", "http"] {
                var components = URLComponents()
                components.scheme = scheme
                components.host = "127.0.0.1"
                components.port = endpoint.port
                components.path = SafeNet.antigravityStatusPath
                guard let url = components.url else { continue }
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.timeoutInterval = 4
                request.httpBody = json
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
                request.setValue(endpoint.csrfToken, forHTTPHeaderField: "X-Codeium-Csrf-Token")
                guard let (data, response) = try? await SafeNet.localData(for: request),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let decoded = try? JSONDecoder().decode(Response.self, from: data),
                      let status = decoded.userStatus else { continue }
                return snapshot(from: status)
            }
        }
        Self.cache.fail("读取失败", "找到了 Antigravity，但没能从它读到额度。可能是 Antigravity 更新后改了内部接口。")
        return nil
    }

    private func snapshot(from status: UserStatus) -> UsageSnapshot? {
        let models = status.cascadeModelConfigData?.clientModelConfigs ?? []
        struct Bucket { let used: Double; let reset: Date? }
        func worst(_ match: (String) -> Bool) -> Bucket? {
            models.compactMap { model -> Bucket? in
                guard let label = model.label?.lowercased(), match(label),
                      let remaining = model.quotaInfo?.remainingFraction else { return nil }
                return Bucket(used: max(0, min(100, (1 - remaining) * 100)), reset: parseISODate(model.quotaInfo?.resetTime))
            }.max { $0.used < $1.used }
        }
        let gemini = worst { $0.contains("gemini") }
        let claude = worst { $0.contains("claude") }
        let any = worst { _ in true }
        guard let primary = gemini ?? any else {
            Self.cache.fail("没有额度", "Antigravity 没有返回任何模型的额度信息。")
            return nil
        }
        let info = status.planStatus?.planInfo
        let plan = info?.planDisplayName ?? info?.displayName ?? info?.planName ?? status.userTier?.name
        var snapshot = UsageSnapshot(
            provider: .antigravity, isConnected: true,
            dailyPercent: primary.used, weeklyPercent: gemini != nil ? claude?.used : nil,
            dailyResetAt: primary.reset, weeklyResetAt: gemini != nil ? claude?.reset : nil,
            totalTokens: nil, planLabel: plan, updatedAt: Date(), error: nil)
        snapshot.primaryLabel = gemini != nil ? "Gemini" : "额度"
        snapshot.secondaryLabel = "Claude"
        return snapshot
    }
}

// MARK: - GitHub Copilot（读 Copilot 插件保存的登录）

/// VS Code、JetBrains、Xcode 等的 Copilot 插件会把 GitHub 登录保存在
/// ~/.config/github-copilot/apps.json 或 hosts.json，这里只读取，不修改。
enum CopilotCredentials {
    static func token() -> String? {
        if let manual = APIKeyStore.key(for: .copilot) { return manual }
        for name in ["apps.json", "hosts.json"] {
            let path = DataFiles.expand("~/.config/github-copilot/\(name)")
            guard let data = FileManager.default.contents(atPath: path),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            for (key, value) in json where key.hasPrefix("github.com") {
                if let entry = value as? [String: Any], let token = entry["oauth_token"] as? String, !token.isEmpty {
                    return token
                }
            }
        }
        return nil
    }
}

struct CopilotUsageCollector: UsageCollecting {
    let provider: Provider = .copilot
    static let cache = LiveCache(freshFor: 60)   // 按月计的额度，最快每分钟查一次

    func collect() async -> UsageSnapshot {
        let token = CopilotCredentials.token()
        return await collectWithCache(.copilot, cache: Self.cache, connected: token != nil) {
            guard let token else { return nil }
            return await fetch(token)
        }
    }

    private func fetch(_ token: String) async -> UsageSnapshot? {
        guard let url = URL(string: "https://api.github.com/copilot_internal/user") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("token \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("vscode/1.96.2", forHTTPHeaderField: "Editor-Version")
        request.setValue("copilot-chat/0.26.7", forHTTPHeaderField: "Editor-Plugin-Version")
        request.setValue("GitHubCopilotChat/0.26.7", forHTTPHeaderField: "User-Agent")
        request.setValue("2025-04-01", forHTTPHeaderField: "X-Github-Api-Version")
        guard let (data, response) = try? await SafeNet.data(for: request) else {
            Self.cache.fail("网络错误", "连接 api.github.com 失败。")
            return nil
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { httpFailure(code, service: "GitHub", cache: Self.cache); return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Self.cache.fail("格式变了", "GitHub 返回的格式和预期不一样。")
            return nil
        }
        let snapshots = json["quota_snapshots"] as? [String: Any] ?? [:]
        func used(_ key: String) -> Double? {
            guard let item = snapshots[key] as? [String: Any] else { return nil }
            if item["unlimited"] as? Bool == true { return nil }
            if let entitlement = item["entitlement"] as? Double, entitlement == 0,
               let remaining = item["remaining"] as? Double, remaining == 0 { return nil }
            guard let remaining = (item["percent_remaining"] as? Double) ?? (item["percent_remaining"] as? Int).map(Double.init) else { return nil }
            return max(0, min(100, 100 - remaining))
        }
        let premium = used("premium_interactions")
        let chat = used("chat")
        guard premium != nil || chat != nil else {
            Self.cache.fail("无限额度", "这个 Copilot 套餐没有可显示的额度上限（不限量或按 token 计费）。")
            return nil
        }
        let reset = parseISODate(json["quota_reset_date"] as? String)
        let plan = (json["copilot_plan"] as? String)?.capitalized
        var snapshot = UsageSnapshot(
            provider: .copilot, isConnected: true,
            dailyPercent: premium ?? chat, weeklyPercent: premium != nil ? chat : nil,
            dailyResetAt: reset, weeklyResetAt: premium != nil ? reset : nil,
            totalTokens: nil, planLabel: plan, updatedAt: Date(), error: nil)
        snapshot.primaryLabel = premium != nil ? "高级" : "对话"
        snapshot.secondaryLabel = "对话"
        return snapshot
    }
}

// MARK: - Cursor（读 Cursor App 自己保存的登录）

/// Cursor App 把登录令牌存在自己的 state.vscdb（SQLite）里，这里只读取。
enum CursorCredentials {
    static let databasePath = DataFiles.expand("~/Library/Application Support/Cursor/User/globalStorage/state.vscdb")

    static func cookie() -> String? {
        guard let token = readValue("cursorAuth/accessToken"), let userID = userID(fromJWT: token) else { return nil }
        return "WorkosCursorSessionToken=\(userID)%3A%3A\(token)"
    }

    private static func readValue(_ key: String) -> String? {
        guard FileManager.default.isReadableFile(atPath: databasePath) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 300)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, "SELECT value FROM ItemTable WHERE key = ? LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, key, -1, transient)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(statement, 0) == SQLITE_TEXT, let text = sqlite3_column_text(statement, 0) {
            return String(cString: text)
        }
        if let blob = sqlite3_column_blob(statement, 0) {
            let count = Int(sqlite3_column_bytes(statement, 0))
            return String(decoding: UnsafeRawBufferPointer(start: blob, count: count), as: UTF8.self)
        }
        return nil
    }

    private static func userID(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = json["sub"] as? String else { return nil }
        return subject.split(separator: "|").last.map(String.init)
    }
}

struct CursorUsageCollector: UsageCollecting {
    let provider: Provider = .cursor
    static let cache = LiveCache(freshFor: 60)   // 按账单周期计，最快每分钟查一次

    func collect() async -> UsageSnapshot {
        let cookie = CursorCredentials.cookie()
        return await collectWithCache(.cursor, cache: Self.cache, connected: cookie != nil) {
            guard let cookie else { return nil }
            return await fetch(cookie)
        }
    }

    private func fetch(_ cookie: String) async -> UsageSnapshot? {
        guard let url = URL(string: "https://cursor.com/api/usage-summary") else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await SafeNet.data(for: request) else {
            Self.cache.fail("网络错误", "连接 cursor.com 失败。")
            return nil
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { httpFailure(code, service: "Cursor", cache: Self.cache); return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Self.cache.fail("格式变了", "Cursor 返回的格式和预期不一样。")
            return nil
        }
        func number(_ value: Any?) -> Double? {
            (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? String).flatMap(Double.init)
        }
        let individual = json["individualUsage"] as? [String: Any]
        let plan = individual?["plan"] as? [String: Any]
        let onDemand = individual?["onDemand"] as? [String: Any]
        // 这些百分比字段本身就是百分数（0.36 表示 0.36%）
        var planPercent = number(plan?["totalPercentUsed"])
        if planPercent == nil, let used = number(plan?["used"]), let limit = number(plan?["limit"]), limit > 0 {
            planPercent = used / limit * 100
        }
        var onDemandPercent: Double?
        if let used = number(onDemand?["used"]), let limit = number(onDemand?["limit"]), limit > 0 {
            onDemandPercent = used / limit * 100
        }
        guard let planPercent else {
            Self.cache.fail("没有额度", "Cursor 没有返回这个账号的套餐用量。")
            return nil
        }
        let reset = parseISODate(json["billingCycleEnd"] as? String)
        let membership = (json["membershipType"] as? String)?.replacingOccurrences(of: "_", with: " ").capitalized
        var snapshot = UsageSnapshot(
            provider: .cursor, isConnected: true,
            dailyPercent: min(100, planPercent), weeklyPercent: onDemandPercent.map { min(100, $0) },
            dailyResetAt: reset, weeklyResetAt: reset,
            totalTokens: nil, planLabel: membership, updatedAt: Date(), error: nil)
        snapshot.primaryLabel = "套餐"
        snapshot.secondaryLabel = "超额"
        return snapshot
    }
}

// MARK: - Kimi（Kimi Code 编程套餐，API Key）

struct KimiUsageCollector: UsageCollecting {
    let provider: Provider = .kimi
    static let cache = LiveCache(freshFor: 20)

    func collect() async -> UsageSnapshot {
        let key = APIKeyStore.key(for: .kimi)
        return await collectWithCache(.kimi, cache: Self.cache, connected: key != nil) {
            guard let key else { return nil }
            return await fetch(key)
        }
    }

    private func fetch(_ key: String) async -> UsageSnapshot? {
        let address = AppConfig.shared.kimiRegion == "intl"
            ? "https://api.kimi.ai/coding/v1/usages"
            : "https://api.kimi.com/coding/v1/usages"
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await SafeNet.data(for: request) else {
            Self.cache.fail("网络错误", "连接 Kimi 失败。")
            return nil
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { httpFailure(code, service: "Kimi", cache: Self.cache); return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let usages = json["usages"] as? [String: Any] else {
            Self.cache.fail("格式变了", "Kimi 返回的格式和预期不一样：\(String(decoding: data.prefix(200), as: UTF8.self))")
            return nil
        }
        func pool(_ name: String) -> (Double, Date?)? {
            guard let item = usages[name] as? [String: Any],
                  let ratio = (item["used_ratio"] as? Double) ?? (item["used_ratio"] as? Int).map(Double.init) else { return nil }
            return (min(1, max(0, ratio)) * 100, parseISODate(item["reset_time"] as? String))
        }
        let session = pool("limit_5h")
        let weekly = pool("limit_7d")
        guard session != nil || weekly != nil else {
            Self.cache.fail("没有额度", "没有找到 Kimi Code 的额度信息，可能这个 Key 没有开通编程套餐。")
            return nil
        }
        let level = ((json["user"] as? [String: Any])?["membership"] as? [String: Any])?["level"] as? String
        let plan: String?
        switch level {
        case "LEVEL_FREE": plan = "Free"
        case "LEVEL_TRIAL": plan = "Trial"
        case "LEVEL_BASIC": plan = "Basic"
        case "LEVEL_INTERMEDIATE": plan = "Plus"
        case "LEVEL_ADVANCED": plan = "Pro"
        default: plan = level?.replacingOccurrences(of: "LEVEL_", with: "").capitalized
        }
        var snapshot = UsageSnapshot(
            provider: .kimi, isConnected: true,
            dailyPercent: (session ?? weekly)?.0, weeklyPercent: session != nil ? weekly?.0 : nil,
            dailyResetAt: (session ?? weekly)?.1, weeklyResetAt: session != nil ? weekly?.1 : nil,
            totalTokens: nil, planLabel: plan, updatedAt: Date(), error: nil)
        snapshot.primaryLabel = session != nil ? "5h" : "W"
        snapshot.secondaryLabel = "W"
        return snapshot
    }
}

// MARK: - MiniMax（编程套餐，API Key）

struct MiniMaxUsageCollector: UsageCollecting {
    let provider: Provider = .minimax
    static let cache = LiveCache(freshFor: 20)

    func collect() async -> UsageSnapshot {
        let key = APIKeyStore.key(for: .minimax)
        return await collectWithCache(.minimax, cache: Self.cache, connected: key != nil) {
            guard let key else { return nil }
            return await fetch(key)
        }
    }

    private func fetch(_ key: String) async -> UsageSnapshot? {
        let address = AppConfig.shared.minimaxRegion == "intl"
            ? "https://api.minimax.io/v1/api/openplatform/coding_plan/remains"
            : "https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains"
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await SafeNet.data(for: request) else {
            Self.cache.fail("网络错误", "连接 MiniMax 失败。")
            return nil
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { httpFailure(code, service: "MiniMax", cache: Self.cache); return nil }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Self.cache.fail("格式变了", "MiniMax 返回的格式和预期不一样。")
            return nil
        }
        let base = json["base_resp"] as? [String: Any]
        if let status = (base?["status_code"] as? Int), status != 0 {
            Self.cache.fail("登录失效", "MiniMax 返回：\(base?["status_msg"] as? String ?? "错误 \(status)")。请检查 API Key。")
            return nil
        }
        let container = (json["data"] as? [String: Any]) ?? json
        guard let remains = (container["model_remains"] as? [[String: Any]])?.first else {
            Self.cache.fail("没有额度", "没有找到 MiniMax 编程套餐的额度信息。")
            return nil
        }
        func number(_ key: String) -> Double? {
            (remains[key] as? Double) ?? (remains[key] as? Int).map(Double.init)
        }
        // 注意：MiniMax 的 *_usage_count 实际上是“剩余次数”
        func usedPercent(remainingPercent: String, total: String, remaining: String) -> Double? {
            if let percent = number(remainingPercent) { return max(0, min(100, 100 - percent)) }
            guard let total = number(total), total > 0, let left = number(remaining) else { return nil }
            return max(0, min(100, (total - left) / total * 100))
        }
        func date(_ key: String) -> Date? {
            guard let raw = number(key) else { return nil }
            return Date(timeIntervalSince1970: raw > 1_000_000_000_000 ? raw / 1000 : raw)
        }
        let interval = usedPercent(remainingPercent: "current_interval_remaining_percent",
                                   total: "current_interval_total_count", remaining: "current_interval_usage_count")
        let weekly = usedPercent(remainingPercent: "current_weekly_remaining_percent",
                                 total: "current_weekly_total_count", remaining: "current_weekly_usage_count")
        guard interval != nil || weekly != nil else {
            Self.cache.fail("没有额度", "MiniMax 没有返回可用的额度数字。")
            return nil
        }
        var snapshot = UsageSnapshot(
            provider: .minimax, isConnected: true,
            dailyPercent: interval ?? weekly, weeklyPercent: interval != nil ? weekly : nil,
            dailyResetAt: interval != nil ? date("end_time") : date("weekly_end_time"),
            weeklyResetAt: interval != nil ? date("weekly_end_time") : nil,
            totalTokens: nil, planLabel: nil, updatedAt: Date(), error: nil)
        snapshot.primaryLabel = interval != nil ? "5h" : "W"
        snapshot.secondaryLabel = "W"
        return snapshot
    }
}
