import AVFoundation
import CoreLocation
import Foundation

/// One-shot position fix using the iPhone's GPS. Works in Airplane Mode (GPS keeps running).
/// The position is only compared with places the user has named, on the device;
/// it is never looked up online or sent anywhere.
@MainActor
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?
    private var authContinuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var isDenied: Bool {
        let s = manager.authorizationStatus
        return s == .denied || s == .restricted
    }

    /// Returns the current position, or nil if unavailable within `timeout` seconds
    /// (e.g. indoors without a GPS view of the sky).
    func currentLocation(timeout: TimeInterval = 20) async -> CLLocation? {
        if manager.authorizationStatus == .notDetermined {
            await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                authContinuation = c
                manager.requestWhenInUseAuthorization()
            }
        }
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { return nil }

        // A recent fix is good enough (same building).
        if let last = manager.location, Date().timeIntervalSince(last.timestamp) < 300,
           last.horizontalAccuracy >= 0, last.horizontalAccuracy < 500 {
            return last
        }

        return await withCheckedContinuation { (c: CheckedContinuation<CLLocation?, Never>) in
            continuation?.resume(returning: nil)
            continuation = c
            manager.requestLocation()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(timeout))
                self?.finish(with: nil)
            }
        }
    }

    private func finish(with location: CLLocation?) {
        continuation?.resume(returning: location)
        continuation = nil
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let best = locations.last
        Task { @MainActor in self.finish(with: best) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.finish(with: nil) }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard manager.authorizationStatus != .notDetermined else { return }
            self.authContinuation?.resume()
            self.authContinuation = nil
        }
    }
}

/// Reads the place a recording was made, if the file carries it (e.g. iPhone Voice Memos / Camera).
enum RecordingLocation {
    static func coordinates(of url: URL) async -> (Double, Double)? {
        let asset = AVURLAsset(url: url)
        guard let items = try? await asset.load(.metadata) else { return nil }
        for item in items {
            let isLocation = item.identifier == .quickTimeMetadataLocationISO6709
                || item.commonKey == .commonKeyLocation
            guard isLocation, let value = try? await item.load(.stringValue) else { continue }
            if let parsed = parseISO6709(value) { return parsed }
        }
        return nil
    }

    /// "+33.7800-117.9500+010.000/" → (33.78, -117.95)
    static func parseISO6709(_ s: String) -> (Double, Double)? {
        var numbers: [Double] = []
        var current = ""
        for ch in s {
            if (ch == "+" || ch == "-") && !current.isEmpty {
                if let v = Double(current) { numbers.append(v) }
                current = String(ch)
            } else if ch == "/" {
                break
            } else {
                current.append(ch)
            }
        }
        if let v = Double(current) { numbers.append(v) }
        guard numbers.count >= 2, abs(numbers[0]) <= 90, abs(numbers[1]) <= 180 else { return nil }
        return (numbers[0], numbers[1])
    }
}
