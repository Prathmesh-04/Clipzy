import Foundation

struct Project: Identifiable, Equatable {
    let id: String
    let name: String
    let status: String
    let createdAt: String
}

struct ChatMessage {
    let role: String
    let text: String
    var toolNames: [String] = []
}

struct BrainstormResult {
    let reply: String
    let finalPrompt: String?
}

struct StyleHabit: Hashable {
    let label: String
    let share: Double
    let instruction: String
}

struct StylePromptResult {
    let prompt: String?
    let note: String
    let habits: [StyleHabit]
}

struct Render: Identifiable, Equatable {
    let id: String
    let profile: String
    let status: String
    let createdAt: String
    let url: String?
    var credits: [String] = []
}

struct SourceVideo {
    let url: String
    let width: Int?
    let height: Int?
    let durationS: Double?
}

struct Word: Identifiable, Hashable {
    let id: String
    let text: String
    let start: Double
}

struct TimelineInfo {
    let version: Int
    let summary: String
    let words: [Word]
}

struct PlanMoment: Hashable {
    let atWord: String
    let show: String
}

struct EditPlan {
    let summary: String
    let steps: [String]
    let moments: [PlanMoment]
    let musicMood: String?
    let transition: String?
}

enum FeedItem: Identifiable {
    case message(id: String, role: String, text: String, toolBadges: [String] = [], isError: Bool = false)
    case finalPrompt(id: String, prompt: String)
    case style(id: String, note: String, prompt: String?, habits: [StyleHabit], submitted: Bool = false)
    case plan(id: String, plan: EditPlan)
    case toolStep(id: String, toolCallId: String, name: String, argsText: String, status: String, resultText: String? = nil)
    case ask(id: String, question: String, options: [String], selectedOption: String? = nil)
    case critic(id: String, score: String, issues: [String])
    case credits(id: String, credits: [String])

    var id: String {
        switch self {
        case .message(let id, _, _, _, _), .finalPrompt(let id, _), .style(let id, _, _, _, _),
             .plan(let id, _), .toolStep(let id, _, _, _, _, _), .ask(let id, _, _, _),
             .critic(let id, _, _), .credits(let id, _):
            return id
        }
    }

    static func newId() -> String { UUID().uuidString }
}
