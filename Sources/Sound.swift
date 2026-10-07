import AVFoundation

/// Synthesizes simple retro sounds and music at runtime, so no audio files are needed.
final class Sound {
    static let shared = Sound()

    private enum Wave { case square, triangle, noise }

    private var effects: [String: Data] = [:]
    private var active: [AVAudioPlayer] = []
    private var music: AVAudioPlayer?
    private let musicVolume: Float = 0.5

    var isMuted = false {
        didSet { music?.volume = isMuted ? 0 : musicVolume }
    }

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)

        effects["jump"] = wav([(300, 0.04), (450, 0.04), (650, 0.07)], .square, 0.30)
        effects["coin"] = wav([(988, 0.06), (1319, 0.18)], .square, 0.25)
        effects["stomp"] = wav([(220, 0.04), (150, 0.06), (100, 0.08)], .triangle, 0.60)
        effects["die"] = wav([(500, 0.10), (400, 0.10), (300, 0.10), (200, 0.12), (120, 0.20)], .square, 0.30)
        effects["win"] = wav([(523, 0.10), (659, 0.10), (784, 0.10), (1047, 0.35)], .square, 0.30)

        let tune: [Double] = [
            523, 0, 659, 784, 659, 0, 523, 392,
            440, 0, 523, 659, 523, 0, 440, 392,
            523, 0, 659, 784, 880, 784, 659, 523,
            587, 659, 587, 523, 494, 0, 392, 0
        ]
        let melody = wav(tune.map { ($0, 0.18) }, .square, 0.10)
        music = try? AVAudioPlayer(data: melody, fileTypeHint: AVFileType.wav.rawValue)
        music?.numberOfLoops = -1
        music?.volume = musicVolume
        music?.prepareToPlay()
    }

    func play(_ name: String) {
        guard !isMuted, let data = effects[name],
              let p = try? AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue) else { return }
        active.removeAll { !$0.isPlaying }
        p.prepareToPlay()
        p.play()
        active.append(p)
    }

    func startMusic() {
        guard let m = music, !m.isPlaying else { return }
        m.volume = isMuted ? 0 : musicVolume
        m.currentTime = 0
        m.play()
    }

    func stopMusic() {
        music?.stop()
    }

    // MARK: Synthesis

    private func wav(_ notes: [(Double, Double)], _ wave: Wave, _ volume: Double) -> Data {
        let rate = 22050.0
        var samples = [Int16]()
        var phase = 0.0
        for (freq, dur) in notes {
            let n = Int(dur * rate)
            for i in 0..<n {
                let t = Double(i) / Double(max(n, 1))
                let env = min(1.0, t * 20) * (1.0 - t * 0.6)
                var v = 0.0
                if freq > 0 {
                    phase += freq / rate
                    phase -= floor(phase)
                    switch wave {
                    case .square: v = phase < 0.5 ? 1 : -1
                    case .triangle: v = 4 * abs(phase - 0.5) - 1
                    case .noise: v = Double.random(in: -1...1)
                    }
                }
                let s = max(-1.0, min(1.0, v * env * volume))
                samples.append(Int16(s * 32000))
            }
        }
        return wavData(samples, rate: Int(rate))
    }

    private func wavData(_ samples: [Int16], rate: Int) -> Data {
        var d = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; d.append(Data(bytes: &x, count: 2)) }
        let dataSize = UInt32(samples.count * 2)
        d.append("RIFF".
