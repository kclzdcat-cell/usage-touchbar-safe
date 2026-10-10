import Foundation

// MARK: - 共用：带退避的实时读取状态

/// 每个新服务的读取状态：成功缓存一段时间，失败后退避，避免频繁请求被限流。
final class LiveCache: @unchecked Sendable {
    struct Status {
        let ok: Bool
        let short: String
        let detail: String
        let at: Date
    }

    private let lock = NSLock()
    private var snapshot: UsageSnapshot?
    private var snapshotAt: Date?
    private var status: Status?
    private let freshFor: TimeInterval

    init(freshFor: TimeInterval) {
        self.freshFor = freshFor
    }

    func fresh() -> UsageSnapshot? {
        lock.lock(); defer { lock.unlock() }
        guard let snapshot, let snapshotAt, Date().timeIntervalSince(snapshotAt) < freshFor else { return nil }
        return snapshot
    }

    func last() -> UsageSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }

    func store(_ value: UsageSnapshot) {
        lock.lock(); defer { lock.unlock() }
        snapshot = value
        snapshotAt = Date()
        status = Status(ok: true, short: "正常", detail: "实时读取正常。", at: Date())
    }

    func fail(_ short: String, _ detail: String) {
        lock.lock(); defer { lock.unlock() }
        status = Status(ok: false, short: short, detail: detail, at: Date())
    }

    func lastStatus() -> Status? {
        lock.lock(); defer { lock.unlock() }
        return status
    }

    /// 刚失败过就先不重试（限流 5 分钟，其他 1 分钟）。
    var inBackoff: Bool {
        lock.lock(); defer { lock.unlock() }
        guard let status, !status.ok else { return false }
        let wait: TimeInterval = status.short == "被限流" ? 300 : 60
        return Date().timeIntervalSince(status.at) < wait
    }

    func flush() {
        lock.lock(); defer { lock.unlock() }
        snapshot = nil
        snapshotAt = nil
        status = nil
    }
}

/// 把 HTTP 状态码翻译成简短原因。
private func describeHTTP(_ code: Int, service: String) -> (String, String) {
    switch code {
    case 401, 403: return ("登录失效", "\(service) 拒绝了这个登录（HTTP \(code)），请重新登录或检查 API Key。")
    case 429: return ("被限流", "请求太频繁，被暂时限流（HTTP 429），稍后会自动恢复。")
    default: return ("HTTP \(code)", "\(service) 接口返回了 HTTP \(code)。")
    }
}

// MARK: - GLM（智谱 GLM Coding Plan，ZCode 使用同一份额度）

/// GLM 的 API Key 来源：
/// 1. 设置窗口里填的 Key（保存在 ~/.config/usage-touchbar/glm-key，权限 600，只有你自己的账户能读）
/// 2. 如果没填，自动读 Claude Code 的 ~/.claude/settings.json：用 GLM Coding Plan 接 Claude Code 时，
///    里面的 ANTHROPIC_BASE_URL 指向智谱，ANTHROPIC_AUTH_TOKEN 就是 Key
enum GLMCredentials {
    struct Credentials {
        let key: String
        let host: String
    }

    static let keyPath = DataFiles.expand("~/.config/usage-touchbar/glm-key")
    static let cnHost = "open.bigmodel.cn"
    static let intlHost = "api.z.ai"

    private static let lock = NSLock()
    private nonisolated(unsafe) static var cached: (Credentials?, Date)?

    static func current() -> Credentials? {
        lock.lock(); defer { lock.unlock() }
        if let cached, Date().timeIntervalSince(cached.1) < 30 { return cached.0 }
        let value = read()
        cached = (value, Date())
        return value
    }

    static func invalidate() {
        lock.lock(); defer { lock.unlock() }
        cached = nil
    }

