import Foundation

/// 加固补丁：所有出网请求的唯一入口。
///
/// - 只允许 HTTPS + GET，且主机必须在白名单里（Anthropic / OpenAI 官方用量接口）。
/// - 重定向到白名单以外的主机会被拦截，Bearer token 不会被带去别处。
/// - 使用 ephemeral 会话：不存 Cookie、不缓存、不保存凭证。
/// - 被拦截的请求会写到 stderr，方便你在日志里发现异常。
///
/// 源码里不应再出现 `URLSession.shared`；可用
/// `grep -rn "URLSession.shared" Sources/` 自查。
enum SafeNet {
    static let allowedHosts: Set<String> = [
        "api.anthropic.com",
        "chatgpt.com",
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
              allowedHosts.contains(host),
              (request.httpMethod ?? "GET").uppercased() == "GET",
              request.httpBody == nil,
              request.httpBodyStream == nil else {
            return false
        }
        return true
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
