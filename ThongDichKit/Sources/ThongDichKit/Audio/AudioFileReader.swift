import AVFoundation
import Foundation

/// Reads the sound track of any audio or video file (m4a, mp3, wav, aiff, caf, mov, mp4…)
/// as 16 kHz mono Float32 chunks, on demand (so a 2-hour file never sits in memory).
/// Nothing is played — the audio is only decoded.
final class AudioFileReader: @unchecked Sendable {
    struct Chunk: Sendable {
        var samples: [Float]
        var progress: Double      // 0…1 of the file decoded so far
    }

    enum ReaderError: LocalizedError {
        case noAudioTrack
        case cannotRead(String)
        var errorDescription: String? {
            switch self {
            case .noAudioTrack: return "This file has no sound track."
            case .cannotRead(let why): return "Could not read this file (\(why))."
            }
        }
    }

    let url: URL
    private(set) var durationSeconds: Double = 0
    private var reader: AVAssetReader?
    private var output: AVAssetReaderAudioMixOutput?
    private var pending: [Float] = []
    private var decodedSamples = 0
    private var finished = false

    init(url: URL) { self.url = url }

    func open() async throws {
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw ReaderError.noAudioTrack }
        let d = CMTimeGetSeconds(try await asset.load(.duration))
        durationSeconds = d.isFinite ? max(0, d) : 0

        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AudioCapture.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw ReaderError.cannotRead("unsupported audio format") }
        reader.add(output)
        guard reader.startReading() else {
            throw ReaderError.cannotRead(reader.error?.localizedDescription ?? "unknown")
        }
        self.reader = reader
        self.output = output
    }

    /// Returns the next chunk, or nil at the end of the file.
    func next(chunkSize: Int = 4096) throws -> Chunk? {
        guard let output, let reader else { return nil }
        while pending.count < chunkSize && !finished {
            guard let sample = output.copyNextSampleBuffer() else {
                finished = true
                if reader.status == .failed {
                    throw ReaderError.cannotRead(reader.error?.localizedDescription ?? "decode failed")
                }
                break
            }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            let count = length / MemoryLayout<Float>.size
            guard count > 0 else { continue }
            var floats = [Float](repeating: 0, count: count)
            let status = floats.withUnsafeMutableBytes { raw -> OSStatus in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * MemoryLayout<Float>.size, destination: raw.baseAddress!)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            pending.append(contentsOf: floats)
            decodedSamples += count
        }
        if pending.isEmpty { return nil }
        let take = min(chunkSize, pending.count)
        let piece = Array(pending[0..<take])
        pending.removeFirst(take)
        let total = max(1, durationSeconds * AudioCapture.sampleRate)
        let consumed = Double(decodedSamples - pending.count)
        return Chunk(samples: piece, progress: min(1, consumed / total))
    }

    func cancel() {
        reader?.cancelReading()
        finished = true
    }
}
