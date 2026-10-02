import SwiftUI
import UIKit

enum QNModernStyle {
    static let action = Color(red: 0.04, green: 0.48, blue: 0.98)
    static let muscle = Color(red: 0.02, green: 0.69, blue: 0.64)
    static let fat = Color(red: 0.98, green: 0.46, blue: 0.12)
    static let page = Color(uiColor: .systemGroupedBackground)
    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let separator = Color.primary.opacity(0.07)
    static let horizontalPadding: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 16
    static let pageBottomPadding: CGFloat = 24
}

extension View {
    func qnModernCard(cornerRadius: CGFloat = 20) -> some View {
        background(QNModernStyle.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(QNModernStyle.separator, lineWidth: 0.5)
            )
    }
}

struct QNModernPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(QNModernStyle.action)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct QNModernMetricTile: View {
    @EnvironmentObject private var store: QNAppStore
    let title: String
    let value: Double?
    let definition: MetricDefinition
    let icon: String
    var accent: Color = QNModernStyle.action
    var evaluation: String? = nil

    private var formatted: (number: String, unit: String?) {
        QNDisplayFormatter.metric(value, definition: definition, weightUnit: store.displayWeightUnit)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(formatted.number)
                    .font(.system(size: 27, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.72)
                if value != nil, let unit = formatted.unit {
                    Text(unit).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
            }
            if value != nil, let evaluation {
                Text(evaluation)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(evaluation.contains("偏高") || evaluation.contains("肥胖") ? QNModernStyle.fat : accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background((evaluation.contains("偏高") || evaluation.contains("肥胖") ? QNModernStyle.fat : accent).opacity(0.12))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .padding(QNModernStyle.cardPadding)
        .qnModernCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }
}

struct QNModernWeightCard: View {
    @EnvironmentObject private var store: QNAppStore
    let snapshot: QNMeasurementSnapshot
    var previousWeight: Double? = nil
    var targetWeight: Double? = nil
    var showsDisclosure = false

    private var weightText: String {
        snapshot.weight.map { store.displayWeightUnit.text(fromKilograms: $0) } ?? "—"
    }

    private var previousDelta: String? {
        guard let weight = snapshot.weight, let previousWeight else { return nil }
        let value = store.displayWeightUnit.fromKilograms(weight - previousWeight)
        return QNDisplayFormatter.number(value, maximumFractionDigits: 2, signed: true)
    }

    private var targetRelation: String? {
        guard let weight = snapshot.weight, let targetWeight else { return nil }
        let difference = weight - targetWeight
        let value = store.displayWeightUnit.fromKilograms(abs(difference))
        let number = QNDisplayFormatter.number(value, maximumFractionDigits: 2)
        if abs(difference) < 0.000_001 { return "已达到目标" }
        return "\(difference > 0 ? "高于" : "低于")目标 \(number) \(store.displayWeightUnit.symbol)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("最新体重").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                if showsDisclosure {
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            HStack(alignment: .lastTextBaseline, spacing: 6) {
                Text(weightText)
                    .font(.system(size: 50, weight: .bold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7)
                if snapshot.weight != nil {
                    Text(store.displayWeightUnit.symbol).font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 16) {
                if let previousDelta {
                    Label("较上次 \(previousDelta) \(store.displayWeightUnit.symbol)", systemImage: "arrow.left.arrow.right")
                } else {
                    Text("暂无上一条有效体重")
                }
                Spacer(minLength: 4)
                if let targetRelation {
                    Text(targetRelation)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .qnModernCard()
    }
}

struct QNModernSegmentCard: View {
    @EnvironmentObject private var store: QNAppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let snapshot: QNMeasurementSnapshot
    @State private var showFat = false
    @State private var selected: QNBodyRegion = .trunk

    private var hasAnySegmentValue: Bool {
        QNBodyRegion.allCases.contains { region in
            [region.muscleType, region.fatIndexType, region.fatMassType, region.muscleIndexType]
                .contains { region.value(type: $0, in: snapshot) != nil }
        }
    }

    private var availableRegions: [QNBodyRegion] {
        QNBodyRegion.allCases.filter { $0.hasValue(showFat: showFat, in: snapshot) }
    }

    private var accent: Color { showFat ? QNModernStyle.fat : QNModernStyle.muscle }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text("身体分段").font(.title3.weight(.bold))
                Spacer()
                Picker("分段指标", selection: $showFat) {
                    Text("肌肉").tag(false)
                    Text("脂肪").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 180)
            }

            if hasAnySegmentValue {
                QNModernBodyDiagram(snapshot: snapshot, showFat: showFat, selected: $selected)
                    .frame(height: 220)
                segmentValues
                QNModernSegmentDetails(snapshot: snapshot, region: selected, showFat: showFat)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "figure.stand").foregroundStyle(.secondary)
                    Text("本次记录未包含分段数据。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
            }
        }
        .padding(QNModernStyle.cardPadding)
        .qnModernCard()
        .onAppear { selectFirstAvailable() }
        .onChange(of: showFat) { _ in selectFirstAvailable() }
    }

    private func selectFirstAvailable() {
        if !selected.hasValue(showFat: showFat, in: snapshot), let first = availableRegions.first {
            selected = first
        }
    }

    private var segmentValues: some View {
        VStack(spacing: 8) {
            segmentButton(.trunk)
            if dynamicTypeSize.isAccessibilitySize {
                ForEach([QNBodyRegion.rightArm, .leftArm, .rightLeg, .leftLeg]) { segmentButton($0) }
            } else {
                HStack(spacing: 8) {
                    segmentButton(.rightArm)
                    segmentButton(.leftArm)
                }
                HStack(spacing: 8) {
                    segmentButton(.rightLeg)
                    segmentButton(.leftLeg)
                }
            }
        }
    }

    private func segmentButton(_ region: QNBodyRegion) -> some View {
        let available = region.hasValue(showFat: showFat, in: snapshot)
        let type = showFat ? region.fatMassType : region.muscleType
        return Button {
            if available { selected = region }
        } label: {
            HStack {
                Text(region.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(segmentValue(region: region, type: type))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(selected == region && available ? accent.opacity(0.10) : Color.primary.opacity(0.035))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(selected == region && available ? accent : Color.clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.55)
    }

    private func segmentValue(region: QNBodyRegion, type: Int) -> String {
        guard let value = region.value(type: type, in: snapshot) else { return "—" }
        let definition = QNMetricCatalog.definition(for: type)
        if definition.unit == "kg" {
            return "\(store.displayWeightUnit.text(fromKilograms: value, precision: definition.precision)) \(store.displayWeightUnit.symbol)"
        }
        return QNDisplayFormatter.number(value, maximumFractionDigits: definition.precision)
    }
}

private struct QNModernBodyDiagram: View {
    @EnvironmentObject private var store: QNAppStore
    let snapshot: QNMeasurementSnapshot
    let showFat: Bool
    @Binding var selected: QNBodyRegion

    private var accent: Color { showFat ? QNModernStyle.fat : QNModernStyle.muscle }

    var body: some View {
        GeometryReader { proxy in
            let diagramWidth = min(proxy.size.width * 0.54, 180)
            ZStack {
                Circle()
                    .fill(Color.secondary.opacity(0.18))
                    .frame(width: diagramWidth * 0.24, height: diagramWidth * 0.24)
                    .position(x: proxy.size.width / 2, y: 25)
                    .accessibilityHidden(true)

                ForEach(QNBodyRegion.allCases) { region in
                    let available = region.hasValue(showFat: showFat, in: snapshot)
                    QNModernBodyRegionShape(region: region)
                        .fill(available && selected == region ? accent : Color.secondary.opacity(available ? 0.26 : 0.12))
                        .overlay(
                            QNModernBodyRegionShape(region: region)
                                .stroke(available && selected == region ? accent.opacity(0.95) : Color.primary.opacity(0.08), lineWidth: 1)
                        )
                        .frame(width: diagramWidth, height: 190)
                        .position(x: proxy.size.width / 2, y: 125)
                        .contentShape(QNModernBodyRegionShape(region: region))
                        .onTapGesture { if available { selected = region } }
                        .allowsHitTesting(available)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(region.title)
                        .accessibilityValue(accessibilityValue(region))
                        .accessibilityAddTraits(selected == region ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
    }

    private func accessibilityValue(_ region: QNBodyRegion) -> String {
        let type = showFat ? region.fatMassType : region.muscleType
        guard let value = region.value(type: type, in: snapshot) else { return "无数据" }
        if !showFat {
            return "\(store.displayWeightUnit.text(fromKilograms: value)) \(store.displayWeightUnit.symbol)"
        }
        return QNDisplayFormatter.number(value, maximumFractionDigits: QNMetricCatalog.definition(for: type).precision)
    }

}

private struct QNModernBodyRegionShape: Shape {
    let region: QNBodyRegion

    func path(in rect: CGRect) -> Path {
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * y)
        }
        var path = Path()
        switch region {
        case .trunk:
            path.move(to: point(0.37, 0.23))
            path.addCurve(to: point(0.63, 0.23), control1: point(0.42, 0.19), control2: point(0.58, 0.19))
            path.addCurve(to: point(0.66, 0.56), control1: point(0.68, 0.32), control2: point(0.69, 0.46))
            path.addCurve(to: point(0.34, 0.56), control1: point(0.59, 0.61), control2: point(0.41, 0.61))
            path.addCurve(to: point(0.37, 0.23), control1: point(0.31, 0.46), control2: point(0.32, 0.32))
            path.closeSubpath()
        case .rightArm:
            path.move(to: point(0.34, 0.25))
            path.addCurve(to: point(0.27, 0.28), control1: point(0.31, 0.24), control2: point(0.29, 0.25))
            path.addLine(to: point(0.14, 0.51))
            path.addCurve(to: point(0.22, 0.57), control1: point(0.11, 0.56), control2: point(0.17, 0.60))
            path.addLine(to: point(0.39, 0.34))
            path.closeSubpath()
        case .leftArm:
            path.move(to: point(0.66, 0.25))
            path.addCurve(to: point(0.73, 0.28), control1: point(0.69, 0.24), control2: point(0.71, 0.25))
            path.addLine(to: point(0.86, 0.51))
            path.addCurve(to: point(0.78, 0.57), control1: point(0.89, 0.56), control2: point(0.83, 0.60))
            path.addLine(to: point(0.61, 0.34))
            path.closeSubpath()
        case .rightLeg:
            path.move(to: point(0.35, 0.56))
            path.addCurve(to: point(0.49, 0.57), control1: point(0.39, 0.54), control2: point(0.45, 0.54))
            path.addLine(to: point(0.46, 0.92))
            path.addCurve(to: point(0.33, 0.91), control1: point(0.45, 0.98), control2: point(0.34, 0.98))
            path.closeSubpath()
        case .leftLeg:
            path.move(to: point(0.51, 0.57))
            path.addCurve(to: point(0.65, 0.56), control1: point(0.55, 0.54), control2: point(0.61, 0.54))
            path.addLine(to: point(0.67, 0.91))
            path.addCurve(to: point(0.54, 0.92), control1: point(0.66, 0.98), control2: point(0.55, 0.98))
            path.closeSubpath()
        }
        return path
    }
}

private struct QNModernSegmentDetails: View {
    @EnvironmentObject private var store: QNAppStore
    let snapshot: QNMeasurementSnapshot
    let region: QNBodyRegion
    let showFat: Bool

    private var types: [(Int, String, Bool)] {
        if showFat {
            return [(region.fatMassType, "脂肪量原值", false), (region.fatIndexType, "脂肪指标原值", false)]
        }
        return [(region.muscleType, "肌肉量", true), (region.muscleIndexType, "肌肉比例原值", false)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(region.title).font(.headline)
            ForEach(types, id: \.0) { type, title, confirmedMass in
                HStack {
                    Text(title).foregroundStyle(.secondary)
                    Spacer()
                    Text(display(type: type, confirmedMass: confirmedMass))
                        .font(.body.weight(.semibold).monospacedDigit())
                }
                .font(.subheadline)
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func display(type: Int, confirmedMass: Bool) -> String {
        guard let value = region.value(type: type, in: snapshot) else { return "—" }
        let definition = QNMetricCatalog.definition(for: type)
        if confirmedMass {
            let converted = store.displayWeightUnit.fromKilograms(value)
            return "\(QNDisplayFormatter.number(converted, maximumFractionDigits: definition.precision)) \(store.displayWeightUnit.symbol)"
        }
        return QNDisplayFormatter.number(value, maximumFractionDigits: definition.precision)
    }
}

struct QNModernShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

struct QNModernShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
