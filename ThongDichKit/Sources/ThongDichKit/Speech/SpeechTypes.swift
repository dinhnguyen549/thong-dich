import Foundation
import NaturalLanguage

/// What a speech engine reports.
enum SpeechEvent: Sendable {
    /// Text still being spoken (may change). Shown dimmed under the transcript.
    case partial(String)
    /// A finished phrase. `start` is seconds since the session/file began.
    case final(text: String, language: SpokenLanguage, start: TimeInterval)
}

/// Settings that shape how speech is cut into phrases.
struct SegmentationTuning: Sendable {
    var vadThreshold: Float          // Silero speech probability needed to start speech
    var minSilence: TimeInterval     // pause that ends a phrase
    var maxSegment: TimeInterval     // force a cut (recognizer window is 15 s)
    var preRoll: TimeInterval        // audio kept before speech starts (no clipped first word)
    var partialEvery: TimeInterval   // how often to refresh live (partial) text; 0 = never
    var minSegment: TimeInterval     // ignore blips shorter than this

    /// People close to the phone: react quickly at short pauses.
    static let conversation = SegmentationTuning(
        vadThreshold: 0.6, minSilence: 0.55, maxSegment: 10, preRoll: 0.3, partialEvery: 0.9, minSegment: 0.25)

    /// Loudspeaker in a church/hall: distant speech scores lower on the detector, and echo
    /// fills short pauses, so use a lower threshold and wait longer before cutting.
    static let loudspeaker = SegmentationTuning(
        vadThreshold: 0.45, minSilence: 0.9, maxSegment: 13, preRoll: 0.4, partialEvery: 1.1, minSegment: 0.35)

    static func offline(_ base: SegmentationTuning) -> SegmentationTuning {
        var t = base
        t.partialEvery = 0
        return t
    }
}

// MARK: - Text helpers

