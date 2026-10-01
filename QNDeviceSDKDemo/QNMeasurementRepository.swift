import CoreData
import Foundation

struct QNMeasurementSnapshot: Identifiable {
    let id: UUID
    let deduplicationKey: String
    let measureTime: Date
    let createdAt: Date
    let updatedAt: Date
    let schemaVersion: Int
    let status: String
    let saveError: String?
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
    let sdkDeviceType: Int?
    let sdkVersion: String?
    let resistance50: Int?
    let resistance500: Int?
    let newEightModel: Int?
    let eightIsAbnormal: Int?
    let eightReasonMask: Int?
    let barCode: String?
    let heightMode: Int?
    let derivationVersion: String?
    let referenceRulesVersion: String?

    var weight: Double? { metrics["weight"] }
    var bmi: Double? { metrics["bmi"] }
    var bodyFatRate: Double? { metrics["bodyFatRate"] }
    var fatMass: Double? { metrics["fatMass"] }
    var subcutaneousFatRate: Double? { metrics["subcutaneousFatRate"] }
    var subcutaneousFatMass: Double? { metrics["subcutaneousFatMass"] }
    var visceralFat: Double? { metrics["visceralFat"] }
    var bodyWaterRate: Double? { metrics["bodyWaterRate"] }
    var waterContent: Double? { metrics["waterContent"] }
    var skeletalMuscleRate: Double? { metrics["skeletalMuscleRate"] }
    var muscleMassRate: Double? { metrics["muscleMassRate"] }
    var muscleMass: Double? { metrics["muscleMass"] }
    var skeletalMuscleMass: Double? { metrics["skeletalMuscleMass"] }
    var boneMass: Double? { metrics["boneMass"] }
    var boneMassPercentage: Double? { metrics["boneMassPercentage"] }
    var bmr: Double? { metrics["bmr"] }
    var proteinRate: Double? { metrics["proteinRate"] }
    var proteinMass: Double? { metrics["proteinMass"] }
    var leanBodyWeight: Double? { metrics["leanBodyWeight"] }
    var metabolicAge: Double? { metrics["metabolicAge"] }
    var healthScore: Double? { metrics["healthScore"] }
    var smi: Double? { metrics["smi"] }
    var waistHipRatio: Double? { metrics["waistHipRatio"] }
    var fattyLiverRisk: Int? { metrics["fattyLiverRisk"].map { Int($0) } }
    var mineralSaltRate: Double? { metrics["mineralSaltRate"] }
    var isAbnormal: Bool { (eightIsAbnormal ?? 0) != 0 }
    var displayDate: String { Self.dateFormatter.string(from: measureTime) }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年MM月dd日 HH:mm"
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
    static let jsonSchemaVersion = 2
    static let derivationVersion = "boneMassPercentage.v1"
    static let referenceRulesVersion = QNReferenceRangeService.version

    private let container: NSPersistentContainer
    private var context: NSManagedObjectContext!

    private static let metricKeys = [
        "weight", "bmi", "bodyFatRate", "healthScore", "fatMass", "subcutaneousFatRate", "subcutaneousFat", "subcutaneousFatMass", "visceralFat", "bodyWaterRate", "waterContent", "muscleRate", "skeletalMuscleRate", "muscleMass", "muscleMassRate", "skeletalMuscleMass", "boneMass", "boneMassPercentage", "bmr", "proteinRate", "proteinMass", "leanBodyWeight", "metabolicAge", "smi", "waistHipRatio", "fattyLiverRisk", "mineralSaltRate", "bodyType", "heartRate", "heartIndex", "obesityDegree", "mineralSalt", "bestVisualWeight", "standWeight", "weightControl", "fatControl", "muscleControl", "obesityLevel", "rightArmMuscleMass", "leftArmMuscleMass", "trunkMuscleMass", "rightLegMuscleMass", "leftLegMuscleMass", "rightArmFatMass", "leftArmFatMass", "trunkFatMass", "rightLegFatMass", "leftLegFatMass"
    ]

