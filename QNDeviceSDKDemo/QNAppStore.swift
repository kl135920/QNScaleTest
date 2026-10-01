import Foundation
import SwiftUI

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

    let service: QNScaleService
    let repository: QNMeasurementRepository?
    private let profileStore = QNProfileStore()
    private let pendingURL: URL

    override init() {
        service = QNScaleService.shared()
        repository = try? QNMeasurementRepository()
        pendingURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("QNScaleTest.pending-measurement.json")
        super.init()
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
        DispatchQueue.main.async { self.serviceState = state }
    }

    func scaleServiceDidUpdateDevices(_ devices: [[AnyHashable : Any]]) {
        DispatchQueue.main.async {
            self.devices = devices.enumerated().map { offset, dictionary in
                let id = Self.string(dictionary["deviceIdentifier"]) ?? "device-\(offset)"
                return QNDeviceRow(id: id, name: Self.string(dictionary["bluetoothName"]) ?? Self.string(dictionary["name"]) ?? "未命名设备", modeId: Self.string(dictionary["modeId"]) ?? "未知型号", deviceType: Self.string(dictionary["deviceTypeName"]) ?? "未知类型", supportsEightElectrodes: Self.bool(dictionary["isSupportEightElectrodes"]), rssi: Self.string(dictionary["rssi"]) ?? "")
            }
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
            } catch { self.lastError = "测量已收到但保存失败：\(error.localizedDescription)；结果已保留，可重试" }
        }
    }

    func retryPendingSave() {
        guard let pendingMeasurement, let profile, let repository else { return }
        do { lastSavedMeasurement = try repository.save(measurement: pendingMeasurement, profile: profile); records = try repository.fetchAll(); clearPendingMeasurement(); lastError = nil }
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
