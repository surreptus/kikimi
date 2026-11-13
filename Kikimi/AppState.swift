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
    /// File > Export Words to Anki… was chosen: the window asks how, and for a folder.
    var ankiExportRequested = false
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
    /// A lesson is waiting to be done, which the sidebar shows as a dot on Learn.
    private(set) var lessonsWaiting = false
    /// Bumped when the database changes under the views (imports, status changes) so they reload.
    private(set) var dataVersion = 0

    /// The message over the window, if there is one. Errors stay longer.
    private(set) var toast: Toast?
    @ObservationIgnored private var toastTimer: Task<Void, Never>?

    /// The latest thing that Edit > Undo (⌘Z) takes back, when no text field is being edited. A toast with an Undo button
    /// sets it for as long as the toast shows. A review answer sets it until the next answer or the end of the session.
    struct QuickUndo {
        let title: String
        let run: () -> Void
        let belongsToToast: Bool
    }
    private(set) var quickUndo: QuickUndo?

    /// The menu item for `quickUndo`: "Undo Review Answer", or plain "Undo" when there is none or it has no name.
    var undoMenuTitle: String {
        guard let title = quickUndo?.title, !title.isEmpty else { return String(localized: "Undo") }
        return String(localized: "Undo \(title)")
    }

    func setQuickUndo(title: String, run: @escaping () -> Void) {
        quickUndo = QuickUndo(title: title, run: run, belongsToToast: false)
    }

    /// Ends a review's quick undo. One that belongs to a toast stays until its toast goes.
    func clearReviewUndo() {
        if quickUndo?.belongsToToast == false { quickUndo = nil }
    }

    /// Runs the quick undo once, as the menu does.
    func performQuickUndo() {
        guard let undo = quickUndo else { return }
        quickUndo = nil
        undo.run()
        if undo.belongsToToast { dismissToast() }
    }

    /// `undo` puts a button on the toast, and keeps it up longer so there is time to use it. It is also the quick undo
    /// while the toast shows; `undoTitle` names it in the Edit menu.
    func showToast(_ text: String, isError: Bool = false, undo: (title: String, run: () -> Void)? = nil, undoTitle: String = "") {
        var shown = Toast(text: text, isError: isError)
        shown.action = undo
        toast = shown
        if let undo { quickUndo = QuickUndo(title: undoTitle, run: undo.run, belongsToToast: true) }
        else if quickUndo?.belongsToToast == true { quickUndo = nil }
        AccessibilityNotification.Announcement(undo == nil ? text : "\(text). \(undo!.title) is available.").post()   // VoiceOver can't see it appear
        dismissToast(after: isError || undo != nil ? 8 : 4)
    }

    func dismissToast() {
        toastTimer?.cancel()
        clearToast()
    }

    private func clearToast() {
        toast = nil
        if quickUndo?.belongsToToast == true { quickUndo = nil }
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
            if !Task.isCancelled { clearToast() }
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
    /// The Debug menu's reset, waiting for the person to confirm.
    var confirmingReset: DebugReset.Kind?
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
        StartOver.applyPending()    // first of all, before anything opens the library
        #if DEBUG
        DebugReset.applyPending()
        #endif
        languageCode = UserDefaults.standard.string(forKey: "language") ?? LanguageProfiles.all[0].code
    }

    func start() async {
        guard case .loading = phase else { return }
        do {
            let env = try LangEnvironment.standard()
            try await env.prepare()
            VoiceRecorder.removeLeftovers()   // a Shadow recording that a crash left behind
            VoiceRecorder.removeWhenQuitting()
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
        let perDay = env.dailyLessons.perDay(for: profile)
        // Reviews over the limit, or lessons off, need no look at the words.
        if perDay > 0, dueCount <= LangDatabase.lessonReviewLimit {
            let lessons = try? await env.database.dailyLessons(language: languageCode, contentPOS: profile.contentPOS, perDay: perDay)
            lessonsWaiting = lessons?.isWaiting ?? false
        } else {
            lessonsWaiting = false
        }
    }

    /// Shows the Learn page and teaches these words there, five at a time, like the day's lessons: each can be ignored or
    /// marked known as it comes, and only the ones that are taught and quizzed join your reviews.
    func learnInLessons(_ wordIDs: [Int64]) {
        pendingLesson = wordIDs
        select(.review)
    }

    /// Help > Report a Problem…: opens a new issue on GitHub in the browser with the versions filled in. Nothing is sent from here.
    func reportProblem() {
        let info = Bundle.main.infoDictionary
        let version = "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let system = "macOS \(os.majorVersion).\(os.minorVersion)"
        if let url = ProblemReport.url(app: version, system: system) { NSWorkspace.shared.open(url) }
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
