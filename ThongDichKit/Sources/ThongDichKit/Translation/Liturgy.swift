import Foundation

// MARK: - Fixed parts of the Mass

/// The fixed dialogues of the Mass with the wording used in Vietnamese parishes.
/// When one of these is recognized (even with an echo-garbled word or two), the standard
/// Vietnamese response is shown instantly instead of being re-translated.
enum MassPhrasebook {
    struct Entry {
        let variants: [String]    // English and Spanish forms
        let vietnamese: String
        fileprivate var normalizedVariants: [String] = []
    }

    static let entries: [Entry] = build([
        (["In the name of the Father, and of the Son, and of the Holy Spirit",
          "En el nombre del Padre, y del Hijo, y del Espíritu Santo"],
         "Nhân danh Cha và Con và Thánh Thần."),
        (["The grace of our Lord Jesus Christ, and the love of God, and the communion of the Holy Spirit be with you all",
          "La gracia de nuestro Señor Jesucristo, el amor del Padre y la comunión del Espíritu Santo estén con todos ustedes",
          "La gracia de nuestro Señor Jesucristo, el amor del Padre y la comunión del Espíritu Santo estén con todos vosotros"],
         "Ân sủng của Đức Giêsu Kitô Chúa chúng ta, tình thương của Chúa Cha và ơn thông hiệp của Chúa Thánh Thần ở cùng tất cả anh chị em."),
        (["The Lord be with you", "El Señor esté con ustedes", "El Señor esté con vosotros"],
         "Chúa ở cùng anh chị em."),
        (["And with your spirit", "Y con tu espíritu"],
         "Và ở cùng cha."),
        (["Peace be with you", "La paz esté con ustedes", "La paz esté con vosotros"],
         "Bình an của Chúa ở cùng anh chị em."),
        (["Brethren, let us acknowledge our sins, and so prepare ourselves to celebrate the sacred mysteries",
          "Hermanos, para celebrar dignamente estos sagrados misterios, reconozcamos nuestros pecados"],
         "Anh chị em thân mến, để xứng đáng cử hành các mầu nhiệm thánh, chúng ta hãy nhận mình là tội nhân."),
        (["May almighty God have mercy on us, forgive us our sins, and bring us to everlasting life",
          "Dios todopoderoso tenga misericordia de nosotros, perdone nuestros pecados y nos lleve a la vida eterna"],
         "Xin Thiên Chúa toàn năng thương xót, tha tội và dẫn đưa chúng ta đến sự sống đời đời."),
        (["Lord, have mercy", "Señor, ten piedad"], "Xin Chúa thương xót chúng con."),
        (["Christ, have mercy", "Cristo, ten piedad"], "Xin Chúa Kitô thương xót chúng con."),
        (["Let us pray", "Oremos"], "Chúng ta cầu nguyện."),
        (["Through Christ our Lord", "Por Jesucristo, nuestro Señor", "Por Cristo, nuestro Señor"],
         "Nhờ Đức Kitô, Chúa chúng con."),
        (["The word of the Lord", "Palabra de Dios"], "Đó là Lời Chúa."),
        (["Thanks be to God", "Te alabamos, Señor", "Demos gracias a Dios"], "Tạ ơn Chúa."),
        (["The Gospel of the Lord", "Palabra del Señor"], "Đó là Lời Chúa."),
        (["Praise to you, Lord Jesus Christ", "Gloria a ti, Señor Jesús"], "Lạy Chúa Kitô, ngợi khen Chúa."),
        (["Glory to you, O Lord", "Glory to you, Lord", "Gloria a ti, Señor"], "Lạy Chúa, vinh danh Chúa."),
        (["Alleluia", "Aleluya"], "Alleluia."),
        (["Let us pray to the Lord", "Roguemos al Señor"], "Chúng ta hãy cầu xin Chúa."),
        (["Lord, hear our prayer", "Te rogamos, óyenos", "Te rogamos, Señor"], "Xin Chúa nhậm lời chúng con."),
        (["Blessed be God for ever", "Bendito seas por siempre, Señor"], "Chúc tụng Thiên Chúa đến muôn đời."),
        (["Pray, brethren, that my sacrifice and yours may be acceptable to God, the almighty Father",
          "Oren, hermanos, para que este sacrificio, mío y de ustedes, sea agradable a Dios, Padre todopoderoso",
          "Orad, hermanos, para que este sacrificio, mío y vuestro, sea agradable a Dios, Padre todopoderoso"],
         "Anh chị em hãy cầu nguyện để hy lễ của tôi cũng là của anh chị em được đẹp lòng Thiên Chúa là Cha toàn năng."),
        (["May the Lord accept the sacrifice at your hands for the praise and glory of his name, for our good and the good of all his holy Church",
          "El Señor reciba de tus manos este sacrificio, para alabanza y gloria de su nombre, para nuestro bien y el de toda su santa Iglesia"],
         "Xin Chúa nhận hy lễ nơi tay cha, để ca ngợi và tôn vinh danh Chúa, cũng để mưu ích cho chúng con và toàn thể Hội Thánh."),
        (["Lift up your hearts", "Levantemos el corazón"], "Hãy nâng tâm hồn lên."),
        (["We lift them up to the Lord", "Lo tenemos levantado hacia el Señor"], "Chúng con đang hướng về Chúa."),
        (["Let us give thanks to the Lord our God", "Demos gracias al Señor, nuestro Dios"],
         "Hãy tạ ơn Chúa là Thiên Chúa chúng ta."),
        (["It is right and just", "Es justo y necesario"], "Thật là chính đáng."),
        (["Hosanna in the highest", "Hosanna en el cielo"], "Hoan hô trên các tầng trời."),
        (["The mystery of faith", "Let us proclaim the mystery of faith",
          "Este es el sacramento de nuestra fe", "Este es el misterio de la fe"],
         "Đây là mầu nhiệm đức tin."),
        (["We proclaim your Death, O Lord, and profess your Resurrection until you come again",
          "Anunciamos tu muerte, proclamamos tu resurrección, ven, Señor Jesús"],
         "Lạy Chúa, chúng con loan truyền việc Chúa chịu chết và tuyên xưng việc Chúa sống lại, cho tới khi Chúa đến."),
        (["For the kingdom, the power and the glory are yours, now and for ever",
          "Tuyo es el reino, tuyo el poder y la gloria, por siempre, Señor"],
         "Vì Chúa là Vua uy quyền và vinh hiển muôn đời."),
        (["The peace of the Lord be with you always", "La paz del Señor esté siempre con ustedes",
          "La paz del Señor esté siempre con vosotros"],
         "Bình an của Chúa luôn ở cùng anh chị em."),
        (["Let us offer each other the sign of peace", "Dense fraternalmente la paz", "Démonos fraternalmente la paz",
          "Daos fraternalmente la paz"],
         "Anh chị em hãy chúc bình an cho nhau."),
        (["Behold the Lamb of God, behold him who takes away the sins of the world. Blessed are those called to the supper of the Lamb",
          "Este es el Cordero de Dios, que quita el pecado del mundo. Dichosos los invitados a la cena del Señor"],
         "Đây Chiên Thiên Chúa, đây Đấng xóa tội trần gian. Phúc cho ai được mời đến dự tiệc Chiên Thiên Chúa."),
        (["Lord, I am not worthy that you should enter under my roof, but only say the word and my soul shall be healed",
          "Señor, no soy digno de que entres en mi casa, pero una palabra tuya bastará para sanarme"],
         "Lạy Chúa, con chẳng đáng Chúa ngự vào nhà con, nhưng xin Chúa phán một lời thì linh hồn con sẽ lành mạnh."),
        (["The Body of Christ", "El Cuerpo de Cristo"], "Mình Thánh Chúa Kitô."),
        (["The Blood of Christ", "La Sangre de Cristo"], "Máu Thánh Chúa Kitô."),
        (["Bow down for the blessing", "Inclínense para recibir la bendición"],
         "Anh chị em hãy cúi đầu nhận lãnh phúc lành."),
        (["May almighty God bless you, the Father, and the Son, and the Holy Spirit",
          "La bendición de Dios todopoderoso, Padre, Hijo y Espíritu Santo, descienda sobre ustedes",
          "La bendición de Dios todopoderoso, Padre, Hijo y Espíritu Santo, descienda sobre vosotros"],
         "Xin Thiên Chúa toàn năng là Cha và Con và Thánh Thần ban phúc lành cho anh chị em."),
        (["Go forth, the Mass is ended", "Go in peace", "Go and announce the Gospel of the Lord",
          "Go in peace, glorifying the Lord by your life", "Pueden ir en paz", "Podéis ir en paz",
          "La misa ha terminado, pueden ir en paz"],
         "Lễ xong, chúc anh chị em đi bình an."),
        (["Amen", "Amén"], "Amen."),
    ])