    init(inMemory: Bool = false, storeURL: URL? = nil) throws {
        let bundle = Bundle(for: MeasurementManagedObject.self)
        guard let modelURL = bundle.url(forResource: Self.modelName, withExtension: "momd") ?? Bundle.main.url(forResource: Self.modelName, withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            throw QNMeasurementRepositoryError.storeLoadFailed("Core Data 模型 QNScaleModel V2 不存在")
        }
        container = NSPersistentContainer(name: Self.modelName, managedObjectModel: model)
        let description = container.persistentStoreDescriptions.first ?? NSPersistentStoreDescription()
        if inMemory { description.url = URL(fileURLWithPath: "/dev/null") }
        if let storeURL { description.url = storeURL }
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)
        container.loadPersistentStores { _, error in loadError = error; semaphore.signal() }
        semaphore.wait()
        if let error = loadError { throw QNMeasurementRepositoryError.storeLoadFailed("数据库加载或迁移失败：\(error.localizedDescription)") }
        context = container.viewContext
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        context.automaticallyMergesChangesFromParent = true
        try migrateLegacyValuesIfNeeded()
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
                let mapped = try QNMeasurementMapper.map(measurement: measurement, profile: profile)
                let request = NSFetchRequest<NSManagedObject>(entityName: "Measurement")
                request.predicate = NSPredicate(format: "deduplicationKey == %@", mapped.deduplicationKey)
                request.fetchLimit = 1
                if let existing = try context.fetch(request).first {
                    result = .success(Self.snapshot(existing))
                    return
                }
                let object = NSEntityDescription.insertNewObject(forEntityName: "Measurement", into: context)
                let now = Date()
                object.setValue(UUID(), forKey: "id")
                object.setValue(mapped.deduplicationKey, forKey: "deduplicationKey")
                object.setValue(mapped.measureTime, forKey: "measureTime")
                object.setValue(Int64(Self.jsonSchemaVersion), forKey: "schemaVersion")
                object.setValue(now, forKey: "createdAt")
                object.setValue(now, forKey: "updatedAt")
                object.setValue(QNMeasurementMapper.string(mapped.user["userId"]) ?? profile.userId, forKey: "userId")
                object.setValue(QNMeasurementMapper.string(mapped.user["nickname"]) ?? profile.nickname, forKey: "nickname")
                object.setValue(QNMeasurementMapper.string(mapped.user["gender"]) ?? profile.gender, forKey: "gender")
                object.setValue(QNMeasurementMapper.date(mapped.user["birthday"]) ?? profile.birthday, forKey: "birthday")
                object.setValue(QNMeasurementMapper.double(mapped.user["height"]) ?? profile.height, forKey: "height")
                object.setValue(Int64(QNMeasurementMapper.int(mapped.user["athleteType"]) ?? profile.athleteType), forKey: "athleteType")
                object.setValue(profile.targetWeight, forKey: "targetWeight")
                object.setValue(QNMeasurementMapper.string(mapped.device["bluetoothName"]), forKey: "bluetoothName")
                object.setValue(QNMeasurementMapper.string(mapped.device["deviceIdentifier"]) ?? QNMeasurementMapper.string(mapped.device["sdkIdentifierMac"]), forKey: "deviceIdentifier")
                object.setValue(QNMeasurementMapper.string(mapped.device["modeId"]), forKey: "modeId")
                object.setValue(QNMeasurementMapper.int(mapped.device["deviceType"]).map { Int64($0) }, forKey: "sdkDeviceType")
                object.setValue(QNMeasurementMapper.string(mapped.metadata["sdkVersion"]), forKey: "sdkVersion")
                object.setValue(QNMeasurementMapper.int(mapped.scale["resistance50"]).map { Int64($0) }, forKey: "resistance50")
                object.setValue(QNMeasurementMapper.int(mapped.scale["resistance500"]).map { Int64($0) }, forKey: "resistance500")
                object.setValue(mapped.hmac, forKey: "hmac")
                object.setValue(QNMeasurementMapper.int(mapped.scale["newEightModel"]).map { Int64($0) }, forKey: "newEightModel")
                object.setValue(QNMeasurementMapper.int(mapped.scale["eightIsAbnormal"]).map { Int64($0) }, forKey: "eightIsAbnormal")
                object.setValue(QNMeasurementMapper.int(mapped.scale["eightReasonMask"]).map { Int64($0) }, forKey: "eightReasonMask")
                object.setValue(QNMeasurementMapper.string(mapped.scale["barCode"]), forKey: "barCode")
                object.setValue(QNMeasurementMapper.int(mapped.scale["heightMode"]).map { Int64($0) }, forKey: "heightMode")

