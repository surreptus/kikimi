import LangCore
import SwiftUI

/// The translations of one video's lines: what is kept, what is on its way, and why translating can't happen if it
/// can't. A line is fetched only when it is shown, and requests made a moment apart become one batch.
@MainActor @Observable
final class LineTranslations {
    private(set) var texts: [Int64: String] = [:]
    /// Asked for and not back yet, for the "Translating…" placeholder.
    private(set) var waiting: Set<Int64> = []
    /// Why translating can't work (a language isn't installed, say), in words for the status line.
    private(set) var problem: String?

    @ObservationIgnored private let service: TranslationService
    @ObservationIgnored private let videoID: Int64
    @ObservationIgnored private let languages: (source: String, target: String)
    @ObservationIgnored private var queue: [Subtitle] = []
    /// Lines that came back with nothing (a lone "♪"), so scrolling past them again doesn't ask again.
    @ObservationIgnored private var none: Set<Int64> = []
    @ObservationIgnored private var usable: Bool?
    @ObservationIgnored private var batching: Task<Void, Never>?

    init(service: TranslationService, videoID: Int64, source: String, target: String) {
        self.service = service
        self.videoID = videoID
        self.languages = (source, target)
    }

    /// Reads what was kept from earlier.
    func load() async {
        texts = (try? await service.stored(videoID: videoID)) ?? [:]
    }

    func need(_ line: Subtitle) {
        guard let id = line.id, texts[id] == nil, !waiting.contains(id), !none.contains(id), usable != false else { return }
        waiting.insert(id)
        queue.append(line)
        batching?.cancel()
        batching = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            await run()
        }
    }

    /// The line's text changed, so what was kept for it is out of date.
    func forget(_ id: Int64) {
        texts[id] = nil
        none.remove(id)
    }

    private func run() async {
        let batch = queue
        queue = []
        guard !batch.isEmpty else { return }
        let ids = batch.compactMap(\.id)
        defer { waiting.subtract(ids) }
        if usable == nil { usable = await checkAvailability() }
        guard usable == true else { return }
        do {
            let made = try await service.translate(batch)
            texts.merge(made) { _, new in new }
            none.formUnion(ids.filter { made[$0] == nil })
        } catch {
            problem = String(localized: "Couldn't translate: \(error.localizedDescription)")
        }
    }

    private func checkAvailability() async -> Bool {
        let source = name(languages.source), target = name(languages.target)
        switch await service.availability() {
        case .ready:
            return true
        case .needsDownload:
            problem = String(localized: "Translating from \(source) to \(target) needs a language download. Add it in System Settings > General > Language & Region > Translation Languages.")
        case .unavailable:
            problem = String(localized: "macOS can't translate from \(source) to \(target).")
        }
        return false
    }

    private func name(_ code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}
