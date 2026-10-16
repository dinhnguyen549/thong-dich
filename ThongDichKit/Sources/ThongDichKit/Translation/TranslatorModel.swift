import Foundation

/// The translation "brains" the app supports. All run on the iPhone GPU through MLX.
enum TranslatorModelID: String, Codable, CaseIterable, Identifiable, Sendable {
    case gemma4E2B
    case translateGemma4B
    case gemma4E4B

    var id: String { rawValue }

    /// Folder name inside `ThongDichModels/translator/` (matches the Hugging Face repo name).
    var folderName: String {
        switch self {
        case .gemma4E2B: return "gemma-4-e2b-it-4bit"
        case .translateGemma4B: return "translategemma-4b-it-4bit"
        case .gemma4E4B: return "gemma-4-e4b-it-4bit"
        }
    }

    /// Source repository (only used by the PC download script, never by the app).
    var huggingFaceRepo: String { "mlx-community/" + folderName }

    enum Kind { case instruction, translationSpecialist }

    var kind: Kind { self == .translateGemma4B ? .translationSpecialist : .instruction }

    /// End-of-turn marker of the chat format.
    var endOfTurnToken: String { self == .translateGemma4B ? "<end_of_turn>" : "<turn|>" }

    /// Approximate size on disk (GB) — shown to the user.
    var diskGB: Double {
        switch self {
        case .gemma4E2B: return 3.6
        case .translateGemma4B: return 2.2
        case .gemma4E4B: return 5.2
        }
    }

    /// Rough GPU memory needed once loaded (bytes). Vision/audio parts of the Gemma 4
    /// files are skipped at load time, so this is less than the file size.
    var estimatedMemoryBytes: Int {
        switch self {
        case .gemma4E2B: return Int(3.0 * 1_073_741_824)
        case .translateGemma4B: return Int(2.4 * 1_073_741_824)
        case .gemma4E4B: return Int(4.6 * 1_073_741_824)
        }
    }

    /// Minimum physical RAM for this model to be offered.
    var minimumDeviceRAM: UInt64 {
        switch self {
        case .gemma4E2B, .translateGemma4B: return 7_000_000_000      // 8 GB iPhones (15 Pro Max)
        case .gemma4E4B: return 11_000_000_000                         // 12 GB iPhones (iPhone Air)
        }
    }

    var displayName: String {
        switch self {
        case .gemma4E2B: return "Gemma 4 E2B"
        case .translateGemma4B: return "TranslateGemma 4B"
        case .gemma4E4B: return "Gemma 4 E4B"
        }
    }

    func subtitle(_ lang: AppLanguage) -> String {
        switch (self, lang) {
        case (.gemma4E2B, .english): return "Smart & fast. Follows Mass / Work / Everyday styles. Recommended."
        case (.gemma4E2B, .vietnamese): return "Thông minh, nhanh. Theo đúng phong cách Thánh Lễ / Công việc / Đời thường. Khuyên dùng."
        case (.translateGemma4B, .english): return "Google's translation specialist. Very literal and accurate, but ignores style instructions."
        case (.translateGemma4B, .vietnamese): return "Mô hình chuyên dịch của Google. Dịch sát nghĩa, nhưng không theo hướng dẫn phong cách."
        case (.gemma4E4B, .english): return "Highest quality. Needs 12 GB RAM (iPhone Air)."
        case (.gemma4E4B, .vietnamese): return "Chất lượng cao nhất. Cần 12 GB RAM (iPhone Air)."
        }
    }

    static var deviceRAM: UInt64 { ProcessInfo.processInfo.physicalMemory }

    /// Models that this iPhone has enough memory for.
    static var supportedOnThisDevice: [TranslatorModelID] {
        allCases.filter { deviceRAM >= $0.minimumDeviceRAM }
    }

    /// Best default for this iPhone: E4B on 12 GB phones (iPhone Air), E2B on 8 GB phones (15 Pro Max).
    static var recommendedForThisDevice: TranslatorModelID {
        deviceRAM >= gemma4E4B.minimumDeviceRAM ? .gemma4E4B : .gemma4E2B
    }
}
