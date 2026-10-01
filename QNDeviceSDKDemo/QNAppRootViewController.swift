import SwiftUI
import UIKit

@objc(QNAppRootViewController)
public final class QNAppRootViewController: UIViewController {
    private let store = QNAppStore()

    public override func viewDidLoad() {
        super.viewDidLoad()
        let controller = UIHostingController(rootView: QNRootView().environmentObject(store))
        addChild(controller)
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controller.view)
        NSLayoutConstraint.activate([
            controller.view.topAnchor.constraint(equalTo: view.topAnchor),
            controller.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controller.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        controller.didMove(toParent: self)
    }
}

private enum QNDesign {
    static let blue = Color(uiColor: .systemBlue)
    static let muscle = Color(red: 0.10, green: 0.68, blue: 0.64)
    static let fat = Color.orange
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
}

private struct QNRootView: View {
    @EnvironmentObject private var store: QNAppStore

    var body: some View {
        Group {
            if store.hasValidProfile {
                QNMainTabView()
            } else {
                QNProfileEditorView(profile: store.profile, isRequired: true)
            }
        }
        .preferredColorScheme(nil)
    }
}

private struct QNMainTabView: View {
    @EnvironmentObject private var store: QNAppStore
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            QNDashboardView(onMeasure: { selectedTab = 2 }).tabItem { Label("首页", systemImage: "heart.text.square") }.tag(0)
            QNTrendView().tabItem { Label("趋势", systemImage: "chart.xyaxis.line") }.tag(1)
            QNMeasurementView().tabItem { Label("测量", systemImage: "scalemass") }.tag(2)
            QNProfileView().tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(3)
        }
        .tint(QNDesign.blue)
        .environmentObject(store)
    }
}

private struct QNDashboardView: View {
    @EnvironmentObject private var store: QNAppStore
    let onMeasure: () -> Void

