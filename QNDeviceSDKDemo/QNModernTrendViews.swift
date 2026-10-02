import SwiftUI

struct QNModernTrendView: View {
    @EnvironmentObject private var store: QNAppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var metric = QNTrendMetric.all[0]
    @State private var range: QNTrendRange = .thirtyDays
    @State private var showMetricPicker = false
    @State private var showComparison = false
    @State private var showHistory = false
    @State private var report: QNMeasurementSnapshot?
    @State private var shareItem: QNModernShareItem?

    private var series: QNTrendSeries {
        QNTrendSeries.make(records: store.records, metric: metric, range: range)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QNModernStyle.sectionSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    QNModernPageTitle(title: "趋势")
                    Spacer()
                    Button { showComparison = true } label: {
                        Label("对比", systemImage: "arrow.left.arrow.right")
                            .font(.subheadline)
                    }
                    .disabled(store.records.count < 2)
                }

                    Button { showMetricPicker = true } label: {
                        HStack(spacing: 6) {
                            Text(metric.title).font(.body.weight(.medium))
                            Image(systemName: "chevron.down").font(.caption)
                        }
                        .foregroundStyle(QNModernStyle.action)
                        .frame(minHeight: 32)
                    }
                    .buttonStyle(.plain)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(QNTrendRange.allCases) { item in
                                Button(item.title) { range = item }
                            .font(.subheadline.weight(.medium))
                                    .foregroundStyle(range == item ? .white : .primary)
                                    .padding(.horizontal, 12).padding(.vertical, 7)
                                    .background(range == item ? QNModernStyle.action : Color.primary.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            }
                        }
                    }

                if series.points.isEmpty {
                    emptyState
                } else {
                    QNModernTrendChart(series: series, metric: metric, allRecords: store.records)
                    if series.points.count == 1 {
                        Label("需要更多该指标的数据才能形成趋势", systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    if let statistics = series.statistics {
                        statisticsCard(statistics)
                    }
                }
                historySummary
            }
            .padding(.horizontal, QNModernStyle.horizontalPadding)
            .padding(.top, QNModernStyle.pageTopPadding)
            .padding(.bottom, QNModernStyle.pageBottomPadding)
        }
        .background(QNModernStyle.page.ignoresSafeArea())
        .sheet(isPresented: $showMetricPicker) {
            QNModernMetricPicker(selection: $metric)
        }
        .sheet(isPresented: $showComparison) {
            QNModernComparisonPickerView()
        }
        .sheet(isPresented: $showHistory) { QNHistoryView() }
        .fullScreenCover(item: $report) { snapshot in
            QNModernReportView(snapshot: snapshot) {
                shareItem = store.export(snapshot).map { QNModernShareItem(url: $0) }
            }
        }
        .sheet(item: $shareItem) { item in QNModernShareSheet(items: [item.url]) }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line").font(.system(size: 34)).foregroundStyle(QNModernStyle.action)
            Text("暂无\(metric.title)趋势数据").font(.headline)
            Text("缺失值不会当作 0 参与图表或统计。")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(26)
        .qnModernCard()
    }

    private var historySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("历史测量记录").font(.headline)
                Spacer()
                Button("全部记录") { showHistory = true }
                    .font(.subheadline.weight(.semibold))
                    .disabled(store.records.isEmpty)
            }
            if store.records.isEmpty {
                Text("还没有测量记录")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(QNModernStyle.cardPadding)
                    .qnModernCard(cornerRadius: 18)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(QNMeasurementTimeline.ordered(store.records, ascending: false).prefix(3).enumerated()), id: \.element.id) { index, snapshot in
                        if index > 0 { Divider().padding(.leading, 50) }
                        Button { report = snapshot } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "scalemass")
                                    .foregroundStyle(QNModernStyle.action)
                                    .frame(width: 26)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(snapshot.weight.map { "\(store.displayWeightUnit.text(fromKilograms: $0)) \(store.displayWeightUnit.symbol)" } ?? "—")
                                        .font(.body.weight(.semibold).monospacedDigit())
                                    Text(snapshot.displayDate).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(snapshot.bodyFatRate.map { QNDisplayFormatter.number($0, maximumFractionDigits: 1) + " %" } ?? "—")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, QNModernStyle.cardPadding)
                            .padding(.vertical, 13)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .qnModernCard(cornerRadius: 18)
            }
        }
    }

    private func statisticsCard(_ statistics: QNTrendStatistics) -> some View {
        let primaryColumns = dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : Array(repeating: GridItem(.flexible()), count: 3)
        return VStack(alignment: .leading, spacing: 14) {
            Text("统计").font(.headline)
            LazyVGrid(columns: primaryColumns, spacing: 12) {
                statistic(title: "当前", value: statistics.current)
                statistic(title: "起始", value: statistics.start)
                statistic(title: "变化", value: statistics.change, signed: true)
            }
            Divider()
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    Text("最高  \(formatted(statistics.maximum))")
                    Text("最低  \(formatted(statistics.minimum))")
                }.font(.subheadline).foregroundStyle(.secondary)
            } else {
                HStack {
                    Text("最高  \(formatted(statistics.maximum))")
                    Spacer()
                    Text("最低  \(formatted(statistics.minimum))")
                }.font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(QNModernStyle.cardPadding)
        .qnModernCard()
    }

    private func statistic(title: String, value: Double, signed: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(formatted(value, signed: signed)).font(.headline.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formatted(_ value: Double, signed: Bool = false) -> String {
        QNDisplayFormatter.joined(value, definition: metric.definition, weightUnit: store.displayWeightUnit, signed: signed)
    }
}

private struct QNModernMetricPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selection: QNTrendMetric

    var body: some View {
        NavigationView {
            List(QNTrendMetric.all) { metric in
                Button {
                    selection = metric
                    dismiss()
                } label: {
                    HStack {
                        Text(metric.title).foregroundStyle(.primary)
                        Spacer()
                        if metric == selection { Image(systemName: "checkmark").foregroundStyle(QNModernStyle.action) }
                    }
                }
            }
            .navigationTitle("选择趋势指标")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
        }
    }
}

