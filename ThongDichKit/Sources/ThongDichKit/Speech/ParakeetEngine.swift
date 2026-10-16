import CoreML
import FluidAudio
import Foundation

/// "Auto" engine: NVIDIA Parakeet Ultra (25 languages incl. English & Spanish) + Silero voice
/// detection, both on the Apple Neural Engine via FluidAudio. Loaded strictly from local files.
///
/// How it works: the voice detector finds where speech starts and stops. While someone is
/// talking, the current phrase is re-recognized about once a second for live text; when they
/// pause, the phrase is recognized one final time and sent for translation. Phrases longer
/// than the recognizer's window are cut at the quietest moment, never mid-word.
actor ParakeetEngine {
    enum EngineError: LocalizedError {
        case modelsMissing
        var errorDescription: String? { "Speech models are not installed yet." }
    }

    private let asr: AsrManager
    private let vadModel: MLModel
    private var vad: VadManager
    private var vadState = VadStreamState.initial()
    private var vadConfig = VadSegmentationConfig.default
    private var tuning = SegmentationTuning.conversation

    private var events: AsyncStream<SpeechEvent>.Continuation?
    private var pendingVAD: [Float] = []          // collects 4096-sample blocks for the detector
    private var preRoll: [Float] = []             // recent audio before speech starts
    private var segment: [Float] = []             // the phrase being spoken
    private var inSpeech = false
    private var segmentStartSample = 0
    private var totalSamples = 0
    private var samplesSincePartial = 0
    private var lastLanguage: SpokenLanguage = .english
    private var lastPartial = ""

    private static let sampleRate = 16_000

    // MARK: Loading (local files only — never downloads)

    static func load(parakeetDirectory: URL, vadModelURL: URL) async throws -> ParakeetEngine {
        let models = try AsrModels.loadLocal(from: parakeetDirectory, version: .ultra)
        let asr = AsrManager(config: .default, models: models)
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine
        let vadModel = try MLModel(contentsOf: vadModelURL, configuration: config)
        return ParakeetEngine(asr: asr, vadModel: vadModel)
    }

    private init(asr: AsrManager, vadModel: MLModel) {
        self.asr = asr
        self.vadModel = vadModel
        self.vad = VadManager(config: VadConfig(defaultThreshold: 0.5), vadModel: vadModel)
    }

    // MARK: Session

    /// Prepares for a new session and returns the stream of recognized speech.
    func begin(tuning: SegmentationTuning) -> AsyncStream<SpeechEvent> {
        self.tuning = tuning
        vad = VadManager(config: VadConfig(defaultThreshold: tuning.vadThreshold), vadModel: vadModel)
        vadState = VadStreamState.initial()
        vadConfig = VadSegmentationConfig(
            minSpeechDuration: 0.15,
            minSilenceDuration: tuning.minSilence,
            maxSpeechDuration: tuning.maxSegment + 1,
            speechPadding: 0.1)
        pendingVAD.removeAll()
        preRoll.removeAll()
        segment.removeAll()
        inSpeech = false
        totalSamples = 0
        samplesSincePartial = 0
        lastPartial = ""
        let (stream, continuation) = AsyncStream<SpeechEvent>.makeStream(bufferingPolicy: .unbounded)
        events = continuation
        return stream
    }

    /// Feeds 16 kHz mono audio (any chunk size).
    func feed(_ samples: [Float]) async {
        pendingVAD.append(contentsOf: samples)
        let block = VadManager.chunkSize
        while pendingVAD.count >= block {
            let chunk = Array(pendingVAD.prefix(block))
            pendingVAD.removeFirst(block)
            await process(chunk)
        }
    }

    /// Ends the session: recognizes whatever is still being said.
    func finish() async {
        if !pendingVAD.isEmpty {
            let rest = pendingVAD
            pendingVAD.removeAll()
            if inSpeech { segment.append(contentsOf: rest) }
            totalSamples += rest.count
        }
        if inSpeech { await finalizeSegment(upTo: segment.count) }
        inSpeech = false
        events?.finish()
        events = nil
    }

    // MARK: Core loop

    private func process(_ chunk: [Float]) async {
        let result: VadStreamResult
        do {
            result = try await vad.processStreamingChunk(chunk, state: vadState, config: vadConfig)
        } catch {
            totalSamples += chunk.count
            return
        }
        vadState = result.state

        if inSpeech {
            segment.append(contentsOf: chunk)
            samplesSincePartial += chunk.count
        } else {
            preRoll.append(contentsOf: chunk)
            let keep = Int(tuning.preRoll * Double(Self.sampleRate)) + chunk.count
            if preRoll.count > keep { preRoll.removeFirst(preRoll.count - keep) }
        }
        totalSamples += chunk.count

        if let event = result.event {
            if event.isStart && !inSpeech {
                inSpeech = true
                segment = preRoll
                segmentStartSample = max(0, totalSamples - preRoll.count)
                preRoll.removeAll()
                samplesSincePartial = 0
            } else if event.isEnd && inSpeech {
                await finalizeSegment(upTo: segment.count)
                inSpeech = false
                return
            }
        }

        guard inSpeech else { return }

        // Too long: cut at the quietest point in the last 3 seconds.
        let maxSamples = Int(tuning.maxSegment * Double(Self.sampleRate))
        if segment.count >= maxSamples {
            let cut = quietestPoint(in: segment, searchLast: 3 * Self.sampleRate)
            await finalizeSegment(upTo: cut)
            return
        }

        // Live text roughly every second.
        if tuning.partialEvery > 0, samplesSincePartial >= Int(tuning.partialEvery * Double(Self.sampleRate)) {
            samplesSincePartial = 0
            if let text = await recognize(segment), !text.isEmpty, text != lastPartial {
                lastPartial = text
                events?.yield(.partial(text))
            }
        }
    }

    /// Recognizes segment[0..<end] as a finished phrase; keeps the rest as the start of the next one.
    private func finalizeSegment(upTo end: Int) async {
        let endIndex = min(end, segment.count)
        let phrase = Array(segment[0..<endIndex])
        let startSeconds = Double(segmentStartSample) / Double(Self.sampleRate)
        let remainder = Array(segment[endIndex...])
        segmentStartSample += endIndex
        segment = remainder
        samplesSincePartial = 0
        lastPartial = ""

        guard Double(phrase.count) / Double(Self.sampleRate) >= tuning.minSegment else {
            events?.yield(.partial(""))
            return
        }
        if let text = await recognize(phrase) {
            let cleaned = TextTools.removeEchoRepeats(text)
            if !cleaned.isEmpty && !TextTools.isFiller(cleaned) {
                let language = TextTools.detectLanguage(cleaned, previous: lastLanguage)
                lastLanguage = language
                events?.yield(.final(text: cleaned, language: language, start: startSeconds))
            }
        }
        events?.yield(.partial(""))
    }

    private func recognize(_ samples: [Float]) async -> String? {
        guard !samples.isEmpty else { return nil }
        var audio = samples
        let minimum = Self.sampleRate  // recognizer wants ≥ 1 s
        if audio.count < minimum { audio.append(contentsOf: [Float](repeating: 0, count: minimum - audio.count)) }
        do {
            var state = try TdtDecoderState(decoderLayers: await asr.decoderLayerCount)
            // Script filter: keeps output in the Latin alphabet (English & Spanish), which stops
            // noisy audio from producing stray Cyrillic tokens.
            let hint: Language = lastLanguage == .spanish ? .spanish : .english
            let result = try await asr.transcribe(audio, decoderState: &state, language: hint)
            return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Index of the quietest 50 ms window within the last `searchLast` samples.
    private func quietestPoint(in samples: [Float], searchLast: Int) -> Int {
        let window = Self.sampleRate / 20
        let startSearch = max(window, samples.count - searchLast)
        var best = samples.count
        var bestEnergy = Float.greatestFiniteMagnitude
        var i = startSearch
        while i + window <= samples.count {
            var e: Float = 0
            for j in i..<(i + window) { e += samples[j] * samples[j] }
            if e < bestEnergy { bestEnergy = e; best = i + window / 2 }
            i += window / 2
        }
        return best
    }
}