    private static func read() -> Credentials? {
        let region = AppConfig.shared.glmRegion ?? "cn"
        let configuredHost = region == "intl" ? intlHost : cnHost
        if let key = savedKey() {
            return Credentials(key: key, host: configuredHost)
        }
        // 从 Claude Code 的设置里找
        guard let data = FileManager.default.contents(atPath: DataFiles.expand("~/.claude/settings.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let env = json["env"] as? [String: Any],
              let base = env["ANTHROPIC_BASE_URL"] as? String,
              let token = (env["ANTHROPIC_AUTH_TOKEN"] as? String) ?? (env["ANTHROPIC_API_KEY"] as? String),
              !token.isEmpty else { return nil }
        if base.contains("api.z.ai") { return Credentials(key: token, host: intlHost) }
        if base.contains("bigmodel.cn") { return Credentials(key: token, host: cnHost) }
        return nil
    }

    static func savedKey() -> String? {
        guard let text = try? String(contentsOfFile: keyPath, encoding: .utf8) else { return nil }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    /// 保存 / 清除设置里填的 Key（文件权限 600）。
    @discardableResult
    static func saveKey(_ key: String?) -> Bool {
        defer { invalidate() }
        let fm = FileManager.default
        guard let key = key?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty else {
            try? fm.removeItem(atPath: keyPath)
            return true
        }
        try? fm.createDirectory(atPath: DataFiles.expand("~/.config/usage-touchbar"), withIntermediateDirectories: true)
        guard fm.createFile(atPath: keyPath, contents: Data(key.utf8), attributes: [.posixPermissions: 0o600]) else {
            return false
        }
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyPath)
        return true
    }

    /// 给设置窗口显示用：Key 从哪来。
    static var sourceDescription: String {
        if savedKey() != nil { return "使用设置里填写的 API Key" }
        if current() != nil { return "已自动从 Claude Code 的设置（~/.claude/settings.json）读取 API Key" }
        return "未找到 API Key：在下面填写，或在 Claude Code 里配置 GLM Coding Plan"
    }
}

struct GLMUsageCollector: UsageCollecting {
    let provider: Provider = .glm
    static let cache = LiveCache(freshFor: 2 * 60)

    private struct Response: Decodable {
        let code: Int?
        let msg: String?
        let success: Bool?
        let data: Payload?
    }
    private struct Payload: Decodable {
        let limits: [Limit]?
        let level: String?
    }
    private struct Limit: Decodable {
        let type: String?
        let unit: Int?
        let number: Int?
        let percentage: Double?
        let nextResetTime: Int64?
    }

    func collect() async -> UsageSnapshot {
        guard let credentials = GLMCredentials.current() else { return .disconnected(.glm) }
        if let fresh = Self.cache.fresh() { return fresh }
        if !Self.cache.inBackoff, let live = await fetch(credentials) {
            Self.cache.store(live)
            return live
        }
        if let stale = Self.cache.last() { return stale }
        return .failure(.glm, message: Self.cache.lastStatus()?.short ?? "读取失败")
    }

    private func fetch(_ credentials: GLMCredentials.Credentials) async -> UsageSnapshot? {
        // 地址写死成常量（不拼接），安全自查才能确认只会连这两个地址
        let address = credentials.host == GLMCredentials.intlHost
            ? "https://api.z.ai/api/monitor/usage/quota/limit"
            : "https://open.bigmodel.cn/api/monitor/usage/quota/limit"
        guard let url = URL(string: address) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        // 智谱的这个接口不用 "Bearer " 前缀
        request.setValue(credentials.key, forHTTPHeaderField: "Authorization")
        request.setValue("zh-CN,zh", forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await SafeNet.data(for: request)
        } catch {
            Self.cache.fail("网络错误", "连接 \(credentials.host) 失败：\(error.localizedDescription)")
            return nil
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let (short, detail) = describeHTTP(code, service: "智谱")
            Self.cache.fail(short, detail)
            return nil
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            Self.cache.fail("格式变了", "智谱接口返回的格式和预期不一样：\(String(decoding: data.prefix(200), as: UTF8.self))")
            return nil
        }
        guard decoded.success != false, let payload = decoded.data else {
            Self.cache.fail("登录失效", "智谱返回：\(decoded.msg ?? "未知错误")（code \(decoded.code ?? 0)）。请检查 API Key 是否正确、是否开通了 GLM Coding Plan。")
            return nil
        }

        let limits = payload.limits ?? []
        // 老套餐：TOKENS_LIMIT 是 5 小时额度；新套餐：CREDIT_LIMIT，最短窗口是 5 小时、最长是每周
        let credits = limits.filter { $0.type == "CREDIT_LIMIT" }
            .sorted { ($0.unit ?? 0, $0.number ?? 0) < ($1.unit ?? 0, $1.number ?? 0) }
        let primary = limits.first { $0.type == "TOKENS_LIMIT" } ?? credits.first
        let secondary = credits.count > 1 ? credits.last : nil
        guard let primary else {
            Self.cache.fail("没有额度", "没有找到 GLM Coding Plan 的额度信息，可能这个 Key 没有开通编程套餐。")
            return nil
        }
        let date: (Int64?) -> Date? = { ms in ms.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) } }

        var snapshot = UsageSnapshot(
            provider: .glm,
            isConnected: true,
            dailyPercent: primary.percentage,
            weeklyPercent: secondary?.percentage,
            dailyResetAt: date(primary.nextResetTime),
            weeklyResetAt: date(secondary?.nextResetTime),
            totalTokens: nil,
            planLabel: payload.level.map { $0.capitalized },
            updatedAt: Date(),
            error: nil
        )
        snapshot.primaryLabel = "5h"
        snapshot.secondaryLabel = "W"
        return snapshot
    }
}

