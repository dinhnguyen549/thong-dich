import SwiftUI
import ThongDichKit

@main
struct ThongDichApp: App {
    init() {
        // Strictly offline: refuse every web request made through the standard URL system.
        // (The app has no networking code; this is a second lock on the door.)
        URLProtocol.registerClass(OfflineGuard.self)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

/// Fails any http(s) request immediately with "not connected to the internet".
final class OfflineGuard: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https" || scheme == "ws" || scheme == "wss"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}