    private static func build(_ raw: [([String], String)]) -> [Entry] {
        raw.map { variants, vi in
            var e = Entry(variants: variants, vietnamese: vi)
            e.normalizedVariants = variants.map { TextTools.normalize($0) }
            return e
        }
    }

    private static let gospelNames: [String: String] = [
        "matthew": "Mátthêu", "mateo": "Mátthêu", "mark": "Máccô", "marcos": "Máccô",
        "luke": "Luca", "lucas": "Luca", "john": "Gioan", "juan": "Gioan",
    ]

    /// Returns the standard Vietnamese wording if this sentence is a fixed part of the Mass.
    static func match(_ sentence: String) -> String? {
        let normalized = TextTools.normalize(sentence)
        let words = normalized.split(separator: " ")
        guard !words.isEmpty else { return nil }

        // Gospel announcement: "A reading from the holy Gospel according to Luke" / "Lectura del santo Evangelio según san Lucas"
        if normalized.contains("gospel according to") || normalized.contains("evangelio segun") {
            if let name = words.last.map(String.init), let vi = gospelNames[name] {
                return "Tin Mừng Chúa Giêsu Kitô theo thánh \(vi)."
            }
        }

        // Character-level similarity: tolerant of small mishearings ("and with you spirit")
        // but not of different words ("and with your help").
        var best: (score: Double, vi: String)?
        for entry in entries {
            for variant in entry.normalizedVariants {
                let a = variant.count, b = normalized.count
                guard abs(a - b) <= max(3, a / 4) else { continue }
                let needed: Double
                switch a {
                case 0...12: needed = 0.999       // "amen", "let us pray": exact
                case 13...30: needed = 0.86
                default: needed = 0.88
                }
                let score = TextTools.characterSimilarity(normalized, variant)
                if score >= needed, score > (best?.score ?? 0) {
                    best = (score, entry.vietnamese)
                }
            }
        }
        return best?.vi
    }
}

