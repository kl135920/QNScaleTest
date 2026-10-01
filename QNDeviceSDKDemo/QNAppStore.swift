import Foundation
import SwiftUI

enum QNDisplayWeightUnit: String, CaseIterable, Identifiable {
    case kilogram
    case jin

    static let defaultsKey = "QNScaleTest.displayWeightUnit"
    var id: String { rawValue }
    var symbol: String { self == .jin ? "斤" : "kg" }
    var title: String { self == .jin ? "斤" : "千克" }

    func fromKilograms(_ value: Double) -> Double { self == .jin ? value * 2 : value }
    func toKilograms(_ value: Double) -> Double { self == .jin ? value / 2 : value }
    func text(fromKilograms value: Double, precision: Int = 2) -> String {
        String(format: precision == 1 ? "%.1f" : "%.2f", fromKilograms(value))
    }
}

struct QNDeviceRow: Identifiable {
    let id: String
    let name: String
    let modeId: String
    let deviceType: String
    let supportsEightElectrodes: Bool
    let rssi: String
}

final class QNAppStore: NSObject, ObservableObject, QNScaleServiceDelegate {
    @Published private(set) var profile: QNUserProfile?
    @Published private(set) var records: [QNMeasurementSnapshot] = []
    @Published private(set) var devices: [QNDeviceRow] = []
    @Published private(set) var serviceState = "SDK 未初始化"
    @Published private(set) var weight: Double?
    @Published private(set) var measurementState = "等待连接"
    @Published private(set) var lastError: String?
    @Published private(set) var pendingMeasurement: [String: Any]?
    @Published private(set) var lastSavedMeasurement: QNMeasurementSnapshot?
    @Published private(set) var healthKitStatus = "未检查"
    @Published private(set) var healthKitLastSyncSummary: String?
    @Published private(set) var healthKitIsSyncing = false
    @Published private(set) var healthKitAutoSyncEnabled: Bool
    @Published private(set) var automaticConnectionEnabled = false
    @Published private(set) var activeDeviceName = "QN-Scale"
    @Published var displayWeightUnit: QNDisplayWeightUnit {
        didSet { UserDefaults.standard.set(displayWeightUnit.rawValue, forKey: QNDisplayWeightUnit.defaultsKey) }
    }

    let service: QNScaleService
    let repository: QNMeasurementRepository?
    private let profileStore = QNProfileStore()
    private let healthKitService: QNHealthKitServiceProtocol
    private let pendingURL: URL
    private var attemptedDeviceIDs = Set<String>()
    private var connectingDeviceID: String?
    private var hadActiveConnection = false

    private static let healthKitAutoSyncKey = "QNScaleTest.healthKit.autoSync.v1"
    private static let preferredDeviceKey = "QNScaleTest.preferredDeviceIdentifier.v1"

    override init() {
        displayWeightUnit = QNDisplayWeightUnit(rawValue: UserDefaults.standard.string(forKey: QNDisplayWeightUnit.defaultsKey) ?? "") ?? .kilogram
        healthKitAutoSyncEnabled = UserDefaults.standard.bool(forKey: Self.healthKitAutoSyncKey)
        service = QNScaleService.shared()
        repository = try? QNMeasurementRepository()
        healthKitService = QNHealthKitService()
        pendingURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("QNScaleTest.pending-measurement.json")
        super.init()
        healthKitStatus = healthKitService.authorizationStateText
        profile = profileStore.load()
        pendingMeasurement = loadPendingMeasurement()
        service.delegate = self
        reloadRecords()
        service.initializeIfNeeded()
    }

    var hasValidProfile: Bool { profile?.isValid == true }
    var debugLog: String { service.debugLogText }
    var authorizationSummary: String { service.authorizationSummary }
    var sdkVersion: String { service.sdkVersion }
    var bundleIdentifier: String { service.bundleIdentifier }
    var isConnected: Bool { service.connectionState == "已连接" }
    var healthKitAvailable: Bool { healthKitService.isAvailable }
    var latestRawMeasurement: [String: Any]? { service.latestRawMeasurement.flatMap(Self.stringKeyedDictionary) }

