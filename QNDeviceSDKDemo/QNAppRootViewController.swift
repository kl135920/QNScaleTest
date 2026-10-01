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
    static let blue = Color(red: 0.04, green: 0.48, blue: 0.98)
    static let cyan = Color(red: 0.03, green: 0.73, blue: 0.68)
    static let purple = Color(red: 0.43, green: 0.31, blue: 0.96)
    static let muscle = cyan
    static let fat = Color(red: 1.00, green: 0.48, blue: 0.12)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let page = Color(uiColor: .systemGroupedBackground)
    static let hairline = Color.primary.opacity(0.07)
    static let blueGradient = LinearGradient(colors: [Color(red: 0.05, green: 0.58, blue: 1.0), Color(red: 0.02, green: 0.38, blue: 0.96)], startPoint: .topLeading, endPoint: .bottomTrailing)
}

private extension View {
    func qnCard(cornerRadius: CGFloat = 22) -> some View {
        self
            .background(QNDesign.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).stroke(QNDesign.hairline, lineWidth: 0.5))
    }
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
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("身体数据")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text(latest.map { $0.displayDate } ?? "还没有测量记录")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let latest {
                        NavigationLink(destination: QNReportView(snapshot: latest, onExport: {})) {
                            QNWeightCard(snapshot: latest, showsDisclosure: true)
                        }
                        .buttonStyle(.plain)
                        HStack(spacing: 12) {
                            QNMetricCard(title: "体脂率", value: latest.bodyFatRate, definition: QNMetricCatalog.definition(for: 3), icon: "percent", tint: .orange, evaluation: QNReferenceRangeService.bodyFatRate(latest.bodyFatRate, gender: latest.gender)?.label)
                            QNMetricCard(title: "肌肉量", value: latest.muscleMass, definition: QNMetricCatalog.definition(for: 13), icon: "figure.strengthtraining.traditional", tint: QNDesign.muscle)
                        }
                        HStack(spacing: 12) {
                            QNMetricCard(title: "骨骼肌量", value: latest.skeletalMuscleMass, definition: QNMetricCatalog.definition(for: 112), icon: "figure.walk", tint: QNDesign.blue)
                            QNMetricCard(title: "BMI", value: latest.bmi, definition: QNMetricCatalog.definition(for: 2), icon: "chart.bar.fill", tint: QNDesign.purple, evaluation: QNReferenceRangeService.bmi(latest.bmi)?.label)
                        }
                        NavigationLink(destination: QNMetricReferenceView(snapshot: latest)) {
                            HStack(spacing: 12) {
                                Image(systemName: "list.clipboard.fill").foregroundStyle(QNDesign.blue)
                                Text("指标参考").font(.headline)
                                Spacer()
                                Text("查看评价与依据").font(.caption).foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .qnCard(cornerRadius: 18)
                        }
                        .buttonStyle(.plain)
                        QNSegmentCard(snapshot: latest)
                        QNButton(title: "开始测量", systemImage: "plus.circle.fill", action: onMeasure)
                    } else {
                        QNEmptyState(title: "开始建立你的身体数据", message: "连接体脂秤完成第一次测量后，数据会保存在此 iPhone 上。", buttonTitle: "开始第一次测量", action: onMeasure)
                    }
                    if store.pendingMeasurement != nil {
                        QNButton(title: "重试保存本次测量", systemImage: "arrow.clockwise") {
                            store.retryPendingSave()
                        }
                    }
                    if let error = store.lastError { Text(error).font(.footnote).foregroundStyle(.red) }
                }
                .padding(.horizontal, 16)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(QNDesign.page.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(true)
        }
    }
}