// MARK: - Prayers said together

/// Prayers the congregation recites from memory. Vietnamese Catholics know them by heart,
/// so the app shows the prayer's name (and the full traditional text for the two oldest
/// prayers) instead of a word-by-word machine translation, and quietly collects the
/// following lines while the prayer is being recited.
struct Prayer: Sendable {
    let key: String
    let title: String                 // Vietnamese name
    let openings: [String]            // how it starts, English & Spanish
    let fullVietnamese: String?
    let duration: TimeInterval        // how long to keep collecting lines
    let words: Set<String>            // vocabulary of the prayer (EN + ES), for recognizing its lines

    static let all: [Prayer] = [
        Prayer(
            key: "ourFather", title: "Kinh Lạy Cha",
            openings: ["our father who art in heaven", "our father which art in heaven",
                       "padre nuestro que estas en el cielo", "padre nuestro que estas en los cielos"],
            fullVietnamese: "Lạy Cha chúng con ở trên trời, chúng con nguyện danh Cha cả sáng, nước Cha trị đến, ý Cha thể hiện dưới đất cũng như trên trời. Xin Cha cho chúng con hôm nay lương thực hằng ngày, và tha nợ chúng con như chúng con cũng tha kẻ có nợ chúng con. Xin chớ để chúng con sa chước cám dỗ, nhưng cứu chúng con cho khỏi sự dữ.",
            duration: 45,
            words: bag("our father who art in heaven hallowed be thy name kingdom come will done on earth as it is give us this day daily bread and forgive trespasses those trespass against lead not into temptation but deliver from evil amen padre nuestro que estas en el cielo santificado sea tu nombre venga a nosotros reino hagase voluntad la tierra como danos hoy pan de cada dia perdona nuestras ofensas tambien perdonamos los nos ofenden no dejes caer tentacion y libranos del mal amen")),
        Prayer(
            key: "hailMary", title: "Kinh Kính Mừng",
            openings: ["hail mary full of grace", "dios te salve maria llena eres de gracia"],
            fullVietnamese: "Kính mừng Maria đầy ơn phúc, Đức Chúa Trời ở cùng Bà, Bà có phúc lạ hơn mọi người nữ, và Giêsu con lòng Bà gồm phúc lạ. Thánh Maria, Đức Mẹ Chúa Trời, cầu cho chúng con là kẻ có tội, khi nay và trong giờ lâm tử.",
            duration: 35,
            words: bag("hail mary full of grace the lord is with thee blessed art thou among women and blessed is fruit thy womb jesus holy mother god pray for us sinners now at hour our death amen dios te salve maria llena eres de gracia el senor contigo bendita tu entre todas las mujeres y bendito fruto vientre jesus santa madre ruega por nosotros pecadores ahora en la hora nuestra muerte amen")),
        Prayer(
            key: "gloria", title: "Kinh Vinh Danh",
            openings: ["glory to god in the highest", "gloria a dios en el cielo", "gloria a dios en las alturas"],
            fullVietnamese: nil, duration: 110,
            words: bag("glory to god in the highest and on earth peace people of good will we praise you bless adore glorify give thanks for your great lord heavenly king o almighty father only begotten son jesus christ lamb who take away sins world have mercy us receive our prayer seated at right hand alone are holy most high with spirit amen gloria a dios en el cielo y la tierra paz los hombres que ama senor te alabamos bendecimos adoramos glorificamos damos gracias por tu inmensa rey celestial padre todopoderoso hijo unico jesucristo cordero quitas pecado del mundo ten piedad de nosotros atiende nuestra suplica estas sentado derecha solo santo altisimo con espiritu amen")),
        Prayer(
            key: "creed", title: "Kinh Tin Kính",
            openings: ["i believe in one god", "i believe in god the father almighty", "we believe in one god",
                       "creo en un solo dios", "creo en dios padre todopoderoso"],
            fullVietnamese: nil, duration: 160,
            words: bag("i believe in one god the father almighty maker of heaven and earth all things visible invisible lord jesus christ only begotten son born before ages from light true not made consubstantial with through whom were for us men our salvation he came down by power holy spirit was incarnate virgin mary became man crucified under pontius pilate suffered death buried rose again third day accordance scriptures ascended into is seated at right hand will come glory to judge living dead his kingdom have no end giver life who proceeds adored glorified has spoken prophets catholic apostolic church confess baptism forgiveness sins look forward resurrection world amen creo en un solo dios padre todopoderoso creador del cielo y la tierra de todo lo visible invisible senor jesucristo hijo unico nacido antes los siglos luz verdadero engendrado no creado misma naturaleza que por quien todo fue hecho nosotros hombres nuestra salvacion bajo obra espiritu santo se encarno maria virgen hizo hombre causa crucificado poncio pilato padecio sepultado resucito tercer dia segun escrituras subio esta sentado derecha vendra con gloria para juzgar vivos muertos su reino tendra fin dador vida procede adoracion gloria hablo profetas iglesia una catolica apostolica confieso bautismo perdon pecados espero resurreccion muertos mundo futuro amen")),
        Prayer(
            key: "sanctus", title: "Kinh Thánh Thánh Thánh",
            openings: ["holy holy holy lord god of hosts", "santo santo santo es el senor"],
            fullVietnamese: nil, duration: 40,
            words: bag("holy lord god of hosts heaven and earth are full your glory hosanna in the highest blessed is he who comes name santo es el senor dios del universo llenos estan cielo y la tierra de tu gloria hosanna en bendito que viene nombre")),
        Prayer(
            key: "agnus", title: "Kinh Lạy Chiên Thiên Chúa",
            openings: ["lamb of god you take away the sins of the world", "cordero de dios que quitas el pecado del mundo"],
            fullVietnamese: nil, duration: 45,
            words: bag("lamb of god you take away the sins world have mercy on us grant peace cordero de dios que quitas el pecado del mundo ten piedad nosotros danos la paz")),
        Prayer(
            key: "confiteor", title: "Kinh Cáo Mình",
            openings: ["i confess to almighty god", "yo confieso ante dios todopoderoso"],
            fullVietnamese: nil, duration: 55,
            words: bag("i confess to almighty god and you my brothers sisters that have greatly sinned in thoughts words what done failed do through fault most grievous therefore ask blessed mary ever virgin all angels saints pray for me the lord our yo confieso ante dios todopoderoso ante ustedes hermanos que he pecado mucho de pensamiento palabra obra omision por mi culpa grande culpa por eso ruego santa maria siempre virgen los angeles santos a ustedes que intercedan por mi nuestro senor")),
    ]

