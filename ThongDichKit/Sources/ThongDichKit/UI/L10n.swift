import Foundation

/// Tiny two-language string helper: every label exists in English and Vietnamese.
/// Screens read `model.settings`, so they redraw in the new language when it changes.
enum L {
    nonisolated(unsafe) static var language: AppLanguage = .english

    static func t(_ en: String, _ vi: String) -> String {
        language == .vietnamese ? vi : en
    }

    static func modeName(_ m: TranslationMode) -> String {
        switch m {
        case .everyday: return t("Everyday", "Đời thường")
        case .work: return t("Work", "Công việc")
        case .mass: return t("Mass", "Thánh Lễ")
        }
    }

    static func modeIcon(_ m: TranslationMode) -> String {
        switch m {
        case .everyday: return "bubble.left.and.bubble.right.fill"
        case .work: return "briefcase.fill"
        case .mass: return "cross.fill"
        }
    }

    static func modeHint(_ m: TranslationMode) -> String {
        switch m {
        case .everyday:
            return t("Put the phone between you and the other person. English and Spanish are detected automatically.",
                     "Đặt điện thoại giữa bạn và người nói. Tự nhận biết tiếng Anh và tiếng Tây Ban Nha.")
        case .work:
            return t("Formal, precise Vietnamese. Choose your field and add special terms in Settings.",
                     "Tiếng Việt trang trọng, chính xác. Chọn lĩnh vực và thêm thuật ngữ riêng trong Cài đặt.")
        case .mass:
            return t("Hold the phone with its back toward the altar or loudspeaker. Responses and prayers use the standard Vietnamese wording.",
                     "Cầm điện thoại với mặt sau hướng về bàn thờ hoặc loa. Lời đáp và kinh dùng đúng lời chuẩn tiếng Việt.")
        }
    }

    static func sceneName(_ s: ListeningScene) -> String {
        switch s {
        case .automatic: return t("Automatic (by mode)", "Tự động (theo chế độ)")
        case .conversation: return t("1-on-1 conversation", "Trò chuyện trực tiếp")
        case .loudspeaker: return t("Loudspeaker (Mass, event)", "Qua loa (Thánh Lễ, sự kiện)")
        }
    }

    static func engineName(_ e: EngineChoice) -> String {
        switch e {
        case .auto: return t("Auto (English + Spanish)", "Tự động (Anh + Tây Ban Nha)")
        case .appleLive: return t("Apple Live (word by word)", "Apple Live (từng chữ)")
        }
    }

    static func languageName(_ l: SpokenLanguage) -> String {
        l == .english ? t("English", "Tiếng Anh") : t("Spanish", "Tiếng Tây Ban Nha")
    }

    static func pronounName(_ p: PronounStyle) -> String {
        guard let pair = p.pair else { return t("Automatic", "Tự động") }
        return "\(pair.0) – \(pair.1)"
    }

    static func dialectName(_ d: Dialect) -> String {
        switch d {
        case .southern: return t("Southern / overseas", "Miền Nam / hải ngoại")
        case .northern: return t("Northern", "Miền Bắc")
        case .neutral: return t("Neutral", "Trung tính")
        }
    }

    static func fieldName(_ f: WorkField) -> String {
        switch f {
        case .business: return t("Business", "Kinh doanh")
        case .medical: return t("Medical", "Y tế")
        case .legal: return t("Legal & government", "Pháp lý & hành chính")
        case .technology: return t("Technology", "Công nghệ")
        case .education: return t("School & education", "Trường học & giáo dục")
        case .customerService: return t("Customer service", "Chăm sóc khách hàng")
        }
    }

    static func micName(_ m: MicChoice) -> String {
        switch m {
        case .automatic: return t("Automatic", "Tự động")
        case .bottom: return t("Bottom", "Dưới")
        case .back: return t("Back (toward stage)", "Mặt sau (hướng về sân khấu)")
        case .front: return t("Front", "Mặt trước")
        }
    }

    static func appearanceName(_ a: Appearance) -> String {
        switch a {
        case .system: return t("Automatic", "Tự động")
        case .light: return t("Light", "Sáng")
        case .dark: return t("Dark", "Tối")
        }
    }

    static func dayTitle(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return t("Today", "Hôm nay") }
        if cal.isDateInYesterday(date) { return t("Yesterday", "Hôm qua") }
        let f = DateFormatter()
        f.locale = Locale(identifier: language == .vietnamese ? "vi_VN" : "en_US")
        f.setLocalizedDateFormatFromTemplate("EEEEdMMMMyyyy")
        return f.string(from: date)
    }

    static func time(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: language == .vietnamese ? "vi_VN" : "en_US")
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    static func dateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: language == .vietnamese ? "vi_VN" : "en_US")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
