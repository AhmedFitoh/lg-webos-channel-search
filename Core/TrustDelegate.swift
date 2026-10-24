import Foundation

/// Accepts the LG webOS TV's self-signed TLS certificate strictly for the saved TV host.
/// Any challenge for a different host uses standard system trust evaluation.
public final class TrustDelegate: NSObject, URLSessionDelegate, Sendable {
    public let allowedHost: String

    public init(allowedHost: String) {
        self.allowedHost = allowedHost.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              !allowedHost.isEmpty,
              challenge.protectionSpace.host.caseInsensitiveCompare(allowedHost) == .orderedSame,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}
