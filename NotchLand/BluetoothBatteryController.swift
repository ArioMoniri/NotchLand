//
//  BluetoothBatteryController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Reports battery levels for connected Bluetooth accessories (AirPods,
//  AirPods Pro/Max, and other BT devices) by shelling out to
//  `system_profiler SPBluetoothDataType -json` on a background queue and
//  parsing whatever battery fields the OS exposes. Runs entirely off the
//  main thread while polling, then publishes results back on the main actor.
//

import Combine
import Foundation

/// A single connected Bluetooth device and whatever battery readings it exposes.
/// Percentages are clamped to 0...100; `nil` means the device did not report
/// that particular value. `id` is the device name.
struct BTDevice: Identifiable, Equatable {
    let id: String
    let name: String
    let main: Int?
    let left: Int?
    let right: Int?
    let batteryCase: Int?
}

@MainActor
final class BluetoothBatteryController: ObservableObject {
    /// Only devices that report at least one battery value are published.
    @Published private(set) var devices: [BTDevice] = []

    private let pollInterval: TimeInterval = 60
    private let commandPath = "/usr/sbin/system_profiler"
    private let processTimeout: TimeInterval = 15
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshNow() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
        refreshNow()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Trigger an immediate poll. The `system_profiler` invocation runs off the
    /// main thread; results are published back on the main actor.
    func refreshNow() {
        let path = commandPath
        let timeout = processTimeout
        DispatchQueue.global(qos: .utility).async {
            let parsed = Self.fetchDevices(commandPath: path, timeout: timeout)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    // Only replace when something actually changed to avoid
                    // needless SwiftUI churn.
                    if parsed != self.devices {
                        self.devices = parsed
                    }
                }
            }
        }
    }

    // MARK: - Off-main data fetch

    /// Runs `system_profiler` and parses its JSON. Fully defensive: any failure
    /// (missing binary, timeout, malformed JSON) yields an empty array rather
    /// than crashing. Must remain `nonisolated` / free of main-actor state.
    private nonisolated static func fetchDevices(commandPath: String, timeout: TimeInterval) -> [BTDevice] {
        guard FileManager.default.isExecutableFile(atPath: commandPath) else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: commandPath)
        process.arguments = ["SPBluetoothDataType", "-json"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return []
        }

        // Read output on a background thread while we optionally enforce a
        // timeout, so a hung `system_profiler` can never block indefinitely.
        var data = Data()
        let readQueue = DispatchQueue(label: "com.notchland.btbattery.read")
        let readDone = DispatchSemaphore(value: 0)
        readQueue.async {
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            readDone.signal()
        }

        if readDone.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            _ = readDone.wait(timeout: .now() + 2)
        }
        process.waitUntilExit()

        guard !data.isEmpty else { return [] }

        return parse(jsonData: data)
    }

    // MARK: - JSON parsing

    /// Parse the top-level `system_profiler` payload into `BTDevice` values.
    static func parse(jsonData: Data) -> [BTDevice] {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: jsonData, options: [])
        } catch {
            return []
        }

        guard let top = root as? [String: Any],
              let dataArray = top["SPBluetoothDataType"] as? [Any],
              let firstAny = dataArray.first,
              let first = firstAny as? [String: Any]
        else { return [] }

        guard let connected = first["device_connected"] as? [Any] else { return [] }

        var result: [BTDevice] = []
        var seen = Set<String>()

        for entryAny in connected {
            // Each entry is a single-key dictionary: { "Device Name": { ... } }.
            guard let entry = entryAny as? [String: Any],
                  let (name, valueAny) = entry.first,
                  let info = valueAny as? [String: Any]
            else { continue }

            let device = makeDevice(name: name, info: info)
            guard let device else { continue }
            guard !seen.contains(device.id) else { continue }
            seen.insert(device.id)
            result.append(device)
        }

        return result
    }

    /// Build a `BTDevice` from one device's info dictionary, returning `nil`
    /// when no battery value of any kind is present.
    private static func makeDevice(name: String, info: [String: Any]) -> BTDevice? {
        let main = percent(info["device_batteryLevelMain"])
        let left = percent(info["device_batteryLevelLeft"])
        let right = percent(info["device_batteryLevelRight"])
        let batteryCase = percent(info["device_batteryLevelCase"])

        guard main != nil || left != nil || right != nil || batteryCase != nil else { return nil }

        return BTDevice(
            id: name,
            name: name,
            main: main,
            left: left,
            right: right,
            batteryCase: batteryCase
        )
    }

    /// Coerce a battery field into a clamped 0...100 percentage.
    /// Accepts values like `"80%"`, `"80"`, or a raw number; returns `nil`
    /// for anything unparseable.
    private static func percent(_ value: Any?) -> Int? {
        let raw: Int?
        switch value {
        case let string as String:
            let trimmed = string
                .replacingOccurrences(of: "%", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            raw = Int(trimmed)
        case let number as Int:
            raw = number
        case let number as Double:
            raw = Int(number)
        case let number as NSNumber:
            raw = number.intValue
        default:
            raw = nil
        }

        guard let raw else { return nil }
        return min(100, max(0, raw))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
