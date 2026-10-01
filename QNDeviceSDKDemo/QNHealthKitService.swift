import Foundation
import HealthKit

enum QNHealthKitError: LocalizedError {
    case unavailable
    case authorizationFailed
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable: return "此设备不支持 Apple 健康"
        case .authorizationFailed: return "Apple 健康授权未完成"
        case .saveFailed(let message): return "写入 Apple 健康失败：\(message)"
        }
    }
}

protocol QNHealthKitServiceProtocol {
    var isAvailable: Bool { get }
    var authorizationStateText: String { get }
    func requestAuthorization() async throws
    func write(_ snapshot: QNMeasurementSnapshot) async throws -> Int
    func importMeasurements(profile: QNUserProfile) async throws -> [[String: Any]]
}

final class QNHealthKitService: QNHealthKitServiceProtocol {
    private struct ImportedSample {
        let type: Int
        let title: String
        let value: Double
        let unit: String?
        let sample: HKQuantitySample
    }

    private let healthStore: HKHealthStore
    private let defaults: UserDefaults
    private let syncedKeysDefaultsKey = "QNScaleTest.healthKit.syncedSampleKeys.v1"
    private let externalUUIDPrefix = "QNScaleTest|"

    init(healthStore: HKHealthStore = HKHealthStore(), defaults: UserDefaults = .standard) {
        self.healthStore = healthStore
        self.defaults = defaults
    }

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var authorizationStateText: String {
        guard isAvailable else { return "不可用" }
        let statuses = quantityTypes.map { healthStore.authorizationStatus(for: $0) }
        if statuses.allSatisfy({ $0 == .sharingAuthorized }) { return "已连接" }
        if statuses.allSatisfy({ $0 == .notDetermined }) { return "未授权" }
        if statuses.contains(.sharingDenied) { return "部分权限未开启" }
        return "部分权限已开启"
    }

