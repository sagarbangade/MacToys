import AppKit
import Foundation

/// Local first-pass writing checks. This deliberately only emits high-confidence
/// changes: it must never silently rewrite a user's text in another application.
@MainActor
final class WritingQualityEngine {
    static let shared = WritingQualityEngine()

    private let grammarReplacements = [
        "dont": "don't", "cant": "can't", "wont": "won't", "shouldnt": "shouldn't",
        "couldnt": "couldn't", "wouldnt": "wouldn't", "im": "I'm", "ive": "I've",
        "youre": "you're", "theyre": "they're", "weve": "we've", "thats": "that's"
    ]

    private init() {}

    func correction(for word: String) -> String? {
        let trimmed = word.trimmingCharacters(in: .punctuationCharacters)
        guard trimmed.count > 1 else { return nil }
        if let grammarReplacement = grammarReplacements[trimmed.lowercased()] {
            return grammarReplacement
        }

        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(
            of: trimmed,
            startingAt: 0,
            language: "en_US",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        guard range.location != NSNotFound,
              let guess = checker.guesses(forWordRange: range, in: trimmed, language: "en_US", inSpellDocumentWithTag: 0)?.first,
              guess.caseInsensitiveCompare(trimmed) != ComparisonResult.orderedSame else {
            return nil
        }
        return guess
    }
}