    private static func bag(_ text: String) -> Set<String> {
        Set(text.split(separator: " ").map(String.init))
    }

    /// The prayer this sentence starts, if any.
    static func starting(_ sentence: String) -> Prayer? {
        let normalized = TextTools.normalize(sentence)
        let words = normalized.split(separator: " ")
        for prayer in all {
            for opening in prayer.openings {
                let o = opening.split(separator: " ")
                let head = Array(words.prefix(o.count + 1))
                if normalized.hasPrefix(opening) || TextTools.similarity(Array(head.prefix(o.count)), o) >= 0.75 {
                    return prayer
                }
            }
        }
        return nil
    }

    /// True if this sentence looks like it is part of the prayer's text.
    func contains(_ sentence: String) -> Bool {
        let w = TextTools.normalize(sentence).split(separator: " ").map(String.init)
        guard !w.isEmpty else { return true }
        let hits = w.filter { words.contains($0) }.count
        return Double(hits) / Double(w.count) >= 0.75
    }
}

/// Remembers which prayer is being recited.
struct LiturgyTracker {
    enum Result {
        case standard(String)          // fixed response → Vietnamese wording
        case prayerStart(Prayer)
        case insidePrayer
        case speech                     // ordinary speech → translate with the LLM
    }

    private(set) var activePrayer: Prayer?
    private var prayerStarted = Date.distantPast

