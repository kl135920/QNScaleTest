import SwiftUI

struct QNModernDashboardView: View {
    @EnvironmentObject private var store: QNAppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var report: QNMeasurementSnapshot?
    @State private var reference: QNMeasurementSnapshot?
    @State private var showHistory = false
    @State private var shareItem: QNModernShareItem?
    let onMeasure: () -> Void

    private var latest: QNMeasurementSnapshot? { store.latestRecord }
    private var previousWeight: Double? {
        guard let latest else { return nil }
        return QNMeasurementTimeline.previousValidWeight(before: latest, in: store.records)?.weight
    }
    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: QNModernStyle.sectionSpacing) {
                header
                if let latest {
                        Button { report = latest } label: {
                            QNModernWeightCard(
                                snapshot: latest,
                                previousWeight: previousWeight,
                                targetWeight: nil,
                                showsDisclosure: true
                            )
                        }
                        .buttonStyle(.plain)

                        LazyVGrid(columns: columns, spacing: 10) {
                            QNModernMetricTile(
                                title: "体脂率",
                                value: latest.bodyFatRate,
                                definition: QNMetricCatalog.definition(for: 3),
                                icon: "percent",
                                accent: QNModernStyle.fat,
                                evaluation: QNReferenceRangeService.bodyFatRate(latest.bodyFatRate, gender: latest.gender)?.label
                            )
                            QNModernMetricTile(
                                title: "肌肉量",
                                value: latest.muscleMass,
                                definition: QNMetricCatalog.definition(for: 13),
                                icon: "figure.strengthtraining.traditional",
                                accent: QNModernStyle.muscle
                            )
                            QNModernMetricTile(
                                title: "骨骼肌量",
                                value: latest.skeletalMuscleMass,
                                definition: QNMetricCatalog.definition(for: 112),
                                icon: "figure.walk",
                                accent: QNModernStyle.muscle
                            )
                            QNModernMetricTile(
                                title: "BMI",
                                value: latest.bmi,
                                definition: QNMetricCatalog.definition(for: 2),
                                icon: "chart.bar.fill",
                                evaluation: QNReferenceRangeService.bmi(latest.bmi)?.label
                            )
                        }

                    goalCard
                    QNModernSegmentCard(snapshot: latest)
                    VStack(spacing: 0) {
                        navigationAction(title: "指标参考", subtitle: "查看评价与依据", icon: "list.clipboard") {
                            reference = latest
                        }
                        Divider().padding(.leading, 50)
                        navigationAction(title: "历史记录", subtitle: "\(store.records.count) 条", icon: "clock.arrow.circlepath") {
                            showHistory = true
                        }
                    }
                    .qnModernCard(cornerRadius: 18)
                    QNModernPrimaryButton(title: "开始测量", systemImage: "scalemass", action: onMeasure)
                } else {
                    emptyState
                }

                    if store.pendingMeasurement != nil {
                        QNModernPrimaryButton(title: "重试保存本次测量", systemImage: "arrow.clockwise") {
                            store.retryPendingSave()
                        }
                    }
                    if let error = store.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
            }
            .padding(.horizontal, QNModernStyle.horizontalPadding)
            .padding(.top, 0)
            .padding(.bottom, QNModernStyle.pageBottomPadding)
        }
        .background(QNModernStyle.page.ignoresSafeArea())
        .overlay(alignment: .top) {
            if let toast = store.toastMessage {
                Label(toast, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.82))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.toastMessage)
        .sheet(item: $reference) { snapshot in
            QNModernMetricReferenceSheet(snapshot: snapshot)
        }
        .sheet(isPresented: $showHistory) { QNHistoryView() }
        .fullScreenCover(item: $report) { snapshot in
            QNModernReportView(snapshot: snapshot) {
                shareItem = store.export(snapshot).map { QNModernShareItem(url: $0) }
            }
        }
        .sheet(item: $shareItem) { item in QNModernShareSheet(items: [item.url]) }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("身体数据").font(.system(size: 34, weight: .bold, design: .default))
            Text(latest.map { "\($0.displayDate) · 最近测量" } ?? "还没有测量记录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func navigationAction(
        title: String,
        subtitle: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(QNModernStyle.action)
                    .frame(width: 26)
                Text(title).font(.body.weight(.semibold))
                Spacer(minLength: 8)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, QNModernStyle.cardPadding)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var goalCard: some View {
        if let target = store.profile?.targetWeight, let latestWeight = latest?.weight {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("目标进度", systemImage: "target").font(.headline)
                    Spacer()
                    Text("目标 \(store.displayWeightUnit.text(fromKilograms: target)) \(store.displayWeightUnit.symbol)")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if let progress = store.goalProgress {
                    if let fraction = progress.fraction {
                        ProgressView(value: fraction).tint(QNModernStyle.action)
                    }
                    let remaining = store.displayWeightUnit.fromKilograms(abs(progress.targetWeight - progress.currentWeight))
                    Text(progress.reached ? "已达到目标" : "距离目标 \(QNDisplayFormatter.number(remaining, maximumFractionDigits: 2)) \(store.displayWeightUnit.symbol)")
                        .font(.subheadline.weight(.medium))
                } else {
                    let difference = store.displayWeightUnit.fromKilograms(target - latestWeight)
                    Text("与目标相差 \(QNDisplayFormatter.number(difference, maximumFractionDigits: 2, signed: true)) \(store.displayWeightUnit.symbol)")
                        .font(.subheadline.weight(.medium))
                }
            }
            .padding(QNModernStyle.cardPadding)
            .qnModernCard(cornerRadius: 18)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "scalemass")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(QNModernStyle.action)
            Text("开始建立你的身体数据").font(.title3.weight(.bold))
            Text("连接体脂秤完成第一次测量后，数据会保存在此 iPhone 上。")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            QNModernPrimaryButton(title: "开始第一次测量", systemImage: "arrow.right", action: onMeasure)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .qnModernCard()
    }
}