    private var latest: QNMeasurementSnapshot? { store.records.first }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("身体数据").font(.largeTitle.weight(.bold))
                        Text(latest.map { "最近测量 · \($0.displayDate)" } ?? "还没有测量记录").foregroundStyle(.secondary)
                    }
                    if let latest {
                        QNWeightCard(snapshot: latest)
                        HStack(spacing: 12) {
                            QNMetricCard(title: "体脂率", value: latest.bodyFatRate, definition: QNMetricCatalog.definition(for: 3))
                            QNMetricCard(title: "肌肉量", value: latest.muscleMass, definition: QNMetricCatalog.definition(for: 13))
                        }
                        HStack(spacing: 12) {
                            QNMetricCard(title: "骨骼肌量", value: latest.skeletalMuscleMass, definition: QNMetricCatalog.definition(for: 112))
                            QNMetricCard(title: "BMI", value: latest.bmi, definition: QNMetricCatalog.definition(for: 2))
                        }
                        QNSegmentCard(snapshot: latest)
                        QNButton(title: "开始测量", systemImage: "plus.circle.fill", action: onMeasure)
                    } else {
                        QNEmptyState(title: "开始建立你的身体数据", message: "连接体脂秤完成第一次测量后，数据会保存在此 iPhone 上。", buttonTitle: "开始第一次测量", action: onMeasure)
                    }
                    if let error = store.lastError { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                .padding(20)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct QNWeightCard: View {
    let snapshot: QNMeasurementSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("体重").foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(snapshot.weight.map { String(format: "%.1f", $0) } ?? "—").font(.system(size: 54, weight: .semibold, design: .rounded).monospacedDigit())
                Text("kg").font(.title3).foregroundStyle(.secondary)
            }
            Text(snapshot.isAbnormal ? "本次测量异常，原始数据已保留" : "SDK 原始结果已保存").font(.footnote).foregroundStyle(snapshot.isAbnormal ? .orange : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct QNMetricCard: View {
    let title: String
    let value: Double?
    let definition: MetricDefinition
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Text(value.map { Self.format($0, precision: definition.precision) } ?? "—").font(.title2.weight(.semibold).monospacedDigit())
            if let unit = definition.unit { Text(unit).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private static func format(_ value: Double, precision: Int) -> String {
        switch precision {
        case 0: return String(format: "%.0f", value)
        case 2: return String(format: "%.2f", value)
        default: return String(format: "%.1f", value)
        }
    }
}

private struct QNSegmentCard: View {
    let snapshot: QNMeasurementSnapshot
    @State private var mode = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("身体分段").font(.title3.weight(.semibold))
            Picker("分段指标", selection: $mode) { Text("肌肉").tag(0); Text("脂肪").tag(1) }.pickerStyle(.segmented)
            QNSegmentBody(snapshot: snapshot, showFat: mode == 1)
        }
        .padding(16)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

private struct QNSegmentBody: View {
    let snapshot: QNMeasurementSnapshot
    let showFat: Bool
    @State private var selected = "躯干"

    private let regions = ["右臂", "左臂", "躯干", "右腿", "左腿"]
    private func value(for region: String) -> Double? {
        let key: String
        if showFat { key = ["右臂":"rightArmFatMass", "左臂":"leftArmFatMass", "躯干":"trunkFatMass", "右腿":"rightLegFatMass", "左腿":"leftLegFatMass"][region]! }
        else { key = ["右臂":"rightArmMuscleMass", "左臂":"leftArmMuscleMass", "躯干":"trunkMuscleMass", "右腿":"rightLegMuscleMass", "左腿":"leftLegMuscleMass"][region]! }
        return snapshot.metrics[key]
    }

    var body: some View {
        VStack(spacing: 10) {
            GeometryReader { proxy in
                ZStack {
                    Canvas { context, size in
                        var path = Path(); path.addEllipse(in: CGRect(x: size.width * 0.43, y: 0, width: size.width * 0.14, height: size.width * 0.14)); context.fill(path, with: .color(.secondary.opacity(0.18)))
                        var torso = Path(); torso.addRoundedRect(in: CGRect(x: size.width * 0.38, y: size.width * 0.16, width: size.width * 0.24, height: size.height * 0.38), cornerSize: CGSize(width: 20, height: 20)); context.fill(torso, with: .color(.secondary.opacity(0.18)))
                        var leftArm = Path(); leftArm.addRoundedRect(in: CGRect(x: size.width * 0.20, y: size.width * 0.18, width: size.width * 0.13, height: size.height * 0.34), cornerSize: CGSize(width: 18, height: 18)); context.fill(leftArm, with: .color(.secondary.opacity(0.18)))
                        var rightArm = Path(); rightArm.addRoundedRect(in: CGRect(x: size.width * 0.67, y: size.width * 0.18, width: size.width * 0.13, height: size.height * 0.34), cornerSize: CGSize(width: 18, height: 18)); context.fill(rightArm, with: .color(.secondary.opacity(0.18)))
                        var leftLeg = Path(); leftLeg.addRoundedRect(in: CGRect(x: size.width * 0.39, y: size.height * 0.56, width: size.width * 0.10, height: size.height * 0.36), cornerSize: CGSize(width: 18, height: 18)); context.fill(leftLeg, with: .color(.secondary.opacity(0.18)))
                        var rightLeg = Path(); rightLeg.addRoundedRect(in: CGRect(x: size.width * 0.51, y: size.height * 0.56, width: size.width * 0.10, height: size.height * 0.36), cornerSize: CGSize(width: 18, height: 18)); context.fill(rightLeg, with: .color(.secondary.opacity(0.18)))
                    }
                    regionButton("右臂", x: 0.12, y: 0.34, width: 0.28, height: 0.30, proxy: proxy)
                    regionButton("左臂", x: 0.88, y: 0.34, width: 0.28, height: 0.30, proxy: proxy)
                    regionButton("躯干", x: 0.50, y: 0.34, width: 0.35, height: 0.35, proxy: proxy)
                    regionButton("右腿", x: 0.43, y: 0.74, width: 0.30, height: 0.32, proxy: proxy)
                    regionButton("左腿", x: 0.57, y: 0.74, width: 0.30, height: 0.32, proxy: proxy)
                }
            }
            .frame(height: 230)
            Text("当前区域：\(selected) · \(value(for: selected).map { String(format: "%.1f", $0) } ?? "—")").font(.subheadline).foregroundStyle(.secondary)
            HStack { ForEach(regions, id: \.self) { region in Text("\(region)：\(value(for: region).map { String(format: "%.1f", $0) } ?? "—")").font(.caption).frame(maxWidth: .infinity) } }.accessibilityElement(children: .combine)
        }
    }

    private func regionButton(_ region: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, proxy: GeometryProxy) -> some View {
        Button { selected = region } label: {
            RoundedRectangle(cornerRadius: 12).fill(selected == region ? (showFat ? QNDesign.fat : QNDesign.muscle).opacity(0.85) : Color.clear).frame(width: proxy.size.width * width, height: proxy.size.height * height).overlay(Text(region).font(.caption.weight(.semibold)).foregroundStyle(selected == region ? .white : .primary))
        }
        .position(x: proxy.size.width * x, y: proxy.size.height * y)
        .accessibilityLabel("\(region)\(showFat ? "脂肪量" : "肌肉量")")
        .accessibilityValue(value(for: region).map { String(format: "%.1f", $0) } ?? "缺失")
    }
}

private struct QNMeasurementView: View {
    @EnvironmentObject private var store: QNAppStore
    @State private var report: QNMeasurementSnapshot?
    @State private var shareURL: QNShareItem?
    @State private var selectedIndex: Int?

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("测量").font(.largeTitle.weight(.bold))
                        Text(store.serviceState).font(.subheadline).foregroundStyle(.secondary)
                        HStack { Text("实时重量").foregroundStyle(.secondary); Spacer(); Text(store.weight.map { String(format: "%.1f kg", $0) } ?? "—").font(.title2.weight(.semibold).monospacedDigit()) }
                            .padding(16).background(QNDesign.card).clipShape(RoundedRectangle(cornerRadius: 16))
                        Text(store.measurementState).font(.headline)
                        Text("请赤脚站上体脂秤，并握住手柄。名称 QN-Scale 与型号仅作提示，可手动选择扫描到的设备。").font(.footnote).foregroundStyle(.secondary)
                        ForEach(Array(store.devices.enumerated()), id: \.element.id) { index, device in
                            Button { selectedIndex = index } label: {
                                HStack {
                                    Image(systemName: selectedIndex == index ? "checkmark.circle.fill" : "circle").foregroundStyle(QNDesign.blue)
                                    VStack(alignment: .leading) { Text(device.name); Text("\(device.modeId) · \(device.deviceType) · \(device.supportsEightElectrodes ? "八电极" : "普通")").font(.caption).foregroundStyle(.secondary) }
                                    Spacer(); Text(device.rssi).font(.caption).foregroundStyle(.secondary)
                                }.padding(12).background(QNDesign.card).clipShape(RoundedRectangle(cornerRadius: 14))
                            }.buttonStyle(.plain)
                        }
                    }.padding(20)
                }
                HStack(spacing: 12) {
                    QNButton(title: "扫描", systemImage: "antenna.radiowaves.left.and.right") { store.startScan() }
                    if store.isConnected {
                        QNButton(title: "断开", systemImage: "link.badge.minus") { store.disconnect() }
                    } else {
                        QNButton(title: "连接", systemImage: "link") { if let selectedIndex { store.connect(index: selectedIndex) } }
                    }
                }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 12).background(.bar)
            }
            .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: store.lastSavedMeasurement?.id) { _ in report = store.lastSavedMeasurement }
            .sheet(item: $report) { snapshot in QNReportView(snapshot: snapshot, onExport: { shareURL = store.export(snapshot).map { QNShareItem(url: $0) } }) }
            .sheet(item: $shareURL) { item in QNShareSheet(items: [item.url]) }
        }
    }
}

