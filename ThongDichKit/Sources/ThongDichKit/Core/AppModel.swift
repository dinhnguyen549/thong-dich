import AVFoundation
import CoreLocation
import Foundation
import Observation
import UIKit

/// The app's brain: owns the models, the live session, recording jobs, history and settings.
@MainActor
@Observable
public final class AppModel {
    // MARK: Settings & storage

    var settings: AppSettings {
        didSet {
            guard settings != oldValue else { return }
            SettingsStore.save(settings)
            L.language = settings.appLanguage
            pipeline?.update(settings: settings)
            if settings.translator != oldValue.translator {
                Task { await loadTranslator() }
            }
        }
    }
    let history = HistoryStore()
    private(set) var library = ModelLibrary()

    // MARK: Engines

    let translator = LLMTranslator()
    private var parakeet: ParakeetEngine?
    private let location = LocationService()

    enum LoadState: Equatable {
        case missing
        case loading
        case ready
        case failed(String)
    }
    private(set) var translatorState: LoadState = .missing
    private(set) var activeTranslator: TranslatorModelID?
    private(set) var speechState: LoadState = .missing
    private(set) var appleLiveInstalled: Set<SpokenLanguage> = []
    var importProgress: Double?

    // MARK: Live session

    enum SessionState: Equatable { case idle, starting, listening, stopping }
    private(set) var sessionState: SessionState = .idle
    private(set) var pipeline: TranslationPipeline?
    private(set) var level: Float = 0
    var errorMessage: String?
    private(set) var currentRecord: SessionRecord?
    private var capture: AudioCapture?
    private var pumpTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var levelTask: Task<Void, Never>?
    private var lastSave = Date.distantPast
    private var openRecords: [UUID: SessionRecord] = [:]   // sessions still finishing off-screen
    private(set) var isAppActive = true

    // MARK: Recordings

    private(set) var fileJob: FileJob?
    /// A recording handed to the app from another app's share sheet.
    var openedRecording: URL?

    public init() {
        let loaded = SettingsStore.load()
        settings = loaded
        L.language = loaded.appLanguage
    }

    // MARK: - Startup & models

    /// Called once when the app appears.
    func onLaunch() async {
        await installPendingPacks()
        rescanModels()
        await refreshAppleLive()
        await loadSpeech()
        await loadTranslator()
    }

    func rescanModels() {
        library = ModelLibrary.scan()
    }

    /// After the user copied or imported models.
    func reloadAll() async {
        await installPendingPacks()
        rescanModels()
        await loadSpeech()
        await loadTranslator()
    }

