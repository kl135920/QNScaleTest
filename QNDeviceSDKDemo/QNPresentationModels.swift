import Foundation

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
        QNDisplayFormatter.number(fromKilograms(value), maximumFractionDigits: precision)
    }
}

enum QNDisplayFormatter {
    static func number(_ value: Double, maximumFractionDigits: Int, signed: Bool = false) -> String {
        guard value.isFinite else { return "—" }
        let digits = max(0, maximumFractionDigits)
        let threshold = 0.5 / pow(10, Double(digits))
        let normalized = abs(value) < threshold ? 0 : value
        var text = String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), digits, normalized)
        if text.contains(".") {
            while text.last == "0" { text.removeLast() }
            if text.last == "." { text.removeLast() }
        }
        if signed, normalized > 0 { text = "+" + text }
        return text
    }

    static func metric(
        _ value: Double?,
        definition: MetricDefinition,
        weightUnit: QNDisplayWeightUnit,
        signed: Bool = false
    ) -> (number: String, unit: String?) {
        guard let value else { return ("—", nil) }
        let isMass = definition.unit == "kg"
        let displayValue = isMass ? weightUnit.fromKilograms(value) : value
        let unit = isMass ? weightUnit.symbol : definition.unit
        return (number(displayValue, maximumFractionDigits: definition.precision, signed: signed), unit)
    }

    static func joined(_ value: Double?, definition: MetricDefinition, weightUnit: QNDisplayWeightUnit, signed: Bool = false) -> String {
        let formatted = metric(value, definition: definition, weightUnit: weightUnit, signed: signed)
        guard let unit = formatted.unit else { return formatted.number }
        return "\(formatted.number) \(unit)"
    }
}

enum QNMeasurementTimeline {
    static func ordered(_ records: [QNMeasurementSnapshot], ascending: Bool = true) -> [QNMeasurementSnapshot] {
        records.sorted {
            if $0.measureTime != $1.measureTime {
                return ascending ? $0.measureTime < $1.measureTime : $0.measureTime > $1.measureTime
            }
            if $0.createdAt != $1.createdAt {
                return ascending ? $0.createdAt < $1.createdAt : $0.createdAt > $1.createdAt
            }
            return ascending ? $0.id.uuidString < $1.id.uuidString : $0.id.uuidString > $1.id.uuidString
        }
    }

    static func latest(_ records: [QNMeasurementSnapshot]) -> QNMeasurementSnapshot? {
        ordered(records, ascending: false).first
    }

    static func previousValidWeight(before record: QNMeasurementSnapshot, in records: [QNMeasurementSnapshot]) -> QNMeasurementSnapshot? {
        ordered(records.filter { candidate in
            candidate.id != record.id && candidate.weight != nil && isEarlier(candidate, than: record)
        }, ascending: false).first
    }

