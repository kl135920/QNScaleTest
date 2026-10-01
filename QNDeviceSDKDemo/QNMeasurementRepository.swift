import CoreData
import Foundation

struct QNMeasurementSnapshot: Identifiable {
    let id: UUID
    let measureTime: Date
    let createdAt: Date
    let status: String
    let userId: String?
    let nickname: String?
    let gender: String?
    let birthday: Date?
    let height: Double?
    let athleteType: Int?
    let targetWeight: Double?
    let metrics: [String: Double]
    let rawItemsJSON: String?
    let rawMeasurementJSON: String?
    let hmac: String?
    let modeId: String?
    let deviceIdentifier: String?
    let bluetoothName: String?
    let sdkVersion: String?
    let resistance50: Int?
    let resistance500: Int?
    let newEightModel: Int?
    let eightIsAbnormal: Int?
    let eightReasonMask: Int?

    var weight: Double? { metrics["weight"] }
    var bodyFatRate: Double? { metrics["bodyFatRate"] }
    var muscleMass: Double? { metrics["muscleMass"] }
    var skeletalMuscleMass: Double? { metrics["skeletalMuscleMass"] }
    var bmi: Double? { metrics["bmi"] }
    var isAbnormal: Bool { (eightIsAbnormal ?? 0) != 0 }
    var displayDate: String { Self.dateFormatter.string(from: measureTime) }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM月dd日 HH:mm"
        return formatter
    }()
}

enum QNMeasurementRepositoryError: LocalizedError {
    case storeLoadFailed(String)
    case invalidMeasurement(String)
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .storeLoadFailed(let message), .invalidMeasurement(let message), .saveFailed(let message): return message
        }
    }
}

final class QNMeasurementRepository {
    static let modelName = "QNScaleModel"
    static let jsonSchemaVersion = 1
    private let container: NSPersistentContainer
    private var context: NSManagedObjectContext!

