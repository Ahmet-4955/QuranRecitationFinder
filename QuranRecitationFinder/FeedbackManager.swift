import Foundation

final class FeedbackManager {
    static let shared = FeedbackManager()

    private let storageKey = "QuranRecitationFinder.FeedbackScores"
    private var scores: [String: Int] = [:]

    private init() {
        loadFeedback()
    }

    func recordFeedback(for verse: QuranVerse, isCorrect: Bool) {
        let current = scores[verse.id] ?? 0
        let delta = isCorrect ? 1 : -1
        let next = min(max(current + delta, -3), 5)
        scores[verse.id] = next
        saveFeedback()
    }

    func confidenceBonus(for verse: QuranVerse) -> Int {
        let current = scores[verse.id] ?? 0
        return current * 8
    }

    func feedbackLabel(for verse: QuranVerse) -> String? {
        guard let score = scores[verse.id], score != 0 else {
            return nil
        }
        if score > 0 {
            return "Feedback: +\(score)"
        }
        return "Feedback: \(score)"
    }

    private func loadFeedback() {
        let defaults = UserDefaults.standard
        if let stored = defaults.dictionary(forKey: storageKey) as? [String: Int] {
            scores = stored
        }
    }

    private func saveFeedback() {
        let defaults = UserDefaults.standard
        defaults.set(scores, forKey: storageKey)
    }
}