    static func isEarlier(_ lhs: QNMeasurementSnapshot, than rhs: QNMeasurementSnapshot) -> Bool {
        if lhs.measureTime != rhs.measureTime { return lhs.measureTime < rhs.measureTime }
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

struct QNHistoryDayGroup: Identifiable {
    let day: Date
    let records: [QNMeasurementSnapshot]

    var id: Date { day }

    static func make(
        records: [QNMeasurementSnapshot],
        calendar: Calendar = .current
    ) -> [QNHistoryDayGroup] {
        let grouped = Dictionary(grouping: QNMeasurementTimeline.ordered(records, ascending: false)) {
            calendar.startOfDay(for: $0.measureTime)
        }
        return grouped.keys.sorted(by: >).map { day in
            QNHistoryDayGroup(day: day, records: grouped[day] ?? [])
        }
    }
}

struct QNGoalProgress: Equatable {
    let startWeight: Double
    let currentWeight: Double
    let targetWeight: Double
    let fraction: Double?

    var remaining: Double { targetWeight - currentWeight }
    var reached: Bool {
        if targetWeight < startWeight { return currentWeight <= targetWeight }
        if targetWeight > startWeight { return currentWeight >= targetWeight }
        return abs(currentWeight - targetWeight) < 0.000_001
    }

    static func make(records: [QNMeasurementSnapshot], targetWeight: Double?) -> QNGoalProgress? {
        guard let targetWeight, targetWeight.isFinite, targetWeight > 0 else { return nil }
        let valid = QNMeasurementTimeline.ordered(records).filter { $0.weight?.isFinite == true }
        guard let startWeight = valid.first?.weight,
              let currentWeight = valid.last?.weight else { return nil }
        let denominator = targetWeight - startWeight
        let fraction: Double?
        if abs(denominator) < 0.000_001 {
            fraction = abs(currentWeight - targetWeight) < 0.000_001 ? 1 : nil
        } else {
            fraction = min(max((currentWeight - startWeight) / denominator, 0), 1)
        }
        return QNGoalProgress(startWeight: startWeight, currentWeight: currentWeight, targetWeight: targetWeight, fraction: fraction)
    }
}

enum QNBodyRegion: String, CaseIterable, Identifiable {
    case rightArm
    case leftArm
    case trunk
    case rightLeg
    case leftLeg

    var id: String { rawValue }
    var title: String {
        switch self {
        case .rightArm: return "右臂"
        case .leftArm: return "左臂"
        case .trunk: return "躯干"
        case .rightLeg: return "右腿"
        case .leftLeg: return "左腿"
        }
    }

    var muscleType: Int {
        switch self {
        case .rightArm: return 101
        case .leftArm: return 102
        case .trunk: return 103
        case .rightLeg: return 104
        case .leftLeg: return 105
        }
    }

    var fatIndexType: Int {
        switch self {
        case .rightArm: return 106
        case .leftArm: return 107
        case .trunk: return 108
        case .rightLeg: return 109
        case .leftLeg: return 110
        }
    }

    var fatMassType: Int {
        switch self {
        case .rightArm: return 113
        case .leftArm: return 114
        case .trunk: return 115
        case .rightLeg: return 116
        case .leftLeg: return 117
        }
    }

    var muscleIndexType: Int {
        switch self {
        case .rightArm: return 119
        case .leftArm: return 118
        case .trunk: return 120
        case .rightLeg: return 122
        case .leftLeg: return 121
        }
    }

    func value(type: Int, in snapshot: QNMeasurementSnapshot) -> Double? {
        let definition = QNMetricCatalog.definition(for: type)
        return snapshot.metrics[QNHistoryComparisonService.key(for: type)] ?? snapshot.metrics["type\(definition.id)"]
    }

    func hasValue(showFat: Bool, in snapshot: QNMeasurementSnapshot) -> Bool {
        let types = showFat ? [fatMassType, fatIndexType] : [muscleType, muscleIndexType]
        return types.contains { value(type: $0, in: snapshot) != nil }
    }
}

struct QNTrendMetric: Identifiable, Hashable {
    let key: String
    let type: Int
    let title: String

    var id: String { key }
    var definition: MetricDefinition { QNMetricCatalog.definition(for: type) }

    static let all: [QNTrendMetric] = [
        .init(key: "weight", type: 1, title: "体重"),
        .init(key: "bodyFatRate", type: 3, title: "体脂率"),
        .init(key: "fatMass", type: 21, title: "脂肪量"),
        .init(key: "muscleMass", type: 13, title: "肌肉量"),
        .init(key: "skeletalMuscleMass", type: 112, title: "骨骼肌量"),
        .init(key: "bmi", type: 2, title: "BMI"),
        .init(key: "bodyWaterRate", type: 6, title: "水分率"),
        .init(key: "visceralFat", type: 5, title: "内脏脂肪"),
        .init(key: "smi", type: 36, title: "SMI")
    ]
}

enum QNTrendRange: Int, CaseIterable, Identifiable {
    case sevenDays = 7
    case thirtyDays = 30
    case threeMonths = 90
    case sixMonths = 180
    case oneYear = 365
    case all = 0

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .sevenDays: return "7天"
        case .thirtyDays: return "30天"
        case .threeMonths: return "3个月"
        case .sixMonths: return "6个月"
        case .oneYear: return "1年"
        case .all: return "全部"
        }
    }
}

struct QNTrendPoint: Identifiable {
    let record: QNMeasurementSnapshot
    let value: Double
    var id: UUID { record.id }
}