private struct QNTrendView: View {
    @EnvironmentObject private var store: QNAppStore
    @State private var range = 30
    @State private var metric = "weight"
    @State private var showComparison = false
    private let metrics = [("weight", "体重"), ("bodyFatRate", "体脂率"), ("fatMass", "脂肪量"), ("muscleMass", "肌肉量"), ("skeletalMuscleMass", "骨骼肌量"), ("bmi", "BMI"), ("bodyWaterRate", "水分率"), ("visceralFat", "内脏脂肪"), ("smi", "SMI")]

    private var filtered: [QNMeasurementSnapshot] {
        guard range > 0 else { return store.records }
        let cutoff = Calendar.current.date(byAdding: .day, value: -range, to: Date()) ?? .distantPast
        return store.records.filter { $0.measureTime >= cutoff }.sorted { $0.measureTime < $1.measureTime }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("趋势").font(.largeTitle.weight(.bold))
                    Picker("指标", selection: $metric) { ForEach(metrics, id: \.0) { Text($0.1).tag($0.0) } }.pickerStyle(.menu)
                    ScrollView(.horizontal, showsIndicators: false) { HStack { ForEach([(7,"7天"),(30,"30天"),(90,"3个月"),(180,"6个月"),(365,"1年"),(0,"全部")], id: \.0) { item in Button(item.1) { range = item.0 }.buttonStyle(.borderedProminent).tint(range == item.0 ? QNDesign.blue : .gray.opacity(0.25)).foregroundStyle(range == item.0 ? .white : .primary) } } }
                    QNButton(title: "选择两次记录对比", systemImage: "arrow.left.arrow.right") { showComparison = true }
                    if filtered.isEmpty { QNEmptyState(title: "暂无趋势数据", message: "完成至少一次真实测量后，这里会从本地数据库读取记录。", buttonTitle: nil, action: nil) }
                    else {
                        QNTrendChart(records: filtered, metric: metric)
                        let values = filtered.compactMap { $0.metrics[metric] }
                        VStack(alignment: .leading, spacing: 8) { Text("统计").font(.headline); Text("当前：\(values.last.map { String(format: "%.1f", $0) } ?? "—")    起始：\(values.first.map { String(format: "%.1f", $0) } ?? "—")"); if let min = values.min(), let max = values.max() { Text("最低：\(String(format: "%.1f", min))    最高：\(String(format: "%.1f", max))    变化：\(String(format: "%+.1f", (values.last ?? min) - (values.first ?? min)))") } }.font(.subheadline).foregroundStyle(.secondary)
                        if filtered.count == 1 { Text("需要更多测量数据才能形成趋势").font(.footnote).foregroundStyle(.secondary) }
                    }
                }.padding(20)
            }.background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea()).navigationBarTitleDisplayMode(.inline)
                .sheet(isPresented: $showComparison) { QNComparisonPickerView() }
        }
    }
}

