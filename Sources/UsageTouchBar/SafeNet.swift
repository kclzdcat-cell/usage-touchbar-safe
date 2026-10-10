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