struct QNModernMeasurementView: View {
    @EnvironmentObject private var store: QNAppStore
    @State private var report: QNMeasurementSnapshot?
    @State private var shareItem: QNModernShareItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("QNSCALE")
                    .font(.caption2.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline) {
                    Text("测量").font(.system(size: 34, weight: .bold))
                    Spacer()
                    connectionBadge
                }
                stateCard
                if let error = store.lastError, case .failed = store.measurementUIState {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, QNModernStyle.horizontalPadding)
            .padding(.top, 0)
            .padding(.bottom, QNModernStyle.pageBottomPadding)
        }
        .background(QNModernStyle.page.ignoresSafeArea())
        .onAppear { store.beginAutomaticConnection() }
        .onChange(of: store.lastSavedMeasurement?.id) { _ in
            report = store.lastSavedMeasurement
        }
        .onChange(of: store.measurementState) { state in
            if state.contains("已保存") {
                report = store.lastSavedMeasurement
            }
        }
        .fullScreenCover(item: $report) { snapshot in
            QNModernReportView(snapshot: snapshot) {
                shareItem = store.export(snapshot).map { QNModernShareItem(url: $0) }
            }
        }
        .sheet(item: $shareItem) { item in QNModernShareSheet(items: [item.url]) }
    }

    private var connectionBadge: some View {
        Label(badgeTitle, systemImage: "bluetooth")
            .font(.caption.weight(.semibold))
            .foregroundStyle(store.isConnected ? QNModernStyle.action : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background((store.isConnected ? QNModernStyle.action : Color.secondary).opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var badgeTitle: String {
        switch store.measurementUIState {
        case .scanning: return "扫描中"
        case .connecting: return "连接中"
        case .connected(_), .measuring(_, _), .completed: return "已连接"
        default: return "未连接"
        }
    }

    @ViewBuilder
    private var stateCard: some View {
        VStack(spacing: 20) {
            switch store.measurementUIState {
            case .unavailable(let message):
                stateHeader(icon: "exclamationmark.triangle", title: "暂时无法测量", message: message, tint: .orange)
                retryButton
            case .disconnected:
                stateHeader(icon: "scalemass", title: "连接体脂秤", message: "唤醒体脂秤后，App 会自动查找并连接。", tint: QNModernStyle.action)
                QNModernPrimaryButton(title: "开始连接", systemImage: "link") { store.retryAutomaticConnection() }
            case .scanning:
                ProgressView().scaleEffect(1.2).tint(QNModernStyle.action)
                stateText(title: "正在查找设备", message: "请唤醒附近的 QN-Scale。")
                secondaryButton(title: "取消查找", systemImage: "xmark") { store.cancelAutomaticConnection() }
            case .connecting(let name):
                ProgressView().scaleEffect(1.2).tint(QNModernStyle.action)
                stateText(title: "正在连接 \(name)", message: "连接通常只需要几秒钟。")
                secondaryButton(title: "取消", systemImage: "xmark") { store.cancelAutomaticConnection() }
            case .connected(let name):
                stateHeader(icon: "checkmark.circle", title: name, message: "请赤脚站上体脂秤并握住手柄。", tint: QNModernStyle.action)
                Text("请保持站姿，测量完成前不要松开手柄。")
                    .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                secondaryButton(title: "断开连接", systemImage: "link.badge.minus") { store.disconnectAndSuspendAutomaticConnection() }
            case .measuring(let weight, let state):
                if let weight {
                    HStack(alignment: .lastTextBaseline, spacing: 7) {
                        Text(store.displayWeightUnit.text(fromKilograms: weight))
                            .font(.system(size: 60, weight: .bold, design: .rounded).monospacedDigit())
                            .minimumScaleFactor(0.7)
                        Text(store.displayWeightUnit.symbol).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    Text("实时重量").font(.subheadline).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    ProgressView().tint(QNModernStyle.action)
                    Text(state).font(.headline)
                }
                Text("请保持站姿并握住手柄。")
                    .font(.subheadline).foregroundStyle(.secondary)
                secondaryButton(title: "断开连接", systemImage: "link.badge.minus") { store.disconnectAndSuspendAutomaticConnection() }
            case .completed:
                let isSaved = store.measurementState.contains("已保存")
                stateHeader(
                    icon: "checkmark.circle.fill",
                    title: isSaved ? "测量结果已保存" : "测量完成",
                    message: isSaved ? "正在打开本次测量报告。" : "正在保存本次测量结果。",
                    tint: QNModernStyle.muscle
                )
                if isSaved, let snapshot = store.lastSavedMeasurement {
                    secondaryButton(title: "查看本次报告", systemImage: "doc.text.magnifyingglass") {
                        report = snapshot
                    }
                }
            case .failed(let message):
                stateHeader(icon: "exclamationmark.circle", title: "连接或测量失败", message: message, tint: .red)
                retryButton
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.vertical, 28)
        .qnModernCard(cornerRadius: 20)
    }

    private var retryButton: some View {
        QNModernPrimaryButton(title: "重试", systemImage: "arrow.clockwise") { store.retryAutomaticConnection() }
    }

    private func stateHeader(icon: String, title: String, message: String, tint: Color) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(tint)
            stateText(title: title, message: message)
        }
    }

    private func stateText(title: String, message: String) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.title3.weight(.bold)).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
    }

    private func secondaryButton(title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(QNModernStyle.action.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(QNModernStyle.action)
    }
}

struct QNModernReportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: QNAppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: QNMeasurementSnapshot
    let onExport: () -> Void
    @State private var showRaw = false

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible()), GridItem(.flexible())]
    }

    var body: some View {
        VStack(spacing: 0) {
            compactHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(snapshot.displayDate).font(.subheadline).foregroundStyle(.secondary)
                    QNModernReportWeight(snapshot: snapshot)
                    Text("身体指标").font(.title2.weight(.bold))
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(QNMetricCatalog.reportTypes.filter { $0 != 1 }, id: \.self) { type in
                            reportTile(type)
                        }
                    }
                    QNModernSegmentCard(snapshot: snapshot)
                    DisclosureGroup(isExpanded: $showRaw) {
                        QNModernRawItems(snapshot: snapshot).padding(.top, 10)
                    } label: {
                        Label("全部 SDK 原始指标", systemImage: "list.number")
                            .font(.headline).foregroundStyle(.primary)
                    }
                    .padding(QNModernStyle.cardPadding)
                    .qnModernCard(cornerRadius: 18)

                    DisclosureGroup("原始测量信息") {
                        VStack(alignment: .leading, spacing: 7) {
                            rawLine("resistance50", snapshot.resistance50)
                            rawLine("resistance500", snapshot.resistance500)
                            rawLine("newEightModel", snapshot.newEightModel)
                            rawLine("eightIsAbnormal", snapshot.eightIsAbnormal)
                            rawLine("eightReasonMask", snapshot.eightReasonMask)
                            Text("modeId：\(snapshot.modeId ?? "—")")
                            Text("SDK：\(snapshot.sdkVersion ?? "—")")
                            if snapshot.hmac != nil {
                                Text("HMAC 已保存在导出的原始 JSON 中")
                            }
                        }
                        .padding(.top, 10)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                    }
                    .padding(QNModernStyle.cardPadding)
                    .qnModernCard(cornerRadius: 18)
                }
                .padding(.horizontal, QNModernStyle.horizontalPadding)
                .padding(.top, 10)
                .padding(.bottom, QNModernStyle.pageBottomPadding)
            }
        }
        .background(QNModernStyle.page.ignoresSafeArea())
    }

    private var compactHeader: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .accessibilityLabel("返回")
            .foregroundStyle(QNModernStyle.action)
            Spacer()
            Text("测量报告")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer()
            Button(action: onExport) {
                Image(systemName: "square.and.arrow.up")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Circle())
            }
            .accessibilityLabel("导出测量报告")
            .foregroundStyle(QNModernStyle.action)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(QNModernStyle.card)
    }

    private func reportTile(_ type: Int) -> some View {
        let definition = QNMetricCatalog.definition(for: type)
        let key = QNHistoryComparisonService.key(for: type)
        let value = snapshot.metrics[key] ?? snapshot.metrics["type\(type)"]
        let evaluation = value.flatMap { QNReferenceRangeService.evaluation(for: key, value: $0, gender: snapshot.gender)?.label }
        return QNModernMetricTile(
            title: definition.title,
            value: value,
            definition: definition,
            icon: icon(for: type),
            accent: type == 3 || type == 21 || type == 35 ? QNModernStyle.fat : QNModernStyle.action,
            evaluation: evaluation
        )
    }

    private func icon(for type: Int) -> String {
        switch type {
        case 2: return "chart.bar"
        case 3, 4: return "percent"
        case 6: return "drop"
        case 13, 112: return "figure.strengthtraining.traditional"
        case 9: return "flame"
        default: return "circle.grid.2x2"
        }
    }

    private func rawLine(_ title: String, _ value: Int?) -> some View {
        Text("\(title)：\(value.map(String.init) ?? "—")")
    }
}