                for (type, value) in mapped.valuesByType {
                    object.setValue(value, forKey: "type\(type)")
                    if let key = Self.standardKey(for: type) { object.setValue(value, forKey: key) }
                }
                object.setValue(mapped.boneMassPercentage, forKey: "boneMassPercentage")
                object.setValue(Self.derivationVersion, forKey: "derivationVersion")
                object.setValue(Self.referenceRulesVersion, forKey: "referenceRulesVersion")
                object.setValue((QNMeasurementMapper.int(mapped.scale["eightIsAbnormal"]) ?? 0) == 0 ? "normal" : "abnormal", forKey: "status")
                object.setValue(nil, forKey: "saveError")
                object.setValue(Self.jsonString(mapped.items), forKey: "rawItemsJSON")
                object.setValue(Self.jsonString(measurement), forKey: "rawMeasurementJSON")
                try context.save()
                result = .success(Self.snapshot(object))
            } catch let error as QNMeasurementRepositoryError {
                result = .failure(error)
            } catch { result = .failure(QNMeasurementRepositoryError.saveFailed("测量保存失败：\(error.localizedDescription)")) }
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

    func export(_ snapshot: QNMeasurementSnapshot) throws -> Data {
        let payload: [String: Any] = [
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "2.37.1",
            "schemaVersion": Self.jsonSchemaVersion,
            "exportedAt": QNMeasurementMapper.isoDate(Date()),
            "profile": Self.profileDictionary(snapshot),
            "measurements": [Self.exportDictionary(snapshot)]
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    func exportAll(profile: QNUserProfile?) throws -> Data {
        let snapshots = try fetchAll()
        let payload: [String: Any] = [
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "2.37.1",
            "schemaVersion": Self.jsonSchemaVersion,
            "exportedAt": QNMeasurementMapper.isoDate(Date()),
            "profile": profile.map { Self.profileDictionary($0) } ?? NSNull(),
            "measurements": snapshots.map(Self.exportDictionary)
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private func migrateLegacyValuesIfNeeded() throws {
        var migrationError: Error?
        context.performAndWait {
            do {
                let request = NSFetchRequest<NSManagedObject>(entityName: "Measurement")
                request.predicate = NSPredicate(format: "skeletalMuscleRate == nil AND muscleRate != nil")
                for object in try context.fetch(request) {
                    object.setValue(object.value(forKey: "muscleRate"), forKey: "skeletalMuscleRate")
                    object.setValue(Date(), forKey: "updatedAt")
                }
                if context.hasChanges { try context.save() }
            } catch { migrationError = error }
        }
        if let migrationError { throw QNMeasurementRepositoryError.storeLoadFailed("旧版肌肉率迁移失败：\(migrationError.localizedDescription)") }
    }

    private static func snapshot(_ object: NSManagedObject) -> QNMeasurementSnapshot {
        func d(_ key: String) -> Double? { (object.value(forKey: key) as? NSNumber)?.doubleValue }
        func i(_ key: String) -> Int? { (object.value(forKey: key) as? NSNumber)?.intValue }
        var metrics: [String: Double] = [:]
        for key in metricKeys { if let value = d(key) { metrics[key] = value } }
        for type in 101...122 { if let value = d("type\(type)") { metrics["type\(type)"] = value } }
        if let legacy = metrics["muscleRate"], metrics["skeletalMuscleRate"] == nil { metrics["skeletalMuscleRate"] = legacy }
        return QNMeasurementSnapshot(
            id: (object.value(forKey: "id") as? UUID) ?? UUID(),
            deduplicationKey: (object.value(forKey: "deduplicationKey") as? String) ?? "",
            measureTime: (object.value(forKey: "measureTime") as? Date) ?? .distantPast,
            createdAt: (object.value(forKey: "createdAt") as? Date) ?? .distantPast,
            updatedAt: (object.value(forKey: "updatedAt") as? Date) ?? .distantPast,
            schemaVersion: i("schemaVersion") ?? 1,
            status: (object.value(forKey: "status") as? String) ?? "normal",
            saveError: object.value(forKey: "saveError") as? String,
            userId: object.value(forKey: "userId") as? String,
            nickname: object.value(forKey: "nickname") as? String,
            gender: object.value(forKey: "gender") as? String,
            birthday: object.value(forKey: "birthday") as? Date,
            height: d("height"),
            athleteType: i("athleteType"),
            targetWeight: d("targetWeight"),
            metrics: metrics,
            rawItemsJSON: object.value(forKey: "rawItemsJSON") as? String,
            rawMeasurementJSON: object.value(forKey: "rawMeasurementJSON") as? String,
            hmac: object.value(forKey: "hmac") as? String,
            modeId: object.value(forKey: "modeId") as? String,
            deviceIdentifier: object.value(forKey: "deviceIdentifier") as? String,
            bluetoothName: object.value(forKey: "bluetoothName") as? String,
            sdkDeviceType: i("sdkDeviceType"),
            sdkVersion: object.value(forKey: "sdkVersion") as? String,
            resistance50: i("resistance50"),
            resistance500: i("resistance500"),
            newEightModel: i("newEightModel"),
            eightIsAbnormal: i("eightIsAbnormal"),
            eightReasonMask: i("eightReasonMask"),
            barCode: object.value(forKey: "barCode") as? String,
            heightMode: i("heightMode"),
            derivationVersion: object.value(forKey: "derivationVersion") as? String,
            referenceRulesVersion: object.value(forKey: "referenceRulesVersion") as? String
        )
    }

    private static func profileDictionary(_ profile: QNUserProfile) -> [String: Any] {
        ["userId": profile.userId, "nickname": profile.nickname, "gender": profile.gender, "birthday": QNMeasurementMapper.isoDate(profile.birthday), "height": profile.height, "athleteType": profile.athleteType, "targetWeight": profile.targetWeight ?? NSNull()]
    }

    private static func profileDictionary(_ snapshot: QNMeasurementSnapshot) -> [String: Any] {
        ["userId": snapshot.userId ?? NSNull(), "nickname": snapshot.nickname ?? NSNull(), "gender": snapshot.gender ?? NSNull(), "birthday": snapshot.birthday.map { QNMeasurementMapper.isoDate($0) } ?? NSNull(), "height": snapshot.height ?? NSNull(), "athleteType": snapshot.athleteType ?? NSNull(), "targetWeight": snapshot.targetWeight ?? NSNull()]
    }

    private static func exportDictionary(_ snapshot: QNMeasurementSnapshot) -> [String: Any] {
        let device: [String: Any] = ["bluetoothName": snapshot.bluetoothName ?? NSNull(), "deviceIdentifier": snapshot.deviceIdentifier ?? NSNull(), "modeId": snapshot.modeId ?? NSNull(), "sdkDeviceType": snapshot.sdkDeviceType ?? NSNull(), "sdkVersion": snapshot.sdkVersion ?? NSNull()]
        let rawItems: Any = snapshot.rawItemsJSON.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } ?? NSNull()
        let rawQNData: Any = snapshot.rawMeasurementJSON.flatMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) } ?? NSNull()
        let derivation: [String: Any] = ["boneMassPercentage": snapshot.boneMassPercentage ?? NSNull(), "version": snapshot.derivationVersion ?? NSNull(), "formula": "boneMass(type8) / weight(type1) * 100"]
        return [
            "id": snapshot.id.uuidString,
            "deduplicationKey": snapshot.deduplicationKey,
            "measureTime": QNMeasurementMapper.isoDate(snapshot.measureTime),
            "createdAt": QNMeasurementMapper.isoDate(snapshot.createdAt),
            "updatedAt": QNMeasurementMapper.isoDate(snapshot.updatedAt),
            "schemaVersion": snapshot.schemaVersion,
            "status": snapshot.status,
            "saveError": snapshot.saveError ?? NSNull(),
            "profile": profileDictionary(snapshot),
            "standardized": snapshot.metrics,
            "device": device,
            "referenceRulesVersion": snapshot.referenceRulesVersion ?? NSNull(),
            "derivation": derivation,
            "rawItems": rawItems,
            "rawQNData": rawQNData
        ]
    }

    private static func standardKey(for type: Int) -> String? {
        [1:"weight",2:"bmi",3:"bodyFatRate",4:"subcutaneousFatRate",5:"visceralFat",6:"bodyWaterRate",7:"skeletalMuscleRate",8:"boneMass",9:"bmr",10:"bodyType",11:"proteinRate",12:"leanBodyWeight",13:"muscleMass",14:"metabolicAge",15:"healthScore",16:"heartRate",17:"heartIndex",21:"fatMass",22:"obesityDegree",23:"waterContent",24:"proteinMass",25:"mineralSalt",26:"bestVisualWeight",27:"standWeight",28:"weightControl",29:"fatControl",30:"muscleControl",31:"muscleMassRate",32:"fattyLiverRisk",35:"subcutaneousFatMass",36:"smi",37:"waistHipRatio",38:"obesityLevel",101:"rightArmMuscleMass",102:"leftArmMuscleMass",103:"trunkMuscleMass",104:"rightLegMuscleMass",105:"leftLegMuscleMass",113:"rightArmFatMass",114:"leftArmFatMass",115:"trunkFatMass",116:"rightLegFatMass",117:"leftLegFatMass",111:"mineralSaltRate",112:"skeletalMuscleMass"][type]
    }

    private static func jsonString(_ value: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
