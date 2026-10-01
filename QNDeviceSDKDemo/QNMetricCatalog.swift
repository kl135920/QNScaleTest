import Foundation

struct MetricDefinition: Identifiable, Hashable {
    let id: Int
    let title: String
    let sdkSemantic: String
    let unit: String?
    let precision: Int
    let category: String
    let officialSource: String

    var displayTitle: String { unit.map { "\(title)（\($0)）" } ?? "\(title)（SDK 原值）" }
}

enum QNMetricCatalog {
    static let source = "QNSDK/SDK/QNScaleItemData.h"

    static let definitions: [Int: MetricDefinition] = [
        1: .init(id: 1, title: "体重", sdkSemantic: "Weight", unit: "kg（SDK 配置）", precision: 1, category: "基础", officialSource: source),
        2: .init(id: 2, title: "BMI", sdkSemantic: "BMI", unit: nil, precision: 1, category: "基础", officialSource: source),
        3: .init(id: 3, title: "体脂率", sdkSemantic: "Body fat rate", unit: nil, precision: 1, category: "基础", officialSource: source),
        4: .init(id: 4, title: "皮下脂肪", sdkSemantic: "Subcutaneous fat", unit: nil, precision: 1, category: "基础", officialSource: source),
        5: .init(id: 5, title: "内脏脂肪", sdkSemantic: "Visceral fat", unit: nil, precision: 1, category: "基础", officialSource: source),
        6: .init(id: 6, title: "身体水分率", sdkSemantic: "Body water rate", unit: nil, precision: 1, category: "基础", officialSource: source),
        7: .init(id: 7, title: "肌肉率", sdkSemantic: "Muscle rate", unit: nil, precision: 1, category: "基础", officialSource: source),
        8: .init(id: 8, title: "骨量", sdkSemantic: "Bone mass", unit: nil, precision: 1, category: "基础", officialSource: source),
        9: .init(id: 9, title: "基础代谢率", sdkSemantic: "BMR", unit: nil, precision: 0, category: "基础", officialSource: source),
        11: .init(id: 11, title: "蛋白质", sdkSemantic: "Protein", unit: nil, precision: 1, category: "基础", officialSource: source),
        12: .init(id: 12, title: "去脂体重", sdkSemantic: "Lean body weight", unit: nil, precision: 1, category: "基础", officialSource: source),
        13: .init(id: 13, title: "肌肉量", sdkSemantic: "Muscle mass", unit: nil, precision: 1, category: "基础", officialSource: source),
        14: .init(id: 14, title: "体年龄", sdkSemantic: "Metabolic age", unit: nil, precision: 0, category: "基础", officialSource: source),
        21: .init(id: 21, title: "脂肪重量", sdkSemantic: "Fat mass", unit: nil, precision: 1, category: "基础", officialSource: source),
        23: .init(id: 23, title: "含水量", sdkSemantic: "Water content index", unit: nil, precision: 1, category: "基础", officialSource: source),
        24: .init(id: 24, title: "蛋白质量", sdkSemantic: "Protein mass index", unit: nil, precision: 1, category: "基础", officialSource: source),
        31: .init(id: 31, title: "肌肉率", sdkSemantic: "Muscle mass rate", unit: nil, precision: 1, category: "基础", officialSource: source),
        35: .init(id: 35, title: "皮下脂肪量", sdkSemantic: "Subcutaneous fat mass", unit: nil, precision: 1, category: "基础", officialSource: source),
        36: .init(id: 36, title: "SMI", sdkSemantic: "Skeletal muscle index", unit: nil, precision: 1, category: "基础", officialSource: source),
        37: .init(id: 37, title: "腰臀比", sdkSemantic: "Waist-hip ratio", unit: nil, precision: 2, category: "基础", officialSource: source),
        101: .init(id: 101, title: "右臂肌肉重量", sdkSemantic: "Right arm muscle weight", unit: nil, precision: 1, category: "五段肌肉", officialSource: source),
        102: .init(id: 102, title: "左臂肌肉重量", sdkSemantic: "Left arm muscle weight", unit: nil, precision: 1, category: "五段肌肉", officialSource: source),
        103: .init(id: 103, title: "躯干肌肉重量", sdkSemantic: "Trunk muscle weight", unit: nil, precision: 1, category: "五段肌肉", officialSource: source),
        104: .init(id: 104, title: "右腿肌肉重量", sdkSemantic: "Right leg muscle weight", unit: nil, precision: 1, category: "五段肌肉", officialSource: source),
        105: .init(id: 105, title: "左腿肌肉重量", sdkSemantic: "Left leg muscle weight", unit: nil, precision: 1, category: "五段肌肉", officialSource: source),
        106: .init(id: 106, title: "右臂 fat 指标", sdkSemantic: "Right arm fat index（官方未确认分母）", unit: nil, precision: 1, category: "五段 fat 原值", officialSource: source),
        107: .init(id: 107, title: "左臂 fat 指标", sdkSemantic: "Left arm fat index（官方未确认分母）", unit: nil, precision: 1, category: "五段 fat 原值", officialSource: source),
        108: .init(id: 108, title: "躯干 fat 指标", sdkSemantic: "Trunk fat index（官方未确认分母）", unit: nil, precision: 1, category: "五段 fat 原值", officialSource: source),
        109: .init(id: 109, title: "右腿 fat 指标", sdkSemantic: "Right leg fat index（官方未确认分母）", unit: nil, precision: 1, category: "五段 fat 原值", officialSource: source),
        110: .init(id: 110, title: "左腿 fat 指标", sdkSemantic: "Left leg fat index（官方未确认分母）", unit: nil, precision: 1, category: "五段 fat 原值", officialSource: source),
        111: .init(id: 111, title: "无机盐比例指标", sdkSemantic: "Mineral salt rate", unit: nil, precision: 1, category: "全身", officialSource: source),
        112: .init(id: 112, title: "骨骼肌量", sdkSemantic: "Skeletal muscle mass", unit: nil, precision: 1, category: "全身", officialSource: source),
        113: .init(id: 113, title: "右臂脂肪量", sdkSemantic: "Right arm fat mass", unit: nil, precision: 1, category: "五段脂肪", officialSource: source),
        114: .init(id: 114, title: "左臂脂肪量", sdkSemantic: "Left arm fat mass", unit: nil, precision: 1, category: "五段脂肪", officialSource: source),
        115: .init(id: 115, title: "躯干脂肪量", sdkSemantic: "Trunk fat mass", unit: nil, precision: 1, category: "五段脂肪", officialSource: source),
        116: .init(id: 116, title: "右腿脂肪量", sdkSemantic: "Right leg fat mass", unit: nil, precision: 1, category: "五段脂肪", officialSource: source),
        117: .init(id: 117, title: "左腿脂肪量", sdkSemantic: "Left leg fat mass", unit: nil, precision: 1, category: "五段脂肪", officialSource: source),
        118: .init(id: 118, title: "左臂肌肉比例指标", sdkSemantic: "Left arm muscle index", unit: nil, precision: 1, category: "五段肌肉比例", officialSource: source),
        119: .init(id: 119, title: "右臂肌肉比例指标", sdkSemantic: "Right arm muscle index", unit: nil, precision: 1, category: "五段肌肉比例", officialSource: source),
        120: .init(id: 120, title: "躯干肌肉比例指标", sdkSemantic: "Trunk muscle index", unit: nil, precision: 1, category: "五段肌肉比例", officialSource: source),
        121: .init(id: 121, title: "左腿肌肉比例指标", sdkSemantic: "Left leg muscle index", unit: nil, precision: 1, category: "五段肌肉比例", officialSource: source),
        122: .init(id: 122, title: "右腿肌肉比例指标", sdkSemantic: "Right leg muscle index", unit: nil, precision: 1, category: "五段肌肉比例", officialSource: source)
    ]

    static func definition(for type: Int) -> MetricDefinition {
        definitions[type] ?? MetricDefinition(id: type, title: "SDK 指标 \(type)", sdkSemantic: "未识别指标", unit: nil, precision: 2, category: "未识别", officialSource: source)
    }
}