    func requestAuthorization() async throws {
        guard isAvailable else { throw QNHealthKitError.unavailable }
        let shareTypes = Set(quantityTypes.map { $0 as HKSampleType })
        let readTypes = Set(quantityTypes.map { $0 as HKObjectType })
        try await withCheckedThrowingContinuation { continuation in
            healthStore.requestAuthorization(toShare: shareTypes, read: readTypes) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume(returning: ()) }
                else { continuation.resume(throwing: QNHealthKitError.authorizationFailed) }
            }
        }
    }

    func write(_ snapshot: QNMeasurementSnapshot) async throws -> Int {
        guard isAvailable else { throw QNHealthKitError.unavailable }
        var savedCount = 0
        var firstError: Error?
        for descriptor in writeDescriptors(snapshot) {
            let syncKey = "\(snapshot.id.uuidString)|\(descriptor.identifier.rawValue)"
            if syncedKeys.contains(syncKey) { continue }
            let externalUUID = "\(externalUUIDPrefix)\(syncKey)"
            let metadata: [String: Any] = [
                HKMetadataKeyExternalUUID: externalUUID,
                HKMetadataKeyWasUserEntered: false,
                "QNScaleTestDeduplicationKey": snapshot.deduplicationKey,
                "QNScaleTestDeviceIdentifier": snapshot.deviceIdentifier ?? "QN-Scale"
            ]
            let sample = HKQuantitySample(
                type: descriptor.type,
                quantity: HKQuantity(unit: descriptor.unit, doubleValue: descriptor.value),
                start: snapshot.measureTime,
                end: snapshot.measureTime,
                metadata: metadata
            )
            do {
                try await save(sample)
                rememberSyncedKey(syncKey)
                savedCount += 1
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if savedCount == 0, let firstError {
            throw QNHealthKitError.saveFailed(firstError.localizedDescription)
        }
        return savedCount
    }

    func importMeasurements(profile: QNUserProfile) async throws -> [[String: Any]] {
        guard isAvailable else { throw QNHealthKitError.unavailable }
        var imported: [ImportedSample] = []
        for type in quantityTypes {
            let samples = try await samples(for: type)
            for sample in samples where !isCreatedByThisApp(sample) {
                if let value = importedValue(from: sample) { imported.append(value) }
            }
        }
        let sorted = imported.sorted { $0.sample.startDate < $1.sample.startDate }
        var groups: [[ImportedSample]] = []
        for value in sorted {
            if let firstDate = groups.last?.first?.sample.startDate,
               abs(value.sample.startDate.timeIntervalSince(firstDate)) <= 60 {
                groups[groups.count - 1].append(value)
            } else {
                groups.append([value])
            }
        }
        return groups.map { measurement(from: $0, profile: profile) }
    }

    private var quantityTypes: [HKQuantityType] {
        [
            HKObjectType.quantityType(forIdentifier: .bodyMass),
            HKObjectType.quantityType(forIdentifier: .bodyMassIndex),
            HKObjectType.quantityType(forIdentifier: .bodyFatPercentage),
            HKObjectType.quantityType(forIdentifier: .leanBodyMass)
        ].compactMap { $0 }
    }

    private typealias WriteDescriptor = (identifier: HKQuantityTypeIdentifier, type: HKQuantityType, unit: HKUnit, value: Double)

    private func writeDescriptors(_ snapshot: QNMeasurementSnapshot) -> [WriteDescriptor] {
        var result: [WriteDescriptor] = []
        append(snapshot.weight, identifier: .bodyMass, unit: .gramUnit(with: .kilo), transform: { $0 }, to: &result)
        append(snapshot.bmi, identifier: .bodyMassIndex, unit: .count(), transform: { $0 }, to: &result)
        append(snapshot.bodyFatRate, identifier: .bodyFatPercentage, unit: .percent(), transform: { $0 / 100 }, to: &result)
        append(snapshot.metrics["leanBodyWeight"], identifier: .leanBodyMass, unit: .gramUnit(with: .kilo), transform: { $0 }, to: &result)
        return result
    }

    private func append(_ value: Double?, identifier: HKQuantityTypeIdentifier, unit: HKUnit, transform: (Double) -> Double, to result: inout [WriteDescriptor]) {
        guard let value, value.isFinite, value > 0,
              let type = HKObjectType.quantityType(forIdentifier: identifier) else { return }
        result.append((identifier, type, unit, transform(value)))
    }

    private func save(_ sample: HKQuantitySample) async throws {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.save(sample) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume(returning: ()) }
                else { continuation.resume(throwing: QNHealthKitError.saveFailed("HealthKit 未保存样本")) }
            }
        }
    }

    private func samples(for type: HKQuantityType) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples as? [HKQuantitySample] ?? []) }
            }
            healthStore.execute(query)
        }
    }

    private func isCreatedByThisApp(_ sample: HKQuantitySample) -> Bool {
        if let externalUUID = sample.metadata?[HKMetadataKeyExternalUUID] as? String,
           externalUUID.hasPrefix(externalUUIDPrefix) { return true }
        return sample.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    private func importedValue(from sample: HKQuantitySample) -> ImportedSample? {
        switch sample.quantityType.identifier {
        case HKQuantityTypeIdentifier.bodyMass.rawValue:
            return ImportedSample(type: 1, title: "体重", value: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)), unit: "kg", sample: sample)
        case HKQuantityTypeIdentifier.bodyMassIndex.rawValue:
            return ImportedSample(type: 2, title: "BMI", value: sample.quantity.doubleValue(for: .count()), unit: nil, sample: sample)
        case HKQuantityTypeIdentifier.bodyFatPercentage.rawValue:
            return ImportedSample(type: 3, title: "全身体脂率", value: sample.quantity.doubleValue(for: .percent()) * 100, unit: "%", sample: sample)
        case HKQuantityTypeIdentifier.leanBodyMass.rawValue:
            return ImportedSample(type: 12, title: "去脂体重", value: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)), unit: "kg", sample: sample)
        default:
            return nil
        }
    }

    private func measurement(from group: [ImportedSample], profile: QNUserProfile) -> [String: Any] {
        var values: [Int: ImportedSample] = [:]
        for value in group { values[value.type] = value }
        let measureTime = group.map(\.sample.startDate).min() ?? Date()
        let sourceNames = Array(Set(group.map { $0.sample.sourceRevision.source.name })).sorted()
        let sourceBundles = Array(Set(group.map { $0.sample.sourceRevision.source.bundleIdentifier })).sorted()
        let sampleIDs = group.map { $0.sample.uuid.uuidString }.sorted()
        let items: [[String: Any]] = values.values.sorted { $0.type < $1.type }.map { value in
            [
                "type": value.type,
                "name": value.title,
                "value": value.value,
                "valueType": 0,
                "valueTypeName": "double",
                "unit": value.unit ?? NSNull(),
                "description": "从 Apple 健康导入"
            ]
        }
        return [
            "metadata": [
                "source": "HealthKit",
                "sourceNames": sourceNames,
                "sourceBundleIdentifiers": sourceBundles
            ],
            "device": [
                "bluetoothName": "Apple 健康",
                "deviceIdentifier": "healthkit",
                "deviceType": -1,
                "modeId": "HealthKit",
                "isSupportEightElectrodes": false
            ],
            "user": [
                "userId": profile.userId,
                "nickname": profile.nickname,
                "gender": profile.gender,
                "height": profile.height,
                "athleteType": profile.athleteType,
                "birthday": QNMeasurementMapper.isoDate(profile.birthday)
            ],
            "scaleData": [
                "measureTime": QNMeasurementMapper.isoDate(measureTime),
                "hmac": "healthkit:\(sampleIDs.joined(separator: ","))",
                "height": profile.height,
                "heightMode": 0,
                "weight": values[1]?.value ?? NSNull(),
                "newEightModel": 0,
                "eightIsAbnormal": 0,
                "eightReasonMask": 0
            ],
            "items": items
        ]
    }

    private var syncedKeys: Set<String> {
        Set(defaults.stringArray(forKey: syncedKeysDefaultsKey) ?? [])
    }

    private func rememberSyncedKey(_ key: String) {
        var keys = syncedKeys
        keys.insert(key)
        defaults.set(Array(keys).sorted(), forKey: syncedKeysDefaultsKey)
    }
}
