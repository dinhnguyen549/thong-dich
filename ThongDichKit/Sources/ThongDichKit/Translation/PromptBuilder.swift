import Foundation

/// One piece of speech to translate, with everything the translator needs to do it well.
struct TranslationRequest: Sendable {
    var text: String
    var language: SpokenLanguage
    var mode: TranslationMode
    var pronouns: PronounStyle
    var dialect: Dialect
    var workField: WorkField
    var glossary: [GlossaryEntry]
    /// Recent (source, Vietnamese) pairs — keeps names, terms and pronouns consistent.
    var context: [(String, String)]
    /// Text came from a loudspeaker / reverberant room: expect more recognition errors.
    var farField: Bool
}

/// Builds the instructions for the instruction-following models (Gemma 4).
/// Kept short: every token here is re-read for every sentence, so brevity = speed.
enum PromptBuilder {
    static func systemPrompt(for r: TranslationRequest) -> String {
        var p = """
        You are an expert live interpreter. Translate the speaker's words from \(r.language.englishName) into natural, fluent Vietnamese for a Vietnamese listener reading live captions.
        Rules:
        - Output ONLY the Vietnamese translation of the latest text. No notes, quotes, labels, romanization or explanations.
        - The text comes from automatic speech recognition. It may contain misheard words, missing punctuation or repeated words. Silently repair obvious errors using context and never mention them.
        - Translate the meaning, not word by word. Turn idioms into natural Vietnamese equivalents.
        - Keep people's names, places, brands and numbers accurate. Use Vietnamese number style (1.000; 3,5).
        """
        if r.farField {
            p += "\n- The audio came through a loudspeaker in an echoing room, so recognition errors are more likely: rely on context."
        }

        switch r.dialect {
        case .southern: p += "\n- Use vocabulary common in Southern Vietnam and overseas Vietnamese communities."
        case .northern: p += "\n- Use standard Northern (Hà Nội) vocabulary."
        case .neutral: break
        }

        switch r.mode {
        case .everyday:
            p += "\nSetting: an everyday spoken conversation. Use warm, natural spoken Vietnamese, not textbook style."
            if let pair = r.pronouns.pair {
                p += " The speaker refers to themself as \"\(pair.0)\" and addresses the listener as \"\(pair.1)\"."
            } else {
                p += " Choose natural Vietnamese pronouns from context; if unclear, use \"tôi\" and \"bạn\"."
            }
        case .work:
            p += "\nSetting: a professional conversation (\(workFieldDescription(r.workField))). Use polite, precise, professional Vietnamese; address people as \"anh/chị\", \"ông/bà\" or \"quý vị\" as appropriate. If a technical term has no common Vietnamese equivalent, keep the original term in parentheses after the Vietnamese."
            p += " " + workFieldRules(r.workField)
        case .mass:
            p += """

            Setting: a Catholic Mass (prayers, Bible readings, homily, announcements). Translate in reverent, dignified Catholic Vietnamese.
            Always use Vietnamese Catholic terms and spellings: Thiên Chúa, Chúa Giêsu Kitô, Đức Kitô, Chúa Thánh Thần, Đức Trinh Nữ Maria, Thánh Giuse, Phêrô, Phaolô, Gioan, Mátthêu, Máccô, Luca, Môsê, Ápraham, Đavít, Isaia, Êlia, Giêrusalem, Bêlem, Nadarét; Thánh Lễ, Thánh Thể, Mình Thánh Chúa, Máu Thánh Chúa, Tin Mừng, Lời Chúa, Hội Thánh, giáo xứ, linh mục, phó tế, giáo dân, bí tích, ân sủng, ơn cứu độ, Mùa Vọng, Mùa Chay, Phục Sinh.
            Never use Protestant forms (Giê-xu, Thánh Linh, Giăng, Phi-e-rơ, mục sư, Tin Lành, Đức Chúa Trời).
            The priest addresses the people as "anh chị em" and refers to himself as "tôi"; when people speak to God they say "Chúa" and "chúng con". Write Bible references in Vietnamese Catholic style, e.g. Ga 3,16; Mt 5,1-12.
            """
        }

        let terms = relevantGlossary(r)
        if !terms.isEmpty {
            p += "\nAlways translate these terms exactly as given: "
                + terms.map { "\"\($0.source)\" = \"\($0.vietnamese)\"" }.joined(separator: "; ") + "."
        }

        if !r.context.isEmpty {
            p += "\nRecent lines, already translated (for consistency only — do not repeat them):"
            for (src, vi) in r.context {
                p += "\n\(src) => \(vi)"
            }
        }
        return p
    }

    static func relevantGlossary(_ r: TranslationRequest) -> [GlossaryEntry] {
        let lower = r.text.lowercased()
        return r.glossary.filter {
            !$0.source.isEmpty && !$0.vietnamese.isEmpty && lower.contains($0.source.lowercased())
        }
    }

    private static func workFieldDescription(_ f: WorkField) -> String {
        switch f {
        case .business: return "business meeting"
        case .medical: return "medical visit"
        case .legal: return "legal or government office"
        case .technology: return "technology / IT"
        case .education: return "school and education"
        case .customerService: return "customer service"
        }
    }

    private static func workFieldRules(_ f: WorkField) -> String {
        switch f {
        case .business: return "Use standard Vietnamese business terminology; keep company and product names unchanged."
        case .medical: return "Use standard Vietnamese medical terminology. Keep medication names, doses, units and numbers exactly."
        case .legal: return "Use formal Vietnamese legal and administrative terminology. Keep form names, case numbers, dates and amounts exactly."
        case .technology: return "Keep software, product names and acronyms in English when Vietnamese engineers normally do."
        case .education: return "Use school vocabulary natural for Vietnamese parents and teachers (học sinh, phụ huynh, giáo viên, điểm, học kỳ)."
        case .customerService: return "Be courteous, clear and reassuring."
        }
    }

    /// For TranslateGemma (which ignores instructions): put glossary terms straight into the source.
    static func applyGlossaryToSource(_ r: TranslationRequest) -> String {
        var text = r.text
        for entry in relevantGlossary(r) {
            text = text.replacingOccurrences(of: entry.source, with: entry.vietnamese, options: [.caseInsensitive])
        }
        return text
    }

    /// Removes anything that isn't the translation itself.
    static func clean(_ raw: String) -> String {
        var text = raw
        // Stop at any leaked turn markers
        for marker in ["<turn|>", "<|turn>", "<end_of_turn>", "<start_of_turn>", "<eos>"] {
            if let r = text.range(of: marker) { text = String(text[..<r.lowerBound]) }
        }
        var lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        // Drop explanation lines the model sometimes appends
        let noteStarts = ["(lưu ý", "lưu ý:", "ghi chú", "(ghi chú", "note:", "(note", "giải thích", "(dịch", "bản dịch khác"]
        lines = lines.filter { line in
            let l = line.lowercased()
            return !noteStarts.contains { l.hasPrefix($0) }
        }
        text = lines.filter { !$0.isEmpty }.joined(separator: " ")
        // Drop leading labels
        for label in ["Bản dịch:", "Dịch:", "Tiếng Việt:", "Vietnamese:", "Translation:", "VI:"] {
            if text.hasPrefix(label) { text = String(text.dropFirst(label.count)) }
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Unwrap quotes around the whole output
        let quotePairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("«", "»"), ("'", "'")]
        for (open, close) in quotePairs where text.count > 2 && text.first == open && text.last == close {
            text = String(text.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        }
        return text
    }
}
