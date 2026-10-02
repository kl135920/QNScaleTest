import Foundation

struct MetricDefinition: Identifiable, Hashable {
    let id: Int
    let title: String
    let sdkSemantic: String
    let unit: String?
    let precision: Int
    let category: String
    let officialSource: String
    let notes: String?

    init(id: Int, title: String, sdkSemantic: String, unit: String?, precision: Int, category: String, officialSource: String = QNMetricCatalog.source, notes: String? = nil) {
        self.id = id
        self.title = title
        self.sdkSemantic = sdkSemantic
        self.unit = unit
        self.precision = precision
        self.category = category
        self.officialSource = officialSource
        self.notes = notes
    }

    var displayTitle: String { title }
}

enum QNMetricCatalog {
    static let source = "QNSDK/SDK/QNScaleItemData.h"

    static let definitions: [Int: MetricDefinition] = [
        1: .init(id: 1, title: "体重", sdkSemantic: "Weight", unit: "kg", precision: 2, category: "基础"),
        2: .init(id: 2, title: "BMI", sdkSemantic: "BMI", unit: nil, precision: 1, category: "基础"),
        3: .init(id: 3, title: "全身体脂率", sdkSemantic: "Body fat rate", unit: "%", precision: 1, category: "基础"),
        4: .init(id: 4, title: "皮下脂肪率", sdkSemantic: "Subcutaneous fat rate", unit: "%", precision: 1, category: "基础"),
        5: .init(id: 5, title: "内脏脂肪等级", sdkSemantic: "Visceral fat level", unit: nil, precision: 0, category: "基础"),
        6: .init(id: 6, title: "水分率", sdkSemantic: "Body water rate", unit: "%", precision: 1, category: "基础"),
        7: .init(id: 7, title: "骨骼肌率", sdkSemantic: "Skeletal muscle rate", unit: "%", precision: 1, category: "基础", notes: "官方头文件中的 QNScaleTypeMuscleRate"),
        8: .init(id: 8, title: "骨量", sdkSemantic: "Bone mass", unit: "kg", precision: 2, category: "基础"),
        9: .init(id: 9, title: "基础代谢", sdkSemantic: "BMR", unit: "kcal", precision: 0, category: "基础"),
        10: .init(id: 10, title: "体型", sdkSemantic: "Body type", unit: nil, precision: 0, category: "SDK 原值"),
        11: .init(id: 11, title: "蛋白质率", sdkSemantic: "Protein rate", unit: "%", precision: 1, category: "基础"),
        12: .init(id: 12, title: "去脂体重", sdkSemantic: "Lean body weight", unit: "kg", precision: 2, category: "基础"),
        13: .init(id: 13, title: "肌肉量", sdkSemantic: "Muscle mass", unit: "kg", precision: 2, category: "基础"),
        14: .init(id: 14, title: "体年龄", sdkSemantic: "Metabolic age", unit: "岁", precision: 0, category: "基础"),
        15: .init(id: 15, title: "健康评分", sdkSemantic: "Health score", unit: "分", precision: 1, category: "基础"),
        16: .init(id: 16, title: "心率", sdkSemantic: "Heart rate", unit: nil, precision: 0, category: "SDK 原值"),
        17: .init(id: 17, title: "心脏指数", sdkSemantic: "Heart index", unit: nil, precision: 2, category: "SDK 原值"),
        21: .init(id: 21, title: "脂肪量", sdkSemantic: "Fat mass", unit: "kg", precision: 2, category: "基础"),
        22: .init(id: 22, title: "肥胖度", sdkSemantic: "Obesity degree", unit: nil, precision: 1, category: "SDK 原值"),
        23: .init(id: 23, title: "含水量", sdkSemantic: "Water content", unit: "kg", precision: 2, category: "完整数据"),
        24: .init(id: 24, title: "蛋白质量", sdkSemantic: "Protein mass", unit: "kg", precision: 2, category: "完整数据"),
        25: .init(id: 25, title: "无机盐状况", sdkSemantic: "Mineral salt status", unit: nil, precision: 0, category: "SDK 原值"),
        26: .init(id: 26, title: "理想视觉体重", sdkSemantic: "Best visual weight", unit: "kg", precision: 2, category: "SDK 原值"),
        27: .init(id: 27, title: "标准体重", sdkSemantic: "Stand weight", unit: "kg", precision: 2, category: "SDK 原值"),
        28: .init(id: 28, title: "体重控制", sdkSemantic: "Weight control", unit: "kg", precision: 2, category: "SDK 原值"),
        29: .init(id: 29, title: "脂肪控制", sdkSemantic: "Fat control", unit: "kg", precision: 2, category: "SDK 原值"),
        30: .init(id: 30, title: "肌肉控制", sdkSemantic: "Muscle control", unit: "kg", precision: 2, category: "SDK 原值"),
        31: .init(id: 31, title: "肌肉率", sdkSemantic: "Muscle mass rate", unit: "%", precision: 1, category: "基础"),
        32: .init(id: 32, title: "脂肪肝风险等级", sdkSemantic: "Fatty liver risk", unit: "级", precision: 0, category: "基础", notes: "编码与等级顺序未在 SDK 头文件中定义"),
        33: .init(id: 33, title: "50kHz 阻抗", sdkSemantic: "Resistance 50kHz", unit: nil, precision: 0, category: "原始数据", notes: "单位未由 SDK 公开确认"),
        34: .init(id: 34, title: "500kHz 阻抗", sdkSemantic: "Resistance 500kHz", unit: nil, precision: 0, category: "原始数据", notes: "单位未由 SDK 公开确认"),
        35: .init(id: 35, title: "皮下脂肪量", sdkSemantic: "Subcutaneous fat mass", unit: "kg", precision: 2, category: "基础"),
        36: .init(id: 36, title: "四肢骨骼肌指数 SMI", sdkSemantic: "Skeletal muscle index", unit: nil, precision: 1, category: "基础"),
        37: .init(id: 37, title: "腰臀比", sdkSemantic: "Waist-hip ratio", unit: nil, precision: 2, category: "完整数据"),
        38: .init(id: 38, title: "肥胖等级", sdkSemantic: "Obesity level", unit: nil, precision: 0, category: "SDK 原值"),
        101: .init(id: 101, title: "右臂肌肉量", sdkSemantic: "Right arm muscle weight", unit: "kg", precision: 2, category: "五段肌肉"),
        102: .init(id: 102, title: "左臂肌肉量", sdkSemantic: "Left arm muscle weight", unit: "kg", precision: 2, category: "五段肌肉"),
        103: .init(id: 103, title: "躯干肌肉量", sdkSemantic: "Trunk muscle weight", unit: "kg", precision: 2, category: "五段肌肉"),
        104: .init(id: 104, title: "右腿肌肉量", sdkSemantic: "Right leg muscle weight", unit: "kg", precision: 2, category: "五段肌肉"),
        105: .init(id: 105, title: "左腿肌肉量", sdkSemantic: "Left leg muscle weight", unit: "kg", precision: 2, category: "五段肌肉"),
        106: .init(id: 106, title: "右臂脂肪指标", sdkSemantic: "Right arm fat index", unit: nil, precision: 2, category: "五段脂肪原值", notes: "SDK 仅标注脂肪率，分母未确认"),
        107: .init(id: 107, title: "左臂脂肪指标", sdkSemantic: "Left arm fat index", unit: nil, precision: 2, category: "五段脂肪原值", notes: "SDK 仅标注脂肪率，分母未确认"),
        108: .init(id: 108, title: "躯干脂肪指标", sdkSemantic: "Trunk fat index", unit: nil, precision: 2, category: "五段脂肪原值", notes: "SDK 仅标注脂肪率，分母未确认"),
        109: .init(id: 109, title: "右腿脂肪指标", sdkSemantic: "Right leg fat index", unit: nil, precision: 2, category: "五段脂肪原值", notes: "SDK 仅标注脂肪率，分母未确认"),
        110: .init(id: 110, title: "左腿脂肪指标", sdkSemantic: "Left leg fat index", unit: nil, precision: 2, category: "五段脂肪原值", notes: "SDK 仅标注脂肪率，分母未确认"),
        111: .init(id: 111, title: "无机盐比例", sdkSemantic: "Mineral salt rate", unit: "%", precision: 1, category: "全身"),
        112: .init(id: 112, title: "骨骼肌量", sdkSemantic: "Skeletal muscle mass", unit: "kg", precision: 2, category: "全身"),
        113: .init(id: 113, title: "右臂脂肪量", sdkSemantic: "Right arm fat mass", unit: nil, precision: 2, category: "五段脂肪", notes: "当前 SDK 公开头文件未确认分段单位"),
        114: .init(id: 114, title: "左臂脂肪量", sdkSemantic: "Left arm fat mass", unit: nil, precision: 2, category: "五段脂肪", notes: "当前 SDK 公开头文件未确认分段单位"),
        115: .init(id: 115, title: "躯干脂肪量", sdkSemantic: "Trunk fat mass", unit: nil, precision: 2, category: "五段脂肪", notes: "当前 SDK 公开头文件未确认分段单位"),
        116: .init(id: 116, title: "右腿脂肪量", sdkSemantic: "Right leg fat mass", unit: nil, precision: 2, category: "五段脂肪", notes: "当前 SDK 公开头文件未确认分段单位"),
        117: .init(id: 117, title: "左腿脂肪量", sdkSemantic: "Left leg fat mass", unit: nil, precision: 2, category: "五段脂肪", notes: "当前 SDK 公开头文件未确认分段单位"),
        118: .init(id: 118, title: "左臂肌肉比例", sdkSemantic: "Left arm muscle index", unit: nil, precision: 2, category: "五段肌肉原值", notes: "分母和单位未确认"),
        119: .init(id: 119, title: "右臂肌肉比例", sdkSemantic: "Right arm muscle index", unit: nil, precision: 2, category: "五段肌肉原值", notes: "分母和单位未确认"),
        120: .init(id: 120, title: "躯干肌肉比例", sdkSemantic: "Trunk muscle index", unit: nil, precision: 2, category: "五段肌肉原值", notes: "分母和单位未确认"),
        121: .init(id: 121, title: "左腿肌肉比例", sdkSemantic: "Left leg muscle index", unit: nil, precision: 2, category: "五段肌肉原值", notes: "分母和单位未确认"),
        122: .init(id: 122, title: "右腿肌肉比例", sdkSemantic: "Right leg muscle index", unit: nil, precision: 2, category: "五段肌肉原值", notes: "分母和单位未确认")
    ]

    static let reportTypes = [1, 15, 2, 3, 21, 35, 4, 5, 6, 112, 7, 36, 8, 9, 11, 13, 14, 32, 12]
    static let segmentMuscleTypes = [101, 102, 103, 104, 105]
    static let segmentFatTypes = [113, 114, 115, 116, 117]
    static let segmentRawTypes = Array(106...110) + Array(118...122)
    static let comparisonTypes = reportTypes + Array(101...122)

    static func definition(for type: Int) -> MetricDefinition {
        definitions[type] ?? MetricDefinition(id: type, title: "SDK 指标 \(type)", sdkSemantic: "未识别指标", unit: nil, precision: 2, category: "未识别", notes: "原始指标保留在 rawItemsJSON")
    }
}
