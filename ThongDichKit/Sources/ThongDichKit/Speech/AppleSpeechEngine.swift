import AVFoundation
import Foundation
import Speech

/// "Apple Live" engine: iOS 26 SpeechAnalyzer + SpeechTranscriber, word-by-word captions.
///
/// Strictly offline: this engine only runs if Apple's speech pack for the language is ALREADY
/// on the iPhone. The app never asks iOS to download one.
final class AppleSpeechEngine: @unchecked Sendable {
    enum EngineError: LocalizedError {
        case notInstalled
        case unsupported
        case permissionDenied
        var errorDescription: String? {
            switch self {
            case .notInstalled: return "Apple's speech pack for this language is not on this iPhone."
            case .unsupported: return "This language is not supported by Apple's on-device recognizer."
            case .permissionDenied: return "Speech recognition permission is off."
            }
        }
    }

    let language: SpokenLanguage
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzerFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private let sourceFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32, sampleRate: AudioCapture.sampleRate, channels: 1, interleaved: false)!
    private var resultsTask: Task<Void, Never>?
    private var startDate = Date()

    init(language: SpokenLanguage) {
        self.language = language
    }

    private static func candidateLocales(_ language: SpokenLanguage) -> [Locale] {
        switch language {
        case .english: return ["en-US", "en-GB", "en-AU"].map { Locale(identifier: $0) }
        case .spanish: return ["es-US", "es-MX", "es-ES"].map { Locale(identifier: $0) }
        }
    }

    /// The installed locale for this language, if Apple's pack is already on the phone (no network).
    static func installedLocale(for language: SpokenLanguage) async -> Locale? {
        let installed = await SpeechTranscriber.installedLocales
        let installedIDs = Set(installed.map { $0.identifier(.bcp47) })
        for candidate in candidateLocales(language) {
            if let supported = await SpeechTranscriber.supportedLocale(equivalentTo: candidate),
               installedIDs.contains(supported.identifier(.bcp47)) {
                return supported
            }
        }
        // Any installed variant of the language
        return installed.first { $0.language.languageCode?.identifier == language.code }
    }

    static func requestPermission() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    /// Starts the analyzer and returns the stream of recognized speech.
    func begin() async throws -> AsyncStream<SpeechEvent> {
        guard await Self.requestPermission() else { throw EngineError.permissionDenied }
        guard let locale = await Self.installedLocale(for: language) else { throw EngineError.notInstalled }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.analyzerFormat = format
        if let format, format != sourceFormat {
            converter = AVAudioConverter(from: sourceFormat, to: format)
            converter?.primeMethod = .none
        }
        startDate = Date()

        let (events, eventCont) = AsyncStream<SpeechEvent>.makeStream(bufferingPolicy: .unbounded)
        let language = self.language
        let startDate = self.startDate
        resultsTask = Task {
            var phraseStart: TimeInterval?
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if phraseStart == nil { phraseStart = Date().timeIntervalSince(startDate) }
                    if result.isFinal {
                        let cleaned = TextTools.removeEchoRepeats(text)
                        if !cleaned.isEmpty && !TextTools.isFiller(cleaned) {
                            eventCont.yield(.final(text: cleaned, language: language, start: phraseStart ?? 0))
                        }
                        eventCont.yield(.partial(""))
                        phraseStart = nil
                    } else {
                        eventCont.yield(.partial(text))
                    }
                }
            } catch {}
            eventCont.finish()
        }

        let (inputs, inputCont) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = inputCont
        try await analyzer.start(inputSequence: inputs)
        return events
    }

    /// Feeds 16 kHz mono audio.
    func feed(_ samples: [Float]) {
        guard let cont = inputContinuation, !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: AVAudioFrameCount(samples.count))
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        if let converter, let format = analyzerFormat {
            let ratio = format.sampleRate / sourceFormat.sampleRate
            let capacity = AVAudioFrameCount((Double(samples.count) * ratio).rounded(.up)) + 32
            guard let out = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
            let feeder = OneShotInput(buffer)
            var error: NSError?
            let status = converter.convert(to: out, error: &error) { _, outStatus in
                if let b = feeder.take() { outStatus.pointee = .haveData; return b }
                outStatus.pointee = .noDataNow
                return nil
            }
            guard status != .error, out.frameLength > 0 else { return }
            cont.yield(AnalyzerInput(buffer: out))
        } else {
            cont.yield(AnalyzerInput(buffer: buffer))
        }
    }

    func finish() async {
        inputContinuation?.finish()
        inputContinuation = nil
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
    }
}
