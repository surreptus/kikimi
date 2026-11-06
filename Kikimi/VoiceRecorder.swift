import AVFoundation
import Observation

/// Records the learner saying a sentence, for the Shadow card, so it can be played beside the original. The recording is
/// a temporary file that exists only while the card does: `discard()` deletes it, and anything left by a crash is
/// deleted when the app next opens (`removeLeftovers`). Nothing is uploaded, transcribed or analysed.
@MainActor @Observable
final class VoiceRecorder: NSObject, AVAudioPlayerDelegate {
    enum State: Equatable { case idle, recording, recorded, denied, failed }

    private(set) var state: State = .idle
    private(set) var isPlaying = false
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var file: URL?
    private var limit: Task<Void, Never>?

    nonisolated private static var folder: URL { FileManager.default.temporaryDirectory.appending(path: "Kikimi-Shadow", directoryHint: .isDirectory) }

    /// Deletes recordings a crash left behind. Call once at launch.
    nonisolated static func removeLeftovers() { try? FileManager.default.removeItem(at: folder) }

    /// Starts recording, asking for the microphone the first time. Stops by itself after `seconds`, so a forgotten
    /// recording can't run on.
    func start(maxSeconds seconds: Double) async {
        discard()
        guard await Self.allowed() else { state = .denied; return }
        do {
            try FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
            let url = Self.folder.appending(path: "\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else { state = .failed; return }
            self.recorder = recorder
            file = url
            state = .recording
            limit = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                if !Task.isCancelled { self?.stop() }
            }
        } catch { state = .failed }
    }

    func stop() {
        limit?.cancel(); limit = nil
        recorder?.stop(); recorder = nil
        if state == .recording { state = file == nil ? .failed : .recorded }
    }

    /// Plays what was recorded, or stops it.
    func togglePlayback() {
        if isPlaying { player?.stop(); isPlaying = false; return }
        guard state == .recorded, let file, let player = try? AVAudioPlayer(contentsOf: file) else { return }
        player.delegate = self
        self.player = player
        isPlaying = player.play()
    }

    /// Stops everything and deletes the recording.
    func discard() {
        limit?.cancel(); limit = nil
        recorder?.stop(); recorder = nil
        player?.stop(); player = nil
        isPlaying = false
        if let file { try? FileManager.default.removeItem(at: file) }
        file = nil
        if state != .denied { state = .idle }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.isPlaying = false }
    }

    private static func allowed() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: true
        case .denied: false
        default: await AVAudioApplication.requestRecordPermission()
        }
    }
}
