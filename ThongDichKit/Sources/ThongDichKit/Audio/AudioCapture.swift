import AVFoundation
import Foundation

/// Microphone capture → 16 kHz mono Float32 chunks, cleaned up by `AudioFrontEnd`.
///
/// The audio session uses the `.record` category: the app can only *listen*;
/// iOS will not let it play any sound.
final class AudioCapture {
    enum CaptureError: LocalizedError {
        case noMicrophone
        var errorDescription: String? { "No microphone input is available." }
    }

    static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private var audioContinuation: AsyncStream<[Float]>.Continuation?
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var observers: [NSObjectProtocol] = []
    private var scene: ListeningScene = .conversation
    private var mic: MicChoice = .automatic
    private(set) var inputName: String = ""

    /// Starts listening. Returns a stream of processed audio chunks and a stream of meter levels (0…1).
    func start(scene: ListeningScene, microphone: MicChoice) throws -> (audio: AsyncStream<[Float]>, levels: AsyncStream<Float>) {
        self.scene = scene
        self.mic = microphone

        let (audio, audioCont) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .unbounded)
        let (levels, levelCont) = AsyncStream<Float>.makeStream(bufferingPolicy: .bufferingNewest(1))
        audioContinuation = audioCont
        levelContinuation = levelCont

        try configureSession()
        try installTapAndStart()
        observeSystemEvents()
        return (audio, levels)
    }

    func stop() {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        observers.removeAll()
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        audioContinuation?.finish()
        levelContinuation?.finish()
        audioContinuation = nil
        levelContinuation = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    // MARK: - Session & microphone

    private func configureSession() throws {
        let session = AVAudioSession.sharedInstance()
        // .measurement = no system AGC / EQ: the most faithful signal for far-away loudspeakers.
        // .default     = iPhone's normal voice tuning, good for people close to the phone.
        let mode: AVAudioSession.Mode = scene == .loudspeaker ? .measurement : .default
        try session.setCategory(.record, mode: mode, options: [])
        try? session.setPreferredSampleRate(48_000)
        try? session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true, options: [])
        selectMicrophone(session)
    }

    /// Chooses which of the iPhone's built-in microphones to use.
    ///  • Loudspeaker: the BACK microphone, directional if possible. While you read the
    ///    screen, the back of the phone faces the altar / stage, so it points at the
    ///    loudspeaker and rejects people talking behind you.
    ///  • Conversation: the BOTTOM microphone (iPhone's main, best-quality mic), omnidirectional,
    ///    so both people around the phone are heard.
    /// A wired or USB-C microphone, when plugged in, is always respected.
    private func selectMicrophone(_ session: AVAudioSession) {
        if let current = session.currentRoute.inputs.first, current.portType != .builtInMic, mic == .automatic {
            inputName = current.portName
            return
        }
        guard let builtIn = session.availableInputs?.first(where: { $0.portType == .builtInMic }) else { return }
        try? session.setPreferredInput(builtIn)

        let wanted: AVAudioSession.Orientation
        switch mic {
        case .bottom: wanted = .bottom
        case .back: wanted = .back
        case .front: wanted = .front
        case .automatic: wanted = scene == .loudspeaker ? .back : .bottom
        }
        guard let sources = builtIn.dataSources, !sources.isEmpty else {
            inputName = builtIn.portName
            return
        }
        let source = sources.first(where: { $0.orientation == wanted })
            ?? sources.first(where: { $0.orientation == .bottom })
            ?? sources[0]
        if let patterns = source.supportedPolarPatterns {
            if scene == .loudspeaker, patterns.contains(.cardioid) {
                try? source.setPreferredPolarPattern(.cardioid)
            } else if patterns.contains(.omnidirectional) {
                try? source.setPreferredPolarPattern(.omnidirectional)
            }
        }
        try? builtIn.setPreferredDataSource(source)
        inputName = "\(builtIn.portName) – \(source.dataSourceName)"
    }

    // MARK: - Engine

    private func installTapAndStart() throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw CaptureError.noMicrophone }

        let profile: AudioFrontEnd.Profile = scene == .loudspeaker ? .loudspeaker : .conversation
        let processor = TapProcessor(inputFormat: format, profile: profile)
        let audioCont = audioContinuation
        let levelCont = levelContinuation

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            let samples = processor.process(buffer)
            guard !samples.isEmpty else { return }
            audioCont?.yield(samples)
            levelCont?.yield(processor.level)
        }
        engine.prepare()
        try engine.start()
    }

    private func observeSystemEvents() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw)
            else { return }
            if type == .ended { self.restart() }
        })
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            self?.restart()
        })
    }

    /// Re-creates the tap after a phone call, Siri, or a microphone being plugged/unplugged.
    private func restart() {
        guard audioContinuation != nil else { return }
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        selectMicrophone(AVAudioSession.sharedInstance())
        try? installTapAndStart()
    }
}

/// Runs on the real-time audio thread: converts to 16 kHz mono and cleans up.
/// Used from one thread only (the tap), hence `@unchecked Sendable`.
private final class TapProcessor: @unchecked Sendable {
    private let converter: AVAudioConverter?
    private let outputFormat: AVAudioFormat
    private var frontEnd: AudioFrontEnd
    private(set) var level: Float = 0

    init(inputFormat: AVAudioFormat, profile: AudioFrontEnd.Profile) {
        outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: AudioCapture.sampleRate,
            channels: 1, interleaved: false)!
        converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        converter?.primeMethod = .none
        frontEnd = AudioFrontEnd(profile: profile)
    }

    func process(_ buffer: AVAudioPCMBuffer) -> [Float] {
        guard let converter else { return [] }
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
        guard let out = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return [] }

        let feeder = OneShotInput(buffer)
        var error: NSError?
        let status = converter.convert(to: out, error: &error) { _, outStatus in
            if let b = feeder.take() {
                outStatus.pointee = .haveData
                return b
            }
            outStatus.pointee = .noDataNow
            return nil
        }
        guard status != .error, let channel = out.floatChannelData?[0], out.frameLength > 0 else { return [] }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        let cleaned = frontEnd.process(samples)
        level = frontEnd.lastLevel
        return cleaned
    }
}

/// Hands the source buffer to AVAudioConverter exactly once.
final class OneShotInput: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?
    init(_ buffer: AVAudioPCMBuffer) { self.buffer = buffer }
    func take() -> AVAudioPCMBuffer? {
        lock.lock(); defer { lock.unlock() }
        let b = buffer
        buffer = nil
        return b
    }
}
