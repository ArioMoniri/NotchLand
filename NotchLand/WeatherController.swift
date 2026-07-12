//
//  WeatherController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  CoreLocation + Open-Meteo backed source for the current local weather shown
//  in the notch. Uses the free, key-less Open-Meteo forecast API. Extremely
//  defensive: every network / decode / location failure surfaces as an error
//  message and never crashes.
//

import Combine
import CoreLocation
import Foundation

@MainActor
final class WeatherController: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Weather: Equatable {
        let temperatureC: Double
        let apparentC: Double?
        let code: Int
        let isDay: Bool
        let locationName: String?

        /// SF Symbol name mapping Open-Meteo WMO weather codes to system icons.
        var sfSymbol: String {
            switch code {
            case 0:
                return isDay ? "sun.max" : "moon.stars"
            case 1, 2, 3:
                return isDay ? "cloud.sun" : "cloud"
            case 45, 48:
                return "cloud.fog"
            case 51...67:
                return "cloud.rain"
            case 71...77:
                return "cloud.snow"
            case 80...82:
                return "cloud.heavyrain"
            case 95...99:
                return "cloud.bolt.rain"
            default:
                return "cloud"
            }
        }

        /// Rounded temperature with a degree sign, e.g. "21°".
        var temperatureString: String {
            "\(Int(temperatureC.rounded()))°"
        }
    }

    @Published private(set) var weather: Weather?
    @Published private(set) var errorMessage: String?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus

    private static let refreshInterval: TimeInterval = 30 * 60

    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var refreshTimer: Timer?
    private var fetchTask: Task<Void, Never>?

    override init() {
        authorizationStatus = locationManager.authorizationStatus
        super.init()
    }

    func start() {
        locationManager.delegate = self
        authorizationStatus = locationManager.authorizationStatus

        switch authorizationStatus {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            locationManager.requestLocation()
        default:
            break
        }

        // Use a cached fix immediately if CoreLocation already has one.
        if let last = locationManager.location {
            fetch(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        }

        startRefreshTimer()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        fetchTask?.cancel()
        fetchTask = nil
    }

    func refresh() {
        guard isAuthorized else { return }
        locationManager.requestLocation()
    }

    private var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .authorizedAlways:
            return true
        default:
            return false
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didUpdateLocations locations: [CLLocation]
    ) {
        guard let location = locations.first else { return }
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        Task { @MainActor [weak self] in
            self?.fetch(latitude: latitude, longitude: longitude)
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.handleAuthorizationChange(status)
        }
    }

    // Retained for older delegate dispatch; forwards to the shared handler.
    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didChangeAuthorization status: CLAuthorizationStatus
    ) {
        Task { @MainActor [weak self] in
            self?.handleAuthorizationChange(status)
        }
    }

    nonisolated func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: Error
    ) {
        let description = error.localizedDescription
        Task { @MainActor [weak self] in
            self?.errorMessage = description
        }
    }

    private func handleAuthorizationChange(_ status: CLAuthorizationStatus) {
        authorizationStatus = status
        switch status {
        case .authorized, .authorizedAlways:
            errorMessage = nil
            locationManager.requestLocation()
        case .denied, .restricted:
            errorMessage = "Location access is not permitted."
        default:
            break
        }
    }

    // MARK: - Fetching

    private func fetch(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite else { return }

        fetchTask?.cancel()
        fetchTask = Task { [weak self] in
            let name = await Self.reverseGeocodeName(
                latitude: latitude,
                longitude: longitude
            )

            guard let url = Self.forecastURL(latitude: latitude, longitude: longitude) else {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "Could not build weather request."
                }
                return
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)

                if let http = response as? HTTPURLResponse,
                   !(200...299).contains(http.statusCode) {
                    await MainActor.run { [weak self] in
                        self?.errorMessage = "Weather service returned \(http.statusCode)."
                    }
                    return
                }

                let decoded = try JSONDecoder().decode(ForecastResponse.self, from: data)
                let current = decoded.current

                let weather = Weather(
                    temperatureC: current.temperature_2m,
                    apparentC: current.apparent_temperature,
                    code: current.weather_code,
                    isDay: current.is_day != 0,
                    locationName: name
                )

                if Task.isCancelled { return }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.weather = weather
                    self.errorMessage = nil
                }
            } catch is CancellationError {
                // Superseded by a newer fetch; ignore.
            } catch {
                let description = error.localizedDescription
                await MainActor.run { [weak self] in
                    self?.errorMessage = description
                }
            }
        }
    }

    private static func forecastURL(latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(
                name: "current",
                value: "temperature_2m,apparent_temperature,is_day,weather_code"
            ),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        return components?.url
    }

    /// Best-effort reverse geocode. Never throws; failures resolve to `nil`.
    private static func reverseGeocodeName(
        latitude: Double,
        longitude: Double
    ) async -> String? {
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let geocoder = CLGeocoder()
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            guard let placemark = placemarks.first else { return nil }
            return placemark.locality
                ?? placemark.subAdministrativeArea
                ?? placemark.administrativeArea
                ?? placemark.country
        } catch {
            return nil
        }
    }

    // MARK: - Codable

    private struct ForecastResponse: Decodable {
        let current: Current

        struct Current: Decodable {
            let temperature_2m: Double
            let apparent_temperature: Double?
            let is_day: Int
            let weather_code: Int
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
