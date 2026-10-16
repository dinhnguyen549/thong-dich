import Foundation

/// Light-weight clean-up applied to 16 kHz mono audio before speech recognition.
///
/// Tuned for two very different situations:
///  • conversation — voices are close and loud; just remove rumble and even out levels.
///  • loudspeaker  — a PA system heard from far away in an echoey church or hall: the
///    signal is quiet, boomy and smeared. We cut more low end (room boom, HVAC, PA hum),
///    allow much more gain, and level it so the recognizer sees a steady, healthy signal.
///
/// Deliberately no aggressive noise reduction: modern recognizers handle background
/// noise far better than they handle the artefacts that denoisers leave behind.
struct AudioFrontEnd {
    struct Profile {
        var highPassHz: Double
        var targetRMS: Float          // linear, ~ -20 dBFS
        var maxGain: Float            // linear
        var attack: Float             // gain smoothing when getting louder (0…1 per block)
        var release: Float            // gain smoothing when getting quieter

        static let conversation = Profile(highPassHz: 70, targetRMS: 0.08, maxGain: 8, attack: 0.5, release: 0.08)
        static let loudspeaker = Profile(highPassHz: 120, targetRMS: 0.1, maxGain: 32, attack: 0.35, release: 0.04)
        static let recording = Profile(highPassHz: 80, targetRMS: 0.09, maxGain: 16, attack: 0.4, release: 0.06)
    }

    private var profile: Profile
    private var hp: Biquad
    private var gain: Float = 1
    private var noiseFloor: Float = 0.002
    private(set) var lastLevel: Float = 0        // 0…1 for the on-screen meter

    init(profile: Profile, sampleRate: Double = 16_000) {
        self.profile = profile
        self.hp = Biquad.highPass(cutoff: profile.highPassHz, sampleRate: sampleRate, q: 0.707)
    }

    /// Processes one block in place and returns it.
    mutating func process(_ input: [Float]) -> [Float] {
        guard !input.isEmpty else { return input }
        var x = input
        hp.process(&x)

        // Measure block loudness
        var sum: Float = 0
        for v in x { sum += v * v }
        let rms = sqrt(sum / Float(x.count))

        // Track the background noise floor (rises slowly, falls fast)
        if rms < noiseFloor { noiseFloor = noiseFloor * 0.7 + rms * 0.3 } else { noiseFloor = noiseFloor * 0.995 + rms * 0.005 }
        noiseFloor = max(noiseFloor, 0.0003)

        // Only amplify real sound, not hiss: below 2× the noise floor, hold the gain steady.
        var desired = gain
        if rms > noiseFloor * 2 {
            desired = min(profile.maxGain, max(1, profile.targetRMS / max(rms, 1e-6)))
        }
        let k = desired < gain ? profile.attack : profile.release
        let startGain = gain
        gain += (desired - gain) * k

        // Apply gain with a per-sample ramp (no clicks) and a soft limiter
        let n = Float(x.count)
        for i in 0..<x.count {
            let g = startGain + (gain - startGain) * (Float(i) / n)
            x[i] = softLimit(x[i] * g)
        }
        lastLevel = min(1, sqrt(sum / Float(x.count)) * gain * 6)
        return x
    }

    @inline(__always) private func softLimit(_ v: Float) -> Float {
        // Transparent below 0.8, smooth saturation above.
        let a = abs(v)
        if a <= 0.8 { return v }
        let over = a - 0.8
        let limited = 0.8 + 0.2 * (over / (over + 0.2))
        return v < 0 ? -limited : limited
    }
}

/// Classic RBJ biquad filter (Direct Form I).
struct Biquad {
    var b0, b1, b2, a1, a2: Double
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    static func highPass(cutoff: Double, sampleRate: Double, q: Double) -> Biquad {
        let w0 = 2 * Double.pi * cutoff / sampleRate
        let alpha = sin(w0) / (2 * q)
        let cosw = cos(w0)
        let a0 = 1 + alpha
        return Biquad(
            b0: ((1 + cosw) / 2) / a0,
            b1: (-(1 + cosw)) / a0,
            b2: ((1 + cosw) / 2) / a0,
            a1: (-2 * cosw) / a0,
            a2: (1 - alpha) / a0)
    }

    mutating func process(_ samples: inout [Float]) {
        for i in 0..<samples.count {
            let x0 = Double(samples[i])
            let y0 = b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = x0
            y2 = y1; y1 = y0
            samples[i] = Float(y0)
        }
    }
}