// MARK: - Gemini（Gemini CLI 的 Google 账号登录）

/// 读 Gemini CLI 保存的登录信息 ~/.gemini/oauth_creds.json（只读，从不改写这个文件）。
/// 访问令牌一小时就过期；过期时用里面的 refresh_token 在内存里换一个新的，
/// 换令牌需要的应用 ID 从本机安装的 Gemini CLI 里读取（不内置任何密钥）。
enum GeminiCredentials {
    static let credsPath = DataFiles.expand("~/.gemini/oauth_creds.json")

    private struct File: Decodable {
        let access_token: String?
        let refresh_token: String?
        let expiry_date: Double?
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var memoryToken: (token: String, expiry: Date)?
    private nonisolated(unsafe) static var clientInfo: (id: String, secret: String)??

    static var isLoggedIn: Bool { FileManager.default.fileExists(atPath: credsPath) }

    enum TokenResult {
        case ok(String)
        case failed(short: String, detail: String)
    }

    static func accessToken() async -> TokenResult {
        if let cached = cachedToken() { return .ok(cached) }
        guard let data = FileManager.default.contents(atPath: credsPath),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            return .failed(short: "未登录", detail: "没有找到 Gemini CLI 的登录信息。在终端运行 gemini，用 Google 账号登录一次。")
        }
        if let token = file.access_token, let expiry = file.expiry_date,
           Date(timeIntervalSince1970: expiry / 1000) > Date().addingTimeInterval(60) {
            return .ok(token)
        }
        guard let refresh = file.refresh_token else {
            return .failed(short: "登录过期", detail: "Gemini CLI 的登录已过期。在终端运行一次 gemini 即可刷新。")
        }
        guard let client = installedClient() else {
            return .failed(short: "登录过期", detail: "Gemini CLI 的登录已过期，而且没找到本机安装的 Gemini CLI 来自动续期。在终端运行一次 gemini 即可刷新。")
        }
        return await refreshToken(refresh, client: client)
    }

    private static func cachedToken() -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let memoryToken, memoryToken.expiry > Date().addingTimeInterval(60) else { return nil }
        return memoryToken.token
    }

    private static func refreshToken(_ refresh: String, client: (id: String, secret: String)) async -> TokenResult {
        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            return .failed(short: "读取失败", detail: "内部错误。")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let form = [
            "client_id": client.id,
            "client_secret": client.secret,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        ].map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")" }
            .joined(separator: "&")
        request.httpBody = Data(form.utf8)

        struct TokenResponse: Decodable {
            let access_token: String?
            let expires_in: Double?
        }
        guard let (data, response) = try? await SafeNet.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data),
              let token = decoded.access_token else {
            return .failed(short: "登录过期", detail: "Gemini 的登录续期失败。在终端运行一次 gemini 重新登录即可。")
        }
        lock.lock()
        memoryToken = (token, Date().addingTimeInterval(decoded.expires_in ?? 3000))
        lock.unlock()
        return .ok(token)
    }

    /// 从本机安装的 Gemini CLI 文件里读出它的 OAuth 应用 ID（这是 Gemini CLI 开源代码里公开的值）。
    private static func installedClient() -> (id: String, secret: String)? {
        lock.lock()
        if let clientInfo { lock.unlock(); return clientInfo }
        lock.unlock()

        var found: (id: String, secret: String)?
        let fm = FileManager.default
        let home = DataFiles.home()
        let roots = [
            "/opt/homebrew/lib/node_modules/@google",
            "/usr/local/lib/node_modules/@google",
            "\(home)/.npm-global/lib/node_modules/@google",
            "\(home)/.bun/install/global/node_modules/@google",
            "/opt/homebrew/Cellar/gemini-cli",
            "/usr/local/Cellar/gemini-cli",
        ]
        search: for root in roots where fm.fileExists(atPath: root) {
            guard let walker = fm.enumerator(atPath: root) else { continue }
            var visited = 0
            while let relative = walker.nextObject() as? String, visited < 40_000 {
                visited += 1
                guard relative.hasSuffix("oauth2.js") || relative.hasSuffix("gemini.js") else { continue }
                let path = "\(root)/\(relative)"
                guard let text = try? String(contentsOfFile: path, encoding: .utf8),
                      let id = firstMatch(#"OAUTH_CLIENT_ID\s*=\s*['"]([^'"]+)['"]"#, in: text),
                      let secret = firstMatch(#"OAUTH_CLIENT_SECRET\s*=\s*['"]([^'"]+)['"]"#, in: text) else { continue }
                found = (id, secret)
                break search
            }
        }
        lock.lock()
        clientInfo = .some(found)
        lock.unlock()
        return found
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range])
    }
}