    mutating func classify(_ sentence: String, now: Date = Date()) -> Result {
        if let p = activePrayer {
            if now.timeIntervalSince(prayerStarted) < p.duration, p.contains(sentence) {
                return .insidePrayer
            }
            activePrayer = nil
        }
        if let prayer = Prayer.starting(sentence) {
            activePrayer = prayer
            prayerStarted = now
            return .prayerStart(prayer)
        }
        if let vi = MassPhrasebook.match(sentence) { return .standard(vi) }
        return .speech
    }

    mutating func reset() { activePrayer = nil }
}

// MARK: - Catholic Vietnamese style

enum CatholicStyle {
    /// Replaces Protestant / secular spellings with the forms used in Vietnamese Catholic churches.
    private static let replacements: [(String, String)] = [
        ("Giăng Báp-tít", "Gioan Tẩy Giả"), ("Giăng Báptít", "Gioan Tẩy Giả"),
        ("Đức Thánh Linh", "Chúa Thánh Thần"), ("Thánh Linh", "Thánh Thần"),
        ("Đức Chúa Jêsus Christ", "Đức Giêsu Kitô"), ("Chúa Jêsus Christ", "Chúa Giêsu Kitô"),
        ("Jêsus Christ", "Giêsu Kitô"), ("Jesus Christ", "Giêsu Kitô"), ("Chúa Cơ Đốc", "Chúa Kitô"),
        ("Đấng Christ", "Đức Kitô"), ("Đấng Cơ Đốc", "Đức Kitô"), ("Đấng Kitô", "Đức Kitô"),
        ("Giê-xu", "Giêsu"), ("Giê-su", "Giêsu"), ("Giêxu", "Giêsu"), ("Jêsus", "Giêsu"), ("Jesus", "Giêsu"),
        ("Cơ Đốc", "Kitô"), ("Christ", "Kitô"),
        ("Ma-ri-a", "Maria"), ("Ma-ri", "Maria"), ("Mary", "Maria"),
        ("Giô-sép", "Giuse"), ("Phi-e-rơ", "Phêrô"), ("Phao-lô", "Phaolô"), ("Giăng", "Gioan"),
        ("Ma-thi-ơ", "Mátthêu"), ("Lu-ca", "Luca"), ("Môi-se", "Môsê"), ("Áp-ra-ham", "Ápraham"),
        ("Đa-vít", "Đavít"), ("Ê-sai", "Isaia"), ("Ê-li", "Êlia"), ("Giê-ru-sa-lem", "Giêrusalem"),
        ("Bết-lê-hem", "Bêlem"), ("Na-xa-rét", "Nadarét"), ("Ga-li-lê", "Galilê"),
        ("Tiệc Thánh", "Thánh Thể"), ("mục sư", "linh mục"), ("Mục sư", "Linh mục"),
        ("Đức Chúa Trời", "Thiên Chúa"), ("Thượng Đế", "Thiên Chúa"), ("Tin Lành", "Tin Mừng"),
    ]

    private static let compiled: [(NSRegularExpression, String)] = replacements.compactMap { from, to in
        let pattern = "(?<![\\p{L}\\-])" + NSRegularExpression.escapedPattern(for: from) + "(?![\\p{L}\\-])"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        return (re, NSRegularExpression.escapedTemplate(for: to))
    }

