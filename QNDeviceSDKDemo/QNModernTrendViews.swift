import SwiftUI

struct QNModernTrendView: View {
    @EnvironmentObject private var store: QNAppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var metric = QNTrendMetric.all[0]
    @State private var range: QNTrendRange = .thirtyDays
    @State private var showMetricPicker = false
    @State private var showComparison = false

    private var series: QNTrendSeries {
        QNTrendSeries.make(records: store.records, metric: metric, range: range)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("趋势").font(.largeTitle.bold())
                        Spacer()
                        Button("对比") { showComparison = true }
                            .font(.subheadline.weight(.semibold))
                            .disabled(store.records.count < 2)
                    }

                    Button { showMetricPicker = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("当前指标").font(.caption).foregroundStyle(.secondary)
                                Text(metric.title).font(.headline)
                            }
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.bold)).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .qnModernCard(cornerRadius: 15)
                    }
                    .buttonStyle(.plain)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(QNTrendRange.allCases) { item in
                                Button(item.title) { range = item }
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(range == item ? .white : .primary)
                                    .padding(.horizontal, 14).padding(.vertical, 8)
                                    .background(range == item ? QNModernStyle.action : Color.primary.opacity(0.06))
                                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
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
            }
            .padding(.horizontal, QNModernStyle.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 96)
        }
        .background(QNModernStyle.page.ignoresSafeArea())
        .sheet(isPresented: $showMetricPicker) {
            QNModernMetricPicker(selection: $metric)
        }
        .sheet(isPresented: $showComparison) {
            QNModernComparisonPickerView()
        }
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
            HStack {
                Text("最低  \(formatted(statistics.minimum))")
                Spacer()
                Text("最高  \(formatted(statistics.maximum))")
            }
            .font(.subheadline).foregroundStyle(.secondary)
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
    let series: QNTrendSeries
    let metric: QNTrendMetric
    let allRecords: [QNMeasurementSnapshot]
    @State private var selectedID: UUID?

    private var selectedPoint: QNTrendPoint? {
        series.points.first { $0.id == selectedID }
    }

    private var displayValues: [Double] {
        series.points.map { display($0.value) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("单位：\(displayUnit ?? "无")")
                .font(.caption).foregroundStyle(.secondary)
            GeometryReader { proxy in
                ZStack {
                    Canvas { context, size in draw(context: &context, size: size) }
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in selectNearest(at: value.location.x, width: proxy.size.width) }
                        )
                }
            }
            .frame(height: 274)

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
            HStack {
                Text(formatted(point.value)).font(.headline.monospacedDigit())
                Spacer()
                Text(delta.map { "较上一条 \(formatted($0, signed: true))" } ?? "没有更早的有效记录")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func selectNearest(at x: CGFloat, width: CGFloat) {
        let plot = plotRect(CGSize(width: width, height: 274))
        selectedID = series.points.min(by: {
            abs(xPosition($0, plot: plot) - x) < abs(xPosition($1, plot: plot) - x)
        })?.id
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        guard !series.points.isEmpty else { return }
        let plot = plotRect(size)
        let scale = yScale(displayValues)

        for tick in scale.ticks {
            let y = yPosition(tick, scale: scale, plot: plot)
            var grid = Path()
            grid.move(to: CGPoint(x: plot.minX, y: y))
            grid.addLine(to: CGPoint(x: plot.maxX, y: y))
            context.stroke(grid, with: .color(Color.secondary.opacity(0.14)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            context.draw(
                Text(QNDisplayFormatter.number(tick, maximumFractionDigits: scale.precision)).font(.caption2).foregroundColor(.secondary),
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
                    Gradient(colors: [QNModernStyle.action.opacity(0.22), QNModernStyle.action.opacity(0.01)]),
                    startPoint: CGPoint(x: 0, y: plot.minY),
                    endPoint: CGPoint(x: 0, y: plot.maxY)
                ))
            }
            var line = Path()
            line.move(to: locations[0])
            for location in locations.dropFirst() { line.addLine(to: location) }
            context.stroke(line, with: .color(QNModernStyle.action), style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }

        for (index, location) in locations.enumerated() {
            let isSelected = series.points[index].id == selectedID
            let radius: CGFloat = isSelected ? 5.5 : 4
            let dot = Path(ellipseIn: CGRect(x: location.x - radius, y: location.y - radius, width: radius * 2, height: radius * 2))
            context.fill(dot, with: .color(Color(uiColor: .systemBackground)))
            context.stroke(dot, with: .color(QNModernStyle.action), lineWidth: isSelected ? 3 : 2)
        }

        let labelDates = [series.domainStart, series.domainStart.addingTimeInterval(series.domainEnd.timeIntervalSince(series.domainStart) / 2), series.domainEnd]
        let anchors: [UnitPoint] = [.leading, .center, .trailing]
        for index in labelDates.indices {
            let fraction = index == 0 ? 0.0 : (index == 1 ? 0.5 : 1.0)
            let x = plot.minX + plot.width * CGFloat(fraction)
            context.draw(
                Text(Self.axisDateFormatter.string(from: labelDates[index])).font(.caption2).foregroundColor(.secondary),
                at: CGPoint(x: x, y: plot.maxY + 13),
                anchor: anchors[index]
            )
        }
    }

    private func plotRect(_ size: CGSize) -> CGRect {
        CGRect(x: 10, y: 10, width: max(size.width - 62, 1), height: max(size.height - 46, 1))
    }

    private func xPosition(_ point: QNTrendPoint, plot: CGRect) -> CGFloat {
        plot.minX + plot.width * CGFloat(series.xFraction(for: point.record.measureTime))
    }

    private func yPosition(_ value: Double, scale: QNYScale, plot: CGRect) -> CGFloat {
        let fraction = (value - scale.lower) / max(scale.upper - scale.lower, 0.000_001)
        return plot.maxY - plot.height * CGFloat(fraction)
    }

    private func yScale(_ values: [Double]) -> QNYScale {
        let rawMin = values.min() ?? 0
        let rawMax = values.max() ?? rawMin
        let magnitude = max(max(abs(rawMin), abs(rawMax)), 1)
        let minimumSpan = max(magnitude * 0.04, metric.definition.precision == 0 ? 4 : 0.4)
        let desiredSpan = max(rawMax - rawMin, minimumSpan) * 1.35
        let rawStep = desiredSpan / 4
        let exponent = floor(log10(max(rawStep, 0.000_001)))
        let power = pow(10, exponent)
        let fraction = rawStep / power
        let niceFraction: Double
        if fraction <= 1 { niceFraction = 1 }
        else if fraction <= 2 { niceFraction = 2 }
        else if fraction <= 2.5 { niceFraction = 2.5 }
        else if fraction <= 5 { niceFraction = 5 }
        else { niceFraction = 10 }
        let step = niceFraction * power
        var lower = floor((rawMin - (desiredSpan - (rawMax - rawMin)) / 2) / step) * step
        var upper = ceil((rawMax + (desiredSpan - (rawMax - rawMin)) / 2) / step) * step
        if lower == upper { lower -= step * 2; upper += step * 2 }
        var ticks: [Double] = []
        var value = lower
        while value <= upper + step * 0.1, ticks.count < 8 {
            ticks.append(value)
            value += step
        }
        let precision = step >= 1 ? 0 : (step >= 0.1 ? 1 : 2)
        return QNYScale(lower: lower, upper: upper, ticks: ticks, precision: precision)
    }

    private struct QNYScale {
        let lower: Double
        let upper: Double
        let ticks: [Double]
        let precision: Int
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
