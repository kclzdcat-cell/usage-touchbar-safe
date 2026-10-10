import Foundation

/// 加固补丁：所有出网请求的唯一入口。
///
/// - 只允许 HTTPS。GET 请求的主机必须在白名单里；POST 只允许发往下面列出的几个
///   具体接口（Gemini 的额度查询和登录续期），其他任何 POST 都会被拦截。
/// - 重定向到白名单以外的主机会被拦截，Bearer token 不会被带去别处。
/// - 使用 ephemeral 会话：不存 Cookie、不缓存、不保存凭证。
/// - 被拦截的请求会写到 stderr，方便你在日志里发现异常。
///
/// 源码里不应再出现 `URLSession.shared`；可用
/// `grep -rn "URLSession.shared" Sources/` 自查。
enum SafeNet {
    /// 允许 GET 的主机：各家官方的用量查询接口
    static let allowedHosts: Set<String> = [
        "api.anthropic.com",        // Claude
        "chatgpt.com",              // Codex
        "open.bigmodel.cn",         // GLM（国内）
        "api.z.ai",                 // GLM（国际）
        "api.github.com",           // GitHub Copilot
        "cursor.com",               // Cursor
        "api.kimi.com",             // Kimi（国内）
        "api.kimi.ai",              // Kimi（国际）
        "api.minimaxi.com",         // MiniMax（国内）
        "api.minimax.io",           // MiniMax（国际）
    ]

    /// 允许 POST 的具体接口（主机 + 路径）
    static let allowedPosts: Set<String> = [
        "cloudcode-pa.googleapis.com/v1internal:loadCodeAssist",     // Gemini：查询账号套餐
        "cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota",  // Gemini：查询额度
        "oauth2.googleapis.com/token",                               // Gemini：登录续期
    ]

    private final class RedirectGuard: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            guard SafeNet.isAllowed(request) else {
                SafeNet.logBlocked(request, reason: "redirect")
                return nil
            }
            return request
        }
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: config, delegate: RedirectGuard(), delegateQueue: nil)
    }()

    static func isAllowed(_ request: URLRequest) -> Bool {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              request.httpBodyStream == nil else {
            return false
        }
        switch (request.httpMethod ?? "GET").uppercased() {
        case "GET":
            return allowedHosts.contains(host) && request.httpBody == nil
        case "POST":
            return allowedPosts.contains(host + url.path)
        default:
            return false
        }
    }

    // MARK: 本机 Antigravity

    /// Antigravity 本机语言服务里查询额度的接口（只允许这一个路径）
    static let antigravityStatusPath = "/exa.language_server_pb.LanguageServerService/GetUserStatus"

    /// 只接受 127.0.0.1 的自签名证书（Antigravity 本机服务用的就是自签名证书）；
    /// 其他任何主机照常严格校验证书。
    private final class LocalTrust: NSObject, URLSessionTaskDelegate, Sendable {
        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge
        ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            guard challenge.protectionSpace.host == "127.0.0.1",
                  challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust else {
                return (.performDefaultHandling, nil)
            }
            return (.useCredential, URLCredential(trust: trust))
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            nil   // 本机请求不允许任何跳转
        }
    }

    private static let localSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCredentialStorage = nil
        config.urlCache = nil
        config.connectionProxyDictionary = [:]   // 本机请求不走代理
        return URLSession(configuration: config, delegate: LocalTrust(), delegateQueue: nil)
    }()

    /// 发往本机 Antigravity 的请求：必须是 127.0.0.1、POST、固定路径。
    static func localData(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = request.url,
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host == "127.0.0.1",
              url.path == antigravityStatusPath,
              (request.httpMethod ?? "GET").uppercased() == "POST" else {
            logBlocked(request, reason: "local")
            throw URLError(.badURL)
        }
        return try await localSession.data(for: request)
    }

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard isAllowed(request) else {
            logBlocked(request, reason: "request")
            throw URLError(.badURL)
        }
        return try await session.data(for: request)
    }

    fileprivate static func logBlocked(_ request: URLRequest, reason: String) {
        let target = request.url.map { "\($0.scheme ?? "?")://\($0.host ?? "?")\($0.path)" } ?? "?"
        FileHandle.standardError.write(Data("[SafeNet] blocked \(reason): \(request.httpMethod ?? "GET") \(target)\n".utf8))
    }
}
