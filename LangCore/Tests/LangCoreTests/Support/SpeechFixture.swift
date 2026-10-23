import AVFoundation
import Foundation

/// A short video whose audio is real synthesized speech (macOS `say`), for end-to-end transcription tests.
enum SpeechFixture {
    static func makeVideo(at url: URL, voice: String, text: String) async throws {
        let work = FileManager.default.temporaryDirectory.appending(path: "speech-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let spoken = work.appending(path: "speech.aiff")
        let say = Process()
        say.executableURL = URL(filePath: "/usr/bin/say")
        say.arguments = ["-v", voice, "-o", spoken.path, text]
        try say.run()
        say.waitUntilExit()
        guard say.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }

        let file = try AVAudioFile(forReading: spoken)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        let rate = Int(file.processingFormat.sampleRate)
        let seconds = Int(ceil(Double(samples.count) / Double(rate))) + 1

        try await FixtureVideo.make(at: url, seconds: seconds, speech: (samples, rate))
    }
}