private struct QNModernReportWeight: View {
    @EnvironmentObject private var store: QNAppStore
    let snapshot: QNMeasurementSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("体重").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(snapshot.weight.map { store.displayWeightUnit.text(fromKilograms: $0) } ?? "—")
                    .font(.system(size: 46, weight: .bold, design: .rounded).monospacedDigit())
                if snapshot.weight != nil {
                    Text(store.displayWeightUnit.symbol).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            if snapshot.isAbnormal {
                Label("异常结果已保留", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption.weight(.semibold)).foregroundStyle(QNModernStyle.fat)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .qnModernCard()
    }
}

private struct QNModernRawItems: View {
    let snapshot: QNMeasurementSnapshot
    private var items: [[String: Any]] {
        guard let text = snapshot.rawItemsJSON,
              let data = text.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [] }
        return values
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if items.isEmpty {
                Text("没有原始指标").font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                let type = (item["type"] as? NSNumber)?.intValue ?? 0
                let definition = QNMetricCatalog.definition(for: type)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("T\(type)").font(.caption.monospaced().weight(.semibold)).foregroundStyle(QNModernStyle.action).frame(width: 44, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(definition.title).font(.subheadline.weight(.medium))
                        Text((item["name"] as? String) ?? definition.sdkSemantic).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    Text(rawValue(item["value"]))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    if let unit = item["unit"] as? String, !unit.isEmpty {
                        Text(unit).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 9)
                if index < items.count - 1 { Divider() }
            }
        }
    }

