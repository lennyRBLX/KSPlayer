//
//  NetworkUtilities.swift
//  KSPlayer
//
//  HTTP networking utilities providing the networking foundation
//  for media service API communication.
//

import Foundation

// MARK: - URLRedirectHandler

/// Intercepts HTTP redirects for URL manipulation or blocking.
/// Binary address: 0x10095995c
public final class URLRedirectHandler: NSObject, URLSessionTaskDelegate {
    /// Redirect callback. Receives (originalURL, newURL) and returns:
    /// - A modified URL to redirect to, or
    /// - nil to block the redirect entirely.
    public var onRedirect: ((URL, URL) -> URL?)?

    public override init() {
        super.init()
    }

    public func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let onRedirect,
           let originalURL = task.originalRequest?.url,
           let newURL = request.url
        {
            if let modified = onRedirect(originalURL, newURL) {
                var newReq = request
                newReq.url = modified
                completionHandler(newReq)
            } else {
                // Block redirect
                completionHandler(nil)
            }
        } else {
            // Allow redirect as-is
            completionHandler(request)
        }
    }
}

// MARK: - DataTaskDelegate

/// URLSession delegate with progress tracking for data tasks.
/// Binary address: 0x100959dc8
public final class DataTaskDelegate: NSObject, URLSessionDataDelegate {
    /// Called when new data is received.
    public var onReceiveData: ((Data) -> Void)?
    /// Called when the task completes (with optional error).
    public var onComplete: ((Error?) -> Void)?
    /// Called with progress updates: (bytesReceived, totalExpected).
    /// totalExpected is -1 when the content length is unknown.
    public var onProgress: ((Int64, Int64) -> Void)?

    private var receivedData = Data()
    private var expectedLength: Int64 = 0

    public override init() {
        super.init()
    }

    public func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        expectedLength = response.expectedContentLength
        completionHandler(.allow)
    }

    public func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive data: Data
    ) {
        receivedData.append(data)
        onReceiveData?(data)
        onProgress?(Int64(receivedData.count), expectedLength)
    }

    public func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        onComplete?(error)
    }
}

// MARK: - AlamofireDataLoader

/// HTTP networking singleton for media service API communication.
/// Binary singleton at 0x1041F2DF0.
///
/// The Forward binary uses Alamofire internally, but this implementation
/// uses URLSession directly. Alamofire can be added later when media
/// services are built out.
public final class AlamofireDataLoader: @unchecked Sendable {
    public static let shared = AlamofireDataLoader()

    private let session: URLSession
    private var disabledHosts: Set<String> = []
    private let lock = NSLock()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpMaximumConnectionsPerHost = 6
        session = URLSession(configuration: config)
    }

    /// Perform an HTTP GET request.
    /// - Parameters:
    ///   - url: The request URL.
    ///   - headers: Optional HTTP headers to include.
    /// - Returns: The response data and URLResponse.
    /// - Throws: An error if the host is disabled or the request fails.
    public func request(_ url: URL, headers: [String: String]? = nil) async throws -> (Data, URLResponse) {
        if isHostDisabled(url.host ?? "") {
            throw URLError(.cancelled, userInfo: [
                NSLocalizedDescriptionKey: "Host \(url.host ?? "") is disabled",
            ])
        }
        var request = URLRequest(url: url)
        if let headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        return try await session.data(for: request)
    }

    /// Check whether a host has been disabled.
    /// - Parameter host: The hostname to check.
    /// - Returns: true if the host is currently disabled.
    public func isHostDisabled(_ host: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return disabledHosts.contains(host)
    }

    /// Disable requests to a specific host.
    /// - Parameter host: The hostname to disable.
    public func disableHost(_ host: String) {
        lock.lock()
        defer { lock.unlock() }
        disabledHosts.insert(host)
    }

    /// Re-enable requests to a previously disabled host.
    /// - Parameter host: The hostname to enable.
    public func enableHost(_ host: String) {
        lock.lock()
        defer { lock.unlock() }
        disabledHosts.remove(host)
    }
}
