import Foundation

struct QNComparisonRow: Identifiable, Hashable {
    let id: String
    let type: Int
    let title: String
    let start: Double?
    let end: Double?
    let difference: Double?
    let unit: String?
    let precision: Int
    let comparable: Bool
}

struct QNMeasurementComparison: Identifiable {
    let start: QNMeasurementSnapshot
    let end: QNMeasurementSnapshot
    let intervalDays: Int
    let rows: [QNComparisonRow]

    var id: String { "\(start.id.uuidString)-\(end.id.uuidString)" }
}

enum QNHistoryComparisonService {
    static func compare(start: QNMeasurementSnapshot, end: QNMeasurementSnapshot) -> QNMeasurementComparison? {
        guard start.id != end.id else { return nil }
        let ordered = [start, end].sorted { QNMeasurementTimeline.isEarlier($0, than: $1) }
        let start = ordered[0]
        let end = ordered[1]
        let rows = QNMetricCatalog.comparisonTypes.map { type -> QNComparisonRow in
            let definition = QNMetricCatalog.definition(for: type)
            let key = key(for: type)
            let startValue = start.metrics[key] ?? start.metrics["type\(type)"]
            let endValue = end.metrics[key] ?? end.metrics["type\(type)"]
            let difference = startValue.flatMap { lhs in endValue.map { $0 - lhs } }
            let comparable = type != 5 && type != 32 && type != 38
            return QNComparisonRow(id: "\(type)", type: type, title: definition.title, start: startValue, end: endValue, difference: comparable ? difference : nil, unit: definition.unit, precision: definition.precision, comparable: comparable)
        }
        let days = max(0, Calendar.current.dateComponents([.day], from: start.measureTime, to: end.measureTime).day ?? 0)
        return QNMeasurementComparison(start: start, end: end, intervalDays: days, rows: rows)
    }

    static func key(for type: Int) -> String {
        [1:"weight",2:"bmi",3:"bodyFatRate",4:"subcutaneousFatRate",5:"visceralFat",6:"bodyWaterRate",7:"skeletalMuscleRate",8:"boneMass",9:"bmr",11:"proteinRate",12:"leanBodyWeight",13:"muscleMass",14:"metabolicAge",15:"healthScore",21:"fatMass",23:"waterContent",24:"proteinMass",31:"muscleMassRate",32:"fattyLiverRisk",35:"subcutaneousFatMass",36:"smi",37:"waistHipRatio",101:"rightArmMuscleMass",102:"leftArmMuscleMass",103:"trunkMuscleMass",104:"rightLegMuscleMass",105:"leftLegMuscleMass",113:"rightArmFatMass",114:"leftArmFatMass",115:"trunkFatMass",116:"rightLegFatMass",117:"leftLegFatMass"][type] ?? "type\(type)"
    }
}
