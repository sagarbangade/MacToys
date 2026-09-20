import AppKit
import Foundation

@MainActor
public final class PredictionEngine {
    public static let shared = PredictionEngine()

    private var bigrams: [String: [String: Int]] = [:]
    private var trigrams: [String: [String: Int]] = [:]
    private var previousWord: String?
    private var wordBeforePrevious: String?
    private var savePending = false

    // This compact bootstrap model makes useful suggestions before the user has
    // typed enough for the personal model to take over.
    private let commonFollowers: [String: [String]] = [
        "hi": ["there", "how", "everyone"],
        "hello": ["there", "everyone", "how"],
        "how": ["are", "do", "to", "much", "many", "long"],
        "are": ["you", "we", "they", "there"],
        "i": ["am", "think", "have", "will", "would", "need", "can", "want"],
        "i'm": ["going", "not", "sorry", "sure", "happy"],
        "the": ["best", "most", "first", "next", "same", "only"],
        "thank": ["you"], "thanks": ["for", "again"], "looking": ["forward"],
        "forward": ["to"], "have": ["a", "been", "to", "you"],
        "can": ["you", "we", "i"], "would": ["you", "be", "like"],
        "could": ["you", "be", "we"], "should": ["be", "we", "i"],
        "will": ["be", "you", "have"], "it": ["is", "was", "will", "would"],
        "this": ["is", "was", "will"], "that": ["is", "was", "would"],
        "what": ["is", "are", "do", "about"], "do": ["you", "we", "not"],
        "is": ["a", "the", "not", "there", "it"], "we": ["can", "should", "will", "need"],
        "please": ["let", "send", "check", "find"], "let": ["me", "us"],
        "me": ["know"], "good": ["morning", "afternoon", "evening", "job"],
        "nice": ["to", "work", "meeting"], "see": ["you", "the", "if"],
        "sounds": ["good", "great", "like"], "hope": ["you", "this", "that"],
        "need": ["to", "a", "your", "help"], "want": ["to", "a"],
        "like": ["to", "a", "this", "that"], "going": ["to"],
        "to": ["be", "the", "do", "get", "have", "make"], "in": ["the", "a", "this", "my"],
        "on": ["the", "my", "this"], "for": ["the", "a", "this", "your", "you"],
        "with": ["the", "a", "this", "my"], "and": ["the", "i", "it", "we"],
        "but": ["i", "it", "the", "we"], "so": ["i", "that", "we", "much"],
        "if": ["you", "we", "the", "it"], "just": ["a", "wanted", "let"],
        "wanted": ["to"], "get": ["back", "a", "the", "it"], "back": ["to"],
        "sorry": ["for", "about", "to"], "no": ["problem", "worries"]
    ]

    private init() { loadCache() }

    public func recordWord(_ word: String) {
        let cleaned = normalize(word)
        guard !cleaned.isEmpty else { return }
        if let previousWord {
            bigrams[previousWord, default: [:]][cleaned, default: 0] += 1
            if let wordBeforePrevious {
                let context = "\(wordBeforePrevious)\u{1F}\(previousWord)"
                trigrams[context, default: [:]][cleaned, default: 0] += 1
            }
            saveCacheDebounced()
        }
        wordBeforePrevious = previousWord
        previousWord = cleaned
    }

    /// Returns ordered candidates for either a word prefix or the next word.
    public func suggestions(after contextWord: String?, partialWord: String) -> [String] {
        let partial = normalize(partialWord)
        let context = contextWord.map(normalize)
        var ranked: [String] = []

        func append(_ candidate: String) {
            let normalized = normalize(candidate)
            guard !normalized.isEmpty,
                  (partial.isEmpty || normalized.hasPrefix(partial)),
                  !ranked.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) else { return }
            ranked.append(normalized)
        }

        // A personal two-word phrase is more relevant than a generic transition.
        if let context, context == previousWord, let wordBeforePrevious,
           let learned = trigrams["\(wordBeforePrevious)\u{1F}\(context)"] {
            learned.sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }.forEach { append($0.key) }
        }

        // A personal one-word transition is the next strongest signal.
        if let context, let learned = bigrams[context] {
            learned.sorted { lhs, rhs in
                lhs.value == rhs.value ? lhs.key < rhs.key : lhs.value > rhs.value
            }.forEach { append($0.key) }
        }
        if let context { commonFollowers[context, default: []].forEach(append) }

        // macOS supplies a broad, language-aware completion vocabulary without
        // shipping a huge static word list or sending typed text off-device.
        if !partial.isEmpty {
            let spellChecker = NSSpellChecker.shared
            let range = NSRange(location: 0, length: (partial as NSString).length)
            spellChecker.completions(
                forPartialWordRange: range,
                in: partial,
                language: "en_US",
                inSpellDocumentWithTag: 0
            )?.forEach(append)
        }

        return Array(ranked.prefix(5))
    }

    private func normalize(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    private func saveCacheDebounced() {
        guard !savePending else { return }
        savePending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.saveCache()
            self?.savePending = false
        }
    }

    private func saveCache() {
        UserDefaults.standard.set(bigrams, forKey: "TypingAssist_Bigrams")
        UserDefaults.standard.set(trigrams, forKey: "TypingAssist_Trigrams")
    }

    private func loadCache() {
        if let saved = UserDefaults.standard.dictionary(forKey: "TypingAssist_Bigrams") as? [String: [String: Int]] {
            bigrams = saved
        }
        if let saved = UserDefaults.standard.dictionary(forKey: "TypingAssist_Trigrams") as? [String: [String: Int]] {
            trigrams = saved
        }
    }
}
