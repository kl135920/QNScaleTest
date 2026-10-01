import Foundation

protocol QNHealthKitServiceProtocol {
    func requestAuthorization() async -> Result<Void, Error>
    func writeWeight(_ value: Double, date: Date) async -> Result<Void, Error>
}

final class QNHealthKitService: QNHealthKitServiceProtocol {
    enum PlaceholderError: LocalizedError {
        case notImplemented
        var errorDescription: String? { "HealthKit 接口已预留，本版本不请求权限、不写入 Apple 健康" }
    }

    func requestAuthorization() async -> Result<Void, Error> { .failure(PlaceholderError.notImplemented) }
    func writeWeight(_ value: Double, date: Date) async -> Result<Void, Error> { .failure(PlaceholderError.notImplemented) }
}