private struct QNTrendChart: View {
    let records: [QNMeasurementSnapshot]
    let metric: String
    var body: some View {
        let values = records.compactMap { $0.metrics[metric] }
        return Canvas { context, size in
            guard values.count > 0 else { return }
            let minValue = values.min() ?? 0; let maxValue = values.max() ?? 1; let span = max(maxValue - minValue, 0.1)
            var path = Path()
            for (index, value) in values.enumerated() { let x = values.count == 1 ? size.width / 2 : size.width * CGFloat(index) / CGFloat(values.count - 1); let y = size.height - CGFloat((value - minValue) / span) * (size.height - 20) - 10; if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) } }
            context.stroke(path, with: .color(QNDesign.blue), lineWidth: 3)
            for (index, value) in values.enumerated() { let x = values.count == 1 ? size.width / 2 : size.width * CGFloat(index) / CGFloat(values.count - 1); let y = size.height - CGFloat((value - minValue) / span) * (size.height - 20) - 10; context.fill(Path(ellipseIn: CGRect(x: x - 5, y: y - 5, width: 10, height: 10)), with: .color(QNDesign.blue)) }
        }.frame(height: 220).padding(12).background(.background).clipShape(RoundedRectangle(cornerRadius: 16)).accessibilityLabel("趋势折线图，共 \(records.count) 条真实测量记录")
    }
}

private struct QNComparisonPickerView: View {
    @EnvironmentObject private var store: QNAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var startID: UUID?
    @State private var endID: UUID?
    @State private var comparison: QNMeasurementComparison?

    var body: some View {
        NavigationView {
            Form {
                Section("选择起点和终点") {
                    Picker("起点", selection: $startID) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(store.records.sorted { $0.measureTime < $1.measureTime }) { record in
                            Text(record.displayDate).tag(Optional(record.id))
                        }
                    }
                    Picker("终点", selection: $endID) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(store.records.sorted { $0.measureTime < $1.measureTime }) { record in
                            Text(record.displayDate).tag(Optional(record.id))
                        }
                    }
                }
                Section {
                    if store.records.count < 2 {
                        Text("至少需要两条真实测量记录，不能生成演示数据。").foregroundStyle(.secondary)
                    } else {
                        Button("查看变化") {
                            guard let startID, let endID,
                                  let start = store.records.first(where: { $0.id == startID }),
                                  let end = store.records.first(where: { $0.id == endID }) else { return }
                            comparison = QNHistoryComparisonService.compare(start: start, end: end)
                        }
                        .disabled(startID == nil || endID == nil || startID == endID)
                    }
                }
            }
            .navigationTitle("选择对比记录")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .sheet(item: $comparison) { QNComparisonView(comparison: $0) }
        }
    }
}

