import LangCore
import Observation
import SwiftUI

/// UI-level state only. Everything that does work lives in LangCore.
@MainActor @Observable
final class AppState {
    enum Phase {
        case loading
        case ready(LangEnvironment)
        case failed(String)
    }

    struct PlaybackRequest: Equatable {
        let videoID: Int64
        let time: Double
    }

    private(set) var phase: Phase = .loading
    var section: SidebarItem = .videos
    /// The "How Reprise works" panel, opened from the nav and from empty screens.
    var showAbout = false
    /// Set by "Play" buttons elsewhere; the Videos screen consumes it.
    var pendingPlayback: PlaybackRequest?
    /// Where the player's back button goes: the screen that sent you to the video, or Videos if none.
    var returnSection: SidebarItem?

    // The Words page keeps its search, filter and selection while you watch a video and come back.
    var wordsSearch = ""
    var wordsFilter: WordStatus?
    var wordsSelection = Set<Int64>()
    private(set) var importQueue: ImportQueue?
    /// Words due for review in the selected language.
    private(set) var dueCount = 0
    /// Bumped when the database changes under the views (imports, status changes) so they reload.
    private(set) var dataVersion = 0

    var languageCode: String {
        didSet {
            UserDefaults.standard.set(languageCode, forKey: "language")
            Task { await refreshDue() }
        }
    }

    var profile: any LanguageProfile {
        LanguageProfiles.profile(for: languageCode) ?? LanguageProfiles.all[0]
    }

    init() {
        languageCode = UserDefaults.standard.string(forKey: "language") ?? LanguageProfiles.all[0].code
    }

    func start() async {
        guard case .loading = phase else { return }
        do {
            let env = try LangEnvironment.standard()
            try await env.prepare()
            importQueue = ImportQueue(pipeline: env.pipeline)
            phase = .ready(env)
            await refreshDue()
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    func refreshDue() async {
        guard case .ready(let env) = phase else { return }
        dueCount = (try? await env.database.dueCount(language: languageCode)) ?? 0
    }

    func openVideo(id: Int64, at time: Double) {
        pendingPlayback = PlaybackRequest(videoID: id, time: time)
        returnSection = section == .videos ? nil : section
        withAnimation(Theme.screenChange(false)) { section = .videos }
    }

    func dataChanged() {
        dataVersion += 1
        Task { await refreshDue() }
    }
}
