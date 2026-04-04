import AVFoundation

@MainActor
class ChiptuneEngine {
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let sampleRate: Double = 44100
    private let format: AVAudioFormat

    init() {
        format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        setupEngine()
        observeAudioDeviceChanges()
    }

    private func setupEngine() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            audioEngine = engine
            playerNode = player
        } catch {
            print("ChiptuneEngine: failed to start: \(error)")
        }
    }

    private func observeAudioDeviceChanges() {
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine, queue: .main
        ) { [weak self] _ in
            self?.audioEngine?.stop()
            self?.setupEngine()
        }
    }

    enum Waveform {
        case square, triangle
    }

    func playAlert() {
        let notes: [(freq: Float, duration: Float)] = [
            (523.25, 0.08), (659.25, 0.08), (783.99, 0.12)
        ]
        play(notes: notes, waveform: .square, volume: 0.3)
    }

    func playApproved() {
        let notes: [(freq: Float, duration: Float)] = [
            (783.99, 0.06), (1046.5, 0.1)
        ]
        play(notes: notes, waveform: .triangle, volume: 0.25)
    }

    func playDenied() {
        let notes: [(freq: Float, duration: Float)] = [
            (659.25, 0.08), (261.63, 0.12)
        ]
        play(notes: notes, waveform: .square, volume: 0.25)
    }

    func playSessionDone() {
        let notes: [(freq: Float, duration: Float)] = [
            (523.25, 0.06), (659.25, 0.06), (783.99, 0.06), (1046.5, 0.15)
        ]
        play(notes: notes, waveform: .triangle, volume: 0.25)
    }

    private func play(notes: [(freq: Float, duration: Float)], waveform: Waveform, volume: Float) {
        guard let player = playerNode, let engine = audioEngine, engine.isRunning else { return }

        let totalDuration = notes.reduce(0) { $0 + $1.duration }
        let frameCount = AVAudioFrameCount(Double(totalDuration) * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return }
        buffer.frameLength = frameCount
        guard let channelData = buffer.floatChannelData?[0] else { return }

        var sampleIndex: AVAudioFrameCount = 0
        for note in notes {
            let noteSamples = AVAudioFrameCount(Double(note.duration) * sampleRate)
            for i in 0..<noteSamples {
                let t = Float(i) / Float(sampleRate)
                let phase = note.freq * t
                let sample: Float

                switch waveform {
                case .square:
                    sample = (phase.truncatingRemainder(dividingBy: 1.0) < 0.5) ? volume : -volume
                case .triangle:
                    let p = phase.truncatingRemainder(dividingBy: 1.0)
                    sample = volume * (p < 0.5 ? 4.0 * p - 1.0 : 3.0 - 4.0 * p)
                }

                let fadeLen: AVAudioFrameCount = 100
                var envelope: Float = 1.0
                if i < fadeLen { envelope = Float(i) / Float(fadeLen) }
                if i > noteSamples - fadeLen { envelope = Float(noteSamples - i) / Float(fadeLen) }

                if sampleIndex < frameCount {
                    channelData[Int(sampleIndex)] = sample * envelope
                    sampleIndex += 1
                }
            }
        }

        player.scheduleBuffer(buffer, at: nil, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}
