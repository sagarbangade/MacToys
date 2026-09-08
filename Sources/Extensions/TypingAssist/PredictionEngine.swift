import Foundation

@MainActor
public final class PredictionEngine {
    public static let shared = PredictionEngine()

    private var bigrams: [String: [String: Int]] = [:]
    private var trigrams: [String: [String: Int]] = [:]
    private var previousWord: String?
    private var wordBeforePrevious: String?
    private var savePending = false
    private let maximumContexts = 5_000
    private let maximumCandidatesPerContext = 16

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

    // A deliberately bounded local lexicon keeps prefix completion off the
    // spell server's synchronous path. It is fast enough to run on every idle
    // keystroke and covers the common words not present in a user's history.
    private let commonWords = [
        "about", "above", "accept", "across", "actually", "after", "again", "against", "almost", "already",
        "also", "always", "another", "anything", "around", "because", "before", "being", "between", "better",
        "both", "bring", "build", "business", "called", "change", "check", "come", "common", "complete",
        "could", "create", "current", "different", "does", "doing", "done", "each", "early", "enough",
        "every", "everything", "example", "first", "follow", "from", "general", "getting", "give", "going",
        "great", "help", "hello", "here", "however", "important", "include", "into", "issue", "just",
        "keep", "know", "later", "like", "little", "look", "make", "many", "might", "more", "most",
        "much", "need", "never", "next", "nothing", "only", "other", "people", "place", "please",
        "possible", "problem", "really", "right", "should", "simple", "some", "someone", "something", "still",
        "such", "system", "take", "tell", "than", "thank", "their", "there", "these", "thing", "think",
        "this", "those", "through", "today", "together", "try", "under", "use", "user", "very", "want",
        "well", "were", "what", "when", "where", "which", "while", "will", "with", "without", "work",
        "would", "write", "year", "yes", "your"
    ]

    private init() { loadCache() }

    public func recordWord(_ word: String) {
        let cleaned = normalize(word)
        guard !cleaned.isEmpty else { return }
        if let previousWord {
            bigrams[previousWord, default: [:]][cleaned, default: 0] += 1
            trimCandidates(for: previousWord, in: &bigrams)
            if let wordBeforePrevious {
                let context = "\(wordBeforePrevious)\u{1F}\(previousWord)"
                trigrams[context, default: [:]][cleaned, default: 0] += 1
                trimCandidates(for: context, in: &trigrams)
            }
            saveCacheDebounced()
        }
        if bigrams.count > maximumContexts { bigrams.removeValue(forKey: previousWord ?? cleaned) }
        if trigrams.count > maximumContexts { trigrams.removeValue(forKey: "\(wordBeforePrevious ?? cleaned)\u{1F}\(previousWord ?? cleaned)") }
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

        if !partial.isEmpty {
            commonFollowers.keys.forEach(append)
            commonFollowers.values.flatMap { $0 }.forEach(append)
            commonWords.forEach(append)
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
        let bigramSnapshot = bigrams
        let trigramSnapshot = trigrams
        DispatchQueue.global(qos: .utility).async {
            UserDefaults.standard.set(bigramSnapshot, forKey: "TypingAssist_Bigrams")
            UserDefaults.standard.set(trigramSnapshot, forKey: "TypingAssist_Trigrams")
        }
    }

    private func loadCache() {
        if let saved = UserDefaults.standard.dictionary(forKey: "TypingAssist_Bigrams") as? [String: [String: Int]] {
            bigrams = Dictionary(uniqueKeysWithValues: saved.prefix(maximumContexts).map { ($0.key, $0.value) })
        }
        if let saved = UserDefaults.standard.dictionary(forKey: "TypingAssist_Trigrams") as? [String: [String: Int]] {
            trigrams = Dictionary(uniqueKeysWithValues: saved.prefix(maximumContexts).map { ($0.key, $0.value) })
        }
    }

    private func trimCandidates(for context: String, in model: inout [String: [String: Int]]) {
        guard let candidates = model[context], candidates.count > maximumCandidatesPerContext else { return }
        model[context] = Dictionary(uniqueKeysWithValues:
            candidates.sorted { lhs, rhs in lhs.value > rhs.value }
                .prefix(maximumCandidatesPerContext)
                .map { ($0.key, $0.value) }
        )
    }
}