struct QNTrendStatistics: Equatable {
    let start: Double
    let current: Double
    let change: Double
    let minimum: Double
    let maximum: Double
}

struct QNTrendSeries {
    let points: [QNTrendPoint]
    let domainStart: Date
    let domainEnd: Date
    let statistics: QNTrendStatistics?

    static func make(records: [QNMeasurementSnapshot], metric: QNTrendMetric, range: QNTrendRange, now: Date = Date()) -> QNTrendSeries {
        let ordered = QNMeasurementTimeline.ordered(records)
        let domainStart: Date
        let domainEnd: Date
        if range == .all {
            domainStart = ordered.first?.measureTime ?? now
            domainEnd = max(ordered.last?.measureTime ?? now, domainStart)
        } else {
            domainStart = Calendar.current.date(byAdding: .day, value: -range.rawValue, to: now) ?? .distantPast
            domainEnd = now
        }
        let points = ordered.compactMap { record -> QNTrendPoint? in
            guard record.measureTime >= domainStart,
                  record.measureTime <= domainEnd,
                  let value = record.metrics[metric.key], value.isFinite else { return nil }
            return QNTrendPoint(record: record, value: value)
        }
        let values = points.map(\.value)
        let statistics = values.first.flatMap { first in
            values.last.map { last in
                QNTrendStatistics(start: first, current: last, change: last - first, minimum: values.min() ?? first, maximum: values.max() ?? first)
            }
        }
        return QNTrendSeries(points: points, domainStart: domainStart, domainEnd: domainEnd, statistics: statistics)
    }

    func xFraction(for date: Date) -> Double {
        let span = domainEnd.timeIntervalSince(domainStart)
        guard span > 0 else { return 0.5 }
        return min(max(date.timeIntervalSince(domainStart) / span, 0), 1)
    }

    static func previousValue(for point: QNTrendPoint, metric: QNTrendMetric, allRecords: [QNMeasurementSnapshot]) -> Double? {
        QNMeasurementTimeline.ordered(allRecords, ascending: false).first(where: {
            QNMeasurementTimeline.isEarlier($0, than: point.record) && $0.metrics[metric.key]?.isFinite == true
        })?.metrics[metric.key]
    }
}

enum QNMeasurementUIState: Equatable {
    case unavailable(String)
    case disconnected
    case scanning
    case connecting(String)
    case connected(String)
    case measuring(weight: Double?, state: String)
    case completed
    case failed(String)

    static func resolve(
        sdkState: String,
        bluetoothState: String,
        connectionState: String,
        isScanning: Bool,
        deviceName: String,
        measurementState: String,
        weight: Double?,
        operationError: String?
    ) -> QNMeasurementUIState {
        if sdkState == "初始化失败" { return .unavailable(operationError ?? "SDK 初始化失败") }
        if bluetoothState == "关闭" || bluetoothState == "未授权" { return .unavailable("蓝牙\(bluetoothState)") }
        if measurementState.contains("失败") { return .failed(operationError ?? measurementState) }
        if connectionState == "连接失败" { return .failed(operationError ?? "连接失败，请重试") }
        if connectionState == "连接中" { return .connecting(deviceName) }
        if isScanning && connectionState != "已连接" { return .scanning }
        guard connectionState == "已连接" else { return .disconnected }
        if measurementState.contains("测量完成") { return .completed }
        let activeStates = ["开始测量", "实时体重", "测量生物阻抗", "测量心率"]
        if activeStates.contains(measurementState) { return .measuring(weight: weight, state: measurementState) }
        return .connected(deviceName)
    }
}

struct QNHealthKitSyncSummary: Codable, Equatable {
    enum Outcome: String, Codable {
        case success
        case noChanges
        case partial
        case failed
    }

    let date: Date
    let written: Int
    let imported: Int
    let outcome: Outcome
    let errorMessage: String?

    var resultText: String {
        switch outcome {
        case .success: return "写入 \(written) 项，导入 \(imported) 条"
        case .noChanges: return "没有新增数据"
        case .partial: return "部分完成：写入 \(written) 项，导入 \(imported) 条"
        case .failed: return errorMessage ?? "同步失败"
        }
    }
}