private struct QNComparisonView: View {
    let comparison: QNMeasurementComparison

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("体重变化").font(.headline)
                        Text(format(comparison.rows.first?.difference, precision: 2, unit: "kg"))
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                        Text("起点 \(comparison.start.displayDate) → 终点 \(comparison.end.displayDate)，相隔 \(comparison.intervalDays) 天").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("指标变化") {
                    ForEach(comparison.rows) { row in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text(row.title).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(row.comparable ? format(row.difference, precision: row.precision, unit: row.unit) : "仅显示两端值")
                                    .foregroundStyle(row.comparable ? QNDesign.blue : .secondary)
                            }
                            HStack {
                                Text("\(format(row.start, precision: row.precision, unit: row.unit)) → \(format(row.end, precision: row.precision, unit: row.unit))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("身体变化")
        }
    }

    private func format(_ value: Double?, precision: Int, unit: String?) -> String {
        guard let value else { return "—" }
        let format = precision == 0 ? "%.0f" : (precision == 1 ? "%.1f" : "%.2f")
        let number = String(format: format, value)
        return unit.map { "\(number) \($0)" } ?? number
    }
}

private struct QNReportView: View {
    let snapshot: QNMeasurementSnapshot
    let onExport: () -> Void
    @State private var showRaw = false
    @State private var segmentMode = 0
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(snapshot.displayDate).font(.subheadline).foregroundStyle(.secondary)
                    QNWeightCard(snapshot: snapshot)
                    Text("核心指标").font(.title2.weight(.bold))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) { ForEach(QNMetricCatalog.reportTypes, id: \.self) { type in reportCard(type) } }
                    Text("身体分段").font(.title2.weight(.bold))
                    Picker("模式", selection: $segmentMode) { Text("肌肉").tag(0); Text("脂肪").tag(1) }.pickerStyle(.segmented)
                    QNSegmentBody(snapshot: snapshot, showFat: segmentMode == 1)
                    Text("全部 SDK 指标").font(.title2.weight(.bold))
                    QNAllItemsView(snapshot: snapshot)
                    DisclosureGroup("原始信息", isExpanded: $showRaw) { VStack(alignment: .leading, spacing: 6) { Text("resistance50：\(snapshot.resistance50.map(String.init) ?? "—")"); Text("resistance500：\(snapshot.resistance500.map(String.init) ?? "—")"); Text("newEightModel：\(snapshot.newEightModel.map(String.init) ?? "—")"); Text("eightIsAbnormal：\(snapshot.eightIsAbnormal.map(String.init) ?? "—")"); Text("eightReasonMask：\(snapshot.eightReasonMask.map(String.init) ?? "—")"); Text("modeId：\(snapshot.modeId ?? "—")"); Text("SDK：\(snapshot.sdkVersion ?? "—")"); Text("HMAC：\(snapshot.hmac ?? "—")").textSelection(.enabled) }.font(.footnote.monospaced()) }
                    QNButton(title: "导出本次原始 JSON", systemImage: "square.and.arrow.up", action: onExport)
                }.padding(20)
            }.navigationTitle("测量报告").navigationBarTitleDisplayMode(.inline)
        }
    }
    @ViewBuilder private func reportCard(_ type: Int) -> some View {
        let definition = QNMetricCatalog.definition(for: type)
        let value = snapshot.metrics[Self.key(for: type)] ?? snapshot.metrics["type\(type)"]
        VStack(alignment: .leading, spacing: 6) {
            QNMetricCard(title: definition.title, value: value, definition: definition)
            if let evaluation = QNReferenceRangeService.evaluation(for: Self.key(for: type), value: value, gender: snapshot.gender) {
                Text(evaluation.label).font(.caption.weight(.semibold)).foregroundStyle(evaluation.label.contains("偏高") || evaluation.label.contains("肥胖") ? .orange : .secondary)
            }
        }
    }

    private static func key(for type: Int) -> String { [1:"weight",2:"bmi",3:"bodyFatRate",4:"subcutaneousFatRate",5:"visceralFat",6:"bodyWaterRate",7:"skeletalMuscleRate",8:"boneMass",9:"bmr",11:"proteinRate",12:"leanBodyWeight",13:"muscleMass",14:"metabolicAge",15:"healthScore",21:"fatMass",31:"muscleMassRate",32:"fattyLiverRisk",35:"subcutaneousFatMass",36:"smi",37:"waistHipRatio",112:"skeletalMuscleMass"][type] ?? "type\(type)" }
}