    func saveProfile(_ value: QNUserProfile) {
        guard value.isValid else { lastError = "资料未完成：请填写昵称、性别、合法生日和身高"; return }
        do {
            try profileStore.save(value)
            profile = value
            lastError = nil
        } catch { lastError = "资料保存失败：\(error.localizedDescription)" }
    }

    func startScan() { service.startScanning() }
    func stopScan() { service.stopScanning() }

    func connect(index: Int) {
        guard let profile else { lastError = "请先完成用户资料"; return }
        let previousHMAC = records.first(where: { $0.userId == profile.userId })?.hmac
        measurementState = "连接中"
        service.connectToDevice(at: UInt(index), userId: profile.userId, nickname: profile.nickname, height: Int(profile.height), gender: profile.gender, birthday: profile.birthday, athleteType: profile.athleteType, previousHMAC: previousHMAC)
    }

    func disconnect() { service.disconnect() }

    func beginAutomaticConnection() {
        automaticConnectionEnabled = true
        attemptedDeviceIDs.removeAll()
        if isConnected { return }
        startScan()
        attemptAutomaticConnection()
    }

    func disconnectAndSuspendAutomaticConnection() {
        automaticConnectionEnabled = false
        connectingDeviceID = nil
        disconnect()
    }

    func retryAutomaticConnection() {
        automaticConnectionEnabled = true
        attemptedDeviceIDs.removeAll()
        connectingDeviceID = nil
        startScan()
        attemptAutomaticConnection()
    }

