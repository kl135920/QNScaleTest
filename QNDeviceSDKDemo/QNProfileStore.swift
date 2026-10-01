import Foundation

final class QNProfileStore {
    private let key = "QNScaleTest.profile.v2"

    func load() -> QNUserProfile? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(QNUserProfile.self, from: data)
    }

    func save(_ profile: QNUserProfile) throws {
        UserDefaults.standard.set(try JSONEncoder().encode(profile), forKey: key)
    }
}