private struct QNWeightCard: View {
    let snapshot: QNMeasurementSnapshot
    var showsDisclosure = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最新体重").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if showsDisclosure { Image(systemName: "chevron.right").font(.headline).foregroundStyle(.tertiary) }
            }
            HStack(alignment: .lastTextBaseline, spacing: 7) {
                Text(snapshot.weight.map { String(format: "%.1f", $0) } ?? "—")
                    .font(.system(size: 58, weight: .bold, design: .rounded).monospacedDigit())
                Text("kg").font(.title2.weight(.semibold)).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                Label(snapshot.isAbnormal ? "异常结果已保留" : "测量结果已保存", systemImage: snapshot.isAbnormal ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(snapshot.isAbnormal ? .orange : QNDesign.muscle)
                Spacer()
                Text(snapshot.displayDate).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .qnCard()
    }
}

private struct QNMetricCard: View {
    let title: String
    let value: Double?
    let definition: MetricDefinition
    var icon: String? = nil
    var tint: Color = QNDesign.blue
    var evaluation: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 30, height: 30)
                        .background(tint)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value.map { Self.format($0, precision: definition.precision) } ?? "—")
                    .font(.system(size: 27, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.75)
                if let unit = definition.unit { Text(unit).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
            }
            if let evaluation {
                Text(evaluation)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(evaluation.contains("偏高") || evaluation.contains("肥胖") ? .orange : tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background((evaluation.contains("偏高") || evaluation.contains("肥胖") ? Color.orange : tint).opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .padding(16)
        .qnCard(cornerRadius: 20)
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
            HStack {
                Text("身体分段").font(.title3.weight(.bold))
                Spacer()
                Picker("分段指标", selection: $mode) { Text("肌肉").tag(0); Text("脂肪").tag(1) }
                    .pickerStyle(.segmented)
                    .frame(width: 190)
            }
            QNSegmentBody(snapshot: snapshot, showFat: mode == 1)
        }
        .padding(18)
        .qnCard()
    }
}

private struct QNSegmentBody: View {
    let snapshot: QNMeasurementSnapshot
    let showFat: Bool
    @State private var selected = "躯干"

    private let regions = ["右臂", "左臂", "躯干", "右腿", "左腿"]
    private var accent: Color { showFat ? QNDesign.fat : QNDesign.muscle }
    private func value(for region: String) -> Double? {
        let key: String
        if showFat { key = ["右臂":"rightArmFatMass", "左臂":"leftArmFatMass", "躯干":"trunkFatMass", "右腿":"rightLegFatMass", "左腿":"leftLegFatMass"][region]! }
        else { key = ["右臂":"rightArmMuscleMass", "左臂":"leftArmMuscleMass", "躯干":"trunkMuscleMass", "右腿":"rightLegMuscleMass", "左腿":"leftLegMuscleMass"][region]! }
        return snapshot.metrics[key]
    }

    var body: some View {
        VStack(spacing: 14) {
            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(Color.secondary.opacity(0.20))
                        .frame(width: proxy.size.width * 0.13)
                        .position(x: proxy.size.width * 0.5, y: proxy.size.height * 0.09)
                    regionButton("右臂", shape: Capsule(), x: 0.31, y: 0.39, width: 0.09, height: 0.38, rotation: 10, proxy: proxy)
                    regionButton("左臂", shape: Capsule(), x: 0.69, y: 0.39, width: 0.09, height: 0.38, rotation: -10, proxy: proxy)
                    regionButton("躯干", shape: RoundedRectangle(cornerRadius: 24, style: .continuous), x: 0.50, y: 0.38, width: 0.27, height: 0.38, proxy: proxy)
                    regionButton("右腿", shape: Capsule(), x: 0.43, y: 0.76, width: 0.10, height: 0.38, rotation: 3, proxy: proxy)
                    regionButton("左腿", shape: Capsule(), x: 0.57, y: 0.76, width: 0.10, height: 0.38, rotation: -3, proxy: proxy)
                }
            }
            .frame(height: 245)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                ForEach(regions, id: \.self) { region in
                    Button { selected = region } label: {
                        VStack(spacing: 3) {
                            Text(region).font(.caption).foregroundStyle(.secondary)
                            HStack(alignment: .lastTextBaseline, spacing: 2) {
                                Text(value(for: region).map { String(format: "%.1f", $0) } ?? "—").font(.subheadline.weight(.bold).monospacedDigit())
                                Text("kg").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(selected == region ? accent.opacity(0.14) : Color.primary.opacity(0.035))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected == region ? accent.opacity(0.65) : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func regionButton<S: Shape>(_ region: String, shape: S, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat, rotation: Double = 0, proxy: GeometryProxy) -> some View {
        Button { selected = region } label: {
            shape
                .fill(selected == region ? accent.opacity(0.88) : Color.secondary.opacity(0.18))
                .overlay(shape.stroke(selected == region ? accent.opacity(0.45) : Color.primary.opacity(0.06), lineWidth: 1))
                .frame(width: proxy.size.width * width, height: proxy.size.height * height)
                .rotationEffect(.degrees(rotation))
                .shadow(color: selected == region ? accent.opacity(0.22) : .clear, radius: 12)
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
        }.frame(height: 220).padding(16).qnCard(cornerRadius: 20).accessibilityLabel("趋势折线图，共 \(records.count) 条真实测量记录")
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
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(snapshot.displayDate).font(.subheadline).foregroundStyle(.secondary)
                            Label(snapshot.isAbnormal ? "异常结果已保留" : "已保存", systemImage: snapshot.isAbnormal ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(snapshot.isAbnormal ? .orange : QNDesign.muscle)
                        }
                        Spacer()
                    }
                    QNWeightCard(snapshot: snapshot)
                    Text("身体指标").font(.title2.weight(.bold))
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(QNMetricCatalog.reportTypes.filter { $0 != 1 }, id: \.self) { type in
                            reportCard(type)
                        }
                    }
                    QNSegmentCard(snapshot: snapshot)
                    DisclosureGroup(isExpanded: $showRaw) {
                        QNAllItemsView(snapshot: snapshot).padding(.top, 12)
                    } label: {
                        HStack {
                            Image(systemName: "list.number").foregroundStyle(QNDesign.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("全部 SDK 原始指标").font(.headline)
                                Text("保留类型、原名、原值和单位").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(16)
                    .qnCard(cornerRadius: 18)
                    DisclosureGroup("原始测量信息") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("resistance50：\(snapshot.resistance50.map(String.init) ?? "—")")
                            Text("resistance500：\(snapshot.resistance500.map(String.init) ?? "—")")
                            Text("newEightModel：\(snapshot.newEightModel.map(String.init) ?? "—")")
                            Text("eightIsAbnormal：\(snapshot.eightIsAbnormal.map(String.init) ?? "—")")
                            Text("eightReasonMask：\(snapshot.eightReasonMask.map(String.init) ?? "—")")
                            Text("modeId：\(snapshot.modeId ?? "—")")
                            Text("SDK：\(snapshot.sdkVersion ?? "—")")
                            Text("HMAC：\(snapshot.hmac ?? "—")").textSelection(.enabled)
                        }
                        .padding(.top, 10)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .qnCard(cornerRadius: 18)
                    QNButton(title: "导出本次原始 JSON", systemImage: "square.and.arrow.up", action: onExport)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            .background(QNDesign.page.ignoresSafeArea())
            .navigationTitle("测量报告")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    @ViewBuilder private func reportCard(_ type: Int) -> some View {
        let definition = QNMetricCatalog.definition(for: type)
        let value = snapshot.metrics[Self.key(for: type)] ?? snapshot.metrics["type\(type)"]
        VStack(alignment: .leading, spacing: 8) {
            Text(definition.title).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(Self.format(value, precision: definition.precision))
                    .font(.system(size: 23, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7)
                if let unit = definition.unit { Text(unit).font(.caption2).foregroundStyle(.secondary) }
            }
            if let evaluation = QNReferenceRangeService.evaluation(for: Self.key(for: type), value: value, gender: snapshot.gender) {
                Text(evaluation.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(evaluation.label.contains("偏高") || evaluation.label.contains("肥胖") ? .orange : QNDesign.muscle)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
        .padding(14)
        .qnCard(cornerRadius: 17)
    }

    private static func format(_ value: Double?, precision: Int) -> String {
        guard let value else { return "—" }
        if precision == 0 { return String(format: "%.0f", value) }
        if precision == 2 { return String(format: "%.2f", value) }
        return String(format: "%.1f", value)
    }

    private static func key(for type: Int) -> String { [1:"weight",2:"bmi",3:"bodyFatRate",4:"subcutaneousFatRate",5:"visceralFat",6:"bodyWaterRate",7:"skeletalMuscleRate",8:"boneMass",9:"bmr",11:"proteinRate",12:"leanBodyWeight",13:"muscleMass",14:"metabolicAge",15:"healthScore",21:"fatMass",31:"muscleMassRate",32:"fattyLiverRisk",35:"subcutaneousFatMass",36:"smi",37:"waistHipRatio",112:"skeletalMuscleMass"][type] ?? "type\(type)" }
}

private struct QNAllItemsView: View {
    let snapshot: QNMeasurementSnapshot
    var items: [[String: Any]] { guard let data = snapshot.rawItemsJSON?.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }; return value }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let type = (item["type"] as? NSNumber)?.intValue ?? 0
                let definition = QNMetricCatalog.definition(for: type)
                HStack(alignment: .center, spacing: 10) {
                    Text("T\(type)").font(.caption.monospaced().weight(.semibold)).foregroundStyle(QNDesign.blue).frame(width: 42, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(definition.title).font(.subheadline.weight(.medium))
                        Text((item["name"] as? String) ?? definition.sdkSemantic).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(Self.value(item["value"])).font(.subheadline.weight(.semibold).monospacedDigit())
                    if let unit = definition.unit { Text(unit).font(.caption2).foregroundStyle(.secondary) }
                }
                .padding(.vertical, 10)
                if index < items.count - 1 { Divider() }
            }
        }
    }
    private static func value(_ value: Any?) -> String { if let value=value as? NSNumber { return String(format:"%.3f", value.doubleValue) }; return value.map { "\($0)" } ?? "—" }
}

private struct QNMetricReferenceView: View {
    let snapshot: QNMeasurementSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("参考测量时的资料 · \(snapshot.gender == "female" ? "女性" : "男性") · \(snapshot.height.map { String(format: "%.0f cm", $0) } ?? "身高未知")")
                    .font(.subheadline).foregroundStyle(.secondary)
                QNReferenceCard(title: "BMI", value: snapshot.bmi, unit: "kg/m²", evaluation: QNReferenceRangeService.bmi(snapshot.bmi), lowerBound: 15, upperBound: 36, tint: QNDesign.purple)
                QNReferenceCard(title: "体脂率", value: snapshot.bodyFatRate, unit: "%", evaluation: QNReferenceRangeService.bodyFatRate(snapshot.bodyFatRate, gender: snapshot.gender), lowerBound: 8, upperBound: 40, tint: .orange)
                VStack(alignment: .leading, spacing: 8) {
                    Text("肌肉量").font(.headline)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(snapshot.muscleMass.map { String(format: "%.1f", $0) } ?? "—").font(.system(size: 38, weight: .bold, design: .rounded))
                        Text("kg").foregroundStyle(.secondary)
                    }
                    Text("当前未采用未经确认的肌肉量参考范围，仅展示 SDK 原始数值和历史趋势。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(18).qnCard()
                Text("参考依据：\(QNReferenceRangeService.source)")
                    .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
            .padding(16)
        }
        .background(QNDesign.page.ignoresSafeArea())
        .navigationTitle("指标参考")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct QNReferenceCard: View {
    let title: String
    let value: Double?
    let unit: String
    let evaluation: QNReferenceEvaluation?
    let lowerBound: Double
    let upperBound: Double
    let tint: Color

    private var progress: CGFloat {
        guard let value else { return 0 }
        return CGFloat(min(max((value - lowerBound) / (upperBound - lowerBound), 0), 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(value.map { String(format: "%.1f", $0) } ?? "—").font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                Text(unit).font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if let evaluation {
                    Text(evaluation.label).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
                        .padding(.horizontal, 11).padding(.vertical, 6).background(tint.opacity(0.12)).clipShape(Capsule())
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(LinearGradient(colors: [Color.cyan, Color.green, Color.yellow, Color.orange, Color.red], startPoint: .leading, endPoint: .trailing)).frame(height: 12)
                    Circle().fill(.white).frame(width: 18, height: 18).overlay(Circle().stroke(tint, lineWidth: 3)).shadow(radius: 2)
                        .offset(x: max(0, min(proxy.size.width - 18, proxy.size.width * progress - 9)))
                }
            }
            .frame(height: 18)
            if let evaluation { Text(evaluation.detail).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(18).qnCard()
    }
}

private struct QNProfileView: View {
    @EnvironmentObject private var store: QNAppStore
    @State private var showEditor = false
    @State private var showHistory = false
    @State private var showDeveloper = false
    @State private var shareURL: QNShareItem?
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("我的").font(.system(size: 36, weight: .bold, design: .rounded))
                    if let profile = store.profile {
                        Button { showEditor = true } label: {
                            HStack(spacing: 16) {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 48)).foregroundStyle(QNDesign.blue)
                                    .frame(width: 58, height: 58)
                                    .background(QNDesign.blue.opacity(0.10)).clipShape(Circle())
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(profile.nickname).font(.title3.weight(.bold))
                                    Text("\(profile.genderText) · \(String(format: "%.0f", profile.height)) cm")
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                            .padding(18).qnCard()
                        }
                        .buttonStyle(.plain)
                    }
                    Text("身体目标").font(.headline).foregroundStyle(.secondary).padding(.horizontal, 4)
                    Button { showEditor = true } label: {
                        QNSettingsRow(icon: "target", title: "目标体重", value: store.profile?.targetWeight.map { String(format: "%.1f kg", $0) } ?? "未设置")
                    }.buttonStyle(.plain).qnCard(cornerRadius: 18)
                    Text("数据管理").font(.headline).foregroundStyle(.secondary).padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        Button { showHistory = true } label: { QNSettingsRow(icon: "clock.arrow.circlepath", title: "历史记录", value: "\(store.records.count) 条") }.buttonStyle(.plain)
                        Divider().padding(.leading, 54)
                        Button { shareURL = store.exportAllHistory().map { QNShareItem(url: $0) } } label: { QNSettingsRow(icon: "square.and.arrow.up", title: "导出全部记录", value: nil) }.buttonStyle(.plain)
                    }.qnCard(cornerRadius: 18)
                    Text("关于").font(.headline).foregroundStyle(.secondary).padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        Button { showDeveloper = true } label: { QNSettingsRow(icon: "hammer", title: "开发者模式", value: nil) }.buttonStyle(.plain)
                        Divider().padding(.leading, 54)
                        QNSettingsRow(icon: "hand.raised", title: "数据仅保存在此 iPhone", value: nil, showsChevron: false)
                    }.qnCard(cornerRadius: 18)
                }
                .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 28)
            }
            .background(QNDesign.page.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showEditor) { QNProfileEditorView(profile: store.profile, isRequired: false) }
            .sheet(isPresented: $showHistory) { QNHistoryView() }
            .sheet(isPresented: $showDeveloper) { QNDeveloperView() }
            .sheet(item: $shareURL) { item in QNShareSheet(items: [item.url]) }
        }
    }
}

private struct QNSettingsRow: View {
    let icon: String
    let title: String
    let value: String?
    var showsChevron = true

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.headline).foregroundStyle(QNDesign.blue).frame(width: 26)
            Text(title).font(.body.weight(.medium))
            Spacer()
            if let value { Text(value).foregroundStyle(.secondary) }
            if showsChevron { Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary) }
        }
        .padding(.horizontal, 16).padding(.vertical, 15)
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
    @State private var targetWeight: String
    @State private var showBirthdayPicker = false
    @State private var showHeightPicker = false
    @State private var showTargetWeightPicker = false

    init(profile: QNUserProfile?, isRequired: Bool) {
        existing = profile
        self.isRequired = isRequired
        _nickname = State(initialValue: profile?.nickname ?? "")
        _gender = State(initialValue: profile?.gender ?? "male")
        _birthday = State(initialValue: profile?.birthday ?? Calendar.current.date(byAdding: .year, value: -30, to: Date())!)
        _height = State(initialValue: profile.map { String(format: "%.0f", $0.height) } ?? "169")
        _targetWeight = State(initialValue: profile?.targetWeight.map { String(format: "%.1f", $0) } ?? "")
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !isRequired {
                        Button("取消") { dismiss() }.font(.body.weight(.semibold))
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(isRequired ? "建立个人资料" : "个人资料")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text("填写用于体脂测量的资料").font(.title3).foregroundStyle(.secondary)
                    }
                    Text("测量资料").font(.headline).foregroundStyle(.secondary).padding(.horizontal, 4)
                    VStack(spacing: 0) {
                        HStack {
                            Text("昵称").font(.body.weight(.medium))
                            Spacer()
                            TextField("请输入昵称", text: $nickname)
                                .multilineTextAlignment(.trailing)
                                .textInputAutocapitalization(.never)
                        }.padding(16)
                        Divider().padding(.leading, 16)
                        HStack {
                            Text("性别").font(.body.weight(.medium))
                            Spacer()
                            Picker("性别", selection: $gender) { Text("男").tag("male"); Text("女").tag("female") }
                                .pickerStyle(.segmented).frame(width: 190)
                        }.padding(16)
                        Divider().padding(.leading, 16)
                        Button { showBirthdayPicker = true } label: {
                            QNProfileValueRow(title: "出生日期", value: Self.birthdayFormatter.string(from: birthday), accent: true)
                        }.buttonStyle(.plain)
                        Divider().padding(.leading, 16)
                        Button { showHeightPicker = true } label: {
                            QNProfileValueRow(title: "身高", value: "\(height) cm")
                        }.buttonStyle(.plain)
                    }.qnCard()
                    Text("身体目标").font(.headline).foregroundStyle(.secondary).padding(.horizontal, 4)
                    Button { showTargetWeightPicker = true } label: {
                        QNProfileValueRow(title: "目标体重", value: Double(targetWeight).map { String(format: "%.1f kg", $0) } ?? "未设置")
                    }.buttonStyle(.plain).qnCard(cornerRadius: 18)
                    Text("新测量使用当前资料，历史记录保留原资料。")
                        .font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                }
                .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 110)
            }
            .background(QNDesign.page.ignoresSafeArea())
            .navigationBarHidden(true)
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    Text("保存资料").font(.headline).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.vertical, 15)
                        .background(QNDesign.blueGradient).clipShape(Capsule())
                }
                .disabled(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Double(height) == nil)
                .opacity(nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || Double(height) == nil ? 0.45 : 1)
                .padding(.horizontal, 16).padding(.vertical, 10).background(.ultraThinMaterial)
            }
            .sheet(isPresented: $showBirthdayPicker) {
                QNDatePickerSheet(value: birthday) { birthday = $0 }
            }
            .sheet(isPresented: $showHeightPicker) {
                QNNumberPickerSheet(title: "身高", values: (100...220).map(Double.init), initialValue: Double(height) ?? 169, unit: "cm", allowsUnset: false) { value in
                    if let value { height = String(format: "%.0f", value) }
                }
            }
            .sheet(isPresented: $showTargetWeightPicker) {
                QNNumberPickerSheet(title: "目标体重", values: stride(from: 30.0, through: 200.0, by: 0.5).map { $0 }, initialValue: Double(targetWeight), unit: "kg", allowsUnset: true) { value in
                    targetWeight = value.map { String(format: "%.1f", $0) } ?? ""
                }
            }
        }
    }
    private func save() { let value=QNUserProfile(userId:existing?.userId ?? UUID().uuidString,nickname:nickname.trimmingCharacters(in:.whitespacesAndNewlines),gender:gender,birthday:birthday,height:Double(height) ?? 0,athleteType:0,targetWeight:Double(targetWeight)); store.saveProfile(value); if value.isValid { dismiss() } }

    private static let birthdayFormatter: DateFormatter = {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "zh_CN"); formatter.dateFormat = "yyyy年M月d日"; return formatter
    }()
}

