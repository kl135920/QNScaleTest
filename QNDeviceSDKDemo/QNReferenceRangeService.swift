import Foundation

struct QNReferenceEvaluation: Identifiable, Hashable {
    let id: String
    let label: String
    let detail: String
    let source: String
    let version: String
}

enum QNReferenceRangeService {
    static let version = "cn-adult-2024.v1"
    static let source = "国家卫生健康委《肥胖症诊疗指南（2024年版）》"

    static func bmi(_ value: Double?) -> QNReferenceEvaluation? {
        guard let value, value.isFinite else { return nil }
        let label: String
        if value < 18.5 { label = "偏低" }
        else if value < 24 { label = "正常" }
        else if value < 28 { label = "超重" }
        else { label = "肥胖区间" }
        return QNReferenceEvaluation(id: "bmi", label: label, detail: "正常范围 18.5 ≤ BMI < 24；超重 24 ≤ BMI < 28；肥胖区间 BMI ≥ 28", source: source, version: version)
    }

    static func bodyFatRate(_ value: Double?, gender: String?) -> QNReferenceEvaluation? {
        guard let value, value.isFinite else { return nil }
        let threshold = gender == "female" ? 30.0 : 25.0
        let label = value > threshold ? "体脂偏高" : "未超出该阈值"
        return QNReferenceEvaluation(id: "bodyFatRate", label: label, detail: "成年男性体脂率 > 25% 或成年女性 > 30%", source: source, version: version)
    }

    static func evaluation(for key: String, value: Double?, gender: String?) -> QNReferenceEvaluation? {
        switch key {
        case "bmi": return bmi(value)
        case "bodyFatRate": return bodyFatRate(value, gender: gender)
        default: return nil
        }
    }
}
