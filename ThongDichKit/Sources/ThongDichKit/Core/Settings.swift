import Foundation

// MARK: - User-facing choices

/// What kind of speech is being translated. Drives the translation style.
public enum TranslationMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case everyday, work, mass
    public var id: String { rawValue }
}

/// Where the sound comes from. Drives microphone + audio clean-up + segmentation.
enum ListeningScene: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic      // decided by the translation mode
    case conversation   // people talking near the phone
    case loudspeaker    // PA system at Mass, a talk, an event
    var id: String { rawValue }
}

/// Which speech recognizer to use.
enum EngineChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case auto        // Parakeet: detects English / Spanish by itself, fully offline
    case appleLive   // Apple SpeechTranscriber: word-by-word, fixed language, needs Apple's packs already on the phone
    var id: String { rawValue }
}

/// Spoken input languages.
enum SpokenLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case spanish = "es"
    var id: String { rawValue }
    var code: String { rawValue }
    var badge: String { rawValue.uppercased() }
    var englishName: String { self == .english ? "English" : "Spanish" }
    var vietnameseName: String { self == .english ? "tiếng Anh" : "tiếng Tây Ban Nha" }
}

/// How the speaker and the listener are addressed in Vietnamese (everyday mode).
enum PronounStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic
    case toiBan, toiAnh, toiChi, toiOng, toiBa, minhBan, emAnh, emChi, conBac
    var id: String { rawValue }

    /// (speaker says "I" as, speaker says "you" as)
    var pair: (String, String)? {
        switch self {
        case .automatic: return nil
        case .toiBan: return ("tôi", "bạn")
        case .toiAnh: return ("tôi", "anh")
        case .toiChi: return ("tôi", "chị")
        case .toiOng: return ("tôi", "ông")
        case .toiBa: return ("tôi", "bà")
        case .minhBan: return ("mình", "bạn")
        case .emAnh: return ("em", "anh")
        case .emChi: return ("em", "chị")
        case .conBac: return ("con", "bác")
        }
    }
}

enum Dialect: String, Codable, CaseIterable, Identifiable, Sendable {
    case southern, northern, neutral
    var id: String { rawValue }
}

enum WorkField: String, Codable, CaseIterable, Identifiable, Sendable {
    case business, medical, legal, technology, education, customerService
    var id: String { rawValue }
}

enum MicChoice: String, Codable, CaseIterable, Identifiable, Sendable {
    case automatic, bottom, back, front
    var id: String { rawValue }
}

enum AppLanguage: String, Codable, CaseIterable, Identifiable, Sendable {
    case vietnamese, english
    var id: String { rawValue }
}

enum Appearance: String, Codable, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
}

/// One glossary rule: whenever `source` is heard, use `vietnamese`.
struct GlossaryEntry: Codable, Identifiable, Hashable, Sendable {
    var id = UUID()
    var source: String
    var vietnamese: String
}

// MARK: - Settings bundle

struct AppSettings: Codable, Equatable, Sendable {
    var mode: TranslationMode = .everyday
    var scene: ListeningScene = .automatic
    var engine: EngineChoice = .auto
    var appleLanguage: SpokenLanguage = .english
    var translator: TranslatorModelID? = nil          // nil = recommended for this iPhone
    var pronouns: PronounStyle = .automatic
    var dialect: Dialect = .southern
    var workField: WorkField = .business
    var microphone: MicChoice = .automatic
    var glossary: [GlossaryEntry] = []
    var textScale: Double = 1.0
    var showOriginal: Bool = true
    var appLanguage: AppLanguage = Locale.preferredLanguages.first?.hasPrefix("vi") == true ? .vietnamese : .english
    var keepScreenOn: Bool = true
    var appearance: Appearance = .system
    var rememberLocation: Bool = true

    /// The listening scene actually used, after resolving "automatic".
    var effectiveScene: ListeningScene {
        switch scene {
        case .automatic: return mode == .mass ? .loudspeaker : .conversation
        default: return scene
        }
    }
}

extension AppSettings {
    // Tolerant decoding: a missing or unknown value falls back to its default,
    // so adding settings in a later version never wipes the user's choices.
    private enum CodingKeys: String, CodingKey {
        case mode, scene, engine, appleLanguage, translator, pronouns, dialect, workField
        case microphone, glossary, textScale, showOriginal, appLanguage, keepScreenOn
        case appearance, rememberLocation
    }

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        mode = value(.mode, mode)
        scene = value(.scene, scene)
        engine = value(.engine, engine)
        appleLanguage = value(.appleLanguage, appleLanguage)
        translator = (try? c.decodeIfPresent(TranslatorModelID.self, forKey: .translator)) ?? nil
        pronouns = value(.pronouns, pronouns)
        dialect = value(.dialect, dialect)
        workField = value(.workField, workField)
        microphone = value(.microphone, microphone)
        glossary = value(.glossary, glossary)
        textScale = value(.textScale, textScale)
        showOriginal = value(.showOriginal, showOriginal)
        appLanguage = value(.appLanguage, appLanguage)
        keepScreenOn = value(.keepScreenOn, keepScreenOn)
        appearance = value(.appearance, appearance)
        rememberLocation = value(.rememberLocation, rememberLocation)
    }
}

/// Persists settings in UserDefaults as one JSON blob (survives app updates and weekly re-signing).
enum SettingsStore {
    private static let key = "ThongDich.settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else { return AppSettings() }
        return decoded
    }

    static func save(_ settings: AppSettings) {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