enum TextTools {
    /// Decides English vs Spanish from the words themselves. Short or ambiguous text keeps the previous language.
    static func detectLanguage(_ text: String, previous: SpokenLanguage?) -> SpokenLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = [.english, .spanish]
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        let en = hypotheses[.english] ?? 0
        let es = hypotheses[.spanish] ?? 0
        let words = text.split(separator: " ").count
        if let previous, words < 3 || abs(en - es) < 0.35 { return previous }
        // Spanish punctuation / letters are a strong hint
        if text.contains("¿") || text.contains("¡") || text.contains("ñ") { return .spanish }
        return es > en ? .spanish : .english
    }

    /// Fillers and noise words that are not worth translating.
    static func isFiller(_ text: String) -> Bool {
        let t = normalize(text)
        if t.isEmpty { return true }
        let fillers: Set<String> = ["uh", "um", "hmm", "mm", "mhm", "ah", "eh", "oh", "uh huh", "este", "eh eh", "mmm", "hm"]
        return fillers.contains(t)
    }

    /// Removes words that echo made the recognizer hear twice, e.g. "the Lord the Lord be with you".
    /// Only collapses a phrase repeated back-to-back with no punctuation between the copies,
    /// so real repetitions like "Holy, Holy, Holy" or "Lord, have mercy. Lord, have mercy." stay.
    static func removeEchoRepeats(_ text: String) -> String {
        var words = text.split(separator: " ").map(String.init)
        guard words.count >= 4 else { return text }
        func key(_ w: String) -> String { w.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        var changed = true
        while changed {
            changed = false
            outer: for n in stride(from: 4, through: 2, by: -1) {
                guard words.count >= 2 * n else { continue }
                var i = 0
                while i + 2 * n <= words.count {
                    let first = words[i..<i + n]
                    let second = words[i + n..<i + 2 * n]
                    let lastOfFirst = words[i + n - 1]
                    let noPunctuation = lastOfFirst.last.map { !$0.isPunctuation } ?? true
                    if noPunctuation && zip(first, second).allSatisfy({ key($0) == key($1) }) {
                        words.removeSubrange(i + n..<i + 2 * n)
                        changed = true
                        break outer
                    }
                    i += 1
                }
            }
        }
        return words.joined(separator: " ")
    }

    /// Lowercase, no accents, no punctuation, single spaces. Used for matching only.
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
        let scalars = folded.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
        return String(scalars).split(separator: " ").joined(separator: " ")
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0 == " " || $0 == "\n" }).count
    }

    /// Splits text into sentences, keeping the punctuation.
    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let enders: Set<Character> = [".", "!", "?", "…"]
        for ch in text {
            current.append(ch)
            if enders.contains(ch) {
                let s = current.trimmingCharacters(in: .whitespaces)
                if !s.isEmpty { result.append(s) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    /// Character-level similarity 0…1 (1 = identical), based on edit distance.
    static func characterSimilarity(_ a: String, _ b: String) -> Double {
        let x = Array(a.unicodeScalars), y = Array(b.unicodeScalars)
        if x.isEmpty && y.isEmpty { return 1 }
        if x.isEmpty || y.isEmpty { return 0 }
        var prev = Array(0...y.count)
        var cur = [Int](repeating: 0, count: y.count + 1)
        for i in 1...x.count {
            cur[0] = i
            for j in 1...y.count {
                let cost = x[i - 1] == y[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        return 1 - Double(prev[y.count]) / Double(max(x.count, y.count))
    }

    /// Word-level similarity 0…1 (1 = identical), based on edit distance.
    static func similarity(_ a: [Substring], _ b: [Substring]) -> Double {
        if a.isEmpty && b.isEmpty { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            cur[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &cur)
        }
        let distance = prev[b.count]
        return 1 - Double(distance) / Double(max(a.count, b.count))
    }
}

// MARK: - Phrase assembly

/// Turns recognizer phrases into translation units: whole sentences where possible,
/// so a homily is not translated in half-sentence fragments, but never waiting too long.
struct SegmentAssembler {
    struct Unit: Sendable {
        var text: String
        var language: SpokenLanguage
        var start: TimeInterval
    }

    var minWords: Int
    var maxWords: Int
    var flushAfter: TimeInterval

    private var buffer = ""
    private var language: SpokenLanguage = .english
    private var start: TimeInterval = 0
    private var lastAdd = Date()

    static func forScene(_ scene: ListeningScene) -> SegmentAssembler {
        scene == .loudspeaker
            ? SegmentAssembler(minWords: 5, maxWords: 45, flushAfter: 1.8)
            : SegmentAssembler(minWords: 1, maxWords: 35, flushAfter: 0.7)
    }

    init(minWords: Int, maxWords: Int, flushAfter: TimeInterval) {
        self.minWords = minWords
        self.maxWords = maxWords
        self.flushAfter = flushAfter
    }

    var hasPending: Bool { !buffer.isEmpty }

    mutating func add(_ text: String, language: SpokenLanguage, start: TimeInterval) -> [Unit] {
        var out: [Unit] = []
        if !buffer.isEmpty && language != self.language, let u = flush() { out.append(u) }
        if buffer.isEmpty { self.start = start; self.language = language }
        buffer = buffer.isEmpty ? text : buffer + " " + text
        lastAdd = Date()

        // Emit every complete sentence group that is long enough.
        let parts = TextTools.sentences(buffer)
        let lastIsComplete = buffer.trimmingCharacters(in: .whitespaces).last.map { ".!?…".contains($0) } ?? false
        let complete = lastIsComplete ? parts : Array(parts.dropLast())
        let remainder = lastIsComplete ? "" : (parts.last ?? "")
        let completeText = complete.joined(separator: " ")
        if !complete.isEmpty && TextTools.wordCount(completeText) >= minWords {
            out.append(Unit(text: completeText, language: self.language, start: self.start))
            buffer = remainder
            self.start = start
        }

        // Never let a unit grow without bound (long run-on sentences in a homily).
        if TextTools.wordCount(buffer) > maxWords {
            let words = buffer.split(separator: " ")
            var cut = words.count
            for (i, w) in words.enumerated().reversed() where i > words.count / 2 {
                if w.hasSuffix(",") || w.hasSuffix(";") || w.hasSuffix(":") { cut = i + 1; break }
            }
            let head = words[0..<cut].joined(separator: " ")
            let tail = words[cut...].joined(separator: " ")
            out.append(Unit(text: head, language: self.language, start: self.start))
            buffer = tail
            self.start = start
        }
        return out
    }

    /// Emits whatever is buffered if the speaker has paused long enough.
    mutating func flushIfStale(now: Date = Date()) -> Unit? {
        guard !buffer.isEmpty, now.timeIntervalSince(lastAdd) >= flushAfter else { return nil }
        return flush()
    }

    mutating func flush() -> Unit? {
        let text = buffer.trimmingCharacters(in: .whitespaces)
        buffer = ""
        guard !text.isEmpty else { return nil }
        return Unit(text: text, language: language, start: start)
    }
}