    init(inMemory: Bool = false) throws {
        guard let modelURL = Bundle.main.url(forResource: Self.modelName, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw QNMeasurementRepositoryError.storeLoadFailed("Core Data 模型 QNScaleModel V1 不存在")
        }
        container = NSPersistentContainer(name: Self.modelName, managedObjectModel: model)
        let description = container.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()
        if inMemory { description.url = URL(fileURLWithPath: "/dev/null") }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in loadError = error; semaphore.signal() }
        semaphore.wait()
        if let error = loadError { throw QNMeasurementRepositoryError.storeLoadFailed("数据库加载或轻量迁移失败：\(error.localizedDescription)") }
        context = container.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
    }

    func fetchAll() throws -> [QNMeasurementSnapshot] {
        var result: Result<[QNMeasurementSnapshot], Error>!
        context.performAndWait {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: "Measurement")
                request.sortDescriptors = [NSSortDescriptor(key: "measureTime", ascending: false)]
                result = .success(try context.fetch(request).map(Self.snapshot))
            } catch { result = .failure(error) }
        }
        return try result.get()
    }

    @discardableResult
    func save(measurement: [String: Any], profile: QNUserProfile) throws -> QNMeasurementSnapshot {
        var result: Result<QNMeasurementSnapshot, Error>!
        context.performAndWait {
            do {
                guard let scale = measurement["scaleData"] as? [String: Any],
                      let device = measurement["device"] as? [String: Any],
                      let user = measurement["user"] as? [String: Any],
                      let measureTime = Self.date(from: scale["measureTime"]) else {
                    throw QNMeasurementRepositoryError.invalidMeasurement("QNScaleData 缺少 scaleData、device、user 或 measureTime")
                }
                let hmac = Self.string(scale["hmac"])
                let deviceIdentifier = Self.string(device["deviceIdentifier"]) ?? "unknown-device"
                let userId = Self.string(user["userId"]) ?? profile.userId
                let deduplicationKey = "\(userId)|\(deviceIdentifier)|\(hmac ?? Self.isoDate(measureTime))"
                let request = NSFetchRequest<NSManagedObject>(entityName: "Measurement")
                request.predicate = NSPredicate(format: "deduplicationKey == %@", deduplicationKey)
                request.fetchLimit = 1
                if let existing = try context.fetch(request).first {
                    result = .success(Self.snapshot(existing))
                    return
                }
                let object = NSEntityDescription.insertNewObject(forEntityName: "Measurement", into: context)
                let now = Date()
                object.setValue(UUID(), forKey: "id")
                object.setValue(deduplicationKey, forKey: "deduplicationKey")
                object.setValue(measureTime, forKey: "measureTime")
                object.setValue(Int64(Self.jsonSchemaVersion), forKey: "schemaVersion")
                object.setValue(now, forKey: "createdAt")
                object.setValue(now, forKey: "updatedAt")
                object.setValue(userId, forKey: "userId")
                object.setValue(Self.string(user["nickname"]) ?? profile.nickname, forKey: "nickname")
                object.setValue(Self.string(user["gender"]) ?? profile.gender, forKey: "gender")
                object.setValue(Self.date(from: user["birthday"]) ?? profile.birthday, forKey: "birthday")
                object.setValue(Self.double(user["height"]) ?? profile.height, forKey: "height")
                object.setValue(Int64(Self.int(user["athleteType"]) ?? profile.athleteType), forKey: "athleteType")
                object.setValue(profile.targetWeight, forKey: "targetWeight")
                object.setValue(Self.string(device["bluetoothName"]), forKey: "bluetoothName")
                object.setValue(deviceIdentifier, forKey: "deviceIdentifier")
                object.setValue(Self.string(device["modeId"]), forKey: "modeId")
                object.setValue(Self.int(device["deviceType"]).map { Int64($0) }, forKey: "sdkDeviceType")
                object.setValue(Self.string(measurement["metadata"].flatMap { ($0 as? [String: Any])?["sdkVersion"] }), forKey: "sdkVersion")
                object.setValue(Self.int(scale["resistance50"]).map { Int64($0) }, forKey: "resistance50")
                object.setValue(Self.int(scale["resistance500"]).map { Int64($0) }, forKey: "resistance500")
                object.setValue(hmac, forKey: "hmac")
                object.setValue(Self.int(scale["newEightModel"]).map { Int64($0) }, forKey: "newEightModel")
                object.setValue(Self.int(scale["eightIsAbnormal"]).map { Int64($0) }, forKey: "eightIsAbnormal")
                object.setValue(Self.int(scale["eightReasonMask"]).map { Int64($0) }, forKey: "eightReasonMask")
                let items = measurement["items"] as? [[String: Any]] ?? []
                for item in items {
                    guard let type = Self.int(item["type"]), let value = Self.double(item["value"]) else { continue }
                    object.setValue(value, forKey: "type\(type)")
                    if let key = Self.standardKey(for: type) { object.setValue(value, forKey: key) }
                }
                object.setValue((Self.int(scale["eightIsAbnormal"]) ?? 0) == 0 ? "normal" : "abnormal", forKey: "status")
                object.setValue(Self.jsonString(items), forKey: "rawItemsJSON")
                object.setValue(Self.jsonString(measurement), forKey: "rawMeasurementJSON")
                try context.save()
                result = .success(Self.snapshot(object))
            } catch let error as QNMeasurementRepositoryError {
                result = .failure(error)
            } catch {
                result = .failure(QNMeasurementRepositoryError.saveFailed("测量保存失败：\(error.localizedDescription)"))
            }
        }
        return try result.get()
    }

    func delete(_ snapshot: QNMeasurementSnapshot) throws {
        var result: Result<Void, Error>!
        context.performAndWait {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: "Measurement")
                request.predicate = NSPredicate(format: "id == %@", snapshot.id as CVarArg)
                if let object = try context.fetch(request).first { context.delete(object); try context.save() }
                result = .success(())
            } catch { result = .failure(error) }
        }
        try result.get()
    }

    func exportAll(profile: QNUserProfile?) throws -> Data {
        let snapshots = try fetchAll()
        let payload: [String: Any] = [
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "2.37.1",
            "schemaVersion": Self.jsonSchemaVersion,
            "exportedAt": Self.isoDate(Date()),
            "profile": profile.map { ["userId": $0.userId, "nickname": $0.nickname, "gender": $0.gender, "birthday": Self.isoDate($0.birthday), "height": $0.height, "athleteType": $0.athleteType, "targetWeight": $0.targetWeight ?? NSNull()] } ?? NSNull(),
            "measurements": snapshots.map(Self.exportDictionary)
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private static func snapshot(_ object: NSManagedObject) -> QNMeasurementSnapshot {
        func d(_ key: String) -> Double? { (object.value(forKey: key) as? NSNumber)?.doubleValue }
        func i(_ key: String) -> Int? { (object.value(forKey: key) as? NSNumber)?.intValue }
        var metrics: [String: Double] = [:]
        let keys = ["weight", "bmi", "bodyFatRate", "fatMass", "subcutaneousFat", "visceralFat", "bodyWaterRate", "waterContent", "muscleRate", "muscleMass", "muscleMassRate", "skeletalMuscleMass", "boneMass", "bmr", "proteinRate", "proteinMass", "leanBodyWeight", "metabolicAge", "smi", "waistHipRatio", "rightArmMuscleMass", "leftArmMuscleMass", "trunkMuscleMass", "rightLegMuscleMass", "leftLegMuscleMass", "rightArmFatMass", "leftArmFatMass", "trunkFatMass", "rightLegFatMass", "leftLegFatMass"] + (101...122).map { "type\($0)" }
        for key in keys { if let value = d(key) { metrics[key] = value } }
        return QNMeasurementSnapshot(id: (object.value(forKey: "id") as? UUID) ?? UUID(), measureTime: (object.value(forKey: "measureTime") as? Date) ?? .distantPast, createdAt: (object.value(forKey: "createdAt") as? Date) ?? .distantPast, status: (object.value(forKey: "status") as? String) ?? "normal", userId: object.value(forKey: "userId") as? String, nickname: object.value(forKey: "nickname") as? String, gender: object.value(forKey: "gender") as? String, birthday: object.value(forKey: "birthday") as? Date, height: d("height"), athleteType: i("athleteType"), targetWeight: d("targetWeight"), metrics: metrics, rawItemsJSON: object.value(forKey: "rawItemsJSON") as? String, rawMeasurementJSON: object.value(forKey: "rawMeasurementJSON") as? String, hmac: object.value(forKey: "hmac") as? String, modeId: object.value(forKey: "modeId") as? String, deviceIdentifier: object.value(forKey: "deviceIdentifier") as? String, bluetoothName: object.value(forKey: "bluetoothName") as? String, sdkVersion: object.value(forKey: "sdkVersion") as? String, resistance50: i("resistance50"), resistance500: i("resistance500"), newEightModel: i("newEightModel"), eightIsAbnormal: i("eightIsAbnormal"), eightReasonMask: i("eightReasonMask"))
    }

    private static func exportDictionary(_ snapshot: QNMeasurementSnapshot) -> [String: Any] {
        let user: [String: Any] = [
            "userId": snapshot.userId ?? NSNull(),
            "nickname": snapshot.nickname ?? NSNull(),
            "gender": snapshot.gender ?? NSNull(),
            "birthday": snapshot.birthday.map { isoDate($0) } ?? NSNull(),
            "height": snapshot.height ?? NSNull(),
            "athleteType": snapshot.athleteType ?? NSNull()
        ]
        let device: [String: Any] = [
            "bluetoothName": snapshot.bluetoothName ?? NSNull(),
            "deviceIdentifier": snapshot.deviceIdentifier ?? NSNull(),
            "modeId": snapshot.modeId ?? NSNull(),
            "sdkVersion": snapshot.sdkVersion ?? NSNull()
        ]
        let rawItems: Any = snapshot.rawItemsJSON.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } ?? NSNull()
        let rawQNData: Any = snapshot.rawMeasurementJSON.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } ?? NSNull()
        return ["id": snapshot.id.uuidString, "measureTime": isoDate(snapshot.measureTime), "status": snapshot.status, "user": user, "standardized": snapshot.metrics, "device": device, "rawItems": rawItems, "rawQNData": rawQNData]
    }
    private static func standardKey(for type: Int) -> String? { [2:"bmi",3:"bodyFatRate",4:"subcutaneousFat",5:"visceralFat",6:"bodyWaterRate",7:"muscleRate",8:"boneMass",9:"bmr",11:"proteinRate",12:"leanBodyWeight",13:"muscleMass",14:"metabolicAge",21:"fatMass",23:"waterContent",24:"proteinMass",31:"muscleMassRate",36:"smi",37:"waistHipRatio",101:"rightArmMuscleMass",102:"leftArmMuscleMass",103:"trunkMuscleMass",104:"rightLegMuscleMass",105:"leftLegMuscleMass",113:"rightArmFatMass",114:"leftArmFatMass",115:"trunkFatMass",116:"rightLegFatMass",117:"leftLegFatMass"][type] }
    private static func string(_ value: Any?) -> String? { if let value = value as? String { return value }; return nil }
    private static func double(_ value: Any?) -> Double? { if let value = value as? NSNumber { return value.doubleValue }; if let value = value as? Double { return value }; return nil }
    private static func int(_ value: Any?) -> Int? { if let value = value as? NSNumber { return value.intValue }; if let value = value as? Int { return value }; return nil }
    private static func date(from value: Any?) -> Date? { guard let string = value as? String else { return nil }; return ISO8601DateFormatter().date(from: string) ?? { let f=DateFormatter(); f.locale=Locale(identifier:"en_US_POSIX"); f.dateFormat="yyyy-MM-dd"; return f.date(from:string) }() }
    private static func isoDate(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
    private static func jsonString(_ value: Any) -> String? { guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return nil }; return String(data: data, encoding: .utf8) }
}
