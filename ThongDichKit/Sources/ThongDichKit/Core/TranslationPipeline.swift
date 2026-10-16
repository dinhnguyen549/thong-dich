import Foundation
import Observation

/// Takes recognized speech, groups it into sentences, recognizes Mass responses and prayers,
/// and feeds the rest to the translation model one unit at a time, newest text streaming in.
/// Used by both live listening and recording translation.
@MainActor
@Observable
final class TranslationPipeline {
    private(set) var lines: [TranscriptLine] = []
    var partial: String = ""

    let startDate: Date
    private(set) var settings: AppSettings
    private let scene: ListeningScene
    private let translator: LLMTranslator
    private var assembler: SegmentAssembler
    private var liturgy = LiturgyTracker()
    private var worker: Task<Void, Never>?
    private var ticker: Task<Void, Never>?

    /// Whether the GPU may be used right now (iOS forbids GPU work while the app is in the background).
    var canUseGPU: () -> Bool = { true }
    /// Whether a translation model is loaded.
    var translatorReady: () -> Bool = { true }
    /// Called whenever a line is added or finished (used for auto-saving history).
    var onChange: (() -> Void)?

    var waitingCount: Int { lines.lazy.filter { $0.status == .waiting }.count }
    var doneCount: Int { lines.lazy.filter { $0.status == .done || $0.status == .failed }.count }
    var isBusy: Bool {
        assembler.hasPending || lines.contains { $0.status == .waiting || $0.status == .translating }
    }

    init(translator: LLMTranslator, settings: AppSettings, scene: ListeningScene, startDate: Date = Date()) {
        self.translator = translator
        self.settings = settings
        self.scene = scene
        self.startDate = startDate
        self.assembler = SegmentAssembler.forScene(scene)
    }