    private func rawValue(_ value: Any?) -> String {
        guard let value else { return "—" }
        if let number = value as? NSNumber {
            return QNDisplayFormatter.number(number.doubleValue, maximumFractionDigits: 3)
        }
        return String(describing: value)
    }
}

private struct QNModernMetricReferenceView: View {
    @EnvironmentObject private var store: QNAppStore
    let snapshot: QNMeasurementSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("参考测量时的资料 · \(snapshot.gender == "female" ? "女性" : "男性") · \(snapshot.height.map { QNDisplayFormatter.number($0, maximumFractionDigits: 0) + " cm" } ?? "身高未知")")
                    .font(.subheadline).foregroundStyle(.secondary)
                referenceRow(title: "BMI", value: snapshot.bmi, definition: QNMetricCatalog.definition(for: 2), evaluation: QNReferenceRangeService.bmi(snapshot.bmi)?.label)
                referenceRow(title: "体脂率", value: snapshot.bodyFatRate, definition: QNMetricCatalog.definition(for: 3), evaluation: QNReferenceRangeService.bodyFatRate(snapshot.bodyFatRate, gender: snapshot.gender)?.label)
                referenceRow(title: "肌肉量", value: snapshot.muscleMass, definition: QNMetricCatalog.definition(for: 13), evaluation: nil)
                Text("未确认参考范围的指标只展示数值和趋势。参考依据：\(QNReferenceRangeService.source)")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(QNModernStyle.horizontalPadding)
        }
        .background(QNModernStyle.page.ignoresSafeArea())
        .navigationTitle("指标参考")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func referenceRow(title: String, value: Double?, definition: MetricDefinition, evaluation: String?) -> some View {
        let formatted = QNDisplayFormatter.metric(value, definition: definition, weightUnit: store.displayWeightUnit)
        return VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.headline)
            HStack(alignment: .lastTextBaseline, spacing: 5) {
                Text(formatted.number).font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                if value != nil, let unit = formatted.unit { Text(unit).font(.subheadline).foregroundStyle(.secondary) }
                Spacer()
                if let evaluation, value != nil {
                    Text(evaluation).font(.subheadline.weight(.semibold)).foregroundStyle(QNModernStyle.fat)
                }
            }
        }
        .padding(QNModernStyle.cardPadding)
        .qnModernCard()
    }
}

private struct QNModernMetricReferenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: QNMeasurementSnapshot

    var body: some View {
        NavigationView {
            QNModernMetricReferenceView(snapshot: snapshot)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                    }
                }
        }
    }
}