private struct QNAllItemsView: View {
    let snapshot: QNMeasurementSnapshot
    var items: [[String: Any]] { guard let data = snapshot.rawItemsJSON?.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }; return value }
    var body: some View { VStack(alignment: .leading, spacing: 10) { ForEach(Array(items.enumerated()), id: \.offset) { _, item in let type=(item["type"] as? NSNumber)?.intValue ?? 0; let definition=QNMetricCatalog.definition(for:type); HStack(alignment: .firstTextBaseline) { Text("T\(type)").font(.caption.monospaced()).frame(width: 42, alignment: .leading); VStack(alignment: .leading) { Text((item["name"] as? String) ?? definition.title); Text("\(definition.title) · \(item["valueTypeName"] as? String ?? "SDK 原值")").font(.caption).foregroundStyle(.secondary) }; Spacer(); Text(Self.value(item["value"])).monospacedDigit(); if let unit = definition.unit { Text(unit).font(.caption).foregroundStyle(.secondary) } } } }.font(.subheadline) }
    private static func value(_ value: Any?) -> String { if let value=value as? NSNumber { return String(format:"%.3f", value.doubleValue) }; return value.map { "\($0)" } ?? "—" }
}

private struct QNProfileView: View {
    @EnvironmentObject private var store: QNAppStore
    @State private var showEditor = false
    @State private var showHistory = false
    @State private var showDeveloper = false
    @State private var shareURL: QNShareItem?
    var body: some View {
        NavigationView {
            List {
                Section("用户资料") {
                    if let profile = store.profile {
                        QNInfoRow(title: "昵称", value: profile.nickname)
                        QNInfoRow(title: "性别", value: profile.genderText)
                        QNInfoRow(title: "身高", value: "\(String(format: "%.0f", profile.height)) cm")
                        QNInfoRow(title: "模式", value: profile.athleteText)
                        QNInfoRow(title: "用户 ID", value: profile.userId)
                    }
                    Button("编辑资料") { showEditor = true }
                }
                Section("数据") {
                    Button("历史记录") { showHistory = true }
                    Button("导出全部历史 JSON") { shareURL = store.exportAllHistory().map { QNShareItem(url: $0) } }
                }
                Section("关于") {
                    Button("开发者模式") { showDeveloper = true }
                    Text("HealthKit 接口已预留，当前不请求权限、不写入健康数据").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $showEditor) { QNProfileEditorView(profile: store.profile, isRequired: false) }
            .sheet(isPresented: $showHistory) { QNHistoryView() }
            .sheet(isPresented: $showDeveloper) { QNDeveloperView() }
            .sheet(item: $shareURL) { item in QNShareSheet(items: [item.url]) }
        }
    }
}

private struct QNHistoryView: View {
    @EnvironmentObject private var store: QNAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var deleting: QNMeasurementSnapshot?
    @State private var report: QNMeasurementSnapshot?
    var body: some View { NavigationView { List { ForEach(store.records) { snapshot in Button { report=snapshot } label: { HStack { VStack(alignment:.leading) { Text(snapshot.displayDate); Text(snapshot.status == "abnormal" ? "异常结果已保留" : "正常结果").font(.caption).foregroundStyle(snapshot.isAbnormal ? .orange : .secondary) }; Spacer(); VStack(alignment:.trailing) { Text(snapshot.weight.map { String(format:"%.1f kg",$0) } ?? "—"); Text(snapshot.bodyFatRate.map { String(format:"%.1f",$0) } ?? "—").font(.caption).foregroundStyle(.secondary) } } }.buttonStyle(.plain).swipeActions { Button(role:.destructive) { deleting=snapshot } label: { Label("删除", systemImage:"trash") } } } }.navigationTitle("历史记录").toolbar { ToolbarItem(placement:.cancellationAction) { Button("完成") { dismiss() } } }.alert("删除这条测量？", isPresented: Binding(get:{deleting != nil},set:{if !$0{deleting=nil}})) { Button("取消",role:.cancel){deleting=nil}; Button("删除",role:.destructive){if let deleting{store.delete(deleting)};deleting=nil} }.sheet(item:$report) { QNReportView(snapshot:$0,onExport:{}) } } }
}

private struct QNDeveloperView: View {
    @EnvironmentObject private var store: QNAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: QNShareItem?
    var body: some View { NavigationView { ScrollView { VStack(alignment:.leading,spacing:16) { Text("SDK version：\(store.sdkVersion)"); Text("Bundle ID：\(store.bundleIdentifier)"); Text("App ID：\(QNScaleServiceAppId)"); Text(store.authorizationSummary).font(.footnote.monospaced()); Text("Debug Log").font(.headline); Text(store.debugLog).font(.caption.monospaced()).textSelection(.enabled); HStack { QNButton(title:"复制日志",systemImage:"doc.on.doc") { store.copyLogs() }; QNButton(title:"分享日志",systemImage:"square.and.arrow.up") { let url=FileManager.default.temporaryDirectory.appendingPathComponent("QNScaleDebugLog.txt"); try? store.debugLog.data(using:.utf8)?.write(to:url); shareURL=QNShareItem(url:url) } } }.padding(20) }.navigationTitle("开发者模式").toolbar { ToolbarItem(placement:.cancellationAction){Button("完成"){dismiss()}} }.sheet(item:$shareURL){item in QNShareSheet(items:[item.url])} } }
}

private struct QNProfileEditorView: View {
    @EnvironmentObject private var store: QNAppStore
    @Environment(\.dismiss) private var dismiss
    let existing: QNUserProfile?
    let isRequired: Bool
    @State private var nickname: String
    @State private var gender: String
    @State private var birthday: Date
    @State private var height: String
    @State private var athlete: Bool
    @State private var targetWeight: String

