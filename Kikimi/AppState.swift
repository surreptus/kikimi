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
    /// The panels over the window. They live here, not in the views, so the menu bar can open them too.
    var showAbout = false
    /// Open How it works at its keyboard list (Help > Keyboard Shortcuts) rather than at the top.
    var aboutAtKeyboard = false
    var showPrivacy = false
    var showTerms = false
    var showStorage = false
    var showAcknowledgements = false
    /// Saving and restoring progress; shared so the File menu, the Settings window and a double-clicked file all use it.
    let backup = BackupModel()
    /// Which tab the Settings window shows; set before opening it to land on one.
    var settingsTab: SettingsTab = .general
    /// Bumped to ask the main window to open the Settings window.
    private(set) var settingsRequest = 0
    /// +1 when moving down the nav list, -1 when moving up; decides which way the new screen slides in.
    private(set) var navDirection: CGFloat = 1
    /// Asked for by the menu bar; the Videos page and the Words page act on them when they show.
    var addVideosPending = false
    var findWordsPending = false
    /// Set by "Play" buttons elsewhere; the Videos screen consumes it.
    var pendingPlayback: PlaybackRequest?
    /// Words a button elsewhere (a video's "Learn N words") wants taught: the Learn page takes them and teaches them as lessons.
    var pendingLesson: [Int64] = []
    /// Where the player's back button goes: the screen that sent you to the video, or Videos if none.
    var returnSection: SidebarItem?

    // The Words page keeps its search, filter and selection while you watch a video and come back.
    var wordsSearch = ""
    var wordsFilter: WordStatus?
    var wordsTypeFilter: PartOfSpeech?
    var wordsSelection = Set<Int64>()
    private(set) var importQueue: ImportQueue?
    /// Videos chosen for import and not yet started, each with its subtitle file if it has one. Kept here so they are
    /// still waiting when you come back to the Videos page.
    var pendingImports: [PendingImport] = []
    /// Words due for review in the selected language.
    private(set) var dueCount = 0
    /// Bumped when the database changes under the views (imports, status changes) so they reload.
    private(set) var dataVersion = 0

    /// The message over the window, if there is one. Errors stay longer.
    private(set) var toast: Toast?
    @ObservationIgnored private var toastTimer: Task<Void, Never>?

    /// `undo` puts a button on the toast, and keeps it up longer so there is time to use it.
    func showToast(_ text: String, isError: Bool = false, undo: (title: String, run: () -> Void)? = nil) {
        var shown = Toast(text: text, isError: isError)
        shown.action = undo
        toast = shown
        AccessibilityNotification.Announcement(undo == nil ? text : "\(text). \(undo!.title) is available.").post()   // VoiceOver can't see it appear
        dismissToast(after: isError || undo != nil ? 8 : 4)
    }

    func dismissToast() {
        toastTimer?.cancel()
        toast = nil
    }

    /// Pointing at a toast holds it; looking away gives it two more seconds.
    func holdToast(_ hold: Bool) {
        guard toast != nil else { return }
        if hold { toastTimer?.cancel() } else { dismissToast(after: 2) }
    }

    private func dismissToast(after seconds: Double) {
        toastTimer?.cancel()
        toastTimer = Task {
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { toast = nil }
        }
    }

    var languageCode: String {
        didSet {
            UserDefaults.standard.set(languageCode, forKey: "language")
            Task { await refreshDue() }
        }
    }

    /// The languages being learned; nil until chosen on first launch.
    private(set) var learningCodes: [String]?

    /// Shown instead of the app until the person has said what they are learning.
    var needsOnboarding: Bool {
        #if DEBUG
        if previewingWelcome { return isReady }
        #endif
        return isReady && learningCodes == nil
    }

    #if DEBUG
    /// Debug menu > Show Welcome Page: the welcome page again, without touching the saved choice. Start closes it.
    var previewingWelcome = false
    #endif

    /// What the sidebar and Settings offer.
    var learning: [any LanguageProfile] {
        guard let learningCodes else { return LanguageProfiles.all }
        return LanguageProfiles.all.filter { learningCodes.contains($0.code) }
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
            VoiceRecorder.removeLeftovers()   // a Shadow recording that a crash left behind
            importQueue = ImportQueue(pipeline: env.pipeline)
            // A library from before this choice existed is already in use, so it skips the welcome.
            if env.learning.codes == nil, try await !env.database.libraryVideos().isEmpty {
                env.learning.codes = LanguageProfiles.all.map(\.code)
            }
            learningCodes = env.learning.codes
            if let learningCodes, !learningCodes.contains(languageCode) { languageCode = learningCodes[0] }
            phase = .ready(env)
            await refreshDue()
            if let url = fileWaitingForLibrary {
                fileWaitingForLibrary = nil
                handleOpen(url)
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// Saves the languages being learned, and moves to one of them if the current one was dropped.
    func setLearning(_ codes: [String]) {
        guard case .ready(let env) = phase else { return }
        #if DEBUG
        if previewingWelcome { previewingWelcome = false; return }
        #endif
        env.learning.codes = codes
        learningCodes = env.learning.codes
        if let learningCodes, !learningCodes.contains(languageCode) { languageCode = learningCodes[0] }
    }

    /// Opens the Settings window on a tab.
    func openSettings(_ tab: SettingsTab) {
        settingsTab = tab
        settingsRequest += 1   // the main window sees this and opens it (only a view can, through `openSettings`)
    }

    /// A `.kikimi` file opened from Finder or dropped on the Dock icon: show what it would restore.
    /// On a cold start the file arrives before the library has opened, so it waits until it has.
    func handleOpen(_ url: URL) {
        guard url.pathExtension == ProgressBackup.fileExtension else { return }
        guard case .ready(let env) = phase else { fileWaitingForLibrary = url; return }
        openSettings(.data)
        Task { await backup.open(url, env: env) }
    }

    private var fileWaitingForLibrary: URL?

    var isReady: Bool {
        if case .ready = phase { return true }
        return false
    }

    /// Go to a page, sliding the new one in the way you moved.
    func select(_ item: SidebarItem, reduceMotion: Bool = false) {
        guard item != section else { return }
        navDirection = item.order >= section.order ? 1 : -1
        withAnimation(Theme.screenChange(reduceMotion)) { section = item }
    }

    /// File > Add Videos…: shows the Videos page and opens the file chooser there.
    func requestAddVideos() {
        select(.videos)
        addVideosPending = true
    }

    /// Go > Find Words: shows the Words page with the search field focused.
    func requestFindWords() {
        select(.words)
        findWordsPending = true
    }

    func refreshDue() async {
        guard case .ready(let env) = phase else { return }
        dueCount = (try? await env.database.dueCount(language: languageCode)) ?? 0
    }

    /// Shows the Learn page and teaches these words there, five at a time, like the day's lessons: each can be ignored or
    /// marked known as it comes, and only the ones that are taught and quizzed join your reviews.
    func learnInLessons(_ wordIDs: [Int64]) {
        pendingLesson = wordIDs
        select(.review)
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
