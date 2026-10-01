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
}