struct GeminiUsageCollector: UsageCollecting {
    let provider: Provider = .gemini
    static let cache = LiveCache(freshFor: 3 * 60)
    private static let base = "https://cloudcode-pa.googleapis.com/v1internal"

    private static let projectLock = NSLock()
    private nonisolated(unsafe) static var project: (id: String?, tier: String?)?

    func collect() async -> UsageSnapshot {
        guard GeminiCredentials.isLoggedIn else { return .disconnected(.gemini) }
        if let fresh = Self.cache.fresh() { return fresh }
        if !Self.cache.inBackoff, let live = await fetch() {
            Self.cache.store(live)
            return live
        }
        if let stale = Self.cache.last() { return stale }
        return .failure(.gemini, message: Self.cache.lastStatus()?.short ?? "读取失败")
    }

    private func post(_ method: String, body: [String: Any], token: String) async -> (Data, Int)? {
        guard let url = URL(string: "\(Self.base):\(method)"),
              let json = try? JSONSerialization.data(withJSONObject: body) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = json
        do {
            let (data, response) = try await SafeNet.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            Self.cache.fail("网络错误", "连接 Google 失败：\(error.localizedDescription)")
            return nil
        }
    }

    private func fetch() async -> UsageSnapshot? {
        let token: String
        switch await GeminiCredentials.accessToken() {
        case .ok(let value): token = value
        case .failed(let short, let detail):
            Self.cache.fail(short, detail)
            return nil
        }

        // 第一次先查一下账号对应的项目和套餐（之后缓存）
        Self.projectLock.lock()
        var known = Self.project
        Self.projectLock.unlock()
        if known == nil {
            guard let (data, code) = await post("loadCodeAssist",
                                                body: ["metadata": ["ideType": "GEMINI_CLI", "pluginType": "GEMINI"]],
                                                token: token) else { return nil }
            guard code == 200 else {
                let (short, detail) = describeHTTP(code, service: "Google")
                Self.cache.fail(short, detail)
                return nil
            }
            let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let projectID = json?["cloudaicompanionProject"] as? String
                ?? (json?["cloudaicompanionProject"] as? [String: Any])?["id"] as? String
            let tier = (json?["currentTier"] as? [String: Any])?["id"] as? String
            known = (projectID, tier)
            Self.projectLock.lock()
            Self.project = known
            Self.projectLock.unlock()
        }

        var body: [String: Any] = [:]
        if let id = known?.id { body["project"] = id }
        guard let (data, code) = await post("retrieveUserQuota", body: body, token: token) else { return nil }
        guard code == 200 else {
            let (short, detail) = describeHTTP(code, service: "Google")
            Self.cache.fail(short, detail)
            return nil
        }
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let buckets = json["buckets"] as? [[String: Any]], !buckets.isEmpty else {
            Self.cache.fail("格式变了", "Google 额度接口返回的格式和预期不一样：\(String(decoding: data.prefix(200), as: UTF8.self))")
            return nil
        }

        // 每个模型一个额度桶：Pro 系列作为主要显示、Flash 系列作为次要显示，各取剩余最少的那个
        struct Bucket { let used: Double; let reset: Date? }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        func parse(_ item: [String: Any]) -> Bucket? {
            guard let remaining = item["remainingFraction"] as? Double else { return nil }
            let stamp = item["resetTime"] as? String
            let reset = stamp.flatMap { iso.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            return Bucket(used: max(0, min(100, (1 - remaining) * 100)), reset: reset)
        }
        func worst(_ keyword: String) -> Bucket? {
            buckets.filter { (($0["modelId"] as? String) ?? "").lowercased().contains(keyword) }
                .compactMap(parse)
                .max { $0.used < $1.used }
        }
        let pro = worst("pro")
        let flash = worst("flash")
        let fallback = buckets.compactMap(parse).max { $0.used < $1.used }

        let plan: String?
        switch known?.tier {
        case "standard-tier": plan = "Paid"
        case "free-tier": plan = "Free"
        case "legacy-tier": plan = "Legacy"
        case .some(let other): plan = other.replacingOccurrences(of: "-tier", with: "").capitalized
        case .none: plan = nil
        }

        let primary = pro ?? fallback
        var snapshot = UsageSnapshot(
            provider: .gemini,
            isConnected: true,
            dailyPercent: primary?.used,
            weeklyPercent: pro != nil ? flash?.used : nil,
            dailyResetAt: primary?.reset,
            weeklyResetAt: pro != nil ? flash?.reset : nil,
            totalTokens: nil,
            planLabel: plan,
            updatedAt: Date(),
            error: nil
        )
        snapshot.primaryLabel = pro != nil ? "Pro" : "额度"
        snapshot.secondaryLabel = "Flash"
        return snapshot
    }
}