private struct QNProfileValueRow: View {
    let title: String
    let value: String
    var accent = false
    var body: some View {
        HStack {
            Text(title).font(.body.weight(.medium))
            Spacer()
            Text(value).foregroundStyle(accent ? QNDesign.blue : Color.primary)
            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
        }.padding(16)
    }
}

private struct QNDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: Date
    let onDone: (Date) -> Void
    init(value: Date, onDone: @escaping (Date) -> Void) { _draft = State(initialValue: value); self.onDone = onDone }
    var body: some View {
        NavigationView {
            DatePicker("出生日期", selection: $draft, in: Self.minimumDate...Self.maximumDate, displayedComponents: .date)
                .datePickerStyle(.wheel).labelsHidden().padding()
                .navigationTitle("出生日期").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { onDone(draft); dismiss() } }
                }
        }
    }
    private static var minimumDate: Date { Calendar.current.date(byAdding: .year, value: -120, to: Date())! }
    private static var maximumDate: Date { Calendar.current.date(byAdding: .year, value: -18, to: Date())! }
}

private struct QNNumberPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let values: [Double]
    let unit: String
    let allowsUnset: Bool
    let onDone: (Double?) -> Void
    @State private var selected: Double?
    init(title: String, values: [Double], initialValue: Double?, unit: String, allowsUnset: Bool, onDone: @escaping (Double?) -> Void) {
        self.title = title; self.values = values; self.unit = unit; self.allowsUnset = allowsUnset; self.onDone = onDone
        let selection: Double?
        if let initialValue { selection = initialValue }
        else if allowsUnset { selection = nil }
        else { selection = values.first }
        _selected = State(initialValue: selection)
    }
    var body: some View {
        NavigationView {
            Picker(title, selection: $selected) {
                if allowsUnset { Text("未设置").tag(Double?.none) }
                ForEach(values, id: \.self) { value in
                    Text("\(value.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", value) : String(format: "%.1f", value)) \(unit)").tag(Optional(value))
                }
            }
            .pickerStyle(.wheel).labelsHidden().padding()
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("完成") { onDone(selected); dismiss() } }
            }
        }
    }
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

private struct QNEmptyState: View { let title:String; let message:String; let buttonTitle:String?; let action:(() -> Void)?; var body: some View { VStack(spacing:14) { Image(systemName:"scalemass").font(.system(size:42, weight:.medium)).foregroundStyle(QNDesign.blue).frame(width:76,height:76).background(QNDesign.blue.opacity(0.10)).clipShape(Circle()); Text(title).font(.title3.weight(.bold)); Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary); if let buttonTitle,let action { QNButton(title:buttonTitle,systemImage:"arrow.right",action:action) } }.frame(maxWidth:.infinity).padding(28).qnCard() } }
private struct QNButton: View { let title:String; let systemImage:String; let action:() -> Void; var body: some View { Button(action:action){Label(title,systemImage:systemImage).font(.headline).foregroundStyle(.white).frame(maxWidth:.infinity).padding(.vertical,15).background(QNDesign.blueGradient).clipShape(Capsule())}.buttonStyle(.plain) } }
private struct QNShareSheet: UIViewControllerRepresentable { let items:[Any]; func makeUIViewController(context:Context)->UIActivityViewController{UIActivityViewController(activityItems:items,applicationActivities:nil)}; func updateUIViewController(_ controller:UIActivityViewController,context:Context){} }
