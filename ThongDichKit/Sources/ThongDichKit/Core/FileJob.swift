import Foundation
import Observation

/// Transcribes and translates a recorded audio/video file, entirely on the iPhone.
/// Speech recognition (Neural Engine) and translation (GPU) run side by side.
@MainActor
@Observable
final class FileJob: Identifiable {
    enum Phase: Equatable {
        case preparing
        case working
        case finishing
        case done
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let displayName: String
    let fileURL: URL
    let pipeline: TranslationPipeline
    private(set) var phase: Phase = .preparing
    private(set) var audioProgress: Double = 0
    private(set) var durationSeconds: Double = 0
    private(set) var recordID = UUID()

    var locate: (() async -> (Double, Double)?)?
    var onFinished: ((SessionRecord) -> Void)?

    private let engine: ParakeetEngine
    private let settings: AppSettings
    private let loudspeaker: Bool
    private var task: Task<Void, Never>?
    private let startedAt = Date()

    var isRunning: Bool { phase == .preparing || phase == .working || phase == .finishing }

    /// 0…1 overall: listening counts for 30 %, translating for 70 %.
    var overallProgress: Double {
        let total = max(1, pipeline.lines.count)
        let translated = Double(pipeline.doneCount) / Double(total)
        let t = pipeline.lines.isEmpty ? 0 : translated * min(1, audioProgress + 0.0001)
        return min(1, 0.3 * audioProgress + 0.7 * t)
    }

    init(fileURL: URL, displayName: String, settings: AppSettings, loudspeaker: Bool,
         translator: LLMTranslator, engine: ParakeetEngine) {
        self.fileURL = fileURL
        self.displayName = displayName
        self.settings = settings
        self.loudspeaker = loudspeaker
        self.engine = engine
        self.pipeline = TranslationPipeline(
            translator: translator, settings: settings,
            scene: loudspeaker ? .loudspeaker : .conversation, startDate: Date())
    }

    func start() {
        pipeline.start()
        task = Task { [weak self] in await self?.run() }
    }

    func cancel() {
        task?.cancel()
        pipeline.stop()
        phase = .cancelled
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func run() async {
        let reader = AudioFileReader(url: fileURL)
        do {
            try await reader.open()
        } catch {
            phase = .failed(error.localizedDescription)
            pipeline.stop()
            return
        }
        durationSeconds = reader.durationSeconds
        phase = .working

        // Where was it recorded? (from the file itself, else where the phone is now)
        var coordinates = await RecordingLocation.coordinates(of: fileURL)
        if coordinates == nil, let locate { coordinates = await locate() }

        let base: SegmentationTuning = loudspeaker ? .loudspeaker : .conversation
        let events = await engine.begin(tuning: .offline(base))
        let pipeline = self.pipeline
        let eventTask = Task { @MainActor in
            for await event in events { pipeline.ingest(event) }
        }

        // Decode + recognize off the main thread.
        let engine = self.engine
        let profile: AudioFrontEnd.Profile = loudspeaker ? .loudspeaker : .recording
        let decode = Task.detached(priority: .userInitiated) { [weak self] () -> String? in
            var frontEnd = AudioFrontEnd(profile: profile)
            var counter = 0
            do {
                while !Task.isCancelled, let chunk = try reader.next() {
                    await engine.feed(frontEnd.process(chunk.samples))
                    counter += 1
                    if counter % 16 == 0 {
                        let p = chunk.progress
                        await MainActor.run { self?.audioProgress = p }
                    }
                }
            } catch {
                return error.localizedDescription
            }
            if Task.isCancelled { reader.cancel() }
            await engine.finish()
            return nil
        }
        let decodeError = await withTaskCancellationHandler {
            await decode.value
        } onCancel: {
            decode.cancel()
        }
        await eventTask.value

        if Task.isCancelled || phase == .cancelled { return }
        if let decodeError {
            phase = .failed(decodeError)
            pipeline.stop()
            return
        }

        audioProgress = 1
        phase = .finishing
        pipeline.finishInput()
        await pipeline.waitUntilIdle()
        pipeline.stop()
        if Task.isCancelled || phase == .cancelled { return }

        var record = SessionRecord(
            id: recordID, source: .recording, fileName: displayName, mode: settings.mode,
            startedAt: startedAt, endedAt: Date())
        record.latitude = coordinates?.0
        record.longitude = coordinates?.1
        record.lines = pipeline.lines
        onFinished?(record)
        phase = .done
        try? FileManager.default.removeItem(at: fileURL)
    }
}
