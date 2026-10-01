import AppIntents
import ActivityKit
import Foundation

struct SessionAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var started: Date
        var todaySeconds: Int
    }
    var id: String
    var day: String
}

enum SessionStorage {
    static let group = "group.com.frekihub.frekiHub"
    static var defaults: UserDefaults { UserDefaults(suiteName: group)! }
}

@available(iOS 17.0, *)
struct ClockOutIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Clock out"
    static var openAppWhenRun: Bool = false
    @Parameter(title: "Session") var sessionId: String
    init() {}
    init(id: String) { sessionId = id }
    func perform() async throws -> some IntentResult {
        SessionStorage.defaults.set(sessionId, forKey: "pendingId")
        SessionStorage.defaults.set(Int64(Date().timeIntervalSince1970 * 1000), forKey: "pendingEnd")
        SessionStorage.defaults.synchronize()
        for activity in Activity<SessionAttributes>.activities where activity.attributes.id == sessionId {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        return .result()
    }
}