    func start() {
        guard worker == nil else { return }
        worker = Task { [weak self] in await self?.runWorker() }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self else { return }
                if let unit = self.assembler.flushIfStale() { self.addUnit(unit) }
            }
        }
    }

    func stop() {
        worker?.cancel()
        ticker?.cancel()
        worker = nil
        ticker = nil
    }

    /// iOS does not allow GPU work in the background. Pause translating (speech recognition keeps
    /// running on the Neural Engine) and resume — catching up — when the app is back on screen.
    func setPaused(_ paused: Bool) {
        if paused {
            worker?.cancel()
            worker = nil
        } else if worker == nil && ticker != nil {
            worker = Task { [weak self] in await self?.runWorker() }
        }
    }

    /// Settings changed mid-session (e.g. pronouns or glossary edited) — applies to the next lines.
    func update(settings: AppSettings) {
        self.settings = settings
    }

    /// Restore lines (when re-opening).
    func load(lines: [TranscriptLine]) {
        self.lines = lines
    }

    // MARK: Input

    func ingest(_ event: SpeechEvent) {
        switch event {
        case .partial(let text):
            partial = text
        case .final(let text, let language, let start):
            for unit in assembler.add(text, language: language, start: start) {
                addUnit(unit)
            }
        }
    }

    /// No more speech is coming: translate whatever is left.
    func finishInput() {
        partial = ""
        if let unit = assembler.flush() { addUnit(unit) }
    }

    func waitUntilIdle() async {
        while isBusy && !Task.isCancelled {
            if !translatorReady() {
                // Nothing can translate: mark what's left so we don't wait forever.
                for i in lines.indices where lines[i].status == .waiting { lines[i].status = .failed }
                if !assembler.hasPending { break }
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    private func addUnit(_ unit: SegmentAssembler.Unit) {
        let date = startDate.addingTimeInterval(unit.start)
        func append(_ source: String, vi: String = "", kind: TranscriptLine.Kind = .speech,
                    title: String? = nil, status: TranscriptLine.Status = .waiting) {
            lines.append(TranscriptLine(
                source: source, language: unit.language, vietnamese: vi, kind: kind, title: title,
                status: status, offset: unit.start, date: date))
        }

        if settings.mode == .mass {
            var speech: [String] = []
            func flushSpeech() {
                if !speech.isEmpty { append(speech.joined(separator: " ")); speech.removeAll() }
            }
            for sentence in TextTools.sentences(unit.text) {
                switch liturgy.classify(sentence) {
                case .standard(let vi):
                    flushSpeech()
                    append(sentence, vi: vi, kind: .liturgy, status: .done)
                case .prayerStart(let prayer):
                    flushSpeech()
                    append(sentence, vi: prayer.fullVietnamese ?? "", kind: .prayer, title: prayer.title, status: .done)
                case .insidePrayer:
                    if let last = lines.indices.last, lines[last].kind == .prayer {
                        lines[last].source += " " + sentence
                    } else {
                        speech.append(sentence)
                    }
                case .speech:
                    speech.append(sentence)
                }
            }
            flushSpeech()
        } else {
            append(unit.text)
        }
        onChange?()
    }

    // MARK: Worker

    private func runWorker() async {
        while !Task.isCancelled {
            guard let index = nextIndexToTranslate() else {
                // Nothing to do: check again shortly.
                try? await Task.sleep(for: .milliseconds(120))
                continue
            }
            guard translatorReady() else {
                lines[index].status = .failed
                onChange?()
                continue
            }
            guard canUseGPU() else {
                try? await Task.sleep(for: .milliseconds(500))
                continue
            }
            await translateLine(at: index)
        }
    }

    private func nextIndexToTranslate() -> Int? {
        guard let first = lines.firstIndex(where: { $0.status == .waiting }) else { return nil }
        // If the speaker is far ahead of the translator, merge the backlog so captions catch up.
        let waiting = lines.indices.filter { lines[$0].status == .waiting && lines[$0].kind == .speech }
        if waiting.count >= 3, lines[first].kind == .speech {
            var merged = lines[first].source
            var toRemove: [UUID] = []
            for i in waiting.dropFirst() {
                guard lines[i].language == lines[first].language,
                      TextTools.wordCount(merged) + TextTools.wordCount(lines[i].source) <= 70,
                      i == first + toRemove.count + 1
                else { break }
                merged += " " + lines[i].source
                toRemove.append(lines[i].id)
            }
            if !toRemove.isEmpty {
                lines[first].source = merged
                lines.removeAll { toRemove.contains($0.id) }
            }
        }
        return first
    }

    private func translateLine(at index: Int) async {
        let id = lines[index].id
        lines[index].status = .translating
        let request = makeRequest(for: lines[index], at: index)
        let mass = settings.mode == .mass

        do {
            let result = try await translator.translate(request) { [weak self] partialText in
                await self?.setVietnamese(partialText, for: id, final: false, mass: mass)
            }
            if Task.isCancelled {
                // Interrupted (app went to the background): translate this line again later.
                if let i = lines.firstIndex(where: { $0.id == id }) {
                    lines[i].status = .waiting
                    lines[i].vietnamese = ""
                }
                return
            }
            setVietnamese(result, for: id, final: true, mass: mass)
        } catch {
            if let i = lines.firstIndex(where: { $0.id == id }) {
                lines[i].status = .failed
            }
        }
        onChange?()
    }

    private func setVietnamese(_ text: String, for id: UUID, final: Bool, mass: Bool) {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        let styled = mass ? CatholicStyle.apply(text) : text
        lines[i].vietnamese = styled
        if final { lines[i].status = styled.isEmpty ? .failed : .done }
    }

    private func makeRequest(for line: TranscriptLine, at index: Int) -> TranslationRequest {
        let context: [(String, String)] = lines[..<index]
            .filter { $0.status == .done && !$0.vietnamese.isEmpty && $0.kind != .prayer }
            .suffix(3)
            .map { ($0.source, $0.vietnamese) }
        let source = settings.mode == .mass ? BibleCitations.convert(line.source) : line.source
        return TranslationRequest(
            text: source, language: line.language, mode: settings.mode, pronouns: settings.pronouns,
            dialect: settings.dialect, workField: settings.workField, glossary: settings.glossary,
            context: context, farField: scene == .loudspeaker)
    }
}
