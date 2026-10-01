import Foundation

struct QNMappedMeasurement {
    let measureTime: Date
    let user: [String: Any]
    let device: [String: Any]
    let scale: [String: Any]
    let metadata: [String: Any]
    let items: [[String: Any]]
    let valuesByType: [Int: Double]
    let deduplicationKey: String

    var hmac: String? { QNMeasurementMapper.string(scale["hmac"]) }
    var weight: Double? { valuesByType[1] }
    var boneMass: Double? { valuesByType[8] }
    var boneMassPercentage: Double? {
        guard let boneMass, let weight, weight > 0, boneMass.isFinite, weight.isFinite else { return nil }
        return boneMass / weight * 100
    }
}

enum QNMeasurementMapper {
    static func map(measurement: [String: Any], profile: QNUserProfile) throws -> QNMappedMeasurement {
        guard let scale = measurement["scaleData"] as? [String: Any],
              let device = measurement["device"] as? [String: Any],
              let user = measurement["user"] as? [String: Any],
              let measureTime = date(scale["measureTime"]) else {
            throw QNMeasurementRepositoryError.invalidMeasurement("QNScaleData 缺少 scaleData、device、user 或 measureTime")
        }
        let metadata = measurement["metadata"] as? [String: Any] ?? [:]
        let items = measurement["items"] as? [[String: Any] ] ?? []
        var values: [Int: Double] = [:]
        for item in items {
            if let type = int(item["type"]), let value = double(item["value"]), value.isFinite { values[type] = value }
        }
        let userId = string(user["userId"]) ?? profile.userId
        let identifier = string(device["deviceIdentifier"]) ?? string(device["sdkIdentifierMac"]) ?? "unknown-device"
        let hmac = string(scale["hmac"])
        let deduplicationKey = "\(userId)|\(identifier)|\(hmac ?? isoDate(measureTime))"
        return QNMappedMeasurement(measureTime: measureTime, user: user, device: device, scale: scale, metadata: metadata, items: items, valuesByType: values, deduplicationKey: deduplicationKey)
    }

    static func string(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Int { return value }
        return nil
    }

    static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: string) ?? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: string)
        }()
    }

    static func isoDate(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
