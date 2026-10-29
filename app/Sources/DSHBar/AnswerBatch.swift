import Foundation

/// Pure builder for the DSH answer batch. Kept out of the view controller so
/// the tricky rules (custom replaces single-select, multi-select keeps labels)
/// are unit-testable without AppKit.
enum AnswerBatch {
    struct Choice {
        var selected: [String]
        var custom: String
    }

    static func build(_ group: BarQuestionGroup, choices: [Choice]) -> [[String: Any]] {
        group.questions.enumerated().map { index, question in
            let choice = index < choices.count ? choices[index] : Choice(selected: [], custom: "")
            let custom = choice.custom.trimmingCharacters(in: .whitespacesAndNewlines)
            let effective = (question.multiSelect == true || custom.isEmpty) ? choice.selected : []
            var answer: [String: Any] = ["id": question.id, "selected": effective]
            if !custom.isEmpty { answer["custom"] = custom }
            return answer
        }
    }
}
