import Foundation

struct QNUserProfile: Codable, Equatable {
    var userId: String
    var nickname: String
    var gender: String
    var birthday: Date
    var height: Double
    var athleteType: Int
    var targetWeight: Double?

    var isValid: Bool {
        let age = Calendar.current.dateComponents([.year], from: birthday, to: Date()).year ?? 0
        return !userId.isEmpty && !nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (gender == "male" || gender == "female") && height >= 50 && height <= 250 && age >= 3 && age <= 80
    }

    var genderText: String { gender == "female" ? "女" : "男" }
    var athleteText: String { athleteType == 1 ? "运动员模式" : "普通模式" }
}
