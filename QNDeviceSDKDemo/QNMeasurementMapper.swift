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
        guard let scale = dictionary(measurement["scaleData"]) else {
            throw QNMeasurementRepositoryError.invalidMeasurement("QNScaleData 缺少 scaleData")
        }
        guard let device = dictionary(measurement["device"]) else {
            throw QNMeasurementRepositoryError.invalidMeasurement("QNScaleData 缺少 device")
        }
        guard let user = dictionary(measurement["user"]) else {
            throw QNMeasurementRepositoryError.invalidMeasurement("QNScaleData 缺少 user")
        }
        guard let measureTime = date(scale["measureTime"]) else {
            throw QNMeasurementRepositoryError.invalidMeasurement("QNScaleData measureTime 无法解析：\(string(scale["measureTime"]) ?? "<nil>")")
        }
        let metadata = dictionary(measurement["metadata"]) ?? [:]
        let items = dictionaries(measurement["items"])
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

    /// Objective-C callbacks bridge nested dictionaries and arrays as
    /// Foundation containers. Normalize them before persistence.
    static func dictionary(_ value: Any?) -> [String: Any]? {
        if let value = value as? [String: Any] { return value }
        if let value = value as? [AnyHashable: Any] {
            return value.reduce(into: [String: Any]()) { result, pair in
                guard let key = pair.key as? String else { return }
                result[key] = pair.value
            }
        }
        if let value = value as? NSDictionary {
            var result: [String: Any] = [:]
            value.forEach { key, item in
                if let key = key as? String { result[key] = item }
            }
            return result
        }
        return nil
    }

    static func dictionaries(_ value: Any?) -> [[String: Any]] {
        guard let values = value as? [Any] else { return [] }
        return values.compactMap(dictionary)
    }

    static func date(_ value: Any?) -> Date? {
        guard let string = value as? String else { return nil }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let internetFormatter = ISO8601DateFormatter()
        internetFormatter.formatOptions = [.withInternetDateTime]
        return fractionalFormatter.date(from: string) ?? internetFormatter.date(from: string) ?? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.date(from: string)
        }()
    }

    static func isoDate(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
