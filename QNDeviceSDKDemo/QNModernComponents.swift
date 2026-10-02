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
    static let sectionSpacing: CGFloat = 14
    static let pageTopPadding: CGFloat = 8
    static let pageBottomPadding: CGFloat = 20
}

extension View {
    func qnModernCard(cornerRadius: CGFloat = 20) -> some View {
        background(QNModernStyle.card)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

struct QNModernPageTitle: View {
    let title: String
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 34

    var body: some View {
        Text(title)
            .font(.system(size: size, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

struct QNModernSettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
                .padding(.horizontal, 4).accessibilityAddTraits(.isHeader)
            content.qnModernCard(cornerRadius: 18)
        }
    }
}

struct QNModernPrimaryButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(QNModernStyle.action)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct QNModernMetricTile: View {
    @EnvironmentObject private var store: QNAppStore
    @ScaledMetric(relativeTo: .title) private var numberSize: CGFloat = 29
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
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(formatted.number)
                    .font(.system(size: numberSize, weight: .semibold).monospacedDigit())
                    .fixedSize(horizontal: false, vertical: true)
                if value != nil, let unit = formatted.unit {
                    Text(unit).font(.caption).foregroundStyle(.secondary)
                }
            }
            if value != nil, let evaluation {
                Text(evaluation)
                    .font(.caption2)
                    .foregroundStyle(evaluation.contains("偏高") || evaluation.contains("肥胖") ? QNModernStyle.fat : accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .padding(QNModernStyle.cardPadding)
        .qnModernCard(cornerRadius: 18)
        .accessibilityElement(children: .combine)
    }
}

struct QNModernWeightCard: View {
    @EnvironmentObject private var store: QNAppStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 54
    let snapshot: QNMeasurementSnapshot
    var previousWeight: Double? = nil
    var targetWeight: Double? = nil
    var showsDisclosure = false

    private var weightText: String {
        snapshot.weight.map { store.displayWeightUnit.text(fromKilograms: $0) } ?? "—"
    }

    private var previousChange: String? {
        QNDisplayFormatter.weightChange(current: snapshot.weight, previous: previousWeight, unit: store.displayWeightUnit)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("最新体重").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                if showsDisclosure {
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    weightNumber
                    weightUnit
                }
            } else {
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    weightNumber
                    weightUnit
                }
            }
            if previousChange != nil || targetRelation != nil {
                VStack(alignment: .leading, spacing: 4) {
                    if let previousChange { Text(previousChange) }
                    if let targetRelation { Text(targetRelation) }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .qnModernCard()
    }

    private var weightNumber: some View {
        Text(weightText)
            .font(.system(size: numberSize, weight: .semibold).monospacedDigit())
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var weightUnit: some View {
        if snapshot.weight != nil {
            Text(store.displayWeightUnit.symbol).font(.title3).foregroundStyle(.secondary)
        }
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

    private var accent: Color { QNModernStyle.action }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("身体分段").font(.headline).accessibilityAddTraits(.isHeader)
                modePicker
            } else {
                HStack(spacing: 12) {
                    Text("身体分段").font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer()
                    modePicker.frame(maxWidth: 148)
                }
            }

            if hasAnySegmentValue {
                QNModernBodyDiagram(snapshot: snapshot, showFat: showFat, selected: $selected)
                    .frame(height: 238)
                segmentValues
                if selected.hasValue(showFat: showFat, in: snapshot) {
                    Divider()
                    QNModernSegmentDetails(snapshot: snapshot, region: selected)
                } else {
                    Text("本次记录未包含\(showFat ? "脂肪" : "肌肉")分段数据。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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

    private var modePicker: some View {
        Picker("分段指标", selection: $showFat) {
            Text("肌肉").tag(false)
            Text("脂肪").tag(true)
        }
        .pickerStyle(.segmented)
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
                    .foregroundStyle(selected == region && available ? .primary : .secondary)
                Spacer(minLength: 8)
                Text(segmentValue(region: region, type: type))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(selected == region && available ? accent.opacity(0.08) : Color.primary.opacity(0.025))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!available)
        .opacity(available ? 1 : 0.55)
        .accessibilityAddTraits(selected == region && available ? .isSelected : [])
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

struct QNModernBodyDiagram: View {
    @EnvironmentObject private var store: QNAppStore
    let snapshot: QNMeasurementSnapshot
    let showFat: Bool
    @Binding var selected: QNBodyRegion

    var body: some View {
        GeometryReader { proxy in
            let diagramWidth = min(proxy.size.width, proxy.size.height * 0.66)
            ZStack {
                QNModernBodyHead()
                    .fill(Color.secondary.opacity(0.24))
                    .accessibilityHidden(true)
                ForEach(QNBodyRegion.allCases) { region in
                    let available = region.hasValue(showFat: showFat, in: snapshot)
                    Button { selected = region } label: {
                        QNModernBodyRegionShape(region: region)
                            .fill(available && selected == region ? QNModernStyle.action : Color.secondary.opacity(available ? 0.28 : 0.11))
                            .contentShape(QNBodyRegionHitShape(region: region))
                    }
                    .buttonStyle(.plain)
                    .disabled(!available)
                    .accessibilityLabel(region.title)
                    .accessibilityValue(accessibilityValue(region))
                    .accessibilityAddTraits(selected == region && available ? .isSelected : [])
                }
            }
            .frame(width: diagramWidth, height: proxy.size.height)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
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

// All paths share one coordinate space. A small physical gap separates the
// five segments; the neutral head/neck never participates in selection.
struct QNModernBodyHead: Shape {
    func path(in rect: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
        }
        var path = Path()
        path.move(to: p(0.5, 0.01))
        path.addCurve(to: p(0.581, 0.060), control1: p(0.553, 0.005), control2: p(0.583, 0.028))
        path.addCurve(to: p(0.553, 0.120), control1: p(0.581, 0.086), control2: p(0.573, 0.104))
        path.addCurve(to: p(0.540, 0.146), control1: p(0.538, 0.129), control2: p(0.539, 0.140))
        path.addLine(to: p(0.548, 0.155))
        path.addQuadCurve(to: p(0.452, 0.155), control: p(0.5, 0.165))
        path.addLine(to: p(0.460, 0.146))
        path.addCurve(to: p(0.447, 0.120), control1: p(0.461, 0.140), control2: p(0.462, 0.129))
        path.addCurve(to: p(0.419, 0.060), control1: p(0.427, 0.104), control2: p(0.419, 0.086))
        path.addCurve(to: p(0.5, 0.01), control1: p(0.417, 0.028), control2: p(0.447, 0.005))
        path.closeSubpath()
        return path
    }
}

struct QNModernBodyRegionShape: Shape {
    let region: QNBodyRegion

    func path(in rect: CGRect) -> Path {
        let mirrored = region == .leftArm || region == .leftLeg
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + rect.width * (mirrored ? 1 - x : x), y: rect.minY + rect.height * y)
        }
        var path = Path()
        switch region {
        case .trunk:
            path.move(to: point(0.445, 0.168))
            path.addQuadCurve(to: point(0.555, 0.168), control: point(0.5, 0.183))
            path.addCurve(to: point(0.679, 0.196), control1: point(0.593, 0.179), control2: point(0.650, 0.179))
            path.addQuadCurve(to: point(0.644, 0.287), control: point(0.666, 0.240))
            path.addCurve(to: point(0.607, 0.362), control1: point(0.628, 0.310), control2: point(0.607, 0.336))
            path.addCurve(to: point(0.642, 0.474), control1: point(0.609, 0.409), control2: point(0.639, 0.441))
            path.addQuadCurve(to: point(0.501, 0.514), control: point(0.612, 0.490))
            path.addQuadCurve(to: point(0.358, 0.474), control: point(0.388, 0.490))
            path.addCurve(to: point(0.393, 0.362), control1: point(0.361, 0.441), control2: point(0.391, 0.409))
            path.addCurve(to: point(0.356, 0.287), control1: point(0.393, 0.336), control2: point(0.372, 0.310))
            path.addQuadCurve(to: point(0.321, 0.196), control: point(0.334, 0.240))
            path.addCurve(to: point(0.445, 0.168), control1: point(0.350, 0.179), control2: point(0.407, 0.179))
            path.closeSubpath()
        case .rightArm, .leftArm:
            path.move(to: point(0.305, 0.198))
            path.addCurve(to: point(0.237, 0.258), control1: point(0.264, 0.203), control2: point(0.245, 0.231))
            path.addCurve(to: point(0.193, 0.332), control1: point(0.222, 0.284), control2: point(0.208, 0.312))
            path.addCurve(to: point(0.152, 0.438), control1: point(0.178, 0.364), control2: point(0.159, 0.407))
            path.addCurve(to: point(0.134, 0.479), control1: point(0.148, 0.453), control2: point(0.131, 0.464))
            path.addQuadCurve(to: point(0.182, 0.499), control: point(0.131, 0.499))
            path.addQuadCurve(to: point(0.212, 0.472), control: point(0.207, 0.491))
            path.addLine(to: point(0.224, 0.455))
            path.addLine(to: point(0.218, 0.443))
            path.addCurve(to: point(0.259, 0.344), control1: point(0.226, 0.414), control2: point(0.247, 0.373))
            path.addCurve(to: point(0.319, 0.273), control1: point(0.279, 0.320), control2: point(0.301, 0.296))
            path.addQuadCurve(to: point(0.305, 0.198), control: point(0.315, 0.227))
            path.closeSubpath()
        case .rightLeg, .leftLeg:
            path.move(to: point(0.360, 0.489))
            path.addQuadCurve(to: point(0.489, 0.532), control: point(0.427, 0.510))
            path.addCurve(to: point(0.447, 0.684), control1: point(0.484, 0.579), control2: point(0.456, 0.636))
            path.addCurve(to: point(0.435, 0.803), control1: point(0.441, 0.722), control2: point(0.443, 0.752))
            path.addCurve(to: point(0.414, 0.913), control1: point(0.426, 0.848), control2: point(0.408, 0.887))
            path.addQuadCurve(to: point(0.417, 0.949), control: point(0.421, 0.935))
            path.addQuadCurve(to: point(0.320, 0.950), control: point(0.362, 0.960))
            path.addQuadCurve(to: point(0.315, 0.929), control: point(0.303, 0.942))
            path.addLine(to: point(0.346, 0.906))
            path.addCurve(to: point(0.356, 0.799), control1: point(0.352, 0.879), control2: point(0.348, 0.838))
            path.addCurve(to: point(0.371, 0.685), control1: point(0.363, 0.754), control2: point(0.378, 0.724))
            path.addCurve(to: point(0.360, 0.489), control1: point(0.355, 0.626), control2: point(0.341, 0.551))
            path.closeSubpath()
        }
        return path
    }
}

private struct QNBodyRegionHitShape: Shape {
    let region: QNBodyRegion
    func path(in rect: CGRect) -> Path {
        let outline = QNModernBodyRegionShape(region: region).path(in: rect)
        var hitArea = outline
        hitArea.addPath(outline.strokedPath(StrokeStyle(lineWidth: 14, lineCap: .round, lineJoin: .round)))
        return hitArea
    }
}

private struct QNModernSegmentDetails: View {
    @EnvironmentObject private var store: QNAppStore
    let snapshot: QNMeasurementSnapshot
    let region: QNBodyRegion
    private var types: [(Int, String, Bool)] {
        [(region.muscleType, "肌肉量", true), (region.fatMassType, "脂肪量原值", false),
         (region.muscleIndexType, "肌肉比例原值", false), (region.fatIndexType, "脂肪指标原值", false)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(region.title).font(.headline)
            ForEach(types.filter { region.value(type: $0.0, in: snapshot) != nil }, id: \.0) { type, title, confirmedMass in
                HStack(alignment: .firstTextBaseline) {
                    Text(title).foregroundStyle(.secondary)
                    Spacer()
                    Text(display(type: type, confirmedMass: confirmedMass))
                        .font(.subheadline.weight(.medium).monospacedDigit())
                }
                .font(.subheadline)
            }
        }
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