private struct QNModernTrendChart: View {
    @EnvironmentObject private var store: QNAppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let series: QNTrendSeries
    let metric: QNTrendMetric
    let allRecords: [QNMeasurementSnapshot]
    @State private var selectedID: UUID?
    private let chartHeight: CGFloat = 220

    private var selectedPoint: QNTrendPoint? {
        series.points.first { $0.id == selectedID }
    }

    private var displayValues: [Double] {
        series.points.map { display($0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let displayUnit {
                Text("单位：\(displayUnit)").font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { proxy in
                ZStack {
                    Canvas { context, size in draw(context: &context, size: size) }
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in selectNearest(at: value.location.x, width: proxy.size.width) }
                                .onEnded { value in selectNearest(at: value.location.x, width: proxy.size.width) }
                        )
                }
            }
            .frame(height: chartHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(metric.title)折线图")
            .accessibilityValue(selectedPoint.map { "\(Self.fullDateFormatter.string(from: $0.record.measureTime))，\(formatted($0.value))" } ?? "\(series.points.count) 条有效记录，上下轻扫选择")
            .accessibilityAdjustableAction { direction in
                let index = series.points.firstIndex { $0.id == selectedID } ?? 0
                let next = direction == .increment ? min(index + 1, series.points.count - 1) : max(index - 1, 0)
                if series.points.indices.contains(next) { selectedID = series.points[next].id }
            }

            if let point = selectedPoint {
                selectedDetail(point)
                    .padding(12)
                    .background(QNModernStyle.action.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text("点按数据点查看完整日期时间和变化")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .padding(QNModernStyle.cardPadding)
        .qnModernCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(metric.title)趋势图，共 \(series.points.count) 条有效记录")
    }

    private var displayUnit: String? {
        metric.definition.unit == "kg" ? store.displayWeightUnit.symbol : metric.definition.unit
    }

    private func display(_ value: Double) -> Double {
        metric.definition.unit == "kg" ? store.displayWeightUnit.fromKilograms(value) : value
    }

    private func formatted(_ value: Double, signed: Bool = false) -> String {
        QNDisplayFormatter.joined(value, definition: metric.definition, weightUnit: store.displayWeightUnit, signed: signed)
    }

    private func selectedDetail(_ point: QNTrendPoint) -> some View {
        let previous = QNTrendSeries.previousValue(for: point, metric: metric, allRecords: allRecords)
        let delta = previous.map { point.value - $0 }
        return VStack(alignment: .leading, spacing: 5) {
            Text(Self.fullDateFormatter.string(from: point.record.measureTime)).font(.subheadline.weight(.semibold))
            Text(formatted(point.value)).font(.headline.monospacedDigit())
            Text(delta.map { "较上一条 \(formatted($0, signed: true))" } ?? "没有更早的有效记录")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func selectNearest(at x: CGFloat, width: CGFloat) {
        let plot = plotRect(CGSize(width: width, height: chartHeight))
        selectedID = series.points.min(by: {
            abs(xPosition($0, plot: plot) - x) < abs(xPosition($1, plot: plot) - x)
        })?.id
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        guard !series.points.isEmpty else { return }
        let plot = plotRect(size)
        let scale = QNTrendAxisScale.make(values: displayValues, precision: metric.definition.precision)

        for tick in scale.ticks {
            let y = yPosition(tick, scale: scale, plot: plot)
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(grid, with: .color(Color.secondary.opacity(0.14)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            context.draw(
                Text(QNDisplayFormatter.number(tick, maximumFractionDigits: scale.precision)).font(.system(size: 11)).foregroundColor(.secondary),
                at: CGPoint(x: size.width - 2, y: y),
                anchor: .trailing
            )
        }

        let locations = series.points.map { point in
            CGPoint(x: xPosition(point, plot: plot), y: yPosition(display(point.value), scale: scale, plot: plot))
        }
        if locations.count > 1 {
            var area = Path()
            area.move(to: locations[0])
            for location in locations.dropFirst() { area.addLine(to: location) }
            if let last = locations.last {
                area.addLine(to: CGPoint(x: last.x, y: plot.maxY))
                area.addLine(to: CGPoint(x: locations[0].x, y: plot.maxY))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [QNModernStyle.action.opacity(0.10), QNModernStyle.action.opacity(0.005)]),
                    startPoint: CGPoint(x: 0, y: plot.minY),
                    endPoint: CGPoint(x: 0, y: plot.maxY)
                ))
            }
            var line = Path()
            line.move(to: locations[0])
            for location in locations.dropFirst() { line.addLine(to: location) }
            context.stroke(line, with: .color(QNModernStyle.action), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }

        for (index, location) in locations.enumerated() {
            let isSelected = series.points[index].id == selectedID
            let radius: CGFloat = isSelected ? 5 : 2.5
            let dot = Path(ellipseIn: CGRect(x: location.x - radius, y: location.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(Color(uiColor: .systemBackground)))
            context.stroke(dot, with: .color(QNModernStyle.action), lineWidth: isSelected ? 2.5 : 1.5)
        }

        let labelDates = series.domainStart == series.domainEnd ? [series.domainStart] : [series.domainStart, series.domainStart.addingTimeInterval(series.domainEnd.timeIntervalSince(series.domainStart) / 2), series.domainEnd]
        let anchors: [UnitPoint] = [.leading, .center, .trailing]
        for index in labelDates.indices {
            let fraction = labelDates.count == 1 ? 0.5 : (index == 0 ? 0.0 : (index == 1 ? 0.5 : 1.0))
            let x = plot.minX + plot.width * CGFloat(fraction)
            context.draw(
                Text(Self.axisDateFormatter.string(from: labelDates[index])).font(.system(size: 11)).foregroundColor(.secondary),
                at: CGPoint(x: x, y: plot.maxY + 13),
                anchor: labelDates.count == 1 ? .center : anchors[index]
            )
        }
    }

    private func plotRect(_ size: CGSize) -> CGRect {
        CGRect(x: 10, y: 10, width: max(size.width - 62, 1), height: max(size.height - 46, 1))
    }

    private func xPosition(_ point: QNTrendPoint, plot: CGRect) -> CGFloat {
        plot.minX + plot.width * CGFloat(series.xFraction(for: point.record.measureTime))
    }

    private func yPosition(_ value: Double, scale: QNTrendAxisScale, plot: CGRect) -> CGFloat {
        let fraction = (value - scale.lower) / max(scale.upper - scale.lower, 0.000_001)
        return plot.maxY - plot.height * CGFloat(fraction)
    }


    private static let axisDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    private static let fullDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        return formatter
    }()
}

struct QNModernComparisonPickerView: View {
    @EnvironmentObject private var store: QNAppStore
    @Environment(\.dismiss) private var dismiss
    @State private var startID: UUID?
    @State private var endID: UUID?
    @State private var comparison: QNMeasurementComparison?

    private var ordered: [QNMeasurementSnapshot] { QNMeasurementTimeline.ordered(store.records) }

    var body: some View {
        NavigationView {
            Form {
                Section("选择两次真实记录") {
                    Picker("第一条", selection: $startID) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(ordered) { Text($0.displayDate).tag(Optional($0.id)) }
                    }
                    Picker("第二条", selection: $endID) {
                        Text("请选择").tag(UUID?.none)
                        ForEach(ordered) { Text($0.displayDate).tag(Optional($0.id)) }
                    }
                }
                Section {
                    Button("查看变化") { buildComparison() }
                        .disabled(startID == nil || endID == nil || startID == endID)
                    Text("起止会按实际测量时间自动确定，选择顺序不会改变差值方向。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("记录对比")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .sheet(item: $comparison) { QNModernComparisonView(comparison: $0) }
        }
    }

    private func buildComparison() {
        guard let startID, let endID,
              let first = store.records.first(where: { $0.id == startID }),
              let second = store.records.first(where: { $0.id == endID }) else { return }
        comparison = QNHistoryComparisonService.compare(start: first, end: second)
    }
}

private struct QNModernComparisonView: View {
    @EnvironmentObject private var store: QNAppStore
    @Environment(\.dismiss) private var dismiss
    let comparison: QNMeasurementComparison

    var body: some View {
        NavigationView {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        comparisonDate(title: "起始", record: comparison.start)
                        comparisonDate(title: "结束", record: comparison.end)
                        Text(intervalText).font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                comparisonSection("身体指标", rows: comparison.rows.filter { $0.type < 100 })
                comparisonSection("五段肌肉", rows: comparison.rows.filter { (101...105).contains($0.type) || (118...122).contains($0.type) })
                comparisonSection("五段脂肪", rows: comparison.rows.filter { (106...110).contains($0.type) || (113...117).contains($0.type) })
            }
            .navigationTitle("身体变化")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
    }

    private func comparisonDate(title: String, record: QNMeasurementSnapshot) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold))
            Spacer()
            Text(record.displayDate).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var intervalText: String {
        let components = Calendar.current.dateComponents([.day, .hour, .minute], from: comparison.start.measureTime, to: comparison.end.measureTime)
        var parts: [String] = []
        if let day = components.day, day > 0 { parts.append("\(day)天") }
        if let hour = components.hour, hour > 0 { parts.append("\(hour)小时") }
        if let minute = components.minute { parts.append("\(minute)分钟") }
        return "间隔 " + (parts.isEmpty ? "0分钟" : parts.joined())
    }

    private func comparisonSection(_ title: String, rows: [QNComparisonRow]) -> some View {
        Section(title) {
            ForEach(rows) { row in comparisonRow(row) }
        }
    }

    private func comparisonRow(_ row: QNComparisonRow) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.title).font(.subheadline.weight(.semibold))
                Spacer()
                direction(row)
            }
            HStack(spacing: 8) {
                Text(format(row.start, row: row))
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                Text(format(row.end, row: row))
            }
            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func direction(_ row: QNComparisonRow) -> some View {
        if let difference = row.difference, row.start != nil, row.end != nil {
            let direction = difference > 0.000_001 ? 1 : (difference < -0.000_001 ? -1 : 0)
            HStack(spacing: 4) {
                Image(systemName: direction > 0 ? "arrow.up.right" : (direction < 0 ? "arrow.down.right" : "minus"))
                Text(format(abs(difference), row: row))
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(direction == 0 ? Color.secondary : QNModernStyle.action)
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }

    private func format(_ value: Double?, row: QNComparisonRow) -> String {
        let definition = QNMetricCatalog.definition(for: row.type)
        return QNDisplayFormatter.joined(value, definition: definition, weightUnit: store.displayWeightUnit)
    }
}
