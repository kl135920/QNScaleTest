import XCTest
import CoreData

final class QNScaleTestPersistenceTests: XCTestCase {
    private func fixture() throws -> [String: Any] {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: "QNScaleMeasurementFixture.redacted", withExtension: "json"))
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func profile() -> QNUserProfile {
        QNUserProfile(userId: "test-user", nickname: "测试用户", gender: "male", birthday: Date(timeIntervalSince1970: 500000000), height: 169, athleteType: 0, targetWeight: nil)
    }

    func testFixtureMapperAndBoneRatio() throws {
        let mapped = try QNMeasurementMapper.map(measurement: fixture(), profile: profile())
        XCTAssertEqual(try XCTUnwrap(mapped.valuesByType[1]), 84.2, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(mapped.valuesByType[7]), 41.6, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(mapped.valuesByType[31]), 68.6, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(mapped.valuesByType[112]), 35.0, accuracy: 0.0001)
        XCTAssertEqual(mapped.boneMassPercentage ?? 0, 4.5 / 84.2 * 100, accuracy: 0.000001)
        XCTAssertEqual(mapped.items.count, 30)
    }

    func testComparisonIncludesFiveSegmentMuscleAndFatMetrics() throws {
        var endMeasurement = try fixture()
        var scaleData = try XCTUnwrap(endMeasurement["scaleData"] as? [String: Any])
        scaleData["measureTime"] = "2026-10-02T15:34:46+08:00"
        endMeasurement["scaleData"] = scaleData
        var items = try XCTUnwrap(endMeasurement["items"] as? [[String: Any]])
        for index in items.indices where (101...105).contains(items[index]["type"] as? Int ?? -1) || (113...117).contains(items[index]["type"] as? Int ?? -1) {
            items[index]["value"] = (items[index]["value"] as? Double ?? 0) + 0.1
        }
        endMeasurement["items"] = items

        let repository = try QNMeasurementRepository(inMemory: true)
        let start = try repository.save(measurement: fixture(), profile: profile())
        let end = try repository.save(measurement: endMeasurement, profile: profile())
        let comparison = try XCTUnwrap(QNHistoryComparisonService.compare(start: start, end: end))

        XCTAssertEqual(comparison.rows.filter { QNMetricCatalog.segmentMuscleTypes.contains($0.type) }.count, 5)
        XCTAssertEqual(comparison.rows.filter { QNMetricCatalog.segmentFatTypes.contains($0.type) }.count, 5)
        XCTAssertEqual(try XCTUnwrap(comparison.rows.first { $0.type == 101 }?.difference), 0.1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(comparison.rows.first { $0.type == 113 }?.difference), 0.1, accuracy: 0.0001)
    }

    func testMapperAcceptsObjectiveCBridgeContainers() throws {
        let source = try fixture()
        let items = try XCTUnwrap(source["items"] as? [[String: Any]])
        let measurement: [String: Any] = [
            "metadata": NSDictionary(dictionary: try XCTUnwrap(source["metadata"] as? [String: Any])),
            "device": NSDictionary(dictionary: try XCTUnwrap(source["device"] as? [String: Any])),
            "user": NSDictionary(dictionary: try XCTUnwrap(source["user"] as? [String: Any])),
            "scaleData": NSDictionary(dictionary: try XCTUnwrap(source["scaleData"] as? [String: Any])),
            "items": NSArray(array: items.map { NSDictionary(dictionary: $0) })
        ]

        let mapped = try QNMeasurementMapper.map(measurement: measurement, profile: profile())
        XCTAssertEqual(try XCTUnwrap(mapped.valuesByType[1]), 84.2, accuracy: 0.0001)
        XCTAssertEqual(mapped.items.count, items.count)
        XCTAssertFalse(mapped.deduplicationKey.isEmpty)
    }

    func testMapperAcceptsSDKTimestampWithFractionalSecondsAndOffset() throws {
        var measurement = try fixture()
        var scaleData = try XCTUnwrap(measurement["scaleData"] as? [String: Any])
        scaleData["measureTime"] = "2026-10-01T18:35:20.000+08:00"
        measurement["scaleData"] = scaleData

        let mapped = try QNMeasurementMapper.map(measurement: measurement, profile: profile())

        XCTAssertEqual(QNMeasurementMapper.isoDate(mapped.measureTime), "2026-10-01T10:35:20Z")
    }

    func testRepositoryDeduplicatesAndReopens() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QNScaleTest-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url); try? FileManager.default.removeItem(at: url.appendingPathExtension("-shm")); try? FileManager.default.removeItem(at: url.appendingPathExtension("-wal")) }
        let measurement = try fixture()
        let first: QNMeasurementSnapshot
        do {
            let repository = try QNMeasurementRepository(storeURL: url)
            first = try repository.save(measurement: measurement, profile: profile())
            let duplicate = try repository.save(measurement: measurement, profile: profile())
            XCTAssertEqual(first.id, duplicate.id)
            XCTAssertEqual(try repository.fetchAll().count, 1)
        }
        let reopened = try QNMeasurementRepository(storeURL: url)
        let records = try reopened.fetchAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].boneMassPercentage ?? 0, 4.5 / 84.2 * 100, accuracy: 0.000001)
        XCTAssertEqual(records[0].metrics["skeletalMuscleRate"] ?? 0, 41.6, accuracy: 0.0001)
        XCTAssertEqual(records[0].metrics["muscleMassRate"] ?? 0, 68.6, accuracy: 0.0001)
    }

    func testV1StoreMigratesToV2AndCopiesLegacyMuscleRate() throws {
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent("QNScaleTest-V1-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: storeURL); try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("-shm")); try? FileManager.default.removeItem(at: storeURL.appendingPathExtension("-wal")) }
        let appBundle = Bundle(for: MeasurementManagedObject.self)
        let momd = try XCTUnwrap(appBundle.url(forResource: "QNScaleModel", withExtension: "momd"))
        let v1Model = try XCTUnwrap(NSManagedObjectModel(contentsOf: momd.appendingPathComponent("V1.mom")))
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: v1Model)
        try coordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: nil)
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.performAndWait {
            let object = NSEntityDescription.insertNewObject(forEntityName: "Measurement", into: context)
            object.setValue(UUID(), forKey: "id")
            object.setValue("legacy-user|legacy-device|legacy-hmac", forKey: "deduplicationKey")
            object.setValue(Date(), forKey: "measureTime")
            object.setValue(Date(), forKey: "createdAt")
            object.setValue(Date(), forKey: "updatedAt")
            object.setValue(41.6, forKey: "muscleRate")
            object.setValue(84.2, forKey: "weight")
            try? context.save()
        }
        let migrated = try QNMeasurementRepository(storeURL: storeURL)
        let record = try XCTUnwrap(try migrated.fetchAll().first)
        XCTAssertEqual(record.schemaVersion, 1)
        XCTAssertEqual(record.metrics["skeletalMuscleRate"] ?? 0, 41.6, accuracy: 0.0001)
    }

    func testDisplayFormatterRemovesMeaninglessTrailingZeros() {
        XCTAssertEqual(QNDisplayFormatter.number(140, maximumFractionDigits: 2), "140")
        XCTAssertEqual(QNDisplayFormatter.number(167.5, maximumFractionDigits: 2), "167.5")
        XCTAssertEqual(QNDisplayFormatter.number(0.2, maximumFractionDigits: 1, signed: true), "+0.2")
        XCTAssertEqual(QNDisplayFormatter.number(-0.2, maximumFractionDigits: 1, signed: true), "-0.2")
        XCTAssertEqual(QNDisplayWeightUnit.jin.text(fromKilograms: 83.75), "167.5")
    }

    func testTimelineLatestPreviousAndGoalUseMeasurementTime() throws {
        let repository = try QNMeasurementRepository(inMemory: true)
        let start = try repository.save(measurement: measurement(date: "2026-09-01T08:00:00+08:00", weight: 90), profile: profile())
        let middle = try repository.save(measurement: measurement(date: "2026-09-20T08:00:00+08:00", weight: 86), profile: profile())
        let latest = try repository.save(measurement: measurement(date: "2026-10-01T08:00:00+08:00", weight: 84), profile: profile())
        let importedLater = try repository.save(measurement: measurement(date: "2026-08-01T08:00:00+08:00", weight: 92, identifier: "healthkit"), profile: profile())
        let records = [middle, importedLater, latest, start]

        XCTAssertEqual(QNMeasurementTimeline.latest(records)?.id, latest.id)
        XCTAssertEqual(QNMeasurementTimeline.previousValidWeight(before: latest, in: records)?.id, middle.id)
        let progress = try XCTUnwrap(QNGoalProgress.make(records: records, targetWeight: 80))
        XCTAssertEqual(progress.startWeight, 92, accuracy: 0.0001)
        XCTAssertEqual(progress.currentWeight, 84, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(progress.fraction), 8.0 / 12.0, accuracy: 0.0001)
    }

    func testHealthKitPartialRecordKeepsUnavailableMetricsNil() throws {
        let repository = try QNMeasurementRepository(inMemory: true)
        var partial = try fixture()
        partial["device"] = [
            "bluetoothName": "Apple 健康",
            "deviceIdentifier": "healthkit",
            "deviceType": -1,
            "modeId": "HealthKit",
            "isSupportEightElectrodes": false
        ]
        let items = try XCTUnwrap(partial["items"] as? [[String: Any]])
        partial["items"] = items.filter { [1, 2, 3, 12].contains($0["type"] as? Int ?? -1) }
        let snapshot = try repository.save(measurement: partial, profile: profile())

        XCTAssertNotNil(snapshot.weight)
        XCTAssertNotNil(snapshot.bodyFatRate)
        XCTAssertNil(snapshot.muscleMass)
        XCTAssertNil(snapshot.skeletalMuscleMass)
        for region in QNBodyRegion.allCases {
            XCTAssertNil(region.value(type: region.muscleType, in: snapshot))
            XCTAssertNil(region.value(type: region.fatMassType, in: snapshot))
        }
    }

    func testSDKRecordPersistsCoreAndSegmentMetrics() throws {
        let repository = try QNMeasurementRepository(inMemory: true)
        let snapshot = try repository.save(measurement: fixture(), profile: profile())
        XCTAssertNotNil(snapshot.muscleMass)
        XCTAssertNotNil(snapshot.skeletalMuscleMass)
        for region in QNBodyRegion.allCases {
            XCTAssertNotNil(region.value(type: region.muscleType, in: snapshot))
            XCTAssertNotNil(region.value(type: region.fatMassType, in: snapshot))
        }
    }

    func testTrendSeriesUsesActualTimeAndIgnoresMissingValues() throws {
        let repository = try QNMeasurementRepository(inMemory: true)
        let first = try repository.save(measurement: measurement(date: "2026-10-01T00:00:00Z", weight: 80), profile: profile())
        let second = try repository.save(measurement: measurement(date: "2026-10-02T00:00:00Z", weight: 81), profile: profile())
        let last = try repository.save(measurement: measurement(date: "2026-10-05T00:00:00Z", weight: 79), profile: profile())
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-05T00:00:00Z"))
        let metric = try XCTUnwrap(QNTrendMetric.all.first { $0.key == "weight" })
        let series = QNTrendSeries.make(records: [last, first, second], metric: metric, range: .all, now: now)

        XCTAssertEqual(series.points.map(\.value), [80, 81, 79])
        XCTAssertEqual(series.xFraction(for: second.measureTime), 0.25, accuracy: 0.0001)
        XCTAssertEqual(series.statistics?.change ?? 0, -1, accuracy: 0.0001)
        XCTAssertEqual(series.statistics?.minimum ?? 0, 79, accuracy: 0.0001)
        XCTAssertEqual(series.statistics?.maximum ?? 0, 81, accuracy: 0.0001)
    }

    func testComparisonOrdersSelectionsAndDoesNotInventMissingDifference() throws {
        let repository = try QNMeasurementRepository(inMemory: true)
        let earlier = try repository.save(measurement: measurement(date: "2026-10-01T08:00:00+08:00", weight: 80), profile: profile())
        var partial = try measurement(date: "2026-10-02T08:00:00+08:00", weight: 82)
        let items = try XCTUnwrap(partial["items"] as? [[String: Any]])
        partial["items"] = items.filter { ($0["type"] as? Int) != 101 }
        let later = try repository.save(measurement: partial, profile: profile())

        let comparison = try XCTUnwrap(QNHistoryComparisonService.compare(start: later, end: earlier))
        XCTAssertEqual(comparison.start.id, earlier.id)
        XCTAssertEqual(comparison.end.id, later.id)
        XCTAssertEqual(try XCTUnwrap(comparison.rows.first { $0.type == 1 }?.difference), 2, accuracy: 0.0001)
        XCTAssertNil(comparison.rows.first { $0.type == 101 }?.difference)
    }

    func testBodyRegionMappingsAndMeasurementStateReducer() {
        XCTAssertEqual(QNBodyRegion.rightArm.muscleType, 101)
        XCTAssertEqual(QNBodyRegion.leftArm.muscleType, 102)
        XCTAssertEqual(QNBodyRegion.rightArm.muscleIndexType, 119)
        XCTAssertEqual(QNBodyRegion.leftArm.muscleIndexType, 118)
        XCTAssertEqual(QNBodyRegion.trunk.muscleIndexType, 120)
        XCTAssertEqual(QNBodyRegion.rightLeg.muscleIndexType, 122)
        XCTAssertEqual(QNBodyRegion.leftLeg.muscleIndexType, 121)
        XCTAssertEqual(
            QNMeasurementUIState.resolve(sdkState: "初始化成功", bluetoothState: "开启", connectionState: "未连接", isScanning: true, deviceName: "QN-Scale", measurementState: "等待连接", weight: nil, operationError: nil),
            .scanning
        )
        XCTAssertEqual(
            QNMeasurementUIState.resolve(sdkState: "初始化成功", bluetoothState: "开启", connectionState: "已连接", isScanning: false, deviceName: "QN-Scale", measurementState: "测量生物阻抗", weight: 84.2, operationError: nil),
            .measuring(weight: 84.2, state: "测量生物阻抗")
        )
        XCTAssertEqual(
            QNMeasurementUIState.resolve(sdkState: "初始化成功", bluetoothState: "开启", connectionState: "已连接", isScanning: false, deviceName: "QN-Scale", measurementState: "保存失败", weight: 84.2, operationError: "数据库写入失败"),
            .failed("数据库写入失败")
        )
    }

    func testHistoryGroupsUseMeasurementDayAndDescendingOrder() throws {
        let repository = try QNMeasurementRepository(inMemory: true)
        let first = try repository.save(measurement: measurement(date: "2026-10-01T08:00:00+08:00", weight: 80), profile: profile())
        let second = try repository.save(measurement: measurement(date: "2026-10-01T20:00:00+08:00", weight: 81), profile: profile())
        let third = try repository.save(measurement: measurement(date: "2026-10-02T08:00:00+08:00", weight: 82), profile: profile())

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let groups = QNHistoryDayGroup.make(records: [first, third, second], calendar: calendar)

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].records.map(\.id), [third.id])
        XCTAssertEqual(groups[1].records.map(\.id), [second.id, first.id])
    }

    func testPercentageComparisonUsesDirectDifference() throws {
        let repository = try QNMeasurementRepository(inMemory: true)
        var firstMeasurement = try measurement(date: "2026-10-01T08:00:00+08:00", weight: 80)
        var secondMeasurement = try measurement(date: "2026-10-02T08:00:00+08:00", weight: 79)
        var firstItems = try XCTUnwrap(firstMeasurement["items"] as? [[String: Any]])
        var secondItems = try XCTUnwrap(secondMeasurement["items"] as? [[String: Any]])
        if let index = firstItems.firstIndex(where: { ($0["type"] as? Int) == 3 }) { firstItems[index]["value"] = 28.1 }
        if let index = secondItems.firstIndex(where: { ($0["type"] as? Int) == 3 }) { secondItems[index]["value"] = 26.5 }
        firstMeasurement["items"] = firstItems
        secondMeasurement["items"] = secondItems
        let first = try repository.save(measurement: firstMeasurement, profile: profile())
        let second = try repository.save(measurement: secondMeasurement, profile: profile())

        let comparison = try XCTUnwrap(QNHistoryComparisonService.compare(start: first, end: second))
        XCTAssertEqual(try XCTUnwrap(comparison.rows.first { $0.type == 3 }?.difference), -1.6, accuracy: 0.0001)
    }

    func testWeightChangeUsesFlatTextAndPreservesJinPrecision() {
        XCTAssertEqual(QNDisplayFormatter.weightChange(current: 83.35, previous: 83.35, unit: .jin), "与上次持平")
        XCTAssertEqual(QNDisplayFormatter.weightChange(current: 83.35, previous: 83.75, unit: .jin), "较上次 -0.8 斤")
        XCTAssertEqual(QNDisplayFormatter.weightChange(current: 83.35, previous: 83, unit: .kilogram), "较上次 +0.35 kg")
        XCTAssertNil(QNDisplayFormatter.weightChange(current: 83.35, previous: nil, unit: .jin))
        XCTAssertEqual(QNDisplayFormatter.metric(.nan, definition: QNMetricCatalog.definition(for: 1), weightUnit: .jin).number, "—")
        XCTAssertNil(QNDisplayFormatter.metric(.nan, definition: QNMetricCatalog.definition(for: 1), weightUnit: .jin).unit)
    }

    func testTrendTicksAreNeatAndConstantValuesHaveBreathingRoom() {
        for values in [[166.7, 170.4], [83.35], [26.5, 26.5], [0.0], []] {
            let scale = QNTrendAxisScale.make(values: values, precision: 2)
            XCTAssertLessThan(scale.lower, scale.upper)
            XCTAssertGreaterThanOrEqual(scale.ticks.count, 2)
            XCTAssertLessThanOrEqual(scale.ticks.count, 8)
            for value in values { XCTAssertGreaterThanOrEqual(value, scale.lower); XCTAssertLessThanOrEqual(value, scale.upper) }
            for tick in scale.ticks {
                let formatted = QNDisplayFormatter.number(tick, maximumFractionDigits: scale.precision)
                XCTAssertEqual(Double(formatted) ?? .nan, tick, accuracy: 0.000001)
            }
        }
    }

    func testSavedAndAbnormalStatesSurviveDeviceDisconnect() {
        XCTAssertEqual(QNMeasurementUIState.resolve(sdkState: "初始化成功", bluetoothState: "开启", connectionState: "未连接", isScanning: false, deviceName: "QN-Scale", measurementState: "测量完成，已保存", weight: 84.2, operationError: nil), .completed)
        XCTAssertEqual(QNMeasurementUIState.resolve(sdkState: "初始化成功", bluetoothState: "开启", connectionState: "已连接", isScanning: false, deviceName: "QN-Scale", measurementState: "测量异常，已保存原始结果", weight: 84.2, operationError: nil), .abnormal("测量异常，已保存原始结果"))
    }

    func testHealthSyncSummaryDistinguishesNoChangesAndPartialErrors() {
        let date = Date(timeIntervalSince1970: 0)
        let noChanges = QNHealthKitSyncSummary(date: date, written: 0, imported: 0, outcome: .noChanges, errorMessage: nil)
        XCTAssertEqual(noChanges.resultText, "没有新增数据")
        let partial = QNHealthKitSyncSummary(date: date, written: 4, imported: 0, outcome: .partial, errorMessage: "导入失败")
        XCTAssertTrue(partial.resultText.contains("写入 4 项"))
        XCTAssertTrue(partial.resultText.contains("导入失败"))
        let failure = QNHealthKitSyncSummary(date: date, written: 0, imported: 0, outcome: .failed, errorMessage: "写入未授权")
        XCTAssertTrue(failure.resultText.contains("写入未授权"))
        XCTAssertNotEqual(failure.resultText, noChanges.resultText)
    }

    func testJSONExportsKeepRawItemsOriginalDataAndProfileSnapshot() throws {
        let repository = try QNMeasurementRepository(inMemory: true)
        let original = try fixture()
        let snapshot = try repository.save(measurement: original, profile: profile())
        for data in [try repository.export(snapshot), try repository.exportAll(profile: profile())] {
            let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let rows = try XCTUnwrap(payload["measurements"] as? [[String: Any]])
            XCTAssertEqual(rows.count, 1)
            let row = try XCTUnwrap(rows.first)
            let raw = try XCTUnwrap(row["rawQNData"] as? [String: Any])
            XCTAssertEqual(try JSONSerialization.data(withJSONObject: raw, options: .sortedKeys), try JSONSerialization.data(withJSONObject: original, options: .sortedKeys))
            XCTAssertEqual((row["rawItems"] as? [[String: Any]])?.count, 30)
            XCTAssertNotNil((row["profile"] as? [String: Any])?["birthday"])
            XCTAssertEqual((row["standardized"] as? [String: Double])?["weight"], 84.2)
            XCTAssertNotNil((raw["scaleData"] as? [String: Any])?["hmac"])
            XCTAssertNotNil((raw["scaleData"] as? [String: Any])?["resistance50"])
        }
    }

    private func measurement(date: String, weight: Double, identifier: String = "test-device") throws -> [String: Any] {
        var result = try fixture()
        var scaleData = try XCTUnwrap(result["scaleData"] as? [String: Any])
        scaleData["measureTime"] = date
        scaleData["hmac"] = "hmac-\(date)-\(identifier)"
        scaleData["weight"] = weight
        result["scaleData"] = scaleData
        var device = try XCTUnwrap(result["device"] as? [String: Any])
        device["deviceIdentifier"] = identifier
        result["device"] = device
        var items = try XCTUnwrap(result["items"] as? [[String: Any]])
        if let index = items.firstIndex(where: { ($0["type"] as? Int) == 1 }) { items[index]["value"] = weight }
        result["items"] = items
        return result
    }
}