    init(profile: QNUserProfile?, isRequired: Bool) {
        existing = profile
        self.isRequired = isRequired
        _nickname = State(initialValue: profile?.nickname ?? "")
        _gender = State(initialValue: profile?.gender ?? "male")
        _birthday = State(initialValue: profile?.birthday ?? Date())
        _height = State(initialValue: profile.map { String(format: "%.0f", $0.height) } ?? "")
        _athlete = State(initialValue: profile?.athleteType == 1)
        _targetWeight = State(initialValue: profile?.targetWeight.map { String(format: "%.1f", $0) } ?? "")
    }

    var body: some View {
        NavigationView {
            Form {
                Section("资料") {
                    TextField("昵称", text: $nickname)
                    Picker("性别", selection: $gender) {
                        Text("男").tag("male")
                        Text("女").tag("female")
                    }
                    DatePicker("出生日期", selection: $birthday, in: ...Date(), displayedComponents: .date)
                    TextField("身高（cm）", text: $height).keyboardType(.decimalPad)
                    Toggle("运动员模式", isOn: $athlete)
                    TextField("目标体重（可选）", text: $targetWeight).keyboardType(.decimalPad)
                }
                Section {
                    Text("出生日期、性别、身高和模式会作为每次测量的用户快照；历史记录不会被重新计算。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(isRequired ? "建立资料" : "编辑资料")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Double(height) == nil)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }.disabled(isRequired).opacity(isRequired ? 0 : 1)
                }
            }
        }
    }
    private func save() { let value=QNUserProfile(userId:existing?.userId ?? UUID().uuidString,nickname:nickname.trimmingCharacters(in:.whitespacesAndNewlines),gender:gender,birthday:birthday,height:Double(height) ?? 0,athleteType:athlete ? 1 : 0,targetWeight:Double(targetWeight)); store.saveProfile(value); if value.isValid { dismiss() } }
}

private struct QNShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct QNInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
    }
}

private struct QNEmptyState: View { let title:String; let message:String; let buttonTitle:String?; let action:(() -> Void)?; var body: some View { VStack(spacing:12) { Image(systemName:"scalemass").font(.system(size:42)).foregroundStyle(QNDesign.blue); Text(title).font(.title3.weight(.semibold)); Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary); if let buttonTitle,let action { QNButton(title:buttonTitle,systemImage:"arrow.right",action:action) } }.frame(maxWidth:.infinity).padding(30).background(.background).clipShape(RoundedRectangle(cornerRadius:18)) } }
private struct QNButton: View { let title:String; let systemImage:String; let action:() -> Void; var body: some View { Button(action:action){Label(title,systemImage:systemImage).frame(maxWidth:.infinity).padding(.vertical,12)}.buttonStyle(.borderedProminent).tint(QNDesign.blue) } }
private struct QNShareSheet: UIViewControllerRepresentable { let items:[Any]; func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:items,applicationActivities:nil)}; func updateUIViewController(_ controller:UIActivityViewController,context:Context){} }