    /// Unpacks any .tdpack model files the user copied onto the iPhone (local only).
    func installPendingPacks() async {
        guard importProgress == nil else { return }
        let packs = ModelLibrary.pendingPacks()
        guard !packs.isEmpty else { return }
        importProgress = 0
        for (index, pack) in packs.enumerated() {
            let base = Double(index) / Double(packs.count)
            let share = 1 / Double(packs.count)
            do {
                try await Task.detached(priority: .userInitiated) {
                    try ModelLibrary.installPack(pack) { p in
                        Task { @MainActor in self.importProgress = base + p * share }
                    }
                }.value
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        importProgress = nil
    }

    /// Model packs or a models folder picked in the Files app (USB drive, iCloud Drive…).
    func importPicked(_ urls: [URL]) {
        Task {
            for url in urls {
                if url.pathExtension.lowercased() == "tdpack" {
                    importProgress = 0
                    do {
                        try await Task.detached(priority: .userInitiated) {
                            try ModelLibrary.installPack(url, deleteAfter: false) { p in
                                Task { @MainActor in self.importProgress = p }
                            }
                        }.value
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    importProgress = nil
                } else {
                    importModels(from: url)
                    while importProgress != nil { try? await Task.sleep(for: .milliseconds(300)) }
                }
            }
            await reloadAll()
        }
    }

    var needsSetup: Bool { !library.speechReady || library.translators.isEmpty }

    func loadSpeech() async {
        guard parakeet == nil else { speechState = .ready; return }
        guard let dir = library.parakeetDirectory, let vad = library.vadModelURL else {
            speechState = .missing
            return
        }
        speechState = .loading
        do {
            parakeet = try await Task.detached(priority: .userInitiated) {
                try await ParakeetEngine.load(parakeetDirectory: dir, vadModelURL: vad)
            }.value
            speechState = .ready
        } catch {
            speechState = .failed(error.localizedDescription)
        }
    }

    func loadTranslator() async {
        guard let id = library.activeTranslator(preferred: settings.translator),
              let dir = library.translators[id] else {
            translatorState = .missing
            activeTranslator = nil
            return
        }
        guard sessionState == .idle, fileJob?.isRunning != true else { return }
        translatorState = .loading
        activeTranslator = id
        do {
            try await translator.load(id, from: dir)
            translatorState = .ready
        } catch {
            // Fall back to the smaller model if the big one does not fit.
            if id == .gemma4E4B, let small = library.translators[.gemma4E2B] {
                do {
                    try await translator.load(.gemma4E2B, from: small)
                    activeTranslator = .gemma4E2B
                    translatorState = .ready
                    return
                } catch {}
            }
            translatorState = .failed(error.localizedDescription)
        }
    }

    func refreshAppleLive() async {
        var set: Set<SpokenLanguage> = []
        for lang in SpokenLanguage.allCases {
            if await AppleSpeechEngine.installedLocale(for: lang) != nil { set.insert(lang) }
        }
        appleLiveInstalled = set
    }

    func importModels(from url: URL) {
        importProgress = 0
        Task {
            do {
                try await Task.detached(priority: .userInitiated) {
                    try ModelLibrary.importFolder(url) { p in
                        Task { @MainActor in self.importProgress = p }
                    }
                }.value
                importProgress = nil
                await reloadAll()
            } catch {
                importProgress = nil
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - App lifecycle

    func setActive(_ active: Bool) {
        isAppActive = active
        pipeline?.setPaused(!active)
        fileJob?.pipeline.setPaused(!active)
        if active { rescanIfIdle() }
    }

    private func rescanIfIdle() {
        guard sessionState == .idle, fileJob?.isRunning != true else { return }
        if !ModelLibrary.pendingPacks().isEmpty {
            Task { await reloadAll() }
            return
        }
        let before = library.translators.count + (library.speechReady ? 1 : 0)
        rescanModels()
        let after = library.translators.count + (library.speechReady ? 1 : 0)
        if after != before { Task { await reloadAll() } }
    }

    func handleMemoryWarning() {
        Task { await translator.trimCaches() }
    }

    private func updateIdleTimer() {
        let busy = sessionState == .listening || sessionState == .starting || fileJob?.isRunning == true
        UIApplication.shared.isIdleTimerDisabled = busy && settings.keepScreenOn
    }

    // MARK: - Live listening

    var isListening: Bool { sessionState == .listening }

    func toggleListening() {
        switch sessionState {
        case .idle: Task { await startListening() }
        case .listening: Task { await stopListening() }
        default: break
        }
    }

    private enum ActiveEngine {
        case parakeet(ParakeetEngine)
        case apple(AppleSpeechEngine)
    }

    func startListening() async {
        guard sessionState == .idle, fileJob?.isRunning != true else { return }
        errorMessage = nil
        sessionState = .starting
        updateIdleTimer()

        guard await AVAudioApplication.requestRecordPermission() else {
            fail(L.t("Microphone access is off. Turn it on in Settings › Thông Dịch.",
                     "Micro đang tắt. Hãy bật trong Cài đặt › Thông Dịch."))
            return
        }

        // Choose the speech engine.
        let scene = settings.effectiveScene
        var engine: ActiveEngine?
        if settings.engine == .appleLive, appleLiveInstalled.contains(settings.appleLanguage) {
            engine = .apple(AppleSpeechEngine(language: settings.appleLanguage))
        } else if let parakeet {
            engine = .parakeet(parakeet)
        }
        guard let engine else {
            fail(L.t("Speech models are not installed yet. Open Setup to add them.",
                     "Chưa cài mô hình nhận giọng nói. Mở mục Cài đặt mô hình để thêm."))
            return
        }

        // Start the microphone.
        let capture = AudioCapture()
        let streams: (audio: AsyncStream<[Float]>, levels: AsyncStream<Float>)
        do {
            streams = try capture.start(scene: scene, microphone: settings.microphone)
        } catch {
            fail(error.localizedDescription)
            return
        }
        self.capture = capture

        // Connect microphone → speech engine.
        let events: AsyncStream<SpeechEvent>
        switch engine {
        case .parakeet(let p):
            let tuning: SegmentationTuning = scene == .loudspeaker ? .loudspeaker : .conversation
            events = await p.begin(tuning: tuning)
            let audio = streams.audio
            pumpTask = Task.detached(priority: .userInitiated) {
                for await chunk in audio { await p.feed(chunk) }
                await p.finish()
            }
        case .apple(let a):
            do {
                events = try await a.begin()
            } catch {
                fail(error.localizedDescription)
                return
            }
            let audio = streams.audio
            pumpTask = Task.detached(priority: .userInitiated) {
                for await chunk in audio { a.feed(chunk) }
                await a.finish()
            }
        }

        // A fresh transcript for each session (previous ones are in History).
        let pipeline = TranslationPipeline(translator: translator, settings: settings, scene: scene)
        configure(pipeline)
        self.pipeline = pipeline
        pipeline.start()

        let record = SessionRecord(source: .live, mode: settings.mode, startedAt: Date(), endedAt: Date())
        if let previous = currentRecord { openRecords[previous.id] = previous }
        currentRecord = record
        let recordID = record.id
        if settings.rememberLocation { locateCurrentSession() }

        // Speech engine → translation; when the session ends, finish translating and save.
        eventTask = Task { [weak self] in
            for await event in events { pipeline.ingest(event) }
            pipeline.finishInput()
            await pipeline.waitUntilIdle()
            self?.saveSession(pipeline, recordID: recordID, final: true)
            pipeline.stop()
        }
        let levels = streams.levels
        levelTask = Task { [weak self] in
            for await l in levels { self?.level = l }
            self?.level = 0
        }

        sessionState = .listening
        updateIdleTimer()
    }

    func stopListening() async {
        guard sessionState == .listening else { return }
        sessionState = .stopping
        capture?.stop()          // ends the audio stream → engine finishes → last phrase is translated
        capture = nil
        _ = await pumpTask?.value
        pumpTask = nil
        levelTask?.cancel()
        level = 0
        sessionState = .idle
        updateIdleTimer()
        if let pipeline, let id = currentRecord?.id { saveSession(pipeline, recordID: id, final: false) }
    }

    private func fail(_ message: String) {
        errorMessage = message
        sessionState = .idle
        capture?.stop()
        capture = nil
        updateIdleTimer()
    }

    private func configure(_ pipeline: TranslationPipeline) {
        pipeline.canUseGPU = { [weak self] in self?.isAppActive ?? false }
        pipeline.translatorReady = { [weak self] in self?.translatorState == .ready }
        pipeline.onChange = { [weak self] in self?.autosave() }
    }

    private func autosave() {
        guard Date().timeIntervalSince(lastSave) > 15, let pipeline, let id = currentRecord?.id else { return }
        saveSession(pipeline, recordID: id, final: false)
    }

    /// Writes a session to History. Safe to call for a session that is no longer on screen.
    private func saveSession(_ pipeline: TranslationPipeline, recordID: UUID, final: Bool) {
        let base: SessionRecord? = (currentRecord?.id == recordID ? currentRecord : nil)
            ?? openRecords[recordID] ?? history.record(recordID)
        guard var record = base else { return }
        record.lines = pipeline.lines.map {
            var line = $0
            if final, line.status == .translating || line.status == .waiting { line.status = .failed }
            return line
        }
        record.endedAt = max(record.startedAt, pipeline.lines.last?.date ?? Date())
        if currentRecord?.id == recordID { currentRecord = record }
        openRecords[recordID] = final ? nil : record
        history.save(record)
        lastSave = Date()
    }

    /// Clears the screen (the session is already saved in History).
    func clearTranscript() {
        guard sessionState == .idle else { return }
        // The session keeps finishing (and saving) in the background; only the screen is cleared.
        if let record = currentRecord { openRecords[record.id] = record }
        pipeline = nil
        currentRecord = nil
    }

    // MARK: - Location

    var currentPlaceName: String? { currentRecord?.placeName }
    var currentHasCoordinates: Bool { currentRecord?.latitude != nil }

    private func locateCurrentSession() {
        let recordID = currentRecord?.id
        Task {
            guard let fix = await location.currentLocation() else { return }
            guard var record = currentRecord, record.id == recordID else { return }
            record.latitude = fix.coordinate.latitude
            record.longitude = fix.coordinate.longitude
            if let place = history.place(near: fix.coordinate.latitude, fix.coordinate.longitude) {
                record.placeID = place.id
                record.placeName = place.name
            }
            currentRecord = record
            persistCurrentIfNeeded()
        }
    }

    /// Names the place of the current session (and remembers it for next time).
    func nameCurrentPlace(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, var record = currentRecord else { return }
        let place: SavedPlace
        if let lat = record.latitude, let lon = record.longitude {
            place = history.addPlace(named: trimmed, latitude: lat, longitude: lon)
        } else {
            place = history.addManualPlace(named: trimmed)
        }
        record.placeID = place.id
        record.placeName = place.name
        currentRecord = record
        persistCurrentIfNeeded()
    }

    func chooseCurrentPlace(_ place: SavedPlace?) {
        guard var record = currentRecord else { return }
        record.placeID = place?.id
        record.placeName = place?.name
        currentRecord = record
        persistCurrentIfNeeded()
    }

    private func persistCurrentIfNeeded() {
        guard let pipeline, !pipeline.lines.isEmpty, let id = currentRecord?.id else { return }
        saveSession(pipeline, recordID: id, final: false)
    }

    func refreshCurrentLocation() {
        guard currentRecord != nil else { return }
        locateCurrentSession()
    }

    // MARK: - Recordings

    func translateRecording(_ pickedURL: URL, loudspeaker: Bool) {
        guard sessionState == .idle, fileJob?.isRunning != true else { return }
        guard let parakeet else {
            errorMessage = L.t("Speech models are not installed yet.", "Chưa cài mô hình nhận giọng nói.")
            return
        }
        // Work on a private copy (the original may be in iCloud Drive or another app's folder).
        let accessing = pickedURL.startAccessingSecurityScopedResource()
        defer { if accessing { pickedURL.stopAccessingSecurityScopedResource() } }
        let temp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + pickedURL.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: pickedURL, to: temp)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        let job = FileJob(
            fileURL: temp, displayName: pickedURL.lastPathComponent, settings: settings,
            loudspeaker: loudspeaker, translator: translator, engine: parakeet)
        job.pipeline.canUseGPU = { [weak self] in self?.isAppActive ?? false }
        job.pipeline.translatorReady = { [weak self] in self?.translatorState == .ready }
        job.locate = { [weak self] in
            guard let self, self.settings.rememberLocation,
                  let fix = await self.location.currentLocation(timeout: 10) else { return nil }
            return (fix.coordinate.latitude, fix.coordinate.longitude)
        }
        job.onFinished = { [weak self] record in
            guard let self else { return }
            var r = record
            if let lat = r.latitude, let lon = r.longitude,
               let place = self.history.place(near: lat, lon) {
                r.placeID = place.id
                r.placeName = place.name
            }
            self.history.save(r)
            self.updateIdleTimer()
        }
        fileJob = job
        job.start()
        updateIdleTimer()
    }

    func dismissFileJob() {
        if fileJob?.isRunning == true { fileJob?.cancel() }
        fileJob = nil
        updateIdleTimer()
    }
}