    static func apply(_ text: String) -> String {
        var result = text
        for (re, template) in compiled {
            let range = NSRange(result.startIndex..., in: result)
            result = re.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return BibleCitations.convert(result)
    }
}

// MARK: - Bible citations

/// "John 3:16" / "Juan 3, 16" → "Ga 3,16" (Vietnamese Catholic abbreviations).
enum BibleCitations {
    private static let books: [(names: [String], abbr: String)] = [
        (["Genesis", "Génesis", "Sáng Thế Ký", "Sáng thế ký"], "St"), (["Exodus", "Éxodo", "Xuất Ê-díp-tô Ký"], "Xh"),
        (["Leviticus", "Levítico"], "Lv"), (["Numbers", "Números"], "Ds"), (["Deuteronomy", "Deuteronomio"], "Đnl"),
        (["Joshua", "Josué"], "Gs"), (["Judges", "Jueces"], "Tl"), (["Ruth", "Rut"], "R"),
        (["Samuel"], "Sm"), (["Kings", "Reyes"], "V"), (["Isaiah", "Isaías", "Ê-sai"], "Is"),
        (["Jeremiah", "Jeremías"], "Gr"), (["Ezekiel", "Ezequiel"], "Ed"), (["Daniel"], "Đn"),
        (["Hosea", "Oseas"], "Hs"), (["Joel"], "Ge"), (["Amos", "Amós"], "Am"), (["Jonah", "Jonás"], "Gn"),
        (["Micah", "Miqueas"], "Mk"), (["Zephaniah", "Sofonías"], "Xp"), (["Zechariah", "Zacarías"], "Dcr"),
        (["Malachi", "Malaquías"], "Ml"), (["Psalms", "Psalm", "Salmos", "Salmo", "Thi Thiên"], "Tv"),
        (["Proverbs", "Proverbios"], "Cn"), (["Wisdom", "Sabiduría"], "Kn"),
        (["Sirach", "Ecclesiasticus", "Eclesiástico"], "Hc"), (["Job"], "G"),
        (["Matthew", "Mateo", "Ma-thi-ơ", "Mátthêu"], "Mt"), (["Mark", "Marcos", "Máccô"], "Mc"),
        (["Luke", "Lucas", "Lu-ca", "Luca"], "Lc"), (["John", "Juan", "Giăng", "Gioan"], "Ga"),
        (["Acts", "Hechos", "Công Vụ"], "Cv"), (["Romans", "Romanos", "Rô-ma"], "Rm"),
        (["Corinthians", "Corintios", "Cô-rinh-tô"], "Cr"), (["Galatians", "Gálatas"], "Gl"),
        (["Ephesians", "Efesios"], "Ep"), (["Philippians", "Filipenses"], "Pl"), (["Colossians", "Colosenses"], "Cl"),
        (["Thessalonians", "Tesalonicenses"], "Tx"), (["Timothy", "Timoteo"], "Tm"), (["Titus", "Tito"], "Tt"),
        (["Hebrews", "Hebreos", "Hê-bơ-rơ"], "Dt"), (["James", "Santiago", "Gia-cơ"], "Gc"),
        (["Peter", "Pedro", "Phi-e-rơ"], "Pr"), (["Revelation", "Apocalipsis", "Khải Huyền"], "Kh"),
    ]

    private static let regex: NSRegularExpression? = {
        let names = books.flatMap { $0.names }.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let pattern = "(?<![\\p{L}])(?:([123])\\s*)?(" + names + ")\\s+(\\d{1,3})\\s*[:,.]\\s*(\\d{1,3})(?:\\s*[-–]\\s*(\\d{1,3}))?"
        return try? NSRegularExpression(pattern: pattern)
    }()

    private static func abbreviation(for name: String) -> String? {
        books.first { $0.names.contains { $0.caseInsensitiveCompare(name) == .orderedSame } }?.abbr
    }

    static func convert(_ text: String) -> String {
        guard let regex else { return text }
        let ns = text as NSString
        var result = ""
        var last = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            func group(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            guard let name = group(2), let abbr = abbreviation(for: name),
                  let chapter = group(3), let verse = group(4) else { continue }
            result += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            var citation = ""
            if let n = group(1) { citation += n + " " }
            citation += "\(abbr) \(chapter),\(verse)"
            if let end = group(5) { citation += "-\(end)" }
            result += citation
            last = m.range.location + m.range.length
        }
        result += ns.substring(from: last)
        return result
    }
}
