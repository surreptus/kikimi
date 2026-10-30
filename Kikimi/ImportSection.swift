import LangCore
import SwiftUI
import UniformTypeIdentifiers

/// Adding videos: the speech model, the drop area and the progress of each import. It sits at the top of the Videos page.
struct ImportSection: View {
    let env: LangEnvironment
    /// Once the library has videos the drop area shrinks to one row, so the list is what the page opens on.
    var compact = false
    @Environment(AppState.self) private var app

    @State private var model = ""
    @State private var modelInstalled: Bool?
    @State private var downloadProgress: Double?
    @State private var downloadError: String?
    @State private var isTargeted = false
    @State private var showImporter = false
    /// The model choice is set once and then stays out of the way; this opens it again.
    @State private var changingModel = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var queue: ImportQueue { app.importQueue! }
    private var canImport: Bool { modelInstalled == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            modelSection
            if compact { compactDropZone } else { dropZone }
            if !queue.jobs.isEmpty { jobList }
        }
        .task(id: app.languageCode) { await loadModel() }
        .onChange(of: app.dataVersion) { Task { await refreshInstalled() } }   // e.g. a model removed in Storage
        .onChange(of: app.addVideosPending) { _, pending in if pending { openChooserIfReady() } }
        .task { if app.addVideosPending { openChooserIfReady() } }
        .onChange(of: queue.jobs.map(\.status)) { _, statuses in
            if statuses.contains(.imported) { app.dataChanged() }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.movie, .audiovisualContent],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result { start(urls) }
        }
    }

    // MARK: Model

    /// Quiet once it's ready: a single line, with the choice one click away. The full card appears only when a
    /// model has to be downloaded or you ask to change it.
    @ViewBuilder
    private var modelSection: some View {
        if modelInstalled == true, downloadProgress == nil, !changingModel {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
                Text("Speech model ready: \(modelShortName)").font(.callout).foregroundStyle(Theme.muted)
                Button("Change") { changingModel = true }
                    .buttonStyle(.plain)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Spacer()
            }
        } else {
            modelCard
        }
    }

    private var modelShortName: String {
        ModelCatalog.name(for: env.preferences.model(for: app.profile))
    }

    private var modelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Image(systemName: "waveform.and.mic").font(.system(size: 20, weight: .bold)).foregroundStyle(Theme.ink)
                Text("Speech model").font(.system(.headline, design: .rounded))
                if model.isEmpty {
                    ProgressView().controlSize(.small)   // selection not loaded yet; a Picker would warn about ""
                } else {
                    Picker("Speech model", selection: $model) {
                        ForEach(modelChoices, id: \.self) { Text(label(for: $0)).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .onChange(of: model) { _, new in
                        env.preferences.setModel(new == app.profile.defaultModel ? nil : new, for: app.profile)
                        Task { await refreshInstalled() }
                    }
                }
                Spacer()
                if let progress = downloadProgress {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView(value: progress).progressViewStyle(.thin).frame(width: 160)
                        Text("\(Int(progress * 100))%").font(Theme.small.weight(.medium)).foregroundStyle(Theme.muted)
                    }
                } else if modelInstalled == false {
                    Button("Download model\(downloadSize)") { Task { await download() } }.buttonStyle(.pill(compact: true))
                } else if modelInstalled == true {
                    Button("Done") { changingModel = false }.buttonStyle(.pill(.secondary, compact: true))
                }
            }
            if let note = ModelCatalog.info(for: model)?.note {
                Text(note).font(Theme.small).foregroundStyle(Theme.muted)
            }
            if let downloadError {
                Text(downloadError).font(Theme.small).foregroundStyle(Theme.red)
            }
        }
        .panel()
    }

    /// " (1.5 GB)": what the download costs, said on the button that starts it.
    private var downloadSize: String {
        ModelCatalog.info(for: env.preferences.model(for: app.profile))
            .map { " (" + ByteCountFormatter.string(fromByteCount: $0.downloadBytes, countStyle: .file) + ")" } ?? ""
    }

    private var modelChoices: [String] {
        let all = ModelPreferences.choices
        return all.contains(app.profile.defaultModel) ? all : [app.profile.defaultModel] + all
    }

    /// "medium · 1.5 GB (recommended)": the size, and a flag on the model suggested for this language.
    private func label(for variant: String) -> String {
        let size = ModelCatalog.info(for: variant)
            .map { " · " + ByteCountFormatter.string(fromByteCount: $0.downloadBytes, countStyle: .file) } ?? ""
        return ModelCatalog.name(for: variant) + size + (variant == app.profile.defaultModel ? String(localized: " (recommended)") : "")
    }

    private func loadModel() async {
        changingModel = false
        model = env.preferences.model(for: app.profile)
        await refreshInstalled()
    }

    /// File > Add Videos…. Without a speech model there is nothing to import into, so the page just shows the model card.
    private func openChooserIfReady() {
        app.addVideosPending = false
        if canImport { showImporter = true }
    }

    private func refreshInstalled() async {
        model = env.preferences.model(for: app.profile)   // it may have been changed in Settings
        modelInstalled = nil
        let variant = env.preferences.model(for: app.profile)
        modelInstalled = await env.models.isInstalled(variant)
    }

    private func download() async {
        let variant = env.preferences.model(for: app.profile)
        downloadError = nil
        downloadProgress = 0
        do {
            try await env.models.download(variant: variant) { p in Task { @MainActor in downloadProgress = p } }
        } catch {
            downloadError = error.localizedDescription
        }
        downloadProgress = nil
        await refreshInstalled()
        if modelInstalled == true { changingModel = false }   // done: fold the card away again
    }

    // MARK: Drop zone

    private var dropZone: some View {
        VStack(spacing: 12) {
            Text(canImport ? String(localized: "Drop \(app.profile.displayName) videos here") : String(localized: "Download the speech model to start importing"))
                .font(Theme.title(20))
            // Only worth saying when there is a choice of language to import as.
            if app.learning.count > 1 {
                Text("Importing as \(app.profile.displayName). Change the language in the sidebar.")
                    .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.ink)
            }
            Text("Your original files are never changed or deleted.")
                .font(.callout).foregroundStyle(Theme.muted)
            Button("Choose files") { showImporter = true }
                .buttonStyle(.pill)
                .disabled(!canImport)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, minHeight: 230)
        .droppable(radius: 26, targeted: isTargeted, reduceMotion: reduceMotion, onDrop: drop, isTargeted: $isTargeted)
    }

    /// The same drop target as one row, for a library that already has videos.
    private var compactDropZone: some View {
        HStack(spacing: 12) {
            Text(canImport ? String(localized: "Drop \(app.profile.displayName) videos here, or") : String(localized: "Download the speech model to start importing"))
                .foregroundStyle(Theme.muted)
            Spacer()
            Button("Add videos…") { showImporter = true }
                .buttonStyle(.pill(.secondary, compact: true))
                .disabled(!canImport)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .droppable(radius: 18, targeted: isTargeted, reduceMotion: reduceMotion, onDrop: drop, isTargeted: $isTargeted)
    }

    private func drop(_ urls: [URL]) -> Bool {
        guard canImport else { return false }
        start(urls)
        return true
    }

    private func start(_ urls: [URL]) {
        let media = urls.filter {
            UTType(filenameExtension: $0.pathExtension)?.conforms(to: .audiovisualContent) ?? false
        }
        queue.enqueue(media, profile: app.profile, model: env.preferences.model(for: app.profile), quality: env.videoQuality.quality)
    }

    // MARK: Jobs

    private var jobList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(queue.jobs) { job in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(job.fileName).font(.system(.body, design: .rounded, weight: .semibold))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        StatusPill(text: statusText(job), color: statusColor(job.status))
                        if canCancel(job.status) {
                            Button("Cancel") { queue.cancel(job.id) }.buttonStyle(.pill(.secondary, compact: true))
                                .help("Stop this import. Your original file is untouched.")
                        }
                    }
                    if case .running(let stage, let fraction) = job.status {
                        // Without a real fraction (the language check, or while the model loads) the bar moves instead
                        // of sitting empty.
                        ProgressView(value: stage.reportsProgress && job.note == nil ? fraction : nil).progressViewStyle(.thin)
                        if let detail = detailText(job) {
                            Text(detail).font(Theme.small).foregroundStyle(Theme.muted)
                        }
                    }
                    if case .failed(let message) = job.status {
                        Text(message).font(Theme.small).foregroundStyle(Theme.red)
                    }
                    if case .languageMismatch(let detected) = job.status, let other = LanguageProfiles.profile(for: detected) {
                        languagePrompt(job: job, detected: other)
                    }
                }
            }
            HStack {
                Spacer()
                Button("Clear finished") { queue.clearFinished() }
                    .buttonStyle(.pill(.secondary, compact: true))
                    .disabled(queue.isBusy && queue.jobs.count == 1)
            }
        }
        .panel()
    }

    /// Asked when the audio sounds like a different supported language than the one selected.
    private func languagePrompt(job: ImportQueue.Job, detected other: any LanguageProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This sounds like \(other.displayName), but you're importing as \(job.profile.displayName). Nothing has been imported yet.")
                .font(.callout)
            HStack(spacing: 10) {
                Button("Import as \(other.displayName)") {
                    queue.retry(job.id, as: other, model: env.preferences.model(for: other))
                }
                .buttonStyle(.pill(compact: true))
                Button("Import as \(job.profile.displayName) anyway") { queue.importAnyway(job.id) }
                    .buttonStyle(.pill(.secondary, compact: true))
                Button("Cancel") { queue.cancel(job.id) }.buttonStyle(.pill(.secondary, compact: true))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.soft))
    }

    private func statusText(_ job: ImportQueue.Job) -> String {
        switch job.status {
        case .queued: String(localized: "Waiting")
        case .running(let stage, _): runningText(stage, job)
        case .imported: String(localized: "Imported · \(job.profile.displayName)")
        case .duplicate: String(localized: "Already in library")
        case .languageMismatch: String(localized: "Check language")
        case .cancelling: String(localized: "Cancelling…")
        case .cancelled: String(localized: "Cancelled")
        case .failed: String(localized: "Failed")
        }
    }

    /// Waiting or running jobs can be cancelled; one already cancelling can't be asked twice.
    private func canCancel(_ status: ImportQueue.Status) -> Bool {
        switch status {
        case .queued, .running: true
        default: false
        }
    }

    private func statusColor(_ status: ImportQueue.Status) -> Color {
        switch status {
        case .imported: Theme.green
        case .failed: Theme.red
        case .languageMismatch, .cancelling: Theme.orange
        case .running: Theme.ink
        default: .secondary
        }
    }

    /// The line under the bar: that the model is loading (the quiet wait before anything can be measured), or how far
    /// along transcribing or compressing is, with the time left once there is enough to judge it by.
    private func detailText(_ job: ImportQueue.Job) -> String? {
        guard case .running(let stage, let fraction) = job.status else { return nil }
        if job.note == .loadingModel { return String(localized: "Loading the speech model. The first time can take a few minutes.") }
        guard stage.reportsProgress, fraction > 0 else { return nil }
        let percent = "\(Int((fraction * 100).rounded()))%"
        guard let started = job.stageStartedAt,
              let left = ProgressEstimate.secondsLeft(elapsed: Date().timeIntervalSince(started), fraction: fraction)
        else { return percent }
        return "\(percent) · \(ProgressEstimate.phrase(secondsLeft: left))"
    }

    /// "3 of 7 · Transcribing": the step's place in the import (out of 6 if the language check was skipped).
    private func runningText(_ stage: ImportStage, _ job: ImportQueue.Job) -> String {
        let place = stage.position(checkingLanguage: job.checksLanguage, compressing: job.compresses)
        return String(localized: "\(place.number) of \(place.of) · \(stageName(stage))")
    }

    private func stageName(_ stage: ImportStage) -> String {
        switch stage {
        case .hashing: String(localized: "Reading file")
        case .staging: String(localized: "Copying")
        case .detectingLanguage: String(localized: "Checking language")
        case .transcribing: String(localized: "Transcribing")
        case .transcoding: String(localized: "Compressing video")
        case .verifying: String(localized: "Verifying")
        case .saving: String(localized: "Saving")
        }
    }
}

private extension View {
    /// A dashed, tinted area that accepts dropped files and lifts slightly while one is over it (not with Reduce Motion).
    func droppable(radius: CGFloat, targeted: Bool, reduceMotion: Bool, onDrop: @escaping ([URL]) -> Bool,
                   isTargeted: Binding<Bool>) -> some View {
        self
            .background(RoundedRectangle(cornerRadius: radius).fill(targeted ? Theme.soft : Theme.soft.opacity(0.45)))
            .overlay(RoundedRectangle(cornerRadius: radius)
                .strokeBorder(Theme.ink.opacity(targeted ? 0.7 : 0.35), style: StrokeStyle(lineWidth: 1.5, dash: [8, 7])))
            .scaleEffect(targeted && !reduceMotion ? 1.01 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: targeted)
            .dropDestination(for: URL.self) { urls, _ in onDrop(urls) } isTargeted: { isTargeted.wrappedValue = $0 }
    }
}
