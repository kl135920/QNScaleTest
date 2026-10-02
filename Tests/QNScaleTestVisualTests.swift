import XCTest
import SwiftUI
import UIKit

private struct QNUIHealthKitStub: QNHealthKitServiceProtocol {
    let isAvailable = true
    let authorizationStateText = "写入未请求"
    let writeAuthorizationStateText = "写入未请求"
    let readAuthorizationStateText = "尚未请求（系统不公开读取状态）"
    func requestAuthorization() async throws {}
    func write(_ snapshot: QNMeasurementSnapshot) async throws -> Int { 0 }
    func importMeasurements(profile: QNUserProfile) async throws -> [[String: Any]] { [] }
}

final class QNScaleTestVisualTests: XCTestCase {
    @MainActor
    private func makeStore(partial: Bool = false, empty: Bool = false, single: Bool = false, abnormal: Bool = false) throws -> QNAppStore {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "QNScaleMeasurementFixture.redacted", withExtension: "json"))
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let profile = QNUserProfile(userId: "ui-test-only", nickname: "测试用户", gender: "male", birthday: Date(timeIntervalSince1970: 500000000), height: 169, athleteType: 0, targetWeight: 70)
        let repository = try QNMeasurementRepository(inMemory: true)
        if !empty {
            let weights = single ? [83.35] : [85.2, 84.8, 85.1, 84.7, 84.2, 83.9, 83.35]
            for (index, weight) in weights.enumerated() {
                var measurement = fixture
                var scale = try XCTUnwrap(measurement["scaleData"] as? [String: Any])
                let daysAgo = Double(weights.count - index - 1) * 4
                scale["measureTime"] = QNMeasurementMapper.isoDate(Date().addingTimeInterval(-daysAgo * 86400 - 3600))
                scale["hmac"] = "ui-test-only-\(index)"
                scale["weight"] = weight
                scale["eightIsAbnormal"] = abnormal ? 1 : 0
                scale["eightReasonMask"] = abnormal ? 4 : 0
                measurement["scaleData"] = scale
                var items = try XCTUnwrap(measurement["items"] as? [[String: Any]])
                if let item = items.firstIndex(where: { ($0["type"] as? Int) == 1 }) { items[item]["value"] = weight }
                if partial { items = items.filter { [1, 2, 3, 12].contains($0["type"] as? Int ?? -1) } }
                measurement["items"] = items
                _ = try repository.save(measurement: measurement, profile: profile)
            }
        }
        QNSetScaleServiceTestState("未连接", false)
        return QNAppStore(uiTestingRepository: repository, profile: profile, healthKit: QNUIHealthKitStub())
    }

    @MainActor
    private func capture<V: View>(_ name: String, view: V, store: QNAppStore, dark: Bool = false, large: Bool = false, size: CGSize? = nil, scrollToBottom: Bool = false) async throws {
        UITabBar.appearance().isHidden = true
        let frame = CGRect(origin: .zero, size: size ?? UIScreen.main.bounds.size)
        let window = UIWindow(frame: frame)
        if let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first { window.windowScene = scene }
        window.frame = frame
        let controller = UIHostingController(rootView: view
            .environmentObject(store)
            .environment(\.dynamicTypeSize, large ? .accessibility3 : .large)
            .preferredColorScheme(dark ? .dark : .light))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(nanoseconds: 700_000_000)
        controller.view.layoutIfNeeded()
        if scrollToBottom {
            let scrolls = allSubviews(controller.view).compactMap { $0 as? UIScrollView }
            let scroll = try XCTUnwrap(scrolls.filter { !$0.isHidden && $0.bounds.height > 100 && $0.contentSize.height > $0.bounds.height }.max { $0.contentSize.height < $1.contentSize.height })
            scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top, scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
            try await Task.sleep(nanoseconds: 300_000_000)
        }
        let renderer = UIGraphicsImageRenderer(bounds: frame)
        let image = renderer.image { _ in
            XCTAssertTrue(window.drawHierarchy(in: frame, afterScreenUpdates: true))
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertGreaterThan(image.size.width, 300)
        XCTAssertGreaterThan(image.pngData()?.count ?? 0, 10_000, "Screenshot must contain rendered content")
        let bitmap = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(bitmap.dataProvider?.data)
        let bytes = try XCTUnwrap(CFDataGetBytePtr(data))
        var colors = Set<UInt32>()
        for y in stride(from: 0, to: bitmap.height, by: max(bitmap.height / 50, 1)) {
            for x in stride(from: 0, to: bitmap.width, by: max(bitmap.width / 50, 1)) {
                let offset = y * bitmap.bytesPerRow + x * (bitmap.bitsPerPixel / 8)
                colors.insert(UInt32(bytes[offset]) << 16 | UInt32(bytes[offset + 1]) << 8 | UInt32(bytes[offset + 2]))
            }
        }
        XCTAssertGreaterThan(colors.count, 8, "A blank or black screenshot is not valid visual evidence")
    }

    @MainActor
    private func allSubviews(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(allSubviews)
    }

    @MainActor func testFourTabsAndHomeBodyScreenshots() async throws {
        let store = try makeStore()
        for tab in QNAppTab.allCases {
            try await capture("\(tab)-light", view: QNMainTabView(initialTab: tab), store: store)
        }
        try await capture("home-dark", view: QNMainTabView(), store: store, dark: true)
        try await capture("home-body", view: QNModernSegmentCard(snapshot: XCTUnwrap(store.latestRecord)).padding(20).background(QNModernStyle.page), store: store)
        try await capture("home-bottom", view: QNMainTabView(), store: store, scrollToBottom: true)
        try await capture("trend-bottom", view: QNMainTabView(initialTab: .trend), store: store, scrollToBottom: true)
        try await capture("profile-bottom", view: QNMainTabView(initialTab: .profile), store: store, scrollToBottom: true)
    }

    @MainActor func testLargeTypeSmallViewportAndReportScreenshots() async throws {
        let store = try makeStore()
        try await capture("home-large-type", view: QNMainTabView(), store: store, large: true)
        try await capture("profile-large-type", view: QNMainTabView(initialTab: .profile), store: store, large: true)
        try await capture("home-small-viewport", view: QNMainTabView(), store: store, size: CGSize(width: 375, height: 667))
        try await capture("report-light", view: QNModernReportView(snapshot: XCTUnwrap(store.latestRecord), onExport: {}), store: store)
        try await capture("report-bottom", view: QNModernReportView(snapshot: XCTUnwrap(store.latestRecord), onExport: {}), store: store, scrollToBottom: true)
    }

    @MainActor func testPartialEmptySingleAndAbnormalScreenshots() async throws {
        let partial = try makeStore(partial: true)
        XCTAssertNil(partial.latestRecord?.muscleMass)
        try await capture("home-health-partial", view: QNMainTabView(), store: partial)
        let empty = try makeStore(empty: true)
        try await capture("home-empty", view: QNMainTabView(), store: empty)
        try await capture("trend-empty", view: QNMainTabView(initialTab: .trend), store: empty)
        let single = try makeStore(single: true)
        try await capture("trend-single", view: QNMainTabView(initialTab: .trend), store: single)
        let abnormal = try makeStore(single: true, abnormal: true)
        XCTAssertTrue(try XCTUnwrap(abnormal.latestRecord).isAbnormal)
        try await capture("report-abnormal", view: QNModernReportView(snapshot: XCTUnwrap(abnormal.latestRecord), onExport: {}), store: abnormal)
    }

    @MainActor func testNativeBodyPathsAreSeparateAndCorrectlyMirrored() {
        let rect = CGRect(x: 0, y: 0, width: 180, height: 270)
        let paths = Dictionary(uniqueKeysWithValues: QNBodyRegion.allCases.map { ($0, QNModernBodyRegionShape(region: $0).path(in: rect)) })
        XCTAssertLessThan(paths[.rightArm]!.boundingRect.maxX, rect.midX)
        XCTAssertGreaterThan(paths[.leftArm]!.boundingRect.minX, rect.midX)
        XCTAssertLessThan(paths[.rightLeg]!.boundingRect.maxX, rect.midX)
        XCTAssertGreaterThan(paths[.leftLeg]!.boundingRect.minX, rect.midX)
        for x in stride(from: CGFloat(0), through: rect.width, by: 2) {
            for y in stride(from: CGFloat(0), through: rect.height, by: 2) {
                let point = CGPoint(x: x, y: y)
                XCTAssertLessThanOrEqual(paths.values.filter { $0.contains(point) }.count, 1, "Five regions must not overlap at \(point)")
                if QNModernBodyHead().path(in: rect).contains(point) { XCTAssertFalse(paths.values.contains { $0.contains(point) }) }
            }
        }
    }
}