    func setHealthKitAutoSyncEnabled(_ enabled: Bool) {
        healthKitAutoSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: Self.healthKitAutoSyncKey)
        if enabled {
            Task { await requestHealthKitAuthorization() }
        }
    }

    @MainActor
    func requestHealthKitAuthorization() async {
        guard healthKitService.isAvailable else { healthKitStatus = "不可用"; return }
        healthKitIsSyncing = true
        defer { healthKitIsSyncing = false }
        do {
            try await healthKitService.requestAuthorization()
            healthKitStatus = healthKitService.authorizationStateText
            lastError = nil
        } catch {
            healthKitStatus = "授权失败"
            lastError = "Apple 健康授权失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    func syncWithHealthKit() async {
        guard let profile, let repository else { lastError = "请先完成用户资料"; return }
        guard healthKitService.isAvailable else { healthKitStatus = "不可用"; return }
        healthKitIsSyncing = true
        defer { healthKitIsSyncing = false }
        do {
            try await healthKitService.requestAuthorization()
            var written = 0
            var firstWriteError: Error?
            for record in records where record.deviceIdentifier != "healthkit" {
                do { written += try await healthKitService.write(record) }
                catch { if firstWriteError == nil { firstWriteError = error } }
            }
            let before = Set(records.map(\.deduplicationKey))
            let imported = try await healthKitService.importMeasurements(profile: profile)
            for measurement in imported { _ = try repository.save(measurement: measurement, profile: profile) }
            records = try repository.fetchAll()
            let importedCount = records.filter { !before.contains($0.deduplicationKey) }.count
            healthKitStatus = healthKitService.authorizationStateText
            healthKitLastSyncSummary = "写入 \(written) 项，导入 \(importedCount) 条"
            lastError = firstWriteError.map { "部分健康数据未写入：\($0.localizedDescription)" }
        } catch {
            healthKitStatus = "同步失败"
            lastError = "Apple 健康同步失败：\(error.localizedDescription)"
        }
    }

    func reloadRecords() {
        guard let repository else { return }
        do { records = try repository.fetchAll(); lastError = nil }
        catch { lastError = error.localizedDescription }
    }

    func delete(_ snapshot: QNMeasurementSnapshot) {
        guard let repository else { return }
        do { try repository.delete(snapshot); reloadRecords() }
        catch { lastError = "删除失败：\(error.localizedDescription)" }
    }

    func exportAllHistory() -> URL? {
        guard let repository else { return nil }
        do {
            let data = try repository.exportAll(profile: profile)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("QNScaleHistory-\(Self.fileStamp()).json")
            try data.write(to: url, options: .atomic)
            return url
        } catch { lastError = "历史导出失败：\(error.localizedDescription)"; return nil }
    }

    func export(_ snapshot: QNMeasurementSnapshot) -> URL? {
        guard let repository, let data = try? repository.export(snapshot) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QNScaleMeasurement-\(Self.fileStamp()).json")
        do { try data.write(to: url, options: .atomic); return url }
        catch { lastError = "测量导出失败：\(error.localizedDescription)"; return nil }
    }

    func copyLogs() { UIPasteboard.general.string = debugLog }

    func scaleServiceDidUpdateState(_ state: String) {
        DispatchQueue.main.async {
            self.serviceState = state
            if self.service.connectionState == "已连接" {
                self.hadActiveConnection = true
                if let identifier = self.connectingDeviceID {
                    UserDefaults.standard.set(identifier, forKey: Self.preferredDeviceKey)
                }
                self.connectingDeviceID = nil
            } else if self.service.connectionState == "连接失败", self.connectingDeviceID != nil {
                self.connectingDeviceID = nil
                if self.automaticConnectionEnabled { self.startScan() }
            } else if self.service.connectionState == "未连接", self.automaticConnectionEnabled, self.hadActiveConnection {
                self.hadActiveConnection = false
                self.retryAutomaticConnection()
            }
        }
    }

    func scaleServiceDidUpdateDevices(_ devices: [[AnyHashable : Any]]) {
        DispatchQueue.main.async {
            self.devices = devices.enumerated().map { offset, dictionary in
                let id = Self.string(dictionary["deviceIdentifier"]) ?? "device-\(offset)"
                return QNDeviceRow(id: id, name: Self.string(dictionary["bluetoothName"]) ?? Self.string(dictionary["name"]) ?? "未命名设备", modeId: Self.string(dictionary["modeId"]) ?? "未知型号", deviceType: Self.string(dictionary["deviceTypeName"]) ?? "未知类型", supportsEightElectrodes: Self.bool(dictionary["isSupportEightElectrodes"]), rssi: Self.string(dictionary["rssi"]) ?? "")
            }
            self.attemptAutomaticConnection()
        }
    }

    func scaleServiceDidUpdateWeight(_ weight: Double, state: String) {
        DispatchQueue.main.async {
            if weight.isFinite { self.weight = weight }
            self.measurementState = state
        }
    }

    func scaleServiceDidReceiveMeasurement(_ measurement: [AnyHashable : Any]) {
        let json = Self.stringKeyedDictionary(measurement) ?? [:]
        DispatchQueue.main.async {
            self.pendingMeasurement = json
            self.persistPendingMeasurement(json)
            guard let profile = self.profile, let repository = self.repository else { self.lastError = "测量收到，但资料或数据库不可用"; return }
            do {
                let saved = try repository.save(measurement: json, profile: profile)
                self.clearPendingMeasurement()
                self.lastSavedMeasurement = saved
                self.records = try repository.fetchAll()
                self.measurementState = saved.isAbnormal ? "测量异常，已保存原始结果" : "测量完成，已保存"
                self.lastError = nil
                if self.healthKitAutoSyncEnabled { Task { await self.writeMeasurementToHealthKit(saved) } }
            } catch { self.lastError = "测量已收到但保存失败：\(error.localizedDescription)；结果已保留，可重试" }
        }
    }

    func retryPendingSave() {
        guard let pendingMeasurement, let profile, let repository else { return }
        do {
            let saved = try repository.save(measurement: pendingMeasurement, profile: profile)
            lastSavedMeasurement = saved
            records = try repository.fetchAll()
            clearPendingMeasurement()
            lastError = nil
            if healthKitAutoSyncEnabled { Task { await self.writeMeasurementToHealthKit(saved) } }
        }
        catch { lastError = "重试保存失败：\(error.localizedDescription)" }
    }

    func scaleServiceDidReceiveLog(_ line: String) { objectWillChange.send() }
    func scaleServiceDidFinishInitialization(_ success: Bool, error: Error?) { DispatchQueue.main.async { if let error { self.lastError = "SDK 初始化失败：\(error.localizedDescription)" } else if !success { self.lastError = "SDK 初始化失败：未知错误" } } }

    private func persistPendingMeasurement(_ measurement: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(measurement), let data = try? JSONSerialization.data(withJSONObject: measurement, options: [.sortedKeys]) else { return }
        do { try FileManager.default.createDirectory(at: pendingURL.deletingLastPathComponent(), withIntermediateDirectories: true); try data.write(to: pendingURL, options: .atomic) } catch { lastError = "待保存结果暂存失败：\(error.localizedDescription)" }
    }

    private func loadPendingMeasurement() -> [String: Any]? {
        guard let data = try? Data(contentsOf: pendingURL), let value = try? JSONSerialization.jsonObject(with: data), let dictionary = value as? [String: Any] else { return nil }
        return dictionary
    }

    private func clearPendingMeasurement() {
        pendingMeasurement = nil
        try? FileManager.default.removeItem(at: pendingURL)
    }

    private func attemptAutomaticConnection() {
        guard automaticConnectionEnabled, !isConnected, service.connectionState != "连接中", connectingDeviceID == nil, hasValidProfile else { return }
        let preferred = UserDefaults.standard.string(forKey: Self.preferredDeviceKey)
        let candidates = devices.enumerated().filter {
            !attemptedDeviceIDs.contains($0.element.id) &&
            ($0.element.id == preferred || $0.element.supportsEightElectrodes || $0.element.name.caseInsensitiveCompare("QN-Scale") == .orderedSame)
        }
        let selected = candidates.max { lhs, rhs in
            automaticConnectionScore(lhs.element, preferred: preferred) < automaticConnectionScore(rhs.element, preferred: preferred)
        }
        guard let selected else { return }
        connectingDeviceID = selected.element.id
        activeDeviceName = selected.element.name
        attemptedDeviceIDs.insert(selected.element.id)
        connect(index: selected.offset)
    }

    private func automaticConnectionScore(_ device: QNDeviceRow, preferred: String?) -> Int {
        var score = 0
        if device.id == preferred { score += 1_000 }
        if device.supportsEightElectrodes { score += 200 }
        if device.name.caseInsensitiveCompare("QN-Scale") == .orderedSame { score += 100 }
        if device.modeId.caseInsensitiveCompare("0EDB") == .orderedSame { score += 50 }
        return score
    }

    @MainActor
    private func writeMeasurementToHealthKit(_ snapshot: QNMeasurementSnapshot) async {
        do {
            try await healthKitService.requestAuthorization()
            let count = try await healthKitService.write(snapshot)
            healthKitStatus = healthKitService.authorizationStateText
            healthKitLastSyncSummary = count == 0 ? "本次测量已同步" : "本次写入 \(count) 项"
        } catch {
            healthKitStatus = "写入失败"
            lastError = "测量已保存，但 Apple 健康写入失败：\(error.localizedDescription)"
        }
    }

    private static func stringKeyedDictionary(_ value: Any) -> [String: Any]? {
        normalizeJSONValue(value) as? [String: Any]
    }

    private static func normalizeJSONValue(_ value: Any) -> Any {
        if let dictionary = value as? NSDictionary {
            var result: [String: Any] = [:]
            dictionary.forEach { rawKey, rawValue in
                let key: String?
                if let string = rawKey as? String { key = string }
                else if let string = rawKey as? NSString { key = string as String }
                else { key = nil }
                if let key { result[key] = normalizeJSONValue(rawValue) }
            }
            return result
        }
        if let array = value as? NSArray {
            return array.map { normalizeJSONValue($0) }
        }
        return value
    }

    private static func string(_ value: Any?) -> String? { if let value = value as? String { return value }; if let value = value as? NSNumber { return value.stringValue }; return nil }
    private static func bool(_ value: Any?) -> Bool { (value as? NSNumber)?.boolValue ?? (value as? Bool ?? false) }
    private static func fileStamp() -> String { let f=DateFormatter(); f.dateFormat="yyyyMMdd-HHmmss"; return f.string(from: Date()) }
}
